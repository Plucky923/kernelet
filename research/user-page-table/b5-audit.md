# B5 审查：Linux 6.12 里哪些代码不经过 VMA 就会碰用户页表

- 日期：2026-11-14
- 源码：`reference/linux-6.12`（未打补丁）
- 问题：方案 B 下，tenant 的 mm 里**没有任何 VMA**，用户半区的页表由 vOSTD 直接写。Linux 里有没有代码会绕过 VMA，直接去读或写这一半的页表？如果有，会不会出问题？

## 方法

1. 在 `mm/`、`kernel/`、`fs/`、`arch/x86/`、`virt/`、`ipc/` 里找出所有从某个 mm 出发、调用 `pgd_offset(mm, …)` 开始遍历页表的地方，排除 `init_mm` 等内核自己的页表，再查看每处所在的函数。
2. 另外找出 `walk_page_range_novma`、GUP 快速路径（`get_user_pages_fast`、`pin_user_pages_fast`、`get_user_page_fast_only`）的所有调用者，覆盖范围扩大到 `drivers/`、`net/`、`io_uring/` 等目录。
3. 对每一处判断：它是否先查 VMA；它在什么上下文里、对哪个 mm 运行；方案 B 下会怎样。

## 结果

### 第一类：按 VMA 遍历，没有 VMA 就什么都不做（方案 B 下安全）

| 代码 | 用途 |
|---|---|
| `copy_page_range`（`mm/memory.c:1408`） | fork 时复制页表，按 VMA 逐个复制 |
| `unmap_page_range`（`:1805`）、`free_pgd_range`（`:355`，经由 `free_pgtables`） | munmap、进程退出时清项并释放页表页，都按 VMA 的范围进行 |
| `__handle_mm_fault`（`:5833`） | 缺页处理，要先找到 VMA。方案 B 下缺页在查 VMA 之前就被钩子截走了（B1） |
| `change_protection_range`（`mm/mprotect.c:521`） | mprotect |
| `follow_page_mask`（`mm/gup.c:1076`），以及 GUP 慢速路径（`gup_vma_lookup`，`mm/gup.c:1326`） | ptrace、`/proc/pid/mem`、`process_vm_readv` 等都走这里，先 `vma_lookup`，找不到就返回 `-EFAULT` |
| `follow_pfnmap_start`（`:6426`）、`remap_pfn_range_internal`（`:2678`）、`walk_to_pmd`（`:1970`） | 都需要传入 VMA |
| `walk_page_range` 和 `walk_pgd_range`（`mm/pagewalk.c:230`）、`folio_walk_start`（`:735`） | 按 VMA 迭代。pagemap、smaps、mincore、MGLRU、khugepaged、NUMA balancing、KSM 都走这里 |
| `page_vma_mapped_walk`、`mm_find_pmd`（`mm/rmap.c:812`） | 从物理页出发，按反向映射找到映射它的地方。grant 里的页没有反向映射 |
| `unuse_vma`（swapfile）、`migrate_vma_insert_page`、`dev_pagemap_mapping_shift`（memory-failure）、hugetlb、mremap、userfaultfd | 都以 VMA 为入口 |

### 第二类：不看 VMA，无锁、只读、只对 `current->mm`（要采取措施）

| 代码 | 谁会触发 | 方案 B 下 |
|---|---|---|
| **GUP 快速路径** `gup_fast_pgd_range`（`mm/gup.c:3308`）及 `gup_fast_pte_range` | Linux 系统调用（futex、O_DIRECT、io_uring、驱动 ioctl 等）；**perf 采样**：`perf_virt_to_phys` 在 NMI 里调用 `get_user_page_fast_only`（`kernel/events/core.c:7686`），tenant 运行时被采样就会触发 | 遇到带 *special* 位的项会直接放弃（`gup_fast_pte_range` 中的 `else if (pte_special(pte)) goto pte_unmap;`）。**所以 vOSTD 写叶子项时必须设置 *special* 位**，否则它会对 grant 里的页拿引用 |
| `perf_get_pgtable_size`（`kernel/events/core.c:7711`） | perf 采样时记录页大小 | 只读，结果只用来上报，无害 |

