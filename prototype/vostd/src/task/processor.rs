// SPDX-License-Identifier: MPL-2.0

//! Ported from real OSTD's `task/processor.rs` at `ab9a4cfdc`.
//!
//! Two changes:
//!
//! 1. `crate::sync::finish_grace_period()` is gone, because vOSTD has no
//!    general RCU (its one grace period, for tenant memory, is in
//!    [`crate::mm::rcu`]).
//! 2. "Local IRQs" are this virtual CPU's virtual interrupts, so the guard that
//!    `switch_to_task` forgets and `after_switching_to` releases is the vCPU's
//!    mask depth. It is also, through the mirror, the host's preemption count,
//!    which means the context switch itself is protected from the host
//!    descheduling the carrier halfway through — for free, and for the same
//!    reason OSTD wanted interrupts off there.

use alloc::sync::Arc;
use core::{ptr::NonNull, sync::atomic::Ordering};

use super::{Task, POST_SCHEDULE_HANDLER, PRE_SCHEDULE_HANDLER};
use crate::{
    arch::task::{context_switch, first_context_switch},
    cpu_local_cell,
    irq::DisabledLocalIrqGuard,
};

cpu_local_cell! {
    /// The `Arc<Task>` (cast by `Arc::into_raw`) that is the current task.
    static CURRENT_TASK_PTR: *const Task = core::ptr::null();
    /// The previous task on the processor before switching to the current task.
    static PREVIOUS_TASK_PTR: *const Task = core::ptr::null();
}

/// Returns a pointer to the current task running on the virtual CPU.
///
/// Returns `None` in the bootstrap context.
pub(super) fn current_task() -> Option<NonNull<Task>> {
    NonNull::new(CURRENT_TASK_PTR.load().cast_mut())
}

/// Switches to another task.
///
/// If the current task is none, the bootstrap context is abandoned and this does
/// not return.
///
/// # Panics
///
/// Panics if called while holding a guard.
#[track_caller]
pub(super) fn switch_to_task(next_task: Arc<Task>) {
    super::atomic_mode::might_sleep();

    let irq_guard = crate::irq::disable_local();

    before_switching_to(&next_task, &irq_guard);

    let next_task_ctx_ptr = next_task.ctx().get().cast_const();

    let current_task_ptr = CURRENT_TASK_PTR.load();
    CURRENT_TASK_PTR.store(Arc::into_raw(next_task));
    debug_assert!(PREVIOUS_TASK_PTR.load().is_null());
    PREVIOUS_TASK_PTR.store(current_task_ptr);

    // We must keep virtual interrupts masked while switching; see
    // `after_switching_to`.
    core::mem::forget(irq_guard);

    let current_task_ctx_ptr = if !current_task_ptr.is_null() {
        // SAFETY: the pointer was built with `Arc::into_raw` and will only be
        // dropped as a previous task, so it is valid until `after_switching_to`.
        let current_task = unsafe { &*current_task_ptr };
        current_task.ctx.get()
    } else {
        // SAFETY: we have exclusive access to the next context, which is either
        // correctly initialised or written by a previous `context_switch`.
        unsafe { first_context_switch(next_task_ctx_ptr) };
        unreachable!("`first_context_switch` should never return");
    };

    // SAFETY: as above for both contexts.
    unsafe {
        context_switch(next_task_ctx_ptr, current_task_ctx_ptr);
    }

    // SAFETY: the task was just switched back to.
    unsafe { after_switching_to() };
}

fn before_switching_to(next_task: &Task, irq_guard: &DisabledLocalIrqGuard) {
    if let Some(handler) = PRE_SCHEDULE_HANDLER.get() {
        handler(irq_guard);
    }

    next_task.kstack.flush_tlb(irq_guard);

    // Ensure that we are not switching to a task that is already running. This
    // is the one place that makes an injected scheduler's mistake harmless
    // rather than catastrophic.
    while next_task
        .switched_to_cpu
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Relaxed)
        .is_err()
    {
        crate::early_println!("kernelet: switching to a task already running in the foreground");
        core::hint::spin_loop();
    }
}

/// Does cleanups after switching to a task.
///
/// # Safety
///
/// Must be called exactly once after switching to a task.
pub(super) unsafe fn after_switching_to() {
    let prev = PREVIOUS_TASK_PTR.load();
    let prev = if !prev.is_null() {
        PREVIOUS_TASK_PTR.store(core::ptr::null());

        // SAFETY: the pointer was built with `Arc::into_raw`, and is taken only
        // once because it is cleared above.
        let prev_task = unsafe { Arc::from_raw(prev) };

        prev_task.switched_to_cpu.store(false, Ordering::Release);

        Some(prev_task)
    } else {
        None
    };

    // Tell the endovisor which stack the upcall may be pushed onto now.
    if let Some(task) = current_task() {
        // SAFETY: the pointer is the current task, alive until it is switched away.
        let base = unsafe { task.as_ref() }.kstack.base_vaddr();
        crate::vcpu::publish_stack_limit(base);
    }

    if let Some(handler) = POST_SCHEDULE_HANDLER.get() {
        handler();
    }

    // See `switch_to_task`, where a guard was forgotten.
    crate::arch::irq::enable_local();

    drop(prev);
}
