// SPDX-License-Identifier: MPL-2.0

//! The Rust heap.
//!
//! The kernelet's heap is the host's `kmalloc`, reached through two services,
//! `mem_alloc` and `mem_free`, rather than an allocator inside the grant: the
//! grant is only 4 MiB in this prototype and is kept for frames, the memory a
//! tenant can be given. The endovisor records every block it hands out, and
//! frees whatever the kernelet still holds when the sandbox ends, so a kernelet
//! that is stopped or evicted with objects alive leaks nothing into the host.

use core::alloc::{GlobalAlloc, Layout};
use core::sync::atomic::{AtomicU64, Ordering};

use crate::{abi::svc, time::read_tsc};

struct HostHeap;

unsafe impl GlobalAlloc for HostHeap {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        (svc().mem_alloc)(layout.size() as u64, layout.align() as u64)
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        (svc().mem_free)(ptr, layout.size() as u64, layout.align() as u64)
    }
}

#[global_allocator]
static HEAP: HostHeap = HostHeap;

/// How many cycles a 64-byte allocation and its free take together, through
/// both services: measured once by `init`, printed by the kernelet's first
/// lines of log.
static ALLOC_FREE_CYCLES: AtomicU64 = AtomicU64::new(0);

const MEASURE_ROUNDS: u64 = 7;
const MEASURE_N: u64 = 1000;

/// Checks that the heap is reachable, and measures what an allocation costs.
/// There is nothing to set up: the host's allocator is already running.
///
/// The measurement is the least of a few rounds, each a run of allocations
/// immediately freed, so that the host's allocator serves every one from its
/// per-processor cache: what is left is the price of the two service calls and
/// of what the endovisor does around `kmalloc` and `kfree`, which is the part
/// this kernelet design adds.
pub(crate) fn init() {
    let probe = unsafe { (svc().mem_alloc)(64, 8) };
    assert!(!probe.is_null(), "the host heap service is not working");
    unsafe { (svc().mem_free)(probe, 64, 8) };

    let mut least = u64::MAX;
    for _ in 0..MEASURE_ROUNDS {
        let t0 = read_tsc();
        for _ in 0..MEASURE_N {
            let p = unsafe { (svc().mem_alloc)(64, 8) };
            unsafe { (svc().mem_free)(p, 64, 8) };
        }
        least = least.min(read_tsc() - t0);
    }
    ALLOC_FREE_CYCLES.store(least / MEASURE_N, Ordering::Relaxed);
}

/// Logs the measurement `init` made.
pub(crate) fn report() {
    crate::early_println!(
        "vOSTD: heap: a 64-byte allocation and its free, {} cycles the pair (least of {} rounds of {}, rdtsc)",
        ALLOC_FREE_CYCLES.load(Ordering::Relaxed),
        MEASURE_ROUNDS,
        MEASURE_N
    );
}
