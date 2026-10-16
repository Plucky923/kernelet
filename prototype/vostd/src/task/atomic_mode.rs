// SPDX-License-Identifier: MPL-2.0

//! Atomic mode.
//!
//! Kernel code is in atomic mode when task preemption is disabled or local
//! interrupts are disabled. Both are facts in the vCPU record — a guard count and
//! a virtual interrupt flag — and both are conditions here, exactly as on bare
//! metal. While in atomic mode, switching tasks or switching to user space
//! panics.

/// Marks a function as one that might sleep.
///
/// Panics if executed in atomic mode.
#[track_caller]
pub fn might_sleep() {
    let guard_count = super::preempt::cpu_local::get_guard_count();
    let irq_off = super::preempt::cpu_local::irq_is_off();
    if (guard_count != 0 || irq_off) && !crate::in_bootstrap_context() {
        panic!(
            "this function might break atomic mode (guards = {}, interrupts masked = {}; last masked at {:?})",
            guard_count, irq_off, crate::irq::last_mask()
        );
    }
}

/// A marker trait for guard types that enforce the atomic mode.
///
/// # Safety
///
/// The implementer must ensure that the atomic mode is maintained while the
/// guard type is alive.
pub unsafe trait InAtomicMode: core::fmt::Debug {}

/// Abstracts any type from which one can obtain a reference to an atomic-mode
/// guard.
pub trait AsAtomicModeGuard {
    /// Returns a guard for the atomic mode.
    fn as_atomic_mode_guard(&self) -> &dyn InAtomicMode;
}

impl<G: InAtomicMode> AsAtomicModeGuard for G {
    fn as_atomic_mode_guard(&self) -> &dyn InAtomicMode {
        self
    }
}

impl AsAtomicModeGuard for dyn InAtomicMode + '_ {
    fn as_atomic_mode_guard(&self) -> &dyn InAtomicMode {
        self
    }
}
