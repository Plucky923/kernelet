// SPDX-License-Identifier: MPL-2.0

//! The clock.
//!
//! The cycle counter is an unprivileged instruction and the sandbox's own view of
//! it is as good as anyone's, so vOSTD reads it directly rather than through a
//! service: a scheduler that timestamps every context switch cannot afford a call
//! into the host for each one. The endovisor publishes the counter's frequency in
//! the boot arguments, and a zero frequency (a host without an invariant counter)
//! turns every reading into zero rather than into nonsense.

use core::sync::atomic::{AtomicU64, Ordering};

static TSC_KHZ: AtomicU64 = AtomicU64::new(0);
static TSC_ORIGIN: AtomicU64 = AtomicU64::new(0);

/// Records the counter's frequency. Called once, at entry.
pub(crate) fn init(tsc_khz: u64) {
    TSC_KHZ.store(tsc_khz, Ordering::Relaxed);
    TSC_ORIGIN.store(read_tsc(), Ordering::Relaxed);
}

/// Reads the cycle counter.
#[inline(always)]
pub fn read_tsc() -> u64 {
    let lo: u32;
    let hi: u32;
    // SAFETY: `rdtsc` has no operands and no side effects.
    unsafe {
        core::arch::asm!(
            "rdtsc",
            out("eax") lo,
            out("edx") hi,
            options(nomem, nostack, preserves_flags),
        );
    }
    ((hi as u64) << 32) | (lo as u64)
}

/// The counter's frequency in kHz, or 0 if the host did not say.
pub fn tsc_khz() -> u64 {
    TSC_KHZ.load(Ordering::Relaxed)
}

/// Nanoseconds since the sandbox started.
#[inline]
pub fn now_ns() -> u64 {
    let khz = TSC_KHZ.load(Ordering::Relaxed);
    if khz == 0 {
        return 0;
    }
    let cycles = read_tsc().wrapping_sub(TSC_ORIGIN.load(Ordering::Relaxed));
    // cycles / (khz / 1e6) nanoseconds, without overflowing for hours of uptime.
    (cycles / khz) * 1_000_000 + ((cycles % khz) * 1_000_000) / khz
}

