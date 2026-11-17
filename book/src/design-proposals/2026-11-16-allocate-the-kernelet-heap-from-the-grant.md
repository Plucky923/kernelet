# 2026-11-16 Allocate the kernelet heap from the grant

- Status: Draft
- Author(s): Plucky923
- Discussion: No public review opened yet.
- Affected chapters: [The first kernel we will run](../accepted-design/the-first-kernel-we-will-run.md), [The kernelet ABI](../accepted-design/the-kernelet-abi.md), [Carriers](../accepted-design/carriers.md), [Stopping a kernelet](../accepted-design/stopping-a-kernelet.md), [What vOSTD adds on top](../accepted-design/what-vostd-adds-on-top.md), and [What it costs](../accepted-design/what-it-costs.md).
- Implementation or experiments: Not yet implemented. The argument below comes from source inspection; no local-heap performance or fault-injection results are available.

## Summary

This proposal removes `mem_alloc`, `mem_free`, and the endovisor's per-block heap table. Instead, vOSTD implements Rust's `#[global_allocator]` (`Box`, `Vec`, `Arc`) directly over grant pages using OSTD's `Frame` and `MetaSlot` model. Moving the heap into the grant eliminates 449-cycle `mem_alloc`/`mem_free` round-trips and sleeping `kmalloc` calls under kernelet spin locks. Linux still delivers, accounts for, and reclaims the grant whole after execution, host accesses, and descriptor references end.

## Problem and motivation

### Host page ownership vs. kernelet objects

