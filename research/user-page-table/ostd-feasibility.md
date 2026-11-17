# 真实 Asterinas OSTD 视角下的方案 B 可行性逐项讨论

这里对照仓库内检出的真实 Asterinas OSTD 源码（`reference/asterinas/ostd/src/mm/`，提交 `ab9a4cfdc726263b3f41ccea0337633e24b443fc`），而不是 `prototype/vostd` 的 PoC，逐项审查“vOSTD 直接写用户页表（方案 B）”在真实 OSTD 中的可行性、代码落点和需要调整的设计。

一次只讨论并确认一个问题。状态标记：**已确认**、**讨论中**、**待讨论**。

---

## 问题清单

| 编号 | 问题 | 状态 |
|---|---|---|
| O1 | 根节点 `mm->pgd` 不在 grant / `MetaSlot` 数组中，如何与 `PageTable` / `PageTableNode` 衔接 | **已确认** |
| O2 | `unmap` 时 `StrayPageTable` 与空页表的回收时机（OSTD RCU vs. Linux 无锁遍历 `perf`/`gup_fast`） | **已确认** |
| O3 | 顶层 PTI 双根写入与叶子 PTE 编码（`PAT` 位冲突、`_PAGE_SPECIAL`、非可读 `SOFTW2`） | **已确认** |
| O4 | 真实 OSTD 的大页（2 MiB / 1 GiB）映射与拆分路径如何处理 | **已确认** |
| O5 | 页表节点锁（`AtomicU8` / `SpinLock`）下的自旋让权（物理与堆分配机制本身不变） | **已确认** |
| O6 | `retire` 延迟销毁队列在去掉 `vm_map`/`unmap`/`protect`/`wait` 后的排空时机 | **已确认** |
| O7 | `VmSpace::reader`/`writer` 与 `TlbFlusher` 在 kernelet 下的适配边界 | **已确认** |

---

## O1：根节点 `mm->pgd` 与 OSTD `MetaSlot` / `PageTableNode` 的衔接（已确认，2026-11-15）

### 真实 OSTD 的实现机制

1. 在 `reference/asterinas/ostd/src/mm/page_table/node/mod.rs:62,125` 中：
   - `PageTableNode<C> = Frame<PageTablePageMeta<C>>`
   - `PageTableNodeRef<'a, C> = FrameRef<'a, PageTablePageMeta<C>>`
   每个页表节点把 `PageTablePageMeta<C>`（包含 `nr_children`、`stray`、`level` 以及节点锁 `lock: AtomicU8`，第 262–277 行）存放在该物理页对应的全局 `MetaSlot` 元数据槽里，并通过物理地址查找（如 `PageTableNodeRef::borrow_paddr()`、`PageTableNode::from_raw()`）。
2. 在 `reference/asterinas/ostd/src/mm/page_table/mod.rs:314-316` 中，`PageTable<C>` 直接持有 `root: PageTableNode<C>`。
3. 在 `reference/asterinas/ostd/src/mm/page_table/cursor/locking.rs:90-166` 中，`try_traverse_and_lock_subtree_root()` 从 `cur_pt_addr = pt.root.paddr()` 开始下降；当第 4 级槽位为空或跨 PGD 范围加锁时，它会用 `PageTableNodeRef::borrow_paddr(cur_pt_addr)` 构造引用并调用 `.lock(guard)` 锁住根节点本身。
4. 在 `PageTablePageMeta::on_drop()`（`node/mod.rs:302-327`）中，顶层（`level == C::NR_LEVELS`）只遍历 `C::TOP_LEVEL_INDEX_RANGE`（即用户半区 `0..256`）来释放子节点。

### 在本方案下的问题

- 第 1–3 级子表（PUD / PMD / PT）由 vOSTD 从沙箱的 grant 中分配，处于 vOSTD 初始化好的 `MetaSlot` 覆盖范围内，可以直接复用 `Frame<PageTablePageMeta<C>>`。
- 但第 4 级根页表 **`mm->pgd` 由宿主机 Linux（`kernelet_mm_alloc()`）分配**，位于沙箱 grant 之外，在 vOSTD 的 `MetaSlot` 数组中没有对应的元数据槽。如果直接对 `mm->pgd` 调用 `PageTableNodeRef::borrow_paddr()` 或 `PageTableNode::from_raw()`，会在查表或 `lock()`/`on_drop()` 时越界或 panic。

### 确认的做法

- **根节点（`level == C::NR_LEVELS`）从 `MetaSlot` 体系抽离，由 `PageTable` / `VmSpace` 单独管理**：
  - 根节点的锁与元数据不存放在 `MetaSlot` 中，而是挂在 `VmSpace` / `PageTable` 结构体自身（生命周期由 `VmSpace` 保证，绝不由游标回收，也不参与 `PageTableNode::from_raw()`）。
  - 顶层只允许读写用户半区槽位（`0..255`），绝对不触碰 Linux 维护的内核半区（`256..511`）。
  - 一旦下降到第 3 级及以下（PUD / PMD / PT），所有子表都来自沙箱 grant，继续走真实 OSTD 原生的 `PageTableNode` / `MetaSlot` 机制。
