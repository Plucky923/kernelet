// SPDX-License-Identifier: MPL-2.0

//! Virtual memory (VM).

pub(crate) mod backend;
pub mod frame;
pub mod heap;
pub mod io;
pub(crate) mod page_prop;
pub(crate) mod page_table;
pub(crate) mod rcu;
pub mod tlb;
pub mod vm_space;

use core::fmt::Debug;

pub use self::{
    frame::{
        allocator::FrameAllocOptions,
        segment::{Segment, USegment},
        untyped::{AnyUFrameMeta, UFrame},
        Frame, FrameRef,
    },
    io::{
        Fallible, FallibleVmRead, FallibleVmWrite, Infallible, VmIo, VmReader, VmWriter,
    },
    page_prop::{CachePolicy, PageFlags, PageProperty},
    vm_space::{Cursor, CursorMut, VmQueriedItem, VmSpace},
};
use crate::arch::mm::PagingConsts;

/// Virtual addresses.
pub type Vaddr = usize;

/// Physical addresses.
pub type Paddr = usize;

/// The end of the user-space virtual address range, exclusive.
pub const MAX_USERSPACE_VADDR: Vaddr = 0x0000_8000_0000_0000 - PAGE_SIZE;

/// Returns whether `vaddr` and `len` specify a user-space virtual address range.
pub fn is_in_user_space(vaddr: Vaddr, len: usize) -> bool {
    vaddr.saturating_add(len) <= MAX_USERSPACE_VADDR
}

/// The level of a page table node or a frame.
pub type PagingLevel = u8;

/// A minimal set of constants that determines the paging system.
///
/// Only `BASE_PAGE_SIZE` is read here; the rest are the shape real OSTD gives
/// the trait, and the page-table walk hard-codes the four-level x86-64 one.
#[allow(dead_code)]
pub(crate) trait PagingConstsTrait: Clone + Debug + Send + Sync + 'static {
    /// The smallest page size.
    const BASE_PAGE_SIZE: usize;
    /// The number of levels in the page table.
    const NR_LEVELS: PagingLevel;
    /// The highest level that a PTE can be directly used to translate a VA.
    const HIGHEST_TRANSLATION_LEVEL: PagingLevel;
    /// The size of a PTE.
    const PTE_SIZE: usize;
    /// The address width.
    const ADDRESS_WIDTH: usize;
    /// Whether virtual addresses are sign-extended.
    const VA_SIGN_EXT: bool;
}

/// The page size.
pub const PAGE_SIZE: usize = PagingConsts::BASE_PAGE_SIZE;

/// A trait for objects that have a physical address.
pub trait HasPaddr {
    /// Returns the physical address.
    fn paddr(&self) -> Paddr;
}

/// A trait for objects that have a size.
pub trait HasSize {
    /// Returns the size in bytes.
    fn size(&self) -> usize;
}

/// Maps a physical address to the host's linear-map alias of it.
///
/// This is the only way the kernelet ever touches tenant memory: through the
/// direct map, never through a user virtual address.
#[inline]
pub(crate) fn paddr_to_vaddr(paddr: Paddr) -> usize {
    crate::abi::linear_map_base() + paddr
}
