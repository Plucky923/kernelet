// SPDX-License-Identifier: MPL-2.0

//! The prototype's instrumentation and its one test hook. **Not OSTD API**: no
//! kernel proper of the Asterinas tree calls anything here, and the 100-line
//! kernel does not. The memory test kernel (`mem/`) uses it to take counter
//! deltas around a test, and to make `vm_map` sleep in the host so that the
//! range lock's slow path is exercised.

use core::sync::atomic::Ordering;

use crate::mm::{frame, rcu, vm_space};

/// A snapshot of the host's counters of the memory paths (the endovisor's
/// `struct klet_mem_stats`), plus vOSTD's own.
#[derive(Clone, Copy, Debug, Default)]
pub struct MemStats {
    /// Calls of the area's `fault`.
    pub faults: u64,
    /// Calls of the area's `pfn_mkwrite`.
    pub mkwrites: u64,
    /// Faults recorded for the kernel proper as a tenant exception.
    pub reported: u64,
    /// Kernel-mode faults answered with SIGBUS.
    pub kernel_faults: u64,
    pub maps: u64,
    pub unmaps: u64,
    pub unmapped: u64,
    pub protects: u64,
    pub protected: u64,
    pub flushes: u64,
    pub flush_alls: u64,
    pub waits: u64,
    pub wait_sleeps: u64,
    pub wakes: u64,
    pub spaces: u64,
    /// vOSTD: compare-and-swap retries and slow-path waits of the range lock.
    pub lock_cas_retries: u64,
    pub lock_waits: u64,
    /// vOSTD: grace periods, and those that found a reader to wait for.
    pub grace_periods: u64,
    pub grace_waits: u64,
    /// vOSTD: `Frame::from_raw` ownership checks performed.
    pub owner_checks: u64,
    /// vOSTD: dropped spaces pushed on the retire list, and drained from it.
    pub retired: u64,
    pub drained: u64,
    /// The host: vm_* services entered with the kernelet's mirrored preemption
    /// count raised, which the prologue lifted.
    pub lifted: u64,
    /// vOSTD: pages moved into and out of the withheld set.
    pub withheld_in: u64,
    pub withheld_out: u64,
    /// vOSTD: frames of the grant allocated now.
    pub frames_in_use: u64,
}

impl MemStats {
    /// `self - before`, field by field (`frames_in_use` is kept as is).
    pub fn since(&self, before: &MemStats) -> MemStats {
        macro_rules! d {
            ($($f:ident),*) => { MemStats { $($f: self.$f.wrapping_sub(before.$f),)* frames_in_use: self.frames_in_use } };
        }
        d!(faults, mkwrites, reported, kernel_faults, maps, unmaps, unmapped, protects,
           protected, flushes, flush_alls, waits, wait_sleeps, wakes, spaces,
           lock_cas_retries, lock_waits, grace_periods, grace_waits,
           owner_checks, retired, drained, lifted, withheld_in, withheld_out)
    }
}

/// Reads every counter.
pub fn mem_stats() -> MemStats {
    let mut m = MemStats::default();
    if let Some(h) = crate::abi::mem_stats() {
        let r = |a: &core::sync::atomic::AtomicU64| a.load(Ordering::Relaxed);
        m.faults = r(&h.faults);
        m.mkwrites = r(&h.mkwrites);
        m.reported = r(&h.reported);
        m.kernel_faults = r(&h.kernel_faults);
        m.maps = r(&h.maps);
        m.unmaps = r(&h.unmaps);
        m.unmapped = r(&h.unmapped);
        m.protects = r(&h.protects);
        m.protected = r(&h.protected);
        m.flushes = r(&h.flushes);
        m.flush_alls = r(&h.flush_alls);
        m.waits = r(&h.waits);
        m.wait_sleeps = r(&h.wait_sleeps);
        m.wakes = r(&h.wakes);
        m.spaces = r(&h.spaces);
        m.lifted = r(&h.lifted);
    }
    let l = |a: &core::sync::atomic::AtomicU64| a.load(Ordering::Relaxed);
    m.lock_cas_retries = l(&vm_space::LOCK_CAS_RETRIES);
    m.lock_waits = l(&vm_space::LOCK_WAITS);
    m.grace_periods = l(&rcu::GRACE_PERIODS);
    m.grace_waits = l(&rcu::GRACE_WAITS);
    m.owner_checks = l(&frame::OWNER_CHECKS);
    m.retired = l(&vm_space::RETIRED);
    m.drained = l(&vm_space::DRAINED);
    m.withheld_in = l(&vm_space::WITHHELD_IN);
    m.withheld_out = l(&vm_space::WITHHELD_OUT);
    m.frames_in_use = frame::allocator::frames_in_use() as u64;
    m
}

/// The contended-cursor test: every `vm_map` sleeps in the host for
/// `klet_test_sleep_ms` (needs the endovisor loaded with `klet_test_hooks=1`).
pub fn set_map_test_sleep(on: bool) {
    vm_space::MAP_TEST_SLEEP.store(on, Ordering::Relaxed);
}

/// How many kernelet spin locks this virtual CPU holds (the sleeping
/// contract's count).
pub fn spin_locks_held() -> u32 {
    crate::sync::r2::held()
}
