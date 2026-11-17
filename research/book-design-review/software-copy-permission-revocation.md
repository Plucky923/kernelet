# Software-copy permission revocation

**Status:** proposed engineering repair, 2026-11-16. No code has been changed and no dynamic validation has been performed. This strengthens vOSTD's existing mapping-coherence contract; it does not require a new Linux/vOSTD responsibility split.

## Required contract

After permission revocation completes, an image-side software access must not continue using a translation authorized by the previous permissions. Clearing a user PTE and invalidating hardware TLBs does not revoke an ordinary direct-map pointer already obtained by a software walker. Both forms of access must be covered before the caller publishes completion, exposes a fork child, or reuses an unmapped frame.

| Operation | Required completion condition |
| --- | --- |
| Fork/COW preparation, writable to read-only | Hardware write translations are invalidated and every software access that could have accepted the old writable entry has finished before the child becomes runnable. |
| `mprotect` removing write or read permission, including `PROT_NONE` | Hardware invalidation and completion of software accesses authorized by the previous entry precede the permission change's externally visible completion. |
| Unmap, replacement, or withdrawal into `withheld`/a non-readable representation | The old entry is unavailable to new accesses; hardware and prior software accesses have completed before old backing can be reused. Withdrawal requires this condition even when no frame is freed. |
| Permission expansion or a newly populated absent entry | No old permission needs revocation, but accesses still use the same protected translation path. The selected flusher implementation below also waits for software copies whenever it dispatches a user-root flush. |

