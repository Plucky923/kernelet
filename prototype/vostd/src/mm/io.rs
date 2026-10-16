// SPDX-License-Identifier: MPL-2.0

//! Abstractions for reading and writing virtual memory (VM) objects.
//!
//! The one structural difference from real OSTD: a *fallible* reader or writer
//! over tenant memory does not hold a user virtual address that the kernel then
//! dereferences with `stac`/`clac` and an exception table. It holds the page
//! table's root and a user virtual address, and every copy walks the table in
//! vOSTD and goes through the linear-map alias of each frame. Tenant memory is
//! therefore never dereferenced through a user address, and a translation
//! failure is a plain `None` rather than a trap.
//!
//! The table walked is the tenant process's Linux page table, and each chunk's
//! walk and copy run inside an RCU read section ([`super::rcu`]): a copy takes
//! no cursor, so an `unmap` on
//! another virtual CPU may clear the entry it walked, and the frame is then
//! released only after the grace period, by which time the copy is done.

use core::marker::PhantomData;

use super::{paddr_to_vaddr, page_table, Paddr, Vaddr, PAGE_SIZE};
use crate::{prelude::Result, Error};

/// A marker type for infallible memory accesses (kernel memory).
pub struct Infallible;

/// A marker type for fallible memory accesses (tenant memory).
pub struct Fallible;

/// Where the bytes are.
#[derive(Clone, Copy)]
enum Region {
    /// A run of host kernel virtual addresses; always the linear map here.
    Kernel { cursor: usize, end: usize },
    /// A run of tenant virtual addresses, to be walked through the page table
    /// whose root is `root`.
    User {
        root: Paddr,
        cursor: Vaddr,
        end: Vaddr,
    },
}

impl Region {
    fn remain(&self) -> usize {
        match *self {
            Region::Kernel { cursor, end } => end - cursor,
            Region::User { cursor, end, .. } => end - cursor,
        }
    }

    /// Resolves the head of the region to a host virtual address and the number
    /// of bytes that are contiguous there.
    fn resolve(&self, write: bool) -> Option<(*mut u8, usize)> {
        match *self {
            Region::Kernel { cursor, end } => Some((cursor as *mut u8, end - cursor)),
            Region::User { root, cursor, end } => {
                let leaf = page_table::walk(root, cursor & !(PAGE_SIZE - 1))?;
                if write && !leaf.flags.contains(super::PageFlags::W) {
                    return None;
                }
                let paddr = leaf.paddr;
                let offset = cursor % PAGE_SIZE;
                let len = (PAGE_SIZE - offset).min(end - cursor);
                // The alias of the byte the cursor is at, not of the frame's
                // base: a chunk may start in the middle of a page.
                Some(((paddr_to_vaddr(paddr) + offset) as *mut u8, len))
            }
        }
    }

    fn advance(&mut self, n: usize) {
        match self {
            Region::Kernel { cursor, .. } => *cursor += n,
            Region::User { cursor, .. } => *cursor += n,
        }
    }
}

/// Copies `n` bytes with `rep movsb`, which the compiler cannot see through.
///
/// Tenant memory may change under the copy (another virtual CPU's tenant
/// thread, or a frame an unmap is about to release), so a plain
/// `copy_nonoverlapping` is a data race the optimizer may exploit: it is free to
/// serve a later load from the destination by loading the source again, after
/// the read section has ended. OSTD copies user memory with an
/// assembly routine for the same reason.
///
/// # Safety
///
/// `dst` must be valid for writes and `src` for reads of `n` bytes.
#[inline]
unsafe fn copy_opaque(dst: *mut u8, src: *const u8, n: usize) {
    // SAFETY: the caller's; the direction flag is clear, as the ABI promises.
    unsafe {
        core::arch::asm!(
            "rep movsb",
            inout("rcx") n => _,
            inout("rdi") dst => _,
            inout("rsi") src => _,
            options(nostack, preserves_flags),
        );
    }
}