- 注：真实 OSTD 的 `PageTableNodeRef::lock()`（`node/mod.rs:137-144`）直接使用 `AtomicU8` + `core::hint::spin_loop()`，在 kernelet 下还需配合 `vcpu::on_spin()`（留在 O5 单独展开）。

### 追问：能否让 Linux 从 grant 分配 `mm->pgd`，或由 vOSTD 传入地址让 Linux 初始化

不建议（实现复杂且破坏生命周期隔离），原因如下（对照 `reference/linux-6.12/arch/x86/mm/pgtable.c`）：

1. **Linux 分配接口绑定了内部逻辑**：`pgd_alloc()`（`:433-469`）内部固定调用 `_pgd_alloc()` → `__get_free_pages(GFP_PGTABLE_USER, PGD_ALLOCATION_ORDER)`（`:421-425`），然后拿 `virt_to_ptdesc(pgd)`（页描述符）记录 `pt_mm` 并链入全局 `pgd_list`（`:96-144`，供同步内核半区使用），最后 `pgd_free()`（`:487-492`）直接 `pgd_list_del` + `free_pages`。传入外部地址要么修改核心 Linux 分配器，要么分配后再偷换 `mm->pgd`（同时手工维护内核半区拷贝、`pgd_list` 和 PTI 入口模板）。
2. **PTI 下根页是 8 KiB（order-1）而不是单个 4 KiB `PageTableNode`**：开启 PTI 时 `PGD_ALLOCATION_ORDER = 1`（内核副本 + 用户副本相邻两页），无法直接套用一个 4 KiB `Frame<PageTablePageMeta>`。
3. **释放归属与生命周期错位（最关键）**：Linux 通过 `free_pages` 释放 `mm->pgd`，而那要等到最后一个 `mmput_async()` / `mmdrop()` 降到 0；相反，在 `KLET_KILL` 时 endovisor 需要尽快整块收回 grant，如果 `mm->pgd` 在 grant 里，要么 `free_pages` 会与 grant 分配器发生双重释放，要么销毁前还要先把 `mm->pgd` 换回原页表、更新 `pgd_list` 并刷 lazy TLB。
4. **收益极不对等**：每个 `VmSpace` 只有唯一一张根页表且永远不由游标释放，在 `VmSpace` / `PageTable` 上直接放一个根锁字段、只对顶层跳过 `paddr_to_meta` 只需极少纯 vOSTD 代码，不必触动 Linux `pgd_alloc`/`pgd_free` 契约。

> 用户确认（2026-11-15）：若反过来由 OSTD/grant 分配或介入初始化 `mm->pgd`，需要对 Linux 做大改，不划算；按 O1 确认的做法，保留 Linux 分配与持有 `mm->pgd`，在 vOSTD 顶层做特殊处理即可。

---

## O2：`unmap` 时 `StrayPageTable` 与空页表的回收时机（已确认，2026-11-15）

### 真实 OSTD 的实现机制

1. 在 `reference/asterinas/ostd/src/mm/page_table/cursor/mod.rs:508-594` 中，`CursorMut::take_next()` 在整张下级页表被覆盖清除时，调用 `replace_cur_entry(PteState::Absent)`：
   - 立刻把子表从父节点摘除；
   - 通过 `locking::dfs_mark_stray_and_unlock()`（`cursor/locking.rs:257-284`）将这棵子树的节点全部标记为 `stray = true`；
   - 返回 `PageTableFrag::StrayPageTable { pt, va, len, num_frames }`，其中 `pt` 是 `RcuDrop<PageTableNode<C>>`。
2. 在 `reference/asterinas/ostd/src/mm/vm_space.rs:459-525` 中，`CursorMut::unmap()` 拿到 `PageTableFrag::StrayPageTable` 后，把它和 TLB 刷新请求一起交给 `self.flusher.issue_tlb_flush_with(..., Frame::rcu_from_unsized(pt))`，最后由 `dispatch_tlb_flush()` 刷完 TLB 后交给 OSTD 自己的 RCU（等待 OSTD 管理的处理器都离开原子模式/抢占守卫）来释放这批页表页，释放时会递归触发 `PageTablePageMeta::on_drop()` 归还整个子树上的页表页和 `UFrame`。

### 在本方案下的问题