Removing execute permission still requires the existing hardware protocol. Software data copies do not emulate instruction fetch. **Cache-policy changes are outside the sufficiency claim:** PTE publication, TLB invalidation, and a copy barrier do not establish compatible cache types across host aliases or perform required cache maintenance. The original prototype explicitly [accepts only write-back memory](../../prototype/vostd/src/mm/vm_space.rs#L204-L208).

## Source constraints

The original prototype's [`Region::resolve`](../../prototype/vostd/src/mm/io.rs#L54-L67) checks a PTE and returns its direct-map alias. [`copy_regions`](../../prototype/vostd/src/mm/io.rs#L110-L139) encloses each page's resolution and assembly access in its dedicated `mm::rcu::read`. That [RCU implementation](../../prototype/vostd/src/mm/rcu.rs#L30-L70) publishes per-vCPU sequence words and waits for active copies on other vCPUs. Its synchronous wait already depends on copies ending without taking a cursor lock.

The prototype [`TlbFlusher`](../../prototype/vostd/src/mm/tlb.rs#L122-L149) waits for this reader domain only when frames are being released. Pure permission downgrades therefore lack the required software-access completion point. [`protect_next`](../../prototype/vostd/src/mm/vm_space.rs#L643-L693) also has a withdrawal path which calls the backend's unmap without freeing a frame. [`unmap`](../../prototype/vostd/src/mm/vm_space.rs#L602-L639) separately performs a reader grace period before dropping frames.

The Linux PoC uses a different lifetime mechanism. Its [copy helper](../../poc/ostd/src/mm/io/copy.rs#L155-L225) holds a generic `DisabledPreemptGuard` across the whole operation. [Fill and user atomics](../../poc/ostd/src/mm/io/copy.rs#L229-L352) likewise translate user addresses and access aliases. The [user-root flusher](../../poc/ostd/src/mm/tlb.rs#L109-L128) performs a synchronous host shootdown; [`sync_tlb_flush`](../../poc/ostd/src/mm/tlb.rs#L199-L204) can then return immediately. [`OpsStack::clear_without_flush`](../../poc/ostd/src/mm/tlb.rs#L462-L467) defers destruction only when frames are queued.

Generic PoC RCU [uses preemption guards to protect readers](../../poc/ostd/src/sync/rcu/mod.rs#L169-L188), and [`RcuDrop`](../../poc/ostd/src/sync/rcu/mod.rs#L513-L520) queues a callback. Its monitor [collects per-vCPU quiescent-state reports](../../poc/ostd/src/sync/rcu/monitor.rs#L196-L219). The scheduler [reports one only after `might_sleep` has excluded preemption guards and RCU readers](../../poc/ostd/src/task/scheduler/mod.rs#L662-L672). Running callbacks can [sleep or yield](../../poc/ostd/src/sync/rcu/monitor.rs#L54-L57). Those properties do not provide a synchronous permission-revocation barrier inside a cursor's existing preemption guard.

Full Asterinas [clears write permission and shares frame references during fork](../../reference/asterinas/kernel/core/src/vm/vmar/vmar_impls/fork.rs#L99-L106); it [requires writes to be stopped when the final TLB flush completes](../../reference/asterinas/kernel/core/src/vm/vmar/vmar_impls/fork.rs#L57-L63). [`clock_gettime`](../../reference/asterinas/kernel/core/src/syscall/clock_gettime.rs#L29-L32) can concurrently write user memory through [`CurrentUserSpace::write`](../../reference/asterinas/kernel/core/src/context.rs#L237-L245), which takes no VMAR mapping or page lock. The repair must preserve these existing caller semantics.

## Dedicated copy-reader domain

Use one private copy-reader domain per kernelet instance, separate from generic OSTD RCU. Its state consists of a short, non-sleeping membership lock and a preallocated atomic sequence slot for each vCPU. Each slot has a monotonically increasing generation: even means inactive, and odd means one active software-access section. A bounded snapshot ticket records only the active generations found at one membership-lock acquisition. Neither entry, exit, snapshot creation, nor polling allocates memory or runs callbacks.

The membership lock provides the publication handshake between PTE writers and newly entering readers. It is held only for registration, deregistration, and taking a snapshot; it is never held during an alias access, hardware shootdown, or grace-period wait. This deliberately uses a concrete lock ordering rather than assuming that the existing prototype's sequence operations can be copied unchanged into generic PoC RCU. Contention and the additional IRQ-masked interval require measurement before implementation acceptance.

### Software-access section

1. Pin the current vCPU and mask virtual IRQ delivery for this private section. Preserve any caller-owned preemption/IRQ state. Host preemption and physical carrier migration remain possible; neither constitutes copy completion.
2. Acquire the membership lock with acquire semantics. Require the local slot to be inactive and publish its next odd generation using an acquire-release RMW. Release the membership lock with release semantics.
3. Obtain the relevant root under its existing lifetime protection. Perform the entire software walk, permission decision, and alias access inside this same section. No alias pointer may escape it. For user-to-user copies, both translations and the actual copy belong to the same section.
4. Limit a copy or fill section to the next page boundary on either user side; atomics cover one valid atomic access. The body performs only bounded translation and memory access. It takes no page-table, VMAR, VMO, allocator, or backend locks and invokes no kernel-proper callbacks or host services.
5. On success or a failed permission/translation check, acquire the membership lock, publish the next even generation with an acquire-release RMW after all alias accesses, and release the lock. Restore the private IRQ/preemption guards only after deregistration. The assembly access must retain its compiler memory effects.

Virtual IRQ masking prevents an interrupt-side revoker from waiting for a copy it interrupted on the same vCPU. The private helper is non-reentrant: it never invokes another copy helper or a revoker while active. These are explicit implementation requirements, not properties established merely by naming the guard. Generic caller-owned preemption guards do not count as active copy sections.

A failed walk returns fault metadata and completed-byte count. The existing nonblocking per-vCPU fault-slot publication may occur before IRQ restoration when needed to preserve its handoff, but the copy generation must be inactive before calling a fault handler, acquiring a cursor/page lock, allocating a page, waiting for I/O, or retrying. Each retry starts a new section and walks again; it never reuses an alias from the failed attempt. The current [retry wrappers already call the resolver after the low-level access returns](../../poc/ostd/src/mm/io/mod.rs#L334-L393), and the [resolver invokes the kernel-proper handler](../../poc/ostd/src/mm/fault/mod.rs#L100-L105). Normal caller context restrictions on fault resolution still apply.

Use the section for every RAM alias path derived from a user translation: copy in either direction, fill/zero, atomic load, compare-exchange, and subsequent helpers added to the same abstraction. Wrapping only `rep movsb` leaves the permission-check window uncovered. Kernel-only copies do not enter this domain.

### Revocation and its completion point

1. Under the existing cursor/node locks, atomically publish all PTE removals or permission downgrades for the batch. Maintain the existing ordering between PTE publication and the host shootdown. Hold backing references throughout the operation.
2. Complete all relevant hardware TLB invalidations through Linux. A failed/refused shootdown cannot produce a successful completion or release old frames.
3. Pin the synchronizing vCPU, acquire the membership lock, and assert that its copy slot is inactive. Snapshot all odd sequence values, then release the membership lock. This snapshot is the software-access cutoff. It must follow PTE publication and hardware-flush completion in program order.
4. Without holding the membership lock, wait until each recorded slot differs from the recorded odd value, using acquire loads. A changed generation proves that the recorded access has ended. An exit's release ordering covers its completed alias accesses; acquire-release RMWs preserve this ordering if a newer generation has already started. Never wait for new generations absent from the ticket.
5. Mark the batch complete only after this ticket is satisfied. Permit any queued old-frame destruction only after this point and after all other applicable lifetime conditions.

Entry and snapshot use the same lock. A reader registered before the cutoff is either already finished or included in its ticket. A reader registered after the cutoff acquires a lock released after the PTE updates, so its subsequent walk observes those updates or a later valid publication. It cannot retain an old writable alias across the cutoff without being tracked. The generation must not wrap or be reset while tickets can reference it; fail the instance before exhaustion. vCPU identity and membership remain stable for the lifetime of this instance's domain.

Concurrent revokers may take separate bounded tickets; each covers its own published batch. Existing cursor locks continue to order competing changes to the same mapping. A later, independently authorized permission expansion is a new mapping operation, not completion of an old access. The membership lock is not a replacement for the page-table locking protocol.

For the user-root path, `dispatch_tlb_flush` completes both the hardware phase and the copy ticket for every nonempty dispatched batch, even when the frame-release queue is empty. Batch/coalescing decisions do not omit the copy phase. `sync_tlb_flush` may return immediately only when that combined completion has already occurred; it must never discard a pending copy ticket. A snapshot is taken once after all hardware invalidations in that dispatch, rather than once per leaf.

The prototype's backend-unmap paths must enter this same completion helper after their hardware flush, including `protect_next` withdrawal and runtime teardown; an empty flusher queue must not bypass that explicit obligation. Replacement cannot make the old backing reusable before its revocation ticket completes. In the PoC, preserve generic `RcuDrop` deferral after the copy barrier, because other generic RCU readers may still protect frames or page-table objects. The copy domain supplies permission coherence; it does not establish that every other reference has disappeared.

On whole-instance kill, host eviction and final quiescence remain authoritative. A stopped carrier may leave an odd image-side slot forever. The host must not depend on that carrier executing a guard destructor; it may reclaim only through the existing whole-instance quiescence protocol, without reusing this domain for a new instance.

## Locking and progress obligations

- Never invoke the copy barrier from an active copy section. Assert the local slot is inactive before taking the ticket; do not silently skip an active local slot. Pinning during this check makes the assertion meaningful.
- Do not call a global `synchronize_rcu`, wait for an `RcuDrop` callback, or manually report generic RCU quiescence inside a preemption guard. The dedicated copy ticket completes independently of scheduler quiescent states and may be waited for while an unrelated caller-owned preemption guard remains active.
- A revoker may retain existing cursor/node locks only because tracked copy bodies neither acquire nor wait for them. Faulting copies deregister before entering the handler that might require those locks. Audit every participating helper; one lock-taking callback inside a tracked body invalidates this progress argument.
- Reader entry/exit and writer snapshot never wait for a copy while holding the membership lock. Polling can notify the host through the existing non-sleeping spin mechanism outside that lock; it must not schedule an inner task, run callbacks, or wait for virtual IRQ delivery from the tracked reader.
- A host-descheduled carrier remains an active reader until it resumes and deregisters, or the instance is terminated through host eviction. There is no fixed wall-clock completion bound and no timeout that turns incomplete revocation into success.
- Guard destruction publishes completion before restoring virtual IRQs. Ordinary scope exits must deregister, and the instance-fatal path must retain backing until host quiescence. Generic RCU callbacks remain at their established safe execution points.

## Acceptance and regression plan

These are required future checks. Existing logs and sequential fork tests do not validate the repair.

| Check | Required observation |
| --- | --- |
| Registration/publication interleavings | Exercise entry before/after PTE publication, hardware flush, snapshot, and exit; every access accepting old permission is included in the ticket or finishes before the cutoff. New entries after it see the published entry or a later valid entry. |
| Real multithreaded fork | Pause a copy after its writable check using test-only atomic instrumentation; another thread forks. Fork must reach the barrier without returning. An independent controller releases the copy; fork then completes. Further parent writes take COW, and the child's private page remains unchanged. |
| `mprotect` read-only and `PROT_NONE` | Permission revocation cannot return while a previously authorized paused access remains active. Later copies and user atomics obey the new permissions or resolve through the normal fault path. Cover both read and write revocation. |
| Unmap, same-VA replacement, frame reuse | Pause an old access, clear/replace the mapping, and attempt reuse. Old backing remains unavailable until the tracked access ends. Reallocation with a distinct pattern receives no late writes and produces no stale copied bytes from reused backing. |
| Missing page/COW/partial-copy retry | Handler entry, cursor-lock acquisition, allocation, and fault retry always observe an inactive copy slot. A multi-page operation reports exact progress and re-walks each retry; fill and atomic operations satisfy the same condition. |
| Preemption guard and lock context | Complete a permission downgrade with the caller's existing preemption guard and cursor locks held. No wait depends on that vCPU reporting generic RCU quiescence. A faulting remote access leaves its section before blocking on those cursor locks. |
| Continuous new copies and concurrent revokers | A ticket waits only for its captured generations; new copies cannot indefinitely extend it. Coalesced and separate flush batches, overlapping range changes, and empty frame-release queues preserve completion. |
| IRQ, host scheduling, and lifetime | Production guards restore the original IRQ/preemption state. Test host preemption and physical carrier migration while a copy is active, then continued execution and whole-instance kill. Neither host descheduling nor idle bookkeeping falsely completes a copy. |

The pause hook is test-only and must not run kernel callbacks or acquire locks inside a copy section. Its independent controller must not wait for the revoker to return before releasing the paused copy; that would manufacture a test deadlock. Capture barrier-entry, generation, and completion events to establish the tested ordering.

Extend the prototype's existing [`mem-conc` target](../../prototype/Makefile#L793-L799) with the permission-revocation races, then run the applicable `mem-func`, `mem-conc`, `mem-kill`, and `mem-pressure` cases after implementation. They cover the small prototype, not compatibility with the full kernel proper.

Run the full Asterinas image through the Linux PoC runner in both supported [direct and VMA modes](../../poc/linux/runner/run-poc.c#L34-L40), with at least two vCPUs. Add the concurrent syscall-copy cases to the real userspace regression suite alongside the existing [fork mapping test](../../poc/test/initramfs/src/regression/memory/mmap/mmap_and_fork.c#L13-L90) and [private-mapping `mprotect` test](../../poc/test/initramfs/src/regression/memory/mmap/mmap_and_mprotect.c#L32-L56). Also check the registration ordering with a small concurrency model; a model does not substitute for the Linux-host run. Record exact image/module revisions, configuration, mode, host-preemption conditions, and raw failure/pass events. No new make target or already passing regression is assumed here.

Measure copy latency and contended/batched revoke latency after correctness checks, including the short membership lock and per-page virtual-IRQ masking. Performance acceptance must use those results, not the original copy timings or the assumption that hardware-flush time dominates. No timing or progress measurements support this proposed implementation yet.
