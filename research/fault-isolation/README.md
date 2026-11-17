# Fault isolation in Kernelet

Date: 2026-11-16. This is a source-based design inventory for the Linux-hosted Kernelet. It records the fault model, existing mechanisms, remaining obligations, and evidence limits. It does not change Accepted Design or implement a repair.

## Scope and source state

The reviewed repository HEAD is `a5ec4b875d0a17890321a362fbc3fd16859b7eb4`. The working tree also contains a modified Linux carrier-hook patch and local direct-page-table and grant-heap proposals. The nested `poc/` checkout is at `7f8476ab463f1dcdf901fd650ee4f127298d28ef` with substantial local changes. These represent different implementation states:

| State | What it establishes |
|---|---|
| Accepted Design and tracked `prototype/` | The original language boundary, stack model, stop/kill protocol, host heap, and existing test assertions. |
| Local Linux adapter in `poc/linux/` | Integration of the event-handler model, direct page-table updates, and additional kernel-fault handling. This is local PoC code, not an update to Accepted Design. |
| Upstream FPU proposal, PR #7 | A proposed checked-import and fatal-fault policy. GitHub reports it open at `cbe7bf32681a4777f983e3b7ad15a23b58b0a34a`; the proposal itself says complete validation and main-prototype integration remain pending. |
| Retained local PoC logs | Earlier observations for specific workloads and configurations. They were read in this review, not rerun, and their exact correspondence to every current dirty source file was not reconstructed. |

The separate Asterinas-host implementation selected by `kernelet-host` in [poc/ostd/src/kernelet/mod.rs](../../poc/ostd/src/kernelet/mod.rs) is outside this Linux-host audit. Its double-fault and stack tests cannot establish Linux-host recovery.

## The fault model

The book's requirement is that bugs triggered by hostile tenant programs remain confined to their own tenant. The operator controls compilation and image registration; the kernel proper uses safe Rust and the permitted framework interfaces. Trusted components include vOSTD, endovisor, the host kernel, permitted unsafe dependencies, and the compiler. The dependency graph must preserve that boundary, as well as the kernel proper's own source. See [Why a kernel of your own](../../book/src/accepted-design/why-a-kernel-of-your-own.md), especially “A kernel inside the kernel,” “A kernel in two layers,” and “The same kernel, a different framework.”

For this analysis, allow the kernel proper to make arbitrary safe calls permitted by those interfaces, choose hostile data, panic, fail to make progress, exhaust its admitted resources, leak objects, and forget guards. This is the adversarial interpretation to test the interface against; it is not a claim that the prototype implements a proof for every such execution.

A raw CPU exception can still be in scope when safe caller-controlled input reaches a trusted hardware operation. For example, the tracked `FpuContext` exposes safe byte mutation and loading, so the implementation must handle invalid state supplied through that interface. Merely placing the restore instruction inside trusted code does not discharge this obligation. See [FpuContext](../../prototype/vostd/src/arch/cpu/context.rs), `as_bytes_mut` and `load`, and [the FPU service](../../prototype/linux/endovisor/carrier.c), `klet_fpu_validate` and `klet_do_fpu_load`.

Compiler bugs, arbitrary unsafe execution in the trusted implementation, physical machine failures, and unrelated host-kernel faults are outside this model. The book explicitly excludes timing and speculative side channels. Preserving isolation also does not undo authorized file writes or other external effects completed before a failure.

## What must remain true

Four properties need separate arguments:

1. **Access confinement.** Safe kernel-proper code cannot read, modify, map, or retain resources beyond its authority. Trusted safe interfaces must enforce this even for hostile arguments and call sequences.
2. **Execution revocation.** After a fatal fault or a host kill decision, the host can stop every carrier without requiring progress by kernel-proper tasks or release of their locks. Ordinary fairness while a sandbox is alive is a separate property.
3. **Host-state restoration.** Leaving the sandbox restores or retires borrowed host state through trusted code: the Linux stack and address-space association, mirrored preemption state, carrier hooks, notifier and identity records, FPU state when relevant, and outstanding timer/interrupt references.
4. **Safe and accounted reclamation.** Reuse starts only after carriers, mappings, software readers, and accepted external accesses can no longer reach the allocation. Any retained backing remains charged and subject to admission limits.

