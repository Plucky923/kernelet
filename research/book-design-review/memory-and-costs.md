# Accepted Design review: memory and cost rationale

Date: 2026-11-16. Repository HEAD: `a5ec4b875d0a17890321a362fbc3fd16859b7eb4`.

Scope: the design choices and arguments in four Accepted Design chapters. Code and proposals are supporting evidence. This is not a list of implementation bugs, missing tests, or unimplemented features. No code, book text, VM state, or existing research notes were changed. No new experiment was run.

## Chapter coverage

| Chapter | Design obligations examined | Result |
|---|---|---|
| [The kernelet ABI](../../book/src/accepted-design/the-kernelet-abi.md) | Host/image interface, per-object heap calls, grant ownership, fixed capacity, startup | Host-owned backing and private image state have coherent roles. A host heap is a policy choice, not a consequence of host ownership; its sleeping behavior contributes to MEM-02. |
| [Tenant memory on Linux's page tables](../../book/src/accepted-design/tenant-memory-on-linux-page-tables.md) | Linux address-space identity, user-PTE ownership, VMA selection, services, faults | MEM-01: a necessity premise overstates what Linux requires. Keeping Linux's mm/CR3 bookkeeping is separately justified. |
| [What vOSTD adds on top](../../book/src/accepted-design/what-vostd-adds-on-top.md) | Walk/copy safety, frame references, RCU, cursor serialization, withheld mappings, deferred destruction, sleeping contexts | MEM-02: explicit interface-context restriction. MEM-03: creation-progress claim does not follow for all contexts the design permits. The stated frame/TLB/reader release ordering is sound within its assumptions; no new defect found there. |
| [What it costs](../../book/src/accepted-design/what-it-costs.md) | Cost attribution, relation between eager PTE work and first touch, fork workload dependence | MEM-04: the universal fork-benefit conclusion conflates two independent choices and lacks an amortization condition. The chapter correctly distinguishes its scheduler-scale numbers from a fair speedup baseline. |

## MEM-01 — Linux address-space integration does not force per-entry Linux mediation

**Status:** confirmed design-rationale defect; the selected implementation remains a possible tradeoff. **Existing coverage:** the local direct-page-table proposal directly addresses this choice; batching is its explicit alternative.

**Book choice and premise.** [Tenant memory, lines 7–11](../../book/src/accepted-design/tenant-memory-on-linux-page-tables.md#L7-L11) moves every cursor edit to Linux because the carrier uses Linux's address space and vOSTD supposedly cannot write its PTEs or select a different table. The resulting design constructs a full-range VMA and translates each map/protect into a service ([lines 38–40](../../book/src/accepted-design/tenant-memory-on-linux-page-tables.md#L38-L40), [159–205](../../book/src/accepted-design/tenant-memory-on-linux-page-tables.md#L159-L205)).

**Failed implication.** Linux's need to own task/mm association, kernel mappings, CR3/PCID bookkeeping, and host shootdown does not establish that trusted vOSTD cannot own the lower user subtree or write permitted user entries. Those responsibilities can be split. The current architecture already permits a Linux patch and trusted code accessing page-table memory through the direct map; this is not a hardware protection barrier forbidding such writes.

**Concrete alternative.** Retain a Linux `mm_struct` and root lifecycle while delegating lower user-table allocation and updates to vOSTD; alternatively batch Linux-owned edits under one host lock. The [direct-PTE draft, lines 51–84](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L51-L84) specifies the split; [lines 144–164](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L144-L164) state TLB/reader teardown obligations; [255–258](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L255-L258) retain batching as an alternative. This is evidence of an alternative design contract, not a proof that every direct-write obligation has been implemented correctly.

**Consequence.** The supposedly necessary choice introduces per-page host services, VMA policy interactions, the withheld set, and sleeping map operations. These costs cannot be described as inherent in running on Linux's page tables.

**Required design decision.** Decide which boundary performs grant/type validation and which party owns user-PTE policy. Compare direct writes with batched mediation on that common contract. Keep host mm/root/scheduling requirements distinct from PTE-update ownership. The existing draft is the right place for this work; a duplicate proposal is unnecessary.

## MEM-02 — Sleeping host memory operations impose a stronger client contract than OSTD

**Status:** confirmed compatibility restriction with unresolved necessity; not a newly demonstrated memory-safety failure. **Existing coverage:** direct PTE addresses map/protect/unmap; the local heap proposal addresses ordinary Rust allocation. Creation/destruction still need a context contract.

**Book choice.** [The ABI, lines 169–189](../../book/src/accepted-design/the-kernelet-abi.md#L169-L189) routes heap operations to Linux and buffers output to avoid blocking under kernelet locks. [What vOSTD adds, lines 286–299](../../book/src/accepted-design/what-vostd-adds-on-top.md#L286-L299) allows host sleep under a plain preemption guard, forbids sleeping memory services under spin locks or virtual IRQ masking, and explicitly states that a kernel which maps successfully on bare metal can be stopped here. The same text acknowledges that heap calls violate this rule.

**Why this is a design issue.** The interface has the same method names and signatures but a different valid execution-context set. A bare-metal kernel can legitimately map while holding a spin lock or with interrupts disabled; translating that operation to a potentially sleeping Linux helper makes it fail. This is a behavior-contract mismatch, not merely an absent test. At the same time, allowing heap allocation to sleep under those locks shows that the strict map prohibition is not being justified as a universal memory-safety invariant.

**Counterargument and scope.** Keeping virtual interrupts masked while Linux schedules the carrier can delay virtual interrupt delivery without necessarily violating the promise that no handler runs before unmasking. Lock-holder preemption can hurt latency while the host still bounds CPU use and killability. Those facts do not prove that allowing all such sleeps is a good design; they show that the rule needs a precise latency, compatibility, or correctness objective rather than an assumed architectural necessity.

**Required design decision.** Either narrow the supported OSTD contract explicitly, or provide operations whose required contexts match OSTD (for example grant-local allocation and non-sleeping PTE edits). Account separately for remaining Linux-backed `vm_create`/`vm_destroy` work. [Direct-PTE integration, lines 263–271](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L263-L271) and [the local heap proposal, lines 19–27 and 51–68](../../book/src/design-proposals/2026-11-16-allocate-the-kernelet-heap-from-the-grant.md#L19-L68) already address much of this restriction. Neither mere API name matching nor removal of one sleeping service establishes full compatibility.

## MEM-03 — Retirement's claimed creation progress excludes a context creation permits

**Status:** confirmed defect in the design's progress argument; runtime consequences are statically derived, not reproduced. **Existing coverage:** only an open question in the direct-PTE draft; changing PTE ownership alone does not resolve it.

**Original endpoints.** [What vOSTD adds, line 250](../../book/src/accepted-design/what-vostd-adds-on-top.md#L250) allows retire-list draining only with no guard held. [Line 252](../../book/src/accepted-design/what-vostd-adds-on-top.md#L252) then claims that `vm_create` drains so creation is never blocked by retired spaces. Yet [lines 286–295](../../book/src/accepted-design/what-vostd-adds-on-top.md#L286-L295) permit the relevant sleeping service under a plain preemption guard; only spin locks and virtual IRQ masking are prohibited.

**Minimal allowed sequence.** Use one vCPU, enabled virtual interrupts, no held spin lock, and initially available address-space slots. Hold one plain `disable_preempt()` guard. Repeatedly create an empty `VmSpace` and immediately drop it without activating or retaining it. All calls meet the stated R2 conditions. Each drop queues a retired space, while every subsequent creation rejects retirement because the plain guard remains held. No other vCPU can drain it.

**Source confirmation.**

- Public safe [`disable_preempt`](../../prototype/vostd/src/task/preempt/guard.rs#L45) supplies the plain guard.
- [`r2::assert_may_sleep`, lines 253–263](../../prototype/vostd/src/sync/spin.rs#L253-L263) checks spin-lock count and virtual IRQ masking, not the plain guard count.
- [`Backend::new`, lines 57–62](../../prototype/vostd/src/mm/backend.rs#L57-L62) invokes the drain before creating a space, and panics if creation returns a nonpositive ID.
- [`retire::safe`, lines 782–787](../../prototype/vostd/src/mm/vm_space.rs#L782-L787) excludes any nonzero guard count. [`VmSpace::drop`, lines 354–363](../../prototype/vostd/src/mm/vm_space.rs#L354-L363) queues the backend without destroying it.
- [`klet_do_vm_create`, lines 364–374](../../prototype/linux/endovisor/space.c#L364-L374) can reuse only slots with no live space, no mm, and no active users. A retired slot remains occupied until `vm_destroy`. The limit is [64 slots](../../prototype/linux/endovisor/kernelet.h#L66).

After at most 64 such create/drop cycles (fewer if other slots were already occupied), the next creation fails and the wrapper panics, although the caller retains none of those spaces. The point is not that finite quotas can be exhausted: the book specifically claims this collector prevents retired spaces from blocking a new creation, but the collector is ineligible in an allowed creation context.

**Required design decision.** State a sufficient context and progress condition for collection, and ensure resource admission cannot depend on a collector that is forbidden at that admission point. Possible directions include a permitted synchronous drain for guarded creation, an explicit stronger context restriction, or independent bounded retirement processing. Each changes a design contract and has its own compatibility/latency obligations.

**Proposal status.** [The direct-PTE draft, line 287](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L287) asks about additional high-watermark drains at syscall return or IRQ re-enable. Its [runtime teardown, line 164](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L164) still uses retirement, and [line 271](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L271) retains context-sensitive creation/destruction. Thus this obligation is recognized but not closed by the proposed PTE split.

## MEM-04 — The fork rationale lacks a touched-page break-even condition

**Status:** confirmed design-rationale overclaim; it does not establish that lazy population is preferable in all workloads. **Existing coverage:** the direct-PTE proposal attacks per-entry cost, while the exact cost/benefit claim still needs correction in Accepted Design.

**Book argument.** [What it costs, lines 76–84](../../book/src/accepted-design/what-it-costs.md#L76-L84) connects eager PTE presence to avoided first-touch faults, then describes the roughly 10 ms fork as the price paid for those savings. It concludes that only a fork which never touches the memory loses and all other workloads gain.

**Counterexample.** Fork a large address space and touch only one or a few pages before exit or exec. This is not the excluded no-touch case. Eager work still processes all mapped pages, while the number of first-touch faults potentially avoided is small. Nothing in the supplied measurements shows that this small saving repays the whole-address-space cost. The conclusion requires a workload-dependent inequality: eager work over all mapped pages must be smaller than the deferred work/fault cost over pages actually used, with common costs treated alike.

**Independent choices.** Keeping child PTEs present and paying one host service per PTE are separate decisions. Batched host edits or trusted direct edits can preserve eager presence without that service count. Linux v6.12's [copy-page-table code](https://github.com/torvalds/linux/blob/v6.12/mm/memory.c#L1080-L1200), also available [locally](../../reference/linux-6.12/mm/memory.c#L1080-L1200), processes a range while retaining page-table lock state; it is not evidence that every eager fork needs this prototype's crossing count.

**Required design decision.** Separate eager/deferred population policy from update-mediation policy. Use touched-page fraction, process lifetime, fault count, and per-update batching to decide the tradeoff; do not use the current universal payoff claim to make per-page host mediation appear necessary. The original repeated-frame workload is disclosed clearly in the book, so its existence alone is not a hidden benchmark or an additional design defect.

## Candidates not promoted to design defects

- The direct-map software copy does not yet call the full kernel proper's demand-fault handler, but [what-vostd, lines 63–65](../../book/src/accepted-design/what-vostd-adds-on-top.md#L63-L65) explicitly identifies the missing behavior and says where it must run. Missing implementation alone is not a new architectural defect.
- Withheld mappings are a coherent adaptation to the selected full-range Linux VMA. Their overhead is derivative of MEM-01, not an independent impossibility or isolation flaw.
- Lockless PTE loads are justified by the stated no-pruning/held-mm invariants, and user-frame reuse is separately delayed until TLB and software-reader conditions hold. No new counterexample was found within those assumptions.
- A fixed 2/4 MiB physically contiguous grant is restrictive, but the book labels it a prototype restriction, and existing returnable-grant work addresses different capacity policy. Size alone is not evidence of an invalid design.
- `memory_max` does not cover every host allocation, but the book documents separate cgroup accounting. A host-wide resource-isolation argument needs an explicit policy; it would be wrong to infer that the book promises this field alone is a total-footprint cap.
- The heap's host block ledger supports cleanup without Rust destructors. Host ownership does not make per-object host allocation necessary, but a grant-local heap is not itself proof of stronger fault isolation.
- ABI line 78's discussion of protection against a buggy vOSTD should not be generalized: a fixed number of output pointers does not validate their addresses. Because vOSTD is trusted in the book's main model, this is a bounded defense-in-depth claim to clarify, not an additional demonstrated safe-kernel-proper escape.

## Evidence boundary

All four assigned chapters were read in full. Supporting paths were inspected only to test the design arguments and the retirement sequence. The findings do not claim a new timing result, a dynamically reproduced failure, complete Linux/OSTD soundness, or a full prose/style review. No temporary files were created. The note is intentionally a local research deliverable under the existing ignored `research/` directory.

## Architecture-only reassessment

### Permission revocation must include software translations

**Status:** a concrete design-contract gap in software user access; static counterexample, not a runtime reproduction. It can be addressed inside vOSTD's existing translation/coherence responsibility, so it does not establish that another cross-layer architecture proposal is necessary.

**Selected mechanism.** [The book, lines 59–65](../../book/src/accepted-design/what-vostd-adds-on-top.md#L59-L65) replaces hardware user-VA access with a software walk and direct-map access. Its [copy algorithm, lines 79–96](../../book/src/accepted-design/what-vostd-adds-on-top.md#L79-L96) checks writable permission before copying; its [grace-period rule, lines 155–161](../../book/src/accepted-design/what-vostd-adds-on-top.md#L155-L161) waits for software readers before freeing unmapped frames. The distinction matters because a valid direct-map pointer remains writable after the user PTE loses write permission.

**A legal concurrent caller.** Full Asterinas's [`sys_clock_gettime`, lines 29–32](../../reference/asterinas/kernel/core/src/syscall/clock_gettime.rs#L29-L32) obtains the result before copying it into user memory. [`Context::user_space`, lines 35–36](../../reference/asterinas/kernel/core/src/context.rs#L35-L36) borrows the current thread's VMAR handle; [`CurrentUserSpace::write`, lines 237–245](../../reference/asterinas/kernel/core/src/context.rs#L237-L245) creates a writer and copies without holding the VMAR mapping lock, a VMO lock, or a page lock. Another thread may enter [`clone_child_process`, lines 503–506](../../reference/asterinas/kernel/core/src/process/clone.rs#L503-L506), and [`clone_vmar`, lines 672–678](../../reference/asterinas/kernel/core/src/process/clone.rs#L672-L678) invokes `Vmar::fork_from` when `CLONE_VM` is absent. A thread-local borrow does not serialize these two threads.

**Minimal trace.** Start with private anonymous page `P` mapped writable in the parent, with a pending `clock_gettime` result destined for `P`.

1. On vCPU A, a software writer reads the writable PTE and obtains the direct-map pointer to frame `F`. Host preemption pauses its carrier before the store. Holding a virtual preemption guard does not prevent this host preemption; the book explicitly allows [descheduled readers](../../book/src/accepted-design/what-vostd-adds-on-top.md#L159-L161).
2. On vCPU B, `fork` clones `F`'s reference, clears the parent's writable bit, and maps `F` read-only in the child: [`cow_copy_pt`, lines 99–106](../../reference/asterinas/kernel/core/src/vm/vmar/vmar_impls/fork.rs#L99-L106).
3. `fork` synchronizes the final TLB flush. Its [documented invariant, lines 57–63](../../reference/asterinas/kernel/core/src/vm/vmar/vmar_impls/fork.rs#L57-L63), requires that no writes can reach these shared COW frames after `fork` returns. A hardware TLB flush cannot invalidate A's ordinary kernel direct-map pointer.
4. The child can read `F`; A subsequently resumes and stores into `F` without a COW fault. The child can then observe its supposedly private inherited memory change. No kernel-proper unsafe code, frame reuse, or unmapped-page access is required.

**Why native OSTD differs.** Its [`VmSpace::writer`, lines 177–189](../../reference/asterinas/ostd/src/mm/vm_space.rs#L177-L189), constructs a user-VA writer after checking the active page table; it does not perform this software translation. [`Memcpy<Infallible> for Fallible`, lines 192–199](../../reference/asterinas/ostd/src/mm/io/copy.rs#L192-L199), invokes the fallible assembly copy through that user address. After write-protection and TLB coherence, resumed stores fault and enter the kernel proper's COW path. The software path must supply the equivalent revocation property itself.

**Existing proposal status.** The direct-PTE proposal preserves [software-copy readers at teardown](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L164) and delegates [hardware shootdowns to Linux](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L146-L149). It does not specify a software-reader barrier on permission downgrades. The local Linux PoC retains the [walk/check followed by alias store](../../poc/ostd/src/mm/io/copy.rs#L171-L221); its [user-root flush, lines 109–128](../../poc/ostd/src/mm/tlb.rs#L109-L128), performs the host shootdown, while [`sync_tlb_flush`, lines 199–204](../../poc/ostd/src/mm/tlb.rs#L199-L204), can return without waiting for software copies. [Deferred frame retirement, lines 462–467](../../poc/ostd/src/mm/tlb.rs#L462-L467), occurs only with frames to retire and does not synchronously revoke a writable translation. Local grant allocation and returnable grants do not change this condition.

**Design remedy and scope.** The permission-revocation completion point must cover hardware translations and software accesses that already accepted the old permission. A viable candidate is: publish the non-writable PTE, perform the hardware shootdown, and wait for pre-existing software-copy sections before the revocation is considered complete. New software writers must observe the non-writable PTE, leave their read section, and resolve COW outside it. Because the existing reader protocol is already designed around this publication/grace-period ordering for `unmap`, a stronger flusher completion contract may suffice; no independent writable-lease subsystem or change to Linux ownership has been shown necessary. Lock context, ordering, and fault-retry progress still require review before selecting that repair.

### Other candidates excluded at this threshold

- **Accessed/dirty-bit effects.** Software aliases do not automatically set the user PTE's hardware A/D bits, but the inspected full kernel proper marks shared cache pages dirty through the [VMO mapping-mode protocol](../../reference/asterinas/kernel/core/src/vm/page_cache/vmo/mod.rs#L325-L347) and [shared write-fault handling](../../reference/asterinas/kernel/core/src/vm/vmar/vm_mapping.rs#L493-L507). No data-loss counterexample based only on omitted PTE A/D updates was established. Emulating those bits would remain a vOSTD implementation obligation.
- **Demand faults and call contexts.** The book explicitly requires [fault-handler calls outside software read sections](../../book/src/accepted-design/what-vostd-adds-on-top.md#L63-L65). Direct PTE allocation and a grant-local heap address the previously identified host-sleep mismatch on common page-table/object paths. The remaining context-sensitive lifecycle services do not by themselves prove that the full kernel proper needs architectural changes.
- **Cost and grant policy.** The earlier fork payoff claim, fixed-grant capacity, and guarded retirement policy are not additional architecture findings in this pass. None supplies a new necessity argument for changing the responsibilities already addressed by the existing proposals.
