# 为什么当前 Rust 堆通过 Linux 分配

调研日期：2026-11-16。范围是当前 kernelet 原型中的 Rust 堆，即 `Box`、`Vec`、`Arc` 等对象使用的分配器。这里调查既有选择的理由和替换它必须保留的条件，不展开 grant 扩容。相关方向已整理为[从 grant 分配 kernelet 堆的提案](../../book/src/design-proposals/2026-11-16-allocate-the-kernelet-heap-from-the-grant.md)，状态为 Draft，尚未实现。

## 结论

**现有材料没有表明 Rust 堆必须把每个对象交给 Linux 分配。可以直接确认的设计理由是：原型的 grant 很小，作者把这块内存留给 tenant 的物理页。** `heap.rs` 的模块注释明确写出 grant 只有 4 MiB，因而堆使用宿主 `kmalloc`；这段理由在本仓库初次导入原型时已经存在。它描述的是原型的资源安排，不能据此推出体系结构上的必要性。[S1][H1]

另有三个需要区分的方面：使用已经运行的宿主分配器简化了启动；`GFP_KERNEL_ACCOUNT` 提供宿主记账；外部块表允许宿主收回未析构的对象。前者是当前源码明确体现的便利，后两者是当前实现满足的要求。这些都不足以单独证明对象分配必须由 `kmalloc` 完成；下文分别说明。[S1][S2][S3]

## 1. 两层不同的“由 Linux 分配”

| 层次 | 当前实现 | 本次问题的含义 |
|---|---|---|
| 从宿主取得底层物理内存 | endovisor 在 `klet_sandbox_start` 中调用 `alloc_pages(GFP_KERNEL_ACCOUNT | __GFP_ZERO | __GFP_NOWARN, order)`，建立 grant，并把物理地址、长度和 direct-map 基址传给 vOSTD。 | kernelet 使用的宿主物理内存由 Linux 交付，并由宿主管理其最终归属。 |
| 在已取得的内存中分配 Rust 对象 | `HostHeap::alloc` 将布局传给 `mem_alloc` 服务；endovisor 的 `klet_do_mem_alloc` 为这个请求调用 `kmalloc`。释放走 `mem_free` 和 `kfree`。 | 当前连对象的划分和回收也交给了 Linux，而不是在 grant 中自行划分。 |

第一层并不决定第二层。这里的可选设计是：Linux 仍交付底层内存，由 kernelet 的本地堆在其中分配对象。这个判断来自两层现有接口的分工，以及下文 OSTD 的实际实现，不表示 kernelet 已实现本地堆。[S1][S2][S4][S8]

### 当前 grant 实际用于什么

当前原型把 grant 接到 `FrameAllocOptions` 上，用于取得随后可映射给 tenant 的物理页。以 hello 内核为例，`create_vm_space` 从 grant 分配 `Segment`，把用户程序字节复制进去，再把其中各页映射到用户虚拟地址。grant 是用户程序实际存储所在的内存，而不只是记录配额的数值。[S10][S11]

kernelet 内核自己的 Rust 堆对象走另一条路径。例如同一份 hello 代码中的 `Arc<VmSpace>`、`Arc<Task>`，以及处理 `write` 时分配的 `Vec<u8>` 缓冲区，其堆存储通过 `HostHeap` 请求宿主内存。这里的“Rust 堆”指 kernelet 内核对象的堆，与 tenant 程序的用户堆属于不同层。[S1][S11]

`mem` 测试的 `new_frames(n) -> Vec<UFrame>` 同时展示了这两条路径：每次 `alloc_frame()` 得到的 4 KiB 页来自 grant；`collect()` 建立的 `Vec` 缓冲区保存 `UFrame` 句柄，其存储来自宿主堆。句柄数组与这些句柄所指的页内容是两份不同的存储。[S1][S10][S12]

这是一种当前实现的用途划分，不是物理内存的固有分类。grant 中的页可以作为本地堆的底层存储，再由堆分配器划分为 Rust 对象；参考 OSTD 的 slab 已采用从页框构建堆的方式。需要补的是页框到对象分配的实现和相应安全约定，而不是先获得 grant 扩容能力。当前 grant 较小，改用本地堆会让它与用户页共享容量。[S1][S4][S8]

