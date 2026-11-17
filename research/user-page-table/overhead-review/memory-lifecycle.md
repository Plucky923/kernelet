# Kernelet 内存与生命周期开销审查

- 日期：2026-11-16。
- 对象：当前 Linux Endovisor + Asterinas Image PoC，主要为 Direct PTE 模式；不将 `prototype/` 的宿主堆实现当作本 PoC 的实现。
- 验证：只读源码、现有配置和运行日志；未修改实现、未构建、未采样、未重跑实验。下列收益均未测量。
- 源码基准：主代理于 `2026-11-17T05:32:23.979156Z` 制作的只读快照，主仓库 HEAD `a5ec4b8`，`poc/` HEAD `7f8476a`，包含本地修改。快照前已经删除的旧 Rust Host 模块未恢复，也未作为当前执行路径使用。

## 1. 结论与执行频度

内存侧存在可消除的重复表示、可减少的查表、过早的全量 TLB 失效，以及可调整的启动和回收粒度。它们主要发生在缺页、批量 MM、创建/销毁和 Task 切换，不在普通、不调度的稳态 `getpid` 中逐次发生。不能用它们解释全部 `83.96 ns` syscall 差值。

| 编号 | 项目 | 发生时机 | 判断 |
|---|---|---|---|
| M1 | 逐页 `OP_VM_MAP/PROTECT/UNMAP` 与 VMA 管理 | VMA 对照组的映射/改权限/卸载 | Direct PTE 已消除这条重复宿主路径，不能重复计算成剩余开销 |
| M2 | metadata 双向查表、叶 PTE 的根专属检查 | Frame 构造/查询、页表读写 | 有明确的合并和缓存空间，保持原归属验证，先核对 release 机器码 |
| M3 | 超过 4 个操作即退化为全地址空间 TLB flush | Direct PTE 的小批量更新 | 可调整策略；不需要取消失效或远端确认 |
| M4 | vOSTD 顶层物理页与 Linux PGD 双份表示 | 每个 `VmSpace` 创建、顶层项变化 | 可重构为单个硬件根与软件管理对象；不能直接删除 Linux `mm_struct` |
| M5 | 全 grant 预分配/清零与后续再次清零 | 创建与首次页使用 | 可追踪已清零状态，或改变预分配策略；不能全局取消用户页初始化 |
| M6 | 每个销毁 root 单独等待 Host RCU | 空间销毁/沙盒整体回收 | 可在满足同一回收谓词后批量等待；异步返回必须同时保留全部被保护对象 |
| M7 | 栈槽高水位物理页持有 | Task 创建/退出与复用 | 是可调整的缓存政策；不表示所有栈 reserve 都已经消耗物理页 |
| M8 | RunDesc 容量、initramfs 和镜像初始化 | 每实例创建/每 kind 注册 | 有容量收紧和只读共享候选，需要同时修改 ABI 容量约束或明确缓存所有权 |

优先级按确定性与改动边界排列：先排除测量语义问题，再核对 M2/M3 的局部热路径，随后讨论 M4/M6 的所有权和协议，M5/M7/M8 用独立冷启动与内存占用实验评估。这个次序不是未测量的耗时排名。

## 2. M1：Direct PTE 已经删除的工作

`poc/ostd/src/mm/vm_space.rs::CursorMut::map:840-858` 先修改本地页表，仅在 `pt_mode == 1` 时调用 `OP_VM_MAP`；`protect_next:1090-1147` 的宿主保护服务也只在 VMA 模式执行；`unmap:1045-1064` 将 VMA 模式的 `OP_VM_UNMAP` 与 Direct PTE 的 shootdown 分开。Direct PTE 仍保留一条 TLB 服务，不再每页调 Linux 插入 PTE。

VMA 模式的 `poc/linux/endovisor/poc_space.c::poc_op_vm_map:524-565` 每次还要转换权限、验证 grant、查 root、取 VMA 锁并 `vmf_insert_pfn_prot`；protect/unmap 对照同文件 `568-643`。这些是该对照模式可避免的跨层工作，不是当前 Direct PTE 的剩余逐页成本。两种模式在 `VmSpace::new` 都创建 Linux `mm`，但 Direct 模式不创建 VMA（同文件 `181-241`）。

