# 相关工作：别人怎么处理"谁来写客户内核的页表"

- 日期：2026-11-14
- 问题：一个客户内核（guest kernel）跑在宿主之上或之内，它的进程页表由谁来写？各个系统给出的理由是什么？
- 说明：大部分资料来自论文摘要、邮件列表和源码片段，只有 coLinux 的论文读了全文。下面的细节如有疑问，以原始资料为准。

## 三类做法

### 第一类：宿主写，每次修改都由宿主检查（kernelet 现在属于这一类）

| 系统 | 做法 | 理由 | 后来遇到的问题和对策 |
|---|---|---|---|
| **Xen PV**（SOSP'03） | 页表对客户机只读，每次修改都要通过 `mmu_update` 超级调用请 Xen 来做；Xen 给每个物理页记一个类型和引用计数，靠它来检查 | 客户内核**不可信**：如果让它随意改页表，它就能映射不属于自己的内存 | 一次超级调用改一项太慢，于是 `mmu_update` 支持一次提交一批，Linux 这边还用 multicall 进一步批量；另外试过"可写页表"（先让客户机直接写，事后再检查），但邮件列表里说对典型负载帮助不大，还拖累 SMP |
| **Nested Kernel**（ASPLOS'15） | 把页表页设成只读，外层内核要改页表必须调用嵌套内核，由它检查 | 外层内核**不可信**（可能被攻破），要缩小可信计算基 | 报告的开销很小：Apache 平均 <1%，内核编译 2.7% |
| **CKI**（EuroSys'25，上海交大 IPADS） | 每个容器的客户内核有独立的地址空间，修改页表等特权操作交给内核安全监控器，通过 PKS 快速门切换过去完成 | 客户内核**不可信**，各容器之间要隔离 | 论文的重点就是把这道门做快 |
| **User-mode Linux** | 客户内核没有真正的页表，每次修改都要变成宿主的 `mmap`、`munmap`、`mprotect` 系统调用 | 没有特权，只能通过系统调用来改 | `arch/um/kernel/tlb.c` 把一段连续的修改合并成一次系统调用（`host_vm_op` 批量）；fork 时要做全量同步；2024 年的重构里提到，新加的页表项常常要等用户程序"不必要地缺页一次"才会同步过去 |

### 第二类：影子页表，延迟生效（书里 R4 否决的那种）

| 系统 | 做法 | 理由 | 问题 |
|---|---|---|---|
| **lguest** | 客户内核写自己的页表，宿主另外维护一份 CPU 真正使用的"影子页表" | 不用硬件虚拟化 | — |
| **PVM**（SOSP'23，蚂蚁和阿里） | 客户内核跑在 ring 3，用 KVM 的影子页表 | 很多云厂商不开放嵌套虚拟化 | cover letter 的原话："The most significant drawback of PVM"，"Shadowpaging results in very bad performance when guest applications frequently modify pagetable"，尤其是 "excessive processes forking" |

### 第三类：客户内核自己写页表，隔离靠别的机制保证

| 系统 | 做法 | 隔离靠什么 |
|---|---|---|
| **Dune**（OSDI'12） | 进程运行在 VT-x 非根模式下，直接管理自己的页表和 CR3 | EPT 由宿主模块配置，进程只能访问它本来就能访问的物理页 |
| **gVisor KVM 平台** | Sentry 在客户机的 ring 0 运行，自己生成并写页表（`pkg/ring0/pagetables`），平台标记为 `DoesOwnPageTables` | KVM 虚拟机的边界 |
| **Cooperative Linux**（OLS'04） | 客户 Linux 以宿主驱动的形式运行在 ring 0，有自己完整的页表；切换时连 CR3、IDT、GDT 一起换掉，用一个"passage page"做中转；客户内核自己处理缺页 | 不隔离，客户内核是可信的。论文自己承认："Acquiring root user access on a Cooperative Linux machine can potentially lead to root on the host machine" |
| **Asterinas / OSTD**（ATC'25，裸机） | kernel proper 通过 `VmSpace` 的 cursor 写页表 | 类型系统：只有 `UFrame` 和 I/O 内存能映射进用户空间，`unsafe` 只出现在 OSTD 里 |

