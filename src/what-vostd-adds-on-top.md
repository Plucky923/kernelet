# What vOSTD adds on top

The last chapter put the tenant's page table in Linux's hands. This one is about what vOSTD must do for the kernel proper that Linux does not: read the table, copy to and from the tenant's memory, keep track of which frame each entry holds, lock a range for the kernel proper's cursor, hold the one kind of page Linux cannot represent, and dispose of an address space at a moment when it may not. Each of these is a few dozen lines, and together they are why the design is sound.

## Reading the table without a lock

The kernel proper asks a cursor what is at an address (`query`), where the next mapped page is (`find_next`), and how many pages an `unmap` removed. On a machine OSTD reads its own page table. Here vOSTD reads Linux's, through the direct map, from the root whose physical address the space's record holds:

*Simplified from `prototype/vostd/src/mm/page_table.rs`: `read_entry`, `child`, `leaf_of`, `walk`.*

```rust
fn read_entry(node: Paddr, idx: usize) -> u64 {
    unsafe { read_volatile((paddr_to_vaddr(node) as *const u64).add(idx)) }   // one 64-bit load
}

fn child(e: u64) -> Option<Paddr> {                       // the next table down, if the entry points at one
    if e & PRESENT == 0 || e & HUGE != 0 { None } else { Some((e & ADDR_MASK) as Paddr) }
}

fn leaf_of(e: u64) -> Option<Leaf> {                      // a present, user-accessible page
    if e & PRESENT == 0 || e & USER == 0 { return None; }
    let mut flags = PageFlags::R;
    if e & WRITE != 0      { flags |= PageFlags::W; }
    if e & NO_EXECUTE == 0 { flags |= PageFlags::X; }
    Some(Leaf { paddr: (e & ADDR_MASK) as Paddr, flags })
}

pub(crate) fn walk(root: Paddr, va: Vaddr) -> Option<Leaf> {
    let mut node = root;
    for level in (2..=4).rev() {                          // four levels; vOSTD refuses a five-level host at start
        node = child(read_entry(node, index(va, level)))?;
    }
    leaf_of(read_entry(node, index(va, 1)))
}
```

That is the walk a processor does, in software, four dependent loads. It takes no lock, and two facts about Linux make that safe. The area's page-table pages are freed only in `exit_mmap()`, which cannot run while the endovisor holds its reference on the address space (the last chapter's second reference), so a page the walk reads is never freed under it. And Linux writes an entry with a single 64-bit store and clears it with an atomic exchange, so a load never sees half an entry. Permissions are taken from the leaf only, never combined down the levels, because on a host with page-table isolation the kernel's copy of the top-level entries carries a no-execute bit that means nothing for the tenant.

## Copying to and from the tenant

The hundred-line kernel's `write` handler reads the program's buffer through `vm_space.reader(addr, len)`. On a machine OSTD would dereference the address and let the fault handler catch a bad one. Inside Linux that is forbidden twice over: the processor refuses a kernel-mode access to a user page unless a flag is set (the protection called SMAP), and recovering from a bad address needs an entry in an exception table, the list of instructions allowed to fault and where to resume, which Linux keeps for its own code and for each module's; the Rust compiler emits no such entries for the image.

vOSTD never dereferences a tenant address. A copy walks the page table from the tenant address to the frame, and copies through the frame's direct-map alias, an ordinary kernel address. An unmapped address is a *result* of the walk, not a fault, and becomes the same page-fault error the kernel proper would have got from a trap.

*Simplified from `prototype/vostd/src/mm/io.rs`: `Region`, `resolve`, `copy_regions`, `copy_opaque`.*

