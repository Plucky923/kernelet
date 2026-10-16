// SPDX-License-Identifier: MPL-2.0

//! The guard behaviors of a spin lock, real OSTD's: a lock holder disables
//! either preemption or (virtual) interrupts, and the guard type says which.
//! The two guards themselves are vOSTD's, because what they raise and lower is
//! the vCPU record (see [`crate::task::preempt`] and [`crate::irq`]).

use crate::{
    irq::{disable_local, DisabledLocalIrqGuard},
    task::{atomic_mode::AsAtomicModeGuard, disable_preempt, DisabledPreemptGuard},
};

/// A guardian that denotes the guard behavior for holding a spin-based lock.
///
/// It at least ensures that the atomic mode is maintained while the lock is
/// held.
pub trait SpinGuardian {
    /// The guard type for holding a spin lock or a spin-based write lock.
    type Guard: AsAtomicModeGuard + GuardTransfer;
    /// The guard type for holding a spin-based read lock.
    type ReadGuard: AsAtomicModeGuard + GuardTransfer;

    /// Creates a new guard.
    fn guard() -> Self::Guard;
    /// Creates a new read guard.
    fn read_guard() -> Self::ReadGuard;
}

/// The Guard can be transferred atomically.
pub trait GuardTransfer {
    /// Atomically transfers the current guard to a new instance.
    fn transfer_to(&mut self) -> Self;
}

/// A guardian that disables preemption while holding a lock.
pub enum PreemptDisabled {}

impl SpinGuardian for PreemptDisabled {
    type Guard = DisabledPreemptGuard;
    type ReadGuard = DisabledPreemptGuard;

    fn guard() -> Self::Guard {
        disable_preempt()
    }
    fn read_guard() -> Self::Guard {
        disable_preempt()
    }
}

/// A guardian that disables virtual interrupts while holding a lock.
pub enum LocalIrqDisabled {}

impl SpinGuardian for LocalIrqDisabled {
    type Guard = DisabledLocalIrqGuard;
    type ReadGuard = DisabledLocalIrqGuard;

    #[track_caller]
    fn guard() -> Self::Guard {
        disable_local()
    }
    fn read_guard() -> Self::Guard {
        disable_local()
    }
}

/// A guardian that disables virtual interrupts while holding a write lock.
pub enum WriteIrqDisabled {}

impl SpinGuardian for WriteIrqDisabled {
    type Guard = DisabledLocalIrqGuard;
    type ReadGuard = DisabledPreemptGuard;

    #[track_caller]
    fn guard() -> Self::Guard {
        disable_local()
    }
    fn read_guard() -> Self::ReadGuard {
        disable_preempt()
    }
}
