# Kernelet implementation and validation

This record covers the current Asterinas-based Kernelet source, its Linux patch, OSDK, and experiment tooling. The source snapshot contains existing user work as well as these changes; it is not a patch that attributes all local modifications to this review. The book's separate teaching implementation and Draft proposals retain their own scope and status.

The design reference is the pinned [syscall proposal](https://github.com/Plucky923/kernelet/blob/ee1b2267e6178c6afaf22d73ad961f0c227ec8db/book/src/design-proposals/2026-10-31-reduce-syscall-overhead.md) and the [confirmed D1–D7 requirements](../decisions.md).

## Final design

| Responsibility | Implementation |
| --- | --- |
| Carrier register storage | Linux owns the fixed `pt_regs` and task stack. NEW initializes their addresses once. Ordinary syscall entry only updates the syscall register convention and event state. DEBUG checks frame identity. |
| Event delivery | All virtual-event producers notify Linux regardless of USER/KERNEL state. Exceptions record data and notify; `on_resume` enters the image. The return path has no pending recheck or full memory barrier. Producer ordering, wakeups, and Linux notification clearing remain explicit. |
| User-register ownership | The active user task owns the carrier frame. Switching through a kernel task preserves that owner. A stopped task's `OwnedUserContext` exposes register operations, without a mutable escape that could replace its representation with a borrowed frame. |
| Task construction | `TaskEntry` expresses the two valid entry forms. User task data and local-data types are checked before resource allocation; invalid inputs return `Error::InvalidArgs`. Shared construction initializes the task once. |
| POSIX dispatch | The selected syscall reads only its declared argument count. Threads borrow their persistent Process reference. `CpuSync` returns immediately when state is already `OnCpu`; stopping-thread checks read process state before thread state. |
| Event callbacks and panic handling | Fixed handler symbols, IRQ-bound CPU-local address reuse, inlined catch wrappers, and cold panic/oops reporting retain D5–D7. Kernelet exposes its event-driven execution API; native OSTD retains its execution loop. |
| Address-space retirement | `VmResources` owns the page table, I/O mappings, and Host root together. Kernelet RCU defers its Drop to sleepable context; synchronous Host unregister completes Host TLB/RCU retirement before Rust releases the lower tables. |
| Grant publication | Published run descriptors are immutable. Physical pages are individually releasable, successful allocations have a single owner, and an unpublished suffix is released once. Partial virtual mappings are removed and invalidated before their pages are freed. Capacity arithmetic is checked before allocation. |
| Sandbox completion | One locked condition claims one cleanup work reference. The last carrier permits resource reclamation; only completed cleanup publishes `exited`. Result descriptors retain the result object. Live `SANDBOX_STATS` and completed `read`/`poll` have distinct meanings. |
| Carrier exit | Linux invokes `on_exit` after `exit_mm` and before `exit_files`. Hooks, preempt notifier, and CPU slot are detached on the original task before a copied lifeline can receive its final `fput` remotely. |
| Direct attach | A cold `kernelet_attach_mm` helper releases Linux userspace registrations using native exec-related routines before replacing the old `mm`. Allocation failures before this commit point preserve the original context. Later failures terminate the carrier. |
| Host fault signals | Hardware exceptions use the exception hook. An unclassified `SI_KERNEL` fault stops the sandbox with the original signal/code; it cannot be translated using an old `thread.trap_nr`. Standard non-`SI_KERNEL` fault information remains available to the VMA path. |
| Image registration | Registration/unregistration require `CAP_SYS_MODULE` and enabled module loading. Registration uses Linux load-data hooks and refuses enforced signatures or lockdown when the raw-image interface cannot satisfy them. |
| Names and tools | C implementation symbols, headers, module, runner, device, command-line keys, and result markers use Endovisor/Kernelet names. Historical repository paths and explicit checks rejecting obsolete artifact names retain their literal identities. |

The lifecycle reasoning and cold attach boundary are detailed in [lifecycle-review.md](lifecycle-review.md) and [attach-registration-review.md](attach-registration-review.md). The runner propagates failed result reads/output, closes pidfds on startup failures, and terminates the instance after an unrecoverable poll error. Init reports the actual command result; guest wait status is decoded before exporting the exit code.

## Actual validation

The x86-64 release image and release image with Rust debug assertions both passed the OSDK build, unsafe-source audit, floating-point instruction audit, and image ABI checks. The Endovisor debug module uses `KCFLAGS=-DDEBUG`. The actual patched Linux 6.12 kernel was rebuilt, and its patch passed application with `--whitespace=error` and an 18-file reverse/forward byte comparison.

Native and Kernelet `aster-core` target checks passed. Kernelet Clippy completed with warnings, so this is not a warning-free lint claim. The OSDK Kernelet-filtered tests passed 71 cases, with 2 ignored and 23 filtered out; the separate integration binary had 22 filtered tests. Rust formatting and the `poc` diff whitespace check passed. The outer root diff treats patch context prefixes as whitespace; the meaningful kernel-patch check is its application to the baseline.

The final runtime matrix used real QEMU/KVM, `-cpu host`, two virtual CPUs, 1024 MiB, Linux 6.12, and a 256 MiB grant. These are functional regressions, with concurrent host activity, not controlled latency measurements.

| Image/module configuration | Cases | Result |
| --- | --- | --- |
| Release, Direct PT, exec | syscall/SMP/GPR/SSE/AVX/rt_sigreturn; event/ptrace/fork/exec; exit 42; kill | 4 boots passed |
| Debug assertions, Direct PT, attach ioctl | syscall/SMP/GPR/SSE/AVX/rt_sigreturn | 1 boot passed |
| Debug assertions, Direct PT, exec | event/ptrace/fork/exec; actual panic recovery; memory safety; kill | 4 boots passed |
| Release, VMA, exec | memory safety; event/ptrace/fork/exec | 2 boots passed |
| Native Linux | syscall/SMP/FPU suite; event suite; Endovisor lifecycle ioctls | 3 boots passed |

All 14 boots completed with the expected init result and module unload. No matching Host BUG, WARNING, panic, or Oops was observed. Each completed Kernelet instance reported equal VM creation/destruction counts. This is an accounting and completion check, not proof of the absence of every possible leak.

The persistent C regressions exercise actual six-argument file mapping, ptrace GETREGS/SETREGS/POKEUSER/single-step/continue, UD2, int3, noncanonical access, blocking fork/exit rounds, and exec status. The Host lifecycle test covers read-only registration output, full kind registry, unregister privilege, task-count overflow, shared files/sighand rejection, descriptor exhaustion, and repeated cleanup. The panic input triggers the implemented kernel's real unsupported timer path and checks sibling progress and released file/memory resources.

Runtime files are `qemu-*.json`, `.log`, and `.stderr`. Each JSON contains the exact command, artifact hashes, actual boolean results, final statistics where applicable, and individual pass/fail checks. `attach-rseq-diagnostic.*` contains a separate diagnostic run and is not a passing final-matrix result.

The container workflow could not run because the current account could not access the Docker socket. Validation used the repository-pinned local nightly, actual Linux builds, and real QEMU. QEMU's process soft memlock limit was explicitly set to zero to avoid the local io_uring initialization failure; manifests record it. No Host kernel module was loaded on the workstation.

## Experiment tooling

[eval-review.md](eval-review.md) records 26 passing existing checks, strict static C compilation, genuine hwloc/libtirpc builds, input identity checks, and actual L/K protocol execution. The runner requires exactly one result per selected case and a matching K/K_vma statistics record. The host overlay carries the selected payload, and GNU gzip/cpio inspects the real archive inputs.

That protocol run used a separately identified existing image. Its formal selfcheck gate failed on vDSO fallback and CPU placement. Its explicitly diagnostic run also rejected K's CPU placement and instance-wide FPU count limit. Those failures remain failures; they are not evidence of a final-image speedup or of an unnecessary save on every syscall. Nix was unavailable, so the Nix derivation was not built.

## Machine-code evidence and remaining costs

[on_syscall.asm](on_syscall.asm) contains no repeated stores of the fixed frame/stack addresses. [do_user_run_on_linux.asm](do_user_run_on_linux.asm) contains no return-side pending handshake or full memory barrier. Its exceptional notification and diagnostic `non_sysret` counter still contain their own locked operations; this is not a claim that the function contains no atomic instructions.

[user_event_entry.asm](user_event_entry.asm) and [handle_syscall.asm](handle_syscall.asm) preserve the final release machine code. Fixed handler dispatch is distinct from the retained dynamic type query on the kernel-event branch and the Host service-table call. The syscall wrapper obtains the number before dispatch rather than unconditionally reading six arguments.

Owned/Frame branches, POSIX type queries, RefCell/Option checks, required IRQ/preemption guards, real task/FPU transitions, Linux exit work, Host services, TLB invalidation, and RCU retirement remain where their contracts require them. Native Asterinas logging/error handling and memory-policy choices are not all Kernelet adaptation costs. The fixed-grant allocator, alternate page-table ownership, batching, and cache-policy candidates in the historical audit are separate design work; this review does not claim those proposals are implemented.

No isolated latency benefit is reported. The correctness matrix does not exhaust notification races, remote final-fput interleavings, allocation-failure injection, every architecture, PTI/security configurations, or physical hardware. `CONFIG_MODULE_SIG` and `CONFIG_SECURITY` are disabled in this tested kernel; their enabled-policy branches require corresponding configurations.

## Artifacts and reproduction

[final-inputs.json](final-inputs.json) records 2579 source files, toolchain versions, repository heads, and complete artifact hashes. [verification.json](verification.json) confirms that all 14 final runs match the retained artifacts, both modules match the current C sources, and the reviewed Rust files match both immutable OSDK build snapshots. [final-source.tar.gz](final-source.tar.gz) preserves the source snapshot; initial/final Git status and diff files preserve its relationship to existing work. No commit or external publication was performed.

| Final artifact | SHA-256 |
| --- | --- |
| `bzImage` | `114963b3e3bda3901938272763ec9ec8e8640ad7143865350b5fd310d8fa93df` |
| `image-release.elf` | `d2567c78f6eda9b20c03b72e5e047cfaba2929034af9ee4edcae071c8bf25c5f` |
| `image-debug.elf` | `8b1d30bea6e16fe95c3a1375d11bf57006ac135f65035e2d66620511ed3c8c7a` |
| `endovisor-release.ko` | `ff2b256c6c7702b35f675f449da8f20550d235c436d7802875024eee9fed1040` |
| `endovisor-debug.ko` | `f3cd632a681124257bf32a61fd29c0a0b38d6869db207c6c82e22682359a1252` |

`host-release.cpio.gz` and `host-debug.cpio.gz` retain the exact tested image, module, runner, and payload bytes. To replay a recorded QEMU command, replace its temporary kernel/initrd paths with the saved files here and retain its CPU, memory, command-line, and memlock settings. `kernelet_attach=ioctl` selects the direct attach path; the default is exec. The retained artifacts are evidence for this review and later regression comparison, while build caches retain their normal software-defined locations.
