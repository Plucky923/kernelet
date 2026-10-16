// SPDX-License-Identifier: MPL-2.0

//! Virtual memory space management.
//!
//! A `VmSpace` *is* the tenant process's Linux address space. Its page table
//! is Linux's, written only by the endovisor's `vm_*` services and read here
//! through the direct map; vOSTD keeps no page table of its own.
//!
//! What vOSTD adds on top of the host's page table:
//!
//! - the **range lock** that the tree's cursor gets from its page-table node
//!   locks, and that the kernel proper relies on: 64-bit words striped by
//!   2 MiB region, `CursorMut` exclusive and `Cursor` shared, one
//!   compare-and-swap uncontended and `vm_wait`/`vm_wake` when contended;
//! - the **withheld set** of pages mapped without read permission, which a
//!   Linux page table cannot express and which therefore have no host entry at
//!   all;
//! - frame references held by the entries (`into_raw` after a successful map,
//!   `from_raw` when an unmap reads the entry back), and their release after
//!   the flush and an RCU grace period;
//! - the **retire list** of dropped spaces, drained where sleeping is
//!   allowed, because the last reference can go inside the post-schedule
//!   handler with interrupts off.

use alloc::{boxed::Box, collections::BTreeMap, sync::Arc, vec::Vec};
use core::{
    ops::Range,
    sync::atomic::{AtomicBool, AtomicPtr, AtomicU64, Ordering},
};

use super::{
    backend::Backend,
    frame::{untyped::AnyUFrameMeta, FrameRef},
    io::{Fallible, VmReader, VmWriter},
    is_in_user_space, page_table,
    tlb::{FlushTarget, TlbFlusher},
    CachePolicy, PageFlags, PageProperty, Paddr, UFrame, Vaddr, MAX_USERSPACE_VADDR, PAGE_SIZE,
};
use crate::{
    abi,
    arch::mm::current_page_table_paddr,
    prelude::Result,
    sync::SpinLock,
    task::{atomic_mode::AsAtomicModeGuard, disable_preempt, DisabledPreemptGuard},
    Error,
};

// ---------------------------------------------------------------------------
// The test hook and the counters (read through `crate::klet`)
// ---------------------------------------------------------------------------

/// The contended-cursor test: every map carries the endovisor's test-sleep
/// bit, so that a cursor's holder sleeps inside `vm_map` and another virtual
/// CPU's cursor over the same range has to take the range lock's slow path.
pub(crate) static MAP_TEST_SLEEP: AtomicBool = AtomicBool::new(false);

pub(crate) static LOCK_CAS_RETRIES: AtomicU64 = AtomicU64::new(0);
pub(crate) static LOCK_WAITS: AtomicU64 = AtomicU64::new(0);
pub(crate) static RETIRED: AtomicU64 = AtomicU64::new(0);
pub(crate) static DRAINED: AtomicU64 = AtomicU64::new(0);
pub(crate) static WITHHELD_IN: AtomicU64 = AtomicU64::new(0);
pub(crate) static WITHHELD_OUT: AtomicU64 = AtomicU64::new(0);

// ---------------------------------------------------------------------------
// The range lock
// ---------------------------------------------------------------------------

const WRITER: u64 = 1 << 63;
const WAITERS: u64 = 1 << 62;
/// New readers defer to a waiting writer, so that a writer cannot starve.
const WRITER_WAITING: u64 = 1 << 61;
const READERS: u64 = WRITER_WAITING - 1;
const STRIPE_SHIFT: usize = 21; // 2 MiB
const NR_WORDS: usize = abi::SPACE_LOCK_WORDS;

/// The distinct words a range covers, as a bit mask. A 2 MiB region maps to a
/// word by its index modulo the array, so regions alias; the words are taken
/// in ascending *word* order, which is a total order, where ascending address
/// order with aliasing is not.
fn stripe_mask(range: &Range<Vaddr>) -> u32 {
    let first = range.start >> STRIPE_SHIFT;
    let last = (range.end - 1) >> STRIPE_SHIFT;
    if last - first + 1 >= NR_WORDS {
        return (1u32 << NR_WORDS) - 1;
    }
    let mut mask = 0u32;
    for r in first..=last {
        mask |= 1 << (r % NR_WORDS);
    }
    mask
}

