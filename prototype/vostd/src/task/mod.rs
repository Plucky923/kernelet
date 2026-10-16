// SPDX-License-Identifier: MPL-2.0

//! Tasks are the unit of code execution.
//!
//! Ported from real OSTD at `ab9a4cfdc`. A task is OSTD's own object with its own
//! kernelet stack, multiplexed onto the sandbox's virtual CPUs by whatever
//! [`scheduler::Scheduler`] the kernel proper injects. The host schedules the N
//! vCPU carriers and never sees a kernelet task.

pub mod atomic_mode;
mod kernel_stack;
pub(crate) mod preempt;
mod processor;
pub mod scheduler;
mod utils;

use core::{
    any::Any,
    borrow::Borrow,
    cell::{Cell, SyncUnsafeCell},
    ops::Deref,
    ptr::NonNull,
    sync::atomic::AtomicBool,
};

use kernel_stack::KernelStack;
use processor::current_task;
use utils::ForceSync;

pub use self::{
    preempt::{disable_preempt, halt_cpu, DisabledPreemptGuard},
    scheduler::info::{AtomicCpuId, TaskScheduleInfo},
};
use crate::{arch::task::TaskContext, irq::DisabledLocalIrqGuard, prelude::*, utils::Once};

static PRE_SCHEDULE_HANDLER: Once<fn(&DisabledLocalIrqGuard)> = Once::new();
static POST_SCHEDULE_HANDLER: Once<fn()> = Once::new();

/// Injects a handler to be executed before scheduling.
pub fn inject_pre_schedule_handler(handler: fn(&DisabledLocalIrqGuard)) {
    PRE_SCHEDULE_HANDLER.call_once(|| handler);
}

/// Injects a handler to be executed after scheduling.
pub fn inject_post_schedule_handler(handler: fn()) {
    POST_SCHEDULE_HANDLER.call_once(|| handler);
}

/// A task that executes a function to the end.
#[derive(Debug)]
pub struct Task {
    #[allow(clippy::type_complexity)]
    func: ForceSync<Cell<Option<Box<dyn FnOnce() + Send>>>>,

    data: Box<dyn Any + Send + Sync>,
    local_data: ForceSync<Box<dyn Any + Send>>,

    ctx: SyncUnsafeCell<TaskContext>,
    kstack: KernelStack,

    /// Whether this task has been switched to on a virtual CPU.
    ///
    /// This is what enforces the one invariant OSTD does not delegate: a task
    /// must not run on more than one CPU at a time.
    switched_to_cpu: AtomicBool,

    schedule_info: TaskScheduleInfo,
}

impl Task {
    /// Gets the current task.
    ///
    /// Returns `None` in the bootstrap context.
    pub fn current() -> Option<CurrentTask> {
        let current_task = current_task()?;

        // SAFETY: `current_task` is the current task.
        Some(unsafe { CurrentTask::new(current_task) })
    }

    pub(crate) fn ctx(&self) -> &SyncUnsafeCell<TaskContext> {
        &self.ctx
    }

    /// Returns whether we need to yield execution to another task.
    pub fn need_yield() -> bool {
        preempt::cpu_local::need_preempt()
    }

    /// Yields execution so that another task may be scheduled.
    #[track_caller]
    pub fn yield_now() {
        scheduler::yield_now()
    }

    /// Kicks the task scheduler to run the task.
    #[track_caller]
    pub fn run(self: &Arc<Self>) {
        scheduler::run_new_task(self.clone());
    }

    /// Returns the task data.
    #[allow(clippy::borrowed_box)]
    pub fn data(&self) -> &Box<dyn Any + Send + Sync> {
        &self.data
    }

    /// Gets the attached scheduling information.
    pub fn schedule_info(&self) -> &TaskScheduleInfo {
        &self.schedule_info
    }
}

/// Options to create or spawn a new task.
pub struct TaskOptions {
    func: Option<Box<dyn FnOnce() + Send>>,
    data: Option<Box<dyn Any + Send + Sync>>,
    local_data: Option<Box<dyn Any + Send>>,
}

impl TaskOptions {
    /// Creates a set of options for a task.
    pub fn new<F>(func: F) -> Self
    where
        F: FnOnce() + Send + 'static,
    {
        Self {
            func: Some(Box::new(func)),
            data: None,
            local_data: None,
        }
    }

    /// Sets the function that represents the entry point of the task.
    pub fn func<F>(mut self, func: F) -> Self
    where
        F: Fn() + Send + 'static,
    {
        self.func = Some(Box::new(func));
        self
    }

