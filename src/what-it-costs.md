# What it costs

Every mechanism in this book has a price, and this chapter gives the handful of numbers that say whether the design is worth it. All of them were measured on the companion prototype, built from this repository, by `make bench` and `make hello`, except one figure from an earlier build, named where it appears. The numbers depend on the machine, so run `make bench` yourself and compare.

**Measured on:** the prototype at the commit this book was built from, in a Linux 6.12 guest under QEMU with KVM, two processors and 512 MiB, on a host with an Intel Xeon E3-1270 v6 processor whose cycle counter runs at 3.79 GHz, so one cycle is 0.26 ns. The host was shared with other work, which shows in the worst cases. Unless a row says otherwise, a figure is the median over five boots of each boot's own median over its samples; the last column is the worst 99th percentile any boot reported.

## The crossing

The endovisor's stub times the crossing, an indirect function call plus two stack switches (chapter 7), at every sandbox's start. It times it with interrupts off, in seven rounds of 2,000 calls of a service that does nothing, and keeps the cheapest round, since the machine beneath the guest can take the processor away in the middle of one; the line is in every `make hello` log, and these three rows are from the one boot quoted in chapter 8.

| | cycles |
|---|---|
| the service body alone, called directly | 24 |
| the same through the service stub, both stack switches included | 36 |
| a 64-byte heap allocation and its free, `mem_alloc` and `mem_free` together | 449 |

So the stack switches cost about ten cycles a call, a few nanoseconds; the two figures move by several cycles from boot to boot, and their difference with them.

The heap pair is two crossings, Linux's `kmalloc` and `kfree`, and the endovisor's table of blocks (chapter 4). It is timed by vOSTD with interrupts on in seven rounds of 1,000 pairs, the cheapest kept. The table costs about a hundred and twenty of those cycles: on an earlier build without the table (`prototype/.build/r5-before-serial-hello2.log`), the pair took 328.

## Tasks

Measured by the scheduler test kernel on its two virtual CPUs (`make sched-perf`), with the sandbox in a control group of its own.

| | median | worst 99th percentile |
|---|---|---|
| two kernelet tasks yielding to each other on one virtual CPU, one round trip | 3,600 cycles (949 ns) | 5,392 |
| a blocked high-priority task woken by a lower-priority one on the same virtual CPU, until it runs | 2,250 cycles (593 ns) | 4,510 |
| the same, woken from the other virtual CPU: `vcpu_kick`, the kick's interrupt and the upcall (chapter 10) | 5,404 cycles (1.42 µs) | 72,852 |
| two tenant threads of two processes alternating on one virtual CPU through a yield system call, one round trip | 13,230 cycles (3.49 µs) | 40,184 |
| for scale: two Linux processes on one processor calling `sched_yield()`, one round trip | 5,016 cycles (1.32 µs) | 9,418 |
| for scale: a Linux process woken through a pipe by one on the other processor | 41,208 cycles (10.9 µs) | 110,156 |

A kernelet task switch, the scheduler's decision included, is therefore under 2,000 cycles; the boots' own medians for the round trip ranged from 2,254 to 3,788 cycles, and the Linux rows moved as much, since the host was shared.

The Linux `sched_yield` row is a scale for it, not a baseline: the Linux pair makes two system calls and changes address space, and the kernelet pair does neither, so the kernelet round trip is an upper bound on what the kernelet's own scheduler costs and not a speed-up.

The tenant-thread row is the honest comparison with it: both are a user thread entering the kernel and another user thread, in another address space, leaving it, timed from the same point in user mode, and the kernelet's costs between two and three times as much. The difference is what each thread pays per trip: the two hooks, in and out, the kernelet's own switch, the adoption of the other address space through `kernelet_switch_mm` (chapter 13), and the kernel proper's save and load of the floating-point registers (chapter 9).

The wake-up across virtual CPUs takes about a microsecond and a half when the kick's interrupt finds the other carrier running kernelet code, of which roughly half a microsecond is the reschedule window of chapter 10 (measured on an earlier build by taking the window's note away: the median fell to about 3,500 cycles): the kick usually lands after the woken virtual CPU has already picked the task, and the note it leaves costs one reschedule that finds nothing to do. Its tail is the widest of any row relative to its median, because the kick may instead find that carrier asleep in `vcpu_idle`, where waking it is a Linux wake-up with Linux's own latency (chapter 9).

## Fairness

The sandbox's control group and a sibling group with equal weight, both confined to the same two processors; the sibling runs busy loops for ten seconds (`make sched-fair`).

| the sandbox runs | the sibling's share, in processors | runnable tasks of the sandbox that Linux saw at once |
|---|---|---|
| 1 task | 0.994 | 2 |
| 50 tasks | 0.995 | 2 |
| 50 tasks and one that holds a guard for 10 ms at a time | 0.884 in the bench run; 0.986 and 0.990 in two reruns (`sched-fair50o-retry1.log`, `-retry2.log`) | 2 |

