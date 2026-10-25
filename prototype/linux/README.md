# linux: everything that is Linux's

Three things live here: the guest kernel's configuration (`config.fragment`,
this file), the carrier hooks (`patches/`, the one patch to Linux v6.12) and the
endovisor (`endovisor/`, the kernel module that hosts the kernelet). The two
subdirectories have their own `README.md`.

## The configuration

`config.fragment` is what the prototype needs of Linux v6.12 beyond
`tinyconfig`. `make config` (run by `make linux` once) starts from
`tinyconfig`, merges the fragment with the tree's own `merge_config.sh`, and
lets `olddefconfig` settle the rest. Editing the fragment makes the next
`make linux` reconfigure and rebuild.

What it turns on, by section (and one thing it keeps off: vsyscall
emulation, `X86_VSYSCALL_EMULATION`, through which a tenant could have Linux
run `gettimeofday`, `time` or `getcpu` for it without passing the syscall hook; the
endovisor refuses to load on a kernel built with it):

- the basics of a bootable 64-bit guest with a serial console, an initramfs,
  modules, `/proc`, `/sys`, `devtmpfs`, and the system calls the runtimes use;
- seccomp filters, because the syscall hook offers a carrier's system calls to the
  kernelet after seccomp;
- full preemption with `PREEMPT_DYNAMIC`, so that `preempt=none` on the command
  line gives `make yield` a kernel that does not preempt kernel code;
- control groups and group scheduling, for the fairness and cooperation tests;
- `CONFIG_KERNELET`, the carrier hooks (`patches/`), which selects
  `PREEMPT_NOTIFIERS`;
- `RSEQ`, so that the concurrency-id brackets of `kernelet_switch_mm()` are
  exercised;
- `DEBUG_ATOMIC_SLEEP`, so that every memory test would see a service that
  slept under a raised preemption count;
- `BUG`, which `tinyconfig` turns off: without it every `WARN_ON()` in Linux
  is silent, and the tests' check that a log has no `WARNING:` would prove
  nothing; and `DEBUG_BUGVERBOSE`, so that a warning names its file and line;
- swap on virtio, `LRU_GEN`, compaction and transparent huge pages, so that
  `make mem-pressure` drives the reclaim paths a distribution kernel has.

The book explains the hooks and this configuration in chapter 5.

## Files

| file | what it is |
|---|---|
| `config.fragment` | the configuration fragment |
| `patches/` | the carrier hooks, `0001-carrier-hooks.patch` (chapter 5) |
| `endovisor/` | the endovisor module, `endovisor.ko` (chapters 4 and 6 to 13) |
