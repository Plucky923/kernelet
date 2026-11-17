# Fault isolation: architecture scope and remaining decisions

Date: 2026-11-16. This follows the earlier engineering and contract audit. The question here is whether an uncovered design decision changes the trust boundary, execution authority, or ownership model. It is not a request to find more missing tests.

## Conclusion

Scheduling and memory have substantial proposal coverage. Fault isolation is a useful next architecture-review axis, but this pass establishes no new fundamental contradiction in the device-free architecture beyond the previously recorded contract and stack-entry defects. The book already combines language confinement with host-controlled preemption and independent teardown; it does not infer complete containment from safe Rust alone.

The strongest remaining architecture decision is the fault domain of safe host-side backends. TypedIO intentionally separates memory-lifetime safety from backend policy correctness, worker CPU attribution, and bounded reclamation. Extending containment to faulty backend execution would require a decision about where that code runs and how the host revokes its execution. Existing carrier eviction does not provide this automatically. This is an explicit scope choice to review, not a newly demonstrated vulnerability in an implemented backend.

## Existing proposal coverage

| Area | Current direction | Important boundary |
|---|---|---|
| Two-level scheduling | [Coordinate the two schedulers](https://github.com/Plucky923/kernelet/blob/005710cc617ac0c639d6ea1ab119e61e44d0fb57/book/src/design-proposals/2026-11-04-coordinate-the-two-schedulers.md) | Draft in the preview branch; retains watch/mirror and defers sleeping/waking coordination. |
| Execution handoff | [PR #3](https://github.com/tatetian/kernelet/pull/3), head `ee1b2267e6178c6afaf22d73ad961f0c227ec8db` | Open proposal; event delivery and user-context ownership are already under redesign. |
| FPU ownership and fatal restore faults | [PR #7](https://github.com/tatetian/kernelet/pull/7), head `cbe7bf32681a4777f983e3b7ad15a23b58b0a34a` | Draft; its fatal-exception policy is not proof that every exception can enter the handler safely. |
| User page-table ownership | [Direct PTE draft](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md) | vOSTD writes lower tables; Linux retains CR3/TLB/RCU and independent teardown. |
| Object allocation | [Grant-backed heap draft](../../book/src/design-proposals/2026-11-16-allocate-the-kernelet-heap-from-the-grant.md) | Host backing ownership and reclamation are distinct from local object allocation. |
| Capacity return | [PR #4](https://github.com/tatetian/kernelet/pull/4), head `5dea2a6442de477579d068e71efcfb41ad74ea40` | Experimental returnable extents; not an accepted general memory-pressure design. |
| Cross-boundary I/O lifetime | [TypedIO](../../book/src/design-proposals/2026-11-08-typed-io.md#lifetime-and-resource-bounds) | Independent host leases, detachment, admission limits, and charged quarantine already address non-cooperating frontends. |

GitHub PR states were read live. The local direct-PTE and heap documents remain Draft; their stated implementation status and any separate dirty PoC must not be conflated. Proposal coverage is not acceptance, completion, or validation.

## 1. Which faults are promised to remain local?

The [book's threat model](../../book/src/accepted-design/why-a-kernel-of-your-own.md#a-kernel-in-two-layers) permits a buggy safe kernel proper but trusts vOSTD, the allowed unsafe dependencies, the compiler, endovisor, and Linux. A vOSTD implementation fault that permits arbitrary privileged execution is outside that guarantee. Enlarging the promise to arbitrary faults in the whole kernelet image would change the protection architecture; this pass does not establish a mechanism for that stronger promise.

The relevant audit is therefore whether a safe caller can violate trusted assumptions through permitted arguments, call sequences, concurrency, forgotten guards, or non-progress. Merely placing an operation in vOSTD does not make safe caller-controlled misuse out of scope. The earlier affinity finding is one local example; its existence does not establish that the whole trust split must be replaced. Rust's [safe/unsafe contract](https://doc.rust-lang.org/nomicon/safe-unsafe-meaning.html) requires unsafe implementations to defend against incorrect safe client implementations.

## 2. Does the host retain authority after kernel-proper progress stops?

The baseline already supplies substantial answers. [Stopping a kernelet](../../book/src/accepted-design/stopping-a-kernelet.md#the-shape-of-a-death) abandons private state without running its destructors, stops all carriers, then reclaims host-recorded resources. Its [eviction argument](../../book/src/accepted-design/stopping-a-kernelet.md#eviction) depends on image code holding no Linux locks at service depth zero; the host repairs mirrored preemption state. Forgotten tenant locks can break the tenant's own progress without becoming Linux cleanup dependencies.

This matches the language constraint: safe Rust may [forget values without running destructors](https://doc.rust-lang.org/core/mem/fn.forget.html#safety). The heap draft's failure section, the direct-PTE draft's ordered TLB/RCU teardown, and TypedIO's independent leases extend the same ownership principle. They should be reviewed together for composition, but their absence cannot be claimed.

Entry from an exhausted stack and the full restoration path remain obligations recorded in the [earlier inventory](README.md) and [reclamation audit](reclamation-audit.md). No new runtime recovery experiment was run. A unified fault-isolation argument should identify those obligations without presenting every local repair as a new architectural flaw.

## 3. Safe backend execution is a separate fault-domain decision

[TypedIO's architecture](../../book/src/design-proposals/2026-11-08-typed-io.md#architecture) places device policy in safe backends and explicitly says safe Rust proves neither policy correctness nor progress. Its [backend framework](../../book/src/design-proposals/2026-11-08-typed-io.md#backend-framework) runs `Backend::handle` on bounded Linux work queues, outside carrier execution. Meanwhile, the [watch callback](../../prototype/linux/endovisor/watch.c) stops immediately when the current Linux task has no `carrier_hooks` (lines 161–169).

A source-derived boundary case, not an observed failure:

1. Instance A submits an admitted operation; a host worker invokes its safe backend handler.
2. A handler logic bug runs a non-yielding loop. Rust memory safety remains intact and no extra request slot is needed.
3. Killing A evicts its carriers and detaches notifications. It does not independently revoke execution of that ordinary worker callback.
4. With full Linux preemption, the worker can be descheduled, but descheduling does not terminate the callback or establish quiescence. Under the book's supported `preempt=none` configuration, the carrier-specific watch also supplies no forced-yield mechanism for that worker. The [book's preemption explanation](../../book/src/accepted-design/sharing-a-processor-politely.md#problem-1-a-linux-that-does-not-preempt-kernel-code) establishes that configuration dependency; Linux's [workqueue execution](../../reference/linux-6.12/kernel/workqueue.c) directly calls `worker->current_func(work)` at line 3229.

Bounding slots limits occupancy; it does not bound the execution time of one callback. Dedicated workers or explicit cgroup attribution can improve accounting and scheduling separation but do not by themselves make arbitrary callback abortion safe. A design that promises non-cooperative backend revocation must control borrowed Linux state as well as instruction execution. This note selects no mechanism.

TypedIO already declares the limitation: [resource bounds](../../book/src/design-proposals/2026-11-08-typed-io.md#resource-bounds) exclude automatic per-instance worker CPU/cgroup attribution and allow charged quarantine when completion/reset cannot establish bounded quiescence. Accordingly, the decision is whether to retain that narrower guarantee or expand the revocable fault domain. Backend authorization is also a separate property: the proposal already has attachment capabilities and target-range checks, so no authorization bypass is established here.

## Next review and evidence limits

The next focused review should make three distinctions explicit: which components are trusted for memory safety versus policy/progress; which execution contexts the host can revoke without cooperation; and which resources become reusable at execution stop versus only after external quiescence. Use the existing stop, FPU, page-table, heap, and TypedIO designs as the starting mechanisms.

Companion source audits: [host execution and trust](architecture-host.md), [ownership and resource containment](architecture-resources.md). This is a static source/design review. No VM tests, fault injection, build, or new isolation proof was performed; book and prototype files were not changed.