- 真实 OSTD 的 `RcuDrop` 只等待 **OSTD 自己的 vCPU** 经过抢占静止点，**不会**等待宿主机 Linux 的所有物理 CPU。
- 在本方案下，Linux 的 `mm->pgd` 仍然可以被宿主机上的两个无锁路径随时遍历：`perf` 采样（NMI 上下文）和 `gup_fast`（关中断 / 宿主 RCU 读端，见 `b5-audit.md`）。
- 如果 `CursorMut::unmap()` 照搬真实 OSTD 把 `StrayPageTable` 摘下并交给 OSTD 自己的 RCU 回收，那在宿主机某颗核还没有退出 `perf` NMI 或 `gup_fast` 之前，这张页表页就可能被归还给 grant 分配器并被改写或用作用户页，造成宿主机无锁遍历踩到非法/复用内存（use-after-free）。

### 可选的处理方式

- **方式 A（提案当前方案）**：在 `take_next()` 中把 `find_next_impl(len, true, true)` 的 `find_unmap_subtree` 设为 `false`，只清除叶子 `Mapped` 项，不把整张空子表从父节点摘除（`cursor/mod.rs:210-226` 原本就支持在遍历时跳过 `nr_children() == 0` 的空子表）。所有中间页表页保留到 `VmSpace` 销毁：届时 `vm_destroy` 清空 `mm->pgd[0..255]`、以 `freed_tables = true` 刷 TLB、等待 Linux `synchronize_rcu()`，随后再由 vOSTD 递归释放全部子表页。
- **方式 B（按需剪枝）**：允许 `unmap` 摘下 `StrayPageTable`，但这些待释放页表页不能直接丢给 OSTD `RcuDrop`，而必须由宿主机路径以 `freed_tables = true` 刷 TLB 并走过 Linux `synchronize_rcu()` 之后才能归还给 grant 分配器。

### 结论与安全性确认（2026-11-15）

- **时间窗口已闭合，不存在残留并发漏洞**：
  - **运行期**：选择方式 A 时，空页表页仍在同一个 `VmSpace` 的页表树中（只是叶子项被清 0），不会被归还或改写为普通数据页；宿主机即使极偶尔触发 `perf`/`gup_fast` 无锁遍历，读到的也只是已清零的空表项，不会越界或崩溃。
  - **销毁期**：`vm_destroy` 先清 `mm->pgd[0..255]`、以 `freed_tables = true` 驱逐硬件缓存与 lazy-TLB CPU，再等待 Linux `synchronize_rcu()` 让在途无锁遍历全部退出，之后才把所有下级页表页与 `UFrame` 归还给 grant。
- **确定采用方式 A（延迟到 `VmSpace` 销毁时回收）**：运行期零宿主机同步成本（不为低概率的宿主遍历付出每次 `munmap` 的运行时开销），真实 OSTD 修改最小（仅让 `take_next()` 不摘空子表，`cursor/mod.rs` 原生就能跳过 `nr_children == 0` 的子表），且热区重新 `mmap` 时可免去重新分配页表页。若将来出现长驻进程极度稀疏 `mmap`/`munmap` 耗尽 grant 的极端情况，再按需补充“低水位触发的延迟批量剪枝 + 单次 `synchronize_rcu()`”即可，平时仍零开销。

---

## O3：顶层 PTI 双根写入与叶子 PTE 编码（已确认，2026-11-16）

### 真实 OSTD 与 Linux 6.12 的差异

1. **顶层 PTI 双根**：
   - 真实 OSTD（`reference/asterinas/ostd/src/arch/x86/mm/mod.rs` 与 `page_table/node/mod.rs`）假设只有单张根表，向 `PteState::PageTable` 写入第 4 级表项时只写单个节点地址，并只设 `PRESENT | WRITABLE | USER`。
   - 在开启 PTI 的 Linux 6.12 上，必须在写入顶层（`level == 4`，槽位 `0..255`）表项时按运行时 `pti_enabled` 同步写入用户根（`root_paddr | PAGE_SIZE`，不带 `_PAGE_NX`）和内核根（`root_paddr`，按 `nx_supported` 带上 `_PAGE_NX`）。
