# 固定 grant 内的基础内存分配：讨论与决策记录

开始日期：2026-11-16。这里逐项讨论固定 grant 内的页框分配、所有权、元数据和堆分配，记录中间结果，供后续整理进设计提案和原型。

状态标记：**已决定**（用户确认的选择）、**源码事实**（已经核对的实现行为）、**待决定**（正在讨论的建议）、**未讨论**。

## 已决定

| 编号 | 日期 | 决定 |
|---|---|---|
| U1 | 2026-11-16 | 先完善基础内存分配，以运行期间容量固定的 grant 为讨论前提；grant 扩容和运行时向宿主归还内存暂缓。此决定不预定 grant 的容量、物理布局或分配算法。 |
| U2 | 2026-11-16 | 逐个问题讨论，把中间结果记录到 `research/`；尚未确认的建议保留为待决定。 |
| U3 | 2026-11-16 | 采用 M1 的职责划分：空闲页分配器管理页的分配与复用，`Frame` 及其元数据管理已分配页的所有权和生命周期。具体接口、元数据布局和分配算法另行讨论。 |
| U4 | 2026-11-16 | 新建提案，说明 kernelet 的 Rust 堆从 grant 中分配，不再逐对象请求 Linux 堆。已建立 [Draft](../../book/src/design-proposals/2026-11-16-allocate-the-kernelet-heap-from-the-grant.md)；具体算法、容量划分和实现尚未确定，也尚未纳入 Accepted Design。 |

## 源码事实

以下事实于 2026-11-16 核对，描述当前原型；页表提案中的安排单独标明。

| 编号 | 事实 | 依据 |
|---|---|---|
| F1 | 内部分配器通过位图寻找连续空闲页，并为每页设置初始引用计数；最后一个 `Frame` 引用释放时，页回到内部空闲池。 | [`frame.rs`](../../prototype/vostd/src/mm/frame.rs)：`allocator::alloc`、`allocator::dec_ref`、`allocator::dealloc`。 |
| F2 | `Frame<M>` 当前只保存物理地址和 `PhantomData<M>`。`alloc_frame_with` 不保存传入的元数据，`alloc_segment_with` 不调用元数据构造函数。 | [`frame.rs`](../../prototype/vostd/src/mm/frame.rs)：`Frame`、`FrameAllocOptions::alloc_frame_with`、`FrameAllocOptions::alloc_segment_with`。 |
| F3 | Rust 堆通过 `mem_alloc` / `mem_free` 服务使用宿主内存，尚未建立在 grant 的页框分配器之上。 | [`heap.rs`](../../prototype/vostd/src/mm/heap.rs)：`HostHeap`。 |
| F4 | 当前分配器使用自身的原子自旋锁；它没有使用 vOSTD `SpinLock` 的抢占或虚拟中断守卫。其允许调用的上下文需要单独讨论，不能据此直接断言已有可触发的死锁。 | [`frame.rs`](../../prototype/vostd/src/mm/frame.rs)：`allocator::Guard`；[`spin.rs`](../../prototype/vostd/src/sync/spin.rs)：`SpinLock::lock`。 |
| F5 | 直接页表更新草案拟从 grant 分配下级页表页，并在页框元数据中保存节点锁；该安排尚未实现。 | [直接页表更新提案](../../book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md)的 “Direct page-table writes in vOSTD” 一节。 |
| F6 | 当前每次宿主堆分配均登记到 `inst->heap.block`；正常释放时移除记录，所有 carrier 停止后逐块 `kfree` 剩余内存，不调用 kernelet 对象的析构函数。 | [`carrier.c`](../../prototype/linux/endovisor/carrier.c)：`klet_do_mem_alloc`、`klet_do_mem_free`、`klet_heap_destroy`、`klet_sandbox_gone`。 |

## 讨论顺序

以下是可调整的讨论入口，不表示已经选定实现方案。

