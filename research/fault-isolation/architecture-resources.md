# Fault isolation: resource authority and independent revocation

Date: 2026-11-16. Scope: the Linux-hosted Kernelet's resource/failure-domain architecture, as described in Accepted Design and the existing relevant proposals. This pass asks whether faulty safe kernel-proper code can prevent the host from ending its fault domain by leaking, forgetting, sharing, or retaining resource objects.

## Result

**No additional major architectural defect was established in this resource/ownership pass after accounting for the existing proposals.** Memory soundness alone is insufficient to establish fault isolation, but the book already assigns scheduling authority, instance identity, backing ownership, and forced destruction to the host. The strongest resource counterexamples either have an explicit mechanism already, concern a trusted implementation's correctness, or demand a stronger availability guarantee that the current design does not claim.

This does not certify every implementation or close the separate CPU-exception/stack review. It means that a new resource-isolation proposal needs a concrete missing responsibility or a deliberately stronger contract; a general statement that safe Rust permits leaks is not enough.

## Model and protected objects

The operator builds each image, the kernel proper is safe Rust against a restricted framework/dependency graph, and vOSTD, endovisor, Linux, the allowed unsafe dependencies, and the compiler remain trusted. These are explicit premises in [Why a kernel of your own, lines 51–78](../../book/src/accepted-design/why-a-kernel-of-your-own.md#L51-L78). Faulty caller-controlled data and API sequences remain in scope even when the eventual hardware operation is implemented by trusted code; putting an operation in vOSTD is not permission to ignore the safe interface's contract.

The immediate fault domain is one sandbox, including its kernel proper and tenant processes. The host retains authority over its carriers and backing resources. The runtime supplies external resources as descriptors, and the sandbox can use only that granted authority ([UAPI, lines 147–151](../../book/src/accepted-design/the-endovisor-uapi.md#L147-L151), [418–429](../../book/src/accepted-design/the-endovisor-uapi.md#L418-L429)). A faulty kernel may misuse a writable resource already granted to it. The language boundary does not roll back legitimate external effects, supply application-level correctness, or make an explicitly shared file private. Stronger separation of such resources is a runtime/attachment policy requirement.

The safe-code adversary considered here may leak its own objects, forget guards or handles, fail to consume completions, submit permitted operations concurrently, or stop making progress. A hypothetical arbitrary memory write by buggy unsafe vOSTD is not an additional fault this architecture promises to contain. Soundness must instead show that no permitted safe client behavior causes trusted code to violate its own contract.

## Existing responsibility chain

| Responsibility | Existing owner and mechanism | Original evidence |
|---|---|---|
| Identify the origin of host operations | The calling carrier identifies its instance; the image cannot name an arbitrary other instance through the private service table | [ABI, lines 76–78](../../book/src/accepted-design/the-kernelet-abi.md#L76-L78); [Two stacks, service identity](../../book/src/accepted-design/two-stacks.md#L221-L225) |
| Define external authority and host resource policy | Runtime-selected descriptors and cgroup; create records the group, grant ceiling and task/stack bound | [UAPI, lines 149–151](../../book/src/accepted-design/the-endovisor-uapi.md#L149-L151), [395–429](../../book/src/accepted-design/the-endovisor-uapi.md#L395-L429) |
| Bound/interrupt execution independently of the kernel proper | Host scheduling, watch/forced yield, and whole-instance eviction; virtual masking does not mask hardware interrupts | [Why, line 84](../../book/src/accepted-design/why-a-kernel-of-your-own.md#L84); [Stopping, lines 125–183](../../book/src/accepted-design/stopping-a-kernelet.md#L125-L183) |
| Recover abandoned private objects | Host-owned lists/records identify heap blocks, spaces and stacks; backing is reclaimed after carriers stop without invoking kernel-proper destructors | [Stopping, lines 7–15](../../book/src/accepted-design/stopping-a-kernelet.md#L7-L15); [`klet_sandbox_gone`](../../prototype/linux/endovisor/carrier.c#L292-L312); [`klet_heap_destroy`](../../prototype/linux/endovisor/carrier.c#L1496-L1529) |
| Retain memory used by accepted external work | Independent trusted pending references and host-owned leases; detachment prevents callbacks into a dead instance | [TypedIO, lines 821–853](../../book/src/design-proposals/2026-11-08-typed-io.md#L821-L853) |
| Keep post-death retention bounded and attributable | Reserve admission credits and full retained backing; use per-instance plus host-wide limits; quarantine when quiescence cannot yet be proved | [TypedIO, lines 845–861](../../book/src/design-proposals/2026-11-08-typed-io.md#L845-L861) |

This is a composition of language/API confinement, host control, and resource-specific lifetime protocols. It is not an inference from Rust memory safety alone. Most responsibilities are already assigned even though they are described in different chapters/proposals.

## Strong counterexamples examined

### 1. Forget every allocation and never run a destructor

**Attack.** The kernel proper leaks `Box`, `Arc`, frames, or task objects, so safe Rust's object ownership no longer releases them normally.

**Existing answer.** The book deliberately abandons all Rust objects on termination. The host's allocation records are independent of those objects, and final reclamation follows carrier death. In the tracked prototype, `klet_heap_destroy` walks the host's block table rather than Rust objects. The local-heap proposal instead reclaims whole grant backing after execution and external accesses stop ([heap proposal, lines 70–80](../../book/src/design-proposals/2026-11-16-allocate-the-kernelet-heap-from-the-grant.md#L70-L80)).

**Assessment.** A live instance can waste its admitted capacity. That is not a demonstrated escape from the host's reclamation authority. Neither the old block ledger nor the proposed whole-grant policy requires leaked objects to cooperate. Changing heap placement is already covered and does not create a new architectural requirement here.

### 2. Forget a lock or virtual interrupt guard and deadlock every vCPU

**Attack.** No kernelet task can finish cleanup or release a lock, so a cooperative shutdown routine could never complete.

**Existing answer.** The host kills the whole instance and evicts image execution rather than acquiring those locks. The key book invariant is that image code at host-service depth zero holds no Linux locks and cannot disable hardware interrupts ([Stopping, line 181](../../book/src/accepted-design/stopping-a-kernelet.md#L181)). The mirrored Linux preemption count is removed by trusted exit code, rather than a forgotten guard's destructor ([`klet_mirror_out`](../../prototype/linux/endovisor/carrier.c#L578-L617)).

**Assessment.** Independent revocation is already the architecture's explicit solution. Correctness of the entry/exit implementation is still required, but an argument that the failed kernel must unlock itself would misdescribe the design. This pass found no additional resource-ownership responsibility that needs to move between layers.

### 3. Forget an in-flight I/O handle, or die while a device still accesses a buffer

**Attack.** A Rust handle disappears without cancellation, or the instance dies while another principal/device retains access; immediately freeing its grant would be unsafe.

**Existing answer.** TypedIO explicitly rejects frontend `Drop` as a cleanup protocol. Acceptance establishes both trusted pending ownership and an independent host lease before dispatch. Death stops acceptance, detaches notification/callback routing, and moves backing to host-owned retired-allocation records. Host records must not contain a pointer to a dead kernelet's `Arc`, allocator, or destructor. A backend must prove quiescence before release; timeout/cancellation alone cannot do so. Concurrent acceptance/removal/teardown share a protected decision and generations cannot wrap into reuse ([TypedIO, lines 821–853](../../book/src/design-proposals/2026-11-08-typed-io.md#L821-L853)).

**Assessment.** This is an important cross-layer architectural obligation, but it is already the purpose of the existing lease/detachment design. Listing it as an undiscovered Fault Isolation gap would duplicate that proposal. Integration and soundness work remain; neither is evidence that the responsibility is absent from the design.

### 4. Repeatedly kill instances so incomplete I/O retains unbounded memory

**Attack.** Each dead instance leaves one inaccessible allocation, and the attacker creates replacements indefinitely.

**Existing answer.** TypedIO charges the complete retained allocation, including an entire grant when that is the retention unit. Per-instance credits are backed by host-wide admission bounds; creation/restart cannot authorize unlimited retained grants. The design permits charged quarantine and refusal of new admission when a backend cannot provide bounded reset ([TypedIO, lines 849–861](../../book/src/design-proposals/2026-11-08-typed-io.md#L849-L861)).

**Assessment.** A stronger guarantee that every killed instance's backing becomes reusable within a fixed deadline would require bounded backend cancellation/reset or narrower supported backends. That would be a substantive availability-contract change. The current proposal explicitly excludes the unconditional deadline, so its absence is not a newly established design defect.

### 5. Enter a host operation that does not promptly return

**Attack.** The carrier is inside trusted Linux code when killed. Evicting arbitrary instructions there could abandon Linux locks or incomplete global state.

**Existing answer.** The service-depth boundary excludes that execution from forced image eviction. The host service completes or its defined killable wait ends, then the service wrapper refuses to resume the doomed instance ([Stopping, lines 44–51 and 181–183](../../book/src/accepted-design/stopping-a-kernelet.md#L44-L183); [service prologue/epilogue](../../prototype/linux/endovisor/carrier.c#L1841-L1867); [fatal return check](../../prototype/linux/endovisor/carrier.c#L1977-L2017)). The baseline buffers output to avoid a carrier blocking on a pipe/terminal ([ABI, line 189](../../book/src/accepted-design/the-kernelet-abi.md#L189)), though final destruction waits for its output worker ([`klet_sandbox_destroy`](../../prototype/linux/endovisor/sandbox.c#L625-L645)).

**Assessment.** Independent control over faulty safe image code does not imply permission to abort arbitrary trusted Linux execution. A universal kill-to-complete-reclamation deadline therefore requires service/backend progress assumptions. The book does not give a universal numeric full-reclamation deadline. The existing restriction is a meaningful architectural boundary, and an unbounded sink is a progress qualification, not proof that the language-based confinement model is fundamentally wrong.

### 6. Charge only the grant while safe code consumes other host resources

**Attack.** A sandbox stays within `memory_max` but consumes host heap, stack, metadata or worker resources, so a single field does not enforce total isolation.

**Existing answer.** The UAPI defines `memory_max` as a ceiling over granted memory, separately defines `max_tasks`, and assigns the instance to a runtime-controlled cgroup. The tracked heap and its allocation table use `GFP_KERNEL_ACCOUNT` ([heap code, lines 1343–1448](../../prototype/linux/endovisor/carrier.c#L1343-L1448)). The local-heap draft expressly says image/stack/address-space allocations remain separately accounted ([line 80](../../book/src/design-proposals/2026-11-16-allocate-the-kernelet-heap-from-the-grant.md#L80)). TypedIO adds admitted-work and retained-backing limits, while explicitly excluding full cgroup attribution of shared backend workers from its initial guarantee ([lines 857–861](../../book/src/design-proposals/2026-11-08-typed-io.md#L857-L861)).

**Assessment.** Accounting and a configured quota are distinct. A complete deployment contract should identify the configured limits and origin attribution for each admitted resource. But the fact that one field is not a total-footprint cap does not contradict that field's stated contract. Full controller attribution for arbitrary shared backends would be a stronger supported-service contract; the current TypedIO text already marks its boundary.

## What a separate Fault Isolation proposal could contribute

A useful proposal could make the existing composition explicit around this common contract:

> A permitted safe client can damage its private state and exhaust its admitted authority. It cannot forge another instance's authority or prevent host-controlled execution revocation by retaining private objects. The host never reuses backing while any trusted/external accessor still holds authority to access it; any delayed retention stays accounted and bounded by admission policy.

This is a source-grounded synthesis to discuss, not a new implemented or proved guarantee. It has four responsibility edges: instance identity/authority, host admission, independent stop/detach, and quiescence before charged reclamation. The sources above already assign owners to each edge.

Before calling the design architecturally incomplete, identify a permitted safe execution for which one of those edges has no enforcement mechanism, or a specific advertised availability bound that existing service contracts cannot meet. This pass found no new such example outside mechanisms already covered by current proposals and the separate fault-entry review.

A proposal that only centralizes these conditions would primarily improve the fault model and composition argument. A proposal requiring bounded cancellation/reset and full origin-controller propagation would change backend contracts and responsibility across layers, but it would deliberately strengthen the guarantee rather than repair a demonstrated claim the current text already makes.

## Limits of this conclusion

This is source-based architectural analysis of the book, tracked prototype, and cited proposals. It is not a proof of vOSTD soundness, a complete audit of every exported safe API, or a reproduced failure test. The separate local Linux PoC and Asterinas-host implementations have different implementation coverage and are not treated as interchangeable. No VM was run and no temporary files were created. Existing research and manuscript files were preserved; this note is the only new artifact for this pass.
