// SPDX-License-Identifier: MPL-2.0

//! Physical memory frames, handed out of the grant.
//!
//! The grant is one physically contiguous run of host pages, described in
//! [`BootArgs`]. It is all the physical memory the kernelet has. The allocator
//! is a bitmap.
//!
//! A frame carries a reference count, as real OSTD's do in their metadata
//! slot: a [`Frame`] handle is one counted reference, `Clone` takes another,
//! and the frame goes back to the allocator when the last one drops. That is
//! what `VmSpace` needs, because a mapping *is* a counted reference, held by
//! the page-table entry: `map` turns a handle into a raw entry with
//! [`Frame::into_raw`], `unmap` turns the entry back into a handle with
//! [`Frame::from_raw`], and `query` lends a [`FrameRef`]. The kernel proper's
//! copy-on-write reuses a frame in place when `reference_count() == 1`, so the
//! count has to be the tree's.
//!
//! [`BootArgs`]: crate::abi::BootArgs

use core::{
    marker::PhantomData,
    mem::ManuallyDrop,
    ops::Deref,
    sync::atomic::{AtomicU64, Ordering},
};

use super::Paddr;

/// Makes a structure usable as frame metadata.
///
/// Real OSTD stores the metadata in a per-frame slot. vOSTD stores only the
/// reference count: the only metadata the kernel propers here use is `()`.
pub trait AnyFrameMeta: Send + Sync + 'static {}

impl AnyFrameMeta for () {}

/// How many times [`Frame::from_raw`] checked a frame's ownership, for the
/// concurrency test.
pub(crate) static OWNER_CHECKS: AtomicU64 = AtomicU64::new(0);

/// A handle to a frame of the grant: one counted reference.
#[derive(Debug)]
pub struct Frame<M: AnyFrameMeta + ?Sized = ()> {
    paddr: Paddr,
    _marker: PhantomData<M>,
}

impl<M: AnyFrameMeta + ?Sized> Frame<M> {
    /// Takes over a reference that was turned into a raw address by
    /// [`Self::into_raw`], typically one a page-table entry held.
    ///
    /// The owner check: the frame must lie in the grant and be allocated, with
    /// at least the one reference being taken over. A stale entry (a frame
    /// already given back) fails it, loudly.
    #[track_caller]
    pub(crate) fn from_raw(paddr: Paddr) -> Self {
        OWNER_CHECKS.fetch_add(1, Ordering::Relaxed);
        allocator::note_from_raw(paddr, core::panic::Location::caller());
        let refs = allocator::refcount(paddr)
            .unwrap_or_else(|| {
                let (base, n) = allocator::bounds();
                panic!(
                    "Frame::from_raw({:#x}): not a frame of the grant [{:#x}, +{} frames)",
                    paddr, base, n
                )
            });
        assert!(
            refs > 0,
            "Frame::from_raw({:#x}): a stale frame, already given back",
            paddr
        );
        Self::from_raw_unchecked(paddr)
    }

    fn from_raw_unchecked(paddr: Paddr) -> Self {
        Self {
            paddr,
            _marker: PhantomData,
        }
    }

    /// Gives up the handle without dropping its reference.
    pub(crate) fn into_raw(self) -> Paddr {
        let paddr = self.paddr;
        core::mem::forget(self);
        paddr
    }

    /// The number of counted references to this frame.
    pub fn reference_count(&self) -> u64 {
        allocator::refcount(self.paddr).unwrap_or(0) as u64
    }

    /// Borrows a reference without counting it.
    pub fn borrow(&self) -> FrameRef<'_, M> {
        // SAFETY: the borrow does not outlive `self`, which holds a reference.
        unsafe { FrameRef::borrow_paddr(self.paddr) }
    }
}

impl<M: AnyFrameMeta + ?Sized> Clone for Frame<M> {
    fn clone(&self) -> Self {
        allocator::inc_ref(self.paddr);
        Self::from_raw_unchecked(self.paddr)
    }
}

impl<M: AnyFrameMeta + ?Sized> PartialEq for Frame<M> {
    fn eq(&self, other: &Self) -> bool {
        self.paddr == other.paddr
    }
}

