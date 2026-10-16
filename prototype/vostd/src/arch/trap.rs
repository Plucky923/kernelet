// SPDX-License-Identifier: MPL-2.0

//! The raw user context, which is also the shape the endovisor copies to and
//! from `task_pt_regs(current)`.

use super::cpu::context::GeneralRegs;

/// Userspace context.
///
/// On bare metal the trailing fields are filled in by the trap handler from the
/// hardware. Here the endovisor fills them in from Linux's `struct pt_regs` and
/// its page-fault information. `fault_addr` is an addition to real OSTD's
/// layout, which reads CR2 instead.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RawUserContext {
    pub(crate) general: GeneralRegs,
    pub(crate) trap_num: usize,
    pub(crate) error_code: usize,
    pub(crate) fault_addr: usize,
}

impl RawUserContext {
    /// Enters user mode and returns the reason it came back: 0 a system call,
    /// 1 an exception, 2 an event.
    pub(crate) fn run(&mut self) -> u64 {
        // There is nothing to save around the call: what the carrier carries is
        // a virtual CPU, and the current OSTD task of that vCPU is OSTD's own
        // per-CPU state, which the carrier keeps across a trip to user mode.
        crate::sync::r2::assert_no_spin_lock("user_run");
        // SAFETY: the service is given a valid context to read and write.
        unsafe { (crate::abi::svc().user_run)(self) }
    }
}
