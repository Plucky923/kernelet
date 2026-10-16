# The kernelet-in-Linux prototype

This is the companion prototype of *Introduction to Kernelets in Linux*. It
runs Asterinas's 100-line Hello World kernel, unedited, as a **kernelet**: a
kernel compiled against an OSTD-shaped library (vOSTD), loaded into a patched
Linux 6.12 as part of a module, running in kernel mode on its own stacks,
serving its tenant program's system calls, mapping its memory in a Linux page
table, scheduled by Linux on ordinary tasks, and stopped by Linux like any
process. Four more kernels proper test the parts the 100-line kernel does not
reach: exceptions and eviction, preemption of kernel code, a scheduler of the
kernelet's own, and tenant memory.

Every claim the book makes about the prototype is a `make` target here that
builds what it needs, boots it in QEMU, and checks the serial log.

## The layers

From the tenant program down to the hardware, with the directory that holds
each layer and the chapter of the book that explains it:

```text
  tenant program       hello/hello.S, probe.S, ...       user mode
 ------------------------------------------------------------------------------
  kernel proper        hello/src/lib.rs (never edited),  ch. 2
                       probe/ yield/ sched/ mem/
  vOSTD                vostd/                            ch. 3, 8, 9, 10, 13
 ----------- the image ABI: services, entry table, boot arguments, ------------
             vCPU records            vostd/src/abi.rs = endovisor/kernelet.h  ch. 3
  endovisor            endovisor/  (kernelet.ko)         ch. 3, 5-12
  the gate             patches/0001-kernelet-gate.patch  ch. 4
  Linux 6.12           .build/linux-6.12, configured by linux/config.fragment
 ------------------------------------------------------------------------------
  kernelet runtime     runtime/run-*.c                   user mode on the host
  initramfs (PID 1)    initramfs/init.c
  QEMU with KVM        the Makefile's `run`
```

The kernel proper and vOSTD are one Rust static library, pre-linked into one
relocatable object, the **image**, which is linked into the endovisor module.
The image calls no Linux symbol: everything it needs from the host is a
service in the table the endovisor hands it at entry. The endovisor is an
ordinary out-of-tree module apart from the gate, a patch to Linux of 183
added lines, most of them in the generic entry code and `kernel/fork.c`. The kernelet runtime is the user-space
program that creates a sandbox, by exec'ing a `.klet` file that the
endovisor's binary-format handler turns into the sandbox's root carrier.

Each directory has a `README.md` saying what is in it.

## Building and running

### What it needs

- **Linux on x86-64 with KVM**, and QEMU at `/usr/local/qemu/bin/qemu-system-x86_64`
  (or `make QEMU=/path/to/qemu-system-x86_64 ...`). The guests use two CPUs and
  512 MiB.
- **Rust** through `rustup`: `rust-toolchain.toml` names the nightly
  (`nightly-2026-07-21`, with `rust-src`), and `rustup` installs it on first
  use. The image is built with `-Zbuild-std` for `x86_64-unknown-none`.
- **What a Linux build needs**: `gcc`, `make`, `flex`, `bison`, `bc`, `perl`,
  the `libelf` headers (objtool), and `cpio`, `xz`, `curl`, `python3`,
  `mkswap`.
- **Disk**: the unpacked and built kernel tree takes 1.8 GB under `.build/`,
  the Rust build about 230 MB, the logs and the 512 MiB sparse swap file of
  `make mem-pressure` about 120 MB. `make source` and `make linux` refuse to
  start with less than 6 GiB free on `/` (`MIN_FREE_GB`).

### From a fresh clone

```sh
make crates   # once, online: the Rust crates of Cargo.lock and of -Zbuild-std
make test     # fetches, unpacks, patches, configures and builds Linux the first
              # time; then builds the image, the module, the runtime and the
              # initramfs for each test, boots, and checks the log
make bench    # the measurements
```