impl<M: AnyFrameMeta + ?Sized> Eq for Frame<M> {}

impl<M: AnyFrameMeta + ?Sized> super::HasPaddr for Frame<M> {
    fn paddr(&self) -> Paddr {
        self.paddr
    }
}

impl<M: AnyFrameMeta + ?Sized> super::HasSize for Frame<M> {
    fn size(&self) -> usize {
        super::PAGE_SIZE
    }
}

impl<M: AnyFrameMeta + ?Sized> Drop for Frame<M> {
    fn drop(&mut self) {
        allocator::dec_ref(self.paddr);
    }
}

/// A borrowed reference to a frame: what real OSTD's `FrameRef` is. Lent by a
/// page table (`query`) for as long as the cursor is borrowed.
pub struct FrameRef<'a, M: AnyFrameMeta + ?Sized> {
    inner: ManuallyDrop<Frame<M>>,
    _marker: PhantomData<&'a Frame<M>>,
}

impl<M: AnyFrameMeta + ?Sized> FrameRef<'_, M> {
    /// # Safety
    ///
    /// Something must hold a counted reference to the frame at `paddr` for the
    /// borrow's whole lifetime.
    pub(crate) unsafe fn borrow_paddr(paddr: Paddr) -> Self {
        let refs = allocator::refcount(paddr).unwrap_or(0);
        assert!(refs > 0, "FrameRef of a free frame {:#x}", paddr);
        Self {
            inner: ManuallyDrop::new(Frame::from_raw_unchecked(paddr)),
            _marker: PhantomData,
        }
    }
}

impl<M: AnyFrameMeta + ?Sized> Deref for FrameRef<'_, M> {
    type Target = Frame<M>;

    fn deref(&self) -> &Self::Target {
        &self.inner
    }
}

impl<M: AnyFrameMeta + ?Sized> core::fmt::Debug for FrameRef<'_, M> {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("FrameRef").field("paddr", &self.inner.paddr).finish()
    }
}

// A frame's contents, through the direct map, as real OSTD's `VmIo` for frames.
impl<M: AnyFrameMeta + ?Sized> super::VmIo for Frame<M> {
    fn read(&self, offset: usize, writer: &mut super::VmWriter) -> crate::prelude::Result<()> {
        segment::read_at(self.paddr, super::PAGE_SIZE, offset, writer)
    }

    fn write(&self, offset: usize, reader: &mut super::VmReader) -> crate::prelude::Result<()> {
        segment::write_at(self.paddr, super::PAGE_SIZE, offset, reader)
    }
}

pub mod untyped {
    //! Untyped frames: frames that may be mapped into user space.

    use super::{AnyFrameMeta, Frame};

    /// Makes a structure usable as untyped frame metadata.
    pub trait AnyUFrameMeta: AnyFrameMeta {}

    impl AnyUFrameMeta for () {}

    /// A smart pointer to an untyped frame with any metadata.
    pub type UFrame = Frame<dyn AnyUFrameMeta>;

    impl<M: AnyUFrameMeta> From<Frame<M>> for UFrame {
        fn from(frame: Frame<M>) -> Self {
            Frame::from_raw_unchecked(frame.into_raw())
        }
    }
}

pub mod segment {
    //! Contiguous runs of frames.

    use core::{marker::PhantomData, ops::Range};

    use super::{allocator, AnyFrameMeta, Frame};
    use crate::{
        mm::{
            io::{Fallible, FallibleVmRead, FallibleVmWrite, VmIo, VmReader, VmWriter},
            paddr_to_vaddr, HasPaddr, HasSize, Paddr, PAGE_SIZE,
        },
        prelude::Result,
        Error,
    };

    /// A contiguous run of frames of the grant; holds one reference on each.
    #[derive(Debug)]
    pub struct Segment<M: AnyFrameMeta + ?Sized = ()> {
        pub(crate) range: Range<Paddr>,
        _marker: PhantomData<M>,
    }

    /// A contiguous run of untyped frames.
    pub type USegment = Segment<dyn super::untyped::AnyUFrameMeta>;

