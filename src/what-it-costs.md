# What it costs

Every mechanism in this book has a price, and this chapter gives the handful of numbers that say whether the design is worth it. All of them were measured on the companion prototype, built from this repository, by `make bench` and `make hello`; nothing here comes from anywhere else. The numbers depend on the machine, so run `make bench` yourself and compare.

**Measured on:** the prototype at the commit this book was built from, in a Linux 6.12 guest under QEMU with KVM, two processors and 512 MiB, on a host with an Intel Xeon E3-1270 v6 processor whose cycle counter runs at 3.79 GHz, so one cycle is 0.26 ns. The host was shared with other work, which shows in the worst cases. Unless a row says otherwise, a figure is the median over five boots of each boot's own median over its samples; the last column is the worst 99th percentile any boot reported.

## The crossing

A service call is an indirect function call plus two stack switches (chapter 6). vOSTD times it at start, with interrupts off, in seven rounds of 2,000 calls of a service that does nothing, and keeps the cheapest round, since the machine beneath the guest can take the processor away in the middle of one; the line is in every `make hello` log.

| | cycles |
|---|---|
| the service body alone, called directly | 22 |
| the same through the service stub, both stack switches included | 37 |

So the stack switches cost about fifteen cycles a call, a few nanoseconds. The two figures move by a few cycles from boot to boot: over the four `make test` runs of the build this book reports, the stub took 34 to 37 cycles and the body 22 to 25.

## Tasks

Measured by the scheduler test kernel on its two virtual CPUs (`make sched-perf`), with the sandbox in a control group of its own.

| | median | worst 99th percentile |
|---|---|---|
| two kernelet tasks yielding to each other on one virtual CPU, one round trip | 2,278 cycles (601 ns) | 4,896 |
| a blocked high-priority task woken by a lower-priority one on the same virtual CPU, until it runs | 1,842 cycles (486 ns) | 3,872 |
| the same, woken from the other virtual CPU: `vcpu_kick`, the kick's interrupt and the upcall (chapter 9) | 3,684 cycles (972 ns) | 135,974 |
| two tenant threads of two processes alternating on one virtual CPU through a yield system call, one round trip | 10,364 cycles (2.73 µs) | 25,250 |
| for scale: two Linux processes on one processor calling `sched_yield()`, one round trip | 3,592 cycles (947 ns) | 10,936 |
| for scale: a Linux process woken through a pipe by one on the other processor | 41,122 cycles (10.8 µs) | 97,230 |

A kernelet task switch, the scheduler's decision included, is therefore about 1,100 cycles. The Linux `sched_yield` row is a scale for it, not a baseline: the Linux pair makes two system calls and changes address space, and the kernelet pair does neither, so the kernelet round trip is an upper bound on what the kernelet's own scheduler costs and not a speed-up. The tenant-thread row is the honest comparison with it: both are a user thread entering the kernel and another user thread, in another address space, leaving it, timed from the same point in user mode, and the kernelet's costs 2.9 times as much. The difference is what each thread pays per trip: the gate's entry and exit, the kernelet's own switch, the adoption of the other address space through `kernelet_switch_mm` (chapter 12), and the kernel proper's save and load of the floating-point registers (chapter 8). The wake-up across virtual CPUs takes a microsecond when the kick's interrupt finds the other carrier running kernelet code; its tail is the widest of any row, because the kick may instead find that carrier asleep in `vcpu_idle`, where waking it is a Linux wake-up, or in user mode, where the bit waits for the carrier's next return (chapter 8).

## Fairness

The sandbox's control group and a sibling group with equal weight, both confined to the same two processors; the sibling runs busy loops for ten seconds (`make sched-fair`).

| the sandbox runs | the sibling's share, in processors, first run | second run, directly after | runnable tasks of the sandbox that Linux saw at once |
|---|---|---|---|
| 1 task | 0.997 | 0.986 | 2 |
| 50 tasks | 0.992 | 0.977 | 3 |
| 50 tasks and one that holds a guard for 10 ms at a time | 0.666 | 0.984 | 3 |

