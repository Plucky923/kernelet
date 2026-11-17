# CPU-time accounting across the two schedulers

Date: 2026-11-16. Parent baseline: `a5ec4b875d0a17890321a362fbc3fd16859b7eb4`. The local `poc/` sources contain additional, uncommitted integration work. Existing changes were preserved. This pass read source and proposal text; it ran no VM or timing experiment.

## Conclusion

**No new major architectural flaw is established.** The design needs a clear distinction between elapsed time and execution time, and consistent host publication of the selected execution clock. Those responsibilities fit the existing host/vOSTD/kernel-proper split.

The local PoC already introduces `runtime_ticks()` for the inner scheduler and separately attributes sampled CPU ticks to explicit guest Task owners. It would be incorrect to describe every guest CPU clock as using uncorrected TSC time or to infer that one coalesced virtual interrupt loses all CPU-time accounting.

A concrete Linux-adapter integration gap remains: `nonrunning_tsc` is declared in the shared ABI and read by `runtime_ticks()`, but no publisher was found in the inspected `poc/linux/` sources or the host patch. Thus the guest interface is existing progress, while complete Linux off-CPU exclusion is not established by this source state. This is an engineering publication/semantic contract, not evidence that a different scheduling architecture is necessary.

## The counters have different meanings

| Counter or interface | Actual coverage in the inspected sources |
|---|---|
| Shared prototype `VcpuRec.stolen_ns` | Completed off-CPU intervals that began while `klet_in_kernelet(c)` held. The outgoing notifier sets `off_cpu_ns` only then; the incoming notifier adds the elapsed interval. This excludes user-mode and host-service/idle departures. Sources: [`sched.c:70`](../../prototype/linux/endovisor/sched.c#L70-L89), [`sched.c:119`](../../prototype/linux/endovisor/sched.c#L119-L135), [`kernelet.h:202`](../../prototype/linux/endovisor/kernelet.h#L202-L204). |
| Shared Linux PoC `stolen_ns` | Also narrow: the outgoing state must be `POC_STATE_KERNEL`, `depth == 0`, not idle, and not evicted. User execution and blocked services do not set its timestamp. Source: [`poc_carrier.c:307`](../../poc/linux/endovisor/poc_carrier.c#L307-L343). |
| Tracked host UAPI `klet_vcpu_stat.stolen_ns` | A different source despite the same name: Linux `task->sched_info.run_delay`, conditional on `CONFIG_SCHED_INFO`. It measures accumulated runnable wait, rather than all elapsed off-CPU time. Sources: [`sandbox.c:713`](../../prototype/linux/endovisor/sandbox.c#L713-L724), [Linux scheduler stats](../../reference/linux-6.12/kernel/sched/stats.h#L247-L290). |
| Tracked host UAPI `run_ns` | Raw `se.sum_exec_runtime` for the carrier. This is a host task total, not a guest-thread split; the read does not explicitly update the currently running interval. Source: [`sandbox.c:713`](../../prototype/linux/endovisor/sandbox.c#L713-L724). |
| PoC `nonrunning_tsc` | Intended host-published offset excluded from the inner scheduler's execution clock. It has TSC units, unlike `stolen_ns`. Declared in [the C record](../../poc/linux/endovisor/poc_endovisor.h#L104-L120) and [the Rust record](../../poc/ostd/src/kernelet/abi.rs#L314-L317); no Linux-side writer was found in this pass. |
| PoC `task_ticks` | One packed atomic word containing pending user/kernel samples; its atomic take defines the old/new guest Task ownership boundary. It is distinct from pending virtual IRQ summary bits and from the TSC execution clock. Sources: [`abi.rs:223`](../../poc/ostd/src/kernelet/abi.rs#L223-L232), [`processor.rs:113`](../../poc/ostd/src/task/processor.rs#L113-L122). |

The book's shared-record wording is broad at [Tasks and virtual CPUs, line 80](../../book/src/accepted-design/tasks-and-virtual-cpus.md#L80). The prototype's source comment supplies its narrower measurement scope. [What it costs, line 54](../../book/src/accepted-design/what-it-costs.md#L54) already states that its `stolen` measurement covers descheduling while running kernelet code and does not measure outer-hypervisor descheduling of the entire test VM.

Subtracting the shared diagnostic `stolen_ns` from elapsed TSC is therefore not automatically a correct all-state CPU clock. It has different units, excludes some relevant departures, and records only completed intervals.

## Existing host interfaces and snapshot semantics

Linux 6.12's [`task_sched_runtime`](../../reference/linux-6.12/kernel/sched/core.c#L5487-L5528) explicitly includes pending current-task runtime. It takes the task runqueue lock when necessary and updates the runqueue/current task before reading the total. The inspected function is not exported to modules; using it from an endovisor would need an appropriate supported integration seam.

[`task_cputime_adjusted`](../../reference/linux-6.12/kernel/sched/cputime.c#L623-L633) is GPL-exported and provides Linux's adjusted user/system totals, with implementation details depending on CPU-accounting configuration. Neither interface automatically divides one carrier's total among the guest tasks that ran on it, and neither is currently exposed as a guest execution-time service in the inspected Linux PoC service list ([`poc_carrier.c:757`](../../poc/linux/endovisor/poc_carrier.c#L757-L773)).

The tracked `KLET_GET_STATS` implementation protects the carrier lookup with the instance lock and reads runtime/delay fields individually. It does not take Linux's runqueue lock or provide a common timestamp/sequence for all rows. These reads are useful diagnostics; they should not be silently promoted into an exact simultaneous runtime/delay snapshot or a precise current CPU clock. Source: [`sandbox.c:699`](../../prototype/linux/endovisor/sandbox.c#L699-L739).

The PoC guest accessor already performs the appropriate kind of consistency check for an offset clock: read the offset, read ordered TSC, reread the offset, and retry if it changed. Source: [`accounting.rs:8`](../../poc/ostd/src/task/accounting.rs#L8-L17). Completing that contract requires the host to publish the offset before guest execution resumes, in matching units, under the current vCPU identity. The double read alone cannot compensate for an absent publisher.

## Services, idle, switches, and guest Task attribution

- **Host service execution:** it executes as the same carrier and is included in the carrier's Linux runtime. A sleep inside that service consumes elapsed time but not continuous CPU execution. The shared diagnostic `stolen_ns` excludes departures at nonzero service depth. The inner execution clock needs its own explicit choice about these intervals; it cannot reuse that diagnostic's eligibility rule without checking the intended semantics. Sources: [`carrier.c:1841`](../../prototype/linux/endovisor/carrier.c#L1841-L1867), [`poc_carrier.c:1005`](../../poc/linux/endovisor/poc_carrier.c#L1005-L1075).
- **Idle:** `vcpu_idle` marks the carrier idle and sleeps in Linux. Waiting is wall time, while the code before/after sleeping consumes CPU time. The current narrow stolen counter intentionally omits this departure. Source: [`prototype idle`](../../prototype/linux/endovisor/carrier.c#L1596-L1634), [`PoC idle`](../../poc/linux/endovisor/poc_carrier.c#L846).
- **Host sampling:** the Linux PoC timer samples a carrier only while it is current. It records user/kernel classification from the interrupted registers, skips some inner interrupt-level kernel samples, and keeps the two Task sample counts in one atomic word. Host-service execution may be sampled as kernel execution of the current guest Task. These are sampled accounting semantics, not a claim of exact nanosecond attribution. Source: [`poc_watch.c:31`](../../poc/linux/endovisor/poc_watch.c#L31-L58).
- **Guest Task switch:** an atomic take captures the outgoing Task's pending samples before changing `CURRENT_TASK_PTR`; later samples belong to the incoming Task. After the switch, the captured batch is charged using the previous Task object before its execution ownership is released. Sources: [`processor.rs:113`](../../poc/ostd/src/task/processor.rs#L113-L125), [`processor.rs:275`](../../poc/ostd/src/task/processor.rs#L275-L293).
- **CPU clocks versus scheduler time:** `Task::account_sampled_ticks` calls explicit-owner callbacks with user/kernel counts; `CurrentTask::flush_sampled_ticks` settles samples before exit. The process timer manager uses the identified Task's thread/process clocks. Sources: [`task/mod.rs:193`](../../poc/ostd/src/task/mod.rs#L193-L210), [`task/mod.rs:641`](../../poc/ostd/src/task/mod.rs#L641-L652), [`timer_manager.rs`](../../poc/kernel/core/src/process/process/timer_manager.rs). This path must be assessed separately from the scheduler's `runtime_ticks()` delta.

No inference is made here that all forms of tick coalescing corrupt all user-visible CPU clocks. The local code already separates pending summary bits, sampled ownership batches, and scheduler execution time.

## A verifiable engineering counterexample

Assume guest Task A remains the inner current Task while Linux deschedules its carrier. It resumes later, without an intervening guest Task switch. In the present Linux adapter, no `nonrunning_tsc` update was found. The next `runtime_ticks()` call therefore subtracts the same offset as before; its delta includes that elapsed off-CPU interval. If the intended clock is execution time, the delta does not meet that contract. This follows from the accessor and missing publication path; no numerical effect or runtime failure was measured.

This counterexample concerns the scheduler clock, not automatically the separate user/kernel sample-based CPU clocks. It can be addressed at the existing host publication/vOSTD clock seam. It does not establish a need to replace the two-level scheduler arrangement.

## Existing proposal coverage and remaining contracts

The retained `origin/preview/scheduler-and-fpu` proposal, [Coordinate the two schedulers](https://github.com/Plucky923/kernelet/blob/005710cc617ac0c639d6ea1ab119e61e44d0fb57/book/src/design-proposals/2026-11-04-coordinate-the-two-schedulers.md), proposes host load/topology observations and mirror coordination; it leaves sleeping/waking coordination deferred. It does not define a complete execution-clock publication ABI. PR #3 changes event/task handoff, and PR #7 coordinates FPU state around carrier scheduling; neither substitutes for a CPU-time definition. The local `runtime_ticks()` interface is a concrete additional engineering step already present in the PoC.

The contract must state which clock measures elapsed time, which measures carrier execution, what host-service/idle/interrupt time belongs to a guest Task, when host offsets become visible, how units/monotonicity and snapshots are maintained, and which user-facing counters remain sampled estimates. Existing ownership boundaries can support those choices.

Linux should continue to account and limit carrier CPU time at the outer level; kernel proper should account its Tasks using the selected inner execution clock and explicit sample owners. Asynchronous host workers are a separate attribution issue already disclosed by [TypedIO, line 859](../../book/src/design-proposals/2026-11-08-typed-io.md#L859); this review does not reopen that architecture discussion.

