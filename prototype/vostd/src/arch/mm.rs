// SPDX-License-Identifier: MPL-2.0

//! The paging system of x86-64, and what this virtual CPU has activated.

use crate::mm::{Paddr, PagingConstsTrait, PagingLevel};

/// The constants of the 4-level x86-64 paging system.
#[derive(Clone, Debug)]
pub(crate) struct PagingConsts {}

impl PagingConstsTrait for PagingConsts {
    const BASE_PAGE_SIZE: usize = 4096;
    const NR_LEVELS: PagingLevel = 4;
    const HIGHEST_TRANSLATION_LEVEL: PagingLevel = 1;
    const PTE_SIZE: usize = 8;
    const ADDRESS_WIDTH: usize = 48;
    const VA_SIGN_EXT: bool = true;
}

/// Returns what this virtual CPU has activated: the id of a `VmSpace`, or 0.
///
/// Per virtual CPU, exactly as real OSTD's `current_page_table_paddr()` is per
/// processor: a plain read of the vCPU record, which the activate service wrote.
pub(crate) fn current_page_table_paddr() -> Paddr {
    if !crate::vcpu::is_up() {
        return 0;
    }
    // SAFETY: the field belongs to this vCPU's record.
    unsafe { core::ptr::read_volatile(crate::vcpu::vrec().space.get()) as Paddr }
}