2. **叶子 PTE 缓存属性与“有效但不可读”标记（实查代码发现的重要冲突）**：
   - 在真实 OSTD 的 `ostd/src/arch/x86/mm/mod.rs:190-195, 229-258` 和 `pat.rs:15-24, 68-93` 中，所有第 1 级叶子 PTE 都**无条件置 bit 7（`PteFlags::HUGE`，在 4 KiB 页上即硬件 `PAT` 位）**，用来统一表示“该表项有效（即便 `PRESENT = 0`，即 `!PageFlags::R`）”；为此 OSTD 自己写 `IA32_PAT` MSR，把槽位 4–7 配成与 0–3 完全一致（`[WB, WT, WC, UC, WB, WT, WC, UC]`）。
   - 在 kernelet 中，宿主机 Linux 全局拥有 `IA32_PAT`，kernelet 不能调 `configure_pat()`；Linux 6.12（`reference/linux-6.12/arch/x86/mm/pat/memtype.c:344`）将 `IA32_PAT` 槽位 0–7 配为 `[WB, WC, UC-, UC, WB, WP, UC-, WT]`。如果 OSTD 继续把 4 KiB 叶子 bit 7（`PAT`）硬编码为 1，只有 `WB`（槽位 4）碰巧一致，`Writethrough` / `WriteCombining` / `Uncacheable` 全会错位成 `WP` / `UC-` / `WT`。
   - 此外，Linux `pgtable_types.h:10-48` 用 bit 9（`_PAGE_SOFTW1`）做 `_PAGE_SPECIAL`，用 bit 8（`_PAGE_GLOBAL`）在 `!PRESENT` 时兼作 `_PAGE_PROTNONE`，bit 10 为空闲软件位 `_PAGE_SOFTW2`；而真实 OSTD 原生不置 `_PAGE_SPECIAL`。

### 需要对齐的修改方向（待用户确认）

- **顶层（level 4, `0..255`）**：若 `pti_enabled` 为真，写根表项时先写 `root_paddr | PAGE_SIZE`（无 NX），再写 `root_paddr`（带 NX）。
- **第 1 级叶子 PTE**：
  - 不再借用 bit 7（`PAT`）充当“有效映射”标记，缓存模式改为按宿主机 Linux 的 `IA32_PAT` 槽位（`WB`/`WC`/`UC` 走 `PAT=0` 的槽位 0/1/3，`WT` 走槽位 7）映射，不再调用 `configure_pat()`；
  - 所有已映射叶子项置 bit 9（`_PAGE_SPECIAL`），并保证 bit 8（`_PAGE_GLOBAL`）始终为 `0`；
  - 不可读但已映射的页（`!PageFlags::R`，如 `PROT_NONE` / write-only）置 `PRESENT = 0`、`GLOBAL = 0`，用 bit 10（`_PAGE_SOFTW2`）标记“有效且不可读”。（若存在 2 MiB 大页则在 O4 另看。）

> 用户确认（2026-11-16）：这些全都是 vOSTD 内部写 PTE 时控制的位与规则（顶层 PTI 双写 + 叶子 `PAT`/缓存位、`_PAGE_SPECIAL`、`SOFTW2`），只需要在 vOSTD 架构层协调好即可，不改宿主机 Linux，也不影响整体核心设计。
>
> 补充核查：`reference/asterinas/ostd/src/arch/x86/mm/mod.rs:207,239` 和 `vm_space.rs:691-698` 中，OSTD 自身仅占用了高位软件位 bit 52（`HIGH_IGN1` / `AVAIL1` 区分 `TrackedFrame` 与 `IoMem`）与 bit 53（`HIGH_IGN2` / `AVAIL2`）；低位软件位 bit 9（`_PAGE_SPECIAL`）和 bit 10（`_PAGE_SOFTW2`）在 OSTD 中完全空闲，二者无位冲突。

---

## O4：真实 OSTD 的大页（2 MiB / 1 GiB）映射与拆分路径（已确认，2026-11-16）

### 真实 OSTD 源码核查

- 在 `reference/asterinas/ostd/src/mm/vm_space.rs:365-412` 中，`VmSpace::CursorMut::map()` 接收 `UFrame`（4 KiB），`map_iomem()` 按 `PAGE_SIZE` 循环映射。
- 在 `UserPtConfig::item_from_raw` / `item_ref_from_raw`（`vm_space.rs:704-723`）中明确写了 `debug_assert_eq!(level, 1)`。
- 也就是说，**当前版本真实 OSTD 的用户态 `VmSpace` 只映射 4 KiB（`level == 1`）页**；`PageTable` 内部虽然实现了大页映射/拆分（`split_if_mapped_huge`），但那主要是给内核态 `KernelPtConfig`（直接映射等）用的，用户态并不触发。

### 结论判断（待确认）

- 只要基于当前基准版本（`ab9a4cfdc726263b3f41ccea0337633e24b443fc`），用户空间仅使用 4 KiB 页，**O4 当前不存在阻断问题**（`walk`、叶子 `_PAGE_SPECIAL`、`SOFTW2` 都只需处理 level 1）。
- 若未来上游 Asterinas 支持向用户空间映射 2 MiB 大页，届时才需要补充检查两点：(1) 软件遍历（`walk` / `retire::destroy`）识别 PMD 层的 `HUGE` 叶子项；(2) 核查 Linux `gup_fast` 的 `gup_pmd_range` 对大页 `_PAGE_SPECIAL` 的处理路径。