    impl<M: AnyFrameMeta + ?Sized> Segment<M> {
        pub(crate) fn from_range(range: Range<Paddr>) -> Self {
            Self {
                range,
                _marker: PhantomData,
            }
        }
    }

    impl<M: AnyFrameMeta + ?Sized> HasPaddr for Segment<M> {
        fn paddr(&self) -> Paddr {
            self.range.start
        }
    }

    impl<M: AnyFrameMeta + ?Sized> HasSize for Segment<M> {
        fn size(&self) -> usize {
            self.range.end - self.range.start
        }
    }

    impl<M: AnyFrameMeta + ?Sized> Iterator for Segment<M> {
        type Item = Frame<M>;

        fn next(&mut self) -> Option<Self::Item> {
            if self.range.start < self.range.end {
                // The segment's reference on this frame becomes the handle's.
                let frame = Frame::<M>::from_raw_unchecked(self.range.start);
                self.range.start += PAGE_SIZE;
                Some(frame)
            } else {
                None
            }
        }
    }

    impl<M: AnyFrameMeta + ?Sized> Drop for Segment<M> {
        fn drop(&mut self) {
            let mut p = self.range.start;
            while p < self.range.end {
                allocator::dec_ref(p);
                p += PAGE_SIZE;
            }
        }
    }

    pub(super) fn read_at(
        base: Paddr,
        size: usize,
        offset: usize,
        writer: &mut VmWriter,
    ) -> Result<()> {
        let len = writer.avail();
        if offset.checked_add(len).ok_or(Error::Overflow)? > size {
            return Err(Error::InvalidArgs);
        }
        // SAFETY: the range is inside frames the caller holds references to.
        let mut reader =
            unsafe { VmReader::<Fallible>::from_kernel_range(paddr_to_vaddr(base + offset), len) };
        writer
            .write_fallible(&mut reader)
            .map_err(|(err, _)| err)
            .map(|_| ())
    }

    pub(super) fn write_at(
        base: Paddr,
        size: usize,
        offset: usize,
        reader: &mut VmReader,
    ) -> Result<()> {
        let len = reader.remain();
        if offset.checked_add(len).ok_or(Error::Overflow)? > size {
            return Err(Error::InvalidArgs);
        }
        // SAFETY: as above.
        let mut writer =
            unsafe { VmWriter::<Fallible>::from_kernel_range(paddr_to_vaddr(base + offset), len) };
        reader
            .read_fallible(&mut writer)
            .map_err(|(err, _)| err)
            .map(|_| ())
    }

    // A segment is physically contiguous, so its linear-map alias is one run of
    // kernel virtual addresses and the copies need no page-by-page walk.
    impl<M: AnyFrameMeta + ?Sized> VmIo for Segment<M> {
        fn read(&self, offset: usize, writer: &mut VmWriter) -> Result<()> {
            read_at(self.range.start, self.size(), offset, writer)
        }

        fn write(&self, offset: usize, reader: &mut VmReader) -> Result<()> {
            write_at(self.range.start, self.size(), offset, reader)
        }
    }
}

pub mod allocator {
    //! The grant's bitmap frame allocator, and every frame's reference count.

    use core::{
        cell::UnsafeCell,
        sync::atomic::{AtomicBool, AtomicU32, AtomicUsize, Ordering},
    };

    use super::{segment::Segment, AnyFrameMeta, Frame};
    use crate::{
        mm::{paddr_to_vaddr, Paddr, PAGE_SIZE},
        prelude::Result,
        Error,
    };

    /// The largest grant the bitmap can describe: 4096 frames, 16 MiB.
    const MAX_FRAMES: usize = 4096;
    const WORDS: usize = MAX_FRAMES / 64;

    struct Bitmap(UnsafeCell<[u64; WORDS]>);

    // SAFETY: every access is inside the spin lock below.
    unsafe impl Sync for Bitmap {}