/// Copies from `src` to `dst`, up to the smaller of the two remainders.
///
/// Returns the number of bytes copied and whether a translation failed before
/// the copy was complete.
fn copy_regions(dst: &mut Region, src: &mut Region) -> (usize, bool) {
    let total = dst.remain().min(src.remain());
    let mut copied = 0;

    let user = matches!(dst, Region::User { .. }) || matches!(src, Region::User { .. });
    while copied < total {
        let left = total - copied;
        let step = |dst: &Region, src: &Region| -> Option<usize> {
            let (dptr, dlen) = dst.resolve(true)?;
            let (sptr, slen) = src.resolve(false)?;
            let n = dlen.min(slen).min(left);
            // SAFETY: both pointers are linear-map aliases of frames that stay
            // allocated for the read section (a frame an unmap removes waits for
            // the grace period), valid for `n` bytes; the two regions do not
            // overlap: one of them is always a kernel buffer in this prototype.
            unsafe { copy_opaque(dptr, sptr as *const u8, n) };
            Some(n)
        };
        let done = if user {
            super::rcu::read(|| step(dst, src))
        } else {
            step(dst, src)
        };
        let Some(n) = done else {
            return (copied, false);
        };
        dst.advance(n);
        src.advance(n);
        copied += n;
    }

    (copied, true)
}

/// Fallible memory read from a `VmReader` to a `VmWriter`.
pub trait FallibleVmRead<F> {
    /// Reads all data into the writer.
    ///
    /// On success, the number of bytes read is returned; on error, both the
    /// error and the number of bytes read so far are returned.
    fn read_fallible(&mut self, writer: &mut VmWriter<'_, F>) -> Result<usize, (Error, usize)>;
}

/// Fallible memory write from a `VmReader`.
pub trait FallibleVmWrite<F> {
    /// Writes all data from the reader.
    fn write_fallible(&mut self, reader: &mut VmReader<'_, F>) -> Result<usize, (Error, usize)>;
}

/// A trait that enables reading/writing data from/to a VM object.
pub trait VmIo {
    /// Reads requested data at a specified offset into a given `VmWriter`.
    fn read(&self, offset: usize, writer: &mut VmWriter) -> Result<()>;

    /// Writes data from a given `VmReader` at a specified offset.
    fn write(&self, offset: usize, reader: &mut VmReader) -> Result<()>;

    /// Reads a specified number of bytes at a specified offset into a buffer.
    fn read_bytes(&self, offset: usize, buf: &mut [u8]) -> Result<()> {
        let mut writer = VmWriter::from(buf).to_fallible();
        self.read(offset, &mut writer)
    }

    /// Writes a specified number of bytes from a buffer at a specified offset.
    fn write_bytes(&self, offset: usize, buf: &[u8]) -> Result<()> {
        let mut reader = VmReader::from(buf).to_fallible();
        self.write(offset, &mut reader)
    }
}

/// `VmReader` is a reader for reading data from a contiguous range of memory.
pub struct VmReader<'a, Fallibility = Fallible> {
    region: Region,
    phantom: PhantomData<(&'a [u8], Fallibility)>,
}

impl<Fallibility> Clone for VmReader<'_, Fallibility> {
    fn clone(&self) -> Self {
        Self {
            region: self.region,
            phantom: PhantomData,
        }
    }
}

impl<'a, Fallibility> VmReader<'a, Fallibility> {
    /// Constructs a reader over a run of host kernel virtual addresses.
    ///
    /// # Safety
    ///
    /// The range must be valid for reads for the whole lifetime `'a`.
    pub(crate) unsafe fn from_kernel_range(vaddr: usize, len: usize) -> Self {
        Self {
            region: Region::Kernel {
                cursor: vaddr,
                end: vaddr + len,
            },
            phantom: PhantomData,
        }
    }

    /// Returns the number of bytes for the remaining data.
    pub fn remain(&self) -> usize {
        self.region.remain()
    }

    /// Returns if it has remaining data to read.
    pub fn has_remain(&self) -> bool {
        self.remain() > 0
    }
}

impl<'a> VmReader<'a, Infallible> {
    /// Constructs a `VmReader` from a pointer and a length in kernel space.
    ///
    /// # Safety
    ///
    /// `ptr` must be valid for reads of `len` bytes for the lifetime `'a`.
    pub unsafe fn from_kernel_space(ptr: *const u8, len: usize) -> Self {
        Self::from_kernel_range(ptr as usize, len)
    }

    /// Converts to a fallible reader.
    pub fn to_fallible(self) -> VmReader<'a, Fallible> {
        VmReader {
            region: self.region,
            phantom: PhantomData,
        }
    }
}

