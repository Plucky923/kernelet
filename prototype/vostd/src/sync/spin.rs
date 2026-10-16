// SPDX-License-Identifier: MPL-2.0

//! A spin lock. Ported from real OSTD, with one addition: after a long spin the
//! slow path tells the endovisor, because on a virtual CPU the holder may be a
//! vCPU the host has descheduled and no amount of spinning will help.

use core::{
    cell::UnsafeCell,
    fmt,
    marker::PhantomData,
    ops::{Deref, DerefMut},
    sync::atomic::{AtomicBool, AtomicU64, Ordering},
};

use super::{guard::SpinGuardian, LocalIrqDisabled, PreemptDisabled};
use crate::task::atomic_mode::AsAtomicModeGuard;

/// How many failed acquisitions make it worth asking the host to run whichever
/// sibling vCPU holds the lock.
const SPINS_BEFORE_ON_SPIN: u32 = 1000;

/// How many times any spin lock in this kernelet reached that point, for the
/// report.
pub(crate) static ON_SPIN_COUNT: AtomicU64 = AtomicU64::new(0);

/// A spin lock.
///
/// # Guard behavior
///
/// The type `G` specifies the guard behavior of the spin lock. While holding the
/// lock,
/// - if `G` is [`PreemptDisabled`], preemption is disabled;
/// - if `G` is [`LocalIrqDisabled`], local (virtual) interrupts are disabled.
#[repr(transparent)]
pub struct SpinLock<T: ?Sized, G = PreemptDisabled> {
    phantom: PhantomData<G>,
    /// Only the last field of a struct may have a dynamically sized type.
    inner: SpinLockInner<T>,
}

struct SpinLockInner<T: ?Sized> {
    lock: AtomicBool,
    val: UnsafeCell<T>,
}

impl<T, G> SpinLock<T, G> {
    /// Creates a new spin lock.
    pub const fn new(val: T) -> Self {
        let lock_inner = SpinLockInner {
            lock: AtomicBool::new(false),
            val: UnsafeCell::new(val),
        };
        Self {
            phantom: PhantomData,
            inner: lock_inner,
        }
    }
}

impl<T: ?Sized> SpinLock<T, PreemptDisabled> {
    /// Converts the guard behavior from disabling preemption to disabling IRQs.
    pub fn disable_irq(&self) -> &SpinLock<T, LocalIrqDisabled> {
        let ptr = self as *const SpinLock<T, PreemptDisabled>;
        let ptr = ptr as *const SpinLock<T, LocalIrqDisabled>;
        // SAFETY: the two types have the same layout, guaranteed by
        // `#[repr(transparent)]`.
        unsafe { &*ptr }
    }
}

impl<T: ?Sized, G: SpinGuardian> SpinLock<T, G> {
    /// Acquires the spin lock.
    #[track_caller]
    pub fn lock(&self) -> SpinLockGuard<'_, T, G> {
        // Notice the guard must be created before acquiring the lock.
        let inner_guard = G::guard();
        self.acquire_lock();
        r2::held_inc();
        SpinLockGuard {
            guard: inner_guard,
            lock: self,
        }
    }

    /// Tries acquiring the spin lock immediately.
    pub fn try_lock(&self) -> Option<SpinLockGuard<'_, T, G>> {
        let inner_guard = G::guard();
        if self.try_acquire_lock() {
            r2::held_inc();
            let lock_guard = SpinLockGuard {
                guard: inner_guard,
                lock: self,
            };
            return Some(lock_guard);
        }
        None
    }

    /// Returns a mutable reference to the underlying data.
    pub fn get_mut(&mut self) -> &mut T {
        self.inner.val.get_mut()
    }

    /// Acquires the spin lock, otherwise busy waiting.
    ///
    /// The one difference from real OSTD: a long spin on a virtual CPU means the
    /// holder may not be running at all, because the host descheduled its
    /// carrier. Spinning cannot fix that, so the endovisor is asked to run a
    /// sibling vCPU instead. Until it is, this is still an ordinary spin, so
    /// correctness does not depend on the service doing anything.
    fn acquire_lock(&self) {
        let mut spins: u32 = 0;
        while !self.try_acquire_lock() {
            core::hint::spin_loop();
            spins += 1;
            if spins == SPINS_BEFORE_ON_SPIN {
                spins = 0;
                ON_SPIN_COUNT.fetch_add(1, Ordering::Relaxed);
                crate::vcpu::on_spin();
            }
        }
    }

    fn try_acquire_lock(&self) -> bool {
        self.inner
            .lock
            .compare_exchange(false, true, Ordering::Acquire, Ordering::Relaxed)
            .is_ok()
    }

    fn release_lock(&self) {
        self.inner.lock.store(false, Ordering::Release);
    }
}