```rust
enum Region {
    Kernel { cursor: usize, end: usize },                  // a kernel buffer
    User { root: Paddr, cursor: Vaddr, end: Vaddr },       // tenant memory, to be walked through `root`
}

impl Region {
    fn resolve(&self, write: bool) -> Option<(*mut u8, usize)> {   // the head of the region, as a kernel pointer
        match *self {
            Region::Kernel { cursor, end } => Some((cursor as *mut u8, end - cursor)),
            Region::User { root, cursor, end } => {
                let leaf = page_table::walk(root, cursor & !(PAGE_SIZE - 1))?;    // None: a page fault
                if write && !leaf.flags.contains(PageFlags::W) { return None; }
                let offset = cursor % PAGE_SIZE;
                let len = (PAGE_SIZE - offset).min(end - cursor);               // up to the end of this page
                Some(((paddr_to_vaddr(leaf.paddr) + offset) as *mut u8, len))
            }
        }
    }
}

fn copy_regions(dst: &mut Region, src: &mut Region) -> (usize, bool) {
    while copied < total {
        let done = rcu::read(|| {                                      // a closure, run inside a read section (below); a `?` in it returns from the closure
            let (dptr, dlen) = dst.resolve(true)?;
            let (sptr, slen) = src.resolve(false)?;
            let n = dlen.min(slen).min(total - copied);
            unsafe { copy_opaque(dptr, sptr, n) };
            Some(n)
        });
        let Some(n) = done else { return (copied, false) };            // a fault: how far we got
        dst.advance(n); src.advance(n); copied += n;
    }
    (copied, true)
}

unsafe fn copy_opaque(dst: *mut u8, src: *const u8, n: usize) {
    asm!("rep movsb", inout("rcx") n => _, inout("rdi") dst => _, inout("rsi") src => _);
}
```

The copy is one `rep movsb` in assembly rather than a Rust copy, and that is not for speed. Tenant memory may change under the copy, since another virtual CPU's thread may be writing it; a plain copy of memory that changes is a data race in Rust's terms, and the optimizer is then free to assume the source did not change. It could, for instance, compile "copy a length out, check it, use it" into a check of the copy and a *re-read of the source* for the use, and a tenant that changed the length in between would have passed the check with a value it never had. An assembly copy is opaque to the compiler, so the destination is the only thing it reads afterwards. OSTD's own user copy is assembly for the same reason.

## Who holds the frame

On a machine, OSTD's page table holds a counted reference on every mapped frame, and the kernel proper relies on the count: its copy-on-write path reuses a frame in place when the count is one. Here the *Linux entry* holds that reference. `map` turns the handle into a raw address after the service succeeds, so the reference passes to the entry only once the entry exists; `unmap` reads the entries back before the service clears them, and turns each address into a handle again, which is dropped.

<div class="rust">

**Rust: destructors, and forgetting.** A frame handle's `Drop` (chapter 2's box) decrements the frame's count, and frees the frame when the count reaches zero. `core::mem::forget(x)` ends the life of `x` *without* running its destructor, so the count stays as it was: that is how a reference is handed to something Rust cannot see, such as a page-table entry. `from_raw` is the reverse: it makes a handle out of an address without incrementing, taking the reference back.

</div>

*Simplified from `prototype/vostd/src/mm/vm_space.rs` and `prototype/vostd/src/mm/frame.rs`: `CursorMut::map`, `CursorMut::unmap`, `Frame::into_raw`, `Frame::from_raw`.*

```rust
pub fn map(&mut self, frame: UFrame, prop: PageProperty) {
    let va = self.core.va;
    /* ... a page without read permission goes to the withheld set, below ... */
    space.backend().map(va, frame.paddr(), prot_bits(&prop));   // the vm_map service; panics the kernelet on failure
    let _ = frame.into_raw();                                    // the entry owns the reference now
    self.core.va += PAGE_SIZE;
}

pub fn unmap(&mut self, len: usize) -> usize {
    let mut frames: Vec<Paddr> = Vec::new();
    page_table::for_each_present(space.root(), start, end, &mut |_, leaf| frames.push(leaf.paddr));  // read first
    if !frames.is_empty() {
        space.backend().unmap(start, len);                       // the vm_unmap service: clears and flushes
    }
    /* ... plus the withheld set's pages in the range ... */
    rcu::synchronize();                                          // every copy in progress is done
    for p in frames { drop(UFrame::from_raw(p)); }               // now the frames may go back
    self.flusher.dispatch_tlb_flush();
    frames.len()
}

pub(crate) fn into_raw(self) -> Paddr { let p = self.paddr; core::mem::forget(self); p }

pub(crate) fn from_raw(paddr: Paddr) -> Self {
    assert!(allocator::refcount(paddr).unwrap() > 0);          // the frame is the grant's and in use
    Self::from_raw_unchecked(paddr)
}
```