> 用户确认（2026-11-16）：当前版本真实 OSTD 的用户态 `VmSpace` 本身就只使用 4 KiB 页（`debug_assert_eq!(level, 1)`），O4 不会触发，不影响核心设计。

---

## O5：页表节点锁下的自旋让权（已确认，2026-11-16）

### 真实 OSTD 源码核查与范围界定

1. **物理帧分配本来就在 grant 内，不涉及向宿主机分配**：下级页表页（4 KiB）直接由 vOSTD 的 grant 帧分配器分配，纯内存操作，不会睡眠。
2. **Rust 小块内核堆（`GlobalAlloc`）沿用书里已有界定**：如 `book/src/accepted-design/what-vostd-adds-on-top.md:299` 所述，当前体系下小块堆走 `mem_alloc`（宿主机 `kmalloc`）在持自旋锁时只影响极端争用下的延迟，不影响正确性；本提案不需要去改动“物理内存或堆怎么向宿主机申请”的设计。
3. **真实 OSTD 唯一需要改的点**：在 `reference/asterinas/ostd/src/mm/page_table/node/mod.rs:133-147` 中，`PageTableNodeRef::lock()` 直接对 `AtomicU8` 自旋并调用 `core::hint::spin_loop()`。接入 kernelet 时需要在其等锁循环里加上 `vcpu::on_spin()`（和现有 `SpinLock` 一致），避免持锁者被宿主机抢占时白耗时间片。

---

## O6：`retire` 延迟销毁队列在移除写服务后的排空时机（已确认，2026-11-16）

### 真实 OSTD 下的触发场景

