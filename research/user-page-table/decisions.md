# 用户页表：讨论与决策记录

这里记录"kernelet 的 PTE 由谁来写"这个问题的讨论过程和决策点，一次讨论一个问题。

- **方案 A**：维持现状，每个 PTE 都由 Linux 写，用 batching 降低服务调用的开销（提案 `2026-11-13-batched-memory-services`）。
- **方案 B**：kernelet 进程对应的 Linux mm 只当作一个壳，用户半区不建 VMA，页表内容由 vOSTD 直接写。

状态标记：**已决定**（用户拍板）、**共识**（讨论中确认的事实或理解）、**待决定**（有选项，等用户选）、**未讨论**。

---

## 已决定

| 编号 | 日期 | 决定 |
|---|---|---|
| U1 | 2026-11-13 | 对比必须在同一台 QEMU 虚拟机里做：同一个内核，同样的 `-smp 2 -m 512M`，KVM。不能拿宿主机和虚拟机的数直接比 |
| U2 | 2026-11-14 | 提案只解决页表（PTE）写入的成本 |
| U3 | 2026-11-14 | 四类操作都要测：装入、复制、改权限、清除（计划见 `../mem-baseline/plan.md`） |
| U4 | 2026-11-14 | 讨论记录放在 `research/`，加入 `.git/info/exclude`，不进仓库 |
| U5 | 2026-11-14 | 质疑"每个 PTE 都由 Linux 写"这个前提，把方案 B 作为认真考虑的选项，逐个问题讨论清楚 |
| U7 | 2026-11-14 | **方向：方案 B（vOSTD 直接写用户页表）作为主方案，batching（方案 A）作为 alternative。** 后续的提案以方案 B 为主体，batching 写进它的 Alternatives 一节。原来那份 `book/src/design-proposals/2026-11-13-batched-memory-services.md`（还没提交）以后要据此改写，具体怎么改另行决定 |
| U8 | 2026-11-14 | **引入通用的用户态异常钩子**，机制和 syscall 钩子一样，取代现在"VMA `fault` 回调"和"信号转异常"这两条路径。**范围只覆盖 kernel proper（Asterinas）支持的异常**：#PF、#DE、#DB、#BP、#OF、#UD、#SS、#GP、#MF、#XM、#AC。#AC 的 split lock 和 #NM 的 XFD 仍然由 Linux 先处理。不转发的异常交给 Linux 按默认方式处理：carrier 被杀死，sandbox 随之结束并被清理（用户确认，2026-11-14） |
| U9 | 2026-11-15 | **提案从第一性原理推导。** 改写 `2026-11-13-batched-memory-services.md`（现已更名为 `2026-11-13-direct-page-table-updates-in-vostd.md`）时，不以"书里的理由、我们的反驳"作主线，而是从基本事实出发：事实 → 要求 → 最小分工 → 设计，再用同一套要求评价其他方案（包括现在的设计和 batching）。大纲记录在 `proposal-outline.md`；当前 `2026-11-13-direct-page-table-updates-in-vostd.md` 先以紧凑提案结构落地，后续若展开全文可按此大纲组织 |
| U6 | 2026-11-14 | **R3：不保留宿主对页表写入的逐页把关。** 页表写入的安全性由 vOSTD 保证：kernel proper 只能通过 `UFrame` 和 `PageProperty` 请求映射，由 vOSTD 构造 PTE，这和 Asterinas 在裸机上的论证一致。因此 R3 不再构成选择方案 A 的理由 |

## 共识

| 编号 | 内容 | 依据 |
|---|---|---|
| C1 | carrier 是一个 Linux 用户任务，tenant 以它的用户态身份运行：系统调用、中断、缺页都会先进入 Linux 的入口代码，并且经由 Linux 的返回路径回到 tenant | `book/src/accepted-design/into-user-mode-and-back.md:60` |
| C2 | 每个 kernelet 进程（`VmSpace`）都对应一个 Linux mm。carrier 换到另一个进程运行时，用 `kernelet_switch_mm()` 切换 `current->mm` 并装载 CR3。现在的设计已经解决了"CR3 怎么和 Linux 的调度配合"这个问题 | `tenant-memory-on-linux-page-tables.md` 的 "The address-space switch" 一节 |
| C3 | "Linux 的页表是唯一的页表"其实是两条，要分开看：(i) CPU 遍历的就是 `mm->pgd`，不搞影子页表，这一条要保留；(ii) 每个 PTE 都由 Linux 写，这一条只是设计选择，**不是必须的** | 讨论 |
| C4 | (ii) 换来的是：借用 Linux 自己代码的正确性（补丁很小）、kill 时的清理不依赖 kernelet 的状态、每个物理页都经过可信代码检查、页表页计入 Linux 的记账。其中逐页检查在书的威胁模型下只是纵深防御：vOSTD 本身是可信的，`UFrame` 类型已经保证了物理页来自 grant | `why-a-kernel-of-your-own.md:51-53`、`what-it-costs.md:78` |
| C5 | 方案 B 下的 carrier 不是内核线程：`tsk->mm` 非空，它也会回到用户态。它是一个"在 Linux 看来地址空间是空的用户任务" | 讨论 |
| C6 | `mm_alloc()` 创建的是空 mm，没有 vdso，也没有栈。现在这个 mm 里只有 endovisor 建的那一块 PFNMAP 区域；方案 B 下一个 VMA 都没有 | `kernelet_mm_alloc()` |
| C8 | CPU 只认 CR3 指向的页表；carrier 运行时，Linux 在每次调度时把 CR3 设成 `current->mm->pgd`（`arch/x86/mm/tlb.c:635,640`，`load_new_mm_cr3(next->pgd, …)`）。因此：**页表的"壳"必须由 Linux 管理**，包括根页、根页里内核半区的项、CR3 的装载、PCID、TLB 刷新的记账；**用户半区的内容（根页里用户半区的项，以及其下各级页表页和 PTE）没有技术上的必要由 Linux 维护**。这只是技术判断，不是决定：要不要这样改，取决于 R3、R4、R8 这几条理由是否成立，以及 Linux 现在顺带做的事（缺页分发、退出时清理、并发控制）换成我们自己做的代价 | 讨论，2026-11-14 |
| C9 | **没有必要让 Linux 维护用户页表**（用户确认，2026-11-14）。书里很大一部分设计，都是"让 Linux 来写用户页表"这个选择推出来的结果，不让 Linux 写之后可以去掉或简化：PFNMAP 区域（VMA）及其 `VM_SHARED`、`VM_DONTCOPY`、区域边界和 *special* 位（*special* 位可能保留作为防御）；`fault` 和 `pfn_mkwrite` 回调（改为缺页钩子）；每页一次的 `vm_map` 和 `vm_protect` 服务；每次服务都拿 `mmap_lock` 并查找区域；写后再检查槽位；PAT 查询；withheld set（可改为像 OSTD 一样编码成"有效但不在内存中"的项）；睡眠规则第 2 条对 `map`、`protect` 不再成立；只能用 4 KiB 页的限制。**不是**由这个选择带来、需要保留的：每个 `VmSpace` 一个 mm 和 `kernelet_switch_mm`；范围锁、RCU 宽限期、待回收列表、表项持有物理页的引用；跨核 TLB 刷新走 Linux。剩下的 B5 审查是"把方案 B 做对"的工程确认，不推翻这个结论 | 第一部分 R1 到 R8 |
| C7 | carrier 必须是用户任务，不能是内核线程，因为 tenant 在 ring 3 运行；carrier 必须有 mm，因为 CPU 要遍历 `mm->pgd`。**但 VMA 不是必须的**：硬件只看页表，不看 VMA。没有 VMA 时，已映射的页可以直接访问；没映射的页照样触发 #PF，照样进入 `exc_page_fault` → `do_user_addr_fault`，只是因为找不到 VMA，最后走到发 `SIGSEGV` 这个分支。VMA 只决定 Linux 进入异常路径之后走哪个分支，不决定会不会进入 | `arch/x86/mm/fault.c`（6.12）第 1272、1481、1493 行 |