| 编号 | 问题 | 状态 |
|---|---|---|
| M1 | 空闲页分配、`Frame` 所有权和对象分配各自负责什么？ | **已决定**空闲页与 `Frame` 的分工（U3）；对象分配的具体设计归入 M5。 |
| M2 | 页框元数据保存在哪里，如何访问和析构，如何区分可供用户使用的页与内部用途的页？ | **已决定**（尽可能遵循 OSTD 契约）：从 grant 开头动态划出 64B `MetaSlot` 数组，完整复用 `Frame<M>` / `UniqueFrame<M>` / `AnyFrameMeta` / `AnyUFrameMeta` 契约 |
| M3 | 单页与连续多页分配的对齐、清零、失败和并发约定是什么？ | **已决定**（沿用 OSTD/OSDK 既有契约）：默认 `zeroed = true`（内部 `.zeroed(false)`）、OOM 返回 `NoMemory`、允许拆散归还，并用 `SpinLock<..., LocalIrqDisabled>`（含 `vcpu::on_spin()`） |
| M4 | 依据这些要求，沿用位图、复用 OSTD 实现或采用其他分配算法？ | **已决定**（直接复用 OSDK Buddy）：采用 `osdk-frame-allocator`（基于 `MetaSlot` 的 `BuddySet`），并通过开机多段 `alloc_pages` 适当放大初始 grant 吸收默认缓存，不额外魔改缓存逻辑 |
| M5 | Rust 堆是否建立在 grant 上，怎样提供小对象和大对象分配？ | **已决定**（直接复用 OSDK 堆分配器）：采用 `osdk-heap-allocator`（`Slab` + `HeapSlot`）全量迁入 grant，保留默认缓存，由足够大的初始 grant 覆盖开销 |
| M6 | 怎样安排初始化和验证，避免分配器与元数据、堆相互依赖？ | **已决定**（严格无堆启动顺序与分层验证）：`BootArgs` $\rightarrow$ grant 开头 `MetaSlot` $\rightarrow$ Buddy $\rightarrow$ Heap $\rightarrow$ `cmdline`/多核/`__ostd_main` |

## M1：空闲页分配与 `Frame` 所有权的分工（已决定）

先讨论每部分的职责，再决定算法和代码组织。

**已确认的分工。** 空闲页分配器只记录哪些页可用，按请求交出尚未被占用的页，并接收已经可以复用的页。这个内部接口只供 vOSTD 使用；kernel proper 通过 `Frame` 和 `Segment` 等安全接口取得内存。

`Frame` 及其元数据负责已分配页的生命周期：初始化元数据，管理拥有引用和借用，执行元数据析构，并在最后一个拥有引用释放后将页交回空闲池。映射和页表的使用者仍须先完成自己的 TLB 刷新及读者等待协议，再释放它们持有的引用；空闲页分配器不负责判定硬件或无锁读者何时停止使用某个页。

这一分工的目的，是让空闲页管理算法可以变化，而 `Frame` 的所有权语义保持稳定。它不要求拆成多个公共模块，也不预定元数据的存放方式。

**决定范围。** U3 确认上述分工，具体接口和元数据模型尚未决定。当前先按用户要求调查 M5 中宿主堆的设计理由。

## M5：从 grant 分配 Rust 堆（方向已决定，提案为 Draft）

当前问题是：堆对象逐次通过宿主 `kmalloc` / `kfree` 分配，究竟是技术要求，还是原型的设计选择？完整来源、历史和替代条件见 [`linux-heap-rationale.md`](linux-heap-rationale.md)。

**调研结论（2026-11-16）。** 源码明确给出的理由是原型 grant 只有 4 MiB，留给 tenant 页；使用宿主堆也简化了启动。提交历史表明，宿主对象分配先于退出时块表清理机制，不能把后者倒推为最初选择的必要原因。

**来源区分。** book 正文描述了宿主堆的分配路径、块表清理和睡眠问题，没有给出为何不用 grant 内对象堆的选择论证。“4 MiB grant 留给 tenant 页”来自 `heap.rs` 的注释；“省去本地堆实现”是根据实现作出的推断，不能说成书正文的设计理由。