1. 在真实 Asterinas 中，进程切换后在**关闭虚拟中断的 post-schedule 回调**中调用 `VmSpace::activate()`（`reference/asterinas/ostd/src/mm/vm_space.rs:125`，[what-vostd-adds-on-top.md](file:///mnt/data/projects/kernelet/book/src/accepted-design/what-vostd-adds-on-top.md#L244-L253)）。如果上一个刚退出运行的进程已经没有其他引用，这次切换就会在关中断状态下 drop 掉最后一个 `Arc<VmSpace>`。
2. 由于关中断状态下不能调用会睡眠的 `vm_destroy`（**为什么 `vm_destroy` 会睡眠**：新方案里它要调用阻塞等待的 Linux `synchronize_rcu()`、要求可睡眠上下文 `might_sleep()` 的 `mmput(mm)`，以及等待在途服务和跨核发 IPI 刷 TLB；同时 vOSTD 规则 2 也禁止在虚拟关中断期间进入可能睡眠的宿主机服务，否则会拖延虚拟中断投递），`VmSpace::drop` 只能先把该空间挂进延迟释放队列 `retire`，等后面某个**可睡眠的安全时刻**（无 `PreemptGuard`、无自旋锁、虚拟中断开启、不在 upcall 中）由 `retire::drain_if_safe()` 真正回收。

### 在本方案下的变化

- 旧设计中，`vm_map`、`vm_unmap`、`vm_protect`、`vm_wait` 每次进入都会调用 `drain_if_safe()`。
- 本方案移除这些按页内存服务后，仅剩 `vm_create`、`vm_destroy` 和 `vcpu_idle` 会触发排空（`vm_activate` 处于关中断路径，不可睡眠也不能排空）。
- 核查真实 Asterinas 上层调用（`reference/asterinas/kernel/core/src/vm/vmar/vmar_impls/mod.rs:62-64`）：`Vmar::new()` 调用 `VmSpace::new()` 时处于普通进程上下文（不持 `PreemptGuard` 或 `SpinLock`）。因此即使写服务全部取消，下次创建新进程/地址空间走 `vm_create` 或系统进 `vcpu_idle` 时，仍然可以安全排空 `retire` 队列（总积压也受 `KLET_MAX_SPACES = 64` 限制）。

### 追问：为什么 `VmSpace::drop()` 不直接让宿主机用 `mmput_async()` 异步释放，省掉 `retire` 队列？

对照 `reference/linux-6.12/kernel/fork.c:1375-1389` 的 `mmput_async()` 实现，关键差别在于 **`mm_struct` 的释放** 和 **grant 中页表页/`UFrame` 的回收**：

1. `mmput_async(mm)` 只是在 `mm_users` 归零时把 `__mmput(mm)`（即 `exit_mmap()` + 最终 `mmdrop()`）丢给 Linux 全局工作队列 `system_unbound_wq` 异步执行，然后立刻返回。
2. 但在我们的方案里，真正需要同步屏障的是**归还 grant 里的下级页表页（1–3 级）和 `UFrame`**，而 `__mmput(mm)` 因为没有 VMA 并不会替我们清 `mm->pgd[0..255]`、用 `freed_tables = true` 刷 TLB 并等 `synchronize_rcu()`。
3. 就算在 Linux 侧把清理工作塞进异步工作队列：如果 `vm_destroy` 不等待 `synchronize_rcu()` 完成就立刻返回，那么 `VmSpace::drop()` 依然**不敢当场释放下级页表页给 grant 分配器**（宿主机此时可能还有 `perf`/`gup_fast` 在里面遍历）——vOSTD 还是得把这些页暂存起来等通知或下次安全时机再收，绕了一圈还是等价于 `retire` 队列。
4. 对比之下，`vm_activate` 之所以能用 `mmput_async(old)`，是因为 `vm_activate` 只释放 `old` 上挂着的一份 `mm_struct` 引用，不回收任何页表页或 `UFrame`；而 `VmSpace::drop()` 要负责把页表页和 `UFrame` 归还 grant，就必须在走完“清 `pgd[0..255]` → `freed_tables` 刷 TLB → `synchronize_rcu()` → `mmput(mm)`”拿到确定性完成之后再还页，因此仍需 `retire` 队列把不可睡眠上下文的 `drop()` 推迟到可睡眠点执行。

### 追问：为什么不在 vOSTD 或 Linux 侧用“真正的后台异步线程/工作队列”来执行 `VmSpace::drop` 的收尾？

`retire` 队列本质上已经是 `drop()` 的异步延迟执行（`drop` 当场挂队即返回）；不用独立后台线程/工作队列的原因如下：

1. **vOSTD 后台线程不可靠**（见 `book/src/accepted-design/what-vostd-adds-on-top.md:246`）：在 `inject_scheduler` 之前起线程会触发默认调度器导致注入失败；之后起线程则脱离 Asterinas 调度器，或被高优先级繁忙任务饿死。
2. **Linux `workqueue` 异步完再回调/通知 vOSTD**：vOSTD 在确认 Linux 跑完 `synchronize_rcu()` 前仍然不敢把下级页表页和 `UFrame` 还回分配器，所以仍要维护队列等待完成状态，平白多出跨边界状态握手；且 `workqueue` 会把清理算力从沙箱自己的 cgroup CPU 记账中漏出去，不如由沙箱自己的 carrier 在 `vm_create`/`vcpu_idle` 捎带完成。

### 真实 OSTD 中的异步销毁适配点核查（修正 `switch_to_task()` 误判）

核查真实 OSTD 调度代码 `reference/asterinas/ostd/src/task/processor.rs` 与 `scheduler/mod.rs:470-601` 后，发现**把 `drain_if_safe()` 放进 `switch_to_task()` 入口（第 45 行 `finish_grace_period()` 旁边）是存在并发隐患的**：

1. **为什么 `switch_to_task()` 入口（`context_switch` 之前）不能做会睡眠的 `vm_destroy`？**
   - 在 `scheduler/mod.rs:470-482`（如 `park_current()`）或 `reschedule()` 选出 `next_task` 之后、`context_switch` 之前，`current_task` 的 `switched_to_cpu` 标记仍然是 `true`（直到切走后在 `processor.rs:131` 的 `after_switching_to()` 才会被清为 `false`）。
   - 如果此时 `switch_to_task()` 在 `processor.rs:45` 调 `vm_destroy` 睡在宿主机 `synchronize_rcu()` 上：一旦另一颗 vCPU 在此期间唤醒并试图切换回 `current_task`，它就会卡在 `processor.rs:104-111` 的 `while next_task.switched_to_cpu.compare_exchange(...)` 自旋死等（且此处原生只调用 `core::hint::spin_loop()`）；同时已经被选中的 `next_task` 也被悬在调度器之外。
2. **因此正确的排空落点**：
   - **常规排空点仍保持在调度切换状态机之外**：`vm_create`、`vm_destroy`、`vcpu_idle`（与 `what-vostd-adds-on-top.md` 一致）；
   - **若需要高水位兜底**（防范“既不 `vcpu_idle` 也不调 `vm_create`、只靠现有进程不断销毁旧空间”的极端场景）：应该放在 **`processor.rs:143-148` 的 `after_switching_to()` 开中断之后**（此时 `prev_task.switched_to_cpu` 已清为 `false`、`next_task` 已切上来且没有任何锁/guard，OSTD 原生也把可能阻塞/复杂的 `drop(prev)` 放在这一步），或放在**返回用户态的系统调用出口**（仅高水位触发），而**不能放在 `switch_to_task()` 的切换前路径上**。

### 追问：为什么 RCU 在 vOSTD 里做一次，到 Linux 宿主机里还要再等一次？

两层 RCU 保护的是**完全不同的读者群体**，互相覆盖不到：

1. **vOSTD 自己的 `rcu::synchronize()` 管不了宿主机物理核**：它只检查沙箱内各个 vCPU 的读端序列号（防止 `copy_regions` 正在通过直接映射拷贝 `UFrame`），看不到正在其他宿主机物理 CPU 上无锁遍历页表的 `perf` NMI 和 `gup_fast`。
2. **Linux 宿主机的 `synchronize_rcu()` 管不了被抢占的 kernelet vCPU**：在宿主机看来，carrier 只是可抢占任务——哪怕 vCPU 正带着 vOSTD 的 `rcu::read` 读半页 `UFrame`，宿主机也随时可以把它抢占切走，从而使宿主机物理 CPU 提前通过 Linux RCU 的静止点，但该 vCPU 恢复调度后仍会继续完成那页拷贝；只有 vOSTD 盯着该 vCPU 的序列号才能等它安全退出。
3. **分工结果**：运行期频繁 `unmap` 只回收 `UFrame`（不回收页表页，且宿主机 `gup_fast` 会跳过 `_PAGE_SPECIAL`），所以只跑微秒级的 vOSTD RCU；只有 `vm_destroy` 真正释放整个 `VmSpace` 回收下级页表页与残余 `UFrame` 时，两边各等一次各司其职。

> 用户确认（2026-11-16）：Linux 的 `synchronize_rcu()` 在运行期（`map`/`protect`/`unmap`/`fork`）完全不发生，仅在进程/空间销毁（`vm_destroy`）或沙箱退出时执行一次；O6 按“常规 `vm_create`/`vm_destroy`/`vcpu_idle` 排空 +（如需兜底则高水位在 `after_switching_to()` 开中断后或系统调用出口排空）”定稿。

---

## O7：`VmSpace::reader`/`writer` 与 `TlbFlusher` 的适配边界（已确认，2026-11-16）

### 真实 OSTD 源码核查

1. **`VmSpace::reader` / `writer`（`reference/asterinas/ostd/src/mm/vm_space.rs:159-225`）**：
   - 原生校验 `current_page_table_paddr() == self.pt.root_paddr()` 后，直接按用户虚拟地址构造 `VmReader::<Fallible>` / `VmWriter::<Fallible>`，依靠硬件直接访存 + 异常表（`__memcpy_fallible`）+ 内核态 `#PF` 触发按需调页。
2. **`TlbFlusher`（`reference/asterinas/ostd/src/mm/tlb.rs:23-144`、`vm_space.rs:354,488-522`）**：
   - 原生在内部缓存待刷地址/范围与延迟释放帧，在 `dispatch_tlb_flush()` 中对本地 CPU 和 `AtomicCpuSet` 里的远端 CPU 通过 `FLUSH_OPS` 发 IPI 刷表。

### 在本方案下的适配方式

1. **`reader` / `writer` 仍保持直接映射软件遍历（非原生直接解引用）**：
   - 注：真实 Asterinas OSTD 自身其实有完整的内核态用户访存异常处理机制（`reference/asterinas/ostd/src/arch/x86/mm/memcpy_fallible.S` 的 `__memcpy_fallible` + `.ex_table`，配合 `ostd/src/mm/fault/mod.rs:55-86` 的 `handle_user_page_fault()` 先调 `USER_PAGE_FAULT_HANDLER` 按需补页，失败再按 `.ex_table` 恢复）。
   - **为什么不在 kernelet 里转发内核态（Ring 0）`#PF` 去复用 OSTD 这套机制，而改用 `copy_regions`？**
     1. 用户态 `#PF` 发生在 Ring 3，可以登记后等到返回用户态的 `on_resume` 时切回 kernelet 正常处理；而内核态 `#PF` 发生在系统调用/内核代码执行半途中（走不到 `on_resume`），且与宿主机 Linux 共用 Ring 0 IDT 入口。要在宿主机 `#PF` 中断现场里识别动态加载的 kernelet `.ex_table`、处理 SMAP（`stac`/`clac`）并原地安全调进 kernelet 分配/锁逻辑，改动大且极易破坏宿主中断/原子上下文安全；
     2. 就算挂上普通异常表但不转发给 kernelet，按需分页的合法读写也会在 Ring 0 `#PF` 时直接被 Linux 判成 `-EFAULT`（见 `what-vostd-adds-on-top.md:59-65`）。
   - 相反，软件查页表 + 内核直接映射拷贝（`copy_regions`）总共只几十行 Rust：永远只访问合法的直接映射内核地址、**绝不触发内核态 `#PF`**，不用改 Linux 内核态缺页分发、也不用接 `.ex_table`/SMAP；查不到页时在普通 Rust 控制流里直接调 `USER_PAGE_FAULT_HANDLER` 再重试即可。
   - **实测开销**：按 `book/src/accepted-design/what-it-costs.md:67-68, 82` 的同机实测，软件查表 + 拷贝 64 字节共 **184 cycles（49 ns）**，拷贝 4 KiB 页共 **406 cycles（107 ns）**（到 4 KiB 时查表本身已被拷贝时间淹没），开销很小且不跨宿主机边界。
   - 本方案仅要求软件遍历兼容 `SOFTW2`（与此前 `withheld` 语义一致，视为未映射/不可读）及直接映射读取即可，接口层无新增复杂度。
2. **`TlbFlusher` 对接 `vm_flush`（规则 T）**：
   - 用户空间的 TLB 刷新不走 OSTD 自己的 IPI / `invlpg`（否则会漏掉 Linux 每个 `mm` 的 `tlb_gen` 与 PCID 同步），而是由 `TlbFlusher` 把需要刷的范围收敛后，在 `dispatch_tlb_flush()` 调用 `vm_flush` 转交 Linux `flush_tlb_mm_range()`。
   - **同时要注意一个真实 OSTD 细节**：`vm_space.rs:489, 514` 的 `unmap` 在原生实现里把 `RcuDrop` 帧放进 `TlbFlusher`，期望等“OSTD 自己发完 IPI + OSTD RCU”后释放；在 kernelet 下，改为 `unmap` 收集待释放的 `UFrame` 后，先经 `vm_flush` 完成同步刷表，再等 vOSTD 自己的 `rcu::synchronize()` 释放 `UFrame`（下级页表页按 O2 不在 `unmap` 时释放）。

> 用户确认（2026-11-16）：我们的最新设计中原本就已明确“保留 `user-copy` 路径”和“通过 `vm_flush` 调 Linux 刷 TLB”。O7 只是核对真实 OSTD 的 `VmSpace::reader`/`writer` 与 `TlbFlusher` 接口能够平滑接入这两条既定机制，没有新增设计变更。

---

## 总结（O1–O7 全部已确认，2026-11-16）

对照真实 Asterinas OSTD（`reference/asterinas/ostd/src/mm/` 及 `task/processor.rs`）逐项核查后，**方案 B（vOSTD 直接写用户页表）在真实 OSTD 中完全可行**，甚至在并发锁模型上比原 PoC 的 `vm_map`/`vm_wait` 更贴近真实 OSTD 原生的 `CursorMut` + 节点锁模型。全部适配工作都收口在 vOSTD 内部，不改核心设计、也不额外扩大 Linux 补丁：

1. **O1（根表 `mm->pgd`）**：保留 Linux 分配与持有 `mm->pgd`；仅在顶级根页表 PGD（OSTD 从下往上编号为 `level == 4`）把根锁挂在 `VmSpace` 字段上、跳过 `paddr_to_meta()`、且只写 `0..255`，其余下级子表（PUD/PMD/PT，即 level 3–1）直接复用 OSTD `MetaSlot`。
2. **O2（`unmap` 不剪枝）**：`CursorMut::take_next()` 关闭摘空子表（`find_unmap_subtree = false`），运行期 0 宿主同步成本；空中间页表页统一留到 `vm_destroy` 清 `pgd`、带 `freed_tables = true` 刷 TLB 并走 Linux `synchronize_rcu()` 后再回收。
3. **O3（PTE 位编码）**：全部在 vOSTD 写 PTE 层协调——顶层按 `pti_enabled` 写双根；第 1 级叶子停用 `PAT` 位（bit 7）作有效标记、改按宿主 `IA32_PAT` 设缓存位、打 `_PAGE_SPECIAL`、禁 `_PAGE_GLOBAL`、用空位 `SOFTW2`（bit 10）标记 `!R` 页（不与 OSTD 自身 bit 52/53 冲突）。
4. **O4（大页）**：当前真实 OSTD `UserPtConfig` 强制 `level == 1`（仅 4 KiB 用户页），无大页冲突。
5. **O5（节点锁自旋）**：真实 OSTD `PageTableNodeRef::lock()` 的 `AtomicU8` 自旋循环补上 `vcpu::on_spin()`；物理页表帧纯从 grant 分配，不改内存分配架构。
6. **O6（`retire` 延迟销毁）**：vOSTD 的 `retire` 队列即 OSTD 版 `mmput_async`；常规留在 `vm_create`/`vm_destroy`/`vcpu_idle` 排空（不能放 `switch_to_task()` 切换前，避免 `switched_to_cpu` 自旋卡死，高水位兜底如需要应放 `after_switching_to()` 开中断之后或系统调用出口）。Linux `synchronize_rcu()` 仅在销毁时发生一次，运行期不发生。
7. **O7（`reader`/`writer` 与 `TlbFlusher`）**：沿用既定方案——`reader`/`writer` 继续走书里已有的 `copy_regions`（软件查页表拿物理地址，再通过内核直接映射做内存拷贝；按需调页失败时调缺页后重试），`TlbFlusher::dispatch_tlb_flush()` 经 `vm_flush` 调 Linux `flush_tlb_mm_range()`。

