// SPDX-License-Identifier: MPL-2.0

//! The default FIFO scheduler, ported verbatim from real OSTD at `ab9a4cfdc`
//! except for two things: `select_cpu` spreads work over the sandbox's virtual
//! CPUs round-robin instead of always choosing the BSP (OSTD's own `FIXME`), and
//! the `util::id_set::Id` import is gone with the rest of that module.

use alloc::{boxed::Box, collections::VecDeque, sync::Arc, vec::Vec};
use core::sync::atomic::{AtomicUsize, Ordering};

use super::{info::CommonSchedInfo, EnqueueFlags, LocalRunQueue, Scheduler, UpdateFlags};
use crate::{
    cpu::{num_cpus, CpuId, PinCurrentCpu},
    sync::SpinLock,
    task::{disable_preempt, Task},
};

pub(super) fn new_instance() -> &'static dyn Scheduler {
    let fifo_scheduler = Box::new(FifoScheduler::default());
    Box::<FifoScheduler<Task>>::leak(fifo_scheduler)
}

/// A simple FIFO (First-In-First-Out) task scheduler.
struct FifoScheduler<T: CommonSchedInfo> {
    /// A thread-safe queue per virtual CPU.
    rq: Vec<SpinLock<FifoRunQueue<T>>>,
    next: AtomicUsize,
}

impl<T: CommonSchedInfo> FifoScheduler<T> {
    fn new(nr_cpus: usize) -> Self {
        let mut rq = Vec::new();
        for _ in 0..nr_cpus {
            rq.push(SpinLock::new(FifoRunQueue::new()));
        }
        Self {
            rq,
            next: AtomicUsize::new(0),
        }
    }

    fn select_cpu(&self) -> CpuId {
        let n = num_cpus();
        let i = self.next.fetch_add(1, Ordering::Relaxed) % n;
        CpuId::new(i as u32)
    }
}

impl<T: CommonSchedInfo + Send + Sync> Scheduler<T> for FifoScheduler<T> {
    fn enqueue(&self, runnable: Arc<T>, flags: EnqueueFlags) -> Option<CpuId> {
        let (still_in_rq, target_cpu) = {
            let selected_cpu_id = self.select_cpu();

            if let Err(task_cpu_id) = runnable.cpu().set_if_is_none(selected_cpu_id) {
                debug_assert!(flags != EnqueueFlags::Spawn);
                (true, task_cpu_id)
            } else {
                (false, selected_cpu_id)
            }
        };

        let mut rq = self.rq[target_cpu.as_usize()].disable_irq().lock();
        if still_in_rq && runnable.cpu().set_if_is_none(target_cpu).is_err() {
            return None;
        }
        rq.queue.push_back(runnable);

        // All tasks are important. Do not preempt the current task without good
        // reason. But a vCPU that is asleep in `vcpu_idle` has to be told, or it
        // will sleep through the work.
        if target_cpu != CpuId::current_racy() {
            Some(target_cpu)
        } else {
            None
        }
    }

    fn local_rq_with(&self, f: &mut dyn FnMut(&dyn LocalRunQueue<T>)) {
        let preempt_guard = disable_preempt();
        let local_rq: &FifoRunQueue<T> = &self.rq[preempt_guard.current_cpu().as_usize()]
            .disable_irq()
            .lock();
        f(local_rq);
    }

    fn mut_local_rq_with(&self, f: &mut dyn FnMut(&mut dyn LocalRunQueue<T>)) {
        let preempt_guard = disable_preempt();
        let local_rq: &mut FifoRunQueue<T> = &mut self.rq[preempt_guard.current_cpu().as_usize()]
            .disable_irq()
            .lock();
        f(local_rq);
    }
}

struct FifoRunQueue<T: CommonSchedInfo> {
    current: Option<Arc<T>>,
    queue: VecDeque<Arc<T>>,
}

impl<T: CommonSchedInfo> FifoRunQueue<T> {
    pub const fn new() -> Self {
        Self {
            current: None,
            queue: VecDeque::new(),
        }
    }
}

impl<T: CommonSchedInfo> LocalRunQueue<T> for FifoRunQueue<T> {
    fn current(&self) -> Option<&Arc<T>> {
        self.current.as_ref()
    }

    fn update_current(&mut self, flags: UpdateFlags) -> bool {
        match flags {
            UpdateFlags::Tick => false,
            UpdateFlags::Wait | UpdateFlags::Yield | UpdateFlags::Exit => !self.queue.is_empty(),
        }
    }

    fn try_pick_next(&mut self) -> Option<&Arc<T>> {
        let next_task = self.queue.pop_front()?;
        if let Some(prev_task) = self.current.replace(next_task) {
            self.queue.push_back(prev_task);
        }

        self.current.as_ref()
    }

    fn dequeue_current(&mut self) -> Option<Arc<T>> {
        self.current.take().inspect(|task| task.cpu().set_to_none())
    }
}

impl Default for FifoScheduler<Task> {
    fn default() -> Self {
        Self::new(num_cpus())
    }
}