impl VmSpace {
    fn lock_word(&self, idx: usize, exclusive: bool) {
        let w = &self.backend().words()[idx];
        loop {
            let cur = w.load(Ordering::Acquire);
            let free = if exclusive {
                cur & (WRITER | READERS) == 0
            } else {
                cur & (WRITER | WRITER_WAITING) == 0
            };
            if free {
                let new = if exclusive {
                    (cur | WRITER) & !WRITER_WAITING
                } else {
                    cur + 1
                };
                if w
                    .compare_exchange(cur, new, Ordering::Acquire, Ordering::Relaxed)
                    .is_ok()
                {
                    return;
                }
                LOCK_CAS_RETRIES.fetch_add(1, Ordering::Relaxed);
                continue;
            }
            // Contended: say so in the word, then sleep in the host until it
            // changes. Nothing spins.
            let want = cur | WAITERS | if exclusive { WRITER_WAITING } else { 0 };
            if want != cur
                && w
                    .compare_exchange(cur, want, Ordering::Relaxed, Ordering::Relaxed)
                    .is_err()
            {
                LOCK_CAS_RETRIES.fetch_add(1, Ordering::Relaxed);
                continue;
            }
            LOCK_WAITS.fetch_add(1, Ordering::Relaxed);
            self.backend().wait(idx, want);
        }
    }

    /// One atomic read-modify-write that releases and clears the waiters bit,
    /// returning the old value; a wake-up only if the bit was set.
    fn unlock_word(&self, idx: usize, exclusive: bool) {
        let w = &self.backend().words()[idx];
        let woke = if exclusive {
            w.fetch_and(!(WRITER | WAITERS), Ordering::Release) & WAITERS != 0
        } else {
            let mut old = w.load(Ordering::Relaxed);
            loop {
                let dec = old - 1;
                let new = if dec & READERS == 0 { dec & !WAITERS } else { dec };
                match w.compare_exchange_weak(old, new, Ordering::Release, Ordering::Relaxed) {
                    Ok(_) => break,
                    Err(cur) => old = cur,
                }
            }
            old & WAITERS != 0 && (old - 1) & READERS == 0
        };
        if woke {
            self.backend().wake(idx);
        }
    }

    fn lock_range(&self, range: &Range<Vaddr>, exclusive: bool) -> u32 {
        let mask = stripe_mask(range);
        for i in 0..NR_WORDS {
            if mask & (1 << i) != 0 {
                self.lock_word(i, exclusive);
            }
        }
        mask
    }

