// SPDX-License-Identifier: MPL-2.0

//! The architecture half of interrupt control.
//!
//! On bare metal these are `cli`, `sti` and a test of RFLAGS.IF. Here they are the
//! vCPU record's `irq_off` flag, which is what makes the endovisor leave a virtual
//! interrupt pending instead of delivering it, and which — mirrored into the host's
//! own preemption count — also stops the host preempting the carrier in the middle
//! of a critical section.

use crate::task::preempt::cpu_local;

/// Masks this virtual CPU's interrupts.
#[inline(always)]
pub(crate) fn disable_local() {
    cpu_local::irq_mask();
}

/// Unmasks this virtual CPU's interrupts, delivering anything that arrived.
#[inline(always)]
pub(crate) fn enable_local() {
    cpu_local::irq_unmask();
}

/// Whether this virtual CPU's interrupts are unmasked.
#[inline(always)]
pub(crate) fn is_local_enabled() -> bool {
    !cpu_local::irq_is_off()
}
