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
ordinary out-of-tree module apart from the gate, a patch to Linux that adds
210 lines (188 of them not blank) and removes none, most of them in the generic
entry code and `kernel/fork.c`. The kernelet runtime is the user-space program
that creates a sandbox, by exec'ing a `.klet` file that the
endovisor's binary-format handler turns into the sandbox's root carrier.

Each directory has a `README.md` saying what is in it.

## Building and running

### What it needs

- **Linux on x86-64 with KVM**, and QEMU's `qemu-system-x86_64`, found on
  `PATH` (or named with `make QEMU=/path/to/qemu-system-x86_64 ...`). The
  options the boots use (`-enable-kvm -cpu host`, `-kernel`/`-initrd`,
  `-serial file:`, a raw virtio drive) are old; QEMU 6.2 (Ubuntu 22.04's) and
  10.0 have both been tested. A QEMU that does not start fails the boot with a
  message saying so. The guests use two CPUs and 512 MiB.
- **Rust** through `rustup`: `rust-toolchain.toml` names the nightly
  (`nightly-2026-07-21`, with `rust-src` and the `x86_64-unknown-none`
  target), and `rustup` installs it on first use. The image is built with
  `-Zbuild-std` for `x86_64-unknown-none`.
- **What the build needs**: `gcc` with a static C library, including the
  static `libpthread` (`libc6-dev` on Debian and Ubuntu, `glibc-static` on
  Fedora), because the runtimes and `init` are linked `-static`; `make`,
  `patch`, `flex`, `bison`, `bc`, `perl`, the `libelf` headers (objtool),
  binutils (`ld`, `objcopy`, `readelf`, `nm`), `tar`, `xz`, `gzip`, `curl`,
  `python3`, GNU coreutils (`timeout`, `truncate`, `stat`), GNU findutils
  (the initramfs list is written with `find -printf`), `cmp` (diffutils, for
  `kernel-proper-check`), and `mkswap` for `make mem-pressure`.
- **No root.** Nothing is installed, and the initramfs is written by the
  kernel's own `usr/gen_init_cpio` from a file list, so its `/dev/console`
  node needs no `mknod`. QEMU needs read and write access to `/dev/kvm`.
- **Disk**: the unpacked and built kernel tree takes 1.8 GB under `.build/`,
  the Rust build about 230 MB, the logs and the 512 MiB sparse swap file of
  `make mem-pressure` about 120 MB. Two steps refuse to start with less than
  6 GiB free on the filesystem `.build/` is on (`MIN_FREE_GB`): the download
  and unpacking of the tree (`make source`, or the first `make linux`), and
  `make linux` while the tree has no `bzImage` or `Module.symvers` yet. Once
  the kernel is built, no target checks the free space, and a boot needs a
  few megabytes.
- **Variables** a user may set: `QEMU` (above), `JOBS` (parallel jobs for the
  Linux and module builds, default 8), `TIMEOUT` (seconds a boot may take
  before QEMU is killed, default 120, raised by the tests that need longer)
  and `MIN_FREE_GB` (default 6).

### From a fresh clone

```sh
make crates   # once, online: the Rust crates of Cargo.lock and of -Zbuild-std
              # (the first build does this itself if the registry lacks them)
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
measured), and `make bench` about the same (about 200 s: eight boots of the
sched kernel and five of the mem kernel). Every build is `--offline`, so
nothing after the crates and the one download needs the network; an offline
build that finds a crate missing says to run `make crates`.

`make test` runs, in order, and stops at the first failure: `hello`, `probe`,
`yield`, `sched-policy`, `sched-coop`, `sched-fpu`, `mem-func`, `mem-r2`,
`mem-conc`, `mem-kill`, `mem-pressure`. It prints one line per test; each
test's whole output is in `.build/test-<name>.out`. `make bench` runs
`sched-fair`, `sched-perf` and `mem-perf` and prints their tables; their
assertions depend on the host being quiet, so they are reported and never
fail the suite. Each one's boots go to `.build/bench/<name>.out`, and its
check, run once after them, to `.build/bench/<name>.table`, which ends with
the verdict, `PASS` or `FAIL`.

## The targets

| target | what it does | chapter |
|---|---|---|
| `make test` | the eleven tests below, in order | – |
| `make bench` | `sched-fair`, `sched-perf`, `mem-perf`, reported | 14 |
| `make hello` | the 100-line kernel, byte-identical to `hello/upstream/`: "Hello, world", a clean stop, a clean module unload; also the one-off measurement of what a service costs ("service stub: N cycles") | 2, 3, 6, 7 |
| `make probe` | demand paging, three non-page-fault exceptions (`ud2`, trap 6; `int3`, trap 3; `hlt`, trap 13, a general-protection fault), and eviction of a kernelet spinning in kernel mode when the sandbox is killed | 7, 11, 12 |
| `make yield` | two boots under `preempt=none`, the watch timer off (the competitor starves) and on (it does not, and the checksums agree) | 9, 10 |
| `make sched-policy` | the kernelet's own scheduler: its trace checked against a reference model | 8 |
| `make sched-coop` | three boots: the mirror on (no involuntary deschedule in a critical section), off (the control), and an overstayer forced to yield at the first tick at least a millisecond after the first strike, about 2 ms on this machine (the check allows 4000 us, because a late tick lengthens it) | 10 |
| `make sched-fpu` | floating-point registers of two tenant threads in two address spaces survive every switch | 8 |
| `make mem-func` | E2, E3, E4, E10: no Linux fault on mapped pages, fault-around, protection changes, a map under a guard, the withheld set | 12, 13 |
| `make mem-r2` | E5: the sleeping contract, broken on purpose, ends the kernelet | 13 |
| `make mem-conc` | E8, E11 on two vCPUs: lockless copies, the contended range lock, a process exiting under a copy, the retire list | 13 |
| `make mem-kill` | E11 and the carriers as Linux tasks: one carrier of a two-thread process is preempted by a competitor, sent SIGTERM and SIGUSR1 (it lives), stopped and continued, and killed while its sibling faults in the same address space; the kill ends the whole sandbox cleanly. Its tenant runs the rewind check meanwhile: a register count and a memory count that must never part. Then two short boots, the carrier of vCPU 1 killed while it is idle in `vcpu_idle` and while it runs a kernel task that calls no service: each kill must end the sandbox within two seconds | 7, 11, 12 |
| `make mem-pressure` | E7: the area's entries survive reclaim and swap | 12 |
| `make sched-fair` | measurement: a sibling group's share of the processors with 1, 50, and 50 tasks and an overstayer | 10, 14 |
| `make sched-perf` | measurement: a kernelet task switch, a wake-up on the same and on the other vCPU, and a round trip between two tenant processes, beside native Linux, five boots; fails if a kernelet measurement has no samples | 14 |
| `make mem-perf` | measurement: E6 and E9, the memory costs, five boots | 14 |
| `make sched`, `make mem` | the sched tests (`sched-policy`, `sched-coop`, `sched-fpu`); the mem tests (`mem-func`, `mem-r2`, `mem-conc`, `mem-kill`, `mem-pressure`). The measurements are `make bench`'s | 8, 10, 12, 13 |
| `make crates` | download the Rust crates, once | – |
| `make source` | download and unpack Linux v6.12 if `.build/linux-6.12` is not there, and apply the gate patch | 4 |
| `make patch` | apply the gate patch; idempotent | 4 |
| `make linux` | configure (once, from `linux/config.fragment`; `make config` does only that) and build `bzImage`, `modules` (which writes the tree's `Module.symvers`, without which no out-of-tree module links) and `modules_prepare` | 4 |
| `make image` | build vOSTD and the kernel proper named by `KLET_KERNEL` (`hello`, `probe`, `yieldk`, `schedk`, `mem`) and pre-link the image | 3 |
| `make kernelet-module` | the image, then `endovisor/kernelet.ko` | 3 |
| `make runtime`, `make initramfs`, `make run` | the runtimes; the initramfs from `.build/stage`; one boot | 5, 7 |
| `make clean` | remove the harness's artifacts: the image and module, the runtimes, the staging area and the initramfs, the Rust build, every log and test output. It leaves the Linux tree, its build, the Cargo registry and `.build/crates.stamp` (which says the registry has the crates) | – |
| `make distclean` | `clean`, then `make mrproper` in the Linux tree, which removes its build and its configuration (`.config`, `include/generated`). It leaves the unpacked source, the gate patch applied to it and the patch's stamp, so the next `make linux` configures and builds again but neither downloads nor patches | – |

Internal targets, which the ones above call: `all` (`linux initramfs`),
`module DIR=<dir>` and `stage-module DIR=<dir>` (an out-of-tree module, built
against the tree and staged), `kernel-proper-check` (the `cmp` of `hello/`
against `hello/upstream/`, before every `make hello`), `df-guard` (the free
space check above), and the `stage-*`, `*-boot` and `check-*` targets.

## Module parameters

The endovisor takes four, which the tests set through the initramfs's
`/modules/order`:

| parameter | default | what it does | used by |
|---|---|---|---|
| `klet_watch` | 1 | the per-processor watch timer: the kernelet's tick, the delivery of virtual interrupts into kernelet code, and the two-tick bound on a critical section | `make yield` (0 for the control boot) |
| `klet_mirror` | 1 | vOSTD mirrors its guard depth into Linux's preemption count, so that Linux does not deschedule a carrier in a kernelet critical section | `make sched-coop` (0 for the control boot) |
| `klet_test_hooks` | 0 | the test hook: a `vm_map` carrying `KLET_PROT_TEST_SLEEP` sleeps in Linux | `make mem-conc` (1) |
| `klet_test_sleep_ms` | 20 | how long such a `vm_map` sleeps, in milliseconds | – |

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
| `mem-*` | `.build/mem/<name>.log` (`func`, `r2`, `conc`, `kill`, `kill-idle`, `kill-spin`, `pressure`, `perf-1` ... `perf-5`) |

A check fails on any `BUG:`, `Oops`, `WARNING:`, `Call Trace` or `switching
to a task already running` (vOSTD's report of a scheduler handing it a task
that is still running elsewhere) in the log, on a missing line it expects,
and on an unclean module unload: init's `delete_module kernelet failed`, or a
log without the endovisor's `kernelet: STATS` line or init's `INIT: done`.
The endovisor prints its counters when it unloads (`STATS`, `MEMSTATS`, the
watch timer's ticks and upcalls), the last thing the endovisor prints; init's
`INIT: done` and Linux's power-off follow.

## Signals, stops and memory

- **Signals.** A signal whose default action is to end a task without a core
  dump (`SIGHUP`, `SIGINT`, `SIGTERM`, `SIGUSR1`, `SIGUSR2`, `SIGALRM`,
  `SIGPIPE`, `SIGIO`, `SIGPROF`, `SIGVTALRM`, `SIGSTKFLT`, `SIGPWR` and the
  real-time signals) is ignored by every carrier: the endovisor sets them to
  `SIG_IGN` when the root carrier execs the `.klet` file, and the vCPU
  carriers inherit it. Otherwise Linux would kill the carrier the moment
  such a signal was sent, before the endovisor ever saw it. Every other
  signal is drained by the endovisor on the carrier's way to user mode. A
  fault signal Linux raised for the tenant's own instruction becomes the CPU
  exception the kernel proper sees: `SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGFPE`
  and `SIGTRAP` with a fault's `si_code`, and `SIGSEGV`, `SIGBUS`, `SIGTRAP`
  and `SIGFPE` with `SI_KERNEL`, which is how Linux reports #GP, #TS, #NP,
  #SS, #BP and the legacy #MF. The rest are dropped, except two. `SIGKILL` is
  Linux's, and kills the carrier. `SIGSTOP` stops a vCPU carrier the way it
  stops any task, and **a stopped carrier is a stopped virtual CPU**: the
  kernelet's tasks on it do not run, a sibling vCPU waiting for one of them
  waits, until `SIGCONT`. The root carrier never returns to user mode and
  cannot stop; it drops `SIGSTOP`.
- **Losing a carrier ends the sandbox.** When any carrier dies while the
  sandbox is live, killed by an operator or by the OOM killer, the endovisor
  kills the rest and evicts whatever is still running kernelet code: a
  sandbox that has lost a virtual CPU would otherwise run on with the others
  spinning on whatever locks the lost one held.
- **A `SIGKILL` to a carrier ends the sandbox wherever the carrier is.** Linux
  acts on it only on the way to user mode, so the endovisor covers the other
  places. In user mode, Linux kills the carrier, and its death ends the
  sandbox. Asleep in a service (`vcpu_idle`, `vm_wait`, a waiting boot) or
  running one, the sleep is killable, and on the way out of every service
  (`klet_svc_body`) a pending fatal signal ends the sandbox and the stub
  leaves the kernelet for good instead of returning into it. Running kernelet
  code, the watch timer's next tick finds the signal and evicts the carrier,
  which then dies. The last needs `klet_watch=1`: with the watch timer off, a
  carrier that loops in kernelet code without calling a service cannot be
  reached until something else ends the sandbox.
- **An idle virtual CPU is not load.** A carrier asleep in `vcpu_idle`, or
  waiting to be booted, sleeps with `TASK_NOLOAD`, so it does not count in
  the host's load average.
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
- `make sched-fair` and `make sched-perf` can fail on a busy host. The
  common `sched-fair` failure is the spread: the check wants the sibling
  group's share to be the same, within 3%, whether the sandbox runs 1, 50, or
  50 tasks and an overstayer, and a busy host moves it by a few percent (3.1%
  has been seen). The rarer one is the share itself, outside 0.90 to 1.10 of
  a processor (0.8 has been seen). `sched-perf` fails on a busy host when its
  native reference, the round trip between two Linux processes, has no
  samples; a kernelet measurement without samples fails it too, but that is a
  fault of the scenario, not noise. They are measurements, which is why `make bench` does not
  fail on them; rerun them on a quiet machine.
