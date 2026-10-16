// SPDX-License-Identifier: MPL-2.0

//! Preemption: the guard that disables it, the per-vCPU word that counts
//! guards, and the idle instruction, which on a virtual CPU is a service.

pub(crate) mod cpu_local;
mod guard;

pub use self::guard::{disable_preempt, DisabledPreemptGuard};

/// Halts the virtual CPU until an interrupt if no preemption is required.
///
/// On bare metal this is `sti; hlt`. Here it is the `vcpu_idle` service: the
/// carrier sleeps in the host until a virtual interrupt arrives.
///
/// # Panics
///
/// Panics if called in the atomic mode.
#[track_caller]
pub fn halt_cpu() {
    crate::task::atomic_mode::might_sleep();

    if !cpu_local::need_preempt() {
        crate::vcpu::idle(0);
    }

    super::scheduler::might_preempt();
}