impl<T: ?Sized + fmt::Debug, G> fmt::Debug for SpinLock<T, G> {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        fmt::Debug::fmt(&self.inner.val, f)
    }
}

// SAFETY: only a single lock holder is permitted to access the inner data.
unsafe impl<T: ?Sized + Send, G> Send for SpinLock<T, G> {}
unsafe impl<T: ?Sized + Send, G> Sync for SpinLock<T, G> {}

impl<T: ?Sized + fmt::Debug> fmt::Debug for SpinLockInner<T> {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("SpinLockInner")
    }
}

/// A guard that provides exclusive access to the data protected by a
/// [`SpinLock`].
#[clippy::has_significant_drop]
#[must_use]
pub struct SpinLockGuard<'a, T: ?Sized, G: SpinGuardian> {
    guard: G::Guard,
    lock: &'a SpinLock<T, G>,
}

impl<T: ?Sized, G: SpinGuardian> AsAtomicModeGuard for SpinLockGuard<'_, T, G> {
    fn as_atomic_mode_guard(&self) -> &dyn crate::task::atomic_mode::InAtomicMode {
        self.guard.as_atomic_mode_guard()
    }
}

impl<T: ?Sized, G: SpinGuardian> Deref for SpinLockGuard<'_, T, G> {
    type Target = T;

    fn deref(&self) -> &T {
        // SAFETY: the lock is held.
        unsafe { &*self.lock.inner.val.get() }
    }
}

impl<T: ?Sized, G: SpinGuardian> DerefMut for SpinLockGuard<'_, T, G> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        // SAFETY: the lock is held.
        unsafe { &mut *self.lock.inner.val.get() }
    }
}

impl<T: ?Sized, G: SpinGuardian> Drop for SpinLockGuard<'_, T, G> {
    fn drop(&mut self) {
        self.lock.release_lock();
        r2::held_dec();
    }
}

impl<T: ?Sized + fmt::Debug, G: SpinGuardian> fmt::Debug for SpinLockGuard<'_, T, G> {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        fmt::Debug::fmt(&**self, f)
    }
}

impl<T: ?Sized, G: SpinGuardian> !Send for SpinLockGuard<'_, T, G> {}

// SAFETY: `SpinLockGuard` can be shared between tasks on the same virtual CPU.
unsafe impl<T: ?Sized + Sync, G: SpinGuardian> Sync for SpinLockGuard<'_, T, G> {}

/// The sleeping contract, called R2 in the messages it panics with: a service
/// that may sleep in the host must not be called while this virtual CPU holds
/// a kernelet spin lock or has its interrupts off, because the carrier takes
/// the virtual CPU to sleep with it, and a sibling spinning on that lock would
/// spin for as long as the host keeps it asleep. The count is of spin-lock
/// guards only, private to vOSTD and
/// separate from the guard count the shared record publishes: a plain
/// preemption guard, an RCU read section or the range lock does not count.
pub(crate) mod r2 {
    crate::cpu_local_cell! {
        static SPIN_HELD: u32 = 0;
    }

    /// Called with the lock's guard (which pins the vCPU) already taken.
    #[inline(always)]
    pub(crate) fn held_inc() {
        if crate::vcpu::is_up() {
            SPIN_HELD.store(SPIN_HELD.load() + 1);
        }
    }

    #[inline(always)]
    pub(crate) fn held_dec() {
        if crate::vcpu::is_up() {
            let n = SPIN_HELD.load();
            SPIN_HELD.store(n.saturating_sub(1));
        }
    }

    /// How many spin locks this virtual CPU holds.
    pub(crate) fn held() -> u32 {
        if crate::vcpu::is_up() {
            SPIN_HELD.load()
        } else {
            0
        }
    }

    /// `user_run`'s check: it counts as a sleeping service, but real OSTD's
    /// `execute` enters user mode with interrupts disabled and a kernel proper
    /// may do the same, so only the spin-lock count is checked.
    #[inline]
    #[track_caller]
    pub(crate) fn assert_no_spin_lock(service: &str) {
        let held = held();
        if held != 0 {
            panic!(
                "R2 violated: {} was called holding {} kernelet spin lock(s)",
                service, held
            );
        }
    }

    /// The stub-side check of every sleeping service: panics the kernelet
    /// (which stops it with the panic code) if R2 is broken.
    #[inline]
    #[track_caller]
    pub(crate) fn assert_may_sleep(service: &str) {
        let held = held();
        let irq_off = crate::vcpu::is_up() && crate::task::preempt::cpu_local::irq_is_off();
        if held != 0 || irq_off {
            panic!(
                "R2 violated: the sleeping service {} was called holding {} kernelet spin lock(s){}",
                service,
                held,
                if irq_off { " with interrupts off" } else { "" }
            );
        }
    }
}