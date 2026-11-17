# Accepted Design review: host boundary and fault isolation

Date: 2026-11-16. Parent repository baseline: `a5ec4b875d0a17890321a362fbc3fd16859b7eb4`.

This review examines the design arguments in five book chapters. Source code and local proposals are supporting evidence. A source-level bug, a missing test, or a disclosed feature omission is not by itself a book design defect. Existing source/book modifications were preserved. No tests or VM boots were run.

## Chapter coverage

| Chapter | Design mechanisms examined | Result |
|---|---|---|
| [Why a kernel of your own](../../book/src/accepted-design/why-a-kernel-of-your-own.md) | Hostile tenant, faulty safe kernel proper, trusted framework/compiler/host; memory soundness; availability; scope of teaching prototype | H1 identifies an unfilled containment guarantee. The trusted build/dependency boundary is explicitly qualified at lines 51–78, so lack of a formal proof is not counted as a new design defect. The root review separately examines scheduler invariants placed on safe code. |
| [The endovisor UAPI](../../book/src/accepted-design/the-endovisor-uapi.md) | FD authority, holder lifetime, registration privilege, PIE/relocation sharing, exec transition, fixed cgroup, kill/read semantics | H2 is an unresolved cgroup reassignment policy. FD copies are explicitly specified and do not constitute an undisclosed lifetime flaw. No independent image-sharing design defect established. |
| [Carriers](../../book/src/accepted-design/carriers.md) | User task requirement, fork/exec inheritance, empty address space, cgroup accounting, lifeline death notice | H2 concerns the lifetime of the accounting assumption. No separate finding for privileged lifeline copies: the book explicitly describes their effect. |
| [Two stacks](../../book/src/accepted-design/two-stacks.md) | Persistent kernelet stacks, service stack switch, guard pages, pooled stacks, stack bounds | H1: guard pages plus timer eviction do not contain exhaustion of the active stack. Pooling and fixed stack size do not supply that missing mechanism. |
| [Stopping a kernelet](../../book/src/accepted-design/stopping-a-kernelet.md) | Whole-instance stop, deferred service completion, depth-zero eviction, destructor abandonment, final resource release | H1 invalidates the unrestricted opening guarantee. The depth-zero/no-Linux-lock argument is otherwise coherent for the stated synchronous resources. Future asynchronous retention is already addressed by TypedIO. |

## H1. Stack exhaustion is outside the available containment mechanism

**Status:** confirmed design defect in the completeness of Accepted Design's fault-isolation guarantee; explicitly disclosed prototype limitation, rather than a hidden implementation bug.

