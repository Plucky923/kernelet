# Accepted Design: design problems found in a first pass

Date: 2026-11-16. Reviewed parent revision: `a5ec4b875d0a17890321a362fbc3fd16859b7eb4`.

This review asks whether the book's design choices and arguments hold under their stated conditions. The primary objects are the 15 Accepted Design chapters. Source code, Linux/OSTD references, and existing proposals are supporting evidence. The result is a technical design review, not a full sentence-level prose audit, a soundness proof, an implementation bug list, or a new experiment report. Existing book and source modifications are preserved.

Four findings are worth retaining: two fault-isolation mechanism gaps, a retirement-progress contradiction, and an overstatement in the fork cost rationale. The first two need priority because they affect the book's central boundary between faulty safe kernel proper and trusted implementation. Stable finding IDs below belong to this review; the two supporting notes retain their local IDs.

## BDR-01. An unenforced scheduler convention carries a safety invariant

**Status:** confirmed design-contract defect. **Priority:** high. **Evidence:** explicit book statements plus a source-level interleaving; no dynamic escape or host corruption has been reproduced. **Next action:** direct repair of the design contract and its enforcement mechanism.

**Book choice and promise.** [Tasks and virtual CPUs, line 59](../../book/src/accepted-design/tasks-and-virtual-cpus.md#L59) delegates scheduling to the kernel proper through the OSTD scheduler interface. [Why a kernel of your own, lines 53 and 70](../../book/src/accepted-design/why-a-kernel-of-your-own.md#L53-L70) requires containment even when safe kernel proper is faulty. Yet [Virtual interrupts, line 185](../../book/src/accepted-design/virtual-interrupts.md#L185) requires a preempted task to resume on its original vCPU, explains the wrong-slot consequence of migration, and explicitly says vOSTD does not enforce this assumption.

**Why the argument fails.** This is not simply a restriction against a useful load-balancing feature. Correctness of trusted vCPU-local operations depends on a convention assigned to the same faulty safe layer the framework promises to contain. The [safe `Scheduler` trait](../../prototype/vostd/src/task/scheduler/mod.rs#L95-L109) and its injection API do not establish that convention. The trusted switch path [checks only that a task is not executing concurrently](../../prototype/vostd/src/task/processor.rs#L93-L110); sequential execution on a different vCPU is not rejected.

**Concrete interleaving.**

1. Task A on vCPU 0 calculates the address of a vCPU-local slot.
2. A virtual interrupt preempts A before the subsequent slot read or write. No pinning guard was taken for this operation.
3. A safe injected scheduler resumes the now-stopped task on vCPU 1, without ever running it concurrently on both vCPUs.
4. A continues using the saved vCPU-0 address, while vCPU 0 can independently access its slot.

[`CpuLocalCell::slot/load/store`](../../prototype/vostd/src/cpu/local.rs#L67-L85) makes this an inspectable example: it selects a current-vCPU slot, then uses a non-atomic volatile read/write. Its safe public methods take no guard. Masking interrupts during the context switch does not pin the continuation after the switch completes. The separately guarded `CpuLocal::get_with` interface does not fix these unguarded operations.

The consequence is a broken vCPU-local ownership/soundness premise and a possible cross-slot race. This review does not claim a measured path from that race to arbitrary host-memory corruption. Rust's own [safe/unsafe contract](https://doc.rust-lang.org/nomicon/safe-unsafe-meaning.html) explains why trusted unsafe code must defend against incorrect safe implementations supplied by its clients; documenting the expectation alone does not supply that defense.

**Required design change.** Either have trusted vOSTD assign and enforce immutable task-to-vCPU binding before context reuse, or make all relevant local-state and continuation operations migration-safe. Any binding record used for enforcement must not be mutable solely through scheduler-owned hints. Treating the scheduler as trusted would change the isolation model and must be an explicit alternative, not an implicit dependency.

**Existing proposal coverage.** PR #3's [pinned task-switch design](https://github.com/tatetian/kernelet/blob/ee1b2267e6178c6afaf22d73ad961f0c227ec8db/book/src/design-proposals/2026-10-31-reduce-syscall-overhead.md#task-switch) repeats the same-vCPU requirement and adds further dependence on it through lazy `pt_regs` ownership and sleeping callbacks. A default scheduler choosing to respect affinity is not enforcement against an injected faulty scheduler. The requirement is therefore still a design obligation; the handoff proposal does not by itself close it.

**Important distinction.** This concerns moving a kernelet Task between vCPUs. Linux moving one carrier between physical CPUs preserves its vCPU identity and is a different event.

## BDR-02. Stack exhaustion can defeat the promised fault boundary

**Status:** confirmed incomplete isolation design, already disclosed as a prototype limitation. **Priority:** high. **Evidence:** the book's own failure scenario. **Next action:** direct repair of the containment mechanism.

**Original endpoints.** [Why, line 53](../../book/src/accepted-design/why-a-kernel-of-your-own.md#L53) requires a bug in kernel proper to affect only its tenant. [Two stacks, line 133](../../book/src/accepted-design/two-stacks.md#L133) states that unbounded recursion can exhaust a kernelet stack and halt the host through double fault. [Sharing a processor politely, line 21](../../book/src/accepted-design/sharing-a-processor-politely.md#L21) also acknowledges that the short-stack yield stub requires unchecked remaining space.

**Mechanism and counterexample.** Fixed-size stacks with guard pages prevent an ordinary linear overflow from silently entering a neighboring mapped area, but they do not establish that exception entry can execute on an exhausted stack. The timer and [eviction stub](../../book/src/accepted-design/stopping-a-kernelet.md#L125-L169) also do not establish a preventive stack bound before the next instruction or a separately safe exit stack. A tenant-triggered deep recursive path in safe kernel proper can therefore reach a condition outside the available termination mechanism.

**Required design change.** Specify an enforceable preventive bound or an emergency-entry/termination protocol. The argument must include bootstrap and task stacks, large compiler-generated frames, the host interruption reserve, and the termination path itself. Increasing stack size or adding a stack-overflow exit code does not establish this property. Restricting the teaching kernels to non-recursive paths discloses scope but does not complete the general mechanism.

**Existing proposal coverage.** PR #7's [fatal kernel-exception policy](https://github.com/tatetian/kernelet/blob/cbe7bf32681a4777f983e3b7ad15a23b58b0a34a/book/src/design-proposals/2026-11-09-fpu-state-management.md#an-exception-occurs-in-kernelet-kernel-code) does not itself make fault entry possible after exhaustion. The Linux PoC's `#PF/#GP` callback is implementation progress after entry succeeds; it is not a proof of double-fault-safe entry. The detailed book argument and counterarguments are in [H1 of the supporting note](host-and-isolation.md#h1-stack-exhaustion-is-outside-the-available-containment-mechanism).

## BDR-03. Retirement cannot guarantee creation progress in every permitted creation context

**Status:** confirmed contradiction in the design's progress argument. **Priority:** medium. **Evidence:** book context rules and a statically checked allowed sequence. **Next action:** direct repair of the collection/admission contract.

**Original endpoints.** [What vOSTD adds, line 250](../../book/src/accepted-design/what-vostd-adds-on-top.md#L250) forbids retire-list draining whenever any preemption guard is held, although sleeping memory services are permitted under a plain guard. [Line 252](../../book/src/accepted-design/what-vostd-adds-on-top.md#L252) then claims creation cannot be held up by retired spaces because `vm_create` drains them. [Rule 2, line 289](../../book/src/accepted-design/what-vostd-adds-on-top.md#L289) permits creation under a plain preemption guard with virtual IRQs enabled and no spin lock held.

**Counterexample.** In a one-vCPU sandbox, hold a plain `disable_preempt()` guard and repeatedly create and immediately drop an empty `VmSpace`. Every call satisfies Rule 2. Each drop retires its backend; every subsequent creation skips draining because the guard is still held. With no other vCPU to collect, retired spaces occupy all 64 slots, and the next creation fails even though the caller retains none of them.

This is not the general fact that finite quotas can run out. It specifically defeats the promised collector progress at the operation that is supposed to make capacity available. The book excludes the collector from a context in which it permits the consumer.

**Source confirmation.** [`Backend::new`](../../prototype/vostd/src/mm/backend.rs#L55-L65) calls the drain and then asserts success; [`retire::safe`](../../prototype/vostd/src/mm/vm_space.rs#L780-L795) excludes all guards; [`VmSpace::drop`](../../prototype/vostd/src/mm/vm_space.rs#L354-L363) queues without destroying; [`klet_do_vm_create`](../../prototype/linux/endovisor/space.c#L364-L374) rejects a full slot table; [`KLET_MAX_SPACES`](../../prototype/linux/endovisor/kernelet.h#L66) is 64. These sources corroborate the design contradiction; this sequence was not run.

**Required design change.** Make collection eligible and sufficiently progressive where creation requires it, give retirement an independent progress mechanism, or explicitly tighten the creation context contract. The chosen repair must explain compatibility and latency rather than relying on an eventual safe point that need not occur before capacity is needed.

**Existing proposal coverage.** The [direct-PTE proposal](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L287) recognizes extra drain points as an open question and retains retirement. Direct PTE writes alone do not decide this collection/admission policy. See [MEM-03](memory-and-costs.md#mem-03--retirements-claimed-creation-progress-excludes-a-context-creation-permits) for the full trace.

## BDR-04. The fork tradeoff argument omits the touched-page fraction

**Status:** confirmed design-rationale overclaim, not proof that eager population is inherently wrong. **Priority:** medium/secondary to the mechanism gaps. **Next action:** author evidence for a bounded cost model and design choice.

**Book argument.** [What it costs, line 84](../../book/src/accepted-design/what-it-costs.md#L84) treats the prototype's eager per-page fork work as a cost repaid by avoided first-touch faults. It excludes no-touch fork/exec and concludes that every other workload gains.

**Countercase and failed inference.** A process can fork a large address space and touch only one or a few pages before exit or exec. This is outside the excluded no-touch case, yet eager work covers every mapping while the avoided first-touch work covers only the small used subset. The universal benefit does not follow from the full-read workload. A valid break-even argument needs the number of mapped pages, pages actually touched, update cost, deferred/fault cost, and common costs.

Eager PTE presence and one host service per PTE are also independent choices. Batched mediation or trusted direct updates can preserve eager presence without this crossing count. The book's current cost is therefore not established as an unavoidable price of the first-touch property.

**Required design change.** Separate population policy from update-mediation policy and justify each over a stated workload range. This need not become another proposal: the existing direct-PTE work already revisits mediation. Correcting the tradeoff's decision criteria is still necessary when integrating that design. See [MEM-04](memory-and-costs.md#mem-04--the-fork-rationale-lacks-a-touched-page-break-even-condition).

## Existing work and lower-priority open questions

The following are genuine design topics but are already substantially covered by existing proposals:

| Original choice or restriction | Existing work | Review conclusion |
|---|---|---|
| Linux mm integration is used to justify Linux writing every user PTE | Local direct-PTE draft, with batching as an alternative | The necessity argument is too strong; responsibilities can be split. Continue the existing proposal rather than count this as a newly uncovered direction. |
| Per-object host heap and sleeping PTE services change valid OSTD call contexts | Local grant-heap and direct-PTE drafts | Same signatures do not preserve the full behavior contract. These drafts address much of the restriction; creation/destruction and collection remain separate obligations. |
| Return-based syscall handoff copies user registers and resumes a suspended chain | PR #3 | An existing execution-model redesign addresses the cost. It does not automatically discharge BDR-01. |
| FPU state ownership and return-from-user-mode preemption windows | PR #7 and PR #3 | The book itself identifies the behavioral gaps; keep their handling in the existing work. Do not generalize this into a claim that pending/idle/wake ordering is fundamentally broken. |
| Host/device accesses can outlive kernel-proper handles | TypedIO | Its independent leases, admission bounds, detachment, and quarantine are the relevant design. Lack of general devices in the teaching prototype is not a newly discovered design flaw. |

Two lower-priority questions remain. The book says all tenant threads on a carrier share its thread-pointer base and sketches per-thread support for a full vOSTD ([Into user mode and back, line 152](../../book/src/accepted-design/into-user-mode-and-back.md#L152)); this is explicit unfinished functionality, not an established flaw in the proposed per-thread ownership direction. The book also leaves the policy for authorized post-start cgroup reassignment unclear; [H2](host-and-isolation.md#h2-fixed-sandbox-cgroup-identity-and-later-task-reassignment-lack-a-shared-policy) records the ambiguity without alleging a tenant escape. Neither is promoted to a confirmed design defect in this pass.

## Coverage of the 15 Accepted Design chapters

This table records which design arguments were examined and whether they yielded a new finding. “No independent finding” means none established by this pass, not a proof of correctness. Lexical/style checks, new runtime validation, and a full trusted-code soundness audit are outside this pass.

| Chapter | Design argument examined | Result |
|---|---|---|
| [Why a kernel of your own](../../book/src/accepted-design/why-a-kernel-of-your-own.md) | Faulty-safe-code confinement and trusted boundary | BDR-01 and BDR-02. |
| [The endovisor UAPI](../../book/src/accepted-design/the-endovisor-uapi.md) | FD authority, exec/creation, image sharing, resource policy | No additional confirmed defect; cgroup policy question H2. |
| [The first kernel we will run](../../book/src/accepted-design/the-first-kernel-we-will-run.md) | Machine-service obligations and preserved OSTD behavior | No independent finding in the narrow hello example; general compatibility qualifications are tracked separately. |
| [The kernelet ABI](../../book/src/accepted-design/the-kernelet-abi.md) | Grants, heap, entry/service ownership | Existing heap/PTE proposals address non-necessary delegation choices. |
| [Carrier hooks and patch overview](../../book/src/accepted-design/carrier-hooks.md) | Syscall authority, resume ordering, Linux interception | Existing PR #3 and direct-trap work; no additional core hook-order defect established. |
| [Carriers](../../book/src/accepted-design/carriers.md) | Exec inheritance, accounting and lifeline ownership | No additional confirmed defect; explicit descriptor/privileged-observer boundaries retained. |
| [Two stacks](../../book/src/accepted-design/two-stacks.md) | Persistent execution state, service stack and overflow containment | BDR-02; handoff redesign already in PR #3. |
| [Into user mode and back](../../book/src/accepted-design/into-user-mode-and-back.md) | Register authority, signal/exception delivery, thread state | Existing execution and user-exception proposals; thread-pointer omission explicitly disclosed. |
| [Tasks and virtual CPUs](../../book/src/accepted-design/tasks-and-virtual-cpus.md) | Safe scheduler delegation, vCPU identity and task state | BDR-01; FPU ownership has existing work. |
| [Virtual interrupts](../../book/src/accepted-design/virtual-interrupts.md) | Upcalls, migration, pending delivery and user-mode scheduling | BDR-01; explicit FPU/user-preemption gaps already have proposals. |
| [Sharing a processor politely](../../book/src/accepted-design/sharing-a-processor-politely.md) | Mirror, forced yield, host scheduling and lock-holder delays | BDR-02 applies to short-stack fallback; no independent pending/idle/wake counterexample established. |
| [Stopping a kernelet](../../book/src/accepted-design/stopping-a-kernelet.md) | Fail-stop, trusted-state cleanup and whole-instance abandonment | BDR-02 affects entry to the stop path; no additional abstract-state-machine defect established. |
| [Tenant memory on Linux's page tables](../../book/src/accepted-design/tenant-memory-on-linux-page-tables.md) | mm/root versus user-PTE ownership and VMA adaptation | Overstated necessity already addressed by direct-PTE proposal. |
| [What vOSTD adds on top](../../book/src/accepted-design/what-vostd-adds-on-top.md) | Frame/readers, cursor contexts and retirement | BDR-03; remaining R2 restrictions are tracked with existing proposals. |
| [What it costs](../../book/src/accepted-design/what-it-costs.md) | Cost attribution and design tradeoff justification | BDR-04. |

Supporting notes: [host boundary and isolation](host-and-isolation.md), [memory and cost rationale](memory-and-costs.md). They include rejected candidate findings and counterarguments. The earlier [fault inventory](../fault-isolation/README.md) remains an engineering inventory; its implementation concerns and unrun tests are not automatically book design findings.

No book/source edit or new VM experiment was performed. Existing PR heads were checked through GitHub during this review; the local draft status remains distinct from adoption into Accepted Design. Review findings above are supported design/argument defects, not a claim that arbitrary host corruption or every predicted failure has been dynamically reproduced.