合并两种实验模式后，Image 的 map/protect/unmap 仍在运行期检查 `boot_args().pt_mode`。可以核对生产 Direct 构建是否仍逐页读取这个固定模式，评估在 cursor 建立时确定处理策略或在构建时专用化；不把源码分支直接当作未被优化的机器码，也不把一个模式判断夸大成仍有逐页宿主服务。

已有报告中的服务计数可作旧运行记录；本轮没有确认旧日志与当前源码/ELF 的内容哈希。下一轮应分别采计时窗口的 map/protect/unmap/flush 计数，不能拿整套统计代替每个操作的频度。

## 3. M2：合并 metadata 查询，把根专属工作移出叶 PTE 路径

**Frame 到 metadata 的重复查询。** `poc/ostd/src/mm/frame/meta.rs::get_slot:244-253` 先执行 `has_meta(paddr)`，再执行 `frame_to_meta(paddr)`。Image 实现分别在 `poc/ostd/src/kernelet/image_grant.rs:109-141`，两者都计算 section 并读取共享索引，后者还重新读取范围信息。可以提供一次返回“验证过的 metadata 地址”的内部查询，合并两次遍历和重复读取；保留页对齐、上界、section、grain bitmap 与元数据发布验证。不能把任意物理地址直接变成有效 `Frame`。

**页表地址可以在 guard 生命周期内缓存。** `Frame::paddr` 经 `MetaSlot::frame_paddr` 调用 Image `meta_to_frame`，后者读取 compact metadata 的 reverse section 表并验证范围（`frame/mod.rs:247-250`，`frame/meta.rs:385-388`，`image_grant.rs:144-155`）。页表 `read_pte/write_pte` 都先求 `self.paddr()`（`page_table/node/mod.rs:256-262,288-292`）；持锁的 `PageTableGuard` 当前只有 `inner` 字段（`218-220`）。可在获得 guard 时缓存该节点的物理页/映射指针，批量访问 512 项时复用。节点必须在 guard 期间保持存活，不能把缓存跨越节点释放、grant 撤销或重新绑定；编译器已消除的重复运算不再算作新收益。

**根专属检查的位置。** `PageTableGuard::write_pte:294-300` 在判断当前层级前读取 `linux_pgd_paddr`，于是叶 PTE 更新也进入这段 root 元数据逻辑。可先判断 level/index，再读取只对根有用的字段，或用单独的顶层安装方法。`write_pte:279-286` 对新子页表再次作 grant metadata 检查；其中一些来源已经通过 `Frame` 构造验证，能否移到节点建立/安装边界，应先完整审计该 unsafe 方法的调用者和所有原始 PTE 来源。不能只依据“安全 Rust 调用了它”就取消归属契约。

可证伪预测：冻结 ELF 中相关查表/根字段访问实际减少，在大批量 PTE 写入中获得可重复收益；若现有优化已经消除它们，则撤销对应候选。回归覆盖非法 paddr、稀疏 grant、跨 section、并发分配/销毁、PTI 顶层更新与 OOM。

## 4. M3：小批量 TLB 请求过早退化为全量失效

`poc/ostd/src/mm/tlb.rs::OpsStack::shootdown_range:418-438` 在 `num_ops > 4` 时直接生成 `(0, u64::MAX)`，随后才有覆盖区间计算和 32 页阈值。五个连续 4 KiB 的单页操作因此已经会请求全地址空间失效，尽管覆盖范围只有 20 KiB。Host `poc_do_tlb_shootdown` 支持 page-aligned `start,len`（`poc/linux/endovisor/poc_space.c:396-427`）。

候选是按实际覆盖范围/稀疏度选择 range 或全量，而不是仅按 4 个操作计数。增加范围归并 CPU 工作与保留更多 TLB 条目的收益需要对照；不能认定调整阈值对所有工作负载都更好。这里无需改变 PTE 发布、Host 同步 shootdown 和远端确认的职责。`dispatch_tlb_flush:109-128` 在 Host 确认后才退休保留的 Frame；`sync_tlb_flush:199-205` 对已同步的用户根直接返回，没有再次等待同一组虚拟 IPI。