---

## 第一部分：书中方案的理由，逐条审视是否必要

相关工作的调研见 `prior-art.md`（2026-11-14）。要点：凡是"每次修改都由宿主检查"的系统，写页表的那一方都是不可信的，而 kernelet 里真正写页表的 vOSTD 是可信的。

先不设计替代方案。对书里给出的每一条理由，弄清楚三件事：它到底在说什么；它依赖什么前提；它是不是必要的。

| 编号 | 书里的说法 | 出处 | 状态 |
|---|---|---|---|
| R1 | "only Linux writes it, under its own locks, with its own bookkeeping of what every entry means"：每个 PTE 都由 Linux 写（也就是那个不变式） | `tenant-memory-on-linux-page-tables.md:9` | **已讨论**：R1 是推论，不是独立的理由 |
| R2 | "vOSTD cannot write a Linux page-table entry, and it cannot make the processor walk a table of its own"：vOSTD 写不了 PTE，也没法让 CPU 遍历自己的表 | 同上 `:9` | **已讨论**：书没有考虑过做法二，只是断言了一句；推测的原因分别归到 R3、R6、R7、R8 |
| R3 | "no translation reaches the hardware without trusted host code having checked the frame"；"the price of letting trusted code check every frame"：每个物理页都要经过可信代码检查 | `tenant-memory-on-linux-page-tables.md:24`、`what-it-costs.md:78` | **已决定（U6）**：靠 vOSTD，不保留宿主逐页把关 |
| R4 | "it is the design's whole reason: any scheme that let Linux's page table be filled lazily ... would pay a fault"：提前映射，避免第一次访问时缺页 | `what-it-costs.md:76` | **已讨论**：R4 只排除影子页表，不支持"由 Linux 写" |
| R5 | 每次服务都拿 `mmap_lock` 并重新查找区域，"the discipline Linux's own code follows" | `tenant-memory-on-linux-page-tables.md:159` | **已讨论**：推论（有 VMA 才需要） |
| R6 | VMA 带来的一串约束：`VM_SHARED`（否则 `BUG_ON`）、`VM_DONTCOPY`、区域范围、*special* 位、`pfn_mkwrite` | `tenant-memory-on-linux-page-tables.md:84-86, 205-224` | **已讨论**：推论；*special* 位可能仍值得保留（待 B5 核实） |
| R7 | 无锁读依赖于"endovisor 的引用让页表一直存活"和"Linux 用单次 store 写 PTE" | `what-vostd-adds-on-top.md:326` | **讨论中** |
| R8 | kill 时"不整理，直接丢弃"：endovisor 整体收回，不看 kernelet 内部的状态 | `stopping-a-kernelet.md:11` | **讨论中** |

### R1：每个 PTE 都由 Linux 写

**书里的说法。** CPU 遍历的那张表，只有 Linux 会写，而且是在 Linux 自己的锁下写，并由 Linux 自己记录"每一项是什么意思"。所以 vOSTD 一项都不写，所有修改都通过服务请 endovisor 调用 Linux 的函数。

**"Linux 自己的记账"具体是什么。** 对 kernelet 这块区域（一个 `VM_PFNMAP` 区域，每个 PTE 都带 *special* 位），我在 Linux 6.12 里逐项核对过：

| # | 记账内容 | 对 kernelet 的 PTE 是否适用 | 依据 |
|---|---|---|---|
| 1 | 物理页的引用计数、mapcount、反向映射（rmap） | **不适用**。*special* 项让 `vm_normal_page()` 返回 `NULL`，Linux 不认为这是它管理的页，不加引用，也不进 rmap | `mm/memory.c` 的 `vm_normal_page()` |
| 2 | RSS 等 mm 计数 | **不适用**，原因同上 | 同上 |
| 3 | 页表页本身：由 Linux 分配（`GFP_PGTABLE_USER` 带 `__GFP_ACCOUNT`，计入 memcg）；初始化 PTE 锁；统计 `NR_PAGETABLE` 和 `mm->pgtables_bytes`；只能由 Linux 的 `free_pgtables` 释放 | 适用，但前提是**页表页是 Linux 分配的** | `include/asm-generic/pgalloc.h:8`、`include/linux/mm.h:2981` |
| 4 | 并发：`mmap_lock` 和 PTE 锁，保证和 Linux 自己的 zap、退出、缺页路径互斥 | 适用，但前提是**这段地址有 Linux 的 VMA，Linux 自己的代码也会来改它** | — |
| 5 | VMA 记录这段地址"是 PFNMAP"，这样 zap 时才知道不能去减引用 | 适用，前提同 4 | — |
| 6 | PAT 内存类型（`track_pfn_insert`） | 和谁来写无关：任何人写 PTE 都要给出正确的内存类型位。grant 里的页是普通 RAM，用 WB 就对 | `arch/x86/mm/pat/memtype.c` |
| 7 | mmu notifier：zap 时通知二级 MMU（KVM、IOMMU SVA） | 这个 mm 上没有注册二级 MMU | — |
| 8 | TLB 刷新的记账（`tlb_gen`、PCID） | 管的是**刷新**，不是**写入**：无论谁来写 PTE，刷新都可以继续交给 Linux 的 `flush_tlb_mm_range` | — |

**分析。**

1. 正因为这块区域是 PFNMAP，Linux 对它的每一项几乎**不记任何"含义"**（第 1、2 行）。书里说的"its own bookkeeping of what every entry means"，指的是 Linux 管理普通内存时的情况；而 kernelet 这块区域之所以设成 PFNMAP，恰恰就是为了让 Linux 不去记这些账。
2. 剩下真正生效的记账（第 3、4、5 行）都有一个共同前提：**这些 PTE 放在 Linux 分配的页表页里，并且被一个 Linux 的 VMA 覆盖着**。在这个前提下，"只能由 Linux 写"确实成立：否则 vOSTD 会和 Linux 自己的 zap、退出路径并发，在 ring 0 里出错。
3. 所以 R1 不是一条独立的理由，而是**一个推论**：它是"把 PTE 放进 Linux 管理的页表、并用 VMA 覆盖"这个选择带来的结果。真正需要回答的问题因此变成了：**为什么一定要把 PTE 放进 Linux 管理的页表、用 VMA 覆盖？** 这要看 R3（逐页检查）、R4（避免缺页）、R6（VMA 的约束）、R8（kill 时的清理）这几条理由。
4. 第 6、8 行和谁来写无关，任何设计都要处理。

