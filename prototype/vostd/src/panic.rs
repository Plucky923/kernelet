// SPDX-License-Identifier: MPL-2.0

//! Panic support.
//!
//! A panic in the kernelet is not a panic of the machine: it stops the
//! instance, which is `stop(PANIC)` on the host side.

use crate::power::ExitCode;

/// Aborts the kernelet.
pub fn abort() -> ! {
    crate::power::poweroff(ExitCode::Failure)
}

#[panic_handler]
fn panic_handler(info: &core::panic::PanicInfo) -> ! {
    // `early_println!` only takes a literal first argument, as in real OSTD.
    crate::console::early_print(format_args!("kernelet: panicked at {}\n", info.message()));
    if let Some(loc) = info.location() {
        crate::console::early_print(format_args!(
            "kernelet:   in {}:{}:{}\n",
            loc.file(),
            loc.line(),
            loc.column()
        ));
    }
    abort()
}