`VmMapping::unmap` 在 `CursorMut::unmap` 已 dispatch 后又调用一次 `dispatch_tlb_flush`（`poc/kernel/core/src/vm/vmar/vm_mapping.rs:830-837`，`poc/ostd/src/mm/vm_space.rs:1063`）。第二次当前遇到空队列提前返回，不能描述成第二次 Host shootdown。可明确 API 的 dispatch 责任并减少冗余空检查，但它也属于原生 Asterinas 共享代码，需要单独计量。

验证至少包含连续/离散 1、4、5、31、32 页、小范围 mprotect/unmap、远端 CPU 正在访问和失效后的重新读取。64 MiB 结果或 `getpid` 结果不能检验五页批次的策略。

## 5. M4：每个地址空间有一个软件根物理页和 Linux PGD

`VmSpace::new` 先让 Host 分配 Linux root，再调用 `PageTable::new_kernelet_user_page_table` 分配 grant 中的 OSTD 根（`poc/ostd/src/mm/vm_space.rs:257-266`，`page_table/mod.rs:354-357`）。`write_pte` 先写这个 OSTD 根，在顶层项变化时再镜像 Linux PGD；开启 PTI 时还写对应 user PGD（`page_table/node/mod.rs:288-323`）。下层表并非全部双份复制，不能夸大成两套完整硬件页表。

这个 vOSTD 顶层物理页主要服务 OSTD 的管理/所有权表示。可以研究让软件根对象持有锁和子树所有权，直接操作 Linux 所有的硬件根，从而消除这额外的 4 KiB 页和顶层镜像。但原 `PageTableNode` 本身就是 `Frame<PageTablePageMeta>`，其析构遍历子项释放下层 Frame（`page_table/node/mod.rs:64,390-423`）。直接删页或把 Linux root 伪装成 grant `Frame` 会破坏元数据和释放归属。

Linux `mm_struct` 还承载 carrier 的地址空间身份、CPU/TLB 跟踪和销毁集成；移除第二份软件根不等于可以删除 `mm_struct`。正常 syscall 使用同一个激活地址空间时，`VmSpace::activate:557-558` 有命中缓存返回，Host 也只在 `current->mm != target` 时切换（`poc_space.c:339-379`）。不能将双层所有权表示等同于每次 `getpid` 多写 CR3。

## 6. M5：预分配与重复清零

Host 创建时将 `grant_mb` 同时作为初始粒度数和上限，循环把所有 2 MiB grain 以 `__GFP_ZERO` 分配，并为每个 grain 分配、初始化、映射 8 个 metadata 页（`poc/linux/endovisor/poc_grant.c:383-386,45-99,554-568`）。在 256 MiB 设置下是 128 个 grain、4 MiB 的 metadata 物理页；metadata 的大 vmalloc 窗口是地址空间预留，不等于该窗口大小的物理占用。全量取得和清零是冷启动政策，不是稳态 `getpid` 的逐次工作。

其后 `FrameAllocOptions` 默认 `zeroed=true`，分配 Frame 后再次 `write_bytes` 清零（`poc/ostd/src/mm/frame/allocator.rs:43-76`）；页表节点也请求清零（`page_table/node/mod.rs:91-98`）。可以为仍保持 Host 初始零内容的页面记录 known-zero 状态，首次分配时省去第二次清零，或调整初始 grant 大小与按需取得策略。页面被 Buddy/slab/tenant 使用、释放或复用后不能继续把它当成 fresh；取消所有清零会违反匿名页语义和跨对象/实例隔离。

当前 `poc_do_grains_request` 在已到 `max_grains` 时返回 0（`poc_grant.c:149-159`），初始循环却已经填满这个上限。分配失败路径仍可尝试一次已无法增长的 Host refill（`frame/allocator.rs:19-29`，`image_grant.rs:85-106`）。可以显式发布当前容量/上限，避免固定 grant 耗尽时的无效往返；若决定按需增长，则应将 initial 与 maximum 分开并证明发布、元数据和失败回滚。这是 OOM/refill 路径，不计入普通分配命中的固定开销。

