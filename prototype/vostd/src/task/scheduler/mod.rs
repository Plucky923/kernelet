// SPDX-License-Identifier: MPL-2.0

//! Task scheduling.
//!
//! Ported from real OSTD's `task/scheduler/mod.rs` at `ab9a4cfdc`. The traits,
//! their method signatures, the four scheduling events and the contract between
//! OSTD and an injected scheduler are unchanged, so a kernel proper's scheduler
//! compiles against either. The differences, all in the parts OSTD does not show
//! its client:
//!
//! - **Cross-CPU preemption** is a KICK virtual interrupt through the endovisor's
//!   `vcpu_kick` service instead of an inter-processor call, because a virtual
//!   CPU is a host task and may not be on a processor at all.
//! - **Idling.** Real OSTD spins in `reschedule`'s retry loop until a task turns
//!   up, and expects the kernel proper to have injected a per-CPU idle task. A
//!   virtual CPU must not spin: it would burn the sandbox's share of a real
//!   processor for nothing. So the retry loop spins a little and then calls the
//!   `vcpu_idle` service, which sleeps the carrier in the host until a virtual
//!   interrupt arrives. This is the one addition to OSTD's own logic in this file.
//!
//! # Scheduler injection
//!
//! To avoid code bloat and offer flexibility, OSTD does not include a
//! one-size-fits-all task scheduler. Instead the client kernel implements the
//! [`Scheduler`] trait in safe Rust and registers it with [`inject_scheduler`],
//! as early as possible during initialization, before any [`Task`]-related API is
//! used.
//!
//! # Safety impact
//!
//! While OSTD delegates scheduling decisions to the injected scheduler, it
//! enforces one invariant itself: a task must not be scheduled to run on more
//! than one CPU at a time. See [`super::processor::switch_to_task`].

mod fifo_scheduler;
pub mod info;

use crate::{
    cpu::{CpuId, PinCurrentCpu},
    prelude::*,
    task::{disable_preempt, preempt::cpu_local, processor, Task},
    timer,
    utils::Once,
};

/// How long a virtual CPU with nothing to run spins before it tells the host.
const IDLE_SPINS: u32 = 64;

/// Injects a custom implementation of task scheduler into OSTD.
///
/// # Panics
///
/// Panics if a scheduler has already been injected, either explicitly or
/// implicitly via the lazy default FIFO scheduler.
pub fn inject_scheduler(scheduler: &'static dyn Scheduler<Task>) {
    let mut is_new = false;
    SCHEDULER.call_once(|| {
        is_new = true;
        scheduler
    });
    assert!(is_new, "a scheduler has already been initialized");
}

/// Enables preemptive scheduling on the current CPU.
///
/// Should be called once on every CPU during initialization, after
/// [`inject_scheduler`].
pub fn enable_preemption_on_cpu() {
    timer::register_callback_on_cpu(|| {
        scheduler_singleton().mut_local_rq_with(&mut |local_rq| {
            let should_pick_next = local_rq.update_current(UpdateFlags::Tick);
            if should_pick_next {
                cpu_local::set_need_preempt();
            }
        })
    });
}

/// The global scheduler singleton.
static SCHEDULER: Once<&'static dyn Scheduler<Task>> = Once::new();

/// Returns the global scheduler, falling back to a default FIFO scheduler.
fn scheduler_singleton() -> &'static dyn Scheduler<Task> {
    *SCHEDULER.call_once(|| fifo_scheduler::new_instance())
}

/// An SMP-aware task scheduler.
pub trait Scheduler<T = Task>: Sync + Send {
    /// Enqueues a runnable task.
    ///
    /// The newly-enqueued task may have a higher priority than the currently
    /// running one on a CPU and thus should preempt the latter. In that case this
    /// method returns the ID of that CPU.
    fn enqueue(&self, runnable: Arc<T>, flags: EnqueueFlags) -> Option<CpuId>;

    /// Gets an immutable access to the local runqueue of the current CPU.
    fn local_rq_with(&self, f: &mut dyn FnMut(&dyn LocalRunQueue<T>));

    /// Gets a mutable access to the local runqueue of the current CPU.
    fn mut_local_rq_with(&self, f: &mut dyn FnMut(&mut dyn LocalRunQueue<T>));
}

/// A per-CPU, local runqueue.
///
/// A local runqueue is consulted by OSTD in response to one of four scheduling
/// events: **yielding**, **sleeping**, **ticking** and **exiting**. The general
/// workflow is: take exclusive access with [`Scheduler::mut_local_rq_with`], call
/// [`LocalRunQueue::update_current`], call [`LocalRunQueue::dequeue_current`] if
/// the task is about to sleep or exit, and call [`LocalRunQueue::pick_next`] if
/// `update_current` returned true.
pub trait LocalRunQueue<T = Task> {
    /// Gets the current runnable task.
    fn current(&self) -> Option<&Arc<T>>;

