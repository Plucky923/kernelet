// SPDX-License-Identifier: MPL-2.0

//! Synchronization primitives.
//!
//! The pieces the task layer and the injected scheduler need, ported from real
//! OSTD. RCU, mutexes and the reader-writer locks are not here: nothing in this
//! prototype uses them. What is here is what the kernels proper compiled
//! against vOSTD call, plus two members of the same interface that none of them
//! calls but a kernel written against OSTD would reasonably reach for, kept for
//! completeness: `SpinLock::try_lock` and `WaitQueue::wake_one`.

mod guard;
mod spin;
pub(crate) use self::spin::r2;
mod wait;

pub use self::{
    guard::{GuardTransfer, LocalIrqDisabled, PreemptDisabled, SpinGuardian, WriteIrqDisabled},
    spin::{SpinLock, SpinLockGuard},
    wait::{WaitQueue, Waiter, Waker},
};