**因果链（2026-11-14 澄清）。** 记账不是目的，而是副作用：

1. 书选择让 Linux 的函数来写 PTE，vOSTD 不写；
2. Linux 导出的、能写用户 PTE 的函数都要一个 VMA 作参数（`vmf_insert_pfn_prot(vma, …)`、`zap_vma_ptes(vma, …)`），所以 endovisor 先建了一个 PFNMAP 区域；
3. 有了 VMA，Linux 就把这段地址当成自己的来管：页表页由 Linux 分配，缺页、zap、进程退出时 Linux 都会来动这段 PTE；
4. 于是 vOSTD 不能再自己写，否则会和 Linux 并发修改。这就是 R1。

R1 在这条链的最下游。真正要追问的是第 1 步为什么要让 Linux 来写，书里给的理由是 R3 和 R4。

**待用户判断。** R1 本身不是必要的，它只是一个推论，必要与否取决于它的前提。用户同意这个判断吗？如果同意，接下来就逐条审视它的前提：先看 R4，也就是书里说的"the design's whole reason"。

### R4：提前映射，避免第一次访问时缺页

**书里的说法**（`what-it-costs.md:76`）：页一旦被 kernel 映射，第一次访问就不花什么代价。因为 `vm_map` 一返回，这一项就已经在 Linux 的页表里了，tenant 第一次访问只是一次 TLB miss 加一次硬件遍历（书里是 82 周期，这次在虚拟机里测的是 64 周期），不会缺页。书里称这是"the design's whole reason"：任何让 Linux 页表按需、延迟填充的方案，都要在每页第一次访问时付出一次缺页，代价是硬件遍历的很多倍。

**澄清：两种"延迟"不能混为一谈（2026-11-14，用户提问）。**

- **延迟分配（按需调页）**：`mmap` 时不分配物理页，第一次访问时缺页，这时才分配并映射。这是 kernel proper 的内存管理策略，是正常内核的做法，**无论哪种方案都保留**。
- **延迟生效（影子页表）**：kernel proper 已经调用了 `map` 之后，这一项是立即出现在 CPU 用的页表里，还是要等 CPU 再缺页一次才补进去。**R4 讨论的只是这一层。**

R4 里的"提前"指 `map` 调用后立即生效，不是"mmap 时就把所有物理页分配好"。mem-perf 一次映射 64 MiB，是微基准测试的设定，不是分配策略。

影子页表多出来的那次缺页，在 kernel proper 一次映射多页时代价最大：fault-around 时其余 15 页，fork 后子进程访问的每一页，exec 和 `MAP_POPULATE` 一次装入的整段，都要再各缺页一次。

**书拿来对比的是什么方案**：延迟填充，也就是影子页表。kernel proper 把映射写进一张 CPU 不用的表；Linux 的页表一开始是空的；tenant 第一次访问某页时缺页，再由 endovisor 照着那张表把这一项补进 Linux 的页表。

**三种方案对比**：

| 方案 | `map` 返回时，CPU 的页表里有这一项吗 | 第一次访问的代价 | 每次 `map` 的代价 |
|---|---|---|---|
| 延迟填充（书里用来对比的方案） | 没有 | 一次缺页，数千周期 | 便宜（只写一张 CPU 不用的表） |
| 书的方案：提前映射，由 Linux 写 | 有 | 一次硬件遍历，64 到 82 周期 | 一次服务调用，447 到 780 周期 |
| 做法二：提前映射，由 vOSTD 直接写进 `mm->pgd` 的用户半区 | 有 | 一次硬件遍历，和书的方案一样 | 直接写内存，估计几十周期（**未测**；参考值：Linux 在 `copy_pte_range` 里每页约 66 周期） |

**分析**：

1. R4 是一个正确的论证，但它论证的是**提前映射优于延迟填充**。
2. R4 没有论证**为什么要由 Linux 来写**。书的方案和做法二都是提前映射，第一次访问的代价完全一样。
3. 书之所以只拿"提前映射、由 Linux 写"和"延迟填充"这两个方案来比，是因为它在 R2 里认定 vOSTD 写不了 PTE（"vOSTD cannot write a Linux page-table entry"）。做法二从一开始就没有被列为选项。
4. 所以 R4 不能支持第 5 步"选做法一而不选做法二"。它只能排除延迟填充，而做法二本来也不是延迟填充。

**待用户判断**：R4 论证的是"提前映射"，不是"由 Linux 写"，所以它不能作为让 Linux 维护用户页表的理由。用户同意吗？

### R3：每个物理页都要经过可信宿主代码检查

**书里的说法**：

- `tenant-memory-on-linux-page-tables.md:24`：比裸机上的内核更强。裸机上框架的 bug 可能把任意物理页映射给 tenant；而这里任何翻译进入硬件之前，都经过了可信宿主代码的检查。
- `what-it-costs.md:78`：每页 780 周期，是"letting trusted code check every frame"的代价。

**endovisor 实际检查了什么**（`prototype/linux/endovisor/space.c:697-720`，`klet_space_insert`；以及 `klet_prot_to_pgprot`）：

1. 物理页属于这个 kernelet 的 grant（`klet_in_grant`），按页对齐，并且 `pfn_valid`；
2. 虚拟地址在区域范围内；
3. 权限位由 endovisor 用自己的常量构造（`vm_get_page_prot`），kernelet 只能传 R、W、X 三个位进来，所以不可能设置 *global* 位；
4. 写入后再查一次，确认这一项确实是刚写进去的那个物理页，用来发现"同一个页被映射两次"这种 vOSTD 的 bug。

**威胁模型**（`why-a-kernel-of-your-own.md:51-53`）：可能被攻破的是 kernel proper，tenant 的程序可以通过 bug 接管它；vOSTD 由运营方编译，属于可信计算基。

**这个检查防的是谁**：

- **防不了、也不需要防 kernel proper。** kernel proper 是安全 Rust，它只能调用 `cursor.map(UFrame, PageProperty)`。`UFrame` 只能从 vOSTD 的分配器里得到，而分配器只管理 grant 里的页，安全 Rust 伪造不出来。`PageProperty` 也是先由 vOSTD 转换成三个权限位（`vostd/src/mm/vm_space.rs:204` 的 `prot_bits`）。所以前面那四项检查，在 kernel proper 这一层就已经由类型保证了，和 Asterinas 在裸机上的论证一样。
- **防的只是 vOSTD 自己的 bug**，这是纵深防御。可是 vOSTD 运行在 ring 0，它的 bug 还有很多别的途径越界，这道检查都挡不住。比如 vOSTD 复制用户内存时，是通过物理页的 direct map 别名直接访问的（`what-vostd-adds-on-top.md:326`）：地址算错了，就能读写任意物理内存。

