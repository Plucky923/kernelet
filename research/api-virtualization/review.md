# `2026-11-16-principles-of-api-virtualization.md` 审阅记录

审阅日期：2026-11-17。对照 `prototype/vostd/src/` 源码、OSTD 接口清单（`ab9a4cfdc`）、各配套提案及仓库 `AGENTS.md` 规范，对当前版 [`2026-11-16-principles-of-api-virtualization.md`](../../book/src/design-proposals/2026-11-16-principles-of-api-virtualization.md) 进行全文审阅。

共整理出 **6 项问题**：前 3 项涉及源码事实与分类严谨度（R1–R3），后 3 项涉及论证一致性与全书体例规范（R4–R6）。状态：**已全部采纳并更新至提案正文（U11，2026-11-17）**。

---

## 一、技术严谨度与分类准确性（R1–R3）

### R1（高优）：复合原语的“快路径本地 + 慢路径/生命周期跨界”被压扁为单一类别

- **位置**：第 79–85 行对照表及第 70–73 行说明。
- **源码与提案核对**：
  1. **`SpinLock` 并非 `Identical`**：[`prototype/vostd/src/sync/spin.rs`](../../prototype/vostd/src/sync/spin.rs) 第 107–117 行在自旋满 1000 次后会调用 `vcpu::on_spin()`（即 `vcpu_on_spin` 服务，属于 `Crossing`），以缓解宿主调度导致的 lock-holder preemption；且两份新提案（[Direct PTE](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md) 第 118 行、[Grant Heap](../../book/src/design-proposals/2026-11-16-allocate-the-kernelet-heap-from-the-grant.md) 第 68 行）均明确保留了 `vcpu::on_spin()`。此外表中 `Crossing` 列也漏掉了 `vcpu_on_spin`。
  2. **`Task` 生命周期含跨界栈分配**：任务上下文切换与调度队列操作在本地完成，但 `TaskOptions::build` 与任务退出会调用 `kstack_alloc` / `kstack_free`（`Crossing`），且 [PR #3](https://github.com/tatetian/kernelet/pull/3) 调整了用户任务的栈顶寄存器保存区切换逻辑，因此严格上只有 `Scheduler`、`WaitQueue`、`Mutex` 是纯 `Identical`。
  3. **`CursorMut::unmap` 含跨界刷洗**：在 [Direct PTE](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md) 第 81 行中，`map`、`protect_next`、`query` 为纯 `Not crossing`，但 `unmap` 为遵守 OSTD 返回前完成跨核 TLB 同步的契约，仍会调用 `vm_flush`（`Crossing`）。
- **分析与修改建议**：
  这并不违背原则 2，反而揭示了原则 2 在复合类型上的精确表现：**分类作用于具体操作/路径而非笼统作用于整个类型**——多路复用单元内部的常态快路径是 `Not crossing`，触及单元边界的慢路径（长自旋让出 `vcpu_on_spin`）或同步/生命周期路径（`vm_flush`、`kstack_alloc`）才 `Crossing`。建议在 Principle 2 补一句该规律，并在表格中精确区分快慢路径与操作粒度。

### R2（中优）：声明覆盖 OSTD 全量清单，但映射表漏掉了 `boot`、`console`/`log` 与 `panic`

- **位置**：第 79–85 行对照表 vs. 第 105 行 `Taxonomic completeness`。
- **源码核对**：[`prototype/vostd/src/abi.rs`](../../prototype/vostd/src/abi.rs) 与 [`console.rs`](../../prototype/vostd/src/console.rs) 中的 `log_write`、`console_write` 是真实存在的 `Crossing` 服务；`BootInfo` 读取 `BootArgs` 属于 `Not crossing`；`catch_unwind` 为 `Identical` 而 `panic::abort` 调 `stop` 属于 `Crossing`。
- **修改建议**：在表格中补齐 `Boot, Log & Panic` 行（或与生命周期合并但显式列出），使表格覆盖 `Services` 中的全部跨界项，与第 105 行的完整性声明自洽。

### R3（中优）：Open Questions 将 `TypedIO` 与核心 `ostd` 接口混谈“合入裸机 OSTD”

- **位置**：第 112 行。
- **问题**：`UserEventHandler` 与 `FpuContext::read_from` 属于核心 `ostd` 层面对裸机同样成立的接口解耦/安全补全（`FpuContext::read_from` 已有上游 Asterinas PR）；但 [`TypedIO`](../../book/src/design-proposals/2026-11-08-typed-io.md) 是面向宿主内核的半虚拟化设备协议与前端层（在 Asterinas 架构中与 `comps/virtio` 并列，裸机硬件不存在宿主 `HostRequest` 后端）。
- **修改建议**：将该开放问题拆清——核心 `ostd` 契约修正（`UserEventHandler`、`FpuContext::read_from`）探讨上游化统一，而 `TypedIO` 探讨如何在 Asterinas 上层驱动组件中与 `VirtIO` 并列集成。

---

## 二、论证一致性与全书体例规范（R4–R6）

### R4（中优）：前后安全性表述存在温差，且第 54 行核心句语法杂糅

- **位置**：第 22 行 vs. 第 92 行；第 54 行。
- **问题**：
  1. 第 22 行断言跨界 *"shrinks neither the TCB nor the attack surface"* 过于绝对；第 92 行则准确指出宿主检查可拦截部分 `vOSTD` 逻辑 bug（纵深防御），但由于 `vOSTD` 已在 ring 0 持有宿主直映区（`linear_map_base`），**无法将 `vOSTD` 移出 TCB**。建议将第 22 行对齐到第 92 行的严谨口径。
  2. 第 54 行 *"creates, switches, synchronizes across physical CPUs, or retires one of the host's multiplexing units or cross-domain lifetimes"* 让四个针对“多路复用单元”的动词同时支配了 `cross-domain lifetimes`（产生“跨物理核同步一个生命周期”的病句）。建议改为并列结构：*“manage a host multiplexing unit (acquiring, switching, synchronizing across physical CPUs, or retiring it) or mediate I/O and lifetimes across fault domains”*。

### R5（低优/体例）：背景框混入项目论点，且使用了全书唯一的 `>` 块引用

- **位置**：第 25–29 行；第 54 行。
- **规范核对**：
  1. [`AGENTS.md`](../../AGENTS.md) 要求 `<div class="background">` 只放超出 OS 课程的通用背景知识，*"Keep the main argument and implementation requirements in the surrounding text."* 第 27 行把 `kernelet-book` 中 22/38 项不跨界的项目评述放进了背景框，熟悉 Popek & Goldberg 而跳过背景框的读者会漏读。应移回正文。
  2. 检索全书所有章节与提案，从未使用过 Markdown `>` 块引用（灰底框在全书视觉语言中专属于 `.background` 与 `.recap`）。第 54 行的 `>` 渲染后像无标签的背景框，建议改为普通加粗段落。

### R6（低优/元数据）：`Affected chapters` 与 `Implementation and integration` 章节列表不一致

- **位置**：第 6 行 vs. 第 99–101 行。
- **问题**：第 6 行列出了 `The first kernel we will run` 却未在 `Implementation and integration` 说明改哪里；同时漏掉了受原则 2 直接影响的第 13 章 `Tenant memory on Linux's page tables`。建议统一两处涉及的章节与修改说明。