## 7. M6：RCU 等待可以改粒度，不能只异步释放 Linux mm

`VmSpace::drop` 先调 `pt_root_unregister`，再由字段析构释放 OSTD 页表（`poc/ostd/src/mm/vm_space.rs:230-241`）。Host teardown 先清顶层、`flush_tlb_mm_range(..., freed_tables=true)`，默认再 `synchronize_rcu()` 后返回（`poc/linux/endovisor/poc_space.c:253-312`）。这里的等待保护 Linux 的锁外页表观察者，Image 内部的 RCU 不等于 Host RCU。

`poc_async_destroy=1` 只把 `sp/mm` 回收放进 `call_rcu`，没有把 Image 下层页表 Frame 的回收一并推迟。若调用服务立刻返回而 Image 继续 drop/free 下层 Frame，仅延后 Linux mm 并不满足同一回收谓词。旧报告的异步退出数值只能是带此限制的诊断消融，不能据更快就把它当成正确优化。

存在两个更具体的方向：

1. 沙盒整体销毁时，`poc_spaces_destroy:437-454` 已先取消所有 root 的发布，却对每个 root 调 `teardown(..., sync_destroy=true)`，每次分别等待 Host RCU。可将“全部停用、清顶层并完成 TLB 同步”与“统一等待一个宽限期后回收”分成两阶段，合并等待。必须确认全部 carrier/异步引用已经不再访问，并保留各 root 的 ref drain 与 flush。
2. 单个 `VmSpace` 销毁若要异步化，需要把其下层表/Frame 的真正再分配推迟到 Host 安全完成的时点，而不是只推迟 `mmput`；可设计退休批次/完成通知，明确 Image 仍活着或整个沙盒结束时由谁最终释放。

验证应同时检查 Host perf/NMI/锁外 walker、远端 lazy TLB、地址空间切换、强杀与释放后复用；单看正常退出与模块卸载不是完整安全证据。普通 `getpid` 不销毁地址空间，不能用默认 RCU 等待解释其差值。

## 8. M7：Task 栈的高水位缓存

`poc_kstack_alloc` 首次使用一个槽就分配并清零 64 页（256 KiB），建立映射；`poc_kstack_free` 只清 live 位和 allocated 标志，保留物理页与映射，直到 `poc_stack_pool_destroy` 才解除映射并释放（`poc/linux/endovisor/poc_grant.c:218-275,278-300,331-365`）。这降低再次建栈成本，却使物理占用保持在该实例曾用栈槽的高水位。

可调成有界空闲槽缓存、后台退栈回收或按已证明的栈用量选择大小；必须在 Task 完全退栈、Host 不再重定向到旧地址且相关 TLB/映射失效完成之后释放。guard 虚拟区间不占同量物理页，不能把 512 KiB stride 全算成物理内存。Image 栈与 Linux carrier 栈分别按内部 Task 和 carrier/vCPU 建立，也不是为每个 tenant Task 复制一个 Linux Task 栈。原生 Asterinas 栈默认本身是 128 页（`poc/ostd/src/task/kernel_stack.rs:24-40`），不能仅因 PoC 是 256 KiB 就声称比原生 Asterinas 更大；实际原生构建的环境覆盖值仍需核对。

## 9. M8：创建期容量与复制

`poc_grant_init:403-410` 为 RunDesc 预留 `max_meta_sections × 64` 项，`max_meta_sections = max_grains`。当前 Host 的 grain 数不会超过 `max_grains`，每次新增 grain 最多新增一个 run；256 MiB 配置下即为最多 128 个实际 run，却按 8192 项容量分配 32 页，而 128 个 16-byte 描述符只需 1 页。差值为 31 页（124 KiB）每实例，属于源码可推导的容量差，不是实测节省。Image entry 对 run table 采用同样的最大容量边界，所以必须共同收紧 ABI 与验证，不能只缩 Host allocation。

同文件 `441-472` 每实例复制并映射只读 initramfs，可研究对同内容的 sealed/固定来源缓存共享，由 kind/内容对象持有引用直到最后实例结束。`poc_image_load:536-568` 已经在 kind 级共享 text/rodata，不能再把它说成每实例重复复制；`poc_image_start:632-648,672-702` 保持私有 data 与 CPU-local。这些副本有隔离作用，合并应明确 COW、重定位和写入归属，不直接共享可变数据。