    fn unlock_range(&self, mask: u32, exclusive: bool) {
        for i in (0..NR_WORDS).rev() {
            if mask & (1 << i) != 0 {
                self.unlock_word(i, exclusive);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// VmSpace
// ---------------------------------------------------------------------------

/// A page mapped without read permission: no host entry, the frame's
/// reference held here.
type Withheld = BTreeMap<Vaddr, (Paddr, PageProperty)>;

/// A virtual address space for user-mode tasks.
pub struct VmSpace {
    backend: Option<Backend>,
    withheld: SpinLock<Withheld>,
    /// Allocated here, in task context, so that `Drop` allocates nothing.
    retire: Option<Box<retire::Node>>,
}

impl core::fmt::Debug for VmSpace {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("VmSpace").field("backend", &self.backend).finish()
    }
}

impl FlushTarget for VmSpace {
    fn flush(&self, va: Vaddr, len: usize) {
        self.backend().flush(va, len);
    }
}

fn prot_bits(prop: &PageProperty) -> u32 {
    assert!(
        prop.cache == CachePolicy::Writeback,
        "only write-back memory can be mapped for a tenant on this host"
    );
    let mut p = 0;
    if prop.flags.contains(PageFlags::R) {
        p |= abi::KLET_PROT_READ;
    }
    if prop.flags.contains(PageFlags::W) {
        p |= abi::KLET_PROT_WRITE;
    }
    if prop.flags.contains(PageFlags::X) {
        p |= abi::KLET_PROT_EXEC;
    }
    p
}

fn rwx(flags: PageFlags) -> PageFlags {
    flags & PageFlags::RWX
}

impl VmSpace {
    /// Creates a new VM address space: in the native build, `vm_create`, a
    /// Linux address space with its one area, ready for `map` before any
    /// carrier runs in it.
    pub fn new() -> Self {
        Self {
            backend: Some(Backend::new()),
            withheld: SpinLock::new(BTreeMap::new()),
            retire: Some(Box::new(retire::Node::empty())),
        }
    }

    #[inline(always)]
    fn backend(&self) -> &Backend {
        self.backend.as_ref().unwrap()
    }

    #[inline]
    fn root(&self) -> Paddr {
        self.backend().root()
    }

    /// Gets an immutable cursor in the virtual address range. Takes the range
    /// lock shared for its lifetime; may sleep in the host if contended.
    pub fn cursor<'a, G: AsAtomicModeGuard>(
        &'a self,
        _guard: &'a G,
        va: &Range<Vaddr>,
    ) -> Result<Cursor<'a>> {
        check_range(va)?;
        let mask = self.lock_range(va, false);
        Ok(Cursor {
            core: Core {
                space: self,
                va: va.start,
                range: va.clone(),
                mask,
                exclusive: false,
            },
        })
    }

    /// Gets a mutable cursor in the virtual address range. Takes the range
    /// lock exclusively for its lifetime; may sleep in the host if contended.
    pub fn cursor_mut<'a, G: AsAtomicModeGuard>(
        &'a self,
        _guard: &'a G,
        va: &Range<Vaddr>,
    ) -> Result<CursorMut<'a>> {
        check_range(va)?;
        let mask = self.lock_range(va, true);
        Ok(CursorMut {
            core: Core {
                space: self,
                va: va.start,
                range: va.clone(),
                mask,
                exclusive: true,
            },
            flusher: TlbFlusher::new(self, disable_preempt()),
        })
    }

    /// Activates the space on the current virtual CPU: `vm_activate`, which
    /// never sleeps. As on the tree, the vCPU keeps a reference to the space
    /// it has active, and the previous one's is dropped here, which is why a
    /// `VmSpace` may be dropped with interrupts off.
    pub fn activate(self: &Arc<Self>) {
        let guard = disable_preempt();
        let last = ACTIVATED.load();
        if last == Arc::as_ptr(self) {
            return;
        }
        ACTIVATED.store(Arc::into_raw(Arc::clone(self)));
        self.backend().activate();
        drop(guard);
        if !last.is_null() {
            // SAFETY: the pointer came from `Arc::into_raw` when that space was
            // activated here, and is restored exactly once.
            drop(unsafe { Arc::from_raw(last) });
        }
    }

    fn check_active(&self, vaddr: Vaddr, len: usize) -> Result<()> {
        if current_page_table_paddr() != self.backend().token() || !is_in_user_space(vaddr, len)
        {
            return Err(Error::AccessDenied);
        }
        Ok(())
    }

    /// Creates a reader to read data from the user space of the current task.
    pub fn reader(&self, vaddr: Vaddr, len: usize) -> Result<VmReader<'_, Fallible>> {
        self.check_active(vaddr, len)?;
        // SAFETY: the range is in user space and the table is this space's.
        Ok(unsafe { VmReader::<Fallible>::from_space(self.root(), vaddr, len) })
    }

    /// Creates a writer to write data into the user space.
    pub fn writer(&self, vaddr: Vaddr, len: usize) -> Result<VmWriter<'_, Fallible>> {
        self.check_active(vaddr, len)?;
        // SAFETY: as above.
        Ok(unsafe { VmWriter::<Fallible>::from_space(self.root(), vaddr, len) })
    }

    /// Creates a reader/writer pair over the same range.
    pub fn reader_writer(
        &self,
        vaddr: Vaddr,
        len: usize,
    ) -> Result<(VmReader<'_, Fallible>, VmWriter<'_, Fallible>)> {
        self.check_active(vaddr, len)?;
        // SAFETY: as above.
        Ok(unsafe {
            (
                VmReader::<Fallible>::from_space(self.root(), vaddr, len),
                VmWriter::<Fallible>::from_space(self.root(), vaddr, len),
            )
        })
    }
}

