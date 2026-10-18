# The kernelet ABI

The previous chapter was the view from above the framework: a kernel that allocates frames, maps pages and enters user mode. This chapter is the view from below. Chapter 3 said what an image is, three layers in one file, and named the third of them, the image ABI, without opening it. This chapter opens it: what the host tells a kernelet at start, what the kernelet may call, and what the host calls, down to the three structures that say so. Nothing in it runs yet; it is the shape that the next chapters fill in.

## The three tables

The image ABI has three structures. Here they are, trimmed to what this chapter can explain; the fields left out belong to later chapters.

*Simplified from `prototype/vostd/src/abi.rs`: `BootArgs`, `Services`, `EntryTable`.*

```rust
/// What the endovisor tells the kernelet about the world it was given.
#[repr(C)]
pub struct BootArgs {
    pub abi_version: u64,
    pub grant_paddr: u64,        // the physical address of its memory
    pub grant_len: u64,          // and how much: 4 MiB here
    pub linear_map_base: u64,    // where Linux maps all of physical memory
    pub nr_vcpus: u64,           // how many virtual CPUs the sandbox has
    pub tsc_khz: u64,            // the cycle counter's frequency
    // ... how to find the virtual CPU record, the command line, and more
}

/// The host functions the kernelet may call. Its only way out.
#[repr(C)]
pub struct Services {
    pub abi_version: u64,
    pub log_write: unsafe extern "C" fn(ptr: *const u8, len: u64),
    pub mem_alloc: unsafe extern "C" fn(size: u64, align: u64) -> *mut u8,
    pub mem_free: unsafe extern "C" fn(ptr: *mut u8, size: u64, align: u64),
    pub user_run: unsafe extern "C" fn(ctx: *mut RawUserContext) -> u64,
    pub vm_create: unsafe extern "C" fn() -> i64,
    pub vm_map: unsafe extern "C" fn(space: u64, va: u64, paddr: u64, prot: u32) -> i64,
    // ... vm_unmap, vm_protect, vm_flush, vm_wait, vm_wake, vm_activate, vm_destroy
    pub kstack_alloc: unsafe extern "C" fn() -> u64,
    pub kstack_free: unsafe extern "C" fn(base: u64),
    pub vcpu_boot: unsafe extern "C" fn(id: u64),
    pub vcpu_kick: unsafe extern "C" fn(id: u64),
    pub vcpu_idle: unsafe extern "C" fn(deadline_ns: u64),
    pub vcpu_yield: unsafe extern "C" fn(),
    // ... vcpu_on_spin, fpu_save, fpu_load
    pub stop: unsafe extern "C" fn(code: u64) -> !,
}

/// The kernelet functions the host may call.
#[repr(C)]
pub struct EntryTable {
    pub abi_version: u64,
    pub kernelet_entry: unsafe extern "C" fn(boot: *const BootArgs, svc: *const Services),
    pub vcpu_entry: unsafe extern "C" fn(id: u64),
    pub virq_entry: unsafe extern "C" fn(),
}
```

vOSTD is the only crate in the image allowed to write `unsafe`, so only vOSTD can call a service.

Two rules shape every service. Arguments are integers or pointers into the kernelet's own memory: a space number, a virtual address, a physical address, a buffer to log. The one exception is `mem_free`, whose pointer is into host memory that `mem_alloc` returned, below; the endovisor checks it against a table of the blocks it handed out, kept where the kernelet cannot reach, reads the block's number below the pointer with a read that tolerates a fault, and refuses what it does not recognize (a stale pointer to a block that was freed and handed out again at the same address is the one case it cannot tell apart). And the host writes into the kernelet only through the two pointers vOSTD hands it for that purpose, the context of chapter 8 and the floating-point area of chapter 9, and keeps no other. Both keep a buggy vOSTD from steering the endovisor into writing wherever the kernelet says.

The image's one exported symbol is the entry table:

*Simplified from `prototype/vostd/src/abi.rs`: `kernelet_entry_table`.*

```rust
#[no_mangle]
pub static kernelet_entry_table: EntryTable = EntryTable {
    abi_version: KLET_ABI_VERSION,
    kernelet_entry: crate::kernelet_entry,
    vcpu_entry: crate::vcpu_entry,
    virq_entry: crate::vcpu::klet_virq_entry,
};
```

The endovisor checks `abi_version` against its own when the module loads, and refuses to load if the two halves were built from different ABIs.

In this prototype the image is linked statically into the endovisor's module, so there is one kernelet per module load; registering kinds, as chapter 3 describes, is what a full endovisor does instead, and the shortcut changes nothing below this chapter.

## The grant and the direct map

A kernel needs memory to manage. The endovisor gives a kernelet a **grant**: one physically contiguous block of RAM, 4 MiB in this prototype, taken from Linux's page allocator when the module loads and described in the boot arguments by its physical address and length.

*Simplified from `prototype/linux/endovisor/main.c`: `klet_grant_alloc`.*

```c
static int klet_grant_alloc(struct klet_inst *inst)
{
	inst->grant_pages = alloc_pages(GFP_KERNEL | __GFP_ZERO, KLET_GRANT_ORDER);  /* 2^10 pages */
	if (!inst->grant_pages)
		return -ENOMEM;
	inst->boot.grant_paddr = page_to_phys(inst->grant_pages);
	inst->boot.grant_len = KLET_GRANT_LEN;
	inst->boot.linear_map_base = (u64)(unsigned long)__va(0);
	return 0;
}
```

