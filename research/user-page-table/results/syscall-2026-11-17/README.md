# 2026-11-17 syscall measurements

The final implementation preserves the Asterinas `syscall_dispatch`, `Context`, `Process`, and event-handler interfaces. The changes remove redundant work inside Endovisor and vOSTD. The only `aster-core` change in this experiment fixes wakeup placement after an affinity change, without changing the scheduler's interface.

The primary matched experiment measures Linux at **39.429 ns** and the final full Asterinas Kernelet at **97.270 ns** per `getpid`. The Kernelet baseline in this experiment is **98.989 ns**. The difference between baseline and final medians is **1.718 ns (1.736%)**. These are end-to-end measurements; the remaining **57.842 ns** difference from Linux combines POSIX implementation differences, event handling, and adaptation costs. It is not a measurement of an irreducible Kernelet mechanism cost.

## Measurement contract

Both L and K run under one QEMU/KVM instance per boot. L is an ordinary process in the guest Linux; K is the same executable running as an Asterinas tenant hosted by that Linux. Neither is a physical-host Linux measurement.

| Control | Value or evidence |
|---|---|
| Physical host | AMD Ryzen 7 5800H; host kernel and governor state recorded in each manifest |
| QEMU | 11.1.3, KVM, `-cpu host -smp 2 -m 1024M -mem-prealloc -nic none -machine q35,kernel-irqchip=split` |
| QEMU placement | vCPU 0 on host CPU 10, vCPU 1 on CPU 12, emulator/I/O on CPU 14; distinct physical cores, verified through QMP/TIDs and affinity |
| Benchmark placement | Singleton guest CPU 0 affinity, checked with raw `SYS_getcpu` before and after each timed window |
| Tenant | Direct page tables, 256 MiB grant, two carriers, `exec` attachment |
| Endovisor | `watch=1 audit=0 profile_hz=0` in performance runs; actual module output retained |
| Executable | Byte-identical static C executable for L and K, SHA-256 `718c25c3771a3372f4e9ac71e0663b3cd204c35e57d36dc020ae23666db4f0aa` |
| Timing | 50,000 warmup calls before each of nine windows of 1,000,000 raw `syscall` instructions; `CLOCK_MONOTONIC` and ordered TSC reads outside the loop |
| Summary | Median of nine batch averages per boot; median and range of five independent boot medians per variant |
| Acceptance | Nine ordered valid samples, expected positive PID, CPU 0, positive elapsed time/TSC, successful suite and host teardown, no kernel warning or fault |

The loop includes syscall-number setup and loop control. No empty-loop estimate is subtracted. Clock reads, affinity operations, result printing, and correctness checks are outside the timed loop. These samples do not support single-call p99 estimates. TSC ticks are not physical core cycles. The primary run's observed TSC/monotonic ratio spans 3.193750–3.194214 GHz; the tool rejects disagreement with the guest's reported TSC frequency above 0.2%.

The benchmark uses raw `getcpu` because the existing native Asterinas vDSO path is not a reliable CPU-placement oracle in the earlier experiments. The scheduler fix ensures wakeup does not reuse `last_cpu` after that CPU leaves the allowed affinity. It does not add immediate migration of a running thread: the benchmark yields, blocks if needed, then verifies actual placement. The same affinity fix is present in all K variants.

Host CPUs are pinned, not exclusively isolated. Other host processes, SMT activity, frequency changes, and temperature are not controlled. No within-window migration counter or hardware PMU attribution was collected. All accepted windows, including slower ones, remain in the raw records. Earlier runs on physical CPUs 0/2/4 are retained as diagnostic evidence and are not pooled with the primary 10/12/14 experiment.

## Primary experiment

All variants use the same Linux image, configuration, QEMU settings, benchmark executable, timing protocol, and physical CPU placement. Variant order is shuffled within each round using seed `20261117`.

| Variant | Cumulative changes | Median ns | Range of five boot medians, ns |
|---|---|---:|---:|
| L | Ordinary Linux process | 39.429 | 39.362–39.734 |
| K0 | Full Kernelet baseline with common affinity fix | 98.989 | 98.458–99.379 |
| K1 | K0 + audit-gated return diagnostics | 100.200 | 98.504–100.585 |
| K2 | K1 + cold logging functions | 98.106 | 97.900–98.272 |
| K3 | K2 + task-switch-only `active_pt_regs` publication | 97.351 | 94.081–97.695 |
| K4 | Final image + aligned handoff destinations | 97.270 | 94.127–97.531 |

