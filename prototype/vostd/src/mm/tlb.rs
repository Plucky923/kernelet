// SPDX-License-Identifier: MPL-2.0

//! TLB flushing, with the tree's structure kept exactly.
//!
//! The kernel proper issues flush operations on a cursor's [`TlbFlusher`] and
//! dispatches them; OSTD releases frames queued with an operation only after
//! the dispatch. What a dispatch *is* differs: real OSTD invalidates locally
//! and sends IPIs to the CPUs in the space's set; here it is one `vm_flush`
//! per operation (or one for everything), which the endovisor serves with
//! `flush_tlb_mm_range()` over every processor in the address space's CPU
//! mask, synchronously. So `sync_tlb_flush` has nothing left to wait for.
//!
//! The operation encoding and the coalescing (at 32 pages or more, flush
//! everything) are the tree's `ostd/src/mm/tlb.rs` at `ab9a4cfdc`.

use alloc::vec::Vec;
use core::ops::Range;

use super::{Paddr, Vaddr, PAGE_SIZE};
use crate::cpu::PinCurrentCpu;

const FLUSH_ALL_PAGES_THRESHOLD: usize = 32;

/// A TLB flush operation: one page, a run of pages, or everything.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TlbFlushOp(Vaddr);

impl TlbFlushOp {
    const FLUSH_ALL_VAL: Vaddr = Vaddr::MAX;
    const FLUSH_RANGE_NPAGES_MASK: Vaddr =
        (1 << (usize::BITS - FLUSH_ALL_PAGES_THRESHOLD.leading_zeros())) - 1;

    /// Flushes every TLB entry of the space.
    pub const fn for_all() -> Self {
        TlbFlushOp(Self::FLUSH_ALL_VAL)
    }

    /// Flushes one page.
    pub const fn for_single(addr: Vaddr) -> Self {
        TlbFlushOp(addr | 1)
    }

    /// Flushes a range of pages.
    pub const fn for_range(range: Range<Vaddr>) -> Self {
        assert!(range.start % PAGE_SIZE == 0, "range start must be page-aligned");
        assert!(range.end % PAGE_SIZE == 0, "range end must be page-aligned");
        assert!(range.start < range.end, "range must not be empty");
        let num_pages = (range.end - range.start) / PAGE_SIZE;
        if num_pages >= FLUSH_ALL_PAGES_THRESHOLD {
            return TlbFlushOp::for_all();
        }
        TlbFlushOp(range.start | num_pages)
    }

    fn is_all(&self) -> bool {
        self.0 == Self::FLUSH_ALL_VAL
    }

    fn num_pages(&self) -> usize {
        if self.is_all() {
            usize::MAX
        } else {
            self.0 & Self::FLUSH_RANGE_NPAGES_MASK
        }
    }

    fn start(&self) -> Vaddr {
        self.0 & !Self::FLUSH_RANGE_NPAGES_MASK
    }
}

/// What a flusher flushes through: the space's host side.
pub(crate) trait FlushTarget {
    fn flush(&self, va: Vaddr, len: usize);
}

/// A TLB flusher, dedicated to one cursor.
pub struct TlbFlusher<'a, G: PinCurrentCpu> {
    target: &'a dyn FlushTarget,
    ops: [Vaddr; FLUSH_ALL_PAGES_THRESHOLD],
    num_ops: usize,
    num_pages: usize,
    all: bool,
    /// References to release after the dispatch, as raw frames.
    frames: Vec<Paddr>,
    _pin_current: G,
}

impl<'a, G: PinCurrentCpu> TlbFlusher<'a, G> {
    pub(crate) fn new(target: &'a dyn FlushTarget, pin_current_guard: G) -> Self {
        Self {
            target,
            ops: [0; FLUSH_ALL_PAGES_THRESHOLD],
            num_ops: 0,
            num_pages: 0,
            all: false,
            frames: Vec::new(),
            _pin_current: pin_current_guard,
        }
    }

    /// Issues a TLB flush operation, to be performed at the next dispatch.
    pub fn issue_tlb_flush(&mut self, op: TlbFlushOp) {
        if self.all {
            return;
        }
        let n = op.num_pages();
        if op.is_all() || self.num_pages + n >= FLUSH_ALL_PAGES_THRESHOLD {
            self.all = true;
            self.num_ops = 0;
            return;
        }
        self.ops[self.num_ops] = op.0;
        self.num_ops += 1;
        self.num_pages += n;
    }

    fn is_empty(&self) -> bool {
        !self.all && self.num_ops == 0 && self.frames.is_empty()
    }

    /// Performs every issued operation on every processor that may cache the
    /// space, then releases the queued frames after a grace period.
    pub fn dispatch_tlb_flush(&mut self) {
        if self.is_empty() {
            return;
        }
        if self.all {
            self.target.flush(0, usize::MAX);
        } else {
            for i in 0..self.num_ops {
                let op = TlbFlushOp(self.ops[i]);
                self.target.flush(op.start(), op.num_pages() * PAGE_SIZE);
            }
        }
        self.all = false;
        self.num_ops = 0;
        self.num_pages = 0;
        if !self.frames.is_empty() {
            super::rcu::synchronize();
            for p in self.frames.drain(..) {
                drop(super::UFrame::from_raw(p));
            }
        }
    }

    /// Waits for the dispatched flushes to complete. They already have: the
    /// host's flush is synchronous.
    pub fn sync_tlb_flush(&mut self) {}
}

impl<G: PinCurrentCpu> Drop for TlbFlusher<'_, G> {
    /// Operations left undispatched are dispatched: the tree's would simply
    /// vanish, with their frames; doing them is the conservative choice.
    fn drop(&mut self) {
        self.dispatch_tlb_flush();
    }
}
