# research

这里保存讨论记录、测量计划、测量工具和原始结果。`poc/` 是独立仓库，以子模块记录在本仓库中；换机器时按[迁移说明](evaluation-plan/migration.md)取得对应版本。确定下来的设计仍需整理进 `book/` 或 `prototype/`。

## 目录

- [`api-virtualization/`](api-virtualization/)：API Virtualization 原则提案的决策和审查记录。
- [`evaluation-plan/`](evaluation-plan/)：syscall 与内存管理评测的总体方案、执行计划、迁移说明和结果。
- [`book-design-review/`](book-design-review/)：Accepted Design 的设计问题审查，包括宿主边界、隔离、生命周期和内存成本。
- [`fault-isolation/`](fault-isolation/)：故障模型、隔离要求、宿主状态恢复、资源回收与所有权审查。
- [`memory-allocation/`](memory-allocation/)：固定 grant 内的内存分配讨论和宿主堆设计理由。
- [`user-page-table/`](user-page-table/)：用户页表管理的决策、相关工作、源码审查、实验计划、原始结果和 Cooperative Linux 论文。
- [`mem-baseline/`](mem-baseline/)：Linux 内存操作基线计划、测量工具和五次启动的结果。

## 参考源码

仓库根目录下的 `reference/` 不纳入版本控制，用于存放只读的参考源码：

| 目录 | 内容 | 来源 |
|---|---|---|
| `reference/linux-6.12` | 未打补丁的 Linux 6.12，和原型使用的版本相同 | `https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.tar.xz` |
| `reference/asterinas` | Asterinas，检出在书和原型引用的提交 `ab9a4cfdc726263b3f41ccea0337633e24b443fc` | `https://github.com/asterinas/asterinas`，用 `--filter=blob:none` 克隆（有完整的提交历史，文件内容按需下载） |

打过 kernelet 补丁的 Linux 在 `prototype/.build/linux-6.12`，那是构建用的目录，不要拿来当参考。

## 当前状态（2026-11-16）

- 已决定方案 B（vOSTD 直接写用户页表）作为主方案，batching 作为 alternative（`user-page-table/decisions.md` 中的 U7）。
- 已完成 B5 审查（`user-page-table/b5-audit.md`）以及面向 `2026-11-13-direct-page-table-updates-in-vostd.md` 的完整实验计划（`user-page-table/experiment-plan.md`，替代 `mem-baseline/plan.md` 中的初版测量草稿）。
- 当前先逐项讨论固定 grant 内的基础内存分配，记录在 [`memory-allocation/decisions.md`](memory-allocation/decisions.md)。grant 扩容和运行时归还暂缓；原有的 256 MiB 分块 grant 与页表实验计划保留。
- 已完成[当前宿主堆的理由调研](memory-allocation/linux-heap-rationale.md)，并建立[从 grant 分配 kernelet 堆的提案草稿](../book/src/design-proposals/2026-11-16-allocate-the-kernelet-heap-from-the-grant.md)；具体分配机制仍待讨论。
- 已补充 [syscall 归因与优化讨论计划](user-page-table/experiment-plan.md#6-syscall-开销归因与优化讨论)：区分虚拟机内 Linux、原生 Asterinas、最小 Kernelet 处理器和完整 Kernelet 四组对照，补齐绑核证据要求，并列出 O1–O12 的候选、预测和不变量。候选选择待讨论，本轮未实现优化或重跑实验。
- 已确定[实验与评测框架总体方案](evaluation-plan/README.md)及[执行计划](evaluation-plan/execution-plan.md)。`poc/eval/` 已有框架实现和离线检查；当前主机的 TSC 与 Linux 客户机 vDSO 自检未通过，尚未开始五轮正式采集。`stress-ng` 不提供该方案所需的大地址空间 `fork + COW` 用例，这项覆盖缺口需要保留。
- 已建立 [API Virtualization 原则提案讨论记录](api-virtualization/decisions.md)：对照 `kernelet-book` 与现有各项提案，按 S1–S5 逐段讨论并打磨 [`2026-11-16-principles-of-api-virtualization.md`](../book/src/design-proposals/2026-11-16-principles-of-api-virtualization.md)，当前从 S1（Summary 与 Problem & motivation）开始。
