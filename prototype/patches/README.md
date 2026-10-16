# patches: the gate

`0001-kernelet-gate.patch` is the whole change to Linux v6.12 that a kernelet
needs; everything else is the endovisor module. It adds, behind
`CONFIG_KERNELET`:

- a `kernelet` pointer in `struct task_struct` and a syscall-work bit, which
  together mark a task as a carrier (`include/linux/sched.h`,
  `include/linux/thread_info.h`, `include/linux/entry-common.h`);
- the two hooks of `struct kernelet_gate_ops` in the generic entry code
  (`kernel/entry/common.c`): `syscall`, offered every system call of a carrier
  after seccomp, and `resume`, run on every exit to user mode with work
  pending, before signals are delivered (`include/linux/kernelet.h`);
- `kernelet_switch_mm()`, which makes the current user task run in another
  address space, modelled on `exec_mmap()` with the concurrency-id brackets
  (`kernel/fork.c`);
- `kernelet_mm_alloc()`, `mm_alloc()` with the sandbox's root carrier as the
  memory controller's owner of the new address space (`kernel/fork.c`);
- exports of `kernel_clone`, `set_memory_ro/rox/rw` and `flush_tlb_mm_range`;
- the Kconfig entry, which selects `PREEMPT_NOTIFIERS` (`init/Kconfig`).

The book explains the patch in chapter 4 (the gate), `kernel_clone` in
chapter 5 (carriers), and the two address-space helpers in chapter 12.

## How it is applied

`make patch` at the top level applies it to `.build/linux-6.12` and is
idempotent: a reverse dry run that succeeds means the patch is already in. A
fresh `make source` applies it right after unpacking.
