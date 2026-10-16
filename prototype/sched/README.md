# sched: a kernel proper with its own scheduler

A kernel proper that injects its own task scheduler through real OSTD's
interface (`inject_scheduler`, `Scheduler`, `LocalRunQueue`): strict priority
over three levels, round robin within a level with a 5 ms slice, per-vCPU run
queues, pinning carried in the task's data. It shows that the *kernelet's*
scheduler decides which kernelet task runs, on virtual CPUs that Linux
schedules and knows nothing about. One image serves every scenario; the
sandbox's command line picks one with `mode=`:

| mode | test | what it shows |
|---|---|---|
| `policy` | `make sched-policy` | the policy is obeyed and it preempts; the trace is checked against a reference model (`bench/sched-model.py`) |
| `coop`, `coop-over` | `make sched-coop` | with the mirror on, Linux never deschedules a carrier inside a kernelet critical section; with it off it does; an overstayer is forced to yield at the first tick at least a millisecond after the first strike, about 2 ms on this machine (the check allows 4000 us, because a late tick lengthens it) |
| `fpu` | `make sched-fpu` | two tenant threads in two address spaces on one vCPU keep their floating-point registers across every switch |
| `fair` | `make sched-fair` (measurement) | a sibling control group's share of the processors does not depend on how many tasks the sandbox runs |
| `perf` | `make sched-perf` (measurement) | the cost of a kernelet task switch, a wake-up on the same and on the other vCPU, and a round trip between two tenant processes on one vCPU (timed in user mode, like the native one), beside native Linux's |

The book explains the task layer and virtual CPUs in chapter 8, the mirror,
the yield stubs and the bound in chapter 10, and the numbers in chapter 14.

## Files

| file | what it is |
|---|---|
| `src/lib.rs` | the scheduler and the scenarios |
| `sched.S` | the tenant program: CPU-bound yields, or the floating-point check-ins |
| `Cargo.toml` | the crate (`schedk`) |
