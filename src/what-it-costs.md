# What it costs

Every mechanism in this book has a price, and this chapter gives the handful of numbers that say whether the design is worth it. All of them were measured on the companion prototype, built from this repository, by `make bench` and `make hello`; nothing here comes from anywhere else. The numbers depend on the machine, so run `make bench` yourself and compare.

**Measured on:** the prototype at the commit this book was built from, in a Linux 6.12 guest under QEMU with KVM, two processors and 512 MiB, on a host with an Intel Xeon E3-1270 v6 processor whose cycle counter runs at 3.79 GHz, so one cycle is 0.26 ns. The host was shared with other work, which shows in the worst cases. Unless a row says otherwise, a figure is the median over five boots of each boot's own median over its samples; the last column is the worst 99th percentile any boot reported.

## The crossing

A service call is an indirect function call plus two stack switches (chapter 6). vOSTD times it at start, with interrupts off, over 2,000 calls of a service that does nothing; the line is in every `make hello` log.

| | cycles |
|---|---|
| the service body alone, called directly | 25 |
| the same through the service stub, both stack switches included | 41 |

So the stack switches cost about 16 cycles a call, a few nanoseconds.

## Tasks

Measured by the scheduler test kernel on its two virtual CPUs (`make sched-perf`), with the sandbox in a control group of its own.

| | median | worst 99th percentile |
|---|---|---|
| two kernelet tasks yielding to each other on one virtual CPU, one round trip | 2,188 cycles (577 ns) | 4,356 |
| a blocked high-priority task woken by a low-priority one on the same virtual CPU, until it runs | 1,796 cycles (474 ns) | 3,484 |
| for scale: two Linux processes on one processor calling `sched_yield()`, one round trip | 3,574 cycles (943 ns) | 10,616 |

A kernelet task switch, the scheduler's decision included, is therefore about 1,100 cycles. The Linux row is a scale, not a baseline: the Linux pair makes two system calls and changes address space, and the kernelet pair does neither, so the first number is an upper bound on what the kernelet's own scheduler costs and not a speed-up. The wake-up across virtual CPUs, through `vcpu_kick`, produced no samples in these boots; chapter 9's section on the kick says why its latency is, in this prototype, up to one tick.

## Fairness

The sandbox's control group and a sibling group with equal weight, both confined to the same two processors; the sibling runs busy loops for ten seconds (`make sched-fair`).

| the sandbox runs | the sibling's share, in processors | runnable tasks of the sandbox that Linux saw at once |
|---|---|---|
| 1 task | 0.987 | 2 |
| 50 tasks | 0.991 | 3 |
| 50 tasks and one that holds a guard for 10 ms at a time | 0.986 | 3 |

Three is the whole argument of chapter 10: two carriers and the root carrier, whether the kernelet runs one task or fifty. The shares are from the second of two runs of the test on this shared host; in the first, the middle row's sibling got 0.667 of a processor while the guest itself was kept off a processor for six of the ten seconds, which the test reports as stolen time. A measurement of fairness on a host that is not fair to the guest means little, so the test is in `make bench`, which reports and does not fail.

## Memory

Measured by the memory test kernel (`make mem-perf`), with a tenant program that times each access with the cycle counter.

| | median | worst 99th percentile |
|---|---|---|
| first touch of a page the kernel mapped ahead | 82 cycles (22 ns), 0 faults | 1,274 |
| `map`, one page per call | 746 cycles (197 ns) | 1,610 |
| `map` of 512 pages under one cursor, per page | 779 cycles (205 ns) | 1,310 |
| protect 2 MiB read-only, with its flush | 396,510 cycles (105 µs) | 628,876 |
| a read of each page after that protect | 80 cycles (21 ns), 0 faults | 294 |
| copy 64 bytes out of tenant memory | 186 cycles (49 ns) | 300 |
| copy 4 KiB out of tenant memory | 398 cycles (105 ns) | 576 |
| `fork` of a process with 64 MiB mapped | 36.3 M cycles (9.6 ms) | 40.3 M |
| the child's first pass over the 64 MiB | 1.9 M cycles (0.51 ms), 0 faults | 4.0 M |
| the parent's re-read of the 64 MiB after the fork | 2.0 M cycles (0.52 ms), 0 faults | 2.3 M |
| `munmap` of the 64 MiB | 1.9 M cycles (0.49 ms) | 3.0 M |

What the rows say, one at a time.

**A page the kernel mapped costs nothing at its first touch.** The entry is in Linux's page table from the moment `vm_map` returns, so the tenant's first access is a TLB miss and a hardware walk, 82 cycles, with no fault. That is a container's cost, and it is the design's whole reason: any scheme that let Linux's page table be filled lazily, on demand, would pay a fault of a couple of thousand cycles at the first touch of every page.

**A `map` costs a crossing.** 746 cycles is one service call: the stub, the address-space lock, the grant check, and Linux's insert. A kernel that maps 512 pages under one cursor pays it 512 times. That is the price of letting trusted code check every frame, paid once per page, where the first-touch saving is collected once per page too.

**A protect costs a crossing per page and saves a refault per page.** 2 MiB read-only is 512 `vm_protect` calls and one flush, about 105 µs; the reads afterwards take 80 cycles and no fault, because the entries were rewritten in place and never removed.

**Copies cost a walk.** 186 cycles for 64 bytes is the software walk of chapter 13 plus the copy; a direct copy on a machine would be a few tens of cycles. For 4 KiB the walk disappears into the copy.

**`fork` is the trade-off.** A `fork` of a process with 64 MiB mapped costs two crossings per page, a protect of the parent and a map into the child, and takes 9.6 ms. In exchange, neither the child's first pass over the memory nor the parent's re-read takes a single fault: half a millisecond each. A design that made the fork cheap by deferring the work to faults would pay it back, with interest, the first time either process touched its memory. A kernel that forks and never touches the memory, as a shell does before `exec`, loses by it; everything else gains.

<div class="recap">

**Recap.** A crossing costs a few nanoseconds. A kernelet task switch costs about a thousand cycles and never involves Linux. A sandbox's share of the processors does not depend on what its kernel does. A page costs a crossing to map and nothing to touch; a copy costs a walk; a fork costs two crossings per page and makes every later access free.

</div>