    static BITMAP: Bitmap = Bitmap(UnsafeCell::new([0; WORDS]));
    static LOCK: AtomicBool = AtomicBool::new(false);
    static BASE: AtomicUsize = AtomicUsize::new(0);
    static NFRAMES: AtomicUsize = AtomicUsize::new(0);
    /// Every frame's reference count. Zero means free.
    static REFS: [AtomicU32; MAX_FRAMES] = [const { AtomicU32::new(0) }; MAX_FRAMES];
    /// How many frames are allocated now, for the tests' leak checks.
    static IN_USE: AtomicUsize = AtomicUsize::new(0);

    struct Guard;

    impl Guard {
        fn lock() -> Self {
            while LOCK.swap(true, Ordering::Acquire) {
                core::hint::spin_loop();
            }
            Self
        }

        #[allow(clippy::mut_from_ref)]
        fn bits(&self) -> &mut [u64; WORDS] {
            // SAFETY: the lock is held for the lifetime of the guard, and there
            // is no other way to reach the bitmap.
            unsafe { &mut *BITMAP.0.get() }
        }
    }

    impl Drop for Guard {
        fn drop(&mut self) {
            LOCK.store(false, Ordering::Release);
        }
    }

    /// Records the grant and clears the bitmap.
    pub(crate) fn init(paddr: usize, len: usize) {
        let nframes = len / PAGE_SIZE;
        assert!(nframes > 0 && nframes <= MAX_FRAMES, "grant out of range");
        assert_eq!(paddr % PAGE_SIZE, 0, "grant is not page aligned");
        let guard = Guard::lock();
        guard.bits().fill(0);
        drop(guard);
        BASE.store(paddr, Ordering::Relaxed);
        NFRAMES.store(nframes, Ordering::Release);
    }

    fn index(paddr: Paddr) -> Option<usize> {
        let base = BASE.load(Ordering::Relaxed);
        let total = NFRAMES.load(Ordering::Acquire);
        if paddr < base || paddr % PAGE_SIZE != 0 {
            return None;
        }
        let i = (paddr - base) / PAGE_SIZE;
        if i < total {
            Some(i)
        } else {
            None
        }
    }

    /// The grant's base and size in frames, for diagnostics.
    pub(crate) fn bounds() -> (Paddr, usize) {
        (BASE.load(Ordering::Relaxed), NFRAMES.load(Ordering::Relaxed))
    }

    /// The frame's reference count, or `None` if it is not a frame of the grant.
    pub(crate) fn refcount(paddr: Paddr) -> Option<u32> {
        index(paddr).map(|i| REFS[i].load(Ordering::Acquire))
    }

    pub(crate) fn inc_ref(paddr: Paddr) {
        let i = index(paddr).expect("inc_ref of a frame outside the grant");
        let old = REFS[i].fetch_add(1, Ordering::Relaxed);
        assert!(old > 0, "a reference taken on a free frame {:#x}", paddr);
    }

    /// Where each frame's reference was last taken back from a page table, for
    /// the report of a reference dropped twice.
    static LAST_FROM_RAW: [core::sync::atomic::AtomicPtr<core::panic::Location<'static>>; MAX_FRAMES] =
        [const { core::sync::atomic::AtomicPtr::new(core::ptr::null_mut()) }; MAX_FRAMES];

    pub(crate) fn note_from_raw(paddr: Paddr, at: &'static core::panic::Location<'static>) {
        if let Some(i) = index(paddr) {
            LAST_FROM_RAW[i].store(at as *const _ as *mut _, Ordering::Relaxed);
        }
    }

    pub(crate) fn dec_ref(paddr: Paddr) {
        let Some(i) = index(paddr) else { return };
        let old = REFS[i].fetch_sub(1, Ordering::Release);
        if old == 0 {
            let at = LAST_FROM_RAW[i].load(Ordering::Relaxed);
            if at.is_null() {
                panic!("a reference dropped on a free frame {:#x} (never taken back from a table)", paddr);
            }
            // SAFETY: only `&'static Location`s are stored.
            let at = unsafe { &*at };
            panic!("a reference dropped on a free frame {:#x}; last taken back from a table at {}", paddr, at);
        }
        if old == 1 {
            core::sync::atomic::fence(Ordering::Acquire);
            dealloc(paddr, 1);
        }
    }

    /// How many frames of the grant are allocated.
    pub fn frames_in_use() -> usize {
        IN_USE.load(Ordering::Relaxed)
    }

    fn test(bits: &[u64; WORDS], i: usize) -> bool {
        bits[i / 64] & (1u64 << (i % 64)) != 0
    }

    /// Allocates `nframes` contiguous frames, first fit, each with one
    /// reference.
    pub(crate) fn alloc(nframes: usize) -> Option<Paddr> {
        let total = NFRAMES.load(Ordering::Acquire);
        if nframes == 0 || nframes > total {
            return None;
        }
        let guard = Guard::lock();
        let bits = guard.bits();
        let mut start = 0;
        'outer: while start + nframes <= total {
            for i in start..start + nframes {
                if test(bits, i) {
                    start = i + 1;
                    continue 'outer;
                }
            }
            for i in start..start + nframes {
                bits[i / 64] |= 1u64 << (i % 64);
                REFS[i].store(1, Ordering::Relaxed);
            }
            IN_USE.fetch_add(nframes, Ordering::Relaxed);
            return Some(BASE.load(Ordering::Relaxed) + start * PAGE_SIZE);
        }
        None
    }