All 30 boots and 270 windows passed the acceptance checks. [The manifest](final-ab/manifest.json) identifies every input and run order; [records](final-ab/records.jsonl) contain the exact QEMU command, physical placement, and each raw sample. [The summary](final-ab/summary.json) retains all five values per variant.

K1 is slower than K0 in this run. K3 and K4 overlap. The data therefore do not establish a separate speedup for every source change or a fixed time per deleted instruction. K4 also uses a fresh build of the final API-preserving Rust sources, so K3/K4 is not a module-only ablation. Compilation layout and host variation remain part of these measurements. The observed total reduction is the difference of the K0 and K4 medians, not a sum of estimated component savings.

The primary Linux configuration uses `CONFIG_CC_OPTIMIZE_FOR_SIZE=y`, `CONFIG_INIT_STACK_ALL_ZERO=y`, `CONFIG_CPU_MITIGATIONS=n`, `CONFIG_JUMP_LABEL=n`, `CONFIG_STACKPROTECTOR=n`, `CONFIG_X86_KERNEL_IBT=n`, and dynamic preemption. Endovisor's own Makefile adds `-O2`. Both L and K boot with `nokaslr mitigations=off`.

## Matched mitigation experiment

These runs use a separate mitigation-capable Linux build. Within this experiment, **the kernel, configuration, Endovisor module, Rust image, benchmark, and initramfs are byte-identical between `off` and `auto`**. Only the mitigation boot parameter changes. Each group contains five L and five K boots, with the full `smp-syscall-fpu` suite and shuffled L/K order. The two mitigation groups were run sequentially, not interleaved across settings.

| Boot parameter | Linux median ns [boot range] | Kernelet median ns [boot range] | K − L, ns |
|---|---:|---:|---:|
| `mitigations=off` | 37.057 [36.948–37.170] | 94.484 [93.941–98.224] | 57.427 |
| `mitigations=auto` | 93.540 [93.277–93.873] | 144.045 [143.363–144.122] | 50.505 |

All 20 boots and 180 windows passed. Enabling the selected Linux mitigations changes the observed medians by **56.483 ns for L** and **49.561 ns for K**. This is an end-to-end difference between settings, not a decomposition among individual mitigations.

