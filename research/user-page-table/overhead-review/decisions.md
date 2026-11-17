# Kernelet overhead decisions

These are the user-confirmed requirements for the Asterinas-based implementation. Implementation and validation are distinct from a measured performance benefit; neither changes a book proposal's Draft status.

The syscall design source is [PR #3](https://github.com/tatetian/kernelet/pull/3), pinned to [the proposal at `ee1b2267e6178c6afaf22d73ad961f0c227ec8db`](https://github.com/Plucky923/kernelet/blob/ee1b2267e6178c6afaf22d73ad961f0c227ec8db/book/src/design-proposals/2026-10-31-reduce-syscall-overhead.md), blob `7f97e2765ef3f3ae6d242bca0cd66b95da940e91`.

## D1: Attribute work to the correct layer

Compare the work already completed by Linux before its hook with the work performed by Endovisor and the image. Separate adaptation costs from ordinary Asterinas algorithms and POSIX semantics. Linux has saved syscall registers before the hook; it has not decoded arguments for the intercepted call. Reading only the selected syscall's arity is therefore a general dispatch improvement, not evidence of duplicate Linux argument decoding.

## D2: Establish fixed carrier addresses once

Implemented in `poc/linux/endovisor/carrier.c`. The NEW branch of `on_resume` records `user_regs`, `linux_sp`, and the published `pt_regs` address. Ordinary `on_syscall` reuses them; DEBUG checks frame identity. An exception with a temporary frame copies its register contents into the fixed frame without changing that frame's address. The invariant comes from the carrier's fixed Linux task stack and `task_pt_regs`, not from the tenant's user SP.

## D3: Notify for every virtual-event publication

Implemented as a complete producer/consumer protocol. Tick, remote kick, self kick, coalesced kick, and idle paths arrange Linux resume notification regardless of the carrier's current USER/KERNEL state. Producers retain the ordering needed to publish event contents. The ordinary `user_run` path has no pending recheck or full memory barrier.

Linux clears the notification before invoking the hook, so a notification set during the callback survives for the next exit-loop iteration. Blocking carriers still require an explicit wakeup. Exceptions record their information and notify; `on_resume` delivers the event after Linux exception entry completes. Invalid-return handling also notifies explicitly.

## D4: Borrow the persistent Process reference

The confirmed scope retains `as_posix_thread` and `as_thread_local` queries. `ThreadLocal::process` holds a persistent strong reference in `RefCell<Option<Arc<Process>>>`; ordinary callbacks borrow it, and exit/oops takes it to break ownership cycles. There is no per-event Process Arc clone/drop to remove. The RefCell and Option checks are separate remaining work; the proposal does not require a new typed task hierarchy here.

## D5: Link fixed user-event handlers

Implemented by `#[ostd::user_event_handler]`: five fixed Rust callback symbols and type-ID functions. Construction validates both task data and local data, returning `Error::InvalidArgs` for a mismatch before allocating task resources. Event dispatch uses direct callbacks. The Kernelet configuration exposes its event-driven interface; native OSTD retains `UserMode::execute`.

Earlier source, image audit, and runtime evidence: [fixed-handler validation](direct-handler-validation/README.md).

## D6: Reuse CPU-local addresses inside the protected interval

Implemented by `CpuLocalAccess<'irq>`, which borrows the real virtual-IRQ guard. One protected lookup supplies the shared vCPU record and private CPU-local base. Address reuse lasts only as long as the guard; mutable fields are read at their required points. The guard and single-instruction access constraints preserve the interrupt/preemption contract.

Earlier source, machine-code, and runtime evidence: [CPU-local validation](cpu-local-validation/README.md).

## D7: Keep panic reporting on cold paths

Implemented with inlined generic catch wrappers and separate cold functions for message formatting, Host reporting, oops accounting, and exceptional exit. Each event retains a valid unwind boundary and POSIX cleanup. No persistent catch frame is carried across the nonreturning user handoff.

Earlier machine-code and actual-panic evidence: [cold-panic validation](panic-cold-validation/README.md). The reported removal of three wrapper calls and 3096 bytes of ordinary-path report space applies to those recorded artifacts; it is not an independent latency measurement.

## Validation

[Current validation](syscall-path-validation/README.md) records the latest builds, release/debug QEMU checks, and unresolved measurement limits. Correctness coverage does not prove every possible event interleaving or quantify an isolated speedup.
