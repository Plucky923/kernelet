# linux: the guest kernel's configuration

`config.fragment` is what the prototype needs of Linux v6.12 beyond
`tinyconfig`. `make config` (run by `make linux` once) starts from
`tinyconfig`, merges the fragment with the tree's own `merge_config.sh`, and
lets `olddefconfig` settle the rest. Editing the fragment makes the next
`make linux` reconfigure and rebuild.

What it turns on, by section:

- the basics of a bootable 64-bit guest with a serial console, an initramfs,
  modules, `/proc`, `/sys`, `devtmpfs`, and the system calls the runtimes use;
- seccomp filters, because the gate offers a carrier's system calls to the
  kernelet after seccomp;
- full preemption with `PREEMPT_DYNAMIC`, so that `preempt=none` on the command
  line gives `make yield` a kernel that does not preempt kernel code;
- control groups and group scheduling, for the fairness and cooperation tests;
- `CONFIG_KERNELET`, the gate (`../patches`), which selects
  `PREEMPT_NOTIFIERS`;
- `RSEQ`, so that the concurrency-id brackets of `kernelet_switch_mm()` are
  exercised;
- `DEBUG_ATOMIC_SLEEP`, so that every memory test would see a service that
  slept under a raised preemption count;
- swap on virtio, `LRU_GEN`, compaction and transparent huge pages, so that
  `make mem-pressure` drives the reclaim paths a distribution kernel has.

The book explains the gate and its configuration in chapter 4.

## Files

| file | what it is |
|---|---|
| `config.fragment` | the configuration fragment |