**工程便利的范围。** “省去本地堆实现”描述当前路径少承担的功能，不是必须省掉本地堆的要求。现有材料没有证明本地堆实现成本过高，也没有完整比较两种方案；这项便利不足以决定继续保留宿主堆。

**故障后回收的代价。** 宿主 `kmalloc` 方案需要 F6 中逐分配块的登记和清理；评估实现复杂度时必须计入这些宿主逻辑。若堆完全建立在 grant 内，在停止全部 carrier、解除外部引用并完成必要的映射与读者清理后，宿主可按底层块整体回收堆内存，本地堆的对象记录无需参与故障后清理。这是支持本地堆的一项设计判断，尚未决定具体实现。逐块记录和整体回收都不能替代 safe Rust 与 vOSTD 的内存安全约定，也不意味着对有任意写能力的可信代码增加了硬件隔离。

底层内存由 Linux 交付，与每个堆对象是否调用 `kmalloc` 是两个选择。根据已经记账的 grant 和 OSTD 从页框构建堆的实现，本地堆在设计上可行；它仍须满足底层资源记账、停止后的安全回收、固定容量竞争及初始化等条件。U4 已决定将本地堆方向写成提案；具体实现和对比实验尚未完成。

**grant 用途澄清。** 当前 grant 为 `FrameAllocOptions` 提供实际物理页，用于 tenant 的用户内存；kernelet 内核自己的 `Box`、`Vec`、`Arc` 堆存储则通过 `HostHeap` 向 Linux 另行申请。比如 [`new_frames`](../../prototype/kernels/mem/src/lib.rs) 返回的 `Vec<UFrame>` 中，页内容在 grant，保存句柄的 `Vec` 缓冲区在宿主堆。grant 中的页可以支撑本地对象堆；现有用途划分不构成必须逐对象调用 `kmalloc` 的理由。

**PR #4 核查（2026-11-16）。** [PR #4](https://github.com/tatetian/kernelet/pull/4) 当前 head 为 `5dea2a6442de477579d068e71efcfb41ad74ea40`，提交的是文档提案及实验结果。它讨论 Frame grant 的分块供给和归还，没有解释 Rust 堆为何使用宿主 `kmalloc`。其 [8.3 节](https://github.com/qrdeaf/kernelet/blob/5dea2a6442de477579d068e71efcfb41ad74ea40/book/src/design-proposals/2026-11-06-sandbox-memory-benchmark-and-returnable-frame-grants.md#L157-L163)明确区分容量操作与普通 Frame 分配：前者在允许睡眠的安全点执行，后者不会隐式触发阻塞式扩容。该区分可供基础分配器讨论参考，不表示本轮采用其扩容方案。

## M2：页框元数据与所有权模型（已决定，2026-11-16）

**已确认原则**：尽可能严格遵循上游 OSTD 的页框元数据与所有权契约（对照 `reference/asterinas/ostd/src/mm/frame/meta.rs`）。

1. **64 字节 `MetaSlot` 与完整的生命周期/类型契约**：vOSTD 沿用 OSTD 的 64 字节 `MetaSlot` 布局（`storage` 最多 40B/对齐至 64B、`ref_count` 编码 `UNUSED`/`UNIQUE`/`0`/`1..`、`vtable_ptr`、`in_list`），支持 `Frame<M>`、`UniqueFrame<M>`、`AnyFrameMeta::on_drop`、`is_untyped` 以及 `Link<M>`。
2. **用户页与内部页的隔离边界**：保留 `AnyFrameMeta` 与 `AnyUFrameMeta: AnyFrameMeta` 两层 trait；仅实现 `AnyUFrameMeta` 的用户页可构造 `UFrame` 传给 `CursorMut::map` 与 `VmReader`/`VmWriter`，堆页（`SlabMeta` / `LargeAllocFrameMeta`）和 1–3 级页表页（`PageTablePageMeta`）只实现 `AnyFrameMeta`，从类型系统上禁止暴露给用户态。
3. **grant 内动态安置与索引**：启动时从每个初始 grant 段开头划出所需页数存放该段的 `MetaSlot` 数组（64B/页，约 1.56%），将这批预留页自身的 `MetaSlot` 标为 `MetaPageMeta` 并从空闲页池剔除；通过封装后的 `frame_to_meta(paddr)` / `meta_to_frame(ptr)`（先校验页对齐与段边界）索引（单段时为直接偏移，启动多段时查有序段表）。由 Linux 分配的顶层 `mm->pgd` 不在 grant 内，继续跳过 `MetaSlot`。