## 2. 可以追溯到的设计理由

### 2.1 原型把小 grant 留给 tenant 页

`prototype/vostd/src/mm/heap.rs:5–10` 明确把宿主堆与 grant 内部分配器对照，并说明 4 MiB 的 grant 保留给能够交付 tenant 的页。这条直接理由来自源码注释。[S1]

书正文描述了宿主堆的设计：ABI 章节说明 `mem_alloc` / `mem_free` 转发到 `kmalloc` / `kfree`，停止章节说明通过宿主块表收回剩余分配，vOSTD 章节承认堆服务可能睡眠。这些内容说明现有方案怎样工作及其约束；相关章节没有解释为什么应选择它而不在 grant 内建立对象堆。“小 grant 留给 tenant 页”的因果解释没有写入这些正文，“省去本地堆实现”则是本文从实现得出的推断，不能归为书正文给出的选择论证。[S5][S7][S9]

历史上，这段注释已经出现在 `4f84aa6`（2026-10-16），即本仓库导入独立原型的提交。该提交说明原型从另一个 PoC 复制而来，所以本次只能确认这一理由在导入时就已存在；没有继续追溯仓库外 PoC 的完整设计过程。[H1]

### 2.2 宿主分配器已经可用，省去本地堆初始化

`heap::init` 的注释直接说宿主分配器已经在运行，无需建立新的分配器；函数只做服务可达性检查和一个分配/释放微基准。`kernelet_entry` 在初始化帧分配器后调用它，随后才构造启动命令行等堆对象。**由此可推断**，当前路径省去了本地堆的初始页保留、对象空闲结构和相关启动顺序；这是一项实现上的简化，不能扩大成“本地堆无法启动”。[S1][S6]

这种简化描述的是当前实现少承担的功能，不是必须省掉本地堆的要求。现有材料没有给出本地堆与宿主堆的完整实现成本比较，也没有证明本地堆成本过高。参考 OSTD 已有从页框构建堆的机制；是否复用、需要适配哪些依赖，须结合当前 vOSTD 判断。因此，“省去本地堆实现”本身不足以决定后续继续使用宿主堆。[S8][S10]

### 2.3 退出清理是后来补上的要求

提交 `4f84aa6` 的宿主堆只有 `kmalloc`、对齐处理和 `kfree`，没有记录尚未释放块的表。后续提交 `d1e2c00`（同为 2026-10-16）的提交说明明确指出：kernelet 结束时，未被它自行释放的堆块会泄漏；该提交新增了每沙箱块表和结束时回收。这说明清理问题是在选用宿主对象分配之后修补的，不能把它倒推成最初选择宿主堆的唯一动机。[H1][H2]

## 3. 当前宿主堆带来的性质与代价

### 3.1 记账：现有路径方便，但粒度可以改变

`KLET_HEAP_GFP` 是 `GFP_KERNEL_ACCOUNT | __GFP_NOWARN`。堆块和块表的分配都使用它，源码注明这些内存计入调用 carrier 所在的沙箱 cgroup。Linux 6.12 的内存分配指南也明确说明，`GFP_KERNEL_ACCOUNT` 用于需要内核内存记账的分配。[S2][E1]

grant 本身也已经使用 `GFP_KERNEL_ACCOUNT` 分配。因此，**如果对象始终来自已经记账、仍由沙箱持有的 grant，则在其中重新划分对象并不会凭空新增宿主物理内存**；这是根据当前分配路径得出的推断。Linux 可以继续按底层内存记账，kernelet 自己维护对象级统计，不需要为了对象划分再调用一次 `kmalloc`。代价是 grant 内部空闲块不会自动降低宿主记账，用户页与堆对象也会竞争固定池的容量。[S2][S4]

### 3.2 强制结束：宿主必须能整体回收，但未必逐对象回收

