// SPDX-License-Identifier: MPL-2.0

//! The small pieces vOSTD would otherwise take from a crates.io dependency.
//!
//! Real OSTD uses `spin::Once`. vOSTD depends on nothing but `core`, `alloc` and
//! the real `ostd-macros`, so here is the same thing, spin-initialised.

use core::{
    cell::UnsafeCell,
    mem::MaybeUninit,
    sync::atomic::{AtomicU32, Ordering},
};

const EMPTY: u32 = 0;
const RUNNING: u32 = 1;
const DONE: u32 = 2;

/// A cell that is initialised at most once.
pub struct Once<T> {
    state: AtomicU32,
    value: UnsafeCell<MaybeUninit<T>>,
}

// SAFETY: the value is published with release/acquire ordering and never changed
// after that.
unsafe impl<T: Send + Sync> Sync for Once<T> {}
unsafe impl<T: Send> Send for Once<T> {}

impl<T> Once<T> {
    /// Creates an empty cell.
    pub const fn new() -> Self {
        Self {
            state: AtomicU32::new(EMPTY),
            value: UnsafeCell::new(MaybeUninit::uninit()),
        }
    }

    /// Returns the value, initialising it with `f` if it is empty.
    ///
    /// Exactly one caller runs `f`; the others spin until it finishes.
    pub fn call_once<F: FnOnce() -> T>(&self, f: F) -> &T {
        if self.state.load(Ordering::Acquire) == DONE {
            // SAFETY: the value is initialised and never changes.
            return unsafe { (*self.value.get()).assume_init_ref() };
        }

        if self
            .state
            .compare_exchange(EMPTY, RUNNING, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
        {
            let value = f();
            // SAFETY: this caller won the race, so nothing else touches the slot.
            unsafe { (*self.value.get()).write(value) };
            self.state.store(DONE, Ordering::Release);
        } else {
            while self.state.load(Ordering::Acquire) != DONE {
                core::hint::spin_loop();
            }
        }

        // SAFETY: the value is initialised.
        unsafe { (*self.value.get()).assume_init_ref() }
    }

    /// Returns the value if it has been initialised.
    pub fn get(&self) -> Option<&T> {
        if self.state.load(Ordering::Acquire) == DONE {
            // SAFETY: the value is initialised.
            Some(unsafe { (*self.value.get()).assume_init_ref() })
        } else {
            None
        }
    }

}