**R3 的代价从哪来**：检查本身很便宜，`klet_in_grant` 只是一次区间比较。贵的是它所依附的那次服务调用。所以：

- R3 能支持的是"每个物理页都由宿主检查"，不是"每个物理页都要一次服务调用"。方案 A 保留了检查，同时去掉了每页一次的调用。
- 方案 B 下，检查可以原样放进 vOSTD 的写入路径里，但它就和写入者处在同一个信任域里了，不再是宿主替你把关。

**和相关工作的对照**（`prior-art.md`）：Xen PV、Nested Kernel、CKI 之所以逐个检查，是因为写页表的那一方不可信。kernelet 里写页表的是 vOSTD，属于可信的一方。

**分析结论（待用户判断）**：

- R3 不是威胁模型要求的，它是一个**纵深防御的偏好**：宿主独立把关，不依赖 kernelet 这一份构建是否正确。
- 这道防线覆盖的范围有限：只挡页表写入这一条路，挡不住 vOSTD 通过 direct map 越界。
- **用户的决定（2026-11-14，U6）**：靠 vOSTD 就好，和 Asterinas 在裸机上一样。
- 当时的选项是：**我们是否愿意为"宿主对页表写入独立把关"这一层纵深防御付出代价？**
  - **愿意**：留在方案 A，用 batching 降低代价。
  - **不愿意**：方案 B 可行，安全性靠 vOSTD 的类型和可信构建保证，和 Asterinas 在裸机上的论证一致。

### R5：每次服务都拿 `mmap_lock`、重新查找区域

**书里的说法**（`tenant-memory-on-linux-page-tables.md:159`）：每次服务都拿地址空间的锁，并重新查找区域，不信任存下来的指针，这是 Linux 自己代码的规矩。

**为什么需要**：区域是一个 Linux 的 VMA，Linux 自己的代码（`vm_destroy` 时的 zap、进程退出时的 `exit_mmap`）也会动它。不拿锁就可能和它们并发；不重新查找，就可能用到一个已经被释放的 VMA 指针。

**分析**：R5 也是"有 VMA、并且用 Linux 的函数来写"带来的结果。方案 B 下没有 VMA，也就不需要查找和拿锁：

- vOSTD 多个写入者之间的互斥，由 vOSTD 自己的范围锁负责（`what-vostd-adds-on-top.md` 里的分段范围锁），和 OSTD 在裸机上一样；
- 写入者和"销毁这个地址空间"之间的互斥，靠空间的引用计数和生命周期来保证。这属于 B2、B8 要讨论的内容。

这一项对应提案里每页成本列表的第 3 项（查找空间、拿锁、查区域），方案 B 下整项消失。

**结论**：推论，不是独立的理由。

### R6：VMA 带来的一串约束

`tenant-memory-on-linux-page-tables.md:84-86, 205-224` 里列出的每一项，以及它们为什么存在：

| 约束 | 为什么存在 | 方案 B 下 |
|---|---|---|
| `VM_SHARED` | 往一个私有的写时复制区域里插入裸物理页号，在 Linux 里会触发 `BUG_ON` | 不用 Linux 的插入函数，这一项不存在 |
| `VM_DONTCOPY` | 防止 carrier 被 fork 时，Linux 把 kernelet 的页表项也复制过去 | fork 按 VMA 复制页表，没有 VMA 就什么都不复制，这一项不存在 |
| 区域正好覆盖可映射的范围 | 让超出范围的 `vm_map` 可以被拒绝；`zap_vma_ptes` 只有在范围完全落在区域内时才会生效 | 范围检查改由 vOSTD 做，OSTD 在创建 cursor 时本来就检查用户地址的上限 |
| *special* 位 | 让 Linux 清理这段页表时，不把 grant 里的页当作 Linux 管理的页去减引用 | Linux 不再按 VMA 清理这段页表，原来的理由消失。**但 vOSTD 写 PTE 时可能仍然应该设置这个位**，作为防御：Linux 里有一些不看 VMA、直接遍历页表的代码，比如 GUP 的快速路径 `gup_fast`。遇到 *special* 项时，它们会放弃，而不是去拿这个页的引用。**待核实**，归到 B5 |
| `pfn_mkwrite` | 写一个只读项时，要让这次缺页交给 endovisor，而不是由 Linux 自作主张把它改成可写 | 没有 VMA，Linux 不会去改；写缺页由缺页钩子转交（B1） |

**结论**：R6 全部是"有 VMA"带来的约束，不是选择"由 Linux 写"的理由。方案 B 下大多数直接消失，只有 *special* 位可能值得保留作为防御，要在 B5 里核实。

### R8：kill 时整体丢弃，不看 kernelet 内部的状态

**书里的说法**（`stopping-a-kernelet.md:3, 11`）：

- kernelet 结束时，Linux 必须恢复到和原来完全一样的状态；
- kernelet 的状态是"丢弃"，不是"整理"：不展开，不运行析构函数，因为这时正是它最不可信的时候；
- endovisor 把给出去的东西整体收回，不看内部：地址空间、kernelet 还持有的堆块、kernelet 栈池。

**现在的做法**：每个空间的页表页都是 Linux 分配的，里面的项都是 Linux 写的。收回时，endovisor 用 `zap` 清掉整块区域，再 `mmput`，由 Linux 的 `exit_mmap` 释放页表页。这里**要遍历页表**，但遍历的是 Linux 自己写的、可信的结构。

**方案 B 下的问题**：用户半区的各级页表页是 grant 里的物理页，内容是 vOSTD 写的。kill 时，这些内容可能写到一半，或者被 vOSTD 的 bug 写坏了。宿主还能"不看内部"吗？

**分析：可以，而且根本不需要遍历。**

1. 页表页本身就是 grant 里的物理页，归还 grant 时会被整体收回，不需要逐页找出来。
2. 宿主唯一要处理的，是 Linux 分配的那张**根页**。根页里用户半区的那 256 个顶层项指向 grant 里的页（开了 PTI 的话，还要处理那份用户态根页副本）。清掉这些项是**固定次数的操作**，不读 kernelet 写的任何内容。
3. 清完之后，对这个 mm 做一次全量 TLB 刷新（`flush_tlb_mm`），把各个 CPU 缓存的翻译和中间级页表项（paging-structure cache）都清掉。
4. 然后才能把 grant 还给 Linux。`mmput` 之后，Linux 的 `exit_mmap` 找不到 VMA，只会用 `pgd_free` 释放根页。

**顺序是硬性要求**：必须"清根页 → 刷 TLB → 归还 grant"。原因有两个：

