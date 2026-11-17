# API Virtualization 原则提案：逐段讨论与决策记录

开始日期：2026-11-17。这里逐段讨论并打磨设计提案 [`2026-11-16-principles-of-api-virtualization.md`](../../book/src/design-proposals/2026-11-16-principles-of-api-virtualization.md) 的结构、核心论断与措辞，记录每轮确认结果，供后续整理进提案定稿、Accepted Design 以及论文相应章节。

状态标记：**已决定**（用户确认的选择）、**事实依据**（已核对的源码、提案或历史文档事实）、**待讨论**（当前或待展开的段落）。

---

## 已决定

| 编号 | 日期 | 决定 |
|---|---|---|
| U1 | 2026-11-16 | **维持三分类，不增设第四分类**：继续沿用 `Absent` / `Identical` / `Virtualized` 三分法；原版 OSTD 因未面向虚拟化设计而产生的耦合或边界缺失，作为虚拟化层对接口的修正/解耦归并进虚拟化讨论中。 |
| U2 | 2026-11-16 | **`Virtualized` 细分为 `Not crossing` 与 `Crossing`**：需要为这两者的切分提炼出明确的判定原则。 |
| U3 | 2026-11-16 | **原则必须足够 high-level**：面向架构与论文抽象层面提炼原则，不把具体实现细节（如 `Grant`、`IoPort`、`pt_regs`）写死在原则定义里。 |
| U4 | 2026-11-16 | **新建设计提案**：已创建 [`2026-11-16-principles-of-api-virtualization.md`](../../book/src/design-proposals/2026-11-16-principles-of-api-virtualization.md) 并在 `SUMMARY.md` 注册，已通过 `make check` 与 `make build`。 |
| U5 | 2026-11-17 | **逐段讨论打磨**：按段落顺序逐一审视并确定写法，所有讨论过程和定稿决策均记录到本文件。 |
| U6 | 2026-11-17 | **从第一性原理推导**：提案的逻辑主线不从“批判/修补 `kernelet-book` 或 `Accepted Design`”出发，而是从多租户 framekernel 的基本事实与核心目标出发进行第一性原理推导；既有设计与各 companion proposals 仅作背景参考、对比印证与经验校验。 |
| U7 | 2026-11-17 | **控制信息密度（每层最多三点）**：去掉冗余的事实/义务编号清单，全篇收束为“**一个前提 + 三条原则**”，每层核心论点、分类维度与条件均控制在三条以内。 |
| U8 | 2026-11-17 | **S1 定稿**：`Summary` 与 `Problem and motivation` 采用“一个前提 → 两个根源误区（VM-exit 惯性过度跨界、机械照搬裸机接口形态）→ 既有设计与提案数据仅作注脚”的推演结构。 |
| U9 | 2026-11-17 | **S2–S3 定稿（核心理论框架）**：收敛为**两条原则**（OSTD 裸机解耦作为并入 Virtualization 的简短前提，不再单列第三原则）。总纲为**将“安全保护（Protection）”与“多路复用（Multiplexing）”解耦**：原则 1 按语义归属与复用耦合划分为 `Absent` / `Identical` / `Virtualized`；原则 2 规定安全保护在 `vOSTD` 本地闭环，`Crossing` 只发生在宿主“多路复用单元”（及跨故障域生命周期）的创建、切换、跨核同步与回收边界上。 |
| U10 | 2026-11-17 | **S4–S5 定稿（严格校对的映射表与收尾）**：在子系统对照表中增设 `Multiplexing unit` 列并标明其反映各配套提案落地后的目标架构，逐项核实每个 OSTD/vOSTD 符号归属；`Alternatives`、`Integration` 与 `Validation`（含 `BDR-01` 等本地安全检查提醒）均控制在每层 3 点以内。 |
| U11 | 2026-11-17 | **全文复审 R1–R6 全部采纳**：明确按操作/路径粒度分类以覆盖快慢路径复合原语（`SpinLock`、`Task`、`CursorMut::unmap`），补齐 `Boot, Log & Panic` 行，区分核心 `ostd` 上游化与上层 `TypedIO` 前端并存，统一 TCB 表述与并列句式，移除背景框内项目论点及唯一 `>` 块引用，并对齐 `Affected chapters`。 |

---

## 事实依据

