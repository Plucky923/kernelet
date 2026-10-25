# probe: the three mechanisms the 100-line kernel never reaches

A second kernel proper in the style of the 100-line kernel, written for this
prototype against the same API, that drives:

1. **demand paging**: only the program's text is mapped; the program stores
   to an unmapped page, the area's fault handler reports the fault to the
   kernelet as a page-fault exception, the kernel maps a fresh frame there,
   and the store is retried. Then a `write` of 4 MiB, whose buffer is more
   than the kernelet's heap gives (`kmalloc`'s limit, less the few bytes the
   endovisor puts in front of every block): the endovisor refuses the
   allocation without asking `kmalloc`, and the kernel proper answers the call
   with `-ENOMEM` and goes on;
2. **three exceptions other than page faults**: `ud2` (trap 6), twice in a
   row, which Linux turns into `SIGILL` and the resume hook into a
   `CpuException::InvalidOpcode` (the second shows that a fault signal the
   drain has ignored again is still forced through);
   `int3` (trap 3), which Linux turns into `SIGTRAP` with `SI_KERNEL` and the
   resume hook into a `CpuException::BreakPoint`; and `hlt` (trap 13),
   privileged, which Linux turns into `SIGSEGV` with `SI_KERNEL` and the resume
   hook into a `CpuException::GeneralProtectionFault`. After them the runtime
   reads the vCPU carrier's `SigIgn` from `/proc`: every signal but `SIGKILL`
   and `SIGSTOP` must be ignored again;
3. **eviction**: a system call whose handler spins in kernel mode for ever,
   so that the only way the host gets that processor back is to evict the
   kernelet when the runtime kills the sandbox.

The book uses it in chapter 5 (seccomp before the syscall hook), chapter 8
(exceptions), chapter 12 (stopping a kernelet: kill and eviction) and chapter
13 (faults on tenant memory).

## How it is built and run

`make probe`: `KLET_KERNEL=probe`, the image, the module, the holder run by
`run-test` as the test, and three boots. The first is the probe, which the
holder ends a second after the start with a SIGKILL to the carrier
(`--kill-after 1000`); the carrier is spinning in kernelet code, so the watch
timer finds the signal and evicts it; checked by `check-probe-log`. The second
runs the same image and tenant with a seccomp filter, installed by the holder
between the fork and the exec (`--seccomp-kill 1000`), that kills the process
on system call 1000, the endless one: seccomp runs before the syscall hook, so
the kernelet never sees the call, and Linux forces `SIGSYS` on the carrier as
a fatal signal. `check-probe-seccomp` checks that the resume hook left it for
Linux to deliver, that the carrier died by it, that its death ended the
sandbox with nobody killing anything, and that Linux printed no warning (a
carrier that lived on would hit one in seccomp at its next system call). The
third ends the probe with `KLET_KILL` (`--klet-kill-after 1000`): the sandbox
is marked dying first, the watch timer stops, and the eviction sweep the kill
arms takes the processor back; `check-probe-klet-kill`.

## Files

| file | what it is |
|---|---|
| `src/lib.rs` | the kernel proper |
| `probe.S` | the tenant program: a store to an unmapped page, a 4 MiB `write`, `ud2` twice, `int3`, `hlt`, and the endless system call |
| `Cargo.toml` | the crate |