Actual guest `/sys/devices/system/cpu/vulnerabilities/*` values are recorded as `HOST_STATE` in every serial log. In `auto`, Spectre v2 reports retpolines, conditional IBPB, firmware IBRS, and RSB filling; speculative return-stack overflow reports Safe RET; Spectre v1 reports usercopy/SWAPGS barriers and pointer sanitization. STIBP remains disabled. In `off`, the corresponding Spectre v2 and return-overflow entries report vulnerable. Meltdown reports not affected in both groups. PTI is compiled in, but these runs do not establish active PTI and do not request `pti=on`. Linux documents the runtime vulnerability files and mitigation controls in its [Spectre documentation](https://docs.kernel.org/6.12/admin-guide/hw-vuln/spectre.html).

The Rust image is the same in both settings. Its OSDK build uses `-Z cf-protection=branch`; that is not evidence that Rust indirect calls and returns have Linux-equivalent Spectre transformations. Thus this is a matched **Linux-host mitigation** comparison, not proof of equal protection across all Linux C and Asterinas Rust instructions.

This Linux build also uses `-O2` and `CONFIG_INIT_STACK_NONE=y`, among other configuration differences from the primary kernel. The 37.057 versus 39.429 ns Linux results cannot be attributed solely to compiler optimization or automatic initialization. The complete configurations are retained, rather than treating those settings as a single controlled variable.

See [off records](mitigations-off/records.jsonl), [auto records](mitigations-auto/records.jsonl), and their manifests. The mitigation kernel's build receipt matches a recomputed source/toolchain input hash of `a72336b5748c0a5ab12d594b62ea93694841c2722412aa268fd4fa90689ee538`. `inputs-at-verification.json` records the later source check, not the original build time.

## Implemented changes and preserved boundaries

| Location | Current behavior and evidence |
|---|---|
| Endovisor `carrier.c` | The extra SYSRET-eligibility diagnostic is executed only under `endovisor_audit_key`. Linux's final SYSRET/IRET validation and exit work remain. With `CONFIG_JUMP_LABEL=n`, the disabled audit gate still needs a load/branch; it is not claimed to cost zero. |
| Endovisor statistics and runner | Disabled syscall/precheck counters are represented as unobserved, not zero. The runner reports `non_sysret_precheck` only when collected. The UAPI layout is unchanged. A precheck runs before Linux exit work and cannot identify the final return instruction. |
| vOSTD logging | `__write_log_record` and the Kernelet console writer are cold, non-inlined functions. Runtime log-level behavior remains. Disassembly changes the `sys_getpid` local frame reservation from 1,224 to 96 bytes. Disabled logging did not execute buffer initialization before this change; the evidence is reduced frame reservation and code placement. |
| vOSTD `user.rs` | Ordinary event entry no longer reloads the carrier frame pointer and republishes `active_pt_regs`. Existing `after_switching_to` publishes the active frame before execution and moves the outgoing task to its saved frame. The event and initial-entry paths retain debug assertions of this invariant. Migration continues through the existing switch protocol. |
| Endovisor `switch.S` | Five redundant `andq $-16,%rsp` instructions are removed. Event destinations are checked when their identity changes; bootstrap destinations are aligned allocations; all Linux destinations use the carrier's initialized aligned `linux_sp`. The alignment precondition is documented. |
| Asterinas scheduler | `select_cpu(&self, thread: &Thread, flags: EnqueueFlags) -> CpuId` keeps its original signature. Wakeup uses `last_cpu` only when the current affinity still contains it. This is a placement correctness fix, not a claimed hot-path speedup. |
| Asterinas syscall layer | `syscall/mod.rs` is byte-identical to the captured starting source, SHA-256 `99a459881e0d685370fb4d5428ddd78bdf682f689a65472ffd99a2b09ae708a9`. Argument extraction, dispatch signature, POSIX borrowing, and signal/ptrace behavior remain. |

The implementation still contains the following work. Frequencies below describe the ordinary source path, not independently measured nanosecond costs.

| Remaining work | Frequency and reason |
|---|---|
| Linux entry, `pt_regs`, and user return | Every syscall; the host owns entry/exit, return validation, and its carrier task semantics. |
| Endovisor/image handoff and carrier state | One inward and one outward handoff; ownership, pending-event delivery, and exit synchronization remain. |
| Protected CPU-local access | Entry and return use the protected `.text.kernelet_cpu_access` protocol. The removed frame-pointer publication does not remove CPU identity, IRQ, or pending-state requirements. |
| POSIX identity and borrowing | `as_posix_thread`, `Process` borrowing, and `Context` construction remain per event under the preserved Asterinas interfaces. There is no per-event `Process` `Arc::clone/drop` here. |
| Dispatch and tenant semantics | Existing argument extraction, dispatch, ptrace fast checks, pending-signal checks, and preemption decisions remain. Host carrier checks do not establish tenant state. |
| FPU, TLS, address-space work | Actual saves/restores and address-space activation depend on ownership/state changes, task switches, or preemption. They are not automatically charged once per `getpid`. |
| Watch/tick activity and cold failures | Watch activity remains enabled. Error reporting and panic handling retain their correctness roles; no new per-syscall panic object is introduced by these changes. |

These retained operations cannot be deleted solely because Linux has operations with similar names. A deletion needs a state/ownership invariant that covers the tenant as well as the carrier. This audit does not assign a fixed 36/26/12/18 ns split to them.

## Validation and evidence limits

The final image passes the full SMP/syscall/FPU suite in all ten K mitigation runs, plus a final run on the primary kernel. Those checks cover two CPUs, raw CPU placement, GPR preservation, x87/SSE/AVX preservation, same-CPU FPU switching, and valid/invalid `rt_sigreturn` frames. Linux counterparts pass the same suite.

Eight additional [functional cases](validation/) exercise the same handoff, logging, publication, and audit changes: direct and VMA event paths, direct and VMA memory safety, SMP/FPU, lifecycle, audit, and running-tenant kill. The event cases include a six-argument syscall, ptrace register changes/single-step, exceptions, blocking/fork, and exec. Each completes without a host kernel warning/fault; VM create/destroy and grant allocation/free counts balance. The kill case reports killed/exit-code 9 and expected runner status 137. The audit case records 11,774,155 syscall entries and three failed return prechecks; it does not claim three actual IRET returns. These eight cases used the recorded `aligned-handoff` artifact; the final API-preserving build has its own full-suite results.

Strict C compilation (`-O2 -Wall -Wextra -Werror -static -pthread` for user tools), Linux module/objtool builds for both kernels, the Kernelet release build and OSDK audits, targeted Rust formatting/diff checks, and Python syntax checks pass. A real QEMU rejection of the existing native ELF is captured in `tool-rejected-boot/`: the measurement driver saves the partial result as invalid, returns failure, and produces no performance summary. These checks and QEMU/KVM results do not establish bare-metal behavior or every possible asynchronous interleaving.

A fresh native Asterinas release build succeeds, but its direct-boot attempts did not produce an accepted benchmark run. The image and boot-failure logs remain under `native-asterinas/` and `native-*-smoke/`. No new native Asterinas latency is reported. The earlier 50.35 ns figure therefore cannot supply a same-build component estimate for this run, including a subtraction such as `50.35 − 32`.

The [pinned syscall proposal](https://github.com/Plucky923/kernelet/blob/ee1b2267e6178c6afaf22d73ad961f0c227ec8db/book/src/design-proposals/2026-10-31-reduce-syscall-overhead.md) reports 57.5 ns Linux and 63.7 ns for a minimal constant-return Kernelet handler, using means across five boots. This report uses medians of boot medians. The proposal's workload is different from full POSIX `getpid`. Its text does not provide a complete Linux configuration and runtime mitigation record establishing why its Linux result is 57.5 ns. This experiment does not infer those missing settings from the number. A comparable native Asterinas baseline, minimal-handler diagnostic, and instruction-level attribution remain unavailable here.

## Artifacts and reproduction

Artifacts in this directory are retained as the evidence for this research experiment. `verification.json` checks 52 accepted boots and 468 windows across the primary, mitigation, and final tool-validation groups, plus the eight functional cases. `provenance.json` records revisions, toolchains, and source hashes; revisions alone do not describe the pre-existing dirty workspaces.

Run `python3 research/user-page-table/results/syscall-2026-11-17/verify_results.py` from the repository root to recheck raw logs, artifact hashes, CPU placement, clock agreement, summaries, and rejection of the failed boot.

| Artifact | Purpose |
|---|---|
| `final-ab/`, `mitigations-off/`, `mitigations-auto/` | Formal raw logs, manifests, samples, exact driver versions, summaries |
| `tool-validation/` | Final measurement-tool and final-image full-suite check; excluded from five-boot medians |
| `final/` | Final Rust ELF, Endovisor module, initramfs, build log, generated manifests, complete frozen local/registry/git source archive |
| `baseline/` | Primary Linux kernel/configuration, starting binaries and captured sources, pre-existing workspace diffs |
| `matched-baseline/`, `matched-logging/`, `final-publication/` | Intermediate images and frozen workspace sources for interpreting cumulative variants |
| `mitigation-kernel/` | Matched mitigation kernel/configuration/module/initramfs, receipt and source-verification record |
| `sources/` | Final C, Python, selected Rust sources, Linux patch, and configuration fragments |
| `changes-from-captured-sources.patch` | Diffs for files whose starting contents were captured; final sources and frozen archives also cover files outside this patch |
| `validation/`, `native-*-smoke/`, earlier measurement directories | Functional and diagnostic evidence; not pooled into the formal timing tables |

The final Rust image SHA-256 is `73698be97c6a1062c8e00dc178dd60669c919893641ef999a75562b84ab8a9c5`. Primary Linux is `114963b3e3bda3901938272763ec9ec8e8640ad7143865350b5fd310d8fa93df`; mitigation-capable Linux is `62623935fa4e18dbb89a701969ad9d403b62e02511ab5ebf80acbbc5c1de32b3`. Each manifest provides the complete configuration and all remaining binary hashes.

From the repository root, reproduce the final L/K comparison using the retained binaries and an unused output directory:

```bash
python3 poc/linux/bench/measure_syscall.py \
  --kernel research/user-page-table/results/syscall-2026-11-17/baseline/bzImage \
  --config research/user-page-table/results/syscall-2026-11-17/baseline/linux.config \
  --native L=research/user-page-table/results/syscall-2026-11-17/final/initrd.cpio.gz \
  --kernelet K=research/user-page-table/results/syscall-2026-11-17/final/initrd.cpio.gz \
  --output research/user-page-table/results/syscall-reproduction \
  --temp-root research/user-page-table/.syscall-reproduction \
  --boots 5 --suite syscall --host-cpus 10 12 14 --mitigations off
```

The temporary directory must be excluded locally and removed after the run. The driver requires KVM access and GNU `cpio`; it records and sets a process-local memlock soft limit of zero for this QEMU environment. It refuses an existing result manifest and aborts rather than summarizing invalid runs. For the mitigation experiment, use `mitigation-kernel/bzImage`, `mitigation-kernel/linux.config`, and `mitigation-kernel/final-initrd.cpio.gz` for both L/K; select `smp-syscall-fpu` and run each mitigation setting into a separate directory. The original commands and exact shuffled order are also retained in the formal records.
