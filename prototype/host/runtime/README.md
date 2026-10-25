# runtime: the kernelet runtime

A kernelet runtime is the user-space program on the host that creates and
configures sandboxes, as a container runtime does. Here it is one client of
the endovisor UAPI (`../../linux/endovisor/uapi/endovisor.h`, chapter 2),
`sandbox.c`, and one command around it, `holder.c`: the sandbox's **holder**,
the process that creates the sandbox, keeps its descriptor open while it lives,
and destroys it. `holder register NAME IMAGE` hands an image file to
`KLET_KIND_REGISTER`; `holder run [OPTIONS] NAME NR_VCPUS [CMDLINE...]` joins
the sandbox's control group (`-c`), creates the sandbox, gives it its console
and log (its own standard output and error, or files: `--console`, `--log`;
`-k` gives it neither, and the endovisor then writes both to the host's
kernel log, prefixed `kernelet:`, which is what every test but `hello` uses),
forks one child per virtual CPU that sets itself up and executes its exec
descriptor, waits for the end, reaps the carriers, destroys the sandbox, and
reports the endovisor module's reference count, read once, which must then
be 0. Its exit status is the kernel proper's exit code, 128 for a panic, 129
for a kill.

What a child sets on itself between the `fork` and the `execveat` survives the
exec and makes the carrier what it is: every child sets no new privileges
(`PR_SET_NO_NEW_PRIVS`), which the endovisor insists on; `-p` pins virtual CPU
*i* to processor *i*; `--seccomp-kill NR` installs a seccomp filter that kills
the process on system call NR (the probe test). Two options end the sandbox
from outside, after a delay, and report the carrier of virtual CPU 0's signal
dispositions from `/proc/<pid>/status` first: `--kill-after MS`, a `SIGKILL` to
that carrier, as an operator would send it, and `--klet-kill-after MS`,
`KLET_KILL` with reason 1.

The runtimes' report lines (`holder:`, `RUN-MEM:`, `RUN-SCHED:`,
`UAPI-CHECK:`) are written into the kernel's log through `/dev/kmsg`, so that
on the serial console they are in order with the endovisor's lines and never
broken in the middle by one; `init` turns off the rate limit Linux puts on
such writes.

init runs every executable under `/tests` with no arguments. A test that is
a sequence of holder invocations is `run-test`, staged as `/tests/10-<name>`,
which reads its steps from `/tests/10-<name>.cmd` (`run`, `start`, `wait`,
`kill`, `sleep`, `pin`, `show`; see the head of `run-test.c`); the Makefile's
`stage-*` targets write them. The experiment drivers read what they do, how
many virtual CPUs the sandbox has and its command line from the three lines
of `/tests/10-<name>.arg`.

The book explains the endovisor UAPI and the holder in chapter 2; the
runtimes' measurements of native Linux appear in chapter 15.

## How they are built

`make runtime`, which every `stage-*` target runs: `gcc -static -O2` into
`.build/`, with `-I linux/endovisor/uapi`.

## Files

| file | what it is | test |
|---|---|---|
| `sandbox.h`, `sandbox.c` | the client of the endovisor UAPI: `open_system`, `register_kind`, `find_kind`, `join_cgroup` (which makes the group if it does not exist), `start_carrier`, `wait_sandbox` (`KLET_WAIT`, watching the children through process descriptors too: a child that dies before its exec never became a carrier, so the holder kills the sandbox itself if one does), `run_sandbox`; and what the tests need around them (`KLET_GET_STATS` printed, the module's reference count, `/proc` fields) | every one |
| `holder.c` | the command: `register` and `run` with its options | `make hello`, `probe`, `yield` |
| `run-test.c` | a test's steps, from `/tests/10-<name>.cmd`, in place of a shell | `make hello`, `probe`, `yield` |
| `uapi-check.c` | the UAPI's promises, checked one by one before the hello boot's own sandbox: every refusal the header names that this prototype can reach, the exec descriptor's file, a sandbox that never boots because a virtual CPU never arrives, the destroy the last close does, two sandboxes of two kinds at once, unregistering | `make hello` |
| `yield-rival.c` | the yield test's two Linux processes: the competitor, pinned to the carrier's processor and computing the same checksum in user space, and the grace-period prodder on the other processor | `make yield` |
| `run-sched.c` | the scheduler experiments: a holder child runs the sandbox in its own control group, `/sys/fs/cgroup/klet`, on CPUs 0 and 1, while the driver, outside it, counts how many carriers Linux sees runnable; with `coop` two competitors in a sibling group, with `fair` one, and the fairness measurement; with `perf` no competitor, and after the sandbox the same switch and wake-up measurements on native Linux | `make sched-*` |
| `run-mem.c` | the memory experiments, the sandbox in `/sys/fs/cgroup/sandbox`; with `pressure` also swap and a memory hog until reclaim has run; with `kill`, a competitor on the processor of vCPU 1's carrier, then both carriers' signal dispositions from `/proc`, a SIGTERM and a SIGUSR1 to it and a SIGTERM to the carrier of vCPU 0, 2000 rounds of SIGQUIT, SIGABRT, SIGTSTP, SIGTTIN and SIGTTOU to it and a SIGQUIT and a SIGTSTP to the carrier of vCPU 0, a SIGSTOP and a SIGCONT, and a SIGKILL; with `killidle` and `killspin`, a SIGKILL to the carrier of vCPU 1 once the kernelet says it is idle in `vcpu_idle` or looping in a kernel task, and the time until the sandbox has exited | `make mem-*` |
