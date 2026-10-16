# What it costs

Every mechanism in this book has a price, and this chapter gives the handful of numbers that say whether the design is worth it. All of them were measured on the companion prototype, built from this repository, by `make bench` and `make hello`; nothing here comes from anywhere else. The numbers depend on the machine, so run `make bench` yourself and compare.

**Measured on:** the prototype at the commit this book was built from, in a Linux 6.12 guest under QEMU with KVM, two processors and 512 MiB, on a host with an Intel Xeon E3-1270 v6 processor whose cycle counter runs at 3.79 GHz, so one cycle is 0.26 ns. The host was shared with other work, which shows in the worst cases. Unless a row says otherwise, a figure is the median over five boots of each boot's own median over its samples; the last column is the worst 99th percentile any boot reported.

## The crossing

A service call is an indirect function call plus two stack switches (chapter 6). vOSTD times it at start, with interrupts off, in seven rounds of 2,000 calls of a service that does nothing, and keeps the cheapest round, since the machine beneath the guest can take the processor away in the middle of one; the line is in every `make hello` log.

| | cycles |
|---|---|
| the service body alone, called directly | 25 |
| the same through the service stub, both stack switches included | 34 |

So the stack switches cost about ten cycles a call, a few nanoseconds.

## Tasks

Measured by the scheduler test kernel on its two virtual CPUs (`make sched-perf`), with the sandbox in a control group of its own.

| | median | worst 99th percentile |
|---|---|---|
| two kernelet tasks yielding to each other on one virtual CPU, one round trip | 2,224 cycles (586 ns) | 4,472 |
| a blocked high-priority task woken by a low-priority one on the same virtual CPU, until it runs | 1,812 cycles (478 ns) | 3,664 |
| for scale: two Linux processes on one processor calling `sched_yield()`, one round trip | 3,574 cycles (943 ns) | 7,308 |

A kernelet task switch, the scheduler's decision included, is therefore about 1,100 cycles. The Linux row is a scale, not a baseline: the Linux pair makes two system calls and changes address space, and the kernelet pair does neither, so the first number is an upper bound on what the kernelet's own scheduler costs and not a speed-up. The wake-up across virtual CPUs, through `vcpu_kick` and the kick's interrupt of chapter 9, produced no samples in these boots, so it is not reported.

## Fairness

The sandbox's control group and a sibling group with equal weight, both confined to the same two processors; the sibling runs busy loops for ten seconds (`make sched-fair`).

| the sandbox runs | the sibling's share, in processors | runnable tasks of the sandbox that Linux saw at once |
|---|---|---|
| 1 task | 0.989 | 2 |
| 50 tasks | 0.984 | 3 |
| 50 tasks and one that holds a guard for 10 ms at a time | 0.982 | 3 |

Three is the whole argument of chapter 10: two carriers and the root carrier, whether the kernelet runs one task or fifty. In an earlier run of the same test on this shared host, the middle row's sibling got 0.667 of a processor while the guest itself was kept off a processor for six of the ten seconds, which the test reports as stolen time. A measurement of fairness on a host that is not fair to the guest means little, so the test is in `make bench`, which reports and does not fail.

## Memory

Measured by the memory test kernel (`make mem-perf`), with a tenant program that times each access with the cycle counter.

| | median | worst 99th percentile |
|---|---|---|
| first touch of a page the kernel mapped ahead | 82 cycles (22 ns), 0 faults | 380 |
| `map`, one page per call | 750 cycles (198 ns) | 808 |
| `map` of 512 pages under one cursor, per page | 791 cycles (209 ns) | 985 |
| protect 2 MiB read-only, with its flush | 402,356 cycles (106 µs) | 528,296 |
| a read of each page after that protect | 82 cycles (22 ns), 0 faults | 298 |
| copy 64 bytes out of tenant memory | 184 cycles (49 ns) | 342 |
| copy 4 KiB out of tenant memory | 400 cycles (105 ns) | 648 |
| `fork` of a process with 64 MiB mapped | 36.7 M cycles (9.7 ms) | 37.7 M |
| the child's first pass over the 64 MiB | 2.0 M cycles (0.52 ms), 0 faults | 3.9 M |
| the parent's re-read of the 64 MiB after the fork | 2.0 M cycles (0.52 ms), 0 faults | 2.2 M |
| `munmap` of the 64 MiB | 1.8 M cycles (0.48 ms) | 2.0 M |

What the rows say, one at a time.

**A page the kernel mapped costs nothing at its first touch.** The entry is in Linux's page table from the moment `vm_map` returns, so the tenant's first access is a TLB miss and a hardware walk, 82 cycles, with no fault. That is a container's cost, and it is the design's whole reason: any scheme that let Linux's page table be filled lazily, on demand, would pay a fault of a couple of thousand cycles at the first touch of every page.

**A `map` costs a crossing.** 750 cycles is one service call: the stub, the address-space lock, the grant check, and Linux's insert. A kernel that maps 512 pages under one cursor pays it 512 times. That is the price of letting trusted code check every frame, paid once per page, where the first-touch saving is collected once per page too.

**A protect costs a crossing per page and saves a refault per page.** 2 MiB read-only is 512 `vm_protect` calls and one flush, about 106 µs; the reads afterwards take 82 cycles and no fault, because the entries were rewritten in place and never removed.

**Copies cost a walk.** 184 cycles for 64 bytes is the software walk of chapter 13 plus the copy; a direct copy on a machine would be a few tens of cycles. For 4 KiB the walk disappears into the copy.

**`fork` is the trade-off.** A `fork` of a process with 64 MiB mapped costs two crossings per page, a protect of the parent and a map into the child, and takes 9.7 ms. In exchange, neither the child's first pass over the memory nor the parent's re-read takes a single fault: half a millisecond each. A design that made the fork cheap by deferring the work to faults would pay it back, with interest, the first time either process touched its memory. A kernel that forks and never touches the memory, as a shell does before `exec`, loses by it; everything else gains.

<div class="recap">

**Recap.** A crossing costs a few nanoseconds. A kernelet task switch costs about a thousand cycles and never involves Linux. A sandbox's share of the processors does not depend on what its kernel does. A page costs a crossing to map and nothing to touch; a copy costs a walk; a fork costs two crossings per page and makes every later access free.

</div>
