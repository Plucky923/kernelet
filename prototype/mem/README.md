# mem: tenant memory, tested and measured

A kernel proper that exercises vOSTD's `VmSpace`, which is a Linux address
space: the endovisor writes its page table through the `vm_*` services and
vOSTD reads it through the direct map. Where it does what Asterinas's own
kernel does, it does it the same way: fault-around maps a 64 KiB window under
one cursor, fork is the tree's `cow_copy_pt`, a protection change is a
`protect_next` loop followed by one flush. What it reads beyond the OSTD API
comes from `ostd::klet`: counter deltas around each test (Linux faults counted
in the area's fault handler, service calls, range-lock waits, grace periods)
and the one test hook, which makes `vm_map` sleep in the host.

The tests go by E-numbers in the code and the logs:

| mode | test | what it checks |
|---|---|---|
| `func` | `make mem-func` | E2: pages mapped by `vm_map` take no Linux fault; one tenant fault maps a sixteen-page fault-around window. E3: a protection change keeps the entries present; a write to a read-only page is one `pfn_mkwrite` report. E4: a map under a preemption guard is legal because the service prologue lifts the mirror, and nothing switches. E10: `PROT_NONE` and back through the withheld set, contents intact |
| `r2` | `make mem-r2` | E5: a sleeping service called under a kernelet spin lock ends the kernelet by vOSTD's own assertion, and Linux reports nothing |
| `conc` | `make mem-conc` | E8: lockless copies on one vCPU against map/unmap loops on the other see no torn page and no foreign frame; a second cursor waits in `vm_wait` for one whose holder sleeps in `vm_map`. E11: a process exits under a copy into its memory, no frame is freed before the grace period, and the space is retired with interrupts off and drained later |
| `kill` | `make mem-kill` | E11: vCPU 1's carrier of a two-thread process is preempted by a competitor on its processor, sent `SIGTERM` and `SIGUSR1` (ignored: it lives), stopped and continued (`SIGSTOP`, `SIGCONT`), then killed from outside while vCPU 0's thread faults in the same address space; the kill ends the whole sandbox cleanly. Meanwhile vCPU 1's tenant runs the rewind check: it counts in a register and in memory together, with a system call between batches, and a return to user mode that put back an earlier system call's registers would part the two |
| `killidle`, `killspin` | `make mem-kill` (its second and third boots) | vCPU 1's carrier killed with `SIGKILL` where Linux would not act on it by itself, because it is not on its way to user mode: asleep in `vcpu_idle` with nothing to run (`killidle`; the service path notices the kill), and running a kernel task that loops in kernelet code and calls no service (`killspin`; the watch timer notices). Each kill must end the sandbox within two seconds, long before vCPU 0's tenant would have finished |
| `pressure` | `make mem-pressure` | E7: every entry survives Linux's reclaim while the guest swaps |
| `perf` | `make mem-perf` (measurement) | E6: first touch, map, protect, read after protect, copies. E9: fork of 64 MiB, the child's reads, the parent's re-reads, munmap |

The book explains the services, the area, faults and adoption in chapter 12,
the walk, copies, frame references, the range lock, the withheld set, the
retire list and the sleeping contract in chapter 13, and the numbers in
chapter 14.

## Files

| file | what it is |
|---|---|
| `src/lib.rs` | the kernel proper: a pinned FIFO scheduler, the tenant driver, and every scenario |
| `mem.S` | the tenant program: a command loop (touch, write, check, spin, read one, write one, and count, the rewind check's count kept in a register and in memory), timed per page with `rdtsc` |
| `Cargo.toml` | the crate |
