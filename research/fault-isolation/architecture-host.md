# Fault isolation architecture: host authority and backend fault domains

Date: 2026-11-16. Parent baseline: `a5ec4b875d0a17890321a362fbc3fd16859b7eb4`, with existing local proposal and Linux-patch modifications preserved. This is a source-based architectural assessment. No new VM tests, fault injections, or implementation changes were made.

## Assessment

For the device-free Accepted Design, this review establishes no new major architectural contradiction once the stated trusted components are correct and their execution/reclamation contracts are implemented. Stack protection, affinity enforcement, retirement progress, and local cleanup races should not be repackaged as independent architectural proposals in this pass.

“Safe Rust soundness plus a host timer” is not a sufficient theorem by itself. The book's argument also relies on restricted authority, host-controlled lifecycle, restoration of borrowed host state, and independently tracked backing. Those responsibilities already have an architectural home in the book and the current proposals. Their need does not establish a new division-of-responsibility defect.

One proposal-level choice remains worthwhile if the intended fault domain expands: **whether shared safe host backends are also allowed to fail arbitrarily, and what containment then means for them.** TypedIO already makes its present availability limitations explicit. The choice is an extension of that guarantee, not a newly discovered vulnerability.

## 1. The actual fault model and what is already assigned

[Why a kernel of your own, lines 51–78](../../book/src/accepted-design/why-a-kernel-of-your-own.md#L51-L78) distinguishes operator-built code, faulty safe kernel proper, and trusted vOSTD/host/compiler/dependencies. The permitted fault domain is not arbitrary faulty machine code in every trusted component. The book also excludes side channels at line 80.

Under that model, kernel proper may choose arbitrary permitted safe operations, panic, loop, hold its own locks forever, and leak its own objects. The trusted interface must keep the consequences within its authority and let the host stop the instance. Existing responsibilities are:

| Property needed for containment | Component or existing design direction |
|---|---|
| Confine accessible memory and resources | Sound vOSTD interfaces and host checks, not merely use of Rust syntax. The direct-page-table draft explicitly keeps grant-bound enforcement in vOSTD: [lines 55–66](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L55-L66). |
| Stop noncooperating kernel proper | Host-owned carrier lifecycle and image-scoped eviction; no dependency on kernel-proper locks being released: [Stopping, lines 125–183](../../book/src/accepted-design/stopping-a-kernelet.md#L125-L183). |
| Preserve host state across delegated execution | Service depth prevents abandoning Linux code; mirror transitions bracket service calls: [Two stacks, lines 225–229](../../book/src/accepted-design/two-stacks.md#L225-L229), [Sharing a processor, lines 169–186](../../book/src/accepted-design/sharing-a-processor-politely.md#L169-L186). |
| Recover architectural FPU state and classify fatal kernel faults | PR #7's earlier carrier restoration, checked imports, and fault cleanup: [pinned proposal](https://github.com/tatetian/kernelet/blob/cbe7bf32681a4777f983e3b7ad15a23b58b0a34a/book/src/design-proposals/2026-11-09-fpu-state-management.md#an-exception-occurs-in-kernelet-kernel-code). |
| Reclaim backing without running damaged Rust state | Host-side stop, all-carrier exit, host allocation records: [Stopping, lines 5–15](../../book/src/accepted-design/stopping-a-kernelet.md#L5-L15). The local heap draft preserves whole-grant cleanup: [lines 70–76](../../book/src/design-proposals/2026-11-16-allocate-the-kernelet-heap-from-the-grant.md#L70-L76). |
| Sever Linux page-table references before reusing grant backing | The direct-page-table draft assigns root clearing, TLB invalidation, host RCU, and mm release to endovisor/Linux: [lines 144–164](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L144-L164). |
| Retain asynchronously accessible storage beyond instance death | TypedIO host leases, detachment, admission accounting, and quarantine: [lines 819–861](../../book/src/design-proposals/2026-11-08-typed-io.md#L819-L861). |

This allocation of responsibility is coherent in principle: Linux controls scheduling and externally visible backing, vOSTD controls safe kernel-proper access within that backing, and damaged kernel-proper state need not participate in termination. This is an architectural inference from the cited contracts, not a proof that every existing implementation satisfies them.

### Why several apparent counterexamples do not establish a new architecture problem

- A defect in vOSTD's unsafe implementation is outside the permitted arbitrary-fault domain. An input that safe kernel proper is allowed to supply remains an obligation of that trusted implementation; it cannot simply be declared out of scope because the faulting instruction is inside vOSTD. PR #7 addresses that distinction for FPU import and restoration.
- The ability to leave a guard or object undropped does not require running its destructor on host kill. The book already abandons the instance after stopping all participants and restores host-owned state independently.
- A timer's inability to abandon Linux while Linux holds its own locks is deliberate. [Stopping, lines 49–50 and 183](../../book/src/accepted-design/stopping-a-kernelet.md#L44-L51) waits for trusted services to finish. The baseline therefore assumes host-service progress; the timer is authority over kernel-proper execution, not arbitrary host execution.
- Device cancellation cannot instantly revoke an already active DMA access. TypedIO explicitly retains and charges storage instead of pretending that cancellation proves quiescence. That is an existing design answer, with a stated availability cost.

## 2. The substantial choice: what fault domain contains a safe host backend?

### Existing contract

TypedIO's [memory-safety goal, line 40](../../book/src/design-proposals/2026-11-08-typed-io.md#L40) supports safe frontend/backend code while keeping the memory-safety TCB small. Its [layer split, lines 105–112](../../book/src/design-proposals/2026-11-08-typed-io.md#L105-L112) assigns device authorization/protocol policy to safe backends and explicitly warns that safe Rust does not prove policy correctness or progress.

Handlers run on bounded Linux work queues after service locks are released. Their safe interface is `Backend::handle(HostRequest<R>)`. The request owns captured state and retained resources independently of the frontend. Sources: [registration and worker execution, lines 413–435](../../book/src/design-proposals/2026-11-08-typed-io.md#L413-L435), [request lifetime, lines 449–453](../../book/src/design-proposals/2026-11-08-typed-io.md#L449-L453).

The host still validates attachment identity, rights, and permitted resource use ([lines 236–238](../../book/src/design-proposals/2026-11-08-typed-io.md#L236-L238)). Thus the existence of safe backend policy code does not, by itself, prove an authorization escape or absence of capability enforcement.

### Concrete permitted-code scenario

Consider a backend implementation with a protocol bug that takes a legal request into an infinite computation. An illustrative safe body is `fn handle(&self, request: HostRequest<R>) { loop { core::hint::spin_loop(); } }`. This is a counterexample to an automatic execution-revocation inference, not a claim about an existing backend's code.

1. Tenant A's request is admitted. The host framework records ownership, credits, and backing retention.
2. A Linux worker enters the safe backend's `handle` and never returns. It need not violate Rust memory safety or retain a framework service lock.
3. The operator kills A. Carrier eviction stops all A's kernelet execution and detaches notifications.
4. That does not revoke the separate worker's execution. The accepted eviction predicate requires a carrier, an instruction in that carrier's image, and zero host-service depth; it does not cover an independent Linux worker. See [book predicate, line 127](../../book/src/accepted-design/stopping-a-kernelet.md#L127) and the supporting [eviction implementation, lines 51–65](../../prototype/linux/endovisor/evict.c#L51-L65).
5. The handler and retained resources can outlive A's carriers. Bounded worker/request credits constrain the amount of outstanding work; they do not force this execution to return or make the storage immediately reusable.

An ordinary preemptible Linux scheduler may still share CPU time with other tasks. That is different from attributing this worker's consumption to A, or forcibly terminating its arbitrary kernel continuation. The book also supports `preempt=none`, under which kernel computation needs a voluntary scheduling point or a return to user mode ([Sharing a processor, lines 9–17](../../book/src/accepted-design/sharing-a-processor-politely.md#L9-L17)). In that configuration, a backend loop without scheduling points may retain its physical CPU, while the carrier-specific watch/sweep machinery does not force that worker to yield. Full preemption changes this CPU-sharing outcome. No unconditional starvation of the entire host is asserted here.

### Why this is already acknowledged, and where a new decision begins

TypedIO [line 859](../../book/src/design-proposals/2026-11-08-typed-io.md#L859) explicitly excludes per-instance CPU-time and Linux cgroup attribution guarantees for shared workers. [Line 861](../../book/src/design-proposals/2026-11-08-typed-io.md#L861) explicitly permits charged quarantine and denies an unconditional I/O reclamation deadline. The scenario is therefore consistent with its stated initial contract. It is not a newly discovered gap in promised TypedIO memory safety.

The architectural decision is whether the broader Kernelet claim should also cover **arbitrary logical failure of safe shared backend code**, rather than only failure of kernel proper within a carrier:

- Keeping shared backends trusted for progress and policy correctness preserves the current boundary. The design should name that trust separately from the smaller memory-safety TCB. Under this decision, no new worker-termination mechanism is implied.
- Extending the faulty-code domain to backends requires an explicit execution and authority contract: what computation may continue after origin-instance death, who can revoke it, which host state it may hold, which authority checks remain enforced independently of its protocol decisions, and what guarantees are intentionally limited to accounting/quarantine.

Dedicated workers or worker cgroups can improve attribution and avoid some cross-instance scheduling interference. They do **not** automatically permit safe termination at any instruction of host code, prove a backend's authorization decisions correct, or cancel already submitted I/O. A complete extension must address those separately; it cannot be achieved by replacing a shared work queue with a per-instance one and reusing the carrier timer unchanged.

This would change a cross-layer contract between frontend, host framework, backend, and Linux adapters. It can justify an independent proposal if the author wants that wider fault domain. This review does not select a particular implementation or propose isolating every trusted component.

## 3. Implication for the book's containment claim

The defensible current claim is conditional: faulty safe kernel proper remains confined when the trusted framework enforces authority, host-controlled termination/restoration works, and host-side accesses obey their retention/progress contracts. Approved external I/O effects are not undone by sandbox death; stalled external operations may leave charged quarantined storage.

The stronger statement that all code written in safe Rust—including safe shared host policies—can fail arbitrarily and remain independently terminable does not follow from the existing memory-safety boundary or carrier timer. The current text does not uniformly promise that stronger statement, and TypedIO explicitly narrows it.

No new major architectural defect in the device-free baseline is established here. The useful frontier is to decide whether the system wants the stronger backend fault model, or to retain and accurately state the current trust and availability boundary. That decision comes before mechanisms or a new benchmark plan.

## Evidence limits

Sources were read from the current parent book, local draft proposals, pinned PR #7 text, existing research notes, and supporting tracked C code. The local PoC's earlier measurements and implementation bugs do not establish or refute this architectural scenario, so none are used as runtime evidence. No dead backend, policy escape, host corruption, or reclamation delay was experimentally reproduced in this pass.
