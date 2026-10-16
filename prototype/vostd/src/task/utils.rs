// SPDX-License-Identifier: MPL-2.0

//! A helper of real OSTD's task module, ported unchanged.

use alloc::fmt;

/// Always [`Sync`], but unsafe to reference the data.
pub(super) struct ForceSync<T>(T);

impl<T> fmt::Debug for ForceSync<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ForceSync").finish_non_exhaustive()
    }
}

// SAFETY: the caller of `ForceSync::get` must ensure that the data is not
// accessed concurrently if the underlying type is not `Sync`.
unsafe impl<T> Sync for ForceSync<T> {}

impl<T> ForceSync<T> {
    pub(super) fn new(data: T) -> Self {
        Self(data)
    }

    /// # Safety
    ///
    /// If the data type is not [`Sync`], the caller must ensure that the data is
    /// not accessed concurrently.
    pub(super) unsafe fn get(&self) -> &T {
        &self.0
    }
}
