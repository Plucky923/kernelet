# What it costs

Every mechanism in this book has a price, and this chapter gives the handful of numbers that say whether the design is worth it. All of them were measured on the companion prototype, built from this repository, by `make bench` and `make hello`; nothing here comes from anywhere else. The numbers depend on the machine, so run `make bench` yourself and compare.

**Measured on:** the prototype at the commit this book was built from, in a Linux 6.12 guest under QEMU with KVM, two processors and 512 MiB, on a host with an Intel Xeon E3-1270 v6 processor whose cycle counter runs at 3.79 GHz, so one cycle is 0.26 ns. The host was shared with other work, which shows in the worst cases. Unless a row says otherwise, a figure is the median over five boots of each boot's own median over its samples; the last column is the worst 99th percentile any boot reported.

## The crossing

A service call is an indirect function call plus two stack switches (chapter 7). The endovisor's stub times it at the sandbox's start, with interrupts off, in seven rounds of 2,000 calls of a service that does nothing, and keeps the cheapest round, since the machine beneath the guest can take the processor away in the middle of one; the line is in every `make hello` log, and these two rows are from the one boot quoted in chapter 8.

| | cycles |
|---|---|
| the service body alone, called directly | 29 |
| the same through the service stub, both stack switches included | 39 |
| a 64-byte heap allocation and its free, `mem_alloc` and `mem_free` together | 411 |

So the stack switches cost about ten cycles a call, a few nanoseconds; the two figures move by several cycles from boot to boot, and their difference with them. The heap pair, timed by vOSTD with interrupts on in seven rounds of 1,000 pairs, the cheapest kept, is two crossings, Linux's `kmalloc` and `kfree`, and the endovisor's table of blocks (chapter 4), which costs some tens of those cycles: without the table, in one boot, the pair took 328.

## Tasks

Measured by the scheduler test kernel on its two virtual CPUs (`make sched-perf`), with the sandbox in a control group of its own.

| | median | worst 99th percentile |
|---|---|---|
| two kernelet tasks yielding to each other on one virtual CPU, one round trip | 2,228 cycles (588 ns) | 4,648 |
| a blocked high-priority task woken by a lower-priority one on the same virtual CPU, until it runs | 1,858 cycles (490 ns) | 3,792 |
| the same, woken from the other virtual CPU: `vcpu_kick`, the kick's interrupt and the upcall (chapter 10) | 5,776 cycles (1.52 µs) | 136,070 |
| two tenant threads of two processes alternating on one virtual CPU through a yield system call, one round trip | 15,790 cycles (4.16 µs) | 34,936 |
| for scale: two Linux processes on one processor calling `sched_yield()`, one round trip | 3,872 cycles (1.02 µs) | 74,712 |
| for scale: a Linux process woken through a pipe by one on the other processor | 41,186 cycles (10.9 µs) | 98,964 |

