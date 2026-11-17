# Kernelet 实验执行计划

- 日期：2026-11-17
- 范围：按 [实验与评测框架总体方案](README.md)，比较 Linux、原生 Asterinas 和 Kernelet 的 syscall 与内存管理开销。
- 状态：**正式采集尚未开始**。当前主机的 TSC 同步检查与 Linux 客户机的 vDSO 自检未通过；现有 Asterinas 镜像与当前源码不一致。

## 已有证据

| 项目 | 当前结果 | 证据 |
|---|---|---|
| 离线检查 | `poc/eval` 的 32 项单元检查通过；`perf-base` 和 `perf-pti` 配置门禁通过 | [Linux 环境诊断报告](results/20261117-125106-linux-environment-probe/report.md) |
| 主机时钟 | 启动时 Linux 检测到 CPU 0 与 CPU 2 间最大 TSC 倒退为 9,025,100,516 个周期，标记 TSC 不稳定并改用 HPET | [内核日志](results/20261117-tsc-diagnosis/kernel-time.log) |
| 当前 CPU 间偏差 | 两次只读测量相隔约 57 秒，CPU 0 均比参考 CPU 1 落后 531,524,932 个周期，约 166 毫秒；其余 CPU 在这两次测量中相差不超过 16 个周期 | [第一次](results/20261117-tsc-diagnosis/tsc-measure-1.txt)、[第二次](results/20261117-tsc-diagnosis/tsc-measure-2.txt) |
| CPU 能力 | CPU 0 和 CPU 2 的 CPUID 均报告 invariant TSC，未报告 `TSC_ADJUST` | [CPU 0](results/20261117-tsc-diagnosis/cpuid-cpu0.txt)、[CPU 2](results/20261117-tsc-diagnosis/cpuid-cpu2.txt) |
| Linux 客户机 vDSO | `clock_gettime` 与 `gettimeofday` 各调用 100,000 次，各发生 100,000 次 syscall；该次记录为 `INVALID` | [自检记录](results/20261117-125106-linux-environment-probe/records.jsonl) |
| 构建一致性 | Asterinas 的构建记录早于当前 `poc/kernel/core/src/sched/sched_class/mod.rs` 修改，必须重建并重新验证 | [构建输入记录](results/20261117-125106-linux-environment-probe/existing-build-inputs.json) |