## M3：单页/多页分配契约与并发安全（已决定，2026-11-16）

**已确认原则**：直接沿用上游 OSTD/OSDK 的既有契约（对照 `reference/asterinas/ostd/src/mm/frame/allocator.rs` 与 `reference/asterinas/osdk/deps/frame-allocator/src/pools/mod.rs`），不另造规则。

1. **对齐、多页与散页归还**：按 `Layout`（至少 `PAGE_SIZE` 对齐）分配单页或连续 `Segment`（`nframes == 0` 返回 `InvalidArgs`）；允许按单页或子区间分别 `dealloc`。
2. **清零与防泄露**：`FrameAllocOptions` 默认 `zeroed = true`（用户内存与页表分配在交出前全页清零）；仅可信内部路径（如 `Slab`、`alloc_large`）显式传 `.zeroed(false)`。
3. **固定容量失败语义**：grant 耗尽时返回 `Err(Error::NoMemory)`，不阻塞等待、不向宿主机 `kmalloc` 借内存或隐式扩容。
4. **并发与中断锁**：淘汰当前 `frame.rs` 自写的裸原子锁，统一使用 vOSTD 的 `SpinLock<..., LocalIrqDisabled>`（自动屏蔽虚拟中断并在自旋时调 `vcpu::on_spin()`），持锁期禁递归堆分配。

## M4：物理页框分配算法与容量处理策略（已决定，2026-11-16）

**已确认原则**：从实用性与上游对齐出发，不保留现有 `frame.rs` 的 PoC 位图，也不为迁就 `4 MiB` 硬去裁剪上游缓存；直接复用 OSDK Buddy，并通过启动时分配充足的静态初始 grant 吸收默认缓存开销（暂不引入运行期扩缩容）。

1. **算法与实现选择（直接复用 OSDK Buddy）**：采用 `osdk-frame-allocator` 的 `BuddySet` 模型——空闲页原地借用自身 `MetaSlot` 的 `in_list` 构造按阶空闲链表（零额外元数据，支持按页拆散归还并在 $O(\log N)$ 内自动合并）。
2. **用充足初始容量代替裁剪缓存**：针对上游 `osdk-frame-allocator` 自带 per-CPU `CacheOfSizes`（最多 ~264 KiB/vCPU）和 `LOCAL_POOL` 在 2–4 MiB 下容易提前撞上限的问题，**不在前期魔改或禁用 OSDK 缓存**；而是放开 [`sandbox.c`](../../prototype/linux/endovisor/sandbox.c) 只能调一次 `alloc_pages(MAX_PAGE_ORDER)`（4 MiB）的限制，允许开机分配多块 2/4 MiB 静态传进 `BootArgs`（例如给足十余至数十 MiB），使上游缓存仅占极小比例，保持正常性能优势。
3. **Fault Isolation 闭环**：运行期物理块静态不变，沙箱异常终止时仍按整实例停止全部 carrier 并整块收回（或循环 `__free_pages` 收回开机多块），不运行 `Drop`/`on_drop`；借助 `frame_to_meta` 边界校验与 `AnyFrameMeta`/`AnyUFrameMeta` 类型隔离，无需在宿主侧维护对象块表。

## M5：Rust 堆在 grant 上的具体分配机制（已决定，2026-11-16）

