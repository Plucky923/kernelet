// SPDX-License-Identifier: MPL-2.0

//! The Rust heap.
//!
//! The kernelet's heap is the host's `kmalloc`, reached through two services,
//! `mem_alloc` and `mem_free`, rather than an allocator inside the grant: the
//! grant is only 4 MiB in this prototype and is kept for frames, the memory a
//! tenant can be given.

use core::alloc::{GlobalAlloc, Layout};

use crate::abi::svc;

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

/// Checks that the heap is reachable. There is nothing to set up: the host's
/// allocator is already running.
pub(crate) fn init() {
    let probe = unsafe { (svc().mem_alloc)(64, 8) };
    assert!(!probe.is_null(), "the host heap service is not working");
    unsafe { (svc().mem_free)(probe, 64, 8) };
}