Linux never saw more than two of the sandbox's tasks runnable at once, its two carriers, whether the kernelet ran one task or fifty: that is the two-level argument of chapter 9, and the reason chapter 11's fairness holds.

One run of the third row fell short, for a reason never found. In the bench run of that row, and in two runs on earlier builds, the sibling got less than nine tenths of a processor; the two reruns of the row are given beside it, and the claim rests on no more than that. The one thing the test measures about interference, the time the sandbox's carriers spent descheduled by the guest's own Linux while running kernelet code, which it reports as *stolen*, was no higher in the odd run of this build than in the passing ones, and the test does not read how long the host kept the whole guest off a processor. A measurement of fairness on a shared host means little, so the test is in `make bench`, which reports and does not fail.

## Memory

Measured by the memory test kernel (`make mem-perf`), with a tenant program that times each access with the cycle counter.

| | median | worst 99th percentile |
|---|---|---|
| first touch of a page the kernel mapped ahead | 82 cycles (22 ns), 0 faults | 310 |
| `map`, one page per call | 780 cycles (206 ns) | 1,324 |
| `map` of 512 pages under one cursor, per page | 817 cycles (215 ns) | 1,595 |
| protect 2 MiB read-only, with its flush | 422,516 cycles (111 µs) | 648,652 |
| a read of each page after that protect | 80 cycles (21 ns), 0 faults | 298 |
| copy 64 bytes out of tenant memory | 184 cycles (49 ns) | 270 |
| copy 4 KiB out of tenant memory | 406 cycles (107 ns) | 2,392 |
| the kernel proper's `fork` of a process with 64 MiB mapped (16,384 pages over 256 frames, each mapped 64 times): a protect of the parent, a map into the child | 38.7 M cycles (10.2 ms) | 45.0 M |
| the child's first read pass over the 64 MiB of mappings | 2.0 M cycles (0.52 ms), 0 faults | 2.1 M |
| the parent's re-read of the 64 MiB of mappings after the fork | 1.9 M cycles (0.51 ms), 0 faults | 2.0 M |
| the kernel proper's unmap of the 64 MiB, under one cursor | 1.8 M cycles (0.48 ms) | 2.5 M |

What the rows say, one at a time.

**A page the kernel mapped costs nothing at its first touch.** The entry is in Linux's page table from the moment `vm_map` returns, so the tenant's first access is a TLB miss and a hardware walk, 82 cycles, with no fault. That is a container's cost, and it is the design's whole reason: any scheme that let Linux's page table be filled lazily, on demand, would pay a fault, many times the cost of a walk, at the first touch of every page.

**A `map` costs a crossing.** 780 cycles is one service call: the stub, the address-space lock, the grant check, and Linux's insert. A kernel that maps 512 pages under one cursor pays it 512 times. That is the price of letting trusted code check every frame, paid once per page, where the first-touch saving is collected once per page too.

**A protect costs a crossing per page and saves a refault per page.** 2 MiB read-only is 512 `vm_protect` calls and one flush, about 111 µs; the reads afterwards take 80 cycles and no fault, because the entries were rewritten in place and never removed.

**Copies cost a walk.** 184 cycles for 64 bytes is the software walk of chapter 14 plus the copy; a direct copy on a machine would be a fraction of that. For 4 KiB the walk disappears into the copy.

**`fork` is the trade-off.** The `fork` and unmap rows are the test kernel doing what Asterinas's full kernel proper does for those system calls, not Linux's. A `fork` of a process with 64 MiB mapped costs two crossings per page, a protect of the parent and a map into the child, and takes 10 ms. In exchange, neither the child's first read pass over the memory nor the parent's re-read takes a single fault: half a millisecond each, which is the cost of the TLB misses and walks alone, since the grant is small and the 64 MiB are 256 frames mapped over and over, so the data never leaves the cache. (A write to a shared page after the fork still faults, as copy-on-write requires.) A design that made the fork cheap by deferring the work to faults would pay it back, with interest, the first time either process touched its memory. A kernel that forks and never touches the memory, as a shell does before `exec`, loses by it; everything else gains.

<div class="recap">

**Recap.** The stack switches of a crossing cost a few nanoseconds; a memory service, with Linux's lock and its work, costs several hundred cycles. A kernelet task switch costs under two thousand cycles and never involves Linux. A sandbox's share of the processors does not depend on what its kernel does, in all but one unexplained run of this build and two of earlier ones. A page costs a crossing to map and nothing to touch; a copy costs a walk; a fork costs two crossings per page and makes every later read free.

</div>
