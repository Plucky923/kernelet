// SPDX-License-Identifier: MPL-2.0

//! Wait queues. The code is real OSTD's at `ab9a4cfdc`, verbatim but for the
//! order of one `use` list and without its `#[ktest]` module; most of its doc
//! comments are not carried over, and the memory-order reasoning in the
//! original's holds unchanged.

use alloc::{collections::VecDeque, sync::Arc};
use core::sync::atomic::{AtomicBool, AtomicU32, Ordering};

use super::{LocalIrqDisabled, SpinLock};
use crate::task::{scheduler, Task};

/// A wait queue.
///
/// One may wait on a wait queue to put its executing thread to sleep.
pub struct WaitQueue {
    // A copy of `wakers.len()`, used for the lock-free fast path.
    num_wakers: AtomicU32,
    wakers: SpinLock<VecDeque<Arc<Waker>>, LocalIrqDisabled>,
}

impl WaitQueue {
    /// Creates a new, empty wait queue.
    pub const fn new() -> Self {
        WaitQueue {
            num_wakers: AtomicU32::new(0),
            wakers: SpinLock::new(VecDeque::new()),
        }
    }

    /// Waits until some condition is met.
    #[track_caller]
    pub fn wait_until<F, R>(&self, mut cond: F) -> R
    where
        F: FnMut() -> Option<R>,
    {
        if let Some(res) = cond() {
            return res;
        }

        let (waiter, _) = Waiter::new_pair();
        let cond = || {
            self.enqueue(waiter.waker());
            cond()
        };
        waiter
            .wait_until_or_cancelled(cond, || Ok::<(), ()>(()))
            .unwrap()
    }

    /// Wakes up one waiting thread, if there is one.
    pub fn wake_one(&self) -> bool {
        if self.is_empty() {
            return false;
        }

        loop {
            let mut wakers = self.wakers.lock();
            let Some(waker) = wakers.pop_front() else {
                return false;
            };
            self.num_wakers.fetch_sub(1, Ordering::Release);
            drop(wakers);

            if waker.wake_up() {
                return true;
            }
        }
    }

    /// Wakes up all waiting threads, returning how many were woken.
    pub fn wake_all(&self) -> usize {
        if self.is_empty() {
            return 0;
        }

        let mut num_woken = 0;

        loop {
            let mut wakers = self.wakers.lock();
            let Some(waker) = wakers.pop_front() else {
                break;
            };
            self.num_wakers.fetch_sub(1, Ordering::Release);
            drop(wakers);

            if waker.wake_up() {
                num_woken += 1;
            }
        }

        num_woken
    }

    fn is_empty(&self) -> bool {
        self.num_wakers.fetch_add(0, Ordering::Release) == 0
    }

    /// Enqueues the input [`Waker`] to the wait queue.
    #[doc(hidden)]
    pub fn enqueue(&self, waker: Arc<Waker>) {
        let mut wakers = self.wakers.lock();
        wakers.push_back(waker);
        self.num_wakers.fetch_add(1, Ordering::Acquire);
    }
}

impl Default for WaitQueue {
    fn default() -> Self {
        Self::new()
    }
}

/// A waiter that can put the current thread to sleep until it is woken up by the
/// associated [`Waker`].
pub struct Waiter {
    waker: Arc<Waker>,
}

impl !Send for Waiter {}
impl !Sync for Waiter {}

/// A waker that can wake up the associated [`Waiter`].
pub struct Waker {
    has_woken: AtomicBool,
    task: Arc<Task>,
}

impl Waiter {
    /// Creates a waiter and its associated [`Waker`].
    pub fn new_pair() -> (Self, Arc<Waker>) {
        let waker = Arc::new(Waker {
            has_woken: AtomicBool::new(false),
            task: Task::current().unwrap().cloned(),
        });
        let waiter = Self {
            waker: waker.clone(),
        };
        (waiter, waker)
    }

    /// Waits until the waiter is woken up.
    #[track_caller]
    pub fn wait(&self) {
        self.waker.do_wait();
    }

    /// Waits until some condition is met or the cancel condition becomes true.
    #[track_caller]
    pub fn wait_until_or_cancelled<F, R, FCancel, E>(
        &self,
        mut cond: F,
        cancel_cond: FCancel,
    ) -> Result<R, E>
    where
        F: FnMut() -> Option<R>,
        FCancel: Fn() -> Result<(), E>,
    {
        loop {
            if let Some(res) = cond() {
                return Ok(res);
            };

            if let Err(e) = cancel_cond() {
                self.waker.close();
                return cond().ok_or(e);
            }

            self.wait();
        }
    }

    /// Gets the associated [`Waker`] of the current waiter.
    pub fn waker(&self) -> Arc<Waker> {
        self.waker.clone()
    }

    /// Returns the task that the associated waker will attempt to wake up.
    pub fn task(&self) -> &Arc<Task> {
        &self.waker.task
    }
}

impl Drop for Waiter {
    fn drop(&mut self) {
        self.waker.close();
    }
}

impl Waker {
    /// Wakes up the associated [`Waiter`].
    pub fn wake_up(&self) -> bool {
        if self.has_woken.swap(true, Ordering::Release) {
            return false;
        }
        scheduler::unpark_target(self.task.clone());

        true
    }

    #[track_caller]
    fn do_wait(&self) {
        while !self.has_woken.swap(false, Ordering::Acquire) {
            scheduler::park_current(|| self.has_woken.load(Ordering::Acquire));
        }
    }

    fn close(&self) {
        let _ = self.has_woken.swap(true, Ordering::Acquire);
    }
}