These are design obligations inferred from the book's isolation requirement and its existing stop protocol, rather than four independently proved properties. The restoration and reclamation mechanisms are traced in [the companion audit](reclamation-audit.md).

Safe Rust does not guarantee that destructors run: the official [`mem::forget` contract](https://doc.rust-lang.org/core/mem/fn.forget.html#safety) permits forgetting values and requires unsafe implementations to tolerate it. Consequently, host cleanup cannot depend on kernel-proper `Drop` implementations. The book already abandons kernelet state without unwinding; see [Stopping a kernelet](../../book/src/accepted-design/stopping-a-kernelet.md), “The shape of a death.”

## Failure inventory

| Fault or behavior | Required response | Existing mechanism and evidence | Remaining boundary |
|---|---|---|---|
| A tenant user program takes a page fault, illegal-instruction fault, breakpoint, or other supported trap | Deliver the event to its kernel proper, which may resolve it or signal/terminate that process. This need not end the sandbox. | The book describes VMA/signal forwarding. The local PoC adds `on_exception`; retained logs cover 11 user exceptions and register preservation. | User-trap delivery is evidence about the tenant/kernel interface. It does not establish recovery from faults in kernelet kernel execution. |
| Kernel proper panics through the normal handler, including a checked assertion failure | End the entire sandbox; do not resume its partly failed state. | Tracked `panic_handler -> abort -> poweroff -> stop` enters `klet_end`; existing `mem-r2` assertions check an intentional panic, a nonzero stop, no host warning, and clean unload. | This path requires sufficient stack and a usable handler/service path. It is not an exception handler for arbitrary CPU traps or exhausted stacks. |
| Kernel proper loops, deadlocks on its own locks, or forgets a virtual interrupt/preemption guard | Preserve host scheduling authority and allow a host-requested whole-sandbox kill. | Watch/mirror and eviction already implement this division. `probe` and `mem-kill` contain assertions for kills during kernelet code and idle/service execution. Local PoC kill logs show termination during syscall and MM workloads. | The timers do not diagnose every logical deadlock automatically. Service execution is not abandoned while it might hold Linux state; a blocked trusted service needs its own completion/cancellation contract. |
| Kernel proper consumes the available stack, or an interrupt/exception arrives with insufficient remaining stack | Reach trusted termination without corrupting host memory or taking Linux's fatal double-fault path. | The book explicitly identifies stack exhaustion as a host-fatal limitation. The local PoC recognizes guard-address `#PF` and redirects to its Linux-stack exit path. | Guard-fault recognition is useful only after exception entry succeeds. The current Linux patch does not hook `#DF`; stack-exhaustion containment is not closed. |
| Caller-controlled state causes a kernel-mode CPU exception, such as a restore fault | Use a narrowly defined recoverable operation or terminate the sandbox after repairing affected host state. | The tracked FPU service stages/validates state and has restore exception-table fixups. The local PoC adds fatal image `#PF/#GP` handling and resets carrier FPU state on `#GP`; PR #7 specifies checked import and fatal cleanup. | The baseline fixup skips a failed restore and continues; it does not reset/report/terminate in that path. The PoC callback only receives the traps routed by the Linux patch. No retained test inspected here forces a fatal image restore fault and validates subsequent host FPU state. |
| Safe code allocates indefinitely, leaks frames/objects, or exhausts task/space slots | Fail admission within the sandbox's configured resource policy; avoid unbounded host retention; keep termination possible. | Fixed grant ownership, task/space limits, host heap records, and cgroup accounting provide pieces. The local heap and returnable-grant proposals address different allocation policies. | Accounting is not itself an enforced quota. Grant limits, host allocations, metadata, stacks, roots, and externally retained backing must be considered together. A local heap changes accounting and reclamation granularity; it does not alone establish fault isolation. |
| Kernel proper stops servicing completions or dies with outstanding external work | Stop new acceptance, detach notifications, and retain backing until access has ended. Do not invoke dead-instance destructors or callbacks. | TypedIO specifies trusted pending records, host leases, generations, admission credits, and quarantine. These are proposal obligations; the tracked prototype has no implemented TypedIO devices. | A kill or cancellation request does not prove quiescence. Arbitrary Linux I/O has no unconditional reclamation deadline; retained allocations need bounds and continued accounting. |

Sources for the rows: [user-mode round trip](../../book/src/accepted-design/into-user-mode-and-back.md); [panic handler](../../prototype/vostd/src/panic.rs); [poweroff](../../prototype/vostd/src/power.rs); [carrier stop, service, FPU and mirror code](../../prototype/linux/endovisor/carrier.c); [watch](../../prototype/linux/endovisor/watch.c); [eviction](../../prototype/linux/endovisor/evict.c); [stack limitation](../../book/src/accepted-design/two-stacks.md); [test assertions](../../prototype/Makefile); [PoC kernel-fault callback](../../poc/linux/endovisor/poc_carrier.c); [TypedIO retention and bounds](../../book/src/design-proposals/2026-11-08-typed-io.md), “Lifetime and resource bounds.”

## Three points that need particular care

### Exception entry precedes fault policy

The Linux PoC's `poc_on_kernel_fault` checks carrier identity, kernel mode, zero host-service depth, and image instruction address or a stack guard address. For a handled fault it marks the instance dying, sets `doomed/evicted`, and rewrites the saved instruction and stack pointers to a Linux-stack exit path. On `#GP` it calls `kernelet_fpu_reset_carrier`. This is real implementation progress, visible in [poc_carrier.c](../../poc/linux/endovisor/poc_carrier.c), lines 702–743.

However, the [current Linux patch](../../prototype/linux/patches/0001-carrier-hooks.patch) invokes that callback for unrecovered kernel `#PF` and `#GP`, after Linux fixups. It adds no double-fault callback or general switch to an emergency stack before those entries. Linux 6.12's [`exc_double_fault`](../../reference/linux-6.12/arch/x86/kernel/traps.c) describes the failed exception-delivery case and ends in `panic("Machine halted.")` when it cannot recover.

Therefore, catching a guard-page `#PF` does not establish that recursive stack exhaustion or a low-stack interrupt can always reach this callback. This is a source-grounded remaining obligation, not a newly reproduced host crash. A repair needs an argument for entry itself, as well as the subsequent stop operation; increasing stack size alone supplies no bound on recursion.

### Recoverable access faults differ from fatal execution faults

The policy should preserve three distinct routes: a user-mode tenant trap to the kernel proper; an authenticated fallible-access fault to its specified error/retry path; and an unexpected image-execution fault to trusted whole-sandbox termination. Host-kernel faults also retain Linux's own handling.

The [fallible memory interface](../../poc/ostd/src/mm/fault/mod.rs) and [user-copy test](../../poc/linux/bench/test_mm_safety.c), `run_kernel_efault_test`, show why `#PF` cannot be classified by privilege level alone. A result of `EFAULT` verifies the fallible interface, not the fatal-fault path. The handler must identify the operation, executing address, service depth, and allowed recovery target before resuming or abandoning anything.

### Stopped, exited, and reclaimed are different events

The original protocol marks the sandbox dying, stops all carriers, and observes the last lifeline before releasing execution resources. Some backing remains until the sandbox descriptor is released. The Linux PoC likewise defers destruction until its lifecycle and descriptor conditions hold. With asynchronous devices, accepted host work can retain backing beyond execution termination. See [Stopping a kernelet](../../book/src/accepted-design/stopping-a-kernelet.md), [poc_main.c](../../poc/linux/endovisor/poc_main.c), and [the companion audit](reclamation-audit.md).

The companion audit also identifies a concrete static implementation defect in the PoC's last-close path: `released` is set before `poc_end`, so an instance with no carriers can initialize and queue the same `destroy_work` from both `poc_sandbox_exited` and `poc_sandbox_release`. The tracked prototype deliberately orders these operations differently. Runtime consequences have not been reproduced; this needs a separate implementation repair and targeted validation. It does not change the fault model.

## Evidence checked and work still needed

This review read source, proposal text, test assertions, and selected retained logs. It ran no VM or fault-injection experiment.

| Evidence read | What it supports |
|---|---|
| [`stage4_baseline_restored_safety.log`](../../poc/target/tmp/stage4_baseline_restored_safety.log), lines 299–364 | Earlier successful user-exception, register, protection, page-table race, and fallible-copy cases; normal exit and module unload. |
| [`stage3_v3_poc_b1.log`](../../poc/target/tmp/stage3_v3_poc_b1.log), lines 322–332 | Earlier rejection/handling of invalid signal-return FPU input, successful completion, and unload. This does not force the restore instruction's fault fallback. |
| [`stage4_chk3a_kill_syscall.log`](../../poc/target/tmp/stage4_chk3a_kill_syscall.log) and [`stage4_chk3b_kill_mm.log`](../../poc/target/tmp/stage4_chk3b_kill_mm.log), lines 259–265 | Earlier holder-requested whole-instance kills during the selected workloads, followed by unload. |
| `check-mem-r2`, `check-mem-kill-quiet`, and `check-probe-klet-kill` in [the Makefile](../../prototype/Makefile) | Assertions exist for intentional panic and multiple kill contexts, including host-warning and unload checks. These assertions were inspected, not rerun. |

The next design discussion should settle three points in order:

1. Define the fatal fault set and its entry guarantees, starting with recursive stack exhaustion and low-stack interrupt/exception entry. Preserve authenticated fallible accesses and keep host faults distinct.
2. Specify one trusted termination sequence and a restoration ledger shared by panic, CPU-fault, and external-kill paths. Check it when a sibling still executes, a guard is forgotten, a service is blocked, or descriptors close concurrently.
3. Define which resource classes must be immediately reusable and which may remain quarantined and charged. Then require an independent host/sibling witness to continue after each injected sandbox fault; check restoration and retained resources, rather than only the victim's exit message.

Useful experiments after that decision are real compiler-generated recursive/large-frame exhaustion, fatal image `#PF/#GP`, failed FPU restore with a subsequent host FPU witness, panic while a sibling holds or waits for kernelet locks, and repeated create/kill/close with exhausted resources and outstanding work. Each must identify the exact source tree, build configuration, fault trigger, and observed host behavior. Existing user-mode trap results do not cover these cases.

For reproducibility, the three most relevant dirty-source SHA-256 values at inspection were:

| Source | SHA-256 |
|---|---|
| `prototype/linux/patches/0001-carrier-hooks.patch` | `4b96ab2964ea8ce6f30d8dfff9db5b8597f309fd74835ea0c0ce86139fb2bce5` |
| `poc/linux/endovisor/poc_carrier.c` | `2a6b0d90093f45c32314e7878ef955bd4216d01c7da9a80401b60146524cddaa` |
| `poc/linux/endovisor/poc_main.c` | `082aa65776a53098c1f897866879f05420a157ca535cc478109fbeac1a804c78` |

Additional primary references: [Rust panic handlers](https://doc.rust-lang.org/reference/panic.html#the-panic_handler-attribute); [PR #7](https://github.com/tatetian/kernelet/pull/7) and its [pinned proposal](https://github.com/tatetian/kernelet/blob/cbe7bf32681a4777f983e3b7ad15a23b58b0a34a/book/src/design-proposals/2026-11-09-fpu-state-management.md); [local PoC result summary](../user-page-table/results.md), used to locate retained evidence rather than as a substitute for it.