This is sound only if Linux never clears an entry of the area on its own initiative. For a raw-frame-number area it does not: reclaim, swapping, compaction, same-page merging and the rest all skip such entries, because there is no Linux page behind them. The test `make mem-pressure` drives the Linux under test into swap with a host process while a tenant has 512 pages mapped, and afterwards every entry is present with the same frame and the same contents.

**The grace period.** A copy takes no cursor, so an `unmap` on another virtual CPU may clear the entry the copy just walked, and then free the frame while the copy is still reading it. The `rcu::read` around each page of a copy, and the `rcu::synchronize()` in `unmap` before the frames are freed, are a minimal RCU (*read-copy-update*, a scheme in which readers take no lock and a writer waits for every reader in progress to finish before it frees anything): each virtual CPU has a sequence word that is odd while it is inside a read section, and `synchronize` waits until every other virtual CPU that was inside a section when it was called has left it. A read section holds a preemption guard, so no task switch happens inside it, which is why `synchronize` need not wait for its own virtual CPU; it lasts one page's walk and copy, so the wait is short. `make mem-conc` runs copies without pause on one virtual CPU against map-and-unmap cycles on the other and finds no torn copy.

## The range lock

On a machine, a cursor holds the page table's node locks for its whole life, and the kernel proper relies on that in two places: its page-fault handler queries, allocates and maps under one cursor, so two threads faulting on one page never both map it; and its page cache commits a page and maps it atomically under one cursor while eviction unmaps through another. Linux's locks are not available to vOSTD, so it keeps a lock of its own per space: sixteen 64-bit words in the space's shared record, one per 2 MiB region of the address space, with regions aliasing onto words by their index modulo sixteen.

A cursor computes the set of words its range touches, takes them in ascending word order (a total order, so two cursors cannot deadlock), exclusively for a `cursor_mut` and shared for a `cursor`, and releases them when it is dropped. Uncontended, taking a word is one compare-and-swap in kernelet memory and no crossing. Each word holds a count of readers in its low bits (`READERS` is their mask) and three flags: `WRITER`, set by an exclusive holder; `WRITER_WAITING`, which holds new readers off while a writer waits; and `WAITERS`, which says that someone is asleep in `vm_wait` on this word.

*Simplified from `prototype/vostd/src/mm/vm_space.rs`: `lock_word`, `unlock_word`.*

```rust
fn lock_word(&self, idx: usize, exclusive: bool) {
    let w = &self.backend().words()[idx];
    loop {
        let cur = w.load(Ordering::Acquire);
        let free = if exclusive { cur & (WRITER | READERS) == 0 } else { cur & (WRITER | WRITER_WAITING) == 0 };
        if free {
            let new = if exclusive { (cur | WRITER) & !WRITER_WAITING } else { cur + 1 };
            if w.compare_exchange(cur, new, Ordering::Acquire, Ordering::Relaxed).is_ok() { return; }
            continue;
        }
        // Contended: say so in the word, then sleep in the host until it changes. Nothing spins.
        let want = cur | WAITERS | if exclusive { WRITER_WAITING } else { 0 };
        if want != cur && w.compare_exchange(cur, want, Ordering::Relaxed, Ordering::Relaxed).is_err() { continue; }
        self.backend().wait(idx, want);                       // the vm_wait service
    }
}

fn unlock_word(&self, idx: usize, exclusive: bool) {
    let old = if exclusive { w.fetch_and(!(WRITER | WAITERS), Ordering::Release) } else { /* decrement the readers, clearing WAITERS with the last */ };
    if old & WAITERS != 0 { self.backend().wake(idx); }       // the vm_wake service
}
```

The slow path is a futex, Linux's "sleep only if this word still holds this value" primitive, rebuilt for carriers. A waiter sets the *waiters* bit and calls `vm_wait(space, word, expected)`; the endovisor takes the space's wait-queue lock, reads the word, returns at once if it no longer equals `expected`, and otherwise puts the carrier to sleep, killably. A releasing holder clears the bit with one atomic read-modify-write and, if it was set, calls `vm_wake`, which wakes every waiter under the same lock. The read under the lock and the single read-modify-write on release are what make a wake-up impossible to lose. Nothing spins: the holder may itself be asleep in Linux inside a `vm_map`, and the waiter then sleeps too. `make mem-conc` has one virtual CPU hold a cursor while its `vm_map` sleeps (a test hook makes it), and the other virtual CPU's cursor on the same region sleeps in `vm_wait` and takes the lock after the release, without a single kernelet task switch.

