# 提案大纲：从基本事实推导

对应决定 U9（2026-11-15）。改写 `book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md`（原 `2026-11-13-batched-memory-services.md`），论证顺序是：基本事实 → 要求 → 最小分工 → 设计，再用同一套要求评价其他方案。

逐层和用户确认。状态标记同 `decisions.md`：**已确认**、**待确认**。

## 第一层：基本事实（待确认）

只收不需要论证、可以从硬件手册、Linux 源码或书的威胁模型直接查到的事实。

### 硬件（x86-64）

| 编号 | 事实 | 依据 |
|---|---|---|
| H1 | CPU 只按 CR3 指向的页表做地址翻译，不知道 VMA 的存在 | SDM 卷 3 第 4 章；C7 |
| H2 | CPU 缓存翻译结果（TLB）和中间级页表项（分页结构缓存），带 PCID 标签，切换 CR3 时不一定丢弃。不缓存"不存在"的项 | SDM 卷 3 第 4.10 节 |
| H3 | CPU 会在后台写页表项：第一次访问时设置 accessed 位，第一次写时设置 dirty 位 | SDM 卷 3 第 4.8 节 |
| H4 | 翻译失败产生 #PF，其他错误产生各自的异常，都经由 IDT 进入内核 | SDM 卷 3 第 6 章 |

### 宿主 Linux

| 编号 | 事实 | 依据 |
|---|---|---|
| L1 | carrier 是 Linux 的用户任务，由 Linux 调度。每次切换时，Linux 把 CR3 设成 `current->mm->pgd`，并用每个 mm 的 `tlb_gen` 跟踪各 CPU 的 TLB 是否过期 | `arch/x86/mm/tlb.c`；C2、C8 |
| L2 | 根页的内核半区由 Linux 维护，所有进程共用。开启 PTI 时每个 mm 有两张根页，用户态用的那张只有用户半区和少量入口映射；内核态那张的用户顶层项带 NX | `what-vostd-adds-on-top.md:45` |
| L3 | IDT 是 Linux 的：tenant 的每个异常和中断都先进入 Linux 的入口代码 | C1 |
| L4 | Linux 有代码会遍历用户页表：按 VMA 遍历的；不看 VMA、无锁、只读 `current->mm` 的（GUP 快速路径、perf）；调试用的 | `b5-audit.md` |
| L5 | Linux 自己在内核态读写用户地址：系统调用参数、信号栈帧、退出时的 `clear_child_tid` 等 | B4（未讨论） |
| L6 | kernelet 结束时，Linux 要能收回给出去的一切，并且不依赖 kernelet 内部的状态，因为这时 kernelet 最不可信 | `stopping-a-kernelet.md:11` |

### kernelet

| 编号 | 事实 | 依据 |
|---|---|---|
| K1 | kernel proper 像在裸机上一样管理用户内存：map、protect、unmap、fork 的写时复制、按需调页、fault-around。这些操作很频繁，而且按页进行 | `what-it-costs.md`、Asterinas |
| K2 | 威胁模型：kernel proper 可能被 tenant 的程序借 bug 接管，但它是安全 Rust，只能通过 OSTD 的接口请求映射（`UFrame`、`PageProperty`）。vOSTD 由运营方编译，是可信的 | `why-a-kernel-of-your-own.md` |
| K3 | kernelet 能用的物理页只有 grant 里的那些；`UFrame` 只能从管理 grant 的分配器得到 | `the-kernelet-abi.md` |
| K4 | vOSTD 运行在 ring 0，已经能通过 direct map 读写全部物理内存，并且已经在直接读 `mm->pgd` 这棵树 | `the-kernelet-abi.md`、`what-vostd-adds-on-top.md:7` |

## 第二层：要求（未开始）

## 第三层：最小分工（未开始）

## 正文草稿（逐段确认）

### First principles › What the hardware does

**H1**（待确认）

> The processor translates every user address through one table, the one whose root CR3 holds. It walks that table by itself, level by level, down to the entry for the page, and it reads nothing else. A Linux VMA is Linux's own record of what a range of addresses is for; the processor never consults it. So whatever the table holds is the translation, whoever wrote it and whether or not a VMA covers it.