## 对 kernelet 的启示

1. **第一类做法都有同一个前提：写页表的那一方不可信。** Xen PV 的客户内核、Nested Kernel 的外层内核、CKI 的容器内核，都被当作潜在的攻击者，所以每次修改都要检查。kernelet 的情况不同：书的威胁模型里，可能被攻破的是 kernel proper，而**真正写页表的是 vOSTD，它在可信计算基里**；kernel proper 只能通过 `UFrame` 类型来请求映射。这一点和 Asterinas 在裸机上的情况一样，属于第三类的信任关系。**kernelet 用的是第一类的机制，信任关系却是第三类。** R3 的"逐页检查"是从第一类借来的，前提并不成立。
2. **第一类的系统最后都做了批量。** Xen 有 `mmu_update` 队列和 multicall，UML 有 `host_vm_op`。这说明方案 A（batching）是一条前人走过的路，有效但治标。
3. **影子页表在 fork 密集的负载下很糟糕**，PVM 的作者自己承认了这一点。这印证了 R4 排除第二类是对的。
4. **没有找到和做法二完全一样的先例**，也就是"在宿主内核里，直接写宿主进程 mm 的用户半区，而不建 VMA"。最接近的有两个：
   - coLinux：在 ring 0 里有自己的页表，但它完全切走 CR3，不和宿主的调度配合；
   - gVisor KVM：自己写页表，但运行在 KVM 虚拟机里。

   做法二要和 Linux 的 mm 共存，这一点是新的，需要自己论证（就是方案 B 问题清单里的 B2 到 B9）。

## 资料来源

- Xen：[X86 Paravirtualised Memory Management](https://wiki.xenproject.org/wiki/X86_Paravirtualised_Memory_Management)；[Xen 3.0 Interface Guide：内存管理](https://www.linuxtopia.org/online_books/linux_virtualization/xen_3.0_interface_guide/linux_virualization_xen_interface_11.html)；[xen-devel 2006：关闭可写页表的讨论](https://lists.xen.org/archives/html/xen-devel/2006-07/msg01007.html)
- Nested Kernel：[项目主页](https://nestedkernel.github.io)；[PerspicuOS](https://github.com/edgar-pek/PerspicuOS)
- CKI：[A Hardware-Software Co-Design for Efficient Secure Containers（EuroSys'25）](https://ipads.se.sjtu.edu.cn/zh/publications/ShiEurosys25.pdf)
- UML：[OLS 2002 论文](https://www.kernel.org/doc/ols/2002/ols2002-pages-107-116.pdf)；[uml: TLB operation batching](https://ayakael.net/forge/linux-pinenote/commit/c56004901fa5dcf55f92318f192ab3c0e87db2d1)；[2024 年 TLB 更新重构补丁](https://patchwork.ozlabs.org/project/linux-um/patch/20240418092327.860135-13-benjamin@sipsolutions.net/)
- PVM：[RFC cover letter](https://lkml.iu.edu/hypermail/linux/kernel/2402.3/02173.html)；[SOSP'23 论文](https://ranger.uta.edu/~jrao/papers/sosp23.pdf)
- lguest：[page_tables.c](https://googlers.googlesource.com/maze/linux/+/v3.3/drivers/lguest/page_tables.c)
- Dune：[OSDI'12](https://www.usenix.org/conference/osdi12/technical-sessions/presentation/belay)
- gVisor：[Platform Guide](https://gvisor.dev/docs/architecture_guide/platforms)；[kvm.go](https://sources.debian.org/src/golang-gvisor-gvisor/0.0~20240729.0-4/pkg/sentry/platform/kvm/kvm.go)
- Cooperative Linux：[OLS 2004 论文](https://www.kernel.org/doc/ols/2004/ols2004v1-pages-23-32.pdf)（本地副本：`refs/colinux-ols2004.pdf`）
- Asterinas：[ATC'25 论文](https://www.usenix.org/conference/atc25/presentation/peng-yuke)；[OSTD：Safe User-Kernel Interactions](https://asterinas.github.io/book/ostd/soundness/safe-user-kernel-interactions.html)