**已确认原则**：直接复用 OSTD/OSDK 既有的 `GlobalHeapAllocator` / `AllocDispatch` + `osdk-heap-allocator`（`Slab` + `HeapSlot`），全量迁入 grant，保留其默认缓存。

1. **小对象与大对象分级路径**：
   - 小对象（$\le 2048\text{ B}$，按 8B..2048B 共 9 个 2 次幂 size class）使用 OSTD 单页 `Slab<SLOT_SIZE>`（`UniqueFrame<Link<SlabMeta<SLOT_SIZE>>>`，空闲槽位和计数存在 `MetaSlot` 40B 存储区里），由 `#[global_allocator]` 分发，经 `paddr_to_vaddr` 直接返回指针，不碰页表。
   - 大对象（$> 2048\text{ B}$ 或按对齐需整页分配）通过 `HeapSlot`（内部 `.zeroed(false)`）直接向 M4 的 Buddy 池申请连续物理页，释放时直接还回 Buddy。
2. **默认缓存直接保留**：既然按 M4 在启动时把 grant 给足，上游 `osdk-heap-allocator` 的 `SlabCache` 空 slab 缓存与 per-CPU `ObjectCache` 可直接保留，避免自写或裁剪带来的维护分叉。

## M6：启动初始化顺序与验证方案（已决定，2026-11-16）

**已确认原则**：严格保证在 `#[global_allocator]` 启用前绝不触发任何堆分配或递归依赖，并在后续实现补齐后按固定指标验证。

1. **严格启动顺序与无堆故障路径（对应 [`prototype/vostd/src/lib.rs`](../../prototype/vostd/src/lib.rs) 与 [`panic.rs`](../../prototype/vostd/src/panic.rs)）**：
   `abi::init_tables`（读取 `BootArgs` 的初始 grant 段与 `linear_map_base`）$\rightarrow$ `cpu::init`、`time::init`（零堆）$\rightarrow$ 为各初始 grant 段切分并清零 `MetaSlot[]`（标为 `MetaPageMeta` 并建立 `frame_to_meta`）$\rightarrow$ 将可用 grant 页投入全局 Buddy（`mm::frame::allocator::init`）$\rightarrow$ 启用本地 `#[global_allocator]` 堆（`mm::heap::init`）$\rightarrow$ 解析 `cmdline`、启动其余 vCPU 并进入 `__ostd_main`。`panic_handler` 与 `alloc_error_handler` 在**全生命周期任何阶段**均保持零堆分配，防止堆未就绪、持锁或 OOM 时递归死锁。
2. **范围划定（暂不做运行期扩缩容）**：当前明确先采用启动分配好、运行期静态不变的 grant（单块或启动多块 2/4 MiB 拼大），不引入运行期跨宿主机增减段、缩容摘链或迁页逻辑；保留 `frame_to_meta` 封装与 `add_free_memory` 作为未来扩展点。
3. **验证清单（留待代码实现阶段执行）**：
   - 分配契约与隔离：大小对象及对齐、空 Slab 归还、`SlabMeta` 类型隔离、`UFrame` 分配前全页清零；
   - 自举与并发：零 `mem_alloc`/`mem_free` 启动、多 vCPU 与关中断自旋锁下无死锁/睡眠；
   - 容量与故障隔离：确定适配 OSDK 默认缓存的初始 grant 大小（避免 4 MiB 提前假 OOM），验证打满返回 `NoMemory`/null 不向宿主机借内存；带故意泄露堆对象强杀沙箱后检查宿主零残留；
   - 成本对照：对比 [`what-it-costs.md`](../../book/src/accepted-design/what-it-costs.md) 的 449 周期基线，测量本地 grant 堆下的分配/释放周期数。

## 验证状态

本轮已核对当前源码、相关 Git 历史和 Linux/Rust 一手文档，没有实现变更或新的运行实验。后续验证项目随各项决定确定；已有页表实验计划保留在 [`user-page-table/experiment-plan.md`](../user-page-table/experiment-plan.md)。
