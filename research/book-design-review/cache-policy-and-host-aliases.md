# Cache-policy authority for grant-backed mappings

Date: 2026-11-16. Scope: cache-policy authority in the direct-page-table proposal, the Accepted Design, and the local Linux PoC. No cache-type experiment or implementation change was performed.

## Finding and boundary

The [direct-PTE proposal](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L140) specifies how vOSTD encodes `CachePolicy` using Linux's PAT slots. Correct encoding does not by itself establish that the requested cache type is compatible with every other mapping of the same physical page. Linux owns the existing direct map and the host's memory-type coordination.

This is a missing cache-policy contract in the proposed extension, not a demonstrated failure of the Accepted Design's supported write-back mappings. The tracked prototype explicitly rejects non-write-back tenant mappings. The evidence does not establish a need to replace the overall Linux/vOSTD architecture.

## Sources and existing behavior

| Source | Relevant behavior |
|---|---|
| [Grant allocation](../../prototype/linux/endovisor/sandbox.c#L471-L480) | The host allocates ordinary RAM and publishes its physical address plus the Linux direct-map base. |
| [vOSTD address conversion](../../prototype/vostd/src/mm/mod.rs#L89-L90) | `paddr_to_vaddr` accesses the host's direct-map alias of a physical page. |
| [Accepted prototype's `prot_bits`](../../prototype/vostd/src/mm/vm_space.rs#L204-L208) | Tenant mappings must use `CachePolicy::Writeback`; another policy causes an instance-local assertion. |
| [OSTD `PageProperty`](../../reference/asterinas/ostd/src/mm/page_prop.rs#L10-L25) | The safe constructor accepts a caller-selected `CachePolicy`. The enum includes UC, WC, WP, WT, and WB. |
| [Direct-PTE proposal](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md#L118-L142) | vOSTD directly implements map/protect operations and uses Linux's PAT encodings. No protocol for changing host aliases or coordinating physical memory types is specified there. |
| [Local PoC map](../../poc/ostd/src/mm/vm_space.rs#L504-L510) and [protect](../../poc/ostd/src/mm/vm_space.rs#L754-L811) | The direct mode forwards caller properties into the page-table implementation. The old write-back-only assertion is not present on these paths. |
| [Local PoC PTE construction](../../poc/ostd/src/arch/x86/mm/mod.rs#L303-L317) and [PAT encoding](../../poc/ostd/src/arch/x86/mm/pat.rs#L68-L92) | Non-WB policies have PTE encodings; encoding selects a PAT slot without changing the host direct-map mapping. |

Linux 6.12's [PAT documentation](../../reference/linux-6.12/Documentation/arch/x86/pat.rst), under “PAT APIs” and “Advanced APIs for drivers,” describes physical-range memory-type coordination. For a RAM range exported with a non-default type, it requires the appropriate `set_memory_*` operation and restoration to WB before returning the pages to the allocator. The corresponding [official online documentation](https://docs.kernel.org/arch/x86/pat.html#advanced-apis-for-drivers) states the same requirement. This is stronger than selecting the intended PAT index in one new PTE.

## Concrete design case

Consider a normal WB RAM grant and a page `F` within it:

1. Linux retains a WB direct-map alias of `F`, which vOSTD uses for memory access.
2. Safe kernel-proper code requests a user mapping of `F` with `CachePolicy::WriteCombining`, or changes an existing mapping to that policy.
3. vOSTD writes the correct WC encoding into the user PTE. It leaves Linux's direct-map alias unchanged and follows no host memory-type transition protocol.

The result has different cache types requested through two aliases of the same physical page. Correct PAT-slot numbering has not established the legality of that combination. The same issue arises when changing a live page's cache policy: hardware TLB coherence and completion of software copies do not alone establish the required cache-type transition.

This trace identifies an unhandled precondition in the proposal. It does not predict a particular processor failure, prove host-memory corruption, or claim that every combination of different cache types has identical behavior. Those stronger claims would need architecture-specific analysis and experiments.

## Responsibility to specify

The mapping contract must tie the requested `CachePolicy` to the resource's host-approved memory type and all aliases that remain accessible. A local PTE edit cannot independently redefine that physical-page property while Linux retains other mappings.

The ordinary-grant WB contract already has an enforcement point in the Accepted prototype. Any extension admitting additional cache types must state how the host authorizes the physical-range type, coordinates aliases and existing accesses, performs necessary cache/TLB maintenance, and restores the type before backing is reused. Device/MMIO memory needs its own resource contract rather than inheriting ordinary-grant assumptions.

This note does not select a reduced API contract as a substitute for a stated device or cache-policy requirement. It records the distinction between encoding a permitted policy and establishing that the policy is permitted for the backing resource. The software-copy repair is recorded separately in [Software-copy permission revocation](software-copy-permission-revocation.md); that repair is not a cache-type transition protocol.

## Evidence limits

The finding is based on the cited proposal, exported safe APIs, code paths, and Linux's documented RAM-mapping requirements. No hardware aliasing failure was reproduced. The local PoC is a separate, modified implementation, so its broader policy acceptance is not attributed to the tracked Accepted prototype. Book and implementation files were not edited.