    /// Sets the data associated with the task.
    pub fn data<T>(mut self, data: T) -> Self
    where
        T: Any + Send + Sync,
    {
        self.data = Some(Box::new(data));
        self
    }

    /// Sets the local data associated with the task.
    pub fn local_data<T>(mut self, data: T) -> Self
    where
        T: Any + Send,
    {
        self.local_data = Some(Box::new(data));
        self
    }

    /// Builds a new task without running it immediately.
    pub fn build(self) -> Result<Task> {
        // All tasks enter this function, which is meant to execute the task's
        // function. `switch.S` provides an assembly wrapper for it as the end of
        // the call stack, so its name must not be mangled.
        //
        // # Safety
        //
        // Must be called from `switch.S` with the context prepared correctly.
        #[no_mangle]
        unsafe extern "C" fn kernel_task_entry() -> ! {
            // SAFETY: the new task is switched to for the first time, so
            // `after_switching_to` has not been called yet.
            unsafe { processor::after_switching_to() };

            let current_task = Task::current()
                .expect("no current task, it should have current task in kernel task entry");

            // SAFETY: `func` is only accessed by the current task in the task
            // context, so it is not accessed concurrently.
            let task_func = unsafe { current_task.func.get() };
            let task_func = task_func
                .take()
                .expect("task function is `None` when trying to run");
            task_func();

            scheduler::exit_current();
        }

        let kstack = KernelStack::new_with_guard_page()?;

        let mut ctx = TaskContext::new();
        ctx.set_instruction_pointer(
            crate::arch::task::kernel_task_entry_wrapper as *const () as usize,
        );
        // Reserve space for the return address, or the context switch writes
        // across the page boundary. The System V AMD64 ABI wants 16-byte
        // alignment and `kernel_task_entry` takes no arguments.
        ctx.set_stack_pointer(kstack.end_vaddr() - 16);

        let new_task = Task {
            func: ForceSync::new(Cell::new(self.func)),
            data: self.data.unwrap_or_else(|| Box::new(())),
            local_data: ForceSync::new(self.local_data.unwrap_or_else(|| Box::new(()))),
            ctx: SyncUnsafeCell::new(ctx),
            kstack,
            switched_to_cpu: AtomicBool::new(false),
            schedule_info: TaskScheduleInfo {
                cpu: AtomicCpuId::default(),
            },
        };

        Ok(new_task)
    }

    /// Builds a new task and runs it immediately.
    #[track_caller]
    pub fn spawn(self) -> Result<Arc<Task>> {
        let task = Arc::new(self.build()?);
        task.run();
        Ok(task)
    }
}

/// The current task.
///
/// Not `Send`, so it cannot outlive the current task; not `Sync`, so it can give
/// access to the local data of the current task.
#[derive(Debug)]
pub struct CurrentTask(NonNull<Task>);

impl !Send for CurrentTask {}
impl !Sync for CurrentTask {}

impl CurrentTask {
    /// # Safety
    ///
    /// The caller must ensure that `task` is the current task.
    unsafe fn new(task: NonNull<Task>) -> Self {
        Self(task)
    }

    /// Returns the local data of the current task.
    ///
    /// # Panics
    ///
    /// Panics if called in a non-task context.
    pub fn local_data(&self) -> &(dyn Any + Send) {
        assert!(crate::irq::InterruptLevel::current().is_task_context());

        let local_data = &self.local_data;

        // SAFETY: only the current task in the task context accesses this.
        &**unsafe { local_data.get() }
    }

    /// Returns a cloned `Arc<Task>`.
    pub fn cloned(&self) -> Arc<Task> {
        let ptr = self.0.as_ptr();

        // SAFETY: the current task is always a valid task held in an `Arc`.
        unsafe { Arc::increment_strong_count(ptr) };

        // SAFETY: the count was just increased.
        unsafe { Arc::from_raw(ptr) }
    }
}

impl Deref for CurrentTask {
    type Target = Task;

    fn deref(&self) -> &Self::Target {
        // SAFETY: the current task is always a valid task.
        unsafe { self.0.as_ref() }
    }
}

impl AsRef<Task> for CurrentTask {
    fn as_ref(&self) -> &Task {
        self
    }
}

impl Borrow<Task> for CurrentTask {
    fn borrow(&self) -> &Task {
        self
    }
}

/// A trait that provides methods to manipulate the task context.
pub(crate) trait TaskContextApi {
    /// Sets the instruction pointer.
    fn set_instruction_pointer(&mut self, ip: usize);

    /// Sets the stack pointer.
    fn set_stack_pointer(&mut self, sp: usize);
}