    /// Updates the current runnable task's scheduling statistics and potentially
    /// its position in the runqueue.
    ///
    /// The return value indicates whether `pick_next` should follow.
    #[must_use]
    fn update_current(&mut self, flags: UpdateFlags) -> bool;

    /// Picks the next runnable task.
    ///
    /// # Panics
    ///
    /// Only invoked by OSTD after `update_current` returned true; an implementer
    /// is free to panic if that contract is broken.
    fn pick_next(&mut self) -> &Arc<T> {
        self.try_pick_next().unwrap()
    }

    /// Tries to pick the next runnable task.
    fn try_pick_next(&mut self) -> Option<&Arc<T>>;

    /// Removes the current runnable task from the runqueue and returns it.
    fn dequeue_current(&mut self) -> Option<Arc<T>>;
}

/// Possible triggers of an `enqueue` action.
#[derive(Clone, Copy, PartialEq)]
pub enum EnqueueFlags {
    /// Spawn a new task.
    Spawn,
    /// Wake a sleeping task.
    Wake,
}

/// Possible triggers of an `update_current` action.
#[derive(Clone, Copy, PartialEq)]
pub enum UpdateFlags {
    /// Timer interrupt.
    Tick,
    /// Task waiting.
    Wait,
    /// Task yielding.
    Yield,
    /// Task exiting.
    Exit,
}

crate::cpu_local_cell! {
    /// Whether this virtual CPU is between a scheduling decision and the switch
    /// that carries it out.
    static IN_RESCHED: bool = false;
}

/// Ends the window [`reschedule`] opened: called by the switched-to task in
/// [`processor::after_switching_to`], and by `reschedule` itself when it
/// decides to do nothing.
pub(super) fn end_resched_window() {
    IN_RESCHED.store(false);
}

/// Preempts the current task.
///
/// Not while this virtual CPU is inside [`reschedule`] or the idle loop's pick.
/// Real OSTD never preempts kernel code from an interrupt; vOSTD does (an
/// upcall, or a guard drop that delivers a pending virtual interrupt), and one
/// that lands after the run queue has decided which task runs next but before
/// the switch has masked interrupts would ask the run queue again. The run
/// queue, which has already made the decided task its current one and put the
/// task still running back in its queue, may then pick the running task, and
/// `switch_to_task` would wait for ever for that task to stop running. The
/// preemption is not lost: `need_preempt` stays set, and the next guard drop
/// or upcall after the switch acts on it.
#[track_caller]
pub(crate) fn might_preempt() {
    if !cpu_local::should_preempt() || IN_RESCHED.load() {
        return;
    }
    reschedule(|local_rq| {
        let next_task_opt = local_rq.try_pick_next();
        if let Some(next_task) = next_task_opt {
            ReschedAction::SwitchTo(next_task.clone())
        } else {
            ReschedAction::DoNothing
        }
    })
}

/// Blocks the current task unless `has_unparked()` returns `true`.
#[track_caller]
pub(crate) fn park_current<F>(has_unparked: F)
where
    F: Fn() -> bool,
{
    let mut current = None;
    let mut is_first_try = true;

    reschedule(|local_rq: &mut dyn LocalRunQueue| {
        let next_task_opt = if is_first_try {
            if has_unparked() {
                return ReschedAction::DoNothing;
            }
            is_first_try = false;

            let should_pick_next = local_rq.update_current(UpdateFlags::Wait);
            current = local_rq.dequeue_current();
            should_pick_next.then(|| local_rq.pick_next())
        } else {
            local_rq.try_pick_next()
        };

        if let Some(next_task) = next_task_opt {
            if Arc::ptr_eq(current.as_ref().unwrap(), next_task) {
                // The current task has been woken and picked as the next task.
                return ReschedAction::DoNothing;
            }
            return ReschedAction::SwitchTo(next_task.clone());
        }

        ReschedAction::Retry
    });
}

/// Unblocks a target task.
pub(crate) fn unpark_target(runnable: Arc<Task>) {
    let preempt_cpu = scheduler_singleton().enqueue(runnable, EnqueueFlags::Wake);
    if let Some(preempt_cpu_id) = preempt_cpu {
        set_need_preempt(preempt_cpu_id);
    }
}

