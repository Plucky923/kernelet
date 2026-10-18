# runtime: the kernelet runtimes

A kernelet runtime is the user-space program on the host that creates and
configures sandboxes, as a container runtime does. Here each test has a small
one, a static C program that `init` runs from `/tests/`: it forks, sets the
child up, and in the child execs the sandbox's `.klet` file, which the endovisor's binary-format handler
turns into the sandbox's root carrier. The parent then does whatever the test
needs around the sandbox, waits for the root carrier to die, and waits for the
module's reference count to reach zero so that `init` can unload it.

What "sets the child up" means differs. Every runtime sets no new privileges
(`PR_SET_NO_NEW_PRIVS`) in the child. `run-yield.c` also pins the child to CPU
0, and `run-sched.c` puts it in its own control group, `/sys/fs/cgroup/klet`,
on CPUs 0 and 1, which it inherits from the runtime. `run-hello.c`,
`run-probe.c` and `run-mem.c` do nothing else: no control group, no pinning
(`run-mem.c`'s `kill` mode pins a running carrier later, from outside),
except that `run-probe.c`'s `seccomp` mode installs a seccomp filter in the
child before the exec, which every carrier inherits.

A `.klet` file is the sandbox's configuration, written by the Makefile's
`stage-*` targets: the magic `KLET`, a version (2), the number of virtual CPUs,
and a command line that the kernel proper reads as its kernel command line.

The book explains creating a sandbox and the root carrier in chapter 5
(carriers); the runtimes' measurements of native Linux appear in chapter 15.

## How they are built

`make runtime`, which every `stage-*` target runs: `gcc -static -O2` into
`.build/run-*`. Each stage target copies the one its test needs to
`/tests/10-<name>` in the initramfs.

## Files

| file | what it is | test |
|---|---|---|
| `run-hello.c` | creates the sandbox and waits | `make hello` |
| `run-probe.c` | creates the sandbox, reads the vCPU carrier's signal dispositions from `/proc/<pid>/status` after the probe's faults, then kills the root carrier from outside, so that the endovisor has to evict the kernelet spinning in kernel mode; with `seccomp` (in `/tests/10-probe.arg`), installs a filter that kills the process on the probe's endless system call, 1000, and kills nothing itself: Linux's kill of the vCPU carrier must end the sandbox | `make probe` |
| `run-yield.c` | the sandbox and a competitor pinned to one CPU; the competitor computes the same checksum in user space and reports its progress | `make yield` |
| `run-sched.c` | the sandbox in its own control group; with `coop` two competitors in a sibling group, with `fair` one, and the fairness measurement; with `perf` no competitor, and after the sandbox the same switch and wake-up measurements on native Linux | `make sched-*` |
| `run-mem.c` | the sandbox; with `pressure` also swap and a memory hog until reclaim has run; with `kill`, a competitor on the processor of vCPU 1's carrier, then the carriers' signal dispositions from `/proc`, a SIGTERM and a SIGUSR1 to it and a SIGTERM to the root carrier, 2000 rounds of SIGQUIT, SIGABRT, SIGTSTP, SIGTTIN and SIGTTOU to it and a SIGQUIT and a SIGTSTP to the root carrier, a SIGSTOP and a SIGCONT, and a SIGKILL; with `killidle` and `killspin`, a SIGKILL to the carrier of vCPU 1 once the kernelet says it is idle in `vcpu_idle` or looping in a kernel task, and the time the sandbox takes to end | `make mem-*` |