- 不先刷 TLB，别的 CPU（比如借用这个 mm 的内核线程，处于 lazy TLB 状态）里可能还缓存着指向这些页的中间项。页一旦被 Linux 重新分配给别人，硬件就可能把新内容当作页表来解读。
- 不先清根页，mm 可能比 sandbox 活得更久：比如有人通过 `/proc` 拿着这个 mm 的引用。之后任何遍历这个 mm 的代码（比如 ptdump）都会走进已经还给 Linux 的内存。

Linux 自己释放页表页时也遵守同样的顺序：`mmu_gather` 先刷 TLB，再释放。

**和现在的做法比**：方案 B 下宿主**完全不遍历页表**，比现在"遍历 Linux 自己写的页表"更符合"不看内部"的原则。

**结论（待用户判断）**：R8 不构成反对方案 B 的理由。它在方案 B 下变成一条设计规则：**清根页的用户半区 → 刷这个 mm 的 TLB → 归还 grant**。这条规则归入 B2。

**用户确认的理解（2026-11-14）**：

- **kernelet 整体结束时**：宿主逐个空间清掉根页里用户半区的项 → 刷每个 mm 的 TLB → 整体归还 grant（页表页随之一起收回）→ `mmput`。宿主完全不遍历页表，比现在更简单。
- **运行中回收单个 mm**：由 kernelet 自己回收。vOSTD 清掉根页里用户半区的项，把页表页放回自己的分配器（这些页仍在 grant 里）；再调用一次服务，由 endovisor 刷这个 mm 的 TLB 并 `mmput`。之后这些页表页才能再次分配出去。沿用现有的待回收列表（retire list）机制来决定回收的时机。
- **细节**：刷 TLB 时必须让 Linux 知道页表页被释放了，即 `flush_tlb_mm_range(…, freed_tables = true)`，这样处于 lazy TLB 状态的 CPU 也会被刷到。现在的 `vm_flush` 传的是什么值，**待核实**。

**附带的问题，归入 B2**：如果 grant 里的页可以在 kernelet 运行期间归还给宿主（仓库历史里有一个"可归还 grant"的提案，commit `5dea2a6`，未核实其内容），vOSTD 必须保证不归还仍在用作页表页的物理页，归还前也要先刷 TLB。

### R7：无锁读的依据，以及并发写

**书里的说法**（`what-vostd-adds-on-top.md:37-41`，以及第 326 行的小结）：vOSTD 遍历页表时不加锁。这样做是安全的，依据是 Linux 的两条性质：

1. **遍历中读到的页表页不会被释放。** Linux 只在四种情况下释放一块区域的页表页：munmap 或移动区域、exec、khugepaged 合并、`exit_mmap`。这四种情况在这里都不会发生，`exit_mmap` 被 endovisor 持有的引用挡住了。`zap_vma_ptes()` 只清项，不释放页表页。
2. **不会读到写了一半的项。** Linux 用一次 64 位 store 写一项，用原子交换清一项。

另外，`:293` 指出：在裸机上，OSTD 要等每个处理器都切换过任务以后，才释放页表页；"Here no table is freed"，所以这里不需要这一步。

**方案 B 下，这两条依据由 vOSTD 自己来保证**：

| 依据 | 方案 B 下怎么保证 |
|---|---|
| 不会读到写了一半的项 | vOSTD 用对齐的 64 位原子 store 写入，和 OSTD 在裸机上一样。修改权限、清除时用 `cmpxchg` 或 `xchg`，因为 CPU 会在后台设置 accessed 和 dirty 位，普通的读、改、写会把这两个位覆盖掉（现在 endovisor 的 `klet_pte_protect` 也是用 `cmpxchg` 循环来做的） |
| 遍历中读到的页表页不会被释放 | **最简单的做法：沿用现在的行为，空间存活期间一张页表页都不释放**，只在销毁整个空间时一起回收（R8 的那个顺序）。这样无锁遍历的论证和现在完全一样。如果以后要提前释放，就要等 vOSTD 的 RCU 宽限期（现在已经用来保护物理页了）**和**一次带 `freed_tables` 的 TLB 刷新都完成之后，才能释放 |

**并发写：方案 B 新增的一个问题**

- 现在多个写入者之间靠两层互斥：vOSTD 的分段范围锁，加上 Linux 的 PTE 锁。
- 范围锁按 2 MiB 区域分段，一个区域正好是一张最底层页表。所以**对同一张最底层页表的写入**，范围锁已经保证了互斥。
- 但**中间几级页表是多个区域共用的**：一张 PMD 级的表覆盖 1 GiB，一张 PUD 级的表覆盖 512 GiB。两个 cursor 落在不同的 2 MiB 区域（不同的分段），却可能同时发现同一个中间级的项为空，各自分配一张新页表去填它，结果一张会覆盖另一张。
- 解决办法：**中间级的项用 `cmpxchg` 安装**。没抢到的一方把自己刚分配的页表页放回去，改用对方装好的那张。Linux 安装中间级页表时也要处理这种竞争（`pmd_install` 用 `page_table_lock` 来保护），OSTD 在裸机上则是靠沿途各级节点的锁。

**还有一项归入 B7**：开启 PTI 时，Linux 会把每个用户顶层项同时写进两份根页（`:45`）。vOSTD 写用户半区的顶层项时也要这样做。

**结论（待用户判断）**：R7 不构成选择"由 Linux 写"的理由。方案 B 下它变成四条设计规则：

1. 用原子 store 写项，用 `cmpxchg` 或 `xchg` 修改、清除项；
2. 空间存活期间不释放页表页（或者等宽限期加 TLB 刷新之后再释放）；
3. 中间级的项用 `cmpxchg` 安装；
4. PTI 下两份根页一起写（B7）。

规则 2 和规则 3 归入 B8。

### R2：书为什么没有考虑"vOSTD 直接写 `mm->pgd`"

**事实（2026-11-14 核查）**：

- 书里没有讨论过这个方案。`tenant-memory-on-linux-page-tables.md:9` 只有一句断言，"vOSTD cannot write a Linux page-table entry"，没有给出理由，也没有任何地方把它当作备选方案比较过。git 历史里也没有相关记录。
- vOSTD 已经从空间的记录里拿到根页表的物理地址，并且通过 direct map 自己遍历这张表（`what-vostd-adds-on-top.md:7`）。它已经在直接**读** `mm->pgd` 这棵树了。

**推测的原因**（作者没有写下来，以下都是推测；每一条在后面的 R 项里检验）：

1. 沿用了驱动程序的套路：实现 `mmap`，提供 VMA 的 `fault` 回调，用 `vmf_insert_pfn` 放页（`:30` 的背景框）。→ R6
2. 想让可信的宿主代码检查每一个物理页。→ R3
3. 想尽量少改 Linux，正确性靠 Linux 自己的代码来保证。→ C4
4. kill 时不想去碰 kernelet 写过的东西。→ R8
5. 无锁读的论证依赖于"PTE 都是 Linux 用单次 store 写的"。→ R7

**措辞上的区分**："直接写 `mm->pgd`"有两种理解：