这两者都**依赖"关中断期间页表页不会被释放"**：Linux 释放页表页之前，会发 IPI 刷新 TLB，或者等一个 RCU 宽限期，而关着中断的遍历者会让它们等下去（见 `kernel/events/core.c:7678` 附近的注释）。所以方案 B 释放页表页时也要遵守同样的顺序，见下文规则 F。

### 第三类：不看 VMA，对指定的 mm 遍历

| 代码 | 方案 B 下 |
|---|---|
| `walk_page_range_novma` → `ptdump`（`mm/ptdump.c:158`），x86 debugfs 的 `current_user`（`arch/x86/mm/debug_pagetables.c:58`） | 调试功能，要 root 权限，只读。满足规则 F 就无害 |
| `__apply_to_page_range`（`mm/memory.c:2955`） | 调用者自己指定 mm；对 tenant mm 调用它的只有现在的 endovisor，方案 B 下不再调用 |
| `arch/x86/kernel/ldt.c` 的 `map_ldt_struct_to_user` 等 | LDT 映射在**内核半区**（`LDT_BASE_ADDR`），和用户半区无关 |
| `arch/x86/kvm/mmu/mmu.c:3114` | 只针对 `kvm->mm`，carrier 的 mm 不会是 KVM 虚拟机的 mm |
| x86 oops 时的 `dump_pagetable` | 只读，用于打印诊断信息 |

### 第四类：驱动和其他子系统

`drivers/`、`net/`、`io_uring/` 等目录里没有直接从用户 mm 遍历页表的代码，命中的全是 GUP 调用（RDMA、vfio、vhost、各种 GPU 和加速器的 userptr）。它们都要在 carrier 的上下文里发起系统调用或 ioctl 才会触发，而且 GUP 快速路径会跳过 *special* 项，慢速路径则要求有 VMA。

## 谁能在 tenant 的 mm 上触发这些代码

- **tenant 自己发不出 Linux 系统调用。** carrier 处于 `KLET_USER` 状态时，所有 64 位系统调用都被 `on_syscall` 钩子交给 kernelet，32 位入口则报 #GP（`prototype/linux/endovisor/carrier.c` 的 `klet_on_syscall`）。所以 Linux 不会替 tenant 执行 mmap、futex、ioctl，也就**不会在 tenant 的 mm 里创建 VMA**，也不会把二级 MMU 挂上来。
- **carrier 退出时，Linux 不会往 tenant 的地址写数据。** carrier 是通过 exec 出生的，exec 会清掉 `clear_child_tid`（`kernel/fork.c` 的 `mm_release`，exec 时经由 `exec_mm_release` 调用，并置 `NULL`）、robust futex 链表（`futex_exec_release`）和 rseq（`rseq_execve`）。
- **其他进程**：ptrace、`/proc/pid/mem`、`process_vm_*` 都走 GUP 慢速路径，找不到 VMA 就失败。现在的方案里，它们会因为区域带 `VM_IO | VM_PFNMAP` 而被拒绝（`mm/gup.c:1268`），所以两种方案的结果一样。
- **perf**：系统范围的采样可以在 tenant 运行时触发第二类代码，靠 *special* 位和规则 F 保证安全。

## 结论

审查范围内**没有发现会推翻方案 B 的代码路径**。审查得出四条方案 B 必须遵守的规则：

