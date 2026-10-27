# The kernelet ABI

The previous chapter was the view from above the framework: a kernel that allocates frames, maps pages and enters user mode. This chapter is the view from below: what is in the image file that the holder registered, and how the code in it talks to the host. Nothing in it runs yet; it is the shape that the next chapters fill in.

A kernelet image is two layers of code compiled into one file, held together by a third thing, an interface.

1. **The kernel proper**, the hundred-line kernel of the last chapter: safe Rust, never edited.
2. **vOSTD**, a Rust crate whose library name is `ostd`, so that the kernel proper's `use ostd::...` lines resolve to it. It offers every type and function the kernel proper uses, with the same names and signatures as the real OSTD. It is in `prototype/vostd/`.
3. **The image ABI** (an *application binary interface* is the exact layout of what two separately compiled pieces of code pass each other), a few C-layout structures that both vOSTD and the endovisor know: what the host tells the kernelet at start, which functions the kernelet may call, and which functions the host may call. It is in `prototype/vostd/src/abi.rs` on the Rust side and `prototype/linux/endovisor/kernelet.h` on the C side, and the two must agree byte for byte.

The first two are the image's contents; the third is this chapter's subject.

Registering an image validates the restricted PIE format described in [the endovisor UAPI](the-endovisor-uapi.md#the-image-format-and-its-requirements). The build links the kernel proper and vOSTD into one self-contained `ET_DYN` image, whose program headers fix the relative layout of code and data. The image imports no host symbols; it calls Linux through the service table supplied at entry. The ELF header's `e_entry` identifies the entry-table object below, which the endovisor reads rather than executing as an instruction.

The registered kind owns one physical copy of the code and read-only data and a pristine template for writable data. Each sandbox gets a separate virtual mapping of that layout: shared physical pages for code and read-only data, fresh pages for writable data and zero-initialized storage. `R_X86_64_RELATIVE` relocations initialize its private pointers using its own load base. The entry table therefore contains addresses within that sandbox's code mapping. Multiple sandboxes of one kind can run concurrently; the code is shared, while globals, pointer tables and vOSTD's state are private.

<div class="background">

**Linux: modules and exported symbols.** A kernel module, code loaded into the running kernel with `insmod`, may call only the kernel functions that the kernel marks as **exported** (`EXPORT_SYMBOL` in the source); the rest are private to the kernel even though they are in the same address space. The endovisor is a module. A few functions it needs are not exported in a stock kernel, which is one of the two reasons for the patch in the next chapter.

</div>

## The three tables

The image ABI has three structures. Here they are, trimmed to what this chapter can explain; the fields left out belong to later chapters.

*Simplified from `prototype/vostd/src/abi.rs`: `BootArgs`, `Services`, `EntryTable`.*

```rust
/// What the endovisor tells the kernelet about the world it was given.
#[repr(C)]
pub struct BootArgs {
    pub abi_version: u64,
    pub grant_paddr: u64,        // the physical address of its memory
    pub grant_len: u64,          // and how much: 2 or 4 MiB here
    pub linear_map_base: u64,    // where Linux maps all of physical memory
    pub nr_vcpus: u64,           // how many virtual CPUs the sandbox has
    // ... how to find the virtual CPU record, and the floating-point area's size
    pub tsc_khz: u64,            // the cycle counter's frequency
    // ... the command line, and more
}

/// The host functions the kernelet may call. Its only way out.
#[repr(C)]
pub struct Services {
    pub abi_version: u64,
    pub log_write: unsafe extern "C" fn(ptr: *const u8, len: u64),
    // ... console_write, added later in the table
    pub mem_alloc: unsafe extern "C" fn(size: u64, align: u64) -> *mut u8,
    pub mem_free: unsafe extern "C" fn(ptr: *mut u8, size: u64, align: u64),
    pub user_run: unsafe extern "C" fn(ctx: *mut RawUserContext) -> u64,
    pub vm_create: unsafe extern "C" fn() -> i64,
    // ... vm_destroy, vm_activate
    pub vm_map: unsafe extern "C" fn(space: u64, va: u64, paddr: u64, prot: u32) -> i64,
    // ... vm_unmap, vm_protect, vm_flush, vm_wait, vm_wake
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

vOSTD is the only crate in the image that can reach the service table, which it keeps private, so only vOSTD can call a service.

Two rules shape every service. Arguments are integers or pointers into the kernelet's own memory: a space number, a virtual address, a physical address, a buffer to log. The one exception is `mem_free`, whose pointer is into host memory that `mem_alloc` returned, below; the endovisor checks it against a table of the blocks it handed out, kept where the kernelet cannot reach, reads the block's number below the pointer with a read that tolerates a fault, and refuses what it does not recognize (a stale pointer to a block that was freed and handed out again at the same address is the one case it cannot tell apart). And the host writes into the kernelet only through the two pointers vOSTD hands it for that purpose, the user context that `user_run` is given and the area that `fpu_save` is given, and keeps no other. Both keep a buggy vOSTD from steering the endovisor into writing wherever the kernelet says.

vOSTD defines the entry table under the symbol `kernelet_entry_table`; the final linker records its address in ELF's `e_entry` field:

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

The endovisor checks the entry table's `abi_version` against its own when an image is registered, and refuses the image if the two halves were built from different ABIs.

## The grant and the direct map

The endovisor gives a kernelet a **grant**: one physically contiguous block of RAM, the `memory_initial` of the holder's create request (4 MiB from the prototype's holder; a request is rounded up to 2 MiB and may not exceed 4 MiB), taken from Linux's page allocator when the sandbox starts, charged to the sandbox's control group, and described in the boot arguments by its physical address and length.

*Simplified from `prototype/linux/endovisor/sandbox.c`: `klet_sandbox_start`.*

```c
int klet_sandbox_start(struct klet_inst *inst)
{
	unsigned int order = get_order(inst->memory_initial);       /* 2^10 pages for 4 MiB */

	int err = klet_image_start(inst);                          // Shared code, private data and relocated pointers.
	if (err)
		return err;
	pages = alloc_pages(GFP_KERNEL_ACCOUNT | __GFP_ZERO | __GFP_NOWARN, order);
	if (!pages)
		return -ENOMEM;
	inst->grant_pages = pages;
	inst->boot.abi_version = KLET_ABI_VERSION;
	inst->boot.grant_paddr = page_to_phys(pages);
	inst->boot.grant_len = PAGE_SIZE << order;
	inst->boot.linear_map_base = (u64)(unsigned long)__va(0);
	inst->boot.nr_vcpus = inst->nr_vcpus;
	/* ... the FPU area's size, the cycle counter's rate, the image's text range, and more in later chapters */
	return 0;
}
```

<div class="background">

**Linux: the direct map.** Linux maps *all* of physical memory, in order, into one region of the kernel's address space, called the direct map or linear map. Turning a physical address into a pointer the kernel can dereference is therefore one addition: `__va(paddr)` is `paddr + base`. `kmalloc` and the page allocator hand out direct-map memory, so for them a kernel pointer and a physical address are two names for the same bytes; `vmalloc`, from which the endovisor takes kernelet stacks, is the exception, because it maps scattered pages into a separate region. The line `__va(0)` above is simply the base.

</div>

vOSTD's frame allocator plays over the grant the part OSTD's plays over a machine's RAM, more simply: where the allocator shipped with OSTD is a buddy system, vOSTD's is a bitmap with one bit per 4 KiB frame, a first-fit search for `n` contiguous free frames, and a reference count per frame (the count matters once tenant pages sit on Linux's page tables). When the kernel proper's `FrameAllocOptions` asks for a segment, this is what answers.

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

**The console and the log.** `println!` collects a line and hands it to `console_write`, the sandbox's console; vOSTD's own lines, among them a panic's message, go to `log_write`, the sandbox's kernel log. Each arrives at the file the holder set for it, through a ring that a work item drains, because a service may not block on a terminal or a pipe while the kernel proper may hold one of its spin locks. A sandbox given no file for one of the two has its lines printed with `printk`, prefixed `kernelet:`, which is why they then appear in the serial log beside Linux's own messages.

**Power-off.** `poweroff` is the service `stop`, which never returns. The endovisor ends the sandbox with it, never the host.

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

`__ostd_main` calls `main` and then `Task::yield_now()`, which, since `main` started a task, switches to it and never returns. That is how the hundred-line kernel goes from piece 1 to piece 3: `main` built a task and returned, and the framework's scheduler ran it.

What remains unexplained is where `kernelet_entry` is *called from*: on which Linux task, on which stack, and how that task later enters user mode for the kernelet. Those are the next four chapters.

<div class="recap">

**Recap.** A kernelet talks to the host through three C-layout tables: boot arguments in, a service table of function pointers out, and an entry table the host calls. Its memory is a grant of a few MiB whose frames it reaches through Linux's direct map, its heap is `kmalloc` behind a service, and its console and log go to files the holder sets, or to `printk` if it sets none. The endovisor starts it by calling `kernelet_entry`, which ends in the kernel proper's `main`.

</div>
