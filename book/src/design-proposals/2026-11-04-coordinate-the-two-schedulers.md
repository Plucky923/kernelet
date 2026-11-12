# 2026-11-04 Coordinate the two schedulers

- Status: Draft
- Author(s): Plucky923
- Discussion: Not yet available.
- Affected chapters: [Tasks and virtual CPUs](../accepted-design/tasks-and-virtual-cpus.md), [Sharing a processor politely](../accepted-design/sharing-a-processor-politely.md), [Virtual interrupts](../accepted-design/virtual-interrupts.md), and [What it costs](../accepted-design/what-it-costs.md).
- Implementation or experiments: Not yet implemented.

## Summary

Linux schedules the carriers that provide a sandbox's virtual CPUs, while the kernelet schedules its own tasks on those virtual CPUs. This proposal coordinates their decisions through direct access to Linux's scheduling state, retaining the existing mirror and watch timer. The additional host load and location accessors and the task-placement policy remain to be specified and implemented. Their performance benefits remain unmeasured.

## Problem and motivation

In the [accepted design](../accepted-design/tasks-and-virtual-cpus.md#two-levels), each virtual CPU has one carrier for the sandbox's lifetime. Linux schedules carriers on physical CPUs. The kernelet schedules tasks on virtual CPUs. Without coordination, each scheduler may lack the other's runtime information.

### 1. Guest scheduling without host runtime information

The kernelet scheduler may make poor task-placement decisions without current information about host CPU load and its carriers' physical cache locality.

<div class="background">

**Virtualization: runtime hypervisor-internal states.** [CPS (§2.2, ASPLOS ’23)](https://doi.org/10.1145/3623278.3624762) reports that guest kernels can make poor task-placement decisions without current information about **Runtime Hypervisor-internal States (RHS)**. The hypervisor maintains these states, including physical CPU load and the current mapping of virtual CPUs to physical cache groups. In the manycore system studied by CPS, a **cache group (CG)** contains physical cores that share a partition of the last-level cache.

</div>

CPS identifies two RHS problems:

1. **Invisible physical CPU load.** In CPS's example, KVM [records each virtual CPU's preemption status in shared memory](https://mailweb.openeuler.org/archives/list/virt@openeuler.org/thread/4VC42ELMHATLJM3J5VFIHIJTE6FRH7K3/). A running virtual CPU can read the status of another virtual CPU that the host has preempted. This status does not reveal physical CPU load. In the low-load case, the guest avoids all preempted virtual CPUs when placing new or awakened tasks. This excludes virtual CPUs that could soon resume on physical CPUs with low load, leaving available capacity underused.
2. **Invisible dynamic cache-group mapping.** A guest may place communicating threads on virtual CPUs mapped to the same physical cache group. The host can then move one virtual CPU to a physical CPU in another group. Without an updated mapping, the guest cannot account for this loss of locality when placing tasks. In CPS's experiment, four threads incremented one shared atomic variable. Among the placements tested, throughput was highest when all four threads ran in one cache group ([§2.2, Table 1](https://doi.org/10.1145/3623278.3624762)).

### 2. Host preemption without guest execution information

The kernelet selects the task that runs on each virtual CPU. Linux decides when that virtual CPU's carrier runs on a physical CPU. Without coordination, Linux does not know which kernelet tasks hold locks or which tasks depend on those lock holders. When ordinary kernel preemption is permitted, Linux may deschedule a carrier while its current kernelet task is in a critical section.

Suppose task A on virtual CPU 0 holds a spin lock that task B on virtual CPU 1 needs. Linux may deschedule A's carrier while B's carrier continues to run. A then cannot release the lock, while B may keep spinning and consuming processor time. A remains the current task on its virtual CPU, but cannot resume until Linux schedules its carrier again. This is the **lock-holder preemption** problem studied in VMs ([eCS, §2.1, USENIX ATC ’18](https://files.usenix.org/s3fs-public/cdn/atc18-kashyap.pdf#page=3)).

<div class="background">

**Virtualization: scheduling interfaces.** [CPS (§4.1)](https://doi.org/10.1145/3623278.3624762) publishes physical CPU load and cache-group mappings in shared memory to guide guest task placement. [eCS (§3)](https://files.usenix.org/s3fs-public/cdn/atc18-kashyap.pdf#page=5) lets the guest mark critical sections in shared memory so the hypervisor can delay virtual CPU preemption. Both avoid a hypercall per access, but must maintain shared state and extend the interface to expose additional host information.

</div>

## Proposed change

Linux schedules carriers, and the kernelet schedules tasks on their virtual CPUs. The proposal coordinates these decisions through direct access to Linux's per-CPU state.

### Shared access through GS

<div class="background">

**Linux and x86-64: per-CPU state and GS.** Linux keeps a separate area of per-CPU data for each physical CPU. During kernel-mode execution, each CPU's GS base identifies its own area, allowing code to access the current CPU's local state.

</div>

Linux passes kernel events to vOSTD within the carrier's host kernel context. The design keeps the host kernel mappings and the current physical CPU's GS base across Linux, endovisor, and kernelet kernel execution. This lets vOSTD read and update selected host per-CPU fields without a host service call. Each access must follow Linux's rules for that field, including synchronization.

### Task placement and carrier preemption

1. **Host state guides kernelet scheduling.** Extend vOSTD to expose host CPU load and carrier cache-group mappings to the kernelet scheduler. For each runnable task, the scheduler can compare candidate virtual CPUs by host contention and cache locality with communicating tasks. GS selects the current physical CPU's per-CPU area. vOSTD must associate each observation with its carrier and host CPU and account for migration.
2. **Kernelet state guides host preemption.** Retain the existing mirror. On entry to the outermost virtual critical section, vOSTD increments Linux's per-CPU preemption count through GS. Linux's existing checks then defer ordinary carrier preemption while kernelet code executes inside the section. On exit, vOSTD removes the increment, checks for a host rescheduling request, and yields if needed.

The watch timer remains a fallback when the kernelet delays responding to a host rescheduling request. During a forced yield from a virtual critical section, the endovisor temporarily removes the mirrored increment so that Linux can schedule. It restores the increment before resuming kernelet execution, with the virtual critical section still active. Host-service calls retain their existing blocking and yielding behavior. Coordination of sleeping and waking remains deferred.

### Advantages

A conventional x86-64 VM uses its own [kernel mappings and GS base](https://www.intel.it/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-3c-part-3-manual.pdf#page=10). Its kernel therefore needs an explicit interface to access host scheduling state. [CPS (§4.1)](https://doi.org/10.1145/3623278.3624762) provides a shared Refer-Table that the guest can read without additional hypercalls after initialization. Direct access to Linux's original state offers three advantages:

1. **New scheduling inputs without shared copies.** When a new scheduling problem needs host information not yet exposed, [CPS (§4.1)](https://doi.org/10.1145/3623278.3624762) must extend its Refer-Table and maintain the added state. Our design resolves each CPU's per-CPU area offset and the required field offsets once during Linux startup. vOSTD then reads live values directly from host per-CPU fields with known layouts, following Linux's access rules. GS selects the current CPU's area, while recorded CPU offsets locate other CPUs' areas. Adding a scheduling input therefore requires no new shared copy or code to keep that copy current.

    <div class="background">

    **Hardware: NUMA nodes.** A non-uniform memory access (NUMA) system groups CPUs and memory into nodes. Memory access costs depend on the CPU and memory nodes.

    </div>

    Examples of host fields that can guide kernelet scheduling include:

    - **NUMA node.** Linux's per-CPU [`numa_node`](https://github.com/torvalds/linux/blob/v6.12/include/linux/topology.h#L82) identifies the CPU's NUMA node. The kernelet can use it to consider memory locality when placing tasks.
    - **Shared cache.** Linux's per-CPU [`sd_llc_id`](https://github.com/torvalds/linux/blob/v6.12/kernel/sched/topology.c#L666) identifies the CPU's last-level-cache domain. Comparing these IDs can guide the placement of communicating tasks on CPUs that share a cache.
    - **CPU load and capacity.** Each CPU's [runqueue](https://github.com/torvalds/linux/blob/v6.12/kernel/sched/sched.h#L1096) contains `nr_running` and `cpu_capacity`. These fields expose the runnable-task count and Linux's CPU capacity estimate for task-placement decisions.

2. **Use of existing host controls.** The mirror changes the count Linux already checks before preemption. This lets Linux defer ordinary preemption without interpreting a separate guest critical-section flag.
3. **Potentially lower overhead.**

    - **State publication.** [CPS (§4.1)](https://doi.org/10.1145/3623278.3624762) publishes each physical CPU's load degree in a shared page. When the kernelet uses existing host per-CPU fields, vOSTD can read them without maintaining a separate shared representation.
    - **Migration updates.** When a vCPU migrates, [CPS (§5.1)](https://doi.org/10.1145/3623278.3624762) changes the guest mapping to refer to the new physical CPU's load page. After a carrier migrates, a GS-relative read uses the new CPU's host state without this extra mapping update.
    - **Expected read savings.** In [CPS (§5.1)](https://doi.org/10.1145/3623278.3624762), the guest reads a load value through a pointer stored in the shared table. For an existing scalar on the current CPU, a [fixed-offset GS read](https://docs.kernel.org/core-api/this_cpu_ops.html#inner-working-of-this-cpu-operations) can access the host field directly. If a query must reload the shared pointer, GS can reduce the pointer and value reads from two dependent loads to one. We expect lower query latency, especially when the table entry misses in cache and delays the value read. Keeping the shared address in a register or fetching the GS offset from memory can remove this advantage.
