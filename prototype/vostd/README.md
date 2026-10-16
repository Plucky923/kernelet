# vostd: the OSTD-shaped API, virtualized

vOSTD is the library a kernel proper is compiled against when it runs as a
kernelet on Linux. Its crate is `vostd` and its library name is `ostd`, so a
kernel proper says `ostd = { package = "vostd", ... }` and its source does not
change: the 100-line kernel in `../hello` is compiled against it byte for
byte. It exposes the same paths, types and signatures as Asterinas's OSTD at
commit `ab9a4cfdc` for everything the kernels in this repository use, plus a
few members of the same interface that no kernel here calls but a kernel
written against OSTD would reasonably reach for, kept for completeness:
`Task::need_yield`, `CpuId::bsp`, `SpinLock::try_lock`, `WaitQueue::wake_one`,
`VmSpace::reader_writer`, and `UserContext::general_regs` and
`general_regs_mut`. Four more blocks carry `#[allow(dead_code)]` because they
describe a format whole although only part of it is read: the
`PagingConstsTrait` in `src/mm/mod.rs` (the shape OSTD gives the trait; only
`BASE_PAGE_SIZE` is read), the `pte` bits in `src/mm/page_table.rs` (every x86-64
entry bit; the walk reads a few), the constants of `PageFaultErrorCode` in
`src/arch/cpu/context.rs` (every bit of the hardware's error code), and the
methods the flags macro in `src/mm/page_prop.rs` gives every flag type (not
every type uses every method). Nothing else.

Where real OSTD talks to hardware, vOSTD talks to the endovisor through the
image ABI (`src/abi.rs`): a table of services the kernelet may call, a table
of entry points the host may call, the boot arguments, and one record per
virtual CPU. It never calls a Linux symbol. The task layer, the scheduler
interface, the context switch and the synchronization primitives are real
OSTD's, ported with as little change as possible; what is virtualized is the
machine beneath them. The book explains vOSTD in chapters 3 (what a kernelet
is made of), 8 (tasks and virtual CPUs), 9 (virtual interrupts), 10 (sharing
a processor) and 13 (what vOSTD adds on top of Linux's page tables).

## How it is built

Never on its own: the top-level `make image` builds it together with one
kernel proper (`KLET_KERNEL=hello`, the default) for `x86_64-unknown-none`,
with `-Zbuild-std`, a static relocation model, the kernel code model and no
red zone, and pre-links the result into `endovisor/image.o_shipped`, which the
endovisor module links in. `OSTD_TASK_STACK_SIZE_IN_PAGES` is set to 64 so
that OSTD's task layer asks for exactly the 256 KiB kernelet stacks the
endovisor's pool hands out.

## Files

| file | what it is | chapter |
|---|---|---|
| `Cargo.toml` | the crate; its one dependency is the real `ostd-macros` (`../libs`) | 2 |
| `src/lib.rs` | the crate root; `kernelet_entry` (vCPU 0) and `vcpu_entry` (the others) | 3, 8 |
| `src/abi.rs` | the image ABI: `BootArgs`, `Services`, `EntryTable`, `VcpuRec`, `SpaceRec`, `MemStats`, `kernelet_entry_table` | 3 |
| `src/vcpu.rs` | finding the vCPU record without a call (`vrec`), the mirror of the guard depth into Linux's preemption count, the upcall stub `klet_virq_entry` and `klet_virq_body`, idle, kick, yield, `vcpu_on_spin`; `publish_stack_limit`, which tells the endovisor the bound of the current kernelet stack | 6, 8, 9, 10 |
| `src/klet.rs` | not OSTD API: the counters the tests read, and the test hook that makes `vm_map` sleep | 13, 14 |
| `src/console.rs` | `println!`, line-buffered onto the `log_write` service | 3 |
| `src/panic.rs` | a kernelet panic stops the sandbox, not the machine | 11 |
| `src/power.rs` | `poweroff`: the `stop` service | 11 |
| `src/time.rs` | the clock, read from the cycle counter directly | 9 |
| `src/error.rs`, `src/prelude.rs` | real OSTD's error type and prelude | 2 |
| `src/utils.rs` | a spin-initialised `Once`, so that vOSTD has no other dependency | – |
| `src/user.rs` | `UserMode`, its hooks and return reasons | 7 |
| `src/arch/cpu/context.rs` | `UserContext`, its `execute` loop over `user_run`, CPU exceptions, `FpuContext` on the `fpu_save`/`fpu_load` services | 7, 8 |
| `src/arch/trap.rs` | `RawUserContext::run`, the call of `user_run` | 7 |
| `src/arch/mod.rs` | the architecture module: x86-64 only, and `read_tsc` | 9 |
| `src/arch/cpu/mod.rs` | the CPU module: `context` | 7 |
| `src/arch/irq.rs` | interrupt masking: the vCPU record's `irq_off` | 9 |
| `src/arch/mm.rs` | x86-64 paging constants; what this vCPU has activated | 12 |
| `src/arch/task/mod.rs`, `src/arch/task/switch.S` | OSTD's context switch, `switch.S` byte for byte | 6, 8 |
| `src/boot/mod.rs` | the boot information: the sandbox's command line | 3 |
| `src/boot/smp.rs` | starting the other virtual CPUs with `vcpu_boot` | 8 |
| `src/cpu/mod.rs`, `src/cpu/local.rs` | `CpuId`, CPU-local storage indexed by vCPU, `cpu_local_cell!` | 8 |
| `src/irq/mod.rs` | `disable_local` and `DisabledLocalIrqGuard`; interrupt or task level | 9 |
| `src/sync/spin.rs` | OSTD's spin lock, telling the host after a long spin; `r2`, the sleeping contract's spin-lock count | 10, 13 |
| `src/sync/wait.rs`, `src/sync/guard.rs`, `src/sync/mod.rs` | wait queues and lock guard behaviors, ported | 8 |
| `src/task/mod.rs`, `src/task/processor.rs` | OSTD's task layer: `Task`, `switch_to_task`, `after_switching_to` | 8 |
| `src/task/kernel_stack.rs` | `KernelStack`: kernelet stacks from the endovisor's pool | 6 |
| `src/task/atomic_mode.rs` | `might_sleep` and atomic mode, which here is the vCPU record's two facts | 8 |
| `src/task/preempt/` | the preemption word in the vCPU record, `inc_guard_count`, `dec_guard_count`, `irq_mask`, `irq_unmask`; the guard; `halt_cpu` | 8, 10 |
| `src/task/scheduler/` | OSTD's scheduler injection, `might_preempt`, `reschedule`, `vcpu_idle_loop`, the default FIFO scheduler | 8 |
| `src/task/utils.rs` | a helper of the task module, ported | – |
| `src/timer/mod.rs`, `src/timer/jiffies.rs` | tick callbacks, run by the TICK virtual interrupt; `Jiffies` computed from the clock | 9 |
| `src/mm/mod.rs` | address types, `paddr_to_vaddr`: every access to tenant memory goes through the host's direct map | 3 |
| `src/mm/frame.rs` | frames of the grant, reference-counted: `Frame::into_raw`, `from_raw`, `FrameRef` | 3, 13 |
| `src/mm/heap.rs` | the Rust heap, on the `mem_alloc` and `mem_free` services, and the one-off measurement of an allocation and its free | 3 |
| `src/mm/backend.rs` | `Backend`: one Linux address space, and the `vm_*` services that change it | 12 |
| `src/mm/vm_space.rs` | `VmSpace`, `Cursor`, `CursorMut`; the range lock, the withheld set, the retire list | 12, 13 |
| `src/mm/page_table.rs` | the lockless walk of a Linux page table through the direct map | 13 |
| `src/mm/io.rs` | `VmReader`, `VmWriter`: copies that walk the table chunk by chunk | 13 |
| `src/mm/rcu.rs` | the grace period before an unmapped frame is freed | 13 |
| `src/mm/tlb.rs` | `TlbFlusher`, dispatched as `vm_flush` | 13 |
| `src/mm/page_prop.rs` | page flags and properties, real OSTD's values | 12 |
