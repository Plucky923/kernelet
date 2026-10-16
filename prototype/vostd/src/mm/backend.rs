// SPDX-License-Identifier: MPL-2.0

//! What a `VmSpace` is made of: a Linux address space the endovisor made,
//! named by an id. Every change to it is a `vm_*` service; vOSTD only reads
//! its page table, through the direct map ([`super::page_table`]).
//!
//! Every service that may sleep in the host is called behind
//! [`r2::assert_may_sleep`]: the sleeping contract says not under a kernelet
//! spin lock and not with interrupts off, because a carrier that sleeps in the
//! host takes its virtual CPU with it, and a sibling spinning on that lock, or
//! an interrupt the virtual CPU has masked, would wait for as long as the host
//! keeps it asleep.

use core::sync::atomic::{AtomicU64, Ordering};

use super::{Paddr, Vaddr};
use crate::{abi, abi::svc, sync::r2};

/// `vm_map` cannot fail on the tree (`vm_space.rs:365`): a page-table page
/// that cannot be allocated is a kernel panic there, and here it ends the
/// kernelet the same way.
#[cold]
fn map_failed(va: Vaddr, paddr: Paddr, err: i64) -> ! {
    let what = match -err {
        abi::KLET_INVALID => "the slot is not empty (a vOSTD bug: the range lock should exclude it)",
        abi::KLET_NOT_OWNED => "the frame is not this kernelet's",
        abi::KLET_LIMIT => "no page-table page could be allocated",
        _ => "an unexpected error",
    };
    panic!("map of {:#x} at {:#x} failed with {}: {}", paddr, va, err, what);
}

/// Every sleeping service's stub: the sleeping contract's assertion, and then
/// a drain point for the retire list if the caller holds no guard (see
/// [`crate::mm::vm_space::retire`]).
#[inline]
#[track_caller]
fn sleeping(name: &str) {
    r2::assert_may_sleep(name);
    crate::mm::vm_space::retire::drain_if_safe();
}

/// One Linux-native address space: its id and its shared record.
pub(crate) struct Backend {
    id: u64,
    rec: &'static abi::SpaceRec,
}

impl core::fmt::Debug for Backend {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(f, "Space({})", self.id)
    }
}

impl Backend {
    /// `vm_create`: a Linux address space with its one area.
    pub(crate) fn new() -> Self {
        sleeping("vm_create");
        // SAFETY: the service makes a Linux address space and touches nothing
        // of the kernelet's.
        let id = unsafe { (svc().vm_create)() };
        assert!(id > 0, "vm_create failed with {}", id);
        Self {
            id: id as u64,
            rec: abi::space_rec(id as u64),
        }
    }

    /// The physical address of Linux's `mm->pgd`.
    #[inline]
    pub(crate) fn root(&self) -> Paddr {
        self.rec.root_paddr.load(Ordering::Relaxed) as Paddr
    }

    /// What the vCPU record holds when this space is active.
    #[inline]
    pub(crate) fn token(&self) -> usize {
        self.id as usize
    }

    /// The range lock's words, in the space's shared record.
    pub(crate) fn words(&self) -> &[AtomicU64; abi::SPACE_LOCK_WORDS] {
        &self.rec.lock
    }

    /// Maps one frame. Ends the kernelet if the host cannot.
    pub(crate) fn map(&self, va: Vaddr, paddr: Paddr, prot: u32) {
        sleeping("vm_map");
        // SAFETY: the endovisor checks the frame against the grant.
        let r = unsafe { (svc().vm_map)(self.id, va as u64, paddr as u64, prot) };
        if r < 0 {
            map_failed(va, paddr, r);
        }
    }

    /// Clears and flushes. The count of what it cleared is the caller's, from
    /// its own walk: `zap_vma_ptes()` reports none.
    pub(crate) fn unmap(&self, va: Vaddr, len: usize) {
        sleeping("vm_unmap");
        // SAFETY: the service clears entries of this kernelet's space.
        let r = unsafe { (svc().vm_unmap)(self.id, va as u64, len as u64) };
        assert!(r >= 0, "vm_unmap({:#x}, {:#x}) failed with {}", va, len, r);
    }

    /// Rewrites one present entry. Not flushed.
    pub(crate) fn protect(&self, va: Vaddr, prot: u32) {
        sleeping("vm_protect");
        // SAFETY: as above.
        let r = unsafe { (svc().vm_protect)(self.id, va as u64, prot) };
        assert!(r == 1, "vm_protect({:#x}) failed with {}", va, r);
    }

    /// `len == usize::MAX`: everything. Never sleeps.
    pub(crate) fn flush(&self, va: Vaddr, len: usize) {
        let len = if len == usize::MAX { u64::MAX } else { len as u64 };
        // SAFETY: a TLB flush of this kernelet's space.
        let r = unsafe { (svc().vm_flush)(self.id, va as u64, len) };
        assert!(r == 0, "vm_flush failed with {}", r);
    }

    /// Makes this the space the current virtual CPU's carrier adopts on its
    /// way to user mode. Never sleeps.
    pub(crate) fn activate(&self) {
        // SAFETY: records the vCPU's current space.
        let r = unsafe { (svc().vm_activate)(self.id) };
        assert!(r == 0, "vm_activate failed with {}", r);
    }

    /// The range lock's slow path: returns when word `stripe` may have
    /// changed.
    pub(crate) fn wait(&self, stripe: usize, expected: u64) {
        sleeping("vm_wait");
        // SAFETY: names a word of this space's record by index.
        let r = unsafe { (svc().vm_wait)(self.id, stripe as u32, expected) };
        assert!(r == 0, "vm_wait failed with {}", r);
    }

    /// Wakes the waiters of word `stripe`. Never sleeps.
    pub(crate) fn wake(&self, stripe: usize) {
        // SAFETY: as above.
        let r = unsafe { (svc().vm_wake)(self.id, stripe as u32) };
        assert!(r == 0, "vm_wake failed with {}", r);
    }

    /// `vm_destroy`: gives the endovisor's reference on the address space back.
    pub(crate) fn destroy(self) {
        sleeping("vm_destroy");
        // SAFETY: the space has no cursor, no mapping and no frame left.
        let r = unsafe { (svc().vm_destroy)(self.id) };
        assert!(r == 0, "vm_destroy failed with {}", r);
    }
}
