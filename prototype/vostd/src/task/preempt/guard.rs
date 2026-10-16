// SPDX-License-Identifier: MPL-2.0

//! The preemption guard: real OSTD's type, whose count lives in the vCPU
//! record and, through the mirror, in the host's preemption count (see
//! [`super::cpu_local`]).

use crate::{sync::GuardTransfer, task::atomic_mode::InAtomicMode};

/// A guard for disabled preemption.
#[clippy::has_significant_drop]
#[must_use]
#[derive(Debug)]
pub struct DisabledPreemptGuard {
    // This private field prevents users from constructing values of this type
    // directly.
    _private: (),
}

impl !Send for DisabledPreemptGuard {}

// SAFETY: the guard masks this vCPU's virtual interrupts and raises the host's
// preemption count, which meets the second sufficient condition for atomic mode.
unsafe impl InAtomicMode for DisabledPreemptGuard {}

impl DisabledPreemptGuard {
    fn new() -> Self {
        super::cpu_local::inc_guard_count();
        Self { _private: () }
    }
}

impl GuardTransfer for DisabledPreemptGuard {
    fn transfer_to(&mut self) -> Self {
        disable_preempt()
    }
}

impl Drop for DisabledPreemptGuard {
    fn drop(&mut self) {
        super::cpu_local::dec_guard_count();
    }
}

/// Disables preemption.
pub fn disable_preempt() -> DisabledPreemptGuard {
    DisabledPreemptGuard::new()
}
