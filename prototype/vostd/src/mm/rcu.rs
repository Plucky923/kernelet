// SPDX-License-Identifier: MPL-2.0

//! A minimal RCU for tenant memory: read sections around lockless copies, and
//! a grace period before an unmapped frame is released.
//!
//! The tree's `unmap` hands removed frames to `RcuDrop`, so that a copy that
//! walked the page table without a cursor (a `VmReader` or `VmWriter`) and is
//! still reading the frame through it finishes first. vOSTD has no general
//! RCU, so this is the smallest thing with the same guarantee: each virtual
//! CPU has a sequence word that is odd while it is
//! inside a read section, a read section holds a preemption guard so it stays
//! on one virtual CPU, and a grace period waits until every other virtual CPU
//! that was inside a section when it started has left it. It is synchronous:
//! the caller waits, rather than queueing a callback.
//!
//! A read section is a few hundred nanoseconds (one page's walk and copy), so
//! the wait is short unless Linux has descheduled the reader's carrier, in
//! which case the waiter tells the host it is spinning (`vcpu_on_spin`).

use core::sync::atomic::{AtomicU64, Ordering};

use crate::{cpu::MAX_CPUS, task::disable_preempt};

static SEQ: [AtomicU64; MAX_CPUS] = [const { AtomicU64::new(0) }; MAX_CPUS];

/// How many grace periods were waited for, and how many of them found a
/// reader to wait for. For the tests.
pub(crate) static GRACE_PERIODS: AtomicU64 = AtomicU64::new(0);
pub(crate) static GRACE_WAITS: AtomicU64 = AtomicU64::new(0);

/// Runs `f` inside a read section on this virtual CPU.
#[inline]
pub(crate) fn read<R>(f: impl FnOnce() -> R) -> R {
    let guard = disable_preempt();
    let v = crate::cpu::CpuId::current_racy().as_usize();
    // Odd: inside. Sequentially consistent, so that a grace period that
    // started after a page-table entry was cleared either sees this or this
    // section's walk sees the cleared entry.
    SEQ[v].fetch_add(1, Ordering::SeqCst);
    let r = f();
    SEQ[v].fetch_add(1, Ordering::Release);
    drop(guard);
    r
}

/// Waits until every read section that was in progress on another virtual
/// CPU when this was called has ended.
pub(crate) fn synchronize() {
    GRACE_PERIODS.fetch_add(1, Ordering::Relaxed);
    let me = crate::cpu::CpuId::current_racy().as_usize();
    let n = crate::cpu::num_cpus().min(MAX_CPUS);
    for v in 0..n {
        if v == me {
            continue;
        }
        let s = SEQ[v].load(Ordering::SeqCst);
        if s & 1 == 0 {
            continue;
        }
        GRACE_WAITS.fetch_add(1, Ordering::Relaxed);
        let mut spins: u32 = 0;
        while SEQ[v].load(Ordering::Acquire) == s {
            core::hint::spin_loop();
            spins += 1;
            if spins % 1000 == 0 {
                crate::vcpu::on_spin();
            }
        }
    }
}
