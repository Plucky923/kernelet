# Fault isolation: host state and reclamation

Date: 2026-11-16. This is a source audit, not a new fault-injection run.

## Scope and provenance

The question is whether a faulty **safe-Rust kernel proper** can be stopped without leaving unsafe host state or permanently losing its backing resources. vOSTD, the endovisor, Linux, the compiler, and audited dependencies remain trusted. An implementation error in one of these components is a TCB defect to investigate, rather than an additional fault that the current architecture promises to contain. This boundary follows [Accepted Design](../../book/src/accepted-design/why-a-kernel-of-your-own.md#L51-L78).

Two implementations must be kept distinct:

- The tracked teaching prototype is based on repository HEAD `a5ec4b875d0a17890321a362fbc3fd16859b7eb4`. Its `prototype/linux/endovisor/` sources remain the baseline for the book.
- The ignored `poc/` checkout is a separate implementation, at nested HEAD `7f8476ab463f1dcdf901fd650ee4f127298d28ef` with local integration code. The inspected working files, not that revision alone, describe its behavior. It implements SMP Asterinas, direct PTE management, additional fault hooks, and a different allocator/lifecycle.
- The parent checkout has existing modifications to `book/src/SUMMARY.md` and `prototype/linux/patches/0001-carrier-hooks.patch`, plus local direct-page-table/heap proposals and images. The modified host patch must not be mistaken for integration of those features into the tracked endovisor.
- `research/` and `poc/` are ignored by the parent repository. This note is a local research deliverable.

The audit covers lifecycle, host state, resource retention, and release conditions. Stack/CPU-fault completeness is reviewed separately. This note reads test assertions and the local results summary but does not independently reproduce those measurements or claim a complete source audit of the nested checkout.

## Conclusions

1. Stopping all carriers is a prerequisite for reclamation, but exit notification, final backing release, and release of the controlling FD are distinct events.
2. Both implementations avoid relying on Rust destructors after forced termination. Host-owned allocation records and Linux references, rather than the damaged kernel proper, authorize cleanup.
3. The tracked prototype has a concrete host-state cleanup path. Its output worker is an example of why full reclamation has no demonstrated unconditional time bound.
4. The Linux PoC adds meaningful teardown machinery: synchronous final page-table teardown, TLB invalidation, RCU waiting, slot/notifier detachment, and whole-grant release. An optional asynchronous per-space teardown mode has a disclosed outstanding page-table-lifetime condition.
5. The PoC has a confirmed static destruction-ownership defect: two paths can initialize and enqueue the same destruction work item. Its runtime consequences have not been reproduced here.
6. TypedIO explicitly extends the release predicate to host/device leases. Those proposed guarantees cannot be inferred from the existing carrier count alone.

## 1. The tracked prototype's termination sequence

The following is verified from the current C sources:

| Stage | Action | Source |
|---|---|---|
| Mark | Record the first exit reason, set `dying`, send `SIGKILL` to carriers, arm eviction | [`sandbox.c:529`](../../prototype/linux/endovisor/sandbox.c#L529-L554) |
| Stop execution | User-mode carriers die through Linux; service callers finish their host service and are marked `doomed`; carrier code at depth zero can be redirected to the exit stub | [`carrier.c:1074`](../../prototype/linux/endovisor/carrier.c#L1074-L1099), [`carrier.c:1977`](../../prototype/linux/endovisor/carrier.c#L1977-L2017), [`evict.c:40`](../../prototype/linux/endovisor/evict.c#L40-L79) |
| Notice death | The lifeline release removes a carrier and decrements `nr_carriers`; loss of one live carrier ends the whole sandbox | [`carrier.c:315`](../../prototype/linux/endovisor/carrier.c#L315-L380) |
| Reap private execution resources | Once no carriers remain, destroy spaces, all tracked heap blocks, and the stack pool, without running kernelet destructors | [`carrier.c:292`](../../prototype/linux/endovisor/carrier.c#L292-L311) |
| Publish exit | Stop counting the sandbox as needing eviction, set `exited`, wake exit-record readers | [`sandbox.c:560`](../../prototype/linux/endovisor/sandbox.c#L560-L590) |
| Final destruction | After exit and last sandbox-FD release, flush output, free output records, grant pages, image mapping, exec files, shared space records, and cgroup references | [`sandbox.c:625`](../../prototype/linux/endovisor/sandbox.c#L625-L668) |

**Implication:** “the sandbox has exited” does not mean that its grant and image have already been released. Keeping the sandbox FD open deliberately retains those resources. A cleanup assertion needs to specify which lifecycle point it observes.

### State that must be repaired or detached

| Host state | Existing mechanism | Boundary |
|---|---|---|
| Linux preemption count | `klet_mirror_out` measures the excess over entry state and removes it; permanent exit forgets it. An anomalous excess is normalized and counted | [`carrier.c:565`](../../prototype/linux/endovisor/carrier.c#L565-L616). The actual anomaly branch repairs the count; its comment's mention of stopping is not a demonstrated stop action |
| Hooks and syscall-work bit | Clear both before the carrier's final Linux exit | [`carrier.c:267`](../../prototype/linux/endovisor/carrier.c#L267-L288) |
| Preemption notifier | Unregister from the carrier's own task before releasing its record | [`sched.c:174`](../../prototype/linux/endovisor/sched.c#L174-L179), [`carrier.c:383`](../../prototype/linux/endovisor/carrier.c#L383-L420) |
| Address-space ownership | Leave the adopted space on detach; final space destruction clears `mm->owner`, waits for RCU readers, and drops the owner pin | [`carrier.c:273`](../../prototype/linux/endovisor/carrier.c#L267-L288), [`space.c:546`](../../prototype/linux/endovisor/space.c#L546-L570) |
| Watch/sweep activity | Watch stops for dead/dying instances; sweep count drops after exit; module unload synchronously cancels timers | [`watch.c:170`](../../prototype/linux/endovisor/watch.c#L170-L173), [`sandbox.c:566`](../../prototype/linux/endovisor/sandbox.c#L566-L571), [`evict.c:131`](../../prototype/linux/endovisor/evict.c#L131-L142) |
| FPU staging allocation | Free the host staging page during detach or lifeline cleanup | [`carrier.c:275`](../../prototype/linux/endovisor/carrier.c#L275-L288), [`carrier.c:332`](../../prototype/linux/endovisor/carrier.c#L332-L345). This alone does not establish completeness of FPU exception recovery |
| Kernelet locks and objects | Abandon them; reclaim backing only after no carrier can use it | [`stopping-a-kernelet.md:11`](../../book/src/accepted-design/stopping-a-kernelet.md#L11) |

The central condition is not that the failed kernel proper voluntarily releases its locks. It is that the host can stop every participant, restore host-owned state, and then reclaim storage independently.

### Host service completion is part of termination

The eviction sweep excludes instructions outside the image and any carrier with `depth != 0`. The service prologue raises depth and removes the mirror; the epilogue restores host/kernelet execution state. A fatal signal is checked before returning to kernelet code. Sources: [`evict.c:55`](../../prototype/linux/endovisor/evict.c#L55-L65), [`carrier.c:1841`](../../prototype/linux/endovisor/carrier.c#L1841-L1867), [`carrier.c:1977`](../../prototype/linux/endovisor/carrier.c#L1977-L2017).

**Design obligation:** a service that can wait needs a termination contract of its own. A timer cannot safely abandon arbitrary Linux code holding Linux locks. The current mechanism therefore does not by itself establish a universal millisecond bound from kill request to full reclamation.

## 2. Descriptor and asynchronous-output qualifications

### Lifeline references

Ordinary carrier death releases its lifeline in its own exit context, allowing notifier/hook detachment. A privileged copy obtained using `pidfd_getfd` can keep that file alive after the carrier exits. If its final release occurs elsewhere while hooks/notifiers remain attached, the prototype deliberately retains the carrier record instead of risking a use-after-free. Sources: [`carrier.c:383`](../../prototype/linux/endovisor/carrier.c#L383-L420), [`carriers.md:158`](../../book/src/accepted-design/carriers.md#L158).

This is a lifetime/authority qualification. It is not evidence that an ordinary safe kernel proper can duplicate its lifeline or escape isolation. A guarantee of unconditional prompt destruction must state its assumptions about host descriptor holders and privileged observers.

### Output retention

The prototype synchronously copies output into a bounded host FIFO; an output worker later calls `kernel_write`. It does not retain the original kernelet buffer for asynchronous use. Sources: [`sandbox.c:67`](../../prototype/linux/endovisor/sandbox.c#L67-L108).

Final destruction calls `flush_work(&inst->out_work)` **before** releasing the grant and image. There is no nonblocking-output or deadline protocol in these functions. Therefore the audit establishes ordering, but not a bound on completion when an attached sink does not make progress. Source: [`sandbox.c:639`](../../prototype/linux/endovisor/sandbox.c#L639-L646).

This output-worker observation applies to the tracked prototype. The Linux PoC instead copies bounded strings into host storage and uses `printk`; it does not implement this FIFO/work-item path. Source: [`poc_carrier.c:955`](../../poc/linux/endovisor/poc_carrier.c#L955-L994).

## 3. The local Linux PoC's reclamation protocol

The PoC retains the distinction between `dying`, `exited`, FD release, and destruction. Its last carrier publishes `exited`; backing cleanup runs later through `destroy_work` once the sandbox FD has been released. Sources: [`poc_main.c:126`](../../poc/linux/endovisor/poc_main.c#L126-L198), [`poc_main.c:664`](../../poc/linux/endovisor/poc_main.c#L664-L689).

The destroy worker executes this order:

1. Unmap private image/CPU-local mappings.
2. Destroy remaining spaces.
3. Destroy stack mappings, initramfs mappings, metadata mappings, grant grains, and shared record mappings.
4. Unpublish the instance/exec files and drop cgroup/owner references.

Sources: [`poc_main.c:105`](../../poc/linux/endovisor/poc_main.c#L105-L123), [`poc_grant.c:580`](../../poc/linux/endovisor/poc_grant.c#L580-L640), [`poc_image.c:580`](../../poc/linux/endovisor/poc_image.c#L580-L614).

The PoC's detach path clears syscall work and hooks, detaches the scheduler notifier, clears the current per-CPU slot, leaves the adopted address space, and drops its own empty-mm reference. Scheduler switch-in/out also sets/clears the slot, and switch-in completes carrier FPU restoration. Sources: [`poc_carrier.c:181`](../../poc/linux/endovisor/poc_carrier.c#L181-L195), [`poc_carrier.c:307`](../../poc/linux/endovisor/poc_carrier.c#L307-L340).

### Direct-page-table release conditions

For direct mode, host teardown clears both relevant user PGDs when PTI is active, issues a whole-mm TLB flush with `freed_tables=true`, clears `mm->owner`, and normally waits for `synchronize_rcu()` before returning. Final sandbox destruction forces this synchronous mode, and drains pending callbacks with `rcu_barrier()` when asynchronous destruction is enabled. Sources: [`poc_space.c:253`](../../poc/linux/endovisor/poc_space.c#L253-L312), [`poc_space.c:437`](../../poc/linux/endovisor/poc_space.c#L437-L462).

The optional `async_destroy=1` mode instead queues the mm's final release with `call_rcu` and returns immediately from individual space unregister. `VmSpace::drop` calls unregister before its fields are subsequently dropped. The local evaluation record explicitly identifies lower-table lifetime across lockless host readers as unfinished for that ablation; synchronous destruction is the default. Sources: [`poc_main.c:46`](../../poc/linux/endovisor/poc_main.c#L46-L48), [`poc_space.c:305`](../../poc/linux/endovisor/poc_space.c#L305-L312), [`vm_space.rs:230`](../../poc/ostd/src/mm/vm_space.rs#L230-L242), [local evaluation record](../user-page-table/results.md#33-poc_async_destroy-ablation-6-kvm-boots-direct-pte).

This is an ordering requirement, not a claim of a newly reproduced race. A faster asynchronous mm release alone cannot justify earlier reuse of lower-table backing.

### Confirmed static implementation defect: destruction-work ownership

The PoC release path sets `inst->released = true`, then calls `poc_end`, then checks `inst->exited`. If true, it initializes and queues `destroy_work`. Independently, `poc_sandbox_exited` initializes and queues that same work item when it sees `released`.

A concrete source-level interleaving is:

1. Close the last sandbox FD while the instance has no carriers, or while its last carrier is exiting.
2. Release publishes `released=true`.
3. `poc_end` or the carrier exit calls `poc_sandbox_exited`; that path initializes/queues the destroy work.
4. Release observes `exited=true` and initializes/queues the same item again.

Sources: [`poc_main.c:176`](../../poc/linux/endovisor/poc_main.c#L176-L198), [`poc_main.c:664`](../../poc/linux/endovisor/poc_main.c#L664-L689).

The tracked prototype explicitly avoids that ordering by calling `klet_end` before publishing `released`. Source: [`sandbox.c:815`](../../prototype/linux/endovisor/sandbox.c#L815-L835).

**Status:** confirmed static scheduling/ownership defect requiring a single-owner destruction decision and a separate implementation check. The no-carrier close sequence reaches both initialization/queue sites without needing a concurrent carrier exit. The exact effects when the first work item is pending or running have not been reproduced here; this is not a reproduced use-after-free. This concerns trusted cleanup code; it is not evidence that arbitrary vOSTD faults are in the promised containment model.

## 4. Memory exhaustion and leaked Rust objects

The tracked prototype's host heap records allocations separately from Rust objects and frees outstanding blocks after all carriers stop. `mem_alloc` bounds request size/alignment, charges allocations to the carrier's memory cgroup, and returns null on allocation failure. Sources: [`carrier.c:1312`](../../prototype/linux/endovisor/carrier.c#L1312-L1345), [`carrier.c:1409`](../../prototype/linux/endovisor/carrier.c#L1409-L1448), [`carrier.c:1503`](../../prototype/linux/endovisor/carrier.c#L1503-L1529).

The book's `memory_max` limits granted memory; it is not a single ceiling over all heap, stack, image, metadata, and Linux address-space resources. Thus “accounted” and “bounded by this one field” are different properties. The host runtime's cgroup policy is part of a resource-isolation argument. Source: [`the-endovisor-uapi.md:400`](../../book/src/accepted-design/the-endovisor-uapi.md#L400).

The local heap proposal changes the accounting/reclamation layout by moving Rust allocation into the grant. That can simplify whole-backing reclamation, but memory safety still depends on vOSTD and storage must remain live until every permitted accessor is gone. Source: [local heap proposal](../../book/src/design-proposals/2026-11-16-allocate-the-kernelet-heap-from-the-grant.md#reclaim-the-grant-after-a-failure).

The Linux PoC already has a distinct grant/metadata/stack arrangement and whole-backing destroy routine. Its resource behavior must be assessed from its own allocator and limits, rather than assigning the teaching prototype's host-heap table to it. Source: [`poc_grant.c:580`](../../poc/linux/endovisor/poc_grant.c#L580-L640).

## 5. Async I/O extends the release predicate

The current teaching prototype has no general devices. TypedIO is a design proposal with its own unimplemented integration obligations. It requires host-owned retention of both the DMA resource and its backing grant, rejection of new work on death, notification detachment, carrier/mapping teardown, and release only after host CPU/DMA/copy-back accesses end. Sources: [`TypedIO: retention`](../../book/src/design-proposals/2026-11-08-typed-io.md#L313-L343), [`TypedIO: death`](../../book/src/design-proposals/2026-11-08-typed-io.md#L819-L853), [`TypedIO: integration`](../../book/src/design-proposals/2026-11-08-typed-io.md#L1336-L1340).

Its accounting charges retained backing, including an entire grant retained by one page, and applies per-instance plus host-wide admission bounds. Cancellation or timeout does not authorize freeing accessible memory; bounded backend reset or charged quarantine is required. It explicitly does not promise unconditional wall-clock reclamation for arbitrary Linux I/O. Source: [`TypedIO: resource bounds`](../../book/src/design-proposals/2026-11-08-typed-io.md#L855-L861).

The resulting design predicate is:

> Reuse backing only after no carrier can execute on it, no tenant mapping or relevant TLB/RCU reader can reach it, no host/device lease permits further access, and a host-owned record authorizes release.

This predicate is an audit obligation derived from the cited mechanisms. It is not a statement that every component has already been implemented and tested together.

## 6. Evidence and follow-up

Existing prototype checks assert clean module unload, zero outstanding heap blocks/stacks/carrier records, sandbox destruction, and selected kill paths. Those are meaningful lifecycle checks for their workloads. Source: [`prototype/Makefile:560`](../../prototype/Makefile#L560-L590), [`prototype/Makefile:853`](../../prototype/Makefile#L853-L872).

The local PoC evaluation records holder-kill, user-exception, rejected FPU-import, and PTI cases. The PoC runner reaps carriers, reads exit statistics, and then closes the sandbox FD; this usual order does not by itself exercise the close-versus-last-exit concern above. Sources: [evaluation matrix](../user-page-table/results.md#4-safety-isolation--pti-verification-matrix), [`run-poc.c:440`](../../poc/linux/runner/run-poc.c#L440-L471).

No new VM boots, fault injection, stress tests, or allocation-ledger measurements were run for this note. In particular, no result here proves bounded destruction with a blocked output sink, concurrent final-close/final-exit safety, or correct retirement of future device leases.

The next focused checks should establish:

1. One owner of instance destruction under unstarted close and close-versus-last-carrier exit.
2. A clear distinction between exit notification, CPU containment, and actual release of every host backing allocation.
3. Host-state cleanup after each supported fault path, including mirror/count, notifier/slot, mm/TLB/RCU, and FPU ownership where relevant.
4. A complete list of host-held references/leases and the event that makes each one releasable; cancellation alone is insufficient.
5. Resource/latency guarantees stated with their cgroup, scheduler, observer, and backend-progress assumptions.
