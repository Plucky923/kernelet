# What vOSTD adds on top

This chapter is about what vOSTD must do for the kernel proper that Linux does not, now that the last chapter has put the tenant's page table in Linux's hands: read the table, copy to and from the tenant's memory, wait for copies in progress before a frame is freed, keep track of which frame each entry holds, lock a range for the kernel proper's cursor, hold the one kind of page Linux cannot represent, dispose of an address space at a moment when sleeping is not allowed, and say when a service may sleep under a guard. Each of these is a few dozen lines. Together they are why the design is sound.

## Reading the table

vOSTD answers a cursor's questions by reading Linux's page table itself, through the direct map, from the root whose physical address the space's record holds. The kernel proper asks a cursor what is at an address (`query`), where the next mapped page is (`find_next`), and how many pages an `unmap` removed; on a machine OSTD reads its own page table for these. It is the walk a processor does, in software, four dependent loads:

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

The walk takes no lock, and two facts about Linux make that safe. First, a page the walk reads is never freed under it. Linux frees an area's page-table pages when the area is unmapped or moved, which only a system call to Linux does, and the tenant's go to the kernel proper; at exec, which never runs in this address space; when khugepaged, Linux's background thread that replaces a last-level table of 4 KiB entries with one 2 MiB *huge* entry, collapses a range, which it refuses for raw-frame-number areas; and in `exit_mmap()`, which cannot run while the endovisor holds its reference on the address space (the last chapter's second reference). `zap_vma_ptes()` clears entries but leaves the tables. Second, Linux writes an entry with a single 64-bit store and clears it with an atomic exchange, so a load never sees half an entry.

The area holds only 4 KiB entries, since `vm_map` inserts one page at a time, and `child` treats a huge entry as absent.

<div class="linux">

**Linux: page-table isolation.** To blunt Meltdown, Linux gives each address space a second top-level page for user mode. Whenever it writes a user entry into `mm->pgd`, it writes the same entry into the second page, so both point at the same lower-level tables; below the top level there is one table, the one the last chapter described. In the kernel-mode copy only, Linux sets no-execute on those top-level user entries, so that a return to user mode on the wrong table faults. The prototype's Linux is built without the mitigation, so this case is argued, not tested.

</div>

Permissions are taken from the leaf only, never combined down the levels. Linux makes every upper-level user entry readable, writable and user-accessible, so only the leaf restricts anything, with one exception: the no-execute bit on the kernel-mode table's top-level user entries, which vOSTD reads. Combined down the levels, that bit would make every tenant page non-executable.

## Copying to and from the tenant

<div class="linux">

**Linux: copying from user memory.** Linux's `copy_from_user` rests on two mechanisms. The processor feature SMAP, supervisor-mode access prevention, faults any kernel-mode access to a user page unless the kernel has opened a window for it with `stac`, which it closes again with `clac`. And the copying instruction is listed in the *exception table*, the list of instructions allowed to fault and where to resume, so that a fault inside it resumes at a fixup that returns an error; Linux keeps a table for its own code and for each module's.

</div>

Inside Linux, vOSTD may not dereference a tenant address as OSTD does on a machine. On a machine OSTD dereferences the address and lets the fault handler catch a bad one; for example, the hundred-line kernel's `write` handler reads the program's buffer through `vm_space.reader(addr, len)`. vOSTD could open an SMAP window and could list an assembly copy in an exception table, but two deeper obstacles remain. The address space the processor is in is not necessarily the one being copied, because a carrier adopts its virtual CPU's space only on the way to user mode. And a kernel-mode fault in the area is answered with a `SIGBUS` and never reaches the kernel proper.

vOSTD never dereferences a tenant address. A copy walks the page table from the tenant address to the frame, and copies through the frame's direct-map alias, an ordinary kernel address.

