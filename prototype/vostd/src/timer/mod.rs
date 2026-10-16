// SPDX-License-Identifier: MPL-2.0

//! The timer support.
//!
//! Ported from real OSTD. The tick is the endovisor's per-processor watch timer,
//! delivered to the kernelet as a TICK virtual interrupt, so a virtual CPU that
//! the host has descheduled gets no ticks at all. That is why [`Jiffies`] is
//! *computed from the clock* here rather than counted: a scheduler that counted
//! ticks would think a descheduled vCPU had stopped time.

mod jiffies;

use alloc::{boxed::Box, vec::Vec};
use core::cell::RefCell;

pub use jiffies::Jiffies;

use crate::{cpu_local, irq};

/// The timer frequency in Hz.
pub const TIMER_FREQ: u64 = 1000;

type InterruptCallback = Box<dyn Fn() + Sync + Send>;

cpu_local! {
    static INTERRUPT_CALLBACKS: RefCell<Vec<InterruptCallback>> = RefCell::new(Vec::new());
}

/// Registers a function to be executed on every tick of the current CPU.
pub fn register_callback_on_cpu<F>(func: F)
where
    F: Fn() + Sync + Send + 'static,
{
    let irq_guard = irq::disable_local();
    INTERRUPT_CALLBACKS
        .get_with(&irq_guard)
        .borrow_mut()
        .push(Box::new(func));
}

/// Runs this virtual CPU's tick callbacks. Called from the virtual-interrupt
/// upcall, which is this machine's timer interrupt.
pub(crate) fn call_timer_callback_functions() {
    let irq_guard = irq::disable_local();

    let callbacks_guard = INTERRUPT_CALLBACKS.get_with(&irq_guard);
    // A callback may itself want the list (it must not), so failure to borrow is
    // silent rather than a panic in an interrupt handler.
    if let Ok(callbacks) = callbacks_guard.try_borrow() {
        for callback in callbacks.iter() {
            (callback)();
        }
    }
}