The first `make test` downloads the v6.12 tarball (about 140 MB) from
cdn.kernel.org, unpacks it into `.build/linux-6.12`, deletes the tarball,
applies the gate patch, configures and builds the kernel (a `tinyconfig`
kernel, so this is quick), builds the Rust image, and then runs the tests:
315 s measured from an empty `.build/` on an eight-core machine, 134 s of them
in the first test. After that, `make test` takes about three minutes (185 s
measured), and `make bench` about the same (190 s: eight boots of the sched
kernel and five of the mem kernel). Every build is `--offline`, so nothing
after `make crates` and the one download needs the network.

`make test` runs, in order, and stops at the first failure: `hello`, `probe`,
`yield`, `sched-policy`, `sched-coop`, `sched-fpu`, `mem-func`, `mem-r2`,
`mem-conc`, `mem-kill`, `mem-pressure`. It prints one line per test; each
test's whole output is in `.build/test-<name>.out`. `make bench` runs
`sched-fair`, `sched-perf` and `mem-perf` and prints their tables; their
assertions depend on the host being quiet, so they are reported and never
fail the suite. Each one's boots go to `.build/bench/<name>.out` and its table
to `.build/bench/<name>.table`.

## The targets

| target | what it does | chapter |
|---|---|---|
| `make test` | the eleven tests below, in order | – |
| `make bench` | `sched-fair`, `sched-perf`, `mem-perf`, reported | 14 |
| `make hello` | the 100-line kernel, byte-identical to `hello/upstream/`: "Hello, world", a clean stop, a clean module unload; also the one-off measurement of what a service costs ("service stub: N cycles") | 2, 3, 6 |
| `make probe` | demand paging, a non-page-fault exception, and eviction of a kernelet spinning in kernel mode when the sandbox is killed | 7, 11, 12 |
| `make yield` | two boots under `preempt=none`, the watch timer off (the competitor starves) and on (it does not, and the checksums agree) | 9, 10 |
| `make sched-policy` | the kernelet's own scheduler: its trace checked against a reference model | 8 |
| `make sched-coop` | three boots: the mirror on (no involuntary deschedule in a critical section), off (the control), and an overstayer forced to yield within two ticks | 10 |
| `make sched-fpu` | floating-point registers of two tenant threads in two address spaces survive every switch | 8 |
| `make mem-func` | E2, E3, E4, E10: no Linux fault on mapped pages, fault-around, protection changes, a map under a guard, the withheld set | 12, 13 |
| `make mem-r2` | E5: the sleeping contract, broken on purpose, ends the kernelet | 13 |
| `make mem-conc` | E8, E11 on two vCPUs: lockless copies, the contended range lock, a process exiting under a copy, the retire list | 13 |
| `make mem-kill` | E11: one carrier of a process stopped and continued, then killed from outside; its sibling carries on | 11, 12 |
| `make mem-pressure` | E7: the area's entries survive reclaim and swap | 12 |
| `make sched-fair` | measurement: a sibling group's share of the processors with 1, 50, and 50 tasks and an overstayer | 10, 14 |
| `make sched-perf` | measurement: kernelet task switch and wake-up beside native Linux, five boots | 14 |
| `make mem-perf` | measurement: E6 and E9, the memory costs, five boots | 14 |
| `make crates` | download the Rust crates, once | – |
| `make source` | download and unpack Linux v6.12 | 4 |
| `make patch` | apply the gate patch; idempotent | 4 |
| `make linux` | configure (once, from `linux/config.fragment`) and build the kernel and `modules_prepare` | 4 |
| `make image` | build vOSTD and the kernel proper named by `KLET_KERNEL` (`hello`, `probe`, `yieldk`, `schedk`, `mem`) and pre-link the image | 3 |
| `make kernelet-module` | the image, then `endovisor/kernelet.ko` | 3 |
| `make runtime`, `make initramfs`, `make run` | the runtimes; the initramfs from `.build/stage`; one boot | 3 |
| `make clean`, `make distclean` | remove the harness's artifacts; also the kernel build | – |

## Module parameters

The endovisor takes three, which the tests set through the initramfs's
`/modules/order`:

| parameter | default | what it does | used by |
|---|---|---|---|
| `klet_watch` | 1 | the per-processor watch timer: the kernelet's tick, the delivery of virtual interrupts into kernelet code, and the two-tick bound on a critical section | `make yield` (0 for the control boot) |
| `klet_mirror` | 1 | vOSTD mirrors its guard depth into Linux's preemption count, so that Linux does not deschedule a carrier in a kernelet critical section | `make sched-coop` (0 for the control boot) |
| `klet_test_hooks` | 0 | the test hook: a `vm_map` carrying `KLET_PROT_TEST_SLEEP` sleeps `klet_test_sleep_ms` (default 20) in Linux | `make mem-conc` (1) |

## The serial log

Everything the guest prints goes to its serial port, which QEMU writes to
`.build/serial.log`; each boot overwrites it. The kernelet's own output is
the lines prefixed `kernelet:` (vOSTD's `println!` is the `log_write`
service, which is `printk`); `INIT:` lines are PID 1's and `RUN-*:` lines the
runtime's. Each test keeps a copy of its boot's log before it checks it:

| test | log |
|---|---|
| `hello`, `probe`, `sched-fpu` | `.build/serial-<test>.log` |
| `yield` | `.build/serial-yield-off.log`, `.build/serial-yield-on.log` |
| `sched-policy`, `sched-coop`, `sched-fair`, `sched-perf` | `.build/serial-sched-*.log` |
| `mem-*` | `.build/mem/<name>.log` (`func`, `r2`, `conc`, `kill`, `pressure`, `perf-1` ... `perf-5`) |

A check fails on any `BUG:`, `Oops`, `WARNING:` or `Call Trace` in the log, on
a missing line it expects, and on an unclean module unload. The endovisor
prints its counters when it unloads (`STATS`, `MEMSTATS`, the watch timer's
ticks and upcalls), which is the last thing in every log.

## Signals, stops and memory

- **Signals.** A carrier's pending signals are drained by the endovisor on its
  way to user mode. A fault signal Linux raised for the tenant's own
  instruction (`SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGFPE`, `SIGTRAP` with a
  fault's `si_code`, and the `SIGSEGV` of a general-protection fault) becomes
  the CPU exception the kernel proper sees; every other signal is dropped,
  except two. `SIGKILL` is Linux's, and kills the carrier. `SIGSTOP` stops a
  vCPU carrier the way it stops any task, and **a stopped carrier is a stopped
  virtual CPU**: the kernelet's tasks on it do not run, a sibling vCPU waiting
  for one of them waits, until `SIGCONT`. The root carrier never returns to
  user mode and cannot stop; it drops `SIGSTOP`.
- **Memory.** What the kernelet allocates through the host is charged to the
  memory cgroup of the carrier that asked, which is the sandbox's: its heap
  (`mem_alloc`, `GFP_KERNEL_ACCOUNT`), its kernelet stacks (`__vmalloc` with
  `GFP_KERNEL_ACCOUNT`, at most `KLET_MAX_KSTACKS` = 512 of 256 KiB per
  sandbox; beyond that `kstack_alloc` returns 0 and vOSTD reports
  `Error::NoMemory`), and the page-table pages of its address spaces, which
  Linux allocates and charges itself. The grant, the 4 MiB of frames the
  kernelet maps for its tenants, is not charged: the endovisor allocates it
  when the module is loaded, before any sandbox or control group exists.

## Known problems

- **`make sched-coop`'s deferral is measured in wall clock.** The design
  forces a critical section off the processor at the first watch tick at
  least 1 ms after the first strike, two ticks at most, and on this machine
  the longest deferral is 2.0 to 2.1 ms. The check allows 4000 us, and prints
  beside the deferral the boot's `stolen_ms` (the time its carriers spent off
  a processor while running kernelet code) and the longest gap between two
  watch ticks, because a tick that a busy host delivers late lengthens a
  deferral beyond two ticks.
- `make sched-fair` and `make sched-perf` can fail on a busy host (a share of
  0.8 of a processor where 1.0 is expected, a native reference with no
  samples). They are measurements, which is why `make bench` does not fail on
  them; rerun them on a quiet machine.