**Original claim.** [Why, line 53](../../book/src/accepted-design/why-a-kernel-of-your-own.md#L53) requires a bug in kernel proper to affect only its tenant. [Lines 59–70](../../book/src/accepted-design/why-a-kernel-of-your-own.md#L59-L70) use the safe-Rust/OSTD boundary to confine faulty kernel proper. [Stopping, lines 3–11](../../book/src/accepted-design/stopping-a-kernelet.md#L3-L11) says every carrier can be stopped and host state/resources recovered.

**Mechanism offered.** [Two stacks, lines 123–135](../../book/src/accepted-design/two-stacks.md#L123-L135) allocates 256 KiB stacks with guard pages. [Stopping, lines 125–169](../../book/src/accepted-design/stopping-a-kernelet.md#L125-L169) redirects an interrupt return to an exit stub, which calls the normal leave path using the interrupted stack before switching to the Linux stack.

**Failure scenario.** A safe kernel proper enters a recursive path whose depth depends on tenant input, or uses sufficiently deep valid call chains. It exhausts its kernelet stack. [Two stacks, line 133](../../book/src/accepted-design/two-stacks.md#L133) explicitly states that delivering the guard-page fault can itself fail because the current stack is exhausted, ending in a host double fault. A timer cannot guarantee eviction before an instruction exhausts the stack. The exit stub itself still requires usable stack space.

**Consequence.** The ordinary memory-safety argument does not establish host survival for this allowed faulty-safe-code execution. This is not established by the absence of a recursion test: the book itself identifies a missing protective mechanism.

**Counterargument and boundary.** The book states that the prototype is small and not a universal isolation proof ([Why, lines 90–94](../../book/src/accepted-design/why-a-kernel-of-your-own.md#L90-L94)); the teaching kernels deliberately avoid recursion. That appropriately discloses prototype scope. However, the stated design guarantee still needs a stack-failure protocol. Choosing teaching workloads that avoid the condition does not derive one. Likewise, assuming vOSTD is correct does not exclude unbounded recursion in the faulty safe kernel proper.

**Necessary design change.** Specify either preventive stack bounds checked before space needed for host interruption/recovery is consumed, or a separately justified emergency-stack/fault-entry protocol that remains executable after exhaustion. The contract must cover task and bootstrap stacks, compiler-created large frames/probing, synchronous exceptions, interrupts, and the termination path's own headroom. The argument must explain which component enforces the bound against faulty safe code. Merely naming a stack-related kill reason is insufficient.

**Existing-proposal coverage.** PR #3 (`ee1b226`) changes handoff and stack ownership but does not supply the bound. PR #7 (`cbe7bf3`, [fault-policy section](https://github.com/tatetian/kernelet/blob/cbe7bf32681a4777f983e3b7ad15a23b58b0a34a/book/src/design-proposals/2026-11-09-fpu-state-management.md#an-exception-occurs-in-kernelet-kernel-code)) requires instance termination on kernel exceptions, but this policy alone does not make exception entry work on an exhausted stack. The local direct-page-table proposal concerns user-trap forwarding; the heap proposal concerns grant allocation/reclamation. Neither closes H1.

The local Linux PoC has guarded-stack and kernel-`#PF`/`#GP` hooks, which are relevant implementation progress. A kernel-fault callback reached only after ordinary fault entry is not, by itself, an argument for surviving the double-fault case. No implementation result is used here to claim that the book already specifies that protocol.

## H2. Fixed sandbox cgroup identity and later task reassignment lack a shared policy

**Status:** unresolved design risk; policy ambiguity, not a demonstrated tenant escape or a claim that ordinary cgroup delegation is unsafe.

**Original claims.** [UAPI, line 149](../../book/src/accepted-design/the-endovisor-uapi.md#L149) requires ordinary Linux task controls, including control groups, to apply to carriers. [KLET_CREATE, lines 418–424](../../book/src/accepted-design/the-endovisor-uapi.md#L418-L424) fixes the creator's cgroup as the sandbox's and holds its group leader as mm owner. [Carriers, line 23](../../book/src/accepted-design/carriers.md#L23) derives CPU and memory attribution from every carrier being in that group.

**Mechanism offered.** Creation records a group, and exec checks that each arriving carrier is in that group. Fork inheritance and exec preservation establish the initial condition. Those are not lifetime invariants of ordinary Linux tasks. Linux documents post-creation migration via `cgroup.procs` and permits it inside a delegated subtree with the required permissions. Existing memory charges do not follow such migration. Supporting primary reference: [Linux 6.12 cgroup documentation, lines 268–276](../../reference/linux-6.12/Documentation/admin-guide/cgroup-v2.rst#L268-L276), [delegation, lines 562–574](../../reference/linux-6.12/Documentation/admin-guide/cgroup-v2.rst#L562-L574), [memory ownership, lines 1815–1818](../../reference/linux-6.12/Documentation/admin-guide/cgroup-v2.rst#L1815-L1818).

**Failure scenario.** After sandbox start, an authorized runtime moves a carrier, or the recorded owner task, from group A to group B. Ordinary Linux CPU attribution and later carrier allocations follow the current task's membership, while the sandbox record and previously allocated backing still refer to the original accounting arrangement. Moving only some carriers produces one instance spread across groups.

**Consequence.** The book's single-sandbox-group attribution argument no longer follows from the creation/exec checks alone. Whether this is forbidden, supported reconfiguration, or an intentionally accepted accounting split is unspecified. It affects interpretation of per-sandbox resource ceilings and reports.

**Counterargument and boundary.** The example runtime creates one cgroup per sandbox and does not migrate carriers; trusted operator configuration can make the current arrangement sufficient. Cgroup permissions also prevent a delegatee from moving tasks outside its authorized subtree. These facts block an automatic cross-tenant escape claim. They do not decide the advertised post-start control semantics.

**Necessary design decision.** State whether a live sandbox's cgroup identity is immutable. If so, define the runtime/operator invariant and any needed enforcement at a delegated boundary. If migration is supported, define whole-instance versus per-carrier reassignment, mm-owner semantics, existing charges, and admission/device-attachment checks. Creation-time equality alone cannot implement both models.

**Existing-proposal coverage.** The local heap draft explicitly separates grant capacity from other Linux-accounted allocations, but does not define live cgroup reassignment. PR #3, PR #7, and direct page-table management do not select this policy. TypedIO explicitly treats attribution on asynchronous host workers as separate integration work; that does not decide carrier reassignment.

## Considered and not promoted to design findings

- **Copied sandbox FDs delay destruction.** [UAPI, lines 581–592](../../book/src/accepted-design/the-endovisor-uapi.md#L581-L592) explicitly makes last-copy closure authoritative. This qualifies the earlier shorthand “dies with its runtime” at line 151. Process-death ownership would require a different policy, but the existing capability-lifetime policy is coherent. An ordinary `dup` is not an undisclosed design hole.
- **Copied lifelines delay death notice.** [Carriers, line 162](../../book/src/accepted-design/carriers.md#L162) explicitly identifies the privileged `pidfd_getfd` case. An actor with host `CAP_SYS_PTRACE` is outside the hostile safe kernel proper boundary. Keeping a still-referenced record is not a new faulty-safe-code escape.
- **Whole-sandbox death after one lost carrier.** [Stopping, lines 105–115](../../book/src/accepted-design/stopping-a-kernelet.md#L105-L115) explains why remaining vCPUs may otherwise depend on locks abandoned by the lost one. No general hot-unplug/recovery protocol is promised. Whole-instance fail-stop is a justified policy here.
- **No Rust destructors during forced teardown.** [Stopping, lines 8–11](../../book/src/accepted-design/stopping-a-kernelet.md#L8-L11) stops all carriers before reclaiming host-owned backing. The synchronous, device-free baseline has a coherent abandonment argument. Safe Rust permitting object leaks is not by itself a host leak when backing is independently recorded.
- **Future DMA/host references survive carrier death.** The accepted prototype explicitly omits devices ([UAPI, line 723](../../book/src/accepted-design/the-endovisor-uapi.md#L723)). [TypedIO, lines 819–861](../../book/src/design-proposals/2026-11-08-typed-io.md#L819-L861) already specifies independent host leases, detachment, full-backing accounting, and quarantine. This is an existing proposal's integration obligation, not a newly uncovered design direction.
- **No unconditional wall-clock cleanup bound.** [Stopping, lines 49–50](../../book/src/accepted-design/stopping-a-kernelet.md#L49-L50) explicitly waits for host services to finish. The service and output-worker implementation deserves separate liveness review, but lack of a test does not establish a new book design defect. The fault model must continue to state its host-progress assumptions.
- **Trusted image build versus ELF validation.** [UAPI, lines 173 and 202](../../book/src/accepted-design/the-endovisor-uapi.md#L173) explicitly distinguishes code trust from format checks. [Lines 234–238](../../book/src/accepted-design/the-endovisor-uapi.md#L234-L238) give the shared-page relocation condition and private-data layout. No additional contradiction was established in those arguments.
- **Exec-based carrier creation.** The book uses exec as the Linux lifecycle boundary that resets the previous program and user-memory registrations while retaining chosen task controls. Merely constructing an empty mm would not reproduce all of that behavior. No supported counterexample here establishes that the chosen exec protocol is unjustified.
- **Implementation teardown-work ownership.** The local PoC's work-item scheduling concern from the earlier reclamation audit is excluded: it is not a flaw in the book's abstract stop/exit/release state machine.

## Priority and coverage boundary

H1 is the substantive isolation mechanism gap in these five chapters. H2 is a lower-priority policy decision whose importance depends on supported runtime delegation/reconfiguration. The root review's separate scheduler-affinity finding is another possible mismatch between the arbitrary-faulty-safe-code claim and an invariant assigned to that same layer; it should be assessed under the execution chapters rather than duplicated here.

No claim is made that the remaining Accepted Design chapters are free of design flaws. This note covers the five named chapter mechanisms, considers surrounding limitations and existing proposals, and does not substitute implementation errors or missing tests for design findings.