- (a) **根页不换**，vOSTD 只写根页里用户半区的项，以及下面的各级页表。根页仍由 Linux 分配、Linux 释放。**做法二指的是这一种。**
- (b) **把 `mm->pgd` 换成 kernelet 自己分配的根页**，再复制内核半区的项。Linux 销毁 mm 时会用 `pgd_free` 释放这张不是它分配的根页，所以必须先把指针换回来，平白多出一个问题。

**结论**：书没有否定做法二，而是根本没有把它当作选项。它把"页表由 Linux 写"当成了出发点，而不是需要论证的结论。

### 第一部分小结：是否闭环（2026-11-14）

**论证层面闭环**：书里给出的八条理由都审视过了，没有一条能证明"用户页表必须由 Linux 维护"。

- R1、R5、R6 是推论；
- R2 是书没有把做法二当作选项；
- R3 已决定（U6）；
- R4 只排除影子页表；
- R7、R8 在方案 B 下变成设计规则。

**验证层面未闭环**：剩下的风险来自 Linux **没写下来的隐含依赖**，也就是 Linux 的某段代码可能假设"用户页表的每一项都是我写的"，或者"有项的地方一定有 VMA"。已知的待核实项：

1. 不看 VMA 就遍历页表的代码（B5）：`gup_fast`（遇到 *special* 项是否放弃，待核实）、perf 采样时的无锁遍历、ptdump，以及其他还没列出来的；
2. Linux 在内核态访问用户地址（B4），以及 B1 的钩子只接管用户态缺页；
3. 二级 MMU 和 mmu notifier：要写成一条明确的约束，禁止往 carrier 的 mm 上挂接；
4. TLB 刷新记账：`freed_tables` 和 lazy TLB；
5. 内存记账：确认 grant 整体计入了 memcg；
6. PTI（B7）。

另外还有一个非技术性的取舍：方案 B 要多加一个缺页钩子，Linux 补丁会变大，这和"尽量少改 Linux"（C4）有冲突。

**下一步建议**：先做 B5 审查，在 Linux 6.12 里系统地列出所有不经过 VMA 就碰用户页表的代码路径。审查通过之后，再决定是否把方案 B 定为主方案。（审查要用 shell 搜索源码；当前临时目录的磁盘配额满了，需要先清理。）

## 问题清单（方案 B，第一部分讨论完之后再展开）

| 编号 | 问题 | 状态 |
|---|---|---|
| B1 | tenant 缺页怎么交给 kernel proper | **已决定（U8）**：扩展为通用的用户态异常钩子，缺页是其中一种 |
| B2 | 销毁 mm、回收页表页时，怎么处理 TLB 和 paging-structure cache | **已确认（2026-11-16）**：运行期 `unmap` 不摘除空子表（O2）；`vm_destroy` 清 `pgd[0..255]` 后带 `freed_tables = true` 刷 TLB 并走 `synchronize_rcu()` 后再回收 |
| B3 | PTE 改动之后的 TLB 刷新：谁来发起，怎么和 Linux 的 `tlb_gen` 和 PCID 记账保持一致 | **已决定**：所有刷新都通过 `vm_flush` 服务调用 Linux 的 `flush_tlb_mm_range`（规则 T），vOSTD 不自己 `invlpg` |
| B4 | Linux 在内核态访问用户地址：信号栈帧、`clear_child_tid`、robust futex、rseq、perf 采样用户栈 | **已审查闭环（2026-11-16）**：`clear_child_tid`/robust futex/`rseq` 已在 `exec` 清空（`b5-audit.md:55`）；carrier 忽略异步信号不写用户信号栈帧；`perf` 采样用户栈在 NMI 下走 `copy_from_user_nmi`（受 `pagefault_disable()` 保护，不查 VMA 也不触发缺页） |
| B5 | 有哪些 Linux 代码不看 VMA、直接遍历页表（ptdump 等），需要审查出一张清单 | **审查完成（2026-11-14，`b5-audit.md`）**：没有发现推翻方案 B 的路径，得出规则 S（叶子项带 *special* 位）、F（页表页的释放顺序）、V（Linux 不得在 tenant 的 mm 里创建 VMA）、N（不得挂接二级 MMU）。补查了直接读 CR3 和 `mm->pgd` 的代码，都可控；新增一条部署约束：宿主不能是 Xen PV 客户机。**用户确认：没有问题，B5 完成** |
| B6 | 安全：放弃逐页检查之后，靠什么保证 PTE 只指向 grant 里的页、权限位里没有 *global* 位 | **已确认**：靠 vOSTD `UFrame` 接口约束 + 写 PTE 前 `in_grant(paddr)` 检查；第 1 级叶子停用 OSTD `PAT` 有效位并禁用 `_PAGE_GLOBAL`（O3） |
| B7 | PTI 开启时用户半区的写法 | **已确认**：顶层 `0..255` 在 `VmSpace` 根锁下按 `pti_enabled` 先写用户根 `root_paddr | PAGE_SIZE`（无 NX）、再写内核根 `root_paddr`（按 `nx_supported` 置 `_PAGE_NX`），1–3 级单份共享（O3） |
| B8 | 多个 vCPU 并发写同一张页表，以及 vOSTD 的无锁读：裸机 OSTD 的做法能否原样照搬 | **已确认（`ostd-feasibility.md`）**：沿用 OSTD 原生逐节点锁（顶层用 `VmSpace` 根锁跳过 `MetaSlot`，下级节点锁补 `vcpu::on_spin()`）+ `unmap` 不剪枝空子表使无锁读（`walk`/`copy_regions` 与宿主 `perf`/`gup_fast`）始终安全（O1、O2、O5） |
| B9 | 方案 B 对 accepted design 各章节、补丁、测试的影响范围 | 待与 `Implementation` / `Validation` 章节一并核对 |

---

## B2、B3：页表页的回收与 TLB（讨论中，2026-11-14）

**现状核实**：`vm_flush`（`prototype/linux/endovisor/space.c:853`）调用 `flush_tlb_mm_range(mm, …, freed_tables = false)`，全量刷新时也是 `false`。这在现在的设计下是对的，因为页表页由 Linux 自己释放，Linux 释放时会自己做带 `freed_tables` 的刷新。方案 B 下页表页由 kernelet 回收，销毁路径**必须**传 `true`。所以需要给 `vm_flush` 加一个标志，或者把这次刷新放进 `vm_destroy` 里完成。

**方案 B 下，TLB 受到的影响**（按对 PTE 做的事分类）：

| 操作 | 要不要刷 TLB | 说明 |
|---|---|---|
| 新装一项（不存在 → 存在） | **不需要** | x86 不缓存"不存在"的翻译，中间级缓存也只缓存存在的项。和 OSTD 在裸机上一样 |
| 放宽权限（只读 → 可写） | **不需要**，但可能出现一次多余的缺页 | 别的 CPU 上可能还缓存着旧的只读翻译，写的时候会触发一次 #PF。CPU 触发 #PF 时会自动作废这个地址的旧翻译，kernel proper 的缺页处理发现已经可写，直接返回重试即可，裸机上也是这样 |
| 收紧权限（可写 → 只读）、清项、换成别的物理页 | **需要**，由 kernel proper 通过 flusher 发起，最终调用 `vm_flush` | 和现在一样，但 unmap 的变化见下一行 |
| unmap | **需要**，改由 vOSTD 清项后调用 `vm_flush` | 现在是 `zap_vma_ptes` 自己清项并刷新；方案 B 下清项变成 vOSTD 直接写内存，刷新仍是一次服务调用，而且可以按范围合并，不必每页一次 |
| 释放页表页 | **需要**，并且必须 `freed_tables = true`，再等一个 RCU 宽限期（规则 F） | 要刷到处于 lazy TLB 状态的 CPU，并清掉中间级的页表缓存 |