## A page without read permission

The kernel proper keeps a `PROT_NONE` page *mapped*, with every permission bit cleared, and on a machine OSTD encodes that as a valid but not-present entry. Linux has no safe equivalent for this area. Linux does have a "no access" form of entry, but it uses it as a marker of its own: its NUMA-balancing code, which moves pages closer to the processors that use them, plants such entries and, on the next fault, rewrites each with the area's full permissions. A `PROT_NONE` page encoded that way would silently become writable. So such a page has **no Linux entry**. vOSTD keeps it in a per-space ordered map, the **withheld set**, from address to frame and property, in kernelet memory under the range lock, and the set holds the frame's reference exactly as an entry would. `query`, `find_next`, `protect_next` and `unmap` consult the set beside the table:

*Simplified from `prototype/vostd/src/mm/vm_space.rs`: `Slot`, `slot`, `protect_next`.*

```rust
enum Slot { Table(page_table::Leaf), Withheld(Paddr, PageProperty) }

fn slot(&self, va: Vaddr) -> Option<Slot> {
    if let Some(leaf) = page_table::walk(self.space.root(), va) { return Some(Slot::Table(leaf)); }
    self.space.withheld.lock().get(&va).map(|&(p, prop)| Slot::Withheld(p, prop))
}

pub fn protect_next(&mut self, len: usize, mut op: impl FnMut(&mut PageFlags, &mut CachePolicy)) -> Option<Range<Vaddr>> {
    let va = self.core.next_mapped(self.core.va, end)?;        // the table merged with the set
    let (paddr, old) = /* from the slot */;
    let mut new = old; op(&mut new.flags, &mut new.cache);
    match (in_table, new.flags.contains(PageFlags::R)) {
        (true, true)   => if rwx(new.flags) != rwx(old.flags) { backend.protect(va, prot_bits(&new)) },  // vm_protect
        (true, false)  => { backend.unmap(va, PAGE_SIZE); withheld.insert(va, (paddr, new)); }            // into the set
        (false, true)  => { withheld.remove(&va); backend.map(va, paddr, prot_bits(&new)); }              // out of the set
        (false, false) => { withheld.insert(va, (paddr, new)); }
    }
    Some(va..va + PAGE_SIZE)
}
```

A tenant access to a withheld page faults as an absent page does, and the kernel proper's own permission check turns that into the signal, as on a machine. `make mem-func` moves 512 pages into the set with `mprotect(PROT_NONE)`, checks that a read of one is refused, moves them back, and reads them all intact with no fault.

## A space that is dropped at the wrong moment

The last reference to a `VmSpace` can be dropped at a bad moment. `activate` keeps one reference per virtual CPU to the space that is active there, and drops the previous space's reference when a new one is activated; the kernel proper activates from the handler it runs right after a task switch, with interrupts off. If that was the last reference, `Drop` runs there, and so it may do nothing that sleeps or crosses, while `vm_destroy` does both.

The usual answer, a helper task that does the work later, is not available. A task created before the kernel proper calls `inject_scheduler` would make OSTD install its default scheduler, and the injection would then fail; a task created afterwards is scheduled by the kernel proper's own policy, which vOSTD cannot ask to run it at a chosen moment.

So `Drop` pushes the space onto a per-kernelet **retire list**, lock-free and without allocating (the list node was allocated at `new`), and the list is drained at the next point on any virtual CPU where sleeping is allowed: the stubs of `vm_create` and `vcpu_idle`, and every sleeping service's stub when the caller holds no guard. The drain unmaps the whole space, which flushes and releases every frame, the withheld set's included, and then calls `vm_destroy`.

*Simplified from `prototype/vostd/src/mm/vm_space.rs`: `Drop`, `retire::drain_if_safe`, `retire::destroy`.*

