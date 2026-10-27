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
- `kernelet_mm_alloc()`, `mm_alloc()` with the sandbox's owner task as the
  memory controller's owner of the new address space (`kernel/fork.c`);
- two exports not already provided to modules: `kernel_clone`
  (`kernel/fork.c`), retained from the earlier carrier implementation,
  and `flush_tlb_mm_range` (`arch/x86/mm/tlb.c`), the synchronous
  flush of `vm_flush`;
- the Kconfig entry, which selects `PREEMPT_NOTIFIERS` (`init/Kconfig`);
- four more exports, for the endovisor's PIE image loader and registration:
  `set_memory_rox`, `set_memory_ro`, and `set_memory_rw`
  (`arch/x86/mm/pat/set_memory.c`) set executable/read-only permissions and
  restore backing-page writability before freeing; `modules_disabled`
  (`kernel/module/main.c`) is checked by `KLET_KIND_REGISTER` as by `init_module`.
  Each is one `EXPORT_SYMBOL_GPL` line:

  ```text
  arch/x86/mm/pat/set_memory.c  +EXPORT_SYMBOL_GPL(set_memory_rox);
  arch/x86/mm/pat/set_memory.c  +EXPORT_SYMBOL_GPL(set_memory_ro);
  arch/x86/mm/pat/set_memory.c  +EXPORT_SYMBOL_GPL(set_memory_rw);
  kernel/module/main.c          +EXPORT_SYMBOL_GPL(modules_disabled);
  ```

  `kernel_clone` is no longer used: the carriers are the holder's children,
  made by `fork`; its export stays in the patch.

It adds 223 lines (202 of them not blank) and removes none, counted with
`git apply --numstat`.

The book explains the patch in chapter 5 (carrier hooks), `kernel_clone` in
chapter 6 (carriers), the two address-space helpers in chapter 13, and the
image loader's exports in chapter 2.

## How it is applied

`make patch` at the top level applies it to `.build/linux-6.12` and is
idempotent: a reverse dry run that succeeds means the patch is already in. It
leaves a stamp, `.build/linux-6.12/.carrier-hooks-patch`, so it runs once per
change of the patch file, and `make source` and `make linux` both go through
it. The patch was generated with `diff -u` against pristine v6.12 files. A
tree that has an older version of the patch applied is not brought up to
date by `make patch`: the reverse dry run of the new patch fails and the
forward one finds most of it applied already. Apply the difference by hand
(the PIE permission-export changes were applied so) or start from a pristine tree.
