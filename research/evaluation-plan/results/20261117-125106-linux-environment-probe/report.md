# 2026-11-17 评测前置环境检查

**状态：INVALID；正式性能采集尚未开始。** Linux 客户机未通过方案规定的 vDSO 门禁。物理主机已将 TSC 判定为不稳定，当前不能提供符合方案要求的计时环境。

## 实测结果

| 检查 | 结果 | 证据 |
|---|---|---|
| 现有离线单元检查 | 32 项通过 | `make -C poc/eval test` |
| Linux 配置 | `perf-base`、`perf-pti` 均通过现有配置门禁 | `make -C poc/eval check-configs` |
| 构建与源码一致性 | 未通过：Asterinas 镜像早于当前调度器源码修改 | `existing-build-inputs.json`；`poc/kernel/core/src/sched/sched_class/mod.rs` |
| QEMU/KVM 启动 | Linux 客户机启动成功 | `logs/r0_L.serial.log` |
| 虚拟硬件 | 2 vCPU、2048 MiB、`-mem-prealloc`、`-cpu host` | `vm_runs.jsonl` |
| QMP 绑核 | vCPU 0 → CPU 0；vCPU 1 → CPU 2；I/O 主线程 → CPU 4；分别属于不同物理核心 | `vm_runs.jsonl`、`host-cpu-topology.txt` |
| Linux THP | 策略 `[never]`；`thp_fault_alloc` 增量 0 | `records.jsonl` |
| 用例 CPU 约束 | `cpu_start=0`、`cpu_end=0`、`migrated=false`、`cpu_obs_ok=true` | `records.jsonl` |
| `clock_gettime(CLOCK_MONOTONIC)` | 100,000 次调用触发 100,000 次 syscall | `records.jsonl` |
| `gettimeofday()` | 100,000 次调用触发 100,000 次 syscall | `records.jsonl` |
| vDSO 判定 | `rc=1`；总回退次数 200,000，大于允许上界 0 | `diagnostic.json`、`records.jsonl` |

## 主机时钟证据

主机运行 `7.2.8-9-omarchy`。本次开机的内核日志记录：

```text
TSC synchronization [CPU#0 -> CPU#2]:
Measured 9025100516 cycles TSC warp between CPUs, turning off TSC clock.
tsc: Marking TSC unstable due to check_tsc_sync_source failed
clocksource: Switched to clocksource hpet
kvm: SMP vm created on host with unstable TSC; guest TSC will not be reliable
```

检查时主机的当前 clocksource 为 `hpet`，可选源为 `hpet acpi_pm`，不包含 `tsc`。完整相关日志保存在 `host-clock-journal.log`。

Linux 客户机日志记录 `clocksource: Switched to clocksource kvm-clock`。Linux 6.12 的 `arch/x86/kernel/kvmclock.c:kvm_setup_vsyscall_timeinfo()` 仅在 `PVCLOCK_TSC_STABLE_BIT` 已设置时启用 pvclock vDSO；`arch/x86/include/asm/vdso/gettimeofday.h` 在该标志缺失时要求回退。该源码机制与本次主机日志及客户机 syscall 实测一致，但本次没有直接读取客户机 pvclock 数据页的 flags。

## 证据范围

这是构建前的 Linux 环境诊断。运行前单独验证了 Linux、Endovisor、runner 和 payload 的源码输入及产物 SHA-256 与各自构建记录一致；对应记录保存在四份 `*-receipt.json`。Asterinas 构建记录已过期，因此未将该诊断称为当前源码的 L/A/K 完整自检。`manifest.json` 明确保留 `build_inputs_verified=false`，并保存产物哈希、主机 CPU 信息和配置检查结果；`source_snapshot.tar.gz`、两份 Git diff 与构建输入记录用于追溯当前源码及未提交修改。

门禁在 `selfcheck.vdso` 返回后终止 QEMU，`vm_runs.jsonl` 中的 `qemu_rc=-9` 对应控制器的主动终止。`selfcheck.noop` 未运行，本次也没有验证正常模块卸载流程。

本次没有采集五轮 L/A/K/K_vma 性能数据，没有产生 K/L 或 K/A 性能比值，也没有进行 PTI 对照或 perf 剖析。`mm.sng.cow` 仍为原方案明确保留的 `COVERAGE GAP`。

## 正式采集的前提

必须先取得 TSC 稳定的运行环境，再从当前源码重新构建 Asterinas 和统一载荷，并通过 L/A/K 的两项前置自检。重启后是否恢复 TSC 同步需要实测确认；本次没有重启主机，也没有强制覆盖内核对 TSC 稳定性的判定。

项目指定的 `asterinas/dev:0.19.0-20261012` Docker 镜像已下载，digest 记录在 `build-container-digest.json`。本次仅检查了容器工具，不在该容器中生成新内核或载荷；容器已退出，镜像保留在 Docker 管理的缓存中供后续构建使用。