启动时的约 90 亿周期和当前的约 5.3 亿周期是不同时间的观测；目前没有证据解释二者变化。一次启动日志和两次只读测量能够确认 TSC 存在偏差，不能单独证明偏差形成的具体机制或长期稳定性。相同型号、CPU 和 BIOS 的其他用户也报告过启动时 TSC 同步失败，但该报告不能证明本机固件中的具体缺陷：[CachyOS issue #925](https://github.com/CachyOS/linux-cachyos/issues/925#issuecomment-5221924605)。

## 1. 恢复并验证实验环境

1. 保存当前主机的内核版本、启动参数、CPU 拓扑、时钟源、TSC 相关日志及只读测量结果。已有原始记录保存在 `results/20261117-tsc-diagnosis/` 和 `results/20261117-125106-linux-environment-probe/`。
2. 排查启动时 CPU 间计数偏差的来源。区分固件启动状态、内核同步检查和运行期间的变化；对每一项结论记录可复现的证据。若需要重启，先取得明确授权，并保存重启前的工作；重启本身不能保证问题恢复。
3. 使用正常启动的主机验证时钟：检查当前与可用 clocksource、内核 TSC 日志和各 CPU 间只读测量。重复测量应包括准备分配给 QEMU 的 CPU，并记录时间、CPU 亲和性、测量方法和误差。不得通过 `tsc=reliable` 等参数跳过检查来宣称 TSC 已同步。
4. 只有主机不再报告 TSC 不稳定、内核正常选择 TSC，并且本次用于实验的 CPU 没有观测到显著跨核偏差，才进入客户机自检。若本机无法满足条件，使用满足相同条件且可访问 KVM 的另一台主机，并在结果中记录硬件和软件差异。

可用以下只读命令记录主机状态：

```bash
uname -a
cat /proc/cmdline
cat /sys/devices/system/clocksource/clocksource0/current_clocksource
cat /sys/devices/system/clocksource/clocksource0/available_clocksource
journalctl -k -b --no-pager -g 'tsc|TSC|clocksource'
lscpu -e=CPU,CORE,SOCKET,ONLINE
```

## 2. 重建并核对产物

1. 固定主仓库与 `poc/` 的提交、未提交修改、编译器、依赖版本和 Linux 配置。保留已有工作，不覆盖用户源码。依据 `poc/AGENTS.md` 使用指定的 Asterinas 构建容器，并确保 Docker、KVM 和构建目录可用。
2. 核对 Nix 载荷中 LMbench、will-it-scale 和 stress-ng 的来源及版本；LMbench 的计时观察补丁需要记录，不能把补丁后的计时结果描述为完全未修改的二进制。核对补丁是否改变计时语义，并在报告中说明。
3. 使用当前源码重新构建原生 Asterinas、Kernelet、Linux 性能内核、Endovisor 和单一测试载荷；检查构建收据、配置和产物 SHA-256。三个被测环境必须使用同一份载荷。若 `poc/eval` 的构建入口与上述要求不一致，先修复或明确阻塞，不能绕过新鲜度门禁。
4. 运行与改动相称的离线检查及配置检查：

```bash
make -C poc/eval test
make -C poc/eval check-configs
make -C poc/eval check-freshness BUILD_PTI=1
```

`check-freshness` 需要在完成重建后执行，并使用与构建收据相匹配的工具链环境。

## 3. 三端前置自检

运行 `make -C poc/eval selfcheck`，检查 `L`、`A`、`K` 三端各自的 `selfcheck.vdso` 和 `selfcheck.noop`。构建模式和工具链需与上一节核对后的环境一致。

验收条件：三端都实际执行两个用例且返回成功；两种时间查询各执行 100,000 次时都没有回退 syscall；允许 CPU 集合、THP 策略与分配增量、载荷哈希和沙盒退出后的资源回收均通过门禁。记录 QEMU 启动命令及 QMP 获取的线程与物理核心绑定关系。

任一条件失败时，保存该次原始日志和失败原因，结果标记为 `INVALID`，停止正式计时。根据实际失败位置修复后重新执行完整自检；不可把诊断性数据并入正式汇总。

## 4. 正式数据采集

1. 使用同一台已通过检查的主机，按总体方案运行 `L`、`A`、`K` 和 `K_vma`：每个目标、每个用例执行五轮；每轮以固定种子打乱目标顺序。QEMU 固定为 2 vCPU、2048 MiB、`-mem-prealloc`，Kernelet 固定为 512 MiB Grant；每个 Kernelet 用例使用新沙盒。
2. 执行 `make -C poc/eval run TARGETS=L,A,K,K_vma ROUNDS=5`。每轮保留串口原文、结构化记录、构建清单、`.config`、CPU 绑定、源码及产物哈希。若门禁失败，保留无效记录和失败原因，排查后从完整自检重新开始，不能将不完整轮次用于比值。
3. 对每个有效序列报告五轮的中位数、均值和 `[min, max]`，并计算同一用例的 `K/L`、`K/A`。解释时分别考虑延迟和吞吐的方向，不将五轮结果描述为单次 syscall 的 p99。
4. `mm.sng.cow` 保持 `COVERAGE GAP`；没有可靠的第三方大地址空间 `fork + COW` 用例时，不称作全场景覆盖。

## 5. 计数器审计与剖析

正式计时之后，在独立轮次执行 `make -C poc/eval audit`，按用例保存并校准 `STATS_JSON`。对显著差异先检查 syscall、缺页、TLB flush、中断和资源回收，再选择需要剖析的用例。

使用同一批已冻结产物，在单独的宿主机 `perf kvm` 轮次检查 Linux、Endovisor、vOSTD 和 `aster-core` 的符号与调用路径。核对宿主 `perf`、权限、内核符号、模块节地址和 Kernelet 映像基址；缺少任何必要信息时保留原始结果并说明无法符号化的范围。PTI 对照属于独立配置，只有两侧使用对称配置并通过同样自检后才进行比较。

## 6. 交付与完成条件

结果保存在 `research/evaluation-plan/results/<运行标识>/`：包含环境与版本清单、源码和配置记录、原始串口日志、结构化记录、无效项原因、五轮汇总和可复现命令。报告须区分实测、源码推断和未完成项目；保留 COW 覆盖缺口与任何未通过的门禁。只有三端自检、五轮有效采集和相应完整性检查全部通过，才能称为完成基线评估。