/// Enqueues a newly built task.
#[track_caller]
pub(super) fn run_new_task(runnable: Arc<Task>) {
    let preempt_cpu = scheduler_singleton().enqueue(runnable, EnqueueFlags::Spawn);
    if let Some(preempt_cpu_id) = preempt_cpu {
        set_need_preempt(preempt_cpu_id);
    }

    might_preempt();
}

/// Where real OSTD would send a reschedule inter-processor call.
fn set_need_preempt(cpu_id: CpuId) {
    let preempt_guard = disable_preempt();

    if preempt_guard.current_cpu() == cpu_id {
        cpu_local::set_need_preempt();
    } else {
        // The endovisor raises a KICK on that vCPU, wakes its carrier if it is
        // asleep in `vcpu_idle`, and flags it if it is in user mode. The KICK
        // handler on the other side does `set_need_preempt` there, which is
        // exactly what the IPI callback does on bare metal.
        crate::vcpu::kick(cpu_id.into());
    }
}

/// Dequeues the current task from its runqueue, because it is exiting.
#[track_caller]
pub(super) fn exit_current() -> ! {
    let mut is_first_try = true;

    reschedule(|local_rq: &mut dyn LocalRunQueue| {
        let next_task_opt = if is_first_try {
            is_first_try = false;
            let should_pick_next = local_rq.update_current(UpdateFlags::Exit);
            let _current = local_rq.dequeue_current();
            should_pick_next.then(|| local_rq.pick_next())
        } else {
            local_rq.try_pick_next()
        };

        if let Some(next_task) = next_task_opt {
            ReschedAction::SwitchTo(next_task.clone())
        } else {
            ReschedAction::Retry
        }
    });

    unreachable!()
}

/// Yields execution.
#[track_caller]
pub(super) fn yield_now() {
    reschedule(|local_rq| {
        let should_pick_next = local_rq.update_current(UpdateFlags::Yield);
        let next_task_opt = should_pick_next.then(|| local_rq.pick_next());
        if let Some(next_task) = next_task_opt {
            ReschedAction::SwitchTo(next_task.clone())
        } else {
            ReschedAction::DoNothing
        }
    })
}

/// The bootstrap context of a virtual CPU that has nothing to do yet.
///
/// Real OSTD expects the kernel proper to spawn an idle task per CPU and return
/// from its entry point. A vCPU carrier has to have something to run before that
/// happens, and it must not spin, so it sleeps in the host. The first task it
/// picks abandons this stack for good, exactly as returning from `#[ostd::main]`
/// abandons the bootstrap stack on bare metal.
pub(crate) fn vcpu_idle_loop() -> ! {
    loop {
        let mut next = None;
        IN_RESCHED.store(true);
        scheduler_singleton().mut_local_rq_with(&mut |rq| {
            next = rq.try_pick_next().cloned();
        });
        match next {
            Some(task) => processor::switch_to_task(task),
            None => {
                end_resched_window();
                crate::vcpu::idle(0)
            }
        }
    }
}

/// Acts on the scheduling decision made by a caller-given closure.
#[track_caller]
fn reschedule<F>(mut f: F)
where
    F: FnMut(&mut dyn LocalRunQueue) -> ReschedAction,
{
    // Even if the decision below is `DoNothing`, this flag should be cleared, and
    // before the decision is made, to avoid a race.
    cpu_local::clear_need_preempt();

    // From the decision to the switch, nothing may preempt this vCPU's code
    // into deciding again (see `might_preempt`).
    IN_RESCHED.store(true);

    let mut spins: u32 = 0;
    let next_task = loop {
        let mut action = ReschedAction::DoNothing;
        scheduler_singleton().mut_local_rq_with(&mut |rq| {
            action = f(rq);
        });

        match action {
            ReschedAction::DoNothing => {
                end_resched_window();
                return;
            }
            ReschedAction::Retry => {
                // Nothing to run on this virtual CPU. Spin a little in case a
                // sibling is about to enqueue something, then give the host
                // processor back until a virtual interrupt says otherwise.
                spins += 1;
                if spins >= IDLE_SPINS {
                    crate::vcpu::idle(0);
                } else {
                    core::hint::spin_loop();
                }
                continue;
            }
            ReschedAction::SwitchTo(next_task) => {
                break next_task;
            }
        };
    };

    // `switch_to_task` spins if it finds the next task still running on some CPU,
    // which guarantees soundness regardless of the scheduler implementation.
    processor::switch_to_task(next_task);
}

/// Possible actions of a rescheduling.
enum ReschedAction {
    /// Keep running the current task and do nothing.
    DoNothing,
    /// Loop until finding a task to swap out the current one.
    Retry,
    /// Switch to the target task.
    SwitchTo(Arc<Task>),
}