项目的退出规则是：所有 carrier 停止后，宿主不展开 kernelet 栈，也不调用其对象析构函数。当前 `klet_sandbox_gone` 先销毁地址空间，再由 `klet_heap_destroy` 遍历宿主自己的块表，最后释放栈池；grant 则在沙箱退出且最后一个描述符关闭后的销毁路径中归还。[S3][S4][S7]

**宿主逐块跟踪已经存在。** `klet_do_mem_alloc` 调用 `kmalloc` 后，将返回的底层块地址写入 `inst->heap.block[n]`；正常 `mem_free` 查验并移除这个记录，再调用 `kfree`。故障导致 kernelet 不再自行释放对象时，宿主在所有 carrier 停止后遍历自己的表，对剩余块逐个 `kfree`。这里跟踪的是每次宿主堆分配得到的内存块，不是 Rust 类型或对象析构关系。使用 `kmalloc` 没有消除沙箱回收逻辑，而是要求宿主补上这份逻辑。[S2][S3]

**跟踪表不等于任意内存错误的隔离。** 它提供资源归属记录、释放参数校验和故障后的内存回收；项目防止 kernel proper 破坏其他内存的论证仍依赖 safe Rust、vOSTD 的 soundness、可信依赖与编译器。`mem_free` 的注释还明确承认，它不能识别地址被重新分配之后发生的陈旧指针重复释放；不能把这张表看成能够约束有任意写能力的 vOSTD 的保护机制。[S2][S13]

**对本地堆的推断：** 若堆的底层页全部属于宿主独立记录的 grant，所有 carrier 已停止，宿主持有的外部引用已经解除，且必要的映射/TLB/读者等待已经完成，那么宿主可以回收底层 grant，无需读取堆的自由链表或逐对象运行析构函数。这遵循“回收交付的底层资源”的现有原则。它不意味着只改 `HostHeap` 就能完成替换，也不省略对地址空间和其他宿主资源的清理。[S3][S4][S7]

这种设计让对象级分配记录留在 kernelet 的本地堆中，宿主只需为堆内存保存底层 grant 或 extent 的归属记录。正常运行时，本地堆仍须管理对象分配和释放；故障后的整体回收才不依赖这些内部记录。因此，从故障后整体回收内存的要求看，本地堆有独立的设计理由。它也不会自动增加针对可信 vOSTD 中任意内存破坏的硬件隔离，内存安全论证仍须成立。这里只比较堆内存的回收粒度，未取消其他宿主资源的跟踪要求。[S2][S4][S7][S13]

### 3.3 睡眠：这是现有方案需要承担的代价

当前 `kmalloc` 使用的 `GFP_KERNEL_ACCOUNT` 包含 `GFP_KERNEL` 的行为，可能触发直接回收并睡眠。服务入口会暂时解除 kernelet 的宿主抢占计数镜像，使 Linux 可以睡眠；但书明确承认，堆服务可能在 kernelet 自旋锁内被调用，且没有执行其他睡眠内存服务的调用约束断言。[S2][S9][E1]

书把这一点界定为延迟问题，而非已证实的 soundness 破坏。本次没有在内存压力下复现或测量它，也不把这条文档判断扩大为对任意未来堆调用路径的证明。本地固定池分配器可以设计成不主动等待 Linux 回收，但它仍需处理自身锁、递归分配、初始化和耗尽失败；这些性质需要实现与验证。[S9][E2]

### 3.4 服务与块表有成本，尚不能声称替换后快多少

当前每个实际送达 `HostHeap` 的分配/释放请求会调用服务，并更新宿主块表。项目已有的启动微基准测量 64 字节对象的分配/释放对，取 7 轮、每轮 1,000 次中的最小平均周期数，主要覆盖热缓存下的服务和分配路径。它没有比较本地堆，也没有覆盖内存压力下的尾延迟，本次不据此给出本地堆的加速比例。[S1][S2]

## 4. OSTD 提供了不同的实际做法