```rust
impl Drop for VmSpace {
    fn drop(&mut self) {                                   // may run with interrupts off: push, nothing else
        node.backend = self.backend.take();
        node.withheld = core::mem::take(&mut *self.withheld.lock());
        retire::push(node);
    }
}

pub(crate) fn drain_if_safe() {                            // called from sleeping stubs and vcpu_idle
    if HEAD.load(Ordering::Relaxed).is_null() || !safe() { return; }   // safe: no guard, no spin lock, interrupts on
    let mut p = HEAD.swap(core::ptr::null_mut(), Ordering::Acquire);
    while !p.is_null() { let node = unsafe { Box::from_raw(p) }; p = node.next; destroy(*node); }
}

fn destroy(mut node: Node) {
    let backend = node.backend.take().unwrap();
    page_table::for_each_present(backend.root(), 0, MAX_USERSPACE_VADDR, &mut |_, leaf| frames.push(leaf.paddr));
    backend.unmap(0, MAX_USERSPACE_VADDR);
    frames.extend(node.withheld.values().map(|&(p, _)| p));
    rcu::synchronize();
    for p in frames { drop(UFrame::from_raw(p)); }
    backend.destroy();                                     // vm_destroy
}
```

## The rule about sleeping

Every memory service except `vm_flush`, `vm_activate` and `vm_wake` may sleep in Linux: for the address-space lock, for a page-table page, for the zap's own pauses between tables, in `vm_wait`. And the kernel proper calls `map` holding a preemption guard, because every cursor takes one. On a machine that would be a contradiction: OSTD forbids sleeping inside a critical section. Here it is not, and the design states the rule in four parts.

1. A service may sleep whenever its work needs it. Its prologue lifts the mirror of chapter 10, so Linux sees nothing wrong, and its epilogue restores it.
2. A service that may sleep must not be called while the caller holds a kernelet **spin lock** or has virtual interrupts off. Under a plain preemption guard it may. The reason is lock-holder preemption: a spin lock held across a Linux sleep makes every other virtual CPU that wants it spin for the sleep's length. vOSTD asserts this before every sleeping service, with a count of spin locks held that is separate from the guard count.
3. What a sleep costs is stated, not hidden: this virtual CPU's pending virtual interrupts and the kernelet's grace periods wait for the carrier to return, as they do when Linux deschedules it.
4. The mirror remains a latency optimization and is load-bearing for correctness nowhere.

*Simplified from `prototype/vostd/src/mm/backend.rs` and `prototype/vostd/src/sync/spin.rs`: `sleeping`, `Backend::map`, `assert_may_sleep`.*

```rust
fn sleeping(name: &str) {                                  // every sleeping service's stub begins here
    r2::assert_may_sleep(name);                            // rule 2
    retire::drain_if_safe();                               // and a drain point for the retire list
}

pub(crate) fn map(&self, va: Vaddr, paddr: Paddr, prot: u32) {
    sleeping("vm_map");
    let r = unsafe { (svc().vm_map)(self.id, va as u64, paddr as u64, prot) };
    if r < 0 { map_failed(va, paddr, r); }                 // as on a machine: a page-table node it cannot get is a panic
}

pub(crate) fn assert_may_sleep(service: &str) {
    if held() != 0 || irq_is_off() {
        panic!("R2 violated: the sleeping service {} was called holding {} kernelet spin lock(s)", service, held());   // R2 is the code's name for rule 2
    }
}
```

Why rule 1 is sound was argued at the end of chapter 10's second problem: a kernelet's critical section promises only that no kernelet task switch happens on this virtual CPU until the guard drops, and a sleep in Linux is the same event as a Linux preemption, which the kernelet already survives at any instruction. `make mem-func` maps a page into a fresh 2 MiB region, which makes Linux allocate a page-table page, inside a preemption guard, on a Linux built with `CONFIG_DEBUG_ATOMIC_SLEEP`, the option that makes Linux complain about any sleep in atomic mode, and Linux reports nothing; `make mem-r2` does the same under a spin lock, and vOSTD stops the kernelet before the call crosses.

<div class="recap">

**Recap.** vOSTD reads Linux's page table through the direct map with a four-level walk that needs no lock, because the endovisor's reference keeps the table alive and Linux writes entries with single stores. Copies walk to the frame and go through its direct-map alias with an opaque `rep movsb`, inside an RCU read section, and `unmap` waits a grace period before it frees a frame. The Linux entry holds the frame's counted reference. A cursor takes a striped range lock whose waiters sleep in Linux through `vm_wait` and `vm_wake`. Pages without read permission live in a withheld set, not in the table. A dropped space goes on a retire list and is destroyed at the next point where sleeping is allowed. A service may sleep under a preemption guard, never under a spin lock.

</div>