A kernelet needs physical pages for user spaces (`UFrame`), its Rust heap (`Box`, `Vec`, `Arc`), and per-page metadata. Linux meters every backing page and reclaims the grant after sandbox exit and final descriptor close ([Stopping a kernelet](../accepted-design/stopping-a-kernelet.md#the-shape-of-a-death)). Subdividing grant pages into aligned objects inside vOSTD meets both host requirements without host calls per object.

### How the accepted host heap works and what it costs

Today, `FrameAllocOptions` draws user pages from a [grant](../accepted-design/the-kernelet-abi.md#the-grant-and-the-direct-map) capped at 4 MiB by a single `alloc_pages(MAX_PAGE_ORDER)` call. Meanwhile, `HostHeap` (`prototype/vostd/src/mm/heap.rs`) forwards Rust allocations to `mem_alloc` and `mem_free`. In `new_frames` (`prototype/kernels/mem/src/lib.rs`), user frames come from the grant while `Vec<UFrame>` comes from Linux because 4 MiB was too tight.

Forwarding every Rust object to Linux adds three concrete costs:

1. **Per-object crossings and lock contention.** Each `alloc` or `free` switches to the Linux stack and takes `inst->heap.lock` to update `inst->heap.block`. [What it costs](../accepted-design/what-it-costs.md#the-crossing) measures 449 cycles for one 64-byte `mem_alloc`/`mem_free` pair, including ~120 cycles for the block table.
2. **Sleeping allocations under spin locks.** `mem_alloc` calls `kmalloc(GFP_KERNEL_ACCOUNT)`, which may sleep. Calling `Box` or `Vec` under a kernelet spin lock violates Rule 2 and can stall sibling vCPUs ([What vOSTD adds on top](../accepted-design/what-vostd-adds-on-top.md#the-rule-about-sleeping)).
3. **Per-block padding and teardown scans.** The endovisor pads every block by alignment (`size + align`) and maintains a dynamically grown `inst->heap.block` table. At teardown, `klet_heap_destroy` scans that table to `kfree` every leaked block.

## Proposed change

Linux continues to deliver, account for, and finally reclaim the grant. vOSTD manages pages and object storage within it.

### Use OSTD's frame model within the grant

Sharing the grant between kernel objects and user memory requires tracking each page's role so kernel pages never escape to user space. Adopting OSTD's `Frame`, `UniqueFrame`, `MetaSlot`, and buddy allocator provides type safety, refcounts, coalescing, and slab metadata:

<div class="background">

**OSTD: direct-map frames and slabs.** OSTD maps physical RAM once at boot via a fixed offset (`paddr_to_vaddr`) and never remaps kernel allocations. OSTD's [`GlobalFrameAllocator`](https://github.com/asterinas/asterinas/blob/ab9a4cfdc726263b3f41ccea0337633e24b443fc/ostd/src/mm/frame/allocator.rs#L130-L175) trait fronts the page allocator, while each page has a 64-byte [`MetaSlot`](https://github.com/asterinas/asterinas/blob/ab9a4cfdc726263b3f41ccea0337633e24b443fc/ostd/src/mm/frame/meta.rs#L75-L118) storing `M`, its refcount, vtable, and list ID (`in_list`). [`Frame<M>`](https://github.com/asterinas/asterinas/blob/ab9a4cfdc726263b3f41ccea0337633e24b443fc/ostd/src/mm/frame/mod.rs#L81-L121) shares read access to `M`, and [`UniqueFrame<M>`](https://github.com/asterinas/asterinas/blob/ab9a4cfdc726263b3f41ccea0337633e24b443fc/ostd/src/mm/frame/unique.rs#L18-L54) holds exclusive write ownership. OSTD's [`Slab`](https://github.com/asterinas/asterinas/blob/ab9a4cfdc726263b3f41ccea0337633e24b443fc/ostd/src/mm/heap/slab.rs#L23-L52) slices a `UniqueFrame` via `paddr_to_vaddr`, keeping free links in unused slots and `SlabMeta` in `MetaSlot`; only `UFrame` mappings edit user page tables.

</div>

1. **Supply startup grant segments.** Pass one or more startup `alloc_pages` runs via `BootArgs` to lift the 4 MiB single-allocation cap without runtime resizing.
2. **Reserve grant-resident `MetaSlot` arrays.** Carve pinned `MetaSlot` pages (`MetaPageMeta`, 64 bytes per page, ~1.56%) from each segment's start before initializing allocators.
3. **Map bidirectionally in `frame_to_meta` and `meta_to_frame`.** Validate alignment, check segment bounds without overflow, and reject inter-segment holes in both conversion directions.
4. **Manage free pages with OSDK's buddy allocator.** Store buddy links (`Link<FreeHeadMeta>`) inside unused `MetaSlot`s, and drain per-vCPU caches and empty slabs before returning `Error::NoMemory`.

During normal execution, dropping the last reference runs `M`'s `on_drop` and Rust destructor before returning the page to the buddy pool. For page tables, detaching root entries after TLB and RCU quiescence lets `PageTablePageMeta::on_drop` release child tables and frames once. On sandbox failure, Linux reclaims all grant segments whole without invoking `on_drop`.

### Connect Rust allocation to the local heap

Replace `HostHeap` (`prototype/vostd/src/mm/heap.rs`) with OSTD's `AllocDispatch` (`#[global_allocator]`) backed by OSDK's `HeapAllocator` implementing `GlobalHeapAllocator`. Objects up to 2,048 bytes with natural alignment allocate from single-page `Slab` classes (`Link<SlabMeta<SLOT_SIZE>>`). Requests above 2,048 bytes or requiring larger alignment route to aligned `LargeAllocFrameMeta` `HeapSlot` segments from the buddy pool. Address conversions (`paddr_to_vaddr` and `HeapSlot::paddr`) use Linux's runtime `linear_map_base` rather than compile-time constants. Exhaustion returns null to `GlobalAlloc` (entering the allocation-error handler) instead of calling `kmalloc`.

### Keep heap pages private to the kernel

Live kernel pages hold Rust objects or metadata and must never be exposed to untrusted code or user space:

- **Typed-frame and `VmIo` boundary.** `SlabMeta`, `LargeAllocFrameMeta`, `PageTablePageMeta`, and `MetaPageMeta` never implement `AnyUFrameMeta`, and vOSTD restricts `VmIo` byte access and `is_untyped()` casts to `AnyUFrameMeta`.
- **Mandatory zeroing.** Keep `FrameAllocOptions::zeroed(false)` internal to vOSTD (`pub(crate)`), so every untyped frame exposed to `kernel proper` or user space starts zeroed.
- **Trusted allocator code.** Allocator code stays inside trusted vOSTD under the [language-based isolation model](../accepted-design/why-a-kernel-of-your-own.md#the-same-kernel-a-different-framework), with no hardware boundary inside the grant.

### Initialize the heap without depending on itself

Bootstrap must break circular dependencies between metadata, page allocation, and the heap:

1. **Strict startup order.** Initialize `MetaSlot` storage, the buddy allocator, and the local heap before secondary vCPUs or heap consumers (`cmdline` parsing and `__ostd_main`).
2. **Allocation-free teardown, panic, and OOM paths.** Keep `panic_handler`, `alloc_error_handler`, `CursorMut::unmap`, and `VmSpace` retirement allocation-free so OOM or teardown never recurses into the heap.
3. **Interrupt-safe locking.** Guard allocators with `SpinLock<..., LocalIrqDisabled>` (no `mem_alloc` crossings or lock-order cycles, calling `vcpu_on_spin` only on extended contention).

### Reclaim the grant after a failure

When a sandbox exits or fails, Linux reclaims grant segments from its own host-side segment array (never trusting grant memory):

1. **Stop execution.** Halt all carriers and block further sandbox entry so no kernelet or user-context access remains active.
2. **Drain host references.** Finish in-flight host calls, active I/O leases ([TypedIO](2026-11-08-typed-io.md)), and address-space, TLB, and RCU teardown ([Stopping a kernelet](../accepted-design/stopping-a-kernelet.md#the-shape-of-a-death)).
3. **Free all grant segments.** Release every recorded `(struct page *, order)` segment on startup rollback or after exit and final sandbox descriptor close.

### Account for the shared capacity

Linux already charges grant segments via `GFP_KERNEL_ACCOUNT` (`prototype/linux/endovisor/sandbox.c`), so subdividing them into Rust objects adds no host charge. Heap objects, `UFrame`s, lower page tables, `MetaSlot` pages, and OSDK caches share this fixed startup budget (contiguous runs stay bounded by one segment). Sizing `memory_initial` above the prototype's 4 MiB single-block cap via multiple startup segments absorbs those caches without runtime resizing. Linux separately charges per-instance private image pages (`image.c`), kernelet stacks, and address spaces (while shared read-only kind pages belong to kind registration).

## Alternatives and tradeoffs

| Alternative | Benefits | Costs and limits |
|---|---|---|
| Keep the host heap | Reuses `kmalloc`/`kfree` outside the grant | Keeps 449-cycle alloc/free pairs, `inst->heap.block`, and sleeping under spin locks |
| Split a fixed heap sub-region | Fixes heap and user quotas at boot | Strands idle pages on one side when the other fills |
| Share one buddy pool in the grant | Shifts pages dynamically between heap and `UFrame`s | Requires `AnyUFrameMeta`/`VmIo` isolation, enforced zeroing, and cache headroom |

## Implementation and integration

Replacing the host heap removes temporary prototype shortcuts across vOSTD, the image ABI, and the endovisor:

| Location | Proposed work |
|---|---|
| `prototype/vostd/src/mm/frame.rs` | Implement `MetaSlot`, typed frames (`VmIo` restricted to `AnyUFrameMeta`, `pub(crate)` `zeroed(false)`), bidirectional segment lookup, and OSDK's buddy allocator with OOM cache drain |
| `prototype/vostd/src/mm/heap.rs` | Wire `AllocDispatch` to OSDK's `HeapAllocator` (`Slab` and aligned `LargeAllocFrameMeta` `HeapSlot`s using runtime `linear_map_base`) |
| `prototype/vostd/src/lib.rs`, `panic.rs`, and `mm/vm_space.rs` | Enforce zero-heap bootstrap ordering and allocation-free `panic`, OOM, `unmap`, and `VmSpace` retirement paths |
| `prototype/vostd/src/abi.rs` and `prototype/linux/endovisor/` | Remove `mem_alloc`, `mem_free`, and `inst->heap.block`; track multi-segment grants in host records and `klet_in_grant()`; bump `KLET_ABI_VERSION` |
| `prototype/kernels/` and host tests | Replace host-heap and 4 MiB cap assumptions with local-heap, alignment, isolation, exhaustion, and multi-segment cleanup checks |
| Affected Accepted Design chapters | Document multi-segment startup grants, local object allocation, whole-grant cleanup, and measured costs after acceptance |

`prototype/vostd/src/mm/frame.rs` serves as the shared foundation for both this design and the [direct page-table update proposal](2026-11-13-direct-page-table-updates-in-vostd.md). In both proposals, lower kernelet allocations consume grant pages while Linux-allocated `mm->pgd` stays outside `MetaSlot`. With multi-segment `klet_in_grant()`, the local heap also works independently under the accepted Linux-managed page tables.

## Validation and evidence

Source inspection establishes the current host heap path, block table, and OSTD allocator contracts. The prototype has no implemented local heap or measured speedup yet. Acceptance requires the existing prototype suite plus targeted checks across six behaviors:

| Area | Required evidence |
|---|---|
| Allocation contracts | Test small classes, page- and over-aligned `HeapSlot`s, runtime `linear_map_base` round-trips, reallocation, and split deallocation without overlap or hole acceptance. |
| Ownership and zeroing | Verify `SlabMeta`, `LargeAllocFrameMeta`, `PageTablePageMeta`, and `MetaPageMeta` reject `UFrame`/`VmIo` access, `kernel proper` cannot skip zeroing, and `on_drop` runs once. |
| Bootstrap and concurrency | Boot without host heap calls. Test multi-vCPU allocations, lock ordering, IRQ state, and OOM paths under `LocalIrqDisabled` spin locks without recursion or sleeping. |
| Fixed capacity and cache drain | Drain caches across vCPUs before `Error::NoMemory`, and confirm `unmap` and teardown succeed without heap growth when the grant is full. |
| Failure cleanup | Destroy sandboxes after partial boot failure, active I/O drain, or leaked `Box`/`Vec`s. After final descriptor close, verify host segment records release all charges. |
| Cost and zero heap crossings | Verify zero `mem_alloc`/`mem_free` calls (allowing `vcpu_on_spin` on contention). Compare cycle counts against the 449-cycle baseline under matched workloads. |

## Open questions

- Should multi-segment startup grants above 4 MiB pass an inline segment array in `BootArgs` or a descriptor table in the first segment?
- What default startup grant size (such as `16 MiB` or `32 MiB`) leaves ample headroom beyond OSDK's caches for typical workloads?

## Decision and follow-up

Status remains Draft pending implementation and benchmark evidence. This proposal defines the shared `MetaSlot`, buddy frame, and local slab allocator over a fixed startup grant. Accepted Design and the prototype keep the host heap until implementation and measurements land.