本地只读参考源码中的 OSTD 为上层提供 `GlobalHeapAllocator`、`Slab` 和 `HeapSlot`：小对象 slab 通过 `FrameAllocOptions::alloc_frame_with` 获得一页，并把元数据保存在页框上；大对象通过 `alloc_segment_with` 获得连续页，再取 direct-map 地址作为对象存储。这个实现把页框供给与对象划分分开，不要求逐个对象请求 Linux。[S8]

Rust 自身的 `GlobalAlloc` 也只规定分配与释放契约，官方示例直接从静态 arena 返回空间，因而“Rust 集合要求宿主 `kmalloc`”不成立。[E2]

不过，**可借鉴不等于可直接复制**。当前 vOSTD 的 `Frame<M>` 只保存物理地址和 `PhantomData<M>`，`alloc_frame_with` 不保存传入的元数据；OSTD 的 slab 则依赖真实页框元数据、唯一页框、`Link` 和 heap-slot 等抽象。迁移需要先核对这些前置条件，而不是仅把 `mem_alloc` 换成 `alloc_frame`。[S8][S10]

## 5. 对下一步讨论的含义

本次调查支持重新选择对象分配的归属。现有材料支持的理由是小 grant 的原型安排和现成分配器的便利；必须保留的条件是宿主可记账、可收回底层资源，以及 kernelet 自身的分配契约。用户已决定提出从 grant 分配 Rust 堆的方案，见[提案草稿](../../book/src/design-proposals/2026-11-16-allocate-the-kernelet-heap-from-the-grant.md)；算法、池大小和具体迁移方案仍未决定。[S1][S2][S4][S8]

## 6. PR #4 是否解释了宿主堆的必要性

