// SPDX-License-Identifier: MPL-2.0

//! Synchronization primitives.
//!
//! The pieces the task layer and the injected scheduler need, ported from real
//! OSTD. RCU, mutexes and the reader-writer locks are not here: nothing in this
//! prototype uses them, and vOSTD exposes only what a kernel proper compiled
//! against it actually calls.

mod guard;
mod spin;
pub(crate) use self::spin::r2;
mod wait;

pub use self::{
    guard::{GuardTransfer, LocalIrqDisabled, PreemptDisabled, SpinGuardian, WriteIrqDisabled},
    spin::{SpinLock, SpinLockGuard},
    wait::{WaitQueue, Waiter, Waker},
};
