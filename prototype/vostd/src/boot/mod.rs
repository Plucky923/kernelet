// SPDX-License-Identifier: MPL-2.0

//! Boot-time facilities.
//!
//! What a bootloader tells a machine, an endovisor tells a sandbox. The only part
//! of it this prototype carries is the command line, which the holder passes to
//! KLET_CREATE and is how the runtime tells one kernel proper which of several
//! scenarios to run — exactly as a kernel command line would.

pub mod smp;

use alloc::string::{String, ToString};

use crate::utils::Once;

/// The boot information provided by the host.
pub struct BootInfo {
    /// The kernel command line arguments.
    pub kernel_cmdline: String,
}

static INFO: Once<BootInfo> = Once::new();

/// Gets the boot information.
pub fn boot_info() -> &'static BootInfo {
    INFO.get().unwrap()
}

/// Records the command line. Called once, at entry, after the heap is up.
pub(crate) fn init(cmdline: &str) {
    INFO.call_once(|| BootInfo {
        kernel_cmdline: cmdline.to_string(),
    });
}