    /// Returns `nframes` frames starting at `paddr` to the allocator.
    fn dealloc(paddr: Paddr, nframes: usize) {
        let Some(start) = index(paddr) else { return };
        let total = NFRAMES.load(Ordering::Acquire);
        if start + nframes > total {
            return;
        }
        let guard = Guard::lock();
        let bits = guard.bits();
        for i in start..start + nframes {
            bits[i / 64] &= !(1u64 << (i % 64));
        }
        IN_USE.fetch_sub(nframes, Ordering::Relaxed);
    }

    fn zero(paddr: Paddr, nframes: usize) {
        // SAFETY: the run was just allocated out of the grant, so its linear-map
        // alias is valid for writes of `nframes` pages.
        unsafe {
            core::ptr::write_bytes(paddr_to_vaddr(paddr) as *mut u8, 0, nframes * PAGE_SIZE)
        };
    }

    /// Options for allocating physical memory frames.
    pub struct FrameAllocOptions {
        zeroed: bool,
    }

    impl Default for FrameAllocOptions {
        fn default() -> Self {
            Self::new()
        }
    }

    impl FrameAllocOptions {
        /// Creates new options for allocating frames.
        pub fn new() -> Self {
            Self { zeroed: true }
        }

        /// Sets whether the allocated frames should be initialized with zeros.
        pub fn zeroed(&mut self, zeroed: bool) -> &mut Self {
            self.zeroed = zeroed;
            self
        }

        /// Allocates a single untyped frame without metadata.
        pub fn alloc_frame(&self) -> Result<Frame<()>> {
            self.alloc_frame_with(())
        }

        /// Allocates a single frame with additional metadata.
        pub fn alloc_frame_with<M: AnyFrameMeta>(&self, _metadata: M) -> Result<Frame<M>> {
            let paddr = alloc(1).ok_or(Error::NoMemory)?;
            if self.zeroed {
                zero(paddr, 1);
            }
            Ok(Frame::from_raw_unchecked(paddr))
        }

        /// Allocates a contiguous range of frames.
        pub fn alloc_segment(&self, nframes: usize) -> Result<Segment<()>> {
            self.alloc_segment_with(nframes, |_| ())
        }

        /// Allocates a contiguous range of frames with additional metadata.
        pub fn alloc_segment_with<M: AnyFrameMeta, F>(
            &self,
            nframes: usize,
            _metadata_fn: F,
        ) -> Result<Segment<M>>
        where
            F: FnMut(Paddr) -> M,
        {
            if nframes == 0 {
                return Err(Error::InvalidArgs);
            }
            let paddr = alloc(nframes).ok_or(Error::NoMemory)?;
            if self.zeroed {
                zero(paddr, nframes);
            }
            Ok(Segment::from_range(paddr..paddr + nframes * PAGE_SIZE))
        }
    }
}
