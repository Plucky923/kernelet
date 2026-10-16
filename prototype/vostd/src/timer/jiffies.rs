// SPDX-License-Identifier: MPL-2.0

//! Jiffies, real OSTD's unit of the tick, computed here from the clock (see
//! [`Jiffies::elapsed`]).

use core::time::Duration;

use super::TIMER_FREQ;

/// Jiffies is a term used to denote the units of time measurement by the kernel.
///
/// A jiffy is one tick of the system timer, whose frequency is [`TIMER_FREQ`] Hz.
///
/// Unlike real OSTD, `elapsed` is derived from the cycle counter rather than from
/// a count of ticks, because a virtual CPU the host has descheduled receives no
/// ticks and would otherwise believe that no time had passed.
#[derive(Clone, Copy, Debug)]
pub struct Jiffies(u64);

impl Jiffies {
    /// The maximum value of [`Jiffies`].
    pub const MAX: Self = Self(u64::MAX);

    /// Creates a new instance.
    pub fn new(value: u64) -> Self {
        Self(value)
    }

    /// Returns the elapsed time since the sandbox started.
    pub fn elapsed() -> Self {
        Self::new(crate::time::now_ns() * TIMER_FREQ / 1_000_000_000)
    }

    /// Gets the number of jiffies.
    pub fn as_u64(self) -> u64 {
        self.0
    }

    /// Adds the given number of jiffies, saturating at [`Jiffies::MAX`].
    pub fn add(&mut self, jiffies: u64) {
        self.0 = self.0.saturating_add(jiffies);
    }

    /// Gets the [`Duration`] calculated from the jiffies counts.
    pub fn as_duration(self) -> Duration {
        let secs = self.0 / TIMER_FREQ;
        let nanos = ((self.0 % TIMER_FREQ) * 1_000_000_000) / TIMER_FREQ;
        Duration::new(secs, nanos as u32)
    }
}

impl From<Jiffies> for Duration {
    fn from(value: Jiffies) -> Self {
        value.as_duration()
    }
}