| 规则 | 内容 | 依据 |
|---|---|---|
| **S** | vOSTD 写的每一个叶子 PTE 都要带 *special* 位（`_PAGE_SPECIAL`，x86 上是软件可用位 `SOFTW1`） | GUP 快速路径和 perf 会无锁读到这些项，*special* 位让它们放弃，不去拿 grant 页的引用 |
| **F** | 页表页的释放顺序：清掉指向它的项 → `flush_tlb_mm_range(…, freed_tables = true)` → 再等一个 RCU 宽限期 → 才能释放或重新使用 | 关中断的无锁遍历者（GUP 快速路径、perf）、硬件的中间级页表缓存，以及处于 lazy TLB 状态的 CPU。和 R7、R8 的规则合并 |
| **V** | Linux 绝不能在 tenant 的 mm 里创建 VMA | 一旦有了 VMA，Linux 的缺页、清理、退出代码就会去遍历 vOSTD 写的页表。现在由"tenant 发不出 Linux 系统调用"来保证；以后如果要让某些 Linux 系统调用直通，必须重新审视这一条 |
| **N** | 不允许二级 MMU（KVM、IOMMU SVA、HMM 等）挂到 tenant 的 mm 上 | vOSTD 直接写页表不会发出 mmu notifier。现在同样由 V 的理由来保证 |

## 补充：直接读 CR3 或 `mm->pgd` 的代码（2026-11-14）

为了补上"只靠函数名 grep 可能漏掉的代码"，另外搜索了 `read_cr3_pa()`、`__read_cr3()` 和 `…->pgd` 的使用者：

| 代码 | 做什么 | 方案 B 下 |
|---|---|---|
| `arch/x86/mm/tlb.c` | 切换任务时把 `mm->pgd` 装进 CR3，并管理 PCID | 这正是方案 B 依赖的机制（C8），不受影响 |
| `arch/x86/mm/fault.c:251, 298, 354, 522` | oops 时打印页表（`dump_pagetable`、`show_fault_oops`） | 只读的诊断代码。规则 F 保证页表页不会被提前释放 |
| `arch/x86/kernel/process_64.c:116, 808` | 打印寄存器；开启 LAM 时改 CR3 | 开启 LAM 要 carrier 自己发 `arch_prctl` 系统调用，做不到 |
| `arch/x86/hyperv/mmu.c`、`arch/x86/xen/mmu_hvm.c` | 运行在 Hyper-V 或 Xen HVM 上时，把 `mm->pgd` 的物理地址作为地址空间标识，交给超级调用刷 TLB | 只用这个地址作标识，不遍历页表，没有影响 |
| `arch/x86/xen/mmu_pv.c` | **宿主 Linux 本身作为 Xen PV 客户机运行时**，所有页表写入都必须通过超级调用交给 Xen | **方案 B 在这种宿主上不能用**：页表页对客户机是只读的，vOSTD 直接写会出错。这是一条新的部署约束，Xen PVH、HVM 和裸机都不受影响 |
| `kernel/fork.c:796`、`arch/x86/mm/pgtable.c:444` | 分配、释放根页 | 根页仍然由 Linux 管理（C8） |
| 挂起、休眠、SEV、启动早期代码 | 保存和恢复 CR3，或者只在启动时运行 | 不遍历用户半区 |
| `mm/debug.c:219` | 打印 `mm->pgd` 指针 | 只打印 |

**结论**：直接读 CR3 或 `mm->pgd` 的代码都可控，要么只读，要么根本触发不了。新增一条部署约束：**宿主不能是 Xen PV 客户机**。

## 范围和局限

- 审查依据的是对源码的 grep：`pgd_offset(mm, …)`、`walk_page_range_novma`，以及 GUP 快速路径的入口。如果有代码直接读 CR3、或者直接用 `mm->pgd` 而不经过这些函数，就可能被漏掉。我已经知道的这类代码只有 oops 诊断时的 `dump_pagetable`，它是只读的。
- 只审查了 x86-64 和通用代码。
- 规则 F 中"再等一个 RCU 宽限期"是保守的做法：x86 在某些配置下（例如开启 paravirt）用 RCU 来释放页表，而不是 IPI。是否可以省掉，留到 B2 再定。