**一条新规则 T：所有 TLB 刷新都必须经过 Linux 的 `flush_tlb_mm_range`，vOSTD 不能自己用 `invlpg` 只刷本地。** 原因是 PCID：一个 CPU 运行过这个 mm、切走之后，它的 TLB 里仍然保留着带这个 mm 的 PCID 标签的翻译。Linux 用每个 mm 的 `tlb_gen` 计数来跟踪这一点：刷新时把计数加一，CPU 下次切回这个 mm 时比较计数，发现落后就先刷新。如果 vOSTD 只做本地 `invlpg` 而不经过 Linux，`tlb_gen` 不会变，曾经运行过这个 mm 的其他 CPU 切回来时就会继续使用过时的翻译。`flush_tlb_mm_range` 内部已经会判断"只有本 CPU 在用"的情况并只刷本地，所以经过它不会多付代价。

**用户确认（2026-11-14）**：TLB 刷新肯定要调用一次服务，规则 T 成立；销毁路径的刷新要带 `freed_tables = true`。

**影响**：刷新仍然是一次服务调用，这是方案 B 唯一保留的、按"操作"而不是按"页"计算的服务开销。fork 时 kernel proper 最后只做一次全量刷新（`cow_copy_pt` 之后的 `for_all`），所以 fork 的每页成本只剩 vOSTD 直接写内存的那部分。

## B1（扩展）：tenant 的所有异常都用钩子交给 kernel proper

**用户的方向（2026-11-14）**：kernelet 的异常都应该像系统调用一样用钩子接管，不只是缺页。

**依据**：carrier 对 kernelet 来说就是一个 vCPU。在真实的 CPU 上，用户态发生的每个异常都直接交给内核。现在的设计里，除缺页以外的异常都要绕一圈信号：Linux 的 trap 处理函数先 `force_sig`，再由 resume 钩子里的 `klet_drain_signals` 把信号取出来、还原成异常（`carrier.c:855, 918`）。缺页则是通过 VMA 的 `fault` 回调交出去的。

**绕信号带来的问题**（`arch/x86/kernel/traps.c`）：

- 路径长：要分配信号、入队、出队；
- 刷日志：`do_trap` 和 #GP 路径都会调用 `show_signal`（`:200`、`:689`）。carrier 把所有信号都设成了忽略，在 Linux 看来就是"没有处理函数"，于是 tenant 的每个 #GP、#UD 等都会打一行日志（缺页走的 `show_signal_msg` 也一样，见下文 B1 的分析）；
- Linux 会先替用户程序做一些"修复"再决定发不发信号，比如 UMIP 指令模拟（`:705`）、iopl 模拟（`:717`）。这些本该由 kernel proper 来决定，就像在裸机上一样。

**做法**：给 carrier 加一个通用的用户态异常钩子，在各个异常入口里，只对"carrier 在用户态"的情况调用。它把陷阱号、错误码和地址记下来，设置 `TIF_NOTIFY_RESUME`，然后返回；由 resume 钩子把异常交给 kernel proper。缺页（B1-b）是它的一个特例。

**哪些异常必须先由 Linux 处理**（初步分类，待确认）：

| 异常 | 入口 | 处理方式 | 原因 |
|---|---|---|---|
| #PF | `exc_page_fault` → `do_user_addr_fault` | 钩子，放在查 VMA 之前 | 见 B1 |
| #DE、#OF、#BR、#UD、#TS、#NP、#SS、#MF、#XM | `do_error_trap` 等 | 钩子，放在 `force_sig` 之前 | 纯粹是 tenant 自己的事 |
| #GP | `exc_general_protection` | 钩子，放在 UMIP、iopl 模拟之前 | 这些模拟应该由 kernel proper 决定 |
| #BP、#DB（用户态） | `exc_int3` → `do_int3_user`、`exc_debug_user` | 钩子 | 宿主的 uprobes 依赖文件 VMA，在 tenant 的 mm 上不会有；代价是宿主没法用 gdb 调试 carrier 里的 tenant 代码 |
| #AC | `exc_alignment_check` | **先让 Linux 处理 split lock**（`handle_user_split_lock`，`:355`），剩下的真正的对齐检查才交给钩子 | split lock 会拖慢整台机器，Linux 对它的处理是宿主的保护策略，不能让 tenant 绕过 |
| #NM | `exc_device_not_available` | **先让 Linux 处理 XFD**（`handle_xfd_event`，`:1283`） | AMX 的状态缓冲区是在第一次使用时、通过 #NM 按需分配给 carrier 的，这是宿主的 FPU 管理 |
| #MC、NMI、#DF、#VE、#VC | — | **不挂钩子** | 这些是宿主的事：硬件错误、宿主自己作为客户机时的虚拟化异常 |
| 内核态访问用户地址时发生的缺页 | `do_user_addr_fault` 的内核态分支 | **不挂钩子** | 这是 Linux 自己的访问，必须由 Linux 的异常表修复（见 B4） |

**附带结论**：通用异常钩子和方案 B 无关，在方案 A 下同样成立，而且能去掉现在"信号转异常"这条间接路径。真实的异步信号（`SIGKILL` 等）仍然走 resume 钩子。

**代价**：补丁要在若干个异常入口里加调用点，`carrier-hooks.md` 里"两个钩子"的说法要改。

**状态**：用户已确定方向。

**范围（用户决定，2026-11-14）**：只转发 kernelet 的 kernel proper 实际支持的异常，也就是 Asterinas 支持的那些。

**Asterinas 支持哪些用户态异常**（`reference/asterinas`，提交 `ab9a4cfdc`）：

- OSTD（`ostd/src/arch/x86/cpu/context/mod.rs`，`UserContext::execute`）：类型为 fault 或 trap 的异常，以 `ReturnReason::UserException` 交给内核；abort（#DF、#MC）、NMI、保留向量直接 panic；#VE 只在机密虚拟机客户机里由 OSTD 自己处理。
- 内核（`kernel/core/src/thread/exception.rs`、`kernel/core/src/arch/x86/signal.rs`）：#PF 先交给缺页处理函数（`handle_page_fault_from_vmar`），处理不了再转成信号；其他异常用 `to_fault_signal` 转成信号；返回 `None` 的异常会让内核 panic（"cannot be handled via signals"）。

