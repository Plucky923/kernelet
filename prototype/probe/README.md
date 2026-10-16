# probe: the three mechanisms the 100-line kernel never reaches

A second kernel proper in the style of the 100-line kernel, written for this
prototype against the same API, that drives:

1. **demand paging**: only the program's text is mapped; the program stores
   to an unmapped page, the area's fault handler reports the fault to the
   kernelet as a page-fault exception, the kernel maps a fresh frame there,
   and the store is retried;
2. **three non-page-fault exceptions**: `ud2` (trap 6), which Linux turns
   into `SIGILL` and the resume hook into a `CpuException::InvalidOpcode`;
   `int3` (trap 3), which Linux turns into `SIGTRAP` with `SI_KERNEL` and the
   resume hook into a `CpuException::BreakPoint`; and `hlt` (trap 13),
   privileged, which Linux turns into `SIGSEGV` with `SI_KERNEL` and the resume
   hook into a `CpuException::GeneralProtectionFault`;
3. **eviction**: a system call whose handler spins in kernel mode for ever,
   so that the only way the host gets that processor back is to evict the
   kernelet when the runtime kills the sandbox.

The book uses it in chapter 7 (exceptions), chapter 11 (stopping a kernelet:
kill and eviction) and chapter 12 (faults on tenant memory).

## How it is built and run

`make probe`: `KLET_KERNEL=probe`, the image, the module, `runtime/run-probe.c`
as the test, one boot, and the checks in `check-probe-log`.

## Files

| file | what it is |
|---|---|
| `src/lib.rs` | the kernel proper |
| `probe.S` | the tenant program: a store to an unmapped page, `ud2`, `int3`, `hlt`, and the endless system call |
| `Cargo.toml` | the crate |
