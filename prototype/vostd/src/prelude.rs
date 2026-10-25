// SPDX-License-Identifier: MPL-2.0

//! The prelude, real OSTD's: the crate's `Result` and the `alloc` types every
//! module uses.

/// A specialized [`Result`] type for this crate.
///
/// [`Result`]: core::result::Result
pub type Result<T, E = crate::error::Error> = core::result::Result<T, E>;

#[allow(unused_imports)]
pub(crate) use alloc::{boxed::Box, string::String, sync::Arc, vec::Vec};

pub use crate::{
    console_print as print, console_println as println,
    mm::{HasPaddr, HasSize, Paddr, Vaddr},
    panic::abort,
};