| 异常 | Asterinas 的处理 | kernelet 是否转发 |
|---|---|---|
| #PF | 缺页处理，失败则 `SIGSEGV` | **转发** |
| #DE | `SIGFPE` | **转发** |
| #DB | `SIGTRAP` | **转发** |
| #BP | `SIGTRAP` | **转发** |
| #OF | `SIGSEGV` | **转发** |
| #UD | `SIGILL` | **转发** |
| #SS | `SIGBUS` | **转发** |
| #GP | `SIGSEGV` | **转发** |
| #MF、#XM | `SIGFPE` | **转发** |
| #AC | `SIGBUS` | **转发**，但 split lock 先由 Linux 处理 |
| #BR、#NM、#TS、#NP、#CP、#9、#HV、#VC、#SX | 内核 panic | 不转发 |
| #DF、#MC、NMI、保留向量 | OSTD panic | 不转发，属于宿主 |

**不转发的异常怎么办（用户确认，2026-11-14）**：交给 Linux 的默认处理，sandbox 随之结束并被清理。carrier 把信号都设成了忽略，但 `force_sig` 会把处理方式重置为默认，于是 carrier 被杀死，整个 sandbox 结束。这和 Asterinas 在裸机上遇到这些异常时 panic 的结果一样，只影响这个 tenant 自己。#NM 的 XFD 仍然由 Linux 先处理。

**由此带来的两点实现要求**：

- resume 钩子里的 `klet_drain_signals` 不再把缺页一类的信号转成异常，因为该转发的异常已经由钩子转发了，留在信号队列里的都是不转发的那些，应该让 Linux 照常投递，从而杀死 carrier。`SIGKILL` 的处理不变。
- carrier 被杀死以后，现有的 lifeline 机制会发现它的进程退出，接着结束整个 sandbox（`stopping-a-kernelet.md` 的 "Stopping from outside" 一节），不需要新机制。

**发现的一个现有缺陷**：`carrier.c:836-853` 的注释承认，XFD 引起的 #NM 不会记录 `thread.trap_nr`，所以经过信号转换后，kernelet 收到的陷阱号是 tenant 上一次异常留下的旧值。改成通用异常钩子之后，这类问题就不存在了。

## B1：tenant 缺页怎么交给 kernel proper

### 现状

tenant 访问一个没有映射的地址：

1. 进入 Linux 的 `do_user_addr_fault`；
2. `lock_vma_under_rcu` 找到 endovisor 的那块区域；
3. `handle_mm_fault` → 区域的 `fault` 回调（`klet_space_report`）记下缺页，设置 `TIF_NOTIFY_RESUME`，返回 `VM_FAULT_NOPAGE`；
4. 返回用户态之前，resume 钩子把这次缺页作为异常交给 kernel proper。

### 方案 B 下，如果什么都不改

`arch/x86/mm/fault.c`（6.12）里的路径是：

1. `lock_vma_under_rcu` 找不到 VMA（第 1329 行）；
2. 退到 `lock_mm_and_find_vma`，它要拿 `mmap_lock`，仍然找不到（第 1361 行）；
3. `bad_area_nosemaphore` → `force_sig_fault(SIGSEGV, SEGV_MAPERR, addr)`（第 825 行）；
4. 返回用户态之前，resume 钩子里的 `klet_drain_signals`（`prototype/linux/endovisor/carrier.c:918`）把信号取出来。`klet_is_fault_signal`（`carrier.c:855`）按 `si_code` 认出这是一次缺页，并从 `thread.trap_nr`、`thread.error_code` 和 `si_addr` 还原出异常，交给 kernel proper。

也就是说，**这条路现在就能用，不需要新代码**。书里 NX 取指错误就是这样处理的。别的进程用 `kill()` 发来的 `SIGSEGV`，`si_code` 是 `SI_USER`，不会被误认为缺页。

### 选项

| 选项 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **B1-a** | 复用信号路径，什么都不改 | 零新代码；已经有 NX 的先例 | 多走一次 `mmap_lock`、一次 sigqueue 分配和入队、一次出队，缺页路径变长。具体慢多少需要测 |
| **B1-b** | 在补丁里给 carrier 加一个缺页钩子，放在 `do_user_addr_fault` 查找 VMA 之前：记下缺页、设置 `TIF_NOTIFY_RESUME`，直接返回 | 路径最短，比现在的 `fault` 回调还短：不查 VMA，不拿任何锁 | 补丁多一个钩子，要改 `carrier-hooks.md`；钩子要放在 x86 特定的代码里 |
| B1-c | 保留一个 VMA，只用来分发缺页 | 缺页路径和现在一样 | 只要有 VMA，Linux 就会去遍历并清理它下面的 PTE，等于退回方案 A 的前提。**不建议** |

### 补充：B1-a 路径上的两个问题（来自 `__bad_area_nosemaphore`，第 779 到 826 行）

- **刷日志**：第 815 行的 `show_signal_msg` 会先用 `unhandled_signal` 判断信号有没有处理函数，处理方式为 `SIG_IGN` 或 `SIG_DFL` 都算没有。carrier 把所有信号都设成了忽略，所以 tenant 的每次正常缺页，都会在内核日志里打一行 `segfault at ...`，只受 `printk_ratelimit` 限制。
- **多读一次用户内存**：第 806 行的 `is_prefetch` 要读出错那条指令的字节。

### 三条路线比较（从 #PF 进入 Linux，到缺页被截住）

| | 这一段做了什么 | 长度 |
|---|---|---|
| 现在的方案 | RCU 查 VMA（找到）→ `handle_mm_fault` 遍历并补齐中间几级页表 → `fault` 回调 `klet_space_report` 记下缺页 | 中 |
| B1-a | RCU 查 VMA（找不到）→ 拿 `mmap_lock` 再查一次（找不到）→ 打日志、读指令、分配信号并入队 → resume 钩子出队、还原 | 最长 |
| B1-b | 进入 `do_user_addr_fault` 后、查 VMA 之前，直接记下缺页并返回 | 最短 |

### 用户的决定

**暂缓（2026-11-14）。** 用户指出，书中方案的理由是否必要还没想清楚，现在设计方案 B 太早，所以这里不作决定，先做第一部分。下面是暂缓时用户表达的倾向和当时的分析，留作参考。

用户的倾向：路径越短越好，倾向 B1-b。B1-b 不仅比 B1-a 短，也比现在的方案短：不查 VMA，不拿锁，不走 `handle_mm_fault`。代价是补丁要多一个 carrier 缺页钩子，放在 `do_user_addr_fault` 查找 VMA 之前，所以 `carrier-hooks.md` 要相应修改。

附带结论：B1-b 不依赖方案 B，在方案 A 下也能用来缩短缺页路径。

待细化：
- 钩子的确切位置：要放在哪些检查之后。vsyscall 模拟、kprobe、`faulthandler_disabled()` 这些要不要先于钩子执行，需要逐条看；
- 钩子只接管 carrier 在用户态发生的缺页（`X86_PF_USER`）；内核态访问用户地址时发生的缺页仍然走 Linux 原来的路径，这一点和 B4 一起讨论。
