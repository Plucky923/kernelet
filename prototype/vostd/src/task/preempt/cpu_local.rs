// SPDX-License-Identifier: MPL-2.0

//! The preemption word and the virtual interrupt flag of the current virtual CPU.
//!
//! Real OSTD keeps the preemption word in one 32-bit CPU-local integer:
//!
//! * bits 0 to 30 are `guard_count`, the number of guards the current CPU holds;
//! * bit 31 is `!need_preempt`.
//!
//! so that the task on a CPU should be preempted exactly when the integer is
//! zero. vOSTD keeps the same word, with the same layout, in the **vCPU record**
//! rather than in CPU-local storage, for two reasons:
//!
//! 1. the endovisor reads it; and
//! 2. every update must be a single read-modify-write instruction, because a
//!    virtual interrupt may arrive between a load and a store and the handler
//!    touches the same word. That is exactly why real OSTD uses `add %gs:…`.
//!
//! # A guard and the interrupt flag
//!
//! On bare metal a preemption guard does not stop the processor taking an
//! interrupt; it only forbids the task switch. The record keeps the two apart
//! as well: the guard count above, and `irq_off`, the virtual interrupt flag,
//! inverted. But the endovisor redirects into the upcall only outside a
//! critical section, with no guard held *and* `irq_off` clear, because it
//! cannot tell whether the upcall will want to switch tasks. An interrupt that
//! arrives under a guard stays pending, and the drop of the last guard
//! delivers it (`dec_guard_count`), so a kernelet holding a spin lock gets its
//! ticks late, never not at all.
//!
//! # The mirror
//!
//! What the host must defer an involuntary preemption for is *either* of those:
//! the kernelet is in a critical section when it holds a guard **or** has its
//! interrupts masked. So the host's own per-processor preemption count is raised
//! by exactly one on the transition out of "not critical" and lowered on the
//! transition back — never more, whatever the nesting, because the host's count
//! has only eight bits for it and 256 nested guards would spill into its
//! soft-interrupt field.
//!
//! The order of the two updates is what keeps it race-free against an upcall:
//! going in, the record is made critical *before* the host's count is raised, so
//! the endovisor never sees a non-critical kernelet whose count is already up;
//! coming out, the host's count is lowered *before* the record is made
//! non-critical, for the same reason in reverse.

use core::arch::asm;

use crate::vcpu;

const NEED_PREEMPT_MASK: u32 = 1 << 31;
const GUARD_COUNT_MASK: u32 = (1 << 31) - 1;

/// The initial value: no guards, no preemption wanted.
pub(crate) const PREEMPT_INFO_INIT: u32 = NEED_PREEMPT_MASK;

#[inline(always)]
fn word() -> *mut u32 {
    vcpu::vrec().preempt_info.get()
}

#[inline(always)]
fn irq_word() -> *mut u32 {
    vcpu::vrec().irq_off.get()
}

#[inline(always)]
fn load() -> u32 {
    if !vcpu::is_up() {
        return PREEMPT_INFO_INIT;
    }
    // SAFETY: the word belongs to this vCPU's record.
    unsafe { core::ptr::read_volatile(word()) }
}

macro_rules! one_instruction_rmw {
    ($name:ident, $op:literal) => {
        #[inline(always)]
        fn $name(value: u32) {
            if !vcpu::is_up() {
                return;
            }
            // SAFETY: one aligned read-modify-write of this vCPU's own word.
            unsafe {
                asm!(
                    concat!($op, " dword ptr [{p}], {v:e}"),
                    p = in(reg) word(),
                    v = in(reg) value,
                    options(nostack),
                );
            }
        }
    };
}

one_instruction_rmw!(add_assign, "add");
one_instruction_rmw!(sub_assign, "sub");
one_instruction_rmw!(bitand_assign, "and");
one_instruction_rmw!(bitor_assign, "or");

/// Whether this vCPU's interrupts are masked.
#[inline(always)]
pub(crate) fn irq_is_off() -> bool {
    if !vcpu::is_up() {
        return false;
    }
    // SAFETY: the field belongs to this vCPU's record.
    unsafe { core::ptr::read_volatile(irq_word()) != 0 }
}

/// Sets or clears the virtual interrupt flag. A plain aligned store: the only
/// other writer is the endovisor, and it only writes a 1 when the flag is 0.
#[inline(always)]
pub(crate) fn set_irq_off(off: bool) {
    if !vcpu::is_up() {
        return;
    }
    // SAFETY: as above.
    unsafe { core::ptr::write_volatile(irq_word(), if off { 1 } else { 0 }) }
}

/// The kernelet is in a critical section: it holds a guard, or its interrupts
/// are masked, or both.
#[inline(always)]
pub(crate) fn in_critical_section() -> bool {
    get_guard_count() != 0 || irq_is_off()
}

/// Returns whether the current task _should_ be preempted or not.
pub(crate) fn should_preempt() -> bool {
    load() == 0 && !irq_is_off()
}

pub(crate) fn need_preempt() -> bool {
    load() & NEED_PREEMPT_MASK == 0
}

pub(crate) fn set_need_preempt() {
    bitand_assign(!NEED_PREEMPT_MASK);
}

pub(crate) fn clear_need_preempt() {
    bitor_assign(NEED_PREEMPT_MASK);
}

pub(crate) fn get_guard_count() -> u32 {
    load() & GUARD_COUNT_MASK
}

/// Takes a preemption guard.
#[inline(always)]
pub(crate) fn inc_guard_count() {
    let was_critical = in_critical_section();
    add_assign(1);
    if !was_critical {
        vcpu::host_preempt_inc();
    }
}

/// Drops a preemption guard.
#[inline(always)]
pub(crate) fn dec_guard_count() {
    debug_assert!(get_guard_count() > 0);
    let leaving = get_guard_count() == 1 && !irq_is_off();

    let host_wants_cpu = if leaving {
        vcpu::host_preempt_dec_and_test()
    } else {
        false
    };
    sub_assign(1);

    if host_wants_cpu {
        vcpu::host_yield();
    }
    if leaving {
        vcpu::deliver_if_pending();
    }
}

/// Masks this vCPU's interrupts. Called only when they were unmasked.
#[inline(always)]
pub(crate) fn irq_mask() {
    let was_critical = in_critical_section();
    set_irq_off(true);
    if !was_critical {
        vcpu::host_preempt_inc();
    }
}

/// Unmasks this vCPU's interrupts and delivers anything that arrived.
#[inline(always)]
pub(crate) fn irq_unmask() {
    let leaving = get_guard_count() == 0;

    let host_wants_cpu = if leaving {
        vcpu::host_preempt_dec_and_test()
    } else {
        false
    };
    set_irq_off(false);

    if host_wants_cpu {
        vcpu::host_yield();
    }
    if leaving {
        vcpu::deliver_if_pending();
    }
}