impl Default for VmSpace {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for VmSpace {
    /// Must neither sleep nor cross: it may run inside the post-schedule
    /// handler with interrupts off. It only pushes the space onto the retire
    /// list, lock-free and without allocating.
    fn drop(&mut self) {
        if let (Some(backend), Some(mut node)) = (self.backend.take(), self.retire.take()) {
            node.backend = Some(backend);
            node.withheld = core::mem::take(&mut *self.withheld.lock());
            retire::push(node);
        }
    }
}

crate::cpu_local_cell! {
    /// The space active on this vCPU, holding one reference, as the tree's.
    static ACTIVATED: *const VmSpace = core::ptr::null();
}

fn check_range(va: &Range<Vaddr>) -> Result<()> {
    if va.start % PAGE_SIZE != 0 || va.end % PAGE_SIZE != 0 || va.start >= va.end {
        return Err(Error::InvalidArgs);
    }
    if !is_in_user_space(va.start, va.end - va.start) {
        return Err(Error::AccessDenied);
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// What both cursors share
// ---------------------------------------------------------------------------

struct Core<'a> {
    space: &'a VmSpace,
    va: Vaddr,
    range: Range<Vaddr>,
    mask: u32,
    exclusive: bool,
}

/// What the slot at `va` holds.
enum Slot {
    Table(page_table::Leaf),
    Withheld(Paddr, PageProperty),
}

impl Core<'_> {
    fn slot(&self, va: Vaddr) -> Option<Slot> {
        if let Some(leaf) = page_table::walk(self.space.root(), va) {
            return Some(Slot::Table(leaf));
        }
        self.space
            .withheld
            .lock()
            .get(&va)
            .map(|&(p, prop)| Slot::Withheld(p, prop))
    }

    /// The first mapped slot in `[va, end)`: the table merged with the set.
    fn next_mapped(&self, va: Vaddr, end: Vaddr) -> Option<Vaddr> {
        let t = page_table::next_present(self.space.root(), va, end);
        let w = self
            .space
            .withheld
            .lock()
            .range(va..end)
            .next()
            .map(|(&v, _)| v);
        match (t, w) {
            (Some(a), Some(b)) => Some(a.min(b)),
            (a, b) => a.or(b),
        }
    }

    fn query(&mut self) -> Result<(Range<Vaddr>, Option<VmQueriedItem<'_>>)> {
        let va = self.va;
        if va >= self.range.end {
            return Err(Error::InvalidArgs);
        }
        let range = va..va + PAGE_SIZE;
        let item = self.slot(va).map(|slot| {
            let (paddr, prop) = match slot {
                Slot::Table(leaf) => (
                    leaf.paddr,
                    PageProperty::new_user(leaf.flags, CachePolicy::Writeback),
                ),
                Slot::Withheld(p, prop) => (p, prop),
            };
            VmQueriedItem::MappedRam {
                // SAFETY: the entry (or the set) holds a reference, and the
                // range lock keeps it there while the cursor is borrowed.
                frame: unsafe { FrameRef::borrow_paddr(paddr) },
                prop,
            }
        });
        Ok((range, item))
    }

    fn find_next(&mut self, len: usize) -> Option<Vaddr> {
        let end = self.va + len;
        assert!(end <= self.range.end, "find_next past the end of the cursor's range");
        match self.next_mapped(self.va, end) {
            Some(v) => {
                self.va = v;
                Some(v)
            }
            None => {
                self.va = end;
                None
            }
        }
    }

    fn jump(&mut self, va: Vaddr) -> Result<()> {
        assert!(va % PAGE_SIZE == 0, "jump to an unaligned address");
        if !self.range.contains(&va) {
            return Err(Error::InvalidArgs);
        }
        self.va = va;
        Ok(())
    }
}

impl Drop for Core<'_> {
    fn drop(&mut self) {
        self.space.unlock_range(self.mask, self.exclusive);
    }
}

