# What it costs

Every mechanism in this book has a price, and this chapter gives the handful of numbers that say whether the design is worth it. All of them were measured on the companion prototype, built from this repository, by `make bench` and `make test`, on the setup below. They are medians over several boots unless a row says otherwise. Run `make bench` yourself and compare; the numbers depend on the machine.

> **Measured on:** _to be filled in from the prototype's `make bench` output_.

## The crossing

A service call is an indirect function call plus two stack switches. Measured at boot, by vOSTD, over 2,000 calls of a service that does nothing:

| | cycles |
|---|---|
| a direct call to the same function | _n_ |
| the same through the service stub, stack switch included | _n_ |

## Tasks

| | median | 99th percentile |
|---|---|---|
| two kernelet tasks yielding to each other on one virtual CPU, round trip | _n_ cycles | _n_ |
| a blocked high-priority task woken by a low-priority one on the same virtual CPU, until it runs | _n_ cycles | _n_ |
| for scale: two Linux processes on one processor calling `sched_yield()`, round trip | _n_ cycles | _n_ |

## Fairness

The sandbox's control group and a sibling group with equal weight, confined to the same two processors; the sibling runs busy loops.

| the sandbox runs | the sibling's share of two processors | runnable tasks of the sandbox Linux saw at once |
|---|---|---|
| 1 task | _n_ | _n_ |
| 50 tasks | _n_ | _n_ |

## Memory

| | this design |
|---|---|
| first touch of a page the kernel mapped ahead | _n_ cycles, 0 faults |
| `map`, one page per call | _n_ cycles |
| protect 2 MiB read-only, with its flush | _n_ µs |
| a read of each page after that protect | _n_ cycles, 0 faults |
| copy 64 bytes out of tenant memory | _n_ cycles |
| copy 4 KiB out of tenant memory | _n_ cycles |
| `fork` of a process with 64 MiB mapped | _n_ ms |
| the child's first pass over the 64 MiB | _n_ ms |
| `munmap` of the 64 MiB | _n_ ms |

_The discussion of each row is written once the numbers are in._