## 10. 当前 PoC 已经使用本地堆

`poc/kernel/core/src/vm/mod.rs:12-27` 注册 OSDK FrameAllocator 和 HeapAllocator；OSTD 全局分配经 `mm/heap/mod.rs:108-132`，大块从本地 Frame 分配（`mm/heap/slot.rs:81-98`）。本轮额外只读核对了 `poc/osdk/deps/{heap-allocator,frame-allocator}/src`，对应内容随后按同一 hash 补入快照的 `additional_primary_sources`：小对象命中 per-CPU cache，本地 Frame 命中缓存/本地池，只有 refill 失败路径才请求 Host grain。

因此 `prototype/vostd` 的 `HostHeap → mem_alloc/mem_free → Linux kmalloc` 讨论不适用于当前 PoC 的每次 Rust 分配；“把堆移回 grant 消除逐次宿主调用”在这里不是待实现的 syscall 优化。OSDK per-CPU 对象/页缓存可能在小 grant 中持有可复用内存，影响容量和回收，但它也是原生 Asterinas 的共享分配器政策；调整大小或跨核回收需要分别测容量、锁争用和吞吐，不能只当作 Kernelet 独有负担。

`cow_copy_pt` 的逐页 Frame 引用、游标查询/保护/映射，和 COW 的 unmap→map 安全接口也主要来自共享 Asterinas MM。可研究原子替换映射、减少重复查询及扩大批次，但需要保留旧 Frame 到 TLB/RCU 安全点；不能把这类通用 MM 算法成本全部记为 Kernelet 引入。

## 11. 现有内存比值的语义与证据缺口

### B1：`MADV_NOHUGEPAGE` 没有被确认生效

本次读取的当前 Linux `.config:235,824-827` 是 `# CONFIG_ADVISE_SYSCALLS is not set`、`CONFIG_TRANSPARENT_HUGEPAGE=y`、`CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y`。而 `bench_mm.c::alloc_anon_64m:87`、memfd `134`、populate `158` 都丢弃 `madvise` 返回值。此配置下不能靠这些调用保证 4 KiB 页；populate 场景还在 `mmap(MAP_POPULATE)` 计时结束之后才调用 madvise，即使调用成功也不能证明 mmap 期间的页表粒度。

已检查 `stage4_r1_native.log` 到 `stage4_r5_native.log`：有 `MM_BENCH_INFO ... pages=16384` 和各项计时，没有找到 `ru_minflt`/实际 fault 数、`AnonHugePages`、`KernelPageSize`、madvise errno 或映射粒度证据。`pages=16384` 是基准源文件常量和归一化分母，不是从页表读出的实际 PTE 数。旧运行是否实际用了 THP 未能由这些日志确认；当前 `.config` 也未与旧内核作内容 hash 对应。因此不能直接认定 THP 解释了多少旧比值，但原报告“双方固定 16,384 个 4 KiB PTE”的前提尚不成立。

下一轮应选择明确关闭 THP 的构建或启动策略，检查 madvise 返回、实际映射粒度和 fault 数，才把 fork/mprotect/COW 结果解释为逐 PTE/逐缺页工作量。这项测量条件修复不算 Kernelet 代码优化。

### B2：`MAP_POPULATE` 的两侧完成工作不同

当前 Asterinas `do_sys_mmap` 解析 `MAP_POPULATE` flag，却在匿名映射分支直接 `options.build()`，没有相应预缺页动作（`poc/kernel/core/src/syscall/mmap.rs:106-123,244-277`）。因此 Native 的 mmap 时间和 Image 的 mmap 时间不能直接当作同样的填表操作。需要实现等价 eager 工作，或比较经验证的 mmap+首次触及总工作；语义变化与 handoff 成本分开报告。

### B3：COW 和退出的计时窗口

`bench_cow_write` 的单引用场景确实先等待 child 退出，双引用场景用 ready/go 管道保持 child 存活（`bench_mm.c:278-341`）。但现有程序没有验证实际 COW fault 次数/页粒度；“child 已退出”本身不证明两边均执行 16,384 次 reuse fault。不得把旧 `cow_write_1ref` 巨大比值全部归给异常交接。

