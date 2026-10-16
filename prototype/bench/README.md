# bench: the scripts that read the measurements

The kernels print their measurements in the serial log as lines of samples
summarised inside the kernelet (`SCHED-PERF`, `NATIVE-PERF`, `MEM-PERF`: a
median, a 99th percentile and the extremes, in cycles of the time-stamp
counter). These scripts aggregate them over several boots and print the
tables; the Makefile's check targets run them.

| file | what it does | run by |
|---|---|---|
| `sched-model.py` | the reference model of the sched kernel's policy: replays the scenario from the kernel's own `SCHED-TASK` and `SCHED-EV` lines, and the trace from its `SCHED: sw` lines between the `SCHED-TRACE` begin and end markers, and checks every switch the kernelet made against what strict priority with round robin would have done | `make sched-policy` |
| `sched-perf.py` | the median of the per-boot medians and the worst p99 of a kernelet task switch, a wake-up on the same and on the other vCPU, a round trip between two tenant processes, and the native Linux comparisons, with a note on which comparisons are fair; it fails if any of the four kernelet measurements has no samples in a boot | `make sched-perf` |
| `mem-perf.py` | the same aggregation for the memory costs: first touch, map, protect, read after protect, copies, fork, the child's reads, munmap; and the counters printed beside them | `make mem-perf` |

`make sched-fair`, `sched-perf` and `mem-perf` are measurements, not tests:
`make bench` runs all three and prints their tables, and never fails, because
their assertions depend on the host being quiet. The book discusses the
numbers in chapter 14 (what it costs).
