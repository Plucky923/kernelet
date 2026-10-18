# patches: the carrier hooks

`0001-carrier-hooks.patch` is the whole change to Linux v6.12 that a kernelet
needs; everything else is the endovisor module. It adds, behind
`CONFIG_KERNELET`:

- a `carrier_hooks` pointer in `struct task_struct` and a syscall-work bit, which
  together mark a task as a carrier (`include/linux/sched.h`,
  `include/linux/thread_info.h`, `include/linux/entry-common.h`);
- the two hooks of `struct carrier_event_hooks` in the generic entry code
  (`kernel/entry/common.c`): `syscall`, offered every system call of a carrier
  after seccomp, and `resume`, run on every exit to user mode with work
  pending, before signals are delivered (`include/linux/kernelet.h`). For a
  carrier, the exit loop runs Linux's own resume work, which clears
  `TIF_NOTIFY_RESUME`, *before* the hook rather than after it, so that a
  virtual interrupt the endovisor flags while the hook runs is not cleared
  with it but makes the loop run the hook again;
- `kernelet_switch_mm()`, which makes the current user task run in another
  address space, modelled on `exec_mmap()` with the concurrency-id brackets
  (`kernel/fork.c`);
- `kernelet_mm_alloc()`, `mm_alloc()` with the sandbox's root carrier as the
  memory controller's owner of the new address space (`kernel/fork.c`);
- two exports, of the two functions the endovisor needs that Linux does not
  already export: `kernel_clone` (`kernel/fork.c`), which clones the vCPU
  carriers, and `flush_tlb_mm_range` (`arch/x86/mm/tlb.c`), the synchronous
  flush of `vm_flush`;
- the Kconfig entry, which selects `PREEMPT_NOTIFIERS` (`init/Kconfig`).

It adds 219 lines (198 of them not blank) and removes none, counted with
`git apply --numstat`.

The book explains the patch in chapter 4 (carrier hooks), `kernel_clone` in
chapter 5 (carriers), and the two address-space helpers in chapter 12.

## How it is applied

`make patch` at the top level applies it to `.build/linux-6.12` and is
idempotent: a reverse dry run that succeeds means the patch is already in. It
leaves a stamp, `.build/linux-6.12/.carrier-hooks-patch`, so it runs once per
change of the patch file, and `make source` and `make linux` both go through
it. The patch was generated with `diff -u` against pristine v6.12 files.