以下事实已从仓库及 [`tatetian/kernelet-book`](https://github.com/tatetian/kernelet-book) 核对：

| 编号 | 事实 | 依据 |
|---|---|---|
| F1 | `kernelet-book` 已提出 `Identical` / `Virtualized` / `Absent` 三分类，其 72 项分类表中 26 项 `Identical`、38 项 `Virtualized`（其中 22 项注记 *never cross into the host*）、7 项 `Absent`、1 项内部项；但仅从“对调用者局部 vs. 触及全机状态”作经验描述，未给出 `not crossing` vs. `crossing` 的设计准则。 | `kernelet-book`: `src/blueprint/overview/api-virtualization.md`、`src/blueprint/asterinas-mode/virtualizing-ostd/README.md`、`src/blueprint/linux-mode/virtualizing-ostd/README.md` |
| F2 | 本仓库 `Accepted Design` 仅在 [Why a kernel of your own](../../book/src/accepted-design/why-a-kernel-of-your-own.md#the-same-kernel-a-different-framework) 一笔带过“触硬件的进宿主、无害的留本地”，并在 [What it costs](../../book/src/accepted-design/what-it-costs.md#the-crossing) 测得空服务调用 36 cycles。 | `book/src/accepted-design/why-a-kernel-of-your-own.md`、`what-it-costs.md` |
| F3 | 本仓库早期设计与原型把大量高频/实例内状态操作推过服务表，导致严重性能退化与执行上下文冲突：逐页 `vm_map`/`vm_protect` 引发 `mmap_lock` 与双次遍历（64 MiB `fork` 7.85 ms vs. 原生 0.34 ms）并引入 Rule 2 与 `retire` 问题；逐对象 `mem_alloc`/`mem_free` 耗时 449 cycles/对且违背 SpinLock 非睡眠约束；FPU staging 每次 syscall 增加 ~330–340 ns、移除后线程切换降 34.3–38.1%。 | [Direct PTE](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md)、[Grant Heap](../../book/src/design-proposals/2026-11-16-allocate-the-kernelet-heap-from-the-grant.md)、PR #7 |
| F4 | 原版 OSTD 面向裸机设计，部分接口耦合了裸机假设或缺乏不信任输入边界：`UserMode::execute` 假定内核栈跨用户态挂起（改为 `UserEventHandler` 后 syscall 从 125.1 ns 降至 63.7 ns）；`FpuContext` 缺少导入校验（需 `FpuContext::read_from`）；`IoMem` 迫使虚拟设备走寄存器模拟（改为 `TypedIO` 类型化协议与共享管道）；非睡眠分配与可睡眠扩容/打开需要分离。 | PR #3、PR #5、[TypedIO](../../book/src/design-proposals/2026-11-08-typed-io.md)、PR #4、PR #7 |
| F5 | 审查指出不能把需要 vOSTD 保障的安全不变量外包给可失败的 safe `kernel proper` 约定（如 `BDR-01` 依赖注入调度器不跨 vCPU 迁移任务、`BDR-03` 守卫上下文与 `retire` 进度矛盾）。 | [book-design-review/README.md](../book-design-review/README.md) |

---

## 逐段讨论路线图

| 段落 | 对应章节 | 状态 | 核心讨论问题 |
|---|---|---|---|
| **S1** | Summary 与 Problem and motivation | **已决定（U7, U8）** | 一个前提 + 两大误区（过度跨界、裸机接口耦合）+ 既有设计作注脚 |
| **S2** | 原则 1（三分类与裸机解耦） | **已决定（U9）** | 仅两条核心原则；三分类按语义归属与复用耦合，OSTD 解耦简短并入虚拟化 |
| **S3** | 原则 2（`Not crossing` vs. `Crossing`） | **已决定（U9）** | 保护与多路复用解耦：保护在 `vOSTD` 本地闭环，跨界仅发生在宿主多路复用单元边界 |
| **S4** | 子系统映射表 & 演进收口 | **已决定（U10）** | 增加 `Multiplexing unit` 列，标明目标态口径并逐项核实符号归类 |
| **S5** | Alternatives, Integration, Validation | **已决定（U10）** | 3 条 Alternatives、3 个 Accepted Design 落点、3 项 Validation（含本地不变量安全检查） |

---

## S1：Summary 与 Problem and motivation（已决定，2026-11-17）

按照决定 **U6、U7、U8**，S1 确定为“**一个前提 + 两大误区 + 经验注脚**”：

- **一个前提**：在 kernelet 中，安全隔离靠语言边界将不可信但内存安全的 `kernel proper` 约束在受信任的 `vOSTD` 接口内；`vOSTD` 与宿主同属 TCB、共享内核地址空间，而多租户共享物理机且任一沙箱随时可能非协作终止。
- **两个误区（Problem）**：
  1. **沿用机器虚拟化惯性**：将“受信任接口内的特权操作”推过宿主服务表，混淆信任边界与协调边界，破坏效率、锁/睡眠契约与整块回收性；
  2. **机械照搬单机框架形态**：把耦合了裸机执行或硬件传输假设的 API 原封不动当作虚拟化目标，在边界被迫做昂贵适配或遗漏输入校验。
- **现有设计与提案的定位**：仅作为背景参考与具体实证注脚，不作为逻辑起点。

---

## S2–S3：两条核心原则定稿（已决定，2026-11-17，U9）

### 核心总纲
传统机器虚拟化把**安全保护（Protection）**与**多路复用（Multiplexing）**锁死在同一道陷入边界上；而 API 虚拟化借语言边界与可信 `vOSTD` 把保护本地化，从而使 `vOSTD → 宿主` 边界只负责多路复用与跨域协同。

1. **原则 1（三分类：按语义归属与复用耦合划分）**
   - **Absent**：治理全局物理拓扑而非单租户的能力，编译期从命名空间抹除（静态完成保护）；
   - **Identical**：完全封闭在实例已获资源内、守恒上下文契约且可无析构整块回收的逻辑，原样复用；
   - **Virtualized**：语义属租户，但必须对接物理执行、地址空间调度或外部共享资源的原语，保留契约并重绑定到单实例作用域。
   - *(附注，并入本节：若原版单机框架将 OS 语义与裸机假象绑死或遗漏入口校验，先在接口层解耦，再落入上述三类，不新增第四类。)*

2. **原则 2（`Not crossing` vs. `Crossing`：只在宿主多路复用单元边界跨界）**
   - **安全保护在 `vOSTD` 本地闭环，绝不为此跨界**；`vOSTD` 只在创建、切换、跨核同步或回收宿主**多路复用单元**（及跨故障域生命周期）的边界上才跨入宿主（`Crossing`），单元内部的一切操作直接在共享内核地址空间原地直达（`Not crossing`）。

---

## S4–S5：子系统映射表与收尾章节（已决定，2026-11-17，U10）

### S4 最终版：按宿主多路复用单元核实后的映射表

对照表反映整合各配套提案（`PR #3`、`PR #4`、`PR #5`、`TypedIO`、`PR #7`、Direct PTE、Grant Heap）后的**目标架构**，对照 OSTD 公开接口清单（`ab9a4cfdc`）：

| Subsystem | Multiplexing unit | Absent | Identical | Virtualized (not crossing) | Virtualized (crossing) |
|---|---|---|---|---|---|
| **Tasks & CPU** | `vCPU` carrier (host task & sandbox lifecycle) | `smp::inter_processor_call`, `PendingIpis` | `Task`, `Scheduler`, `WaitQueue`, `Mutex`, `SpinLock<_, PreemptDisabled>` | `cpu_local!`, `CpuId`, `LocalIrqDisabled`, `%gs` preempt mirror, `Jiffies` | `vcpu_boot`, `vcpu_idle`, `vcpu_kick`, `vcpu_yield`, `poweroff`/`stop` |
| **Memory & Heap** | Coarse physical `Grant` & `kstack` pool | `kspace::{KVirtArea, LINEAR_MAPPING_*, VMALLOC_*}` | Grant-backed `Frame<M>`, `MetaSlot`, `FrameAllocOptions`, `Slab` heap | `Fallible` `VmReader`/`VmWriter` (PT walk + direct map), `paddr_to_vaddr` | Coarse grant alloc/return (`grains_request`/extents), `kstack_alloc`/`free` |
| **Address Spaces** | `mm_struct` root (`CR3`, kernel half, `mm_cpumask`) | Host-kernel PT management (`PageTable<KernelMode>`) | `PageProperty`, `PageFlags` | `VmSpace`/`CursorMut` user-half PT walks & direct leaf/subtree writes | `vm_create`, `vm_activate`, `vm_flush` (cross-CPU TLB shootdown), `vm_destroy` |
| **User Mode & FPU** | Carrier ring-3 entry & carrier FPU ownership | — | `GeneralRegs`, `CpuException`, `UserEvent` | In-place `UserContext` (`pt_regs`), `FpuContext::read_from` & `XSAVE`/`XRSTOR` | `user_run` (ring-3 entry/return gate & carrier FPU recovery) |
| **Devices & Channels** | Authorized device attachment & cross-domain lease/pipe | `IoPort`, `IRQ_CHIP`, `IrqLine::remapping_index`, `ACPI_INFO`/`DEVICE_TREE` | `Protocol`/`Message` schemas, frontend `WaitQueue` & tag tables | Local `DmaStream` sync, `IrqLine` callback table, opaque copies on leased pipe spans | `discover`/`open`, `try_submit`/`try_pop_completion` & DMA leases, pipe `try_reserve`/`commit`, `bind_irq`/`rearm_irq` |

### S5 定稿状态
`Alternatives`、`Integration` 与 `Validation` 各保持 3 条精炼要点；随后已将全套定稿写入 [`2026-11-16-principles-of-api-virtualization.md`](../../book/src/design-proposals/2026-11-16-principles-of-api-virtualization.md) 并完成 `make check`、`make build` 与页面渲染检查。

---

## 全文复审（2026-11-17）

已对照 `prototype/vostd/src/` 源码、配套提案与 `AGENTS.md` 完成独立全文复审，发现的 6 项改进点（**R1–R6**，详见 [`review.md`](review.md)）已由用户确认全部采纳（**U11**），并同步更新至提案正文。
