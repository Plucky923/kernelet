# runtime: the kernelet runtimes

A kernelet runtime is the user-space program on the host that creates and
configures sandboxes, as a container runtime does. Here each test has a small
one, a static C program that `init` runs from `/tests/`: it forks, sets the
child up (control group, CPU pinning, no new privileges), and in the child
execs the sandbox's `.klet` file, which the endovisor's binary-format handler
turns into the sandbox's root carrier. The parent then does whatever the test
needs around the sandbox, waits for the root carrier to die, and waits for the
module's reference count to reach zero so that `init` can unload it.

A `.klet` file is the sandbox's configuration, written by the Makefile's
`stage-*` targets: the magic `KLET`, a version (2), the number of virtual CPUs,
and a command line that the kernel proper reads as its kernel command line.

The book explains creating a sandbox and the root carrier in chapter 5
(carriers); the runtimes' measurements of native Linux appear in chapter 14.

## How they are built

`make runtime`, which every `stage-*` target runs: `gcc -static -O2` into
`.build/run-*`. Each stage target copies the one its test needs to
`/tests/10-<name>` in the initramfs.

## Files

| file | what it is | test |
|---|---|---|
| `run-hello.c` | creates the sandbox and waits | `make hello` |
| `run-probe.c` | creates the sandbox, then kills the root carrier from outside, so that the endovisor has to evict the kernelet spinning in kernel mode | `make probe` |
| `run-yield.c` | the sandbox and a competitor pinned to one CPU; the competitor computes the same checksum in user space and reports its progress | `make yield` |
| `run-sched.c` | the sandbox in its own control group; with `coop`, `fair` or `perf` also competitors in a sibling group, the fairness measurement, and the same switch and wake-up measurements on native Linux | `make sched-*` |
| `run-mem.c` | the sandbox; with `pressure` also swap and a memory hog until reclaim has run; with `kill`, a SIGKILL to vCPU 1's carrier | `make mem-*` |