已通读 [tatetian/kernelet PR #4](https://github.com/tatetian/kernelet/pull/4) 所提交的完整 298 行提案。本文核对的是 head `5dea2a6442de477579d068e71efcfb41ad74ea40`，题为 “2026-11-06 Benchmarking Sandbox Memory Efficiency and Returning Unused Frame Grants”。**正文没有讨论 `HostHeap`、`kmalloc`、`kfree`、`mem_alloc` 或 `GlobalAlloc`，也没有说明为什么 Rust 对象堆必须交给 Linux。** 它讨论的是 Frame 池的容量管理、空闲 extent 归还及其测量。[P1]

与本问题相关的内容可以按层次区分：

| 层次 | PR #4 的安排 | 对宿主堆问题能说明什么 |
|---|---|---|
| 宿主交付和收回物理内存 | 由独立的 2 MiB extent 替代单块 Frame 池；宿主在 `budget_lock` 外分配 order-9 物理块，使用 `GFP_KERNEL_ACCOUNT \| __GFP_ZERO \| __GFP_NORETRY`，并跟踪 reserved / committed 容量。 | 说明底层内存仍由 Linux 交付和记账；不要求 Rust 对象逐个使用 `kmalloc`。[第 118–140 行](https://github.com/qrdeaf/kernelet/blob/5dea2a6442de477579d068e71efcfb41ad74ea40/book/src/design-proposals/2026-11-06-sandbox-memory-benchmark-and-returnable-frame-grants.md#L118-L140) |
| extent 内部的 Frame 分配 | Rust registry 为每个 extent 保存 512 页的位图和引用计数；完全空闲的新增 extent 才能退出本地可分配集合并归还宿主。 | PR 本身也区分了 Linux 的块交付与 vOSTD 的内部页分配。[第 151–155 行](https://github.com/qrdeaf/kernelet/blob/5dea2a6442de477579d068e71efcfb41ad74ea40/book/src/design-proposals/2026-11-06-sandbox-memory-benchmark-and-returnable-frame-grants.md#L151-L155) |
| 容量操作与普通分配的上下文 | 容量操作要求当前 Task、无 upcall、`guard_count=0`、IRQ 开启且 `R2held=0`；增长由安全点上的 `ensure` 显式触发，普通 Frame 分配不会隐式执行阻塞增长。 | 这是把可能睡眠的容量操作与普通分配分开的做法，未规定对象堆的分配实现。[第 157–163 行](https://github.com/qrdeaf/kernelet/blob/5dea2a6442de477579d068e71efcfb41ad74ea40/book/src/design-proposals/2026-11-06-sandbox-memory-benchmark-and-returnable-frame-grants.md#L157-L163) |

提案中出现的 persistent objects 不能直接等同于 vOSTD 中的 `Box`、`Vec` 或 slab 对象。其方法是先在 Linux 中测量源程序，再把内存曲线转换为 4 KiB 模型页的生命周期，最后在 kernelet 中执行 Frame 的分配、映射、访问与释放。它明确表示，重放的是重建的 Frame 负载，而非完整的源应用执行。[方法说明第 34–44 行](https://github.com/qrdeaf/kernelet/blob/5dea2a6442de477579d068e71efcfb41ad74ea40/book/src/design-proposals/2026-11-06-sandbox-memory-benchmark-and-returnable-frame-grants.md#L34-L44)

这一 PR 因而没有改变本次调查的结论：它提供了 Frame 池管理的相关设计，但没有为“逐对象调用 Linux 堆”补充必要性论证。提案还明确说，本次提交不把 PoC 实现合入主线；其测量不构成宿主堆与本地堆的性能对照。透明换出、活页迁移和页表页回收也不在已实现机制中。[第 116–122 行](https://github.com/qrdeaf/kernelet/blob/5dea2a6442de477579d068e71efcfb41ad74ea40/book/src/design-proposals/2026-11-06-sandbox-memory-benchmark-and-returnable-frame-grants.md#L116-L122)、[第 288–298 行](https://github.com/qrdeaf/kernelet/blob/5dea2a6442de477579d068e71efcfb41ad74ea40/book/src/design-proposals/2026-11-06-sandbox-memory-benchmark-and-returnable-frame-grants.md#L288-L298)

上述结论依据提案的实际范围和正文，不把讨论区缺少反馈当成作者对任何堆方案的认可，也没有审计或运行该 PR 描述的实验归档源码。

## 来源

- [S1] [`prototype/vostd/src/mm/heap.rs`](../../prototype/vostd/src/mm/heap.rs)：模块注释第 5–10 行；`HostHeap` 第 17–30 行；`init` 与测量方法第 32–62 行。
- [S2] [`prototype/linux/endovisor/carrier.c`](../../prototype/linux/endovisor/carrier.c)：堆块表及记账说明第 1312–1345 行；`klet_heap_grow` 第 1368–1407 行；`klet_do_mem_alloc` 第 1409–1449 行；`klet_do_mem_free` 第 1451–1494 行。
- [S3] [`prototype/linux/endovisor/carrier.c`](../../prototype/linux/endovisor/carrier.c)：`klet_sandbox_gone` 第 292–312 行；`klet_heap_destroy` 第 1496–1533 行。
- [S4] [`prototype/linux/endovisor/sandbox.c`](../../prototype/linux/endovisor/sandbox.c)：`klet_sandbox_start` 第 454–480 行；`klet_sandbox_destroy` 第 625–645 行。
- [S5] [`book/src/accepted-design/the-kernelet-abi.md`](../../book/src/accepted-design/the-kernelet-abi.md)：grant 和 direct map 第 96–130 行；堆分配第 169–188 行。
- [S6] [`prototype/vostd/src/lib.rs`](../../prototype/vostd/src/lib.rs)：`kernelet_entry` 第 73–99 行。
- [S7] [`book/src/accepted-design/stopping-a-kernelet.md`](../../book/src/accepted-design/stopping-a-kernelet.md)：第 3–11 行的停止与整体回收规则。
- [S8] 本地参考 OSTD，已通过 `git rev-parse HEAD` 确认在 `ab9a4cfdc726263b3f41ccea0337633e24b443fc`：[`mm/heap/mod.rs`](../../reference/asterinas/ostd/src/mm/heap/mod.rs) 第 22–51 行的 `GlobalHeapAllocator`；[`mm/heap/slab.rs`](../../reference/asterinas/ostd/src/mm/heap/slab.rs) 第 83–117 行的 `Slab::new`；[`mm/heap/slot.rs`](../../reference/asterinas/ostd/src/mm/heap/slot.rs) 第 73–99 行的 `HeapSlot::alloc_large`。参考树的来源约定见 [`research/README.md`](../README.md)。
- [S9] [`book/src/accepted-design/what-vostd-adds-on-top.md`](../../book/src/accepted-design/what-vostd-adds-on-top.md)：第 284–299 行的睡眠规则及堆的已知例外；[`carrier.c`](../../prototype/linux/endovisor/carrier.c) 第 1841–1874 行的服务入口。
- [S10] [`prototype/vostd/src/mm/frame.rs`](../../prototype/vostd/src/mm/frame.rs)：`Frame<M>` 第 42–47 行；`alloc_frame_with` 第 539–546 行；`alloc_segment_with` 第 553–570 行。
- [S11] [`prototype/kernels/hello/src/lib.rs`](../../prototype/kernels/hello/src/lib.rs)：第 31 行的 `Arc<VmSpace>`；`create_vm_space` 第 37–63 行的页分配、用户程序装入与映射；第 96 行的 `Arc<Task>`；第 119 行的 `Vec<u8>` 缓冲区。
- [S12] [`prototype/kernels/mem/src/lib.rs`](../../prototype/kernels/mem/src/lib.rs)：`new_frames` 第 285–289 行。
- [S13] [`book/src/accepted-design/why-a-kernel-of-your-own.md`](../../book/src/accepted-design/why-a-kernel-of-your-own.md)：第 51–78 行的 kernel proper、vOSTD 和可信依赖范围；内存安全依赖语言及可信实现的 soundness。
- [H1] 提交 [`4f84aa6d74948f11bec0e3b83dadc279c5f20ad1`](https://github.com/Plucky923/kernelet/commit/4f84aa6d74948f11bec0e3b83dadc279c5f20ad1)，2026-10-16。通过本地 `git show` 核对提交说明、该版本的 `prototype/vostd/src/mm/heap.rs` 和当时位于 `prototype/endovisor/carrier.c` 的堆实现。
- [H2] 提交 [`d1e2c003b67727fc5c3db41152cb2fdd2f8b45b1`](https://github.com/Plucky923/kernelet/commit/d1e2c003b67727fc5c3db41152cb2fdd2f8b45b1)，2026-10-16。通过本地 `git show` 核对提交说明及块表、清理路径和 `heap.rs` 的改动。
- [E1] [Linux 6.12 Memory Allocation Guide](https://docs.kernel.org/6.12/core-api/memory-allocation.html)，尤其是 GFP flags 与 `GFP_KERNEL_ACCOUNT` 的说明；本地对应 [`Documentation/core-api/memory-allocation.rst`](../../reference/linux-6.12/Documentation/core-api/memory-allocation.rst) 第 39–56 行。
- [E2] [Rust `GlobalAlloc` 官方文档](https://doc.rust-lang.org/alloc/alloc/trait.GlobalAlloc.html)：自定义静态 arena 示例、分配契约与重入限制。该网页是调研时的在线文档，非原型固定工具链的版本快照。
- [P1] [PR #4](https://github.com/tatetian/kernelet/pull/4) 的[固定版本提案正文](https://github.com/qrdeaf/kernelet/blob/5dea2a6442de477579d068e71efcfb41ad74ea40/book/src/design-proposals/2026-11-06-sandbox-memory-benchmark-and-returnable-frame-grants.md#L1-L298)。本地通过 `git show 5dea2a6442de477579d068e71efcfb41ad74ea40:book/src/design-proposals/2026-11-06-sandbox-memory-benchmark-and-returnable-frame-grants.md` 读取全部内容，并检索堆相关标识符。

## 证据边界与检查

当前项目 HEAD 为 `a5ec4b875d0a17890321a362fbc3fd16859b7eb4`；本次只读取与本问题有关的当前文件、Git 对象和一手文档。工作区已有未提交的页表提案，它不改变本文所述堆实现。已核对当前调用路径与上述历史提交，没有修改实现、重新运行原型或执行本地堆对比实验；本地堆的可行性是设计推断，尚未获得端到端验证。