On a bad address, vOSTD returns the page-fault error at once, where OSTD would first call the kernel proper's own page-fault handler and retry. An unmapped or read-only address is a *result* of the walk, not a fault. Returning the error is enough for kernels that map eagerly. Asterinas's full kernel proper maps on demand, so before it can run as a kernelet vOSTD must call its handler outside the RCU read section described below and walk again, which this prototype does not do.

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
        let done = rcu::read(|| {                                      // run inside a read section (below)
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

The copy is one `rep movsb` in assembly rather than a Rust copy, so that the compiler cannot assume tenant memory holds still. Tenant memory may change under the copy, since another virtual CPU's thread may be writing it; a plain copy of memory that changes is a data race in Rust's terms, and the optimizer is then free to assume the source did not change. It could, for instance, compile "copy a length out, check it, use it" into a check of the copy and a *re-read of the source* for the use, and a tenant that changed the length in between would have passed the check with a value it never had. An assembly copy is opaque to the compiler, so the destination is the only thing it reads afterwards.

## Who holds the frame

Inside Linux, vOSTD counts each Linux entry as holding the reference that OSTD's page table holds on a machine; Linux knows nothing of the count. The kernel proper relies on it: its copy-on-write path reuses a frame in place when the count is one. `map` turns the handle into a raw address after the service succeeds, so the reference passes to the entry only once the entry exists. `unmap` reads the entries back before the service clears them, and turns each address into a handle again, which is dropped after the wait described below.

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
    let n = frames.len();
    for p in frames { drop(UFrame::from_raw(p)); }               // now the frames may go back
    self.flusher.dispatch_tlb_flush();                           // the kernel proper's own queued flushes; the zap has flushed this range
    n
}

pub(crate) fn into_raw(self) -> Paddr { let p = self.paddr; core::mem::forget(self); p }

pub(crate) fn from_raw(paddr: Paddr) -> Self {
    assert!(allocator::refcount(paddr).unwrap() > 0);          // the frame is the grant's and in use
    Self::from_raw_unchecked(paddr)
}
```

This is sound only if Linux never clears an entry of the area on its own initiative, and for this area it does not. The entries are marked special, so Linux finds no page of its own behind them. Every scanner that walks address spaces skips the area by its flags: the multi-generational LRU walk, khugepaged, same-page merging, NUMA balancing, the out-of-memory reaper. Reclaim finds pages to evict through its LRU lists and the entries that map a page through its reverse mapping; the grant's frames are ordinary RAM on no LRU list, and no reverse mapping leads from a frame to this area, so swap-out and compaction never see them.

The test `make mem-pressure` tries to drive the Linux under test into swap with a host process while a tenant has 512 pages mapped (the log reports how much was swapped; the check does not require it), and afterwards every entry is present with the same frame and the same contents.

## Freeing a frame a copy may be reading

`unmap` waits for every copy in progress before it frees a frame, because a copy takes no cursor (it would serialize every copy against every cursor) and may still be reading the frame whose entry the `unmap` just cleared. This is a minimal RCU: the `rcu::read` around each page of a copy, and the `rcu::synchronize()` in `unmap` before the frames are freed. RCU, *read-copy-update*, is a scheme in which readers take no lock and a writer waits a *grace period*, until every reader in progress has finished, before it frees anything.

Each virtual CPU has a sequence word that is odd while it is inside a read section, and `synchronize` waits until every other virtual CPU that was inside a section when it was called has left it. `synchronize` skips its own virtual CPU: its caller is not in a read section, and since a read section holds a preemption guard, no other task on this virtual CPU can have been switched out partway through one.

The wait is short, one page's walk and copy, unless Linux has descheduled the reader's carrier; then the waiter spins, telling the host through `vcpu_on_spin`, until that carrier runs again.

`make mem-conc` runs copies without pause on one virtual CPU against map-and-unmap cycles on the other and finds no copy that read a frame after its `unmap` returned (the test rewrites the frames then, standing in for reuse). A second phase frees the frames for real under copies and finds none overwritten.

## The range lock

vOSTD keeps a range lock of its own per space, because the kernel proper relies on a cursor's locks in two places and no Linux lock can stay held while kernelet code runs. On a machine, a cursor holds the page table's node locks for its whole life: the kernel proper's page-fault handler queries, allocates and maps under one cursor, so two threads faulting on one page never both map it; and its page cache commits a page and maps it atomically under one cursor while its eviction and truncation unmap through another. A Linux lock cannot stay held while the carrier is back in kernelet code, where a tenant-controlled kernel could hold it forever against Linux's own users of the address space.

The lock is sixteen 64-bit words in the space's shared record: each 2 MiB region, what one last-level table covers, is guarded by the word at its region index modulo sixteen, a striped lock. Each word holds a count of readers in its low bits (`READERS` is their mask) and three flags: `WRITER`, set by an exclusive holder; `WRITER_WAITING`, which holds new readers off while a writer waits; and `WAITERS`, which says that someone is asleep in `vm_wait` on this word.

A cursor takes every word its range touches, exclusively for a `cursor_mut` and shared for a `cursor`. It takes them in ascending order, a total order, so two cursors cannot deadlock, and releases them when it is dropped. Uncontended, taking a word is one compare-and-swap on the shared record and no crossing.

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
    let (old, last) = if exclusive { (w.fetch_and(!(WRITER | WAITERS), Ordering::Release), true) }
                      else { /* decrement the readers, clearing WAITERS with the last; last: was this the last reader? */ };
    if old & WAITERS != 0 && last { self.backend().wake(idx); }   // the vm_wake service
}
```

A contended cursor sleeps rather than spins, because the holder may itself be asleep in Linux inside a `vm_map`. The waiter's whole virtual CPU sleeps with it, which costs no more than spinning on a machine's page-table lock would.

The slow path is a futex, Linux's "sleep only if this word still holds this value" primitive. It is rebuilt for carriers because Linux's futex keys on a user address in the caller's address space and this word lives in kernel memory. A waiter sets the `WAITERS` bit and calls `vm_wait(space, word, expected)`; the endovisor takes the space's wait-queue lock, reads the word, returns at once if it no longer equals `expected`, and otherwise puts the carrier to sleep, killably. A releasing holder clears the bit with one atomic read-modify-write and, if it was set and no reader remains, calls `vm_wake`, which wakes every waiter under the same lock. The read under the lock and the single read-modify-write on release are what make a wake-up impossible to lose, by the argument chapter 9 made for `vcpu_idle`: one side marks, then checks; the other changes, then checks the mark; so one of the two always sees the other.

`make mem-conc` has one virtual CPU hold a cursor while its `vm_map` sleeps (a test hook makes it), and the other virtual CPU's cursor on the same region sleeps in `vm_wait` and takes the lock after the release, without a single kernelet task switch.

## A page without read permission

A page without read permission has **no Linux entry**; vOSTD keeps it in a per-space **withheld set** instead. The kernel proper keeps such a page *mapped*, a `PROT_NONE` page with every permission bit cleared or a write-only page alike, since x86 page tables cannot express write without read; on a machine OSTD encodes every such page as a valid but not-present entry.

Linux has no usable encoding for it in this area. Linux periodically makes entries no-access for its NUMA balancing, so that the next touch faults and tells it which processor uses the page, and its fault handler therefore treats every no-access entry in an area that allows access as such a marker and rewrites it with the area's page protection: here read and execute, plus write if the entry's dirty bit is set. A page encoded that way would become readable on its first touch.

The set is an ordered map from address to frame and property, in kernelet memory. It is under the range lock, which orders cursors on one region, and a spin lock of its own, because cursors on different regions share one map. It holds the frame's reference exactly as an entry would. `query`, `find_next`, `protect_next` and `unmap` consult the set beside the table:

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

A tenant access to a withheld page faults as an absent page does, and the kernel proper's own permission check turns that into a `SIGSEGV` for the program, as on a machine. `make mem-func` moves 512 pages into the set with `protect_next` clearing all three permissions, as a kernel proper's `mprotect(PROT_NONE)` would, checks that a read of one is refused, moves them back, and reads them all intact with no fault.

## A space that is dropped at the wrong moment

The last reference to a `VmSpace` can be dropped with virtual interrupts off, where `Drop` may do nothing that may sleep, yet `vm_destroy` sleeps. The drop can come from `activate`, which keeps one reference per virtual CPU to the space active there and drops the previous one's when a new space is activated. A full kernel proper, such as Asterinas's, activates from the handler it runs right after a task switch, with virtual interrupts off, so that drop can be the last; the test kernels of this book activate from `main`, but vOSTD is not written for them alone.

A helper task to do the work later is not available. A task spawned before the kernel proper calls `inject_scheduler` would make OSTD install its default scheduler, and the injection would then fail. A task spawned afterwards is never run by a kernel proper like Asterinas's, whose scheduler enqueues only its own threads; a kernel proper that did accept it would still schedule it by its own policy, at no moment vOSTD can choose, so a busy higher-priority task could hold the frames and the Linux address space indefinitely.

`Drop` pushes the space onto a per-kernelet **retire list**, lock-free and without allocating, since an allocation is `mem_alloc`, which may sleep (the list node was allocated at `new`).

The list is drained at the next point where sleeping is allowed: every sleeping service's wrapper, and `vcpu_idle`, whenever the caller holds no guard and no spin lock, has virtual interrupts on and is not in an upcall. A guard is excluded although rule 1 below allows a sleep under one, because the drain may take long and the caller did not ask for it. The drain unmaps the whole space, which flushes and releases every frame, the withheld set's included, and then calls `vm_destroy`.

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

Inside Linux, a memory service may sleep even when the kernel proper calls it under a preemption guard, which OSTD forbids on a machine. The kernel proper calls `map` holding a preemption guard, because every cursor takes one, and every memory service except `vm_flush`, `vm_activate` and `vm_wake` may sleep in Linux: `vm_map`, `vm_unmap` and `vm_protect` wait for the address-space lock, `vm_map` may wait for a page-table page, `vm_unmap`'s zap may be preempted between page-table pages, and `vm_wait` sleeps by design. The design states the rule in four parts:

1. A service may sleep whenever its work needs it. Its prologue lifts the mirror of chapter 11, so Linux sees nothing wrong, and its epilogue restores it.
2. A service that may sleep must not be called while the caller holds a kernelet **spin lock** or has virtual interrupts off; under a plain preemption guard it may. The reason for the spin lock is lock-holder preemption: a spin lock held across a Linux sleep makes every other virtual CPU that wants it spin for the sleep's length. The reason for the interrupts is that a masked virtual CPU's interrupts would wait out the whole sleep. vOSTD asserts this before every sleeping memory service, with a count of spin locks held that is separate from the guard count.
3. A sleep delays this virtual CPU's pending virtual interrupts until the carrier returns, exactly as a Linux preemption does; the design accepts that.
4. The mirror remains a latency optimization and is load-bearing for correctness nowhere.

Rule 1 is sound because a kernelet's critical section promises only that no kernelet task switch happens on this virtual CPU until the guard drops, as Problem 2 of chapter 11 argued. A sleep in Linux is the same event as a Linux preemption, which the kernelet already survives at any instruction. The guard's other job on a machine, keeping page-table pages alive, has nothing to do here: no table is freed, and vOSTD's read sections count sections, not task switches.

Rule 2 is the one place where vOSTD asks more of the kernel proper than OSTD does: a kernel proper that maps under a spin lock or with virtual interrupts off runs on a machine and is stopped here, because a latency rule the tenant's kernel could break at will is enforced, not counted. Whether Asterinas's full kernel proper keeps the rule everywhere has not been checked. The heap services, which may sleep inside `kmalloc`, carry no assertion and are called under spin locks, the withheld set's insert among them. By rule 4 that costs latency, not soundness: a virtual CPU that wants the lock spins, and hands its turn on through `vcpu_on_spin`, for as long as `kmalloc` sleeps. It is a known gap.

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

Two tests exercise the rule. `make mem-func` runs on a Linux built with `CONFIG_DEBUG_ATOMIC_SLEEP`, which complains whenever Linux code might sleep with Linux's preemption count raised. Inside a preemption guard it maps a page into a fresh 2 MiB region, which makes Linux allocate a page-table page, and Linux reports nothing. `make mem-r2` does the same under a spin lock, and vOSTD stops the kernelet before the call crosses.

<div class="recap">

**Recap.** vOSTD reads Linux's page table through the direct map with a four-level walk that needs no lock, because the endovisor's reference keeps the table alive and Linux writes entries with single stores. Copies walk to the frame and go through its direct-map alias with an opaque `rep movsb`, inside an RCU read section, and `unmap` waits a grace period before it frees a frame. vOSTD counts the Linux entry as holding the frame's reference. A cursor takes a striped range lock whose waiters sleep in Linux through `vm_wait` and `vm_wake`. Pages without read permission live in a withheld set, not in the table. A dropped space goes on a retire list and is destroyed at the next point where sleeping is allowed. A memory service may sleep under a preemption guard, never under a spin lock; the heap services break that rule, a known gap that costs latency.

</div>
