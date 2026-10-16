// SPDX-License-Identifier: MPL-2.0

//! Page tables, read through the direct map.
//!
//! The only page table a tenant process has is its *Linux* page table. vOSTD
//! never writes it: the endovisor does, in the `vm_*` services. vOSTD reads it
//! here, without a lock, through the direct map. That is safe for two reasons
//! the host guarantees: the page-table pages of a space's area are freed only
//! in `exit_mmap()`, which the endovisor's reference on the address space
//! holds off until `vm_destroy`; and Linux writes an entry with a single
//! 64-bit store, so a reader sees either the old entry or the new one.
//!
//! The walk is the four-level x86-64 one; vOSTD refuses to start on a host
//! that uses five levels.

use super::{paddr_to_vaddr, PageFlags, Paddr, Vaddr, PAGE_SIZE};

/// x86-64 page table entry bits.
#[allow(dead_code)]
pub(crate) mod pte {
    pub(crate) const PRESENT: u64 = 1 << 0;
    pub(crate) const WRITE: u64 = 1 << 1;
    pub(crate) const USER: u64 = 1 << 2;
    pub(crate) const PWT: u64 = 1 << 3;
    pub(crate) const PCD: u64 = 1 << 4;
    pub(crate) const ACCESSED: u64 = 1 << 5;
    pub(crate) const DIRTY: u64 = 1 << 6;
    /// Page size (a huge leaf) at levels 2 and above; the PAT bit at level 1.
    pub(crate) const HUGE: u64 = 1 << 7;
    pub(crate) const GLOBAL: u64 = 1 << 8;
    pub(crate) const NO_EXECUTE: u64 = 1 << 63;
    pub(crate) const ADDR_MASK: u64 = 0x000f_ffff_ffff_f000;
}

const NR_LEVELS: u32 = 4;

fn index(va: Vaddr, level: u32) -> usize {
    (va >> (12 + 9 * (level - 1))) & 0x1ff
}

fn level_size(level: u32) -> usize {
    1usize << (12 + 9 * (level - 1))
}

/// Reads entry `idx` of the table page at `node`, with one load.
#[inline(always)]
fn read_entry(node: Paddr, idx: usize) -> u64 {
    // SAFETY: `node` is a page-table page that cannot be freed under us (the
    // endovisor's reference on the address space holds off `exit_mmap()`), so
    // its direct-map alias is valid for reads, and `idx < 512`.
    unsafe { core::ptr::read_volatile((paddr_to_vaddr(node) as *const u64).add(idx)) }
}

/// The table one entry above level 1 points to, or `None` if it is absent or a
/// huge leaf (never made in this area). Nothing else is read above the leaf:
/// permissions come from the leaf only, because under PTI the kernel's copy of
/// a user PGD entry carries NX (arch/x86/mm/pti.c:157-159).
#[inline(always)]
fn child(e: u64) -> Option<Paddr> {
    if e & pte::PRESENT == 0 || e & pte::HUGE != 0 {
        None
    } else {
        Some((e & pte::ADDR_MASK) as Paddr)
    }
}

/// What a present leaf says.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Leaf {
    pub(crate) paddr: Paddr,
    pub(crate) flags: PageFlags,
}

fn leaf_of(e: u64) -> Option<Leaf> {
    if e & pte::PRESENT == 0 || e & pte::USER == 0 {
        return None;
    }
    let mut flags = PageFlags::R;
    if e & pte::WRITE != 0 {
        flags = flags | PageFlags::W;
    }
    if e & pte::NO_EXECUTE == 0 {
        flags = flags | PageFlags::X;
    }
    if e & pte::ACCESSED != 0 {
        flags = flags | PageFlags::ACCESSED;
    }
    if e & pte::DIRTY != 0 {
        flags = flags | PageFlags::DIRTY;
    }
    Some(Leaf {
        paddr: (e & pte::ADDR_MASK) as Paddr,
        flags,
    })
}

/// Walks the table at `root` for `va`. A leaf is returned only if every level
/// is present and the user's.
#[inline]
pub(crate) fn walk(root: Paddr, va: Vaddr) -> Option<Leaf> {
    if root == 0 {
        return None;
    }
    let mut node = root;
    for level in (2..=NR_LEVELS).rev() {
        node = child(read_entry(node, index(va, level)))?;
    }
    leaf_of(read_entry(node, index(va, 1)))
}

/// The first present leaf in `[va, end)`, skipping absent subtrees whole.
pub(crate) fn next_present(root: Paddr, va: Vaddr, end: Vaddr) -> Option<Vaddr> {
    let mut found = None;
    for_each_present_until(root, va, end, &mut |v, _| {
        found = Some(v);
        false
    });
    found
}

/// Calls `f` for every present leaf in `[va, end)`, in address order.
pub(crate) fn for_each_present(root: Paddr, va: Vaddr, end: Vaddr, f: &mut dyn FnMut(Vaddr, Leaf)) {
    for_each_present_until(root, va, end, &mut |v, l| {
        f(v, l);
        true
    });
}

fn for_each_present_until(
    root: Paddr,
    va: Vaddr,
    end: Vaddr,
    f: &mut dyn FnMut(Vaddr, Leaf) -> bool,
) {
    if root == 0 || va >= end {
        return;
    }
    visit(root, NR_LEVELS, 0, va, end, f);
}

/// Visits the part of `[va, end)` the table at `node` (covering from `base`)
/// maps. Returns false to stop.
fn visit(
    node: Paddr,
    level: u32,
    base: Vaddr,
    va: Vaddr,
    end: Vaddr,
    f: &mut dyn FnMut(Vaddr, Leaf) -> bool,
) -> bool {
    let size = level_size(level);
    let first = if va > base { (va - base) / size } else { 0 };
    let last = core::cmp::min(512, (end - base + size - 1) / size);
    for idx in first..last {
        let slot = base + idx * size;
        if slot >= end || (level == NR_LEVELS && slot >= super::MAX_USERSPACE_VADDR + PAGE_SIZE) {
            break;
        }
        let e = read_entry(node, idx);
        if level == 1 {
            if slot >= va {
                if let Some(leaf) = leaf_of(e) {
                    if !f(slot, leaf) {
                        return false;
                    }
                }
            }
        } else if let Some(next) = child(e) {
            if !visit(next, level - 1, slot, va, end, f) {
                return false;
            }
        }
    }
    true
}
