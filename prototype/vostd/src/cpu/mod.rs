// SPDX-License-Identifier: MPL-2.0

//! CPU-related definitions. A "CPU" here is one of the sandbox's virtual CPUs.

pub mod local;

use core::sync::atomic::{AtomicU32, Ordering};

pub use self::local::{AtomicCpuSet, CpuSet};
use crate::task::atomic_mode::InAtomicMode;

/// The largest number of virtual CPUs a sandbox may have in this prototype.
pub const MAX_CPUS: usize = 8;

static NUM_CPUS: AtomicU32 = AtomicU32::new(1);

/// The ID of a virtual CPU in the sandbox.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CpuId(u32);

impl CpuId {
    /// Creates a new instance.
    ///
    /// # Panics
    ///
    /// The given number must be smaller than [`num_cpus`].
    pub fn new(raw_id: u32) -> Self {
        assert!(raw_id < num_cpus() as u32);
        Self(raw_id)
    }

    /// Returns the ID of the bootstrap processor, which is always zero.
    pub const fn bsp() -> Self {
        Self(0)
    }

    /// Returns the ID of the current virtual CPU.
    ///
    /// Safe to call but vulnerable to races: the current OSTD task may migrate.
    /// To be sure, call it under a guard that implements [`PinCurrentCpu`].
    pub fn current_racy() -> Self {
        Self(crate::vcpu::current_id())
    }

    /// The raw index.
    pub const fn as_usize(self) -> usize {
        self.0 as usize
    }
}

impl From<CpuId> for u32 {
    fn from(cpu_id: CpuId) -> Self {
        cpu_id.0
    }
}

/// The error type returned when converting an out-of-range integer to [`CpuId`].
#[derive(Clone, Copy, Debug)]
pub struct CpuIdFromIntError;

impl TryFrom<usize> for CpuId {
    type Error = CpuIdFromIntError;

    fn try_from(raw_id: usize) -> Result<Self, Self::Error> {
        if raw_id < num_cpus() {
            Ok(Self(raw_id as u32))
        } else {
            Err(CpuIdFromIntError)
        }
    }
}

/// Returns the number of virtual CPUs.
pub fn num_cpus() -> usize {
    NUM_CPUS.load(Ordering::Relaxed) as usize
}

/// Returns an iterator over all virtual CPUs.
pub fn all_cpus() -> impl Iterator<Item = CpuId> {
    (0..num_cpus() as u32).map(CpuId)
}

/// Records how many virtual CPUs the sandbox has. Called once, at entry.
pub(crate) fn init(nr: usize) {
    assert!(nr >= 1 && nr <= MAX_CPUS);
    NUM_CPUS.store(nr as u32, Ordering::Relaxed);
}

/// A marker trait for guard types that "pin" the current task to the current
/// virtual CPU.
///
/// # Safety
///
/// The implementor must ensure that the current task is pinned to the current
/// virtual CPU while any instance exists.
pub unsafe trait PinCurrentCpu {
    /// Returns the ID of the current virtual CPU.
    fn current_cpu(&self) -> CpuId {
        CpuId::current_racy()
    }
}

// SAFETY: a guard that enforces the atomic mode masks virtual interrupts and
// raises the host's preemption count, so the carrier is neither preempted by the
// kernelet's scheduler nor involuntarily by the host's.
unsafe impl<T: InAtomicMode> PinCurrentCpu for T {}
unsafe impl PinCurrentCpu for dyn InAtomicMode + '_ {}

/// The CPU privilege level.
#[repr(u8)]
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub enum PrivilegeLevel {
    /// User mode.
    User = 0,
    /// Kernel mode.
    Kernel = 1,
}