<div class="linux">

**Linux: the direct map.** Linux maps *all* of physical memory, in order, into one region of the kernel's address space, called the direct map or linear map. Turning a physical address into a pointer the kernel can dereference is therefore one addition: `__va(paddr)` is `paddr + base`. `kmalloc` and the page allocator hand out direct-map memory, so for them a kernel pointer and a physical address are two names for the same bytes; `vmalloc`, which chapter 7 uses, is the exception, because it maps scattered pages into a separate region. The line `__va(0)` above is simply the base.

</div>

vOSTD's frame allocator runs over the grant exactly as OSTD's runs over a machine's RAM: a bitmap with one bit per 4 KiB frame, a first-fit search for `n` contiguous free frames, and a reference count per frame (the count matters in chapter 14). When the kernel proper's `FrameAllocOptions` asks for a segment, this is what answers.

*Simplified from `prototype/vostd/src/mm/frame.rs`: `alloc`, `FrameAllocOptions`.*

```rust
pub(crate) fn alloc(nframes: usize) -> Option<Paddr> {
    let guard = Guard::lock();                 // a spin lock over the bitmap
    let bits = guard.bits();
    let mut start = 0;
    'outer: while start + nframes <= total {
        for i in start..start + nframes {
            if test(bits, i) { start = i + 1; continue 'outer; }   // in use: look further
        }
        for i in start..start + nframes {
            bits[i / 64] |= 1u64 << (i % 64);
            REFS[i].store(1, Ordering::Relaxed);                     // one reference: the handle
        }
        return Some(BASE + start * PAGE_SIZE);
    }
    None
}
```

And the translation from a frame's physical address to something the kernelet can read and write is the same one addition Linux uses, with the base the boot arguments supplied:

*Unchanged from `prototype/vostd/src/mm/mod.rs`: `paddr_to_vaddr`.*

```rust
pub(crate) fn paddr_to_vaddr(paddr: Paddr) -> usize {
    crate::abi::linear_map_base() + paddr
}
```

This is how the hundred-line kernel's `segment.write_bytes(0, program)` lands in RAM: vOSTD adds the base to the segment's physical address and copies there. No page table is touched, because Linux mapped that memory before the kernelet existed.

## Three small services

Three of the services need no more than a sentence each, and the hundred-line kernel uses all three.

**The heap.** Rust's `Vec`, `Box` and `Arc` need a heap. vOSTD's is the host's: a global allocator that forwards each allocation to the services `mem_alloc` and `mem_free`, which the endovisor implements with Linux's `kmalloc` and `kfree`.

*Simplified from `prototype/vostd/src/mm/heap.rs`: `HostHeap`.*

```rust
struct HostHeap;

unsafe impl GlobalAlloc for HostHeap {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        (svc().mem_alloc)(layout.size() as u64, layout.align() as u64)
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        (svc().mem_free)(ptr, layout.size() as u64, layout.align() as u64)
    }
}

#[global_allocator]
static HEAP: HostHeap = HostHeap;
```

**The console.** `println!` collects a line and hands it to `log_write`, which the endovisor prints with `printk`, prefixed `kernelet:`. That is why every line the kernelet prints appears in the serial log beside Linux's own messages.

**Power-off.** `poweroff` is the service `stop`, which never returns. What the endovisor does with it is chapter 12.

## How the kernelet starts

The endovisor enters the image at `kernelet_entry` with the two tables. vOSTD records them, sets up what the chapter has described, and calls the kernel proper's `main`.

*Simplified from `prototype/vostd/src/lib.rs`: `kernelet_entry`.*

```rust
pub(crate) unsafe extern "C" fn kernelet_entry(boot: *const BootArgs, svc: *const Services) {
    abi::init_tables(boot, svc);          // keep the pointers; check the ABI version
    let args = &*boot;
    cpu::init(args.nr_vcpus as usize);
    time::init(args.tsc_khz);
    mm::frame::allocator::init(args.grant_paddr as usize, args.grant_len as usize);
    mm::heap::init();
    boot::init(cmdline);                   // the command line, copied out of the boot arguments
    __ostd_main()                          // generated by #[ostd::main]: calls main(), then yields
}
```

`__ostd_main` is generated by the `#[ostd::main]` attribute on the kernel proper's `main`. It calls `main`, and then calls `Task::yield_now()`, which switches to the first task that `main` started and never returns. That is how the hundred-line kernel goes from piece 1 to piece 3: `main` built a task and returned, and the framework's scheduler ran it.

What remains unexplained is where `kernelet_entry` is *called from*: on which Linux task, on which stack, and how that task later enters user mode for the kernelet. Those are the next four chapters.

<div class="recap">

**Recap.** A kernelet talks to the host through three C-layout tables: boot arguments in, a service table of function pointers out, and an entry table the host calls. Its memory is a grant of 4 MiB whose frames it reaches through Linux's direct map, its heap is `kmalloc` behind a service, and its console is `printk`. The endovisor starts it by calling `kernelet_entry`, which ends in the kernel proper's `main`.

</div>