A kernelet task switch, the scheduler's decision included, is therefore about 1,100 cycles. The Linux `sched_yield` row is a scale for it, not a baseline: the Linux pair makes two system calls and changes address space, and the kernelet pair does neither, so the kernelet round trip is an upper bound on what the kernelet's own scheduler costs and not a speed-up. The tenant-thread row is the honest comparison with it: both are a user thread entering the kernel and another user thread, in another address space, leaving it, timed from the same point in user mode, and the kernelet's costs about four times as much. The difference is what each thread pays per trip: the two hooks, in and out, the kernelet's own switch, the adoption of the other address space through `kernelet_switch_mm` (chapter 13), and the kernel proper's save and load of the floating-point registers (chapter 9). The wake-up across virtual CPUs takes about a microsecond and a half when the kick's interrupt finds the other carrier running kernelet code, of which roughly half a microsecond is the reschedule window of chapter 10 (measured by taking the window's note away: the median falls to about 3,500 cycles): the kick usually lands after the woken virtual CPU has already picked the task, and the note it leaves costs one reschedule that finds nothing to do. Its tail is the widest of any row, because the kick may instead find that carrier asleep in `vcpu_idle`, where waking it is a Linux wake-up with Linux's own latency (chapter 9).

## Fairness

The sandbox's control group and a sibling group with equal weight, both confined to the same two processors; the sibling runs busy loops for ten seconds (`make sched-fair`).

| the sandbox runs | the sibling's share, in processors | runnable tasks of the sandbox that Linux saw at once |
|---|---|---|
| 1 task | 0.986 | 3 |
| 50 tasks | 0.982 | 2 |
| 50 tasks and one that holds a guard for 10 ms at a time | 0.989 | 2 |

Linux never saw more than three of the sandbox's tasks runnable at once, the two carriers and, briefly, the root carrier, whether the kernelet ran one task or fifty: that is the two-level argument of chapter 9, and the reason chapter 11's fairness holds. In two runs on earlier builds, one row's sibling got two thirds of a processor, and the cause was never found, so the claim rests on this build's runs. The one thing the test measures about interference, the time the sandbox's carriers spent descheduled by the guest's own Linux while running kernelet code, which it reports as *stolen*, was no higher in either odd run than in the passing ones, and the test does not read how long the host kept the whole guest off a processor. A measurement of fairness on a shared host means little, so the test is in `make bench`, which reports and does not fail.

## Memory

Measured by the memory test kernel (`make mem-perf`), with a tenant program that times each access with the cycle counter.

| | median | worst 99th percentile |
|---|---|---|
| first touch of a page the kernel mapped ahead | 82 cycles (22 ns), 0 faults | 640 |
| `map`, one page per call | 726 cycles (191 ns) | 1,588 |
| `map` of 512 pages under one cursor, per page | 775 cycles (204 ns) | 1,412 |
| protect 2 MiB read-only, with its flush | 406,574 cycles (107 µs) | 619,842 |
| a read of each page after that protect | 80 cycles (21 ns), 0 faults | 108 |
| copy 64 bytes out of tenant memory | 194 cycles (51 ns) | 326 |
| copy 4 KiB out of tenant memory | 408 cycles (108 ns) | 602 |
| the kernel proper's `fork` of a process with 64 MiB mapped (16,384 pages over 256 frames, each mapped 64 times): a protect of the parent, a map into the child | 36.7 M cycles (9.7 ms) | 41.0 M |
| the child's first read pass over the 64 MiB of mappings | 2.0 M cycles (0.53 ms), 0 faults | 2.2 M |
| the parent's re-read of the 64 MiB of mappings after the fork | 2.0 M cycles (0.52 ms), 0 faults | 2.1 M |
| the kernel proper's unmap of the 64 MiB, under one cursor | 1.9 M cycles (0.50 ms) | 2.4 M |

What the rows say, one at a time.

**A page the kernel mapped costs nothing at its first touch.** The entry is in Linux's page table from the moment `vm_map` returns, so the tenant's first access is a TLB miss and a hardware walk, 82 cycles, with no fault. That is a container's cost, and it is the design's whole reason: any scheme that let Linux's page table be filled lazily, on demand, would pay a fault, many times the cost of a walk, at the first touch of every page.

**A `map` costs a crossing.** 726 cycles is one service call: the stub, the address-space lock, the grant check, and Linux's insert. A kernel that maps 512 pages under one cursor pays it 512 times. That is the price of letting trusted code check every frame, paid once per page, where the first-touch saving is collected once per page too.

**A protect costs a crossing per page and saves a refault per page.** 2 MiB read-only is 512 `vm_protect` calls and one flush, about 107 µs; the reads afterwards take 80 cycles and no fault, because the entries were rewritten in place and never removed.

**Copies cost a walk.** 194 cycles for 64 bytes is the software walk of chapter 14 plus the copy; a direct copy on a machine would be a fraction of that. For 4 KiB the walk disappears into the copy.

**`fork` is the trade-off.** The `fork` and unmap rows are the test kernel doing what the tree's kernel proper does for those system calls, not Linux's. A `fork` of a process with 64 MiB mapped costs two crossings per page, a protect of the parent and a map into the child, and takes 9.7 ms. In exchange, neither the child's first read pass over the memory nor the parent's re-read takes a single fault: half a millisecond each, which is the cost of the TLB misses and walks alone, since the grant is small and the 64 MiB are 256 frames mapped over and over, so the data never leaves the cache. (A write to a shared page after the fork still faults, as copy-on-write requires.) A design that made the fork cheap by deferring the work to faults would pay it back, with interest, the first time either process touched its memory. A kernel that forks and never touches the memory, as a shell does before `exec`, loses by it; everything else gains.

<div class="recap">

**Recap.** The stack switches of a crossing cost a few nanoseconds; a memory service, with Linux's lock and its work, costs several hundred cycles. A kernelet task switch costs about eleven hundred cycles and never involves Linux. A sandbox's share of the processors does not depend on what its kernel does, in every run of this build, and in all but two unexplained runs of earlier ones. A page costs a crossing to map and nothing to touch; a copy costs a walk; a fork costs two crossings per page and makes every later read free.

</div>