`measure_child_exit:398-405` 先向 go pipe 写入放行字节，再取 `t0` 并 `waitpid`。child 可以在 `t0` 前已经开始或完成 close/exit。该值包含剩余等待/通知/调度，可能漏掉部分真实退出，并非完整 `VmSpace::drop` 或 `synchronize_rcu` 费用。需要明确选择“parent 放行至 wait 完成”的端到端窗口，或另做子进程/内核边界观测，保持两侧相同定义。

## 12. 来源与验证限制

关键快照 SHA-256：

| 文件 | SHA-256 |
|---|---|
| `poc/linux/endovisor/poc_grant.c` | `e618e96f978954ad47113cdf10cc51e130a6fc6a6f1d3e6b9a38cf2fcbc37e46` |
| `poc/linux/endovisor/poc_space.c` | `b0db37b65b0ef154b2822aec530622e2cdcb493aeb2c7dc12f77d57449b2474e` |
| `poc/ostd/src/mm/vm_space.rs` | `92e9db2b9aca0cd895236db53a6360d8ed11599ca74f26683a0ddee901648e7e` |
| `poc/kernel/core/src/vm/vmar/vm_mapping.rs` | `9181e6683764edea7b25c8e5cc0293b0fc439078246cf450ec9e6c27bf6b574d` |
| `poc/linux/bench/bench_mm.c` | `26ec663704dec8c4e7d03c1f7fb09467a3d1f0e4775e44978dcfa5579cdb353d` |

补充来源 SHA-256：原始快照已包含的 Linux `.config` 为 `ac9ce6d2e6b53690110d3e5f90bed83002d03a57b1d16b480bdd8547d9885c42`；后来按同一内容补入 `additional_primary_sources` 的 `poc/osdk/deps/heap-allocator/src/allocator.rs` 为 `0f1e4d395e3fe8c36f8304b891bb87799387c099e351e67fb82098a36bb13a7b`，`poc/osdk/deps/frame-allocator/src/lib.rs` 为 `3c39f11a5d51ce24160ce2ec3d860800dc8335075098917574cf774aa0f93ec2`。它们没有被当作历史轮次的哈希。

直接读过的范围包括 grant/image/space/main 的创建与回收、Image Frame/heap/page-table/VM/TLB、对应 VMAR fork/缺页/保护/卸载、OSDK 分配器和 C 基准。未完整审查所有 I/O 子系统、页表 walker 并发时序或分配器每个底层实现，也未证明所有候选在当前 release 机器码中形成了不可消除的指令。本报告是源码审查及历史证据审计，不是新增性能结果或完整内存安全证明。未建立临时文件；只读快照由主代理统一管理。

## 13. 收尾时的增量源码核对

在 `2026-11-17T05:43:59Z` 至 `05:44:43Z` 重新读取工作区，并与 05:32:23 快照比较。这个时间窗内源树仍在清理，不把它当作一次全树原子快照；下表与 hash 对应实际读取版本，后续改动需要再核对。前文的原始行号继续指向 05:32 快照，本节列部分当前行号便于导航。

本次变化主要删除 `kernelet-host`、RQ1/diagnostic 支持及旧 Host 测试。当前 Linux-as-Host PoC 的 Image 使用 `feature = "kernelet"`；删掉本就未进入该 Image 发布构建的旧 Host 分支，不等于实施了一个新的运行期 MM 优化，也不证明旧实验计时有所变化。

