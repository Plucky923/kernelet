// SPDX-License-Identifier: MPL-2.0

//! Starting the sandbox's other virtual CPUs.
//!
//! The shape is real OSTD's: the kernel proper registers an entry function for
//! the application processors and OSTD brings them up. Here "bringing up a
//! processor" is the `vcpu_boot` service, which lets the carrier of that vCPU into
//! the image at `vcpu_entry`; it then waits here until the entry function has been
//! registered, calls it, and falls into the idle loop.

use crate::{
    cpu::num_cpus,
    utils::Once,
};

static AP_ENTRY: Once<fn()> = Once::new();

/// Registers the entry function of every virtual CPU other than the first, and
/// starts them.
///
/// Call this after injecting a scheduler: an application processor that reached
/// the scheduler first would instantiate the default one and make
/// [`crate::task::scheduler::inject_scheduler`] panic.
pub fn register_ap_entry(entry: fn()) {
    AP_ENTRY.call_once(|| entry);
    for id in 1..num_cpus() as u32 {
        crate::vcpu::boot(id);
    }
}

/// Waits for the entry function and runs it. Called from `vcpu_entry`.
pub(crate) fn run_ap_entry() {
    // The carrier only gets here because the kernel proper called
    // `register_ap_entry`, which sets this first.
    if let Some(entry) = AP_ENTRY.get() {
        entry();
    }
}
