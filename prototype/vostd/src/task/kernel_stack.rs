// SPDX-License-Identifier: MPL-2.0

//! Kernelet stacks.
//!
//! Real OSTD maps a task's kernel stack in its own kernel virtual area, out of
//! frames it allocated, and flushes the TLB for it on the processor that is about
//! to run the task. Here the stack comes from the host, through the
//! `kstack_alloc` service — a `vmalloc` with the guard page `vmalloc` already
//! provides — so the host owns the mapping and there is no TLB work for the
//! kernelet to do.

use crate::{abi::svc, mm::Vaddr, prelude::*};

/// The kernelet stack size of a task, in pages, as real OSTD takes it: from the
/// environment at build time. The host's pool hands out stacks of exactly this
/// size, so the two numbers have to agree, and the build sets both.
const STACK_SIZE_IN_PAGES: usize =
    if let Some(size_str) = option_env!("OSTD_TASK_STACK_SIZE_IN_PAGES") {
        match usize::from_str_radix(size_str, 10) {
            Ok(size) => size,
            Err(_) => panic!(
                "The environment variable `OSTD_TASK_STACK_SIZE_IN_PAGES` \
                    specifies an invalid value"
            ),
        }
    } else {
        64
    };
const KERNEL_STACK_SIZE: usize = STACK_SIZE_IN_PAGES * crate::mm::PAGE_SIZE;

#[derive(Debug)]
pub(super) struct KernelStack {
    base: Vaddr,
    size: usize,
}

impl KernelStack {
    /// Allocates a kernelet stack with a guard page.
    pub(super) fn new_with_guard_page() -> Result<Self> {
        // SAFETY: the service returns a stack out of the sandbox's pool, or 0.
        let base = unsafe { (svc().kstack_alloc)() } as Vaddr;
        if base == 0 {
            return Err(crate::Error::NoMemory);
        }
        Ok(Self {
            base,
            size: KERNEL_STACK_SIZE,
        })
    }

    /// Nothing to do: the host owns the mapping and it is global.
    pub(super) fn flush_tlb(&self, _guard: &crate::irq::DisabledLocalIrqGuard) {}

    pub(super) fn end_vaddr(&self) -> Vaddr {
        self.base + self.size
    }

    /// The lowest address of the stack. Published in the vCPU record so that the
    /// endovisor knows how much room is left below an interrupted instruction
    /// before it pushes an upcall frame there.
    pub(super) fn base_vaddr(&self) -> Vaddr {
        self.base
    }
}

impl Drop for KernelStack {
    fn drop(&mut self) {
        // SAFETY: the stack came from `kstack_alloc` and nothing is on it: a task
        // is dropped only after `exit_current` has switched away from it. The host
        // returns it to the sandbox's pool rather than to `vmalloc`.
        unsafe { (svc().kstack_free)(self.base as u64) }
    }
}