// ---------------------------------------------------------------------------
// Cursor
// ---------------------------------------------------------------------------

/// The cursor for querying over the VM space without modifying it. Holds the
/// range lock shared: a relaxation of the tree, whose read cursors lock
/// exclusively too, and a safe one, because a `Cursor` changes nothing.
pub struct Cursor<'a> {
    core: Core<'a>,
}

impl Cursor<'_> {
    /// Queries the mapping at the current virtual address.
    pub fn query(&mut self) -> Result<(Range<Vaddr>, Option<VmQueriedItem<'_>>)> {
        self.core.query()
    }

    /// Moves the cursor forward to the next mapped virtual address within
    /// `len` bytes, or past them.
    pub fn find_next(&mut self, len: usize) -> Option<Vaddr> {
        self.core.find_next(len)
    }

    /// Jumps to the virtual address.
    pub fn jump(&mut self, va: Vaddr) -> Result<()> {
        self.core.jump(va)
    }

    /// The virtual address of the current slot.
    pub fn virt_addr(&self) -> Vaddr {
        self.core.va
    }
}

// ---------------------------------------------------------------------------
// CursorMut
// ---------------------------------------------------------------------------

/// The cursor for modifying the mappings in VM space. Holds the range lock
/// exclusively.
pub struct CursorMut<'a> {
    // Dropped in this order: pending flushes are dispatched before the range
    // lock (in `core`) is released.
    flusher: TlbFlusher<'a, DisabledPreemptGuard>,
    core: Core<'a>,
}

impl<'a> CursorMut<'a> {
    /// Queries the mapping at the current virtual address.
    pub fn query(&mut self) -> Result<(Range<Vaddr>, Option<VmQueriedItem<'_>>)> {
        self.core.query()
    }

    /// Moves the cursor forward to the next mapped virtual address.
    pub fn find_next(&mut self, len: usize) -> Option<Vaddr> {
        self.core.find_next(len)
    }

    /// Jumps to the virtual address.
    pub fn jump(&mut self, va: Vaddr) -> Result<()> {
        self.core.jump(va)
    }

    /// The virtual address of the current slot.
    pub fn virt_addr(&self) -> Vaddr {
        self.core.va
    }