| 项目 | 增量核对状态 |
|---|---|
| M1 | 仍成立。当前 `vm_space.rs::map:504`、`unmap:638`、`protect_next:754` 仍以 `pt_mode == 1` 选择 VMA 服务；Direct 路径及逐次模式判断均未改成另一实现。 |
| M2 | 仍是候选。`frame/meta.rs` 只删除旧 Host 所用的两个 offset 常量；`get_slot:236` 与 `frame_paddr:378` 的查询行为不变。`node/mod.rs::write_pte:248` 仍先作 grant 检查，在 `267` 读取根字段后才测试层级。未新增缓存节点物理地址或合并 metadata 查找。 |
| M3 | 仍是候选。`tlb.rs` 删除旧 Host dispatch helper 和诊断 tokens，Image `shootdown_range:378-383` 的 `num_ops > 4 → full flush` 仍存在；Host 同步失效和 Frame 退休规则未改变。 |
| M4 | 仍是候选。`VmSpace::new:99-124` 仍分别取得 Linux root 和 `new_kernelet_user_page_table`；后者当前在 `page_table/mod.rs:348` 分配 OSTD root。被删除的是旧 Asterinas-as-Host 的 `RegisteredPageTable/RootActivation`，不是这里的软件根或 Linux PGD。 |
| M5 | 仍成立。`poc_grant.c`、Image `image_grant.rs`、`frame/allocator.rs` 与原快照逐字节相同；全量初始 grant、清零与 refill 失败行为未变。 |
| M6 | 仍成立。`poc_space.c` 与原快照相同，当前 `VmSpace::drop:83-94` 仍先 unregister 再由字段析构释放页表；没有新的统一 Host RCU 批次或 Image Frame 延迟回收协议。 |
| M7 | 仍成立。Host 栈池实现未变。`task/kernel_stack.rs` 只删旧 Host reservation 常量，原生默认 128 页未变；`task/mod.rs` 和 `processor.rs` 清理旧 Host/diagnostic 字段及 hook，没有给 Image 栈池新增收缩或回收政策。 |
| M8 | 仍成立。Host grant/image/main 与原快照相同；Image entry 的 `run_bytes = max_meta_sections × grains_per_section × sizeof(RunDesc)` 仍在 `entry.rs:63-67`。没有收紧 RunDesc 容量或新增只读 initramfs 共享。 |
| B1–B3 | `bench_mm.c`、`.config`、Asterinas `mmap.rs`、VMAR mapping/fork 与原快照相同；忽略 madvise 返回、THP 前提缺口、MAP_POPULATE 工作不同和退出计时窗口问题均保留。本次未新增能确认历史实际页粒度/缺页数的证据。 |

Task accounting 的 `cfg` 也已从包含 Host/diagnostic 的组合收窄为 `kernelet/ktest`，但 Image 的调度采样/恢复分支仍编译；不能把这次条件清理记为“Image 所有 accounting 已移除”。本次没有构建或重测来判断清理后的二进制可运行性和速度。

增量版本 SHA-256（`vm_space.rs` 于 `05:44:43Z` 单次读取，其余为 `05:44:23Z` 读取）：

| 文件（均为 `poc/ostd/src/` 下） | SHA-256 |
|---|---|
| `mm/frame/meta.rs` | `fd67243581246b37b816fff6bfdb356ad05999458d1b92b1fe80698d345d3536` |
| `mm/page_table/mod.rs` | `5e07cdd2a4b85a13950828e8d9e8d7d0d397310e65515c52702251236973eb2b` |
| `mm/page_table/node/mod.rs` | `c50f44ae480c32fe98e229e8ad49d812e2215ba5ffe9486739cf0fec45c02c22` |
| `mm/tlb.rs` | `86c68b8f8bd56f3f4a291c917487f758c229602570ac24dc34da7c0bfe984d04` |
| `mm/vm_space.rs` | `dc27ae0ac1ad969a184653b74b8a9492598eed667fd077cfa34b5ad982c678d0` |
| `task/mod.rs` | `e63e926ca528adad3219a50071e38b6dc4d7edd3aa6f61d93c733a00ad0d41bd` |
| `task/processor.rs` | `108ca3ea6fa47ca0d65197769f42fce3dcb4fe97773310e406847f55b8139c5d` |
| `task/kernel_stack.rs` | `4628876ba1633f50b87cb4992ccb6321c03b780ab7b37a1bd2730ed8ed932660` |
| `task/accounting.rs` | `ad039d04f090e22c8a1897c163c6f719bfae66ce1a9eb5777d3f5c06f6a2e9ae` |
| `task/scheduler/mod.rs` | `fce488ff3d85b8878b680ea20f04edf09c16d78d613444f9cea307fd78a8d5d6` |