Linux never saw more than three of the sandbox's tasks runnable at once, the two carriers and, briefly, the root carrier, whether the kernelet ran one task or fifty: that is the two-level argument of chapter 8, and the reason chapter 10's fairness holds. The first run's last row is the exception, and it is unexplained: the sibling got two thirds of a processor and the sandbox, by its own account, 1.32. The same two-thirds share appeared once before on this shared host, in the middle row of an earlier run, and never twice in a row. The one thing the test measures about interference, the time the sandbox's carriers spent descheduled by the guest's own Linux while running kernelet code, which it reports as *stolen*, was no higher in either odd run than in the passing ones, and the test does not read how long the host kept the whole guest off a processor. A measurement of fairness on a shared host means little, so the test is in `make bench`, which reports and does not fail.

## Memory

Measured by the memory test kernel (`make mem-perf`), with a tenant program that times each access with the cycle counter.

| | median | worst 99th percentile |
|---|---|---|
| first touch of a page the kernel mapped ahead | 86 cycles (23 ns), 0 faults | 1,148 |
| `map`, one page per call | 742 cycles (196 ns) | 804 |
| `map` of 512 pages under one cursor, per page | 782 cycles (206 ns) | 928 |
| protect 2 MiB read-only, with its flush | 409,064 cycles (108 µs) | 565,730 |
| a read of each page after that protect | 82 cycles (22 ns), 0 faults | 312 |
| copy 64 bytes out of tenant memory | 180 cycles (47 ns) | 236 |
| copy 4 KiB out of tenant memory | 394 cycles (104 ns) | 516 |
| `fork` of a process with 64 MiB mapped | 37.0 M cycles (9.8 ms) | 37.6 M |
| the child's first pass over the 64 MiB | 2.0 M cycles (0.52 ms), 0 faults | 2.2 M |
| the parent's re-read of the 64 MiB after the fork | 1.9 M cycles (0.51 ms), 0 faults | 2.2 M |
| `munmap` of the 64 MiB | 1.9 M cycles (0.51 ms) | 2.1 M |

What the rows say, one at a time.

**A page the kernel mapped costs nothing at its first touch.** The entry is in Linux's page table from the moment `vm_map` returns, so the tenant's first access is a TLB miss and a hardware walk, 86 cycles, with no fault. That is a container's cost, and it is the design's whole reason: any scheme that let Linux's page table be filled lazily, on demand, would pay a fault, many times the cost of a walk, at the first touch of every page.

**A `map` costs a crossing.** 742 cycles is one service call: the stub, the address-space lock, the grant check, and Linux's insert. A kernel that maps 512 pages under one cursor pays it 512 times. That is the price of letting trusted code check every frame, paid once per page, where the first-touch saving is collected once per page too.

**A protect costs a crossing per page and saves a refault per page.** 2 MiB read-only is 512 `vm_protect` calls and one flush, about 108 µs; the reads afterwards take 82 cycles and no fault, because the entries were rewritten in place and never removed.

**Copies cost a walk.** 180 cycles for 64 bytes is the software walk of chapter 13 plus the copy; a direct copy on a machine would be a fraction of that. For 4 KiB the walk disappears into the copy.

**`fork` is the trade-off.** A `fork` of a process with 64 MiB mapped costs two crossings per page, a protect of the parent and a map into the child, and takes 9.8 ms. In exchange, neither the child's first pass over the memory nor the parent's re-read takes a single fault: half a millisecond each. A design that made the fork cheap by deferring the work to faults would pay it back, with interest, the first time either process touched its memory. A kernel that forks and never touches the memory, as a shell does before `exec`, loses by it; everything else gains.

<div class="recap">

**Recap.** The stack switches of a crossing cost a few nanoseconds; a memory service, with Linux's lock and its work, costs several hundred cycles. A kernelet task switch costs about eleven hundred cycles and never involves Linux. A sandbox's share of the processors does not depend on what its kernel does. A page costs a crossing to map and nothing to touch; a copy costs a walk; a fork costs two crossings per page and makes every later access free.

</div>