    /// The dedicated TLB flusher for this cursor.
    pub fn flusher(&mut self) -> &mut TlbFlusher<'a, DisabledPreemptGuard> {
        &mut self.flusher
    }

    /// Maps a frame into the current slot and moves to the next one.
    ///
    /// # Panics
    ///
    /// Panics if the slot is already mapped, or if the host cannot map it
    /// (which on the tree is a page-table node it cannot allocate).
    pub fn map(&mut self, frame: UFrame, prop: PageProperty) {
        let va = self.core.va;
        assert!(va < self.core.range.end, "the cursor is past the end of its range");
        let space = self.core.space;

        if !prop.flags.contains(PageFlags::R) {
            // No host entry: the frame's reference goes to the withheld set.
            assert!(
                page_table::walk(space.root(), va).is_none(),
                "map over a mapped slot {:#x}",
                va
            );
            let old = space.withheld.lock().insert(va, (frame.into_raw(), prop));
            assert!(old.is_none(), "map over a mapped slot {:#x}", va);
            WITHHELD_IN.fetch_add(1, Ordering::Relaxed);
            self.core.va += PAGE_SIZE;
            return;
        }
        if !space.withheld.lock().is_empty() {
            assert!(
                !space.withheld.lock().contains_key(&va),
                "map over a mapped slot {:#x}",
                va
            );
        }

        let mut prot = prot_bits(&prop);
        if MAP_TEST_SLEEP.load(Ordering::Relaxed) {
            prot |= abi::KLET_PROT_TEST_SLEEP;
        }

        {
            use super::HasPaddr;
            space.backend().map(va, frame.paddr(), prot);
        }
        // Only now does the reference pass to the entry.
        let _ = frame.into_raw();
        self.core.va += PAGE_SIZE;
    }

    /// Clears the mappings in the next `len` bytes and returns how many there
    /// were. Flushes before it returns, as the tree's does; the frames are
    /// released after the flush and a grace period.
    pub fn unmap(&mut self, len: usize) -> usize {
        assert!(len % PAGE_SIZE == 0, "unmap of an unaligned length");
        let start = self.core.va;
        let end = start + len;
        assert!(end <= self.core.range.end, "unmap past the end of the cursor's range");
        let space = self.core.space;

        // The leaves, read through the direct map before the host clears them.
        let mut frames: Vec<Paddr> = Vec::new();
        page_table::for_each_present(space.root(), start, end, &mut |_, leaf| {
            frames.push(leaf.paddr);
        });
        // The count is vOSTD's own: the host's zap reports none.
        if !frames.is_empty() {
            space.backend().unmap(start, len);
        }
        {
            let mut set = space.withheld.lock();
            let keys: Vec<Vaddr> = set.range(start..end).map(|(&v, _)| v).collect();
            for v in keys {
                let (p, _) = set.remove(&v).unwrap();
                frames.push(p);
                WITHHELD_OUT.fetch_add(1, Ordering::Relaxed);
            }
        }
        let n = frames.len();
        if n > 0 {
            super::rcu::synchronize();
            for p in frames {
                drop(UFrame::from_raw(p));
            }
        }
        // As the tree's unmap ends: anything issued before is dispatched too.
        self.flusher.dispatch_tlb_flush();
        self.core.va = end;
        n
    }

    /// Applies `op` to the next mapped slot in the next `len` bytes, and only
    /// that one, which `fork` relies on. Returns the slot's range, or `None`
    /// if there is none (the cursor then stops at the end). Does not flush.
    pub fn protect_next(
        &mut self,
        len: usize,
        mut op: impl FnMut(&mut PageFlags, &mut CachePolicy),
    ) -> Option<Range<Vaddr>> {
        let end = self.core.va + len;
        assert!(end <= self.core.range.end, "protect_next past the end of the cursor's range");
        let Some(va) = self.core.next_mapped(self.core.va, end) else {
            self.core.va = end;
            return None;
        };
        let space = self.core.space;
        let slot = self.core.slot(va).unwrap();
        let (paddr, old) = match slot {
            Slot::Table(leaf) => (
                leaf.paddr,
                PageProperty::new_user(leaf.flags, CachePolicy::Writeback),
            ),
            Slot::Withheld(p, prop) => (p, prop),
        };
        let mut new = old;
        op(&mut new.flags, &mut new.cache);
        let in_table = matches!(slot, Slot::Table(_));
        let readable = new.flags.contains(PageFlags::R);

        match (in_table, readable) {
            (true, true) => {
                if rwx(new.flags) != rwx(old.flags) {
                    space.backend().protect(va, prot_bits(&new));
                }
            }
            (true, false) => {
                // Out of the host's table; the entry's reference moves to the set.
                space.backend().unmap(va, PAGE_SIZE);
                space.withheld.lock().insert(va, (paddr, new));
                WITHHELD_IN.fetch_add(1, Ordering::Relaxed);
            }
            (false, true) => {
                space.withheld.lock().remove(&va);
                space.backend().map(va, paddr, prot_bits(&new));
                WITHHELD_OUT.fetch_add(1, Ordering::Relaxed);
            }
            (false, false) => {
                space.withheld.lock().insert(va, (paddr, new));
            }
        }
        self.core.va = va + PAGE_SIZE;
        Some(va..va + PAGE_SIZE)
    }
}

/// The result of a query over the VM space.
pub enum VmQueriedItem<'a> {
    /// The slot is mapped to a frame of RAM.
    MappedRam {
        /// The mapped frame, borrowed for the cursor's lifetime.
        frame: FrameRef<'a, dyn AnyUFrameMeta>,
        /// The property of the slot.
        prop: PageProperty,
    },
    /// The slot is mapped to device memory. Never produced on this host:
    /// `map_iomem` is refused in the first version.
    MappedIoMem {
        /// The physical address.
        paddr: Paddr,
        /// The property of the slot.
        prop: PageProperty,
    },
}