impl VmReader<'_, Fallible> {
    /// Constructs a reader over tenant memory, to be walked through `root`.
    ///
    /// # Safety
    ///
    /// `root` must be the root of a page table of one of this kernelet's spaces, and
    /// `vaddr..vaddr + len` must be a user-space range.
    pub(crate) unsafe fn from_space(root: Paddr, vaddr: Vaddr, len: usize) -> Self {
        Self {
            region: Region::User {
                root,
                cursor: vaddr,
                end: vaddr + len,
            },
            phantom: PhantomData,
        }
    }
}

impl<'a> From<&'a [u8]> for VmReader<'a, Infallible> {
    fn from(slice: &'a [u8]) -> Self {
        // SAFETY: the slice outlives `'a` and is plain-old-data.
        unsafe { Self::from_kernel_space(slice.as_ptr(), slice.len()) }
    }
}

/// `VmWriter` is a writer for writing data to a contiguous range of memory.
pub struct VmWriter<'a, Fallibility = Fallible> {
    region: Region,
    phantom: PhantomData<(&'a mut [u8], Fallibility)>,
}

impl<'a, Fallibility> VmWriter<'a, Fallibility> {
    /// Constructs a writer over a run of host kernel virtual addresses.
    ///
    /// # Safety
    ///
    /// The range must be valid for writes for the whole lifetime `'a`.
    pub(crate) unsafe fn from_kernel_range(vaddr: usize, len: usize) -> Self {
        Self {
            region: Region::Kernel {
                cursor: vaddr,
                end: vaddr + len,
            },
            phantom: PhantomData,
        }
    }

    /// Returns the number of bytes for the available space.
    pub fn avail(&self) -> usize {
        self.region.remain()
    }

    /// Returns if it has available space to write.
    pub fn has_avail(&self) -> bool {
        self.avail() > 0
    }
}

impl<'a> VmWriter<'a, Infallible> {
    /// Constructs a `VmWriter` from a pointer and a length in kernel space.
    ///
    /// # Safety
    ///
    /// `ptr` must be valid for writes of `len` bytes for the lifetime `'a`.
    pub unsafe fn from_kernel_space(ptr: *mut u8, len: usize) -> Self {
        Self::from_kernel_range(ptr as usize, len)
    }

    /// Converts to a fallible writer.
    pub fn to_fallible(self) -> VmWriter<'a, Fallible> {
        VmWriter {
            region: self.region,
            phantom: PhantomData,
        }
    }
}

impl VmWriter<'_, Fallible> {
    /// Constructs a writer over tenant memory, to be walked through `root`.
    ///
    /// # Safety
    ///
    /// As [`VmReader::from_space`].
    pub(crate) unsafe fn from_space(root: Paddr, vaddr: Vaddr, len: usize) -> Self {
        Self {
            region: Region::User {
                root,
                cursor: vaddr,
                end: vaddr + len,
            },
            phantom: PhantomData,
        }
    }
}

impl<'a> From<&'a mut [u8]> for VmWriter<'a, Infallible> {
    fn from(slice: &'a mut [u8]) -> Self {
        // SAFETY: the slice outlives `'a`, is exclusively borrowed and is
        // plain-old-data.
        unsafe { Self::from_kernel_space(slice.as_mut_ptr(), slice.len()) }
    }
}

macro_rules! impl_read_fallible {
    ($reader_fallibility:ty, $writer_fallibility:ty) => {
        impl FallibleVmRead<$writer_fallibility> for VmReader<'_, $reader_fallibility> {
            fn read_fallible(
                &mut self,
                writer: &mut VmWriter<'_, $writer_fallibility>,
            ) -> Result<usize, (Error, usize)> {
                let (copied, complete) = copy_regions(&mut writer.region, &mut self.region);
                if complete {
                    Ok(copied)
                } else {
                    Err((Error::PageFault, copied))
                }
            }
        }
    };
}

macro_rules! impl_write_fallible {
    ($writer_fallibility:ty, $reader_fallibility:ty) => {
        impl FallibleVmWrite<$reader_fallibility> for VmWriter<'_, $writer_fallibility> {
            fn write_fallible(
                &mut self,
                reader: &mut VmReader<'_, $reader_fallibility>,
            ) -> Result<usize, (Error, usize)> {
                reader.read_fallible(self)
            }
        }
    };
}

impl_read_fallible!(Fallible, Infallible);
impl_read_fallible!(Fallible, Fallible);
impl_read_fallible!(Infallible, Fallible);
impl_write_fallible!(Fallible, Infallible);
impl_write_fallible!(Fallible, Fallible);
impl_write_fallible!(Infallible, Fallible);
