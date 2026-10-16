// SPDX-License-Identifier: MPL-2.0

//! Local interrupt control, and where in the machine we are.
//!
//! A kernelet cannot disable the host processor's interrupts, and must not: the
//! host's timer, its IPIs and its device interrupts are none of the sandbox's
//! business. What the kernelet disables is its *own* interrupts, the virtual
//! ones the endovisor delivers, which is a depth in the vCPU record — the same
//! depth a preemption guard raises. So on a virtual CPU "interrupts disabled"
//! and "preemption disabled" really are one state, and this module is a thin
//! second face on [`crate::task::preempt`].

use crate::{sync::GuardTransfer, task::atomic_mode::InAtomicMode};

/// Disables this virtual CPU's interrupts.
///
/// Returns a guard that re-enables them when dropped, correctly when nested.
#[track_caller]
pub fn disable_local() -> DisabledLocalIrqGuard {
    DisabledLocalIrqGuard::new()
}

/// Diagnostics: who last masked each vCPU's interrupts.
pub(crate) static LAST_MASK: [core::sync::atomic::AtomicPtr<core::panic::Location<'static>>;
    crate::cpu::MAX_CPUS] =
    [const { core::sync::atomic::AtomicPtr::new(core::ptr::null_mut()) }; crate::cpu::MAX_CPUS];

pub(crate) fn last_mask() -> Option<&'static core::panic::Location<'static>> {
    let v = crate::cpu::CpuId::current_racy().as_usize();
    let p = LAST_MASK[v].load(core::sync::atomic::Ordering::Relaxed);
    // SAFETY: only `&'static Location`s are stored.
    if p.is_null() { None } else { Some(unsafe { &*p }) }
}

/// A guard for disabled virtual interrupts.
#[clippy::has_significant_drop]
#[must_use]
#[derive(Debug)]
pub struct DisabledLocalIrqGuard {
    was_enabled: bool,
}

impl !Send for DisabledLocalIrqGuard {}

// SAFETY: the guard masks this vCPU's virtual interrupts, which meets the first
// sufficient condition for atomic mode.
unsafe impl InAtomicMode for DisabledLocalIrqGuard {}

impl DisabledLocalIrqGuard {
    #[track_caller]
    fn new() -> Self {
        let was_enabled = crate::arch::irq::is_local_enabled();
        if was_enabled {
            crate::arch::irq::disable_local();
            let v = crate::cpu::CpuId::current_racy().as_usize();
            LAST_MASK[v].store(
                core::panic::Location::caller() as *const _ as *mut _,
                core::sync::atomic::Ordering::Relaxed,
            );
        }
        Self { was_enabled }
    }
}

impl GuardTransfer for DisabledLocalIrqGuard {
    fn transfer_to(&mut self) -> Self {
        let was_enabled = self.was_enabled;
        self.was_enabled = false;
        Self { was_enabled }
    }
}

impl Drop for DisabledLocalIrqGuard {
    fn drop(&mut self) {
        if self.was_enabled {
            crate::arch::irq::enable_local();
        }
    }
}

/// Where in the machine the current code is running.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InterruptLevel {
    /// Ordinary task (or bootstrap) context.
    Task,
    /// Inside a virtual-interrupt upcall.
    Interrupt,
}

impl InterruptLevel {
    /// The level of the code calling this.
    pub fn current() -> Self {
        if crate::vcpu::in_upcall() {
            Self::Interrupt
        } else {
            Self::Task
        }
    }

    /// Whether this is ordinary task context.
    pub fn is_task_context(&self) -> bool {
        *self == Self::Task
    }
}