impl VmQueriedItem<'_> {
    /// Returns the page property of the mapped item.
    pub fn prop(&self) -> &PageProperty {
        match self {
            Self::MappedRam { prop, .. } => prop,
            Self::MappedIoMem { prop, .. } => prop,
        }
    }
}

// ---------------------------------------------------------------------------
// The retire list
// ---------------------------------------------------------------------------

/// Dropped spaces wait here to be destroyed. vOSTD cannot own a task on this
/// host to do it (a task spawned before the kernel proper injects its scheduler
/// installs OSTD's default and the injection panics; one spawned after is not
/// a thread the kernel proper's scheduler will enqueue),
/// so the list is drained at the next point on any virtual CPU that may sleep:
/// the stubs of `vm_create` and `vcpu_idle`, and every sleeping service's stub
/// whose caller holds no guard and has interrupts on.
pub(crate) mod retire {
    use super::*;

    pub(crate) struct Node {
        next: *mut Node,
        pub(super) backend: Option<Backend>,
        pub(super) withheld: Withheld,
    }

    // SAFETY: a node is owned by exactly one party at a time: the space, then
    // the list, then the drainer.
    unsafe impl Send for Node {}
    // SAFETY: the raw link is touched only by the party that owns the node.
    unsafe impl Sync for Node {}

    impl Node {
        pub(super) fn empty() -> Self {
            Self {
                next: core::ptr::null_mut(),
                backend: None,
                withheld: BTreeMap::new(),
            }
        }
    }

    static HEAD: AtomicPtr<Node> = AtomicPtr::new(core::ptr::null_mut());
    static DRAINING: AtomicBool = AtomicBool::new(false);

    /// Lock-free push; neither sleeps nor crosses.
    pub(super) fn push(node: Box<Node>) {
        let node = Box::into_raw(node);
        let mut head = HEAD.load(Ordering::Relaxed);
        loop {
            // SAFETY: the node is ours until the exchange publishes it.
            unsafe { (*node).next = head };
            match HEAD.compare_exchange_weak(head, node, Ordering::Release, Ordering::Relaxed) {
                Ok(_) => break,
                Err(h) => head = h,
            }
        }
        RETIRED.fetch_add(1, Ordering::Relaxed);
    }

    /// Whether the caller may sleep here: a virtual CPU's task (or bootstrap)
    /// context, no guard, no spin lock, interrupts on, not in an upcall.
    fn safe() -> bool {
        crate::vcpu::is_up()
            && !crate::vcpu::in_upcall()
            && crate::task::preempt::cpu_local::get_guard_count() == 0
            && !crate::task::preempt::cpu_local::irq_is_off()
            && crate::sync::r2::held() == 0
    }

    /// Drains the list if this is a point where sleeping is allowed, and no
    /// other virtual CPU (nor this one, further up the stack) is draining.
    pub(crate) fn drain_if_safe() {
        if HEAD.load(Ordering::Relaxed).is_null() || !safe() {
            return;
        }
        if DRAINING.swap(true, Ordering::Acquire) {
            return;
        }
        let mut p = HEAD.swap(core::ptr::null_mut(), Ordering::Acquire);
        while !p.is_null() {
            // SAFETY: the swap took the whole list; each node came from
            // `Box::into_raw` in `push`.
            let node = unsafe { Box::from_raw(p) };
            p = node.next;
            destroy(*node);
            DRAINED.fetch_add(1, Ordering::Relaxed);
        }
        DRAINING.store(false, Ordering::Release);
    }

    /// Unmap everything (which flushes), release every frame after a grace
    /// period, the withheld set's included, then `vm_destroy`.
    fn destroy(mut node: Node) {
        let backend = node.backend.take().unwrap();
        let mut frames: Vec<Paddr> = Vec::new();
        page_table::for_each_present(backend.root(), 0, MAX_USERSPACE_VADDR, &mut |_, leaf| {
            frames.push(leaf.paddr);
        });
        if !frames.is_empty() {
            backend.unmap(0, MAX_USERSPACE_VADDR);
        }
        frames.extend(node.withheld.values().map(|&(p, _)| p));
        super::super::rcu::synchronize();
        for p in frames {
            drop(UFrame::from_raw(p));
        }
        backend.destroy();
    }
}
