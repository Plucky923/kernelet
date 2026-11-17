# Direct page-table updates in vOSTD：实验计划

- 日期：2026-11-15（2026-11-17 更新 syscall 实验状态）
- 服务对象：`book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md`
- 状态：已有 Asterinas + Linux 6.12 PoC 的 KVM 功能、安全与端到端性能记录（详见 `results.md`）。2026-11-17 已完成 Linux/Kernelet 同配置对照、四项适配层优化、缓解关闭/自动选择对照和相关回归，保留 Asterinas 现有接口，详见 [syscall 实测报告](results/syscall-2026-11-17/README.md)。逐段纳秒归因、可接受的原生 Asterinas 基线、Intel Xeon 物理核隔离与 Intel PT 剖析仍未完成。本计划替代 `research/mem-baseline/plan.md` 的初版草稿；背景审查见 `decisions.md` 和 `b5-audit.md`。

## 1. 实验基座与环境规范

### 代码基座与对比组

所有 Kernelet 变体均构建在 **PR #3（优化后的事件进出 handoff PoC）** 与 **PR #7（载体 FPU 状态管理）** 之上，避免原版双栈切换与寄存器复制开销干扰缺页与异常路径。在此基础上，正式性能实验对比以下三列（控制单一变量）：

| 对比组 | 说明 |
|---|---|
| **Native Linux** | QEMU/KVM 虚拟机内，同一打过补丁的 Linux 6.12 内核构建下的普通用户进程；不是物理机上的 Linux 基线 |
| **改前 Kernelet（PR #3 基座 + VMA 服务，`pt_mode=1`）** | PR #3 PoC + `VM_PFNMAP` VMA、逐页 `OP_VM_MAP`/`OP_VM_PROTECT`、`OP_VM_UNMAP`、VMA `fault`/`pfn_mkwrite` 回调与异常路径 |
| **改后 Kernelet（本提案：Direct PTE，`pt_mode=0`）** | PR #3 PoC + 无 VMA 空壳 `mm_struct` + vOSTD 直接原子写页表 + `on_exception` 钩子 |

### 256 MiB 分块 Grant

将沙盒 Grant 上限扩至 **512 MiB**（本次 PoC 基准与安全测量统一分配 **256 MiB**）：底层由 `poc_endovisor`（`poc/linux/endovisor/poc_grant.c`）在沙盒启动时按 **2 MiB** 物理连续 grain 多次调用 `alloc_pages(GFP_KERNEL_ACCOUNT | __GFP_ZERO, 9)` 申请并交给 vOSTD。所有 64 MiB 测试均使用 **16,384 个真正独立的 4 KiB 物理页**（除 `mprotect_ro_2m` 为 512 页；含 `fork` + COW 复制达到的 ~128 MiB 峰值），消除原版 256 页循环复用造成的缓存工作集偏差。

### 硬件平台、计时与统计口径

- **已有 PoC KVM 环境记录**：本地主机 `AMD Ryzen 7 5800H`，虚拟机内为 Linux 6.12 + `prototype/linux/patches/0001-carrier-hooks.patch`，QEMU/KVM 基本参数为 `-enable-kvm -cpu host -smp 2 -m 1024M -nic none`。两个 carrier 分别绑定虚拟机 Linux CPU 0、1。2026-11-17 的 syscall 实验另行使用 QMP 验证宿主物理 CPU 绑定，并在 `run_getpid_bench` 中设置 CPU 0 affinity、通过 raw `getcpu` 核实实际 CPU，完整参数见实测报告。两侧使用相同静态 C 基准；本轮 syscall 结果不替代 MM 的页大小与计时语义验证。QEMU TCG 的 `SapphireRapids` 配置仅作为已有异常行为对照；本机 TCG 不支持 XFD，不能用它声明完成 `XFD #NM` 验证。
- **尚未执行的正式宿主机专项（Deferred）**：Intel Xeon 宿主物理核独占绑核（`-m 512M` / 隔离核）、Intel PT 10 ms 周期剖析（第 2 节）、`prototype/` 既有 `make mem-*` 回归套件改写（第 4.1 节）、独立 512 页 `OP_BENCH_VM_APPLY_512` 批量替代方案微基准（第 3.3 节）、宿主机 `perf` 无锁采样并发验证与损坏下层页表 `KLET_KILL` 测试（第 4.2 节第 4 项），以及真实硬件 AMX `XFD #NM`（当前 AMD Ryzen 7 5800H 无 AMX/XFD 硬件支持，且 QEMU 11.1.3 TCG 不支持 `CPUID[0xD,1].EAX.xfd`）。
- **被测循环零插桩**：废除原仓库 `prototype/kernels/mem/mem.S` 在整段通读时逐页插 `lfence; rdtsc` 的写法。内存初始化、预热和事后校验均放在计时区外；两侧使用同一静态 C 程序以 `clock_gettime(CLOCK_MONOTONIC)` 在循环外包裹单次操作或整趟 64 MiB 遍历（`fork_64m` 与 `cow_write_*` 使用 `go_pipe`/`ready_pipe` 栅栏消除父子进程竞争）。
- **启动与报告口径**：Stage 3 对比配置各独立启动 **5 次**；Stage 4 按打乱顺序（shuffled order：`R1: native direct vma`，`R2: direct vma native`，`R3: native direct vma`，`R4: direct vma native`，`R5: vma native direct`）各独立启动 **5 次**（每次启动内跑 5 轮取中位数），此外对 `poc_async_destroy=0` vs `1` 各跑 **3 次**消融启动，以及开启 `CONFIG_MITIGATION_PAGE_TABLE_ISOLATION=y` + `pti=on` 的专项安全与 MM 验证。`results.md` 同时报告 5 次启动的中位数（Median）、平均值（Mean）、`[min, max]` 范围、原始逐次数值、相对 `Native Linux` 的比值以及 `VMA / Direct` 加速比。

---

## 2. 开销剖析实验（支撑 `Problem and motivation`，Intel PT）

在 Intel 宿主机上对 **改前 Kernelet（PR #3 基座 + VMA 服务）** 采集 **5 次启动 × 10 ms 的 Intel PT trace**（开启周期计数，同时对比未追踪运行以确认追踪扰动在可忽略范围），列出每一步的 `Instructions | Cycles | Time (ns)`，用于实测支撑提案提出的问题根源：

1. **单页映射（`vm_map`）拆解**：精确测量一次单页 `CursorMut::map` 内部各段耗时——vOSTD 检查与服务栈切换、拿 `mmap_read_lock` 与 `vma_lookup`、`track_pfn_insert`（PAT 检查）、`insert_pfn`（第 1 次 4 级页表遍历 + PTE 锁 + 写 PTE）、`klet_space_ptes`（第 2 次 4 级遍历 + PTE 锁校验 `klet_pte_is_pfn`）以及解锁返回。
2. **缺页异常（`#PF`）进内核拆解**：对比改前“RCU 查 VMA + `handle_mm_fault` + `klet_space_report` 回调”与改后“入口直接走 `on_exception` 钩子”省掉的指令数与周期。

---

## 3. 端到端性能对比实验（支撑 `Validation and evidence` 与 `Alternatives`）

扩展 `research/mem-baseline/tools/forkbench.c` 为静态编译基准程序，并在 Kernelet 测试内核中实现对应的无插桩用户态负载。在 **Native Linux | 改前 Kernelet | 改后 Kernelet** 之间测试以下 **5 个批量改页表的 syscall + 3 种直接访存触发的 `#PF` 缺页**（规模统一为 **64 MiB = 16,384 页**，除另注明子项外）：

### 3.1 5 个批量改页表的 `syscall`

| 操作 | 测试内容与两侧对齐细节 | 校验不变式 |
|---|---|---|
| **`mmap(..., MAP_POPULATE)`** | 一次调用将 64 MiB（16,384 个预先分配的物理页）全部填入页表；随后从头到尾读遍历一遍，单独计时读遍耗时。 | 读遍历 **0 次缺页** |
| **`fork()`** | 写满 64 MiB 并预热后调 `fork()`（父进程 16,384 项改只读、子进程建 16,384 项映射、刷 1 次 TLB；Linux 侧用管道栅栏令子进程等父进程 `fork()` 计时结束后再开始读，避免子进程抢跑混入 `fork` 耗时）；随后分别计时**子进程首读**与**父进程重读**。 | 父子读遍历均 **0 次缺页** |
| **`mprotect(..., PROT_READ)`** | 对写满的 **2 MiB** 和 **64 MiB** 区域调一次 `mprotect` / `protect_next` 清写权限并刷 TLB（同时记录纯改表与含刷 TLB 耗时）；随后测一遍读遍历。 | 读遍历 **0 次缺页** |
| **`munmap()`** | 对已写满的 64 MiB 调一次 `munmap` / `CursorMut::unmap` 清掉全部表项并刷 TLB。 | 不相对 `zap_vma_ptes` 退化 |
| **`exit()`** | 销毁整个进程地址空间，测两组：(a) 占满 64 MiB 的进程退出；(b) 刚 `fork` 出来什么都不做的空进程立即 `exit`（专门检验 `vm_destroy` 加入 `synchronize_rcu()` 对短命进程退出的固定延迟影响）。 | 物理页与页表页全部归还 |

### 3.2 3 种读写内存触发的缺页异常（`#PF`）

用户程序先映射 64 MiB 空虚拟区间（页表初始为空），再通过实际访存触发缺页异常（Linux 侧通过 `getrusage` 的 `ru_minflt`、Kernelet 侧通过内核计数核对精确缺页次数）：

| 缺页场景 | 测试内容与两侧对齐细节 | 校验不变式 |
|---|---|---|
| **匿名页单页写缺页** | 按 4 KiB 步长向 64 MiB 区间每页写 1 字节，每次现场分配并清零 1 个物理页填入页表（Linux 侧为 `MAP_PRIVATE \| MAP_ANONYMOUS` + `MADV_NOHUGEPAGE`）。 | 精确 **16,384 次缺页** |
| **文件页预读缺页（Fault-around）** | 按 4 KiB 步长读 64 MiB 区间，每次缺页将周围 **16 个预先分配好的物理页**填入页表（对齐 Linux 先填满 page cache 的 64 MiB `memfd` 读缺页，两侧均无现场分配与清零开销）。 | 精确 **1,024 次缺页** |
| **`fork` 后写时复制缺页（COW）** | 对 `fork` 产生的只读 64 MiB 按页写触发 `#PF`，分两种情况：(a) 父进程已退出、物理页仅剩单引用，直接原地改回可写并单页刷 TLB；(b) 父进程存活、双引用，分配新页拷贝 4 KiB 后按 OSTD 契约执行 `unmap` + `map` 换页表。 | 精确 **16,384 次写缺页**，父进程原页内容不被覆盖 |

### 3.3 替代方案参考微基准（支撑 `Alternatives`）

不单独维护完整的双槽位 `vm_apply` 批量服务原型，仅在 `endovisor` 测试开关下测量**单次 `mmap_read_lock` + `vma_lookup` 内连续填 512 个非连续物理页（2 MiB）**的宿主侧时间下界（分别测循环调 `vmf_insert_pfn_prot` 与 `apply_to_page_range` 单锁填充），配合上述三类单页 `#PF`（batch size = 1、无法凑批）的数据，定量界定“批量内存服务”替代方案的收益上限与短板。

---

## 4. 功能与安全检查（支撑 `Functional checks`）

### 4.1 适配并跑通现有 `make mem` 回归套件

在新方案下跑通全部已有测试 target：
- `mem-func`、`mem-conc`、`mem-pressure`、`mem-kill`：移除对已删除的宿主机 `vm_map`/`vm_unmap` 计数和 `vm_map` 睡眠测试钩子的旧依赖，替换为对应的新观测点与 kernelet 侧延时测试点；
- `mem-r2`：验证新方案下 `map`、`protect_next`、`unmap` 在持有自旋锁与关中断下**合法成功**（不再触发 R2 限制），而保留的睡眠服务（`vm_create`、`vm_destroy`、`mem_alloc`）在持自旋锁调用时仍按预期触发 R2 panic。

### 4.2 针对新设计的专项功能检查

1. **PTI 开启验证**：新增开启 `CONFIG_CPU_MITIGATIONS=y`、`CONFIG_MITIGATION_PAGE_TABLE_ISOLATION=y` 并在内核启动参数传入 `pti=on` 的测试构建，验证 `BootArgs` 正确上报 PTI 与 NX 标志，用户态代码可正常取指执行，同时内核根页用户半区顶层项严格带有 `_PAGE_NX`。
2. **双 vCPU 中间级页表并发分配**：两个 vCPU 同时在相邻但属于不同 2 MiB 子树的未分配区域（共享同一个未分配 PUD 或 PGD 槽位）发起映射，验证跨核竞争安装中间级页表不会丢页或漏表，空间销毁后分配器在用页数严格归零。
3. **异常边界与 PR #3 寄存器保存**：
   - 逐一在用户态触发提案规定的全部 **11 种转发异常**（需先统一 `prototype/vostd/src/arch/cpu/context.rs` 中补齐 `#SS(12)` 并移除 `#BR(5)`/`#NM(7)` 转发，且用户态 `#PF` 需同时覆盖 `< TASK_SIZE_MAX` 与 `>= TASK_SIZE_MAX` 内核高地址并校验 `X86_PF_PROT` 错误码脱敏），验证经 `on_exception` 与 PR #3 返回用户态后 `RCX`、`R11` 等通用寄存器完好无损；
   - 验证内核态 `copy_from_user` 访问未映射或只读用户地址时干净返回 `-EFAULT`（不触发 `on_exception`）；
   - 在实际暴露 AMX/XFD 且支持相应行为的平台验证 `XFD #NM` 由宿主优先处理且不会残留旧陷阱号；本机 KVM/TCG 均不满足这项前提，保持未验证；
   - 验证未转发致命异常仍交给 Linux 默认路径处理，终止 carrier 并经 lifeline 干净回收整个沙盒。
4. **`perf` 采样与损坏页表 `KLET_KILL`**：
   - 宿主机挂载 `perf` 对运行中的 carrier 进行无锁采样，并发执行映射切换与空间销毁，确认 `_PAGE_SPECIAL` 等标志让宿主安全跳过、无异常日志或引用计数损坏；
   - 在测试内核中故意破坏 Grant 内的下层页表页（例如写入自环指针、越界物理页号、保留位），随后从宿主机发送 `KLET_KILL`，验证宿主机只清零顶层 256 项而不读取下层坏页表，`endovisor.ko` 可无泄漏干净卸载。

---

## 5. PoC 执行清单（已执行 vs 延后）

| 计划项 | 状态 | 说明 |
|---|---|---|
| PR #3 + PR #7 集成验证（Stage 3） | **已执行**（KVM 5 次对比启动） | 完成 2-vCPU SMP、`getpid` 与寄存器保存、x87+SSE/AVX 跨 `getpid` 零保存恢复、CPU 0 A↔B FPU 切换、`rt_sigreturn` 校验。 |
| 256 MiB 分块 Grant 与 64 MiB MM 对比（第 1、3.1、3.2 节） | **已执行**（KVM 5 次打乱启动 + 6 次 `async_destroy` 消融） | 覆盖全部 14 项 `MM_RESULT`（`anon_pf_1page`、`memfd_faultaround_16p`、`mmap_populate_64m`、`mmap_populate_read_64m`、`fork_64m`、`child_read_64m`、`parent_read_64m`、`mprotect_ro_2m`、`mprotect_ro_64m`、`cow_write_1ref`、`cow_write_2ref`、`munmap_64m`、`exit_empty`、`exit_64m`）与 `POC_STATS_JSON` 计数。注：`bench_mm.c` 对每轮仅采集单次 64 MiB 遍历（以 `clock_gettime(CLOCK_MONOTONIC)` 计时），且 Asterinas `do_sys_mmap` 将 `MAP_POPULATE` 延后至缺页时填充。 |
| PTI 开启验证（第 4.2 节第 1 项） | **已执行**（`pti=on` KVM） | 临时启用 `CONFIG_CPU_MITIGATIONS=y` + `CONFIG_MITIGATION_PAGE_TABLE_ISOLATION=y` 并以 `pti=on` 通过全部安全与 MM 测试（验证 `poc_switch.S` 在 `CONFIG_MITIGATION_RETHUNK=y` 下 0 `__warn_thunk` 警告，随后已恢复非缓解基线内核）。 |
| 双 vCPU 页表并发、11 转发异常 + `RCX`/`R11`、`copy_*_user` `-EFAULT`、`POC_SANDBOX_KILL`（第 4.2 节第 2–3 项） | **已执行**（KVM `test_mm_safety` + `poc_kill_ms=50`） | 11 项异常全部命中预期信号，`#PF` 恢复后 `RCX`/`R11` 及通用寄存器完好，`PROT_NONE` 状态迁移、双 vCPU 同 PMD 并发 `mmap`/`munmap` 1,000 轮 0 错误，pipe `EFAULT` 检查与 `POC_SANDBOX_KILL` 均通过。 |
| Intel Xeon 物理核绑定与 Intel PT 10 ms 剖析（第 2 节） | **延后（Deferred）** | 本机为 AMD Ryzen 7 5800H，未进行 Xeon 物理核隔离与 Intel PT trace 采集。 |
| 替代方案 `OP_BENCH_VM_APPLY_512` 独立微基准（第 3.3 节） | **延后（Deferred）** | `poc/linux/endovisor/poc_space.c` 已实现接口框架，但未作为独立实验跑分项执行。 |
| `prototype/` `make mem-*` 回归套件适配（第 4.1 节） | **延后（Deferred）** | 本轮采用独立的 `poc/` Asterinas + `poc_endovisor.ko` 验证套件，未改动 `prototype/` 下的 `make mem-*` 目标。 |
| `perf` 无锁采样、故意损坏下层页表 `KLET_KILL`、真机 AMX `XFD #NM`（第 4.2 节第 3–4 项） | **延后（Deferred）** | 宿主 Ryzen 7 5800H 无 AMX/XFD；QEMU 11.1.3 TCG `-cpu SapphireRapids` 不支持 `XFD` CPUID 特性且原生对照组同样在 `#SS`/`#XM`/`#AC` 上呈现 TCG 模拟差异。 |

---

## 6. Syscall 开销归因与优化讨论

本节处理 `getpid` 的固定开销，以及同一入口/出口机制对 FPU、调度和缺页路径的影响。先讨论测量设计与各候选的不变量，明确后补全对照，再用数据决定取舍；当前授权是完善计划和讨论，以下实现、诊断构建与重测均为待执行工作。页表、堆和 grant 的独立设计仍按各自的研究记录讨论。

### 6.1 已有证据与未解问题

本节的路径表与数值描述其原始审查快照。当前接口、二进制和有效测量结论以 [2026-11-17 报告](results/syscall-2026-11-17/README.md) 为准。

已有五次启动的中位数为 Native Linux `38.95 ns`、完整 Asterinas-on-Linux `122.91 ns`，差值 `83.96 ns`，比值 `3.16x`（[结果报告](results.md)，Stage 3）。这只能描述已有条件下的整条路径；缺少同环境原生 Asterinas 和最小处理器两组基线，不能把差值分配给某个函数，也不能直接认定它是 Kernelet 机制的固有成本。新发现的绑核证据缺口要求重新建立基线，不证明旧实验实际发生过迁移，更不证明迁移解释了全部差值。

完整路径的可避免工作与归因限制见 [Kernelet 开销审查](overhead-review/README.md)。内存重测还需先解决页大小与计时前提：审查所读 Linux 配置关闭 `ADVISE_SYSCALLS`、启用 THP always，而基准忽略 `MADV_NOHUGEPAGE` 失败；历史日志也没有实际页大小/缺页数证据。`MAP_POPULATE` 和 child exit 的计时边界另有语义差异。未完成这些核对前，不以巨大 MM 比值推导 Kernelet 每页的固有成本。该审查基于有时间和内容摘要的源码快照，不将并发源码清理追认为已测优化。

进一步的源码和当前产物核对见 [syscall-overhead-source-audit.md](syscall-overhead-source-audit.md)。讨论统一使用以下证据边界：

| 项目 | 当前能确认的事实 | 尚不能据此得出的结论 |
|---|---|---|
| 寄存器上下文 | `poc/ostd/src/arch/x86/cpu/context/mod.rs` 的 `from_frame` 借用活跃 `pt_regs`；`Frame` 分支的 `sync_to_frame` 不复制整帧 | 所有寄存器访问和分派都没有开销；只有 `Context` 才可能是瓶颈 |
| POSIX `Context` | `poc/kernel/core/src/context.rs` 中是五个借用字段，不是硬件上下文切换，也不在这个构造中分配堆内存 | 每次构造都昂贵，或构造必然被编译器完全消除 |
| 原生与 Kernelet 入口 | 当前 checkout 的非 `kernelet` 路径在 `thread/task.rs::create_new_user_task` 中于循环外建立 `Context`，并在外部捕获 panic；`Thread::handle` 每次事件入口重新建立借用和捕获边界 | 原生 Asterinas 每次 syscall 同样重新进入这个捕获边界；仅凭这个差异可确定其耗时 |
| ptrace 与信号 | 未跟踪时 `ptrace_may_stop_on_syscall` 提前返回；信号队列均空时 `dequeue_pending_signal` 在获取 dispositions 锁前返回 | 热路径每次执行完整 ptrace/信号处理，或这些检查可以删除 |
| 栈检查 | 当前 `.ko` 的固定步长除法/取余已编为位测试和移位，没有 `div` | 再把源码改成位运算能消掉一个除法瓶颈；当前 `.ko` 就是旧五轮实验的同一二进制 |
| 返回屏障 | `poc_do_user_run_on_linux` 每次发布 USER 状态后执行 `smp_mb()`，然后检查 pending | 已测出屏障占多少 ns，或可直接删除它 |
| FPU/TLS | `CpuSync::before_user_exec` 仅在状态为 `InMemory` 时执行恢复；已有 FPU 计数来自整套运行 | 三次状态检查等于三次硬件恢复，或整套计数能代替计时窗口内的操作计数 |
| 编译与缓解 | 当前 Linux 配置是 `-Os`、自动栈清零、关闭 CPU 缓解；历史 `pti=on` 记录主要覆盖安全/MM | `-O2`、去掉清零或开启缓解一定改善比值；已有完整的缓解开启 syscall 对比 |

Linux carrier 的检查与 Asterinas tenant 的检查分别作用于不同的任务状态。当前仅设置 `SYSCALL_WORK_KERNELET` 的 Linux 快路径绕过 `syscall_trace_enter`；不能以“carrier 已检查”为由取消 tenant 的 ptrace/信号语义。两边实现相同功能也不等于两边机器码或耗时相同。

### 6.2 必须补齐的四组对照

```text
共同外层：物理机器上的 Linux → QEMU/KVM（单层虚拟机）

L：虚拟机 Linux 6.12 → 普通测试进程
A：虚拟机直接启动原生 Asterinas → 同一测试程序
S：虚拟机 Linux 6.12 → Endovisor → 最小 Kernelet 处理器 → 测试程序
K：虚拟机 Linux 6.12 → Endovisor → 完整 Asterinas Kernelet → 同一测试程序
```

| 组 | 用途与实现约束 | 状态 |
|---|---|---|
| L | 使用当前补丁内核，沿用 `host_init.c` 的 `native-syscall` 分支；与 K 的 Linux、模块可用性、启动参数和基准二进制一致，记录实际加载状态 | 已完成主对照及缓解关闭/自动选择对照，各五次启动 |
| A | 在相同源码的原生配置下构建 release 内核，使用同一个 benchmark ELF，保持 Asterinas 现有接口 | 构建通过；直接启动未得到有效 benchmark 结果，未报告新延迟 |
| S | 拟复用 K 的启动、程序加载和同一个 C 基准，仅把计时中的 `getpid` 交给受审计的最小事件处理器，其他 syscall/事件回到完整处理路径；保留同一 Linux/Endovisor、寄存器借用、栈认证、FPU 所有权与返回协议。单 tenant 固定 CPU，受控窗口内不启用跟踪/信号；记录事件干扰及省略的 POSIX/vOSTD 工作 | 处理器选择与异常窗口判定待讨论；未实现 |
| K | 冻结当前完整 Asterinas-on-Linux、Direct PTE、256 MiB grant 与 2 个 carrier，作为所有候选优化的起点 | 已完成主对照、四项适配层优化及缓解关闭/自动选择对照，各五次启动 |

L、S、K 必须使用同一份 Linux 构建。A 使用不同操作系统内核，统一用户程序和可对齐的虚拟硬件、运行参数，列出不能对齐的调度、中断、设备、vDSO/时钟与构建差异。A 是“原生 Asterinas 作为虚拟机操作系统”，不称为物理裸机测量。需要时再增加物理机专项，不把 TCG 数据并入 KVM 性能表。

`K−L`、`K−A`、`K−S` 分别回答整套部署差距、相对原生 Asterinas 的差距、在最小处理器基础上增加完整处理栈的差距。它们不是可直接相加的独立组件成本；缓存、分支预测和代码布局存在交互。S 是诊断对照，不能把省略 POSIX 功能后的结果当作完整 K 的优化收益。上游 PR 在其他机器上的绝对 ns 值只作背景。

### 6.3 测量前提与统计口径

2026-11-17 的 syscall 实验已使用相同 benchmark ELF、QMP 绑核、raw `getcpu` 校验、每次启动九个计时窗口、五次独立启动和原始 JSON 记录。QEMU 两个 vCPU 分别绑定宿主 CPU 10、12，其他 QEMU 线程绑定 CPU 14；这三个 CPU 属于不同物理核，但宿主其他进程未隔离。L/K 及缓解对照已完成；下列要求中其余基线、独立编译选项消融和硬件剖析仍须分别验证。

1. **冻结来源与产物**：记录主仓库及 `poc/` 的 HEAD、工作区差异、未跟踪源文件清单与内容摘要，保存 Linux `.config`、启动参数、QEMU 版本/命令、C/Rust/OSDK 工具链与完整构建参数。为内核、模块、image ELF、基准 ELF、CPIO 保存 SHA-256。`poc/` 当前有大量本地修改，只有 commit ID 不足以复现。现存文件的新 hash 不追认旧实验来源。
2. **分别验证 CPU 对应关系**：宿主 QEMU vCPU 线程 → 宿主物理 CPU；虚拟机内 carrier → guest CPU；tenant 测试线程 → Kernelet vCPU。Native Linux 和 Asterinas 基准都显式绑定 guest CPU 0，核对 affinity、计时前后 CPU 和可获得的迁移计数；两端 CPU 相同不能证明窗口内从未迁移。carrier 默认绑核与物理核隔离分开记录。相邻 vCPU 避免放在同一物理核的 SMT siblings，记录后台 emulator/I/O 线程放置、cgroup/调度策略、时钟 tick/watch 设置、频率策略和温度；任何未控制项明确披露。
3. **控制构建与缓解条件**：先复现原有未缓解配置，再单独比较 `-Os`/`-O2`；自动栈清零、栈保护、LTO、日志等级各作为独立变量，不能随优化级别一起偷偷改变。主性能构建关闭 `kernelet_getpid_profile`、`kernelet_rq1_diagnostics` 等探针，结合构建命令和反汇编核实，不能只凭 `nm` 找不到符号。另建双方 Linux 路径一致的缓解开启对照，并记录 A 的缓解支持差异。
4. **单独测 syscall 套件**：`host_init.c` 已为两组提供相同的 `syscall` 或 `smp-syscall-fpu` 套件选择。`bench_syscall_fpu.c::raw_getpid_loop` 直接执行 `syscall`，不走 libc 的 `getpid` 包装。每个窗口先预热 50,000 次，再对 1,000,000 次调用整体计时；每次启动采九个窗口，计时外核对返回 PID、CPU 0 affinity、raw `getcpu` 和寄存器保持结果。任一检查失败时，该次启动不进入统计。
5. **独立启动与顺序**：四组各至少 5 次独立启动，按预先记录的随机种子打乱轮次；单项候选用原版/候选配对、交替先后顺序，并插入原版复测观察漂移。报告每个窗口的原始值、每次启动中位数、跨启动中位数/范围和逐轮差值，均值作补充。五个启动样本不支持可靠的单次 syscall p99；一百万次的平均值也不是一百万个单次延迟样本。
6. **计时与剖析分开**：主结果使用整段 `CLOCK_MONOTONIC` 差值除以调用数，核实各 OS 时钟来源及频率尺度；循环外 TSC 读数可交叉校验。TSC ticks 不直接称为核心执行周期。指令数、硬件 cycles、分支/缓存事件只有在本机 PMU/vPMU 支持并经检查后才报告；不可用即记录缺失，不补估算值。
7. **区分 KVM、宿主调度和路径开销**：在单独诊断运行中，按 QEMU vCPU 线程收集可用的 KVM exit 原因/次数、宿主调度停顿和 guest 任务切换计数；先检查追踪能力与权限，采集扰动单列。定位 `CR3`、MSR、FPU 操作的真实执行频度，不能因源码含有相关函数就假设每次 `getpid` 都执行，也不能把所有 KVM exit 算到 syscall 交接层。裸机验证仍是另一层证据。

### 6.4 按执行时间线核对开销

| 阶段 | 主要源码位置（仓库根目录相对路径） | 要回答的问题 |
|---|---|---|
| Linux 入口 | `prototype/linux/patches/0001-carrier-hooks.patch`；构建树 `arch/x86/entry/common.c` | 与 L 共用哪些机器码？仅设置 carrier work bit 时实际多走哪些分支和间接调用？ |
| Endovisor 进入 Image | `poc/linux/endovisor/poc_carrier.c::poc_on_syscall`、`poc_enter_user_event`；`poc_switch.S` | 栈认证、FPU 快路径与切栈各执行什么？有哪些状态/寄存器写入是真正额外的？ |
| vOSTD 事件入口 | `poc/ostd/src/user.rs::user_event_entry` | 当前 Task/handler 查询、虚拟 IRQ 开启、函数指针分派的实际机器码和快路径频度是多少？ |
| POSIX 处理 | `poc/kernel/core/src/thread/task.rs::Thread::handle`；`syscall/mod.rs::handle_syscall` | 重建借用和 panic 边界、参数打包、ptrace、信号、日志分别走什么路径？与 A 的调用结构有何差别？ |
| vOSTD 用户态准备 | `poc/ostd/src/user.rs::enter_user_mode`；`process/posix_thread/cpu_sync.rs` | `should_exit`、抢占、IRQ 屏蔽、`sync_to_frame`、FPU/FS/GS 状态检查是否重复？哪些可以证明满足后合并？ |
| Endovisor/Linux 返回 | `poc/linux/endovisor/poc_carrier.c::poc_do_user_run_on_linux`；补丁 `kernelet_return_to_user` | 地址/flags 检查、pending 握手、Linux exit work 和 SYSRET/IRET 分支各在何种条件下执行？ |

先用冻结产物的反汇编确认控制流，再做低扰动采样或逐项对照。插桩构建只用于区分路径和验证预测，测出探针成本及相对未插桩运行的扰动后仍不把各段差值直接相加成 `83.96 ns`。Intel PT 专项仍受第 2 节硬件条件限制；本机没有该能力不妨碍先完成无插桩对照。

### 6.5 优化候选与讨论清单

以下是当前 syscall 链路可见的候选范围，不宣称穷尽未来的微架构优化。O1–O11 的逐项确认与实现状态见 [讨论决定](overhead-review/decisions.md)。D2 的固定地址初始化和 D3 的通知协议已确认、未实施；D4 暂保留类型查询；D5 的固定事件入口、D6 的 CPU-local 地址复用与 D7 的捕获包装及冷错误处理均已实现并完成相应验证，独立延迟收益待测量。O12 保留已被当前机器码否定的建议。每项讨论必须明确：现有工作为什么需要、状态由谁持有、什么时候失效、候选怎样减少执行工作、怎样证伪收益，以及失败时如何回到完整慢路径。

| 编号 | 候选与可选方式 | 可证伪的预测/区分实验 | 必须保留的条件 |
|---|---|---|---|
| O1 | **POSIX `Context` 与 Task 查询**：保留每次构造但减少重复查询；或在 Task 内维护稳定的已验证关联，入口仍重建短期借用 | 反汇编中实际的查询、借用检查和临时栈写入减少；单独候选在完整 K 中可重复改善 | `Context` 是五个借用字段；不跨用户态保留可能失效的 Rust 引用，不误用 carrier/tenant 身份。exec、退出和调度后的关联必须正确 |
| O2 | **panic 捕获与冷错误处理**：D7 已内联泛型捕获包装，报告、payload 处理、oops 计数和异常退出使用独立冷函数 | Release 与调试断言镜像均已消除三层包装调用，正常路径不再预留 3096 字节报告空间；真实 panic 恢复通过，独立延迟收益待配对测量 | 当前 K 继续按 `event_rsp` 进入，每个事件具有有效的异常捕获终点。保留展开、Drop、POSIX 清理和 Host 报告；本项没有引入跨事件悬挂的调用 |
| O3 | **寄存器表示与 syscall 参数**：保留活跃 `pt_regs` 借用，减少 `Owned/Frame` 分支、临时对象与无用参数打包 | 观察 `from_frame`、`syscall_args`、返回值写入的实际 load/store、拷贝与分支；单独改变表示后比较 | 正常 syscall、异常、fork 子任务、ptrace、信号返回和跨 Task `pt_regs` 所有权都正确；不能只为 `getpid` 返回常量 |
| O4 | **事件和服务分派**：D5 已将事件回调改为宏生成的固定符号，保留 `ServiceTable` 服务调用 | 反汇编已确认三次 handler 回调直接调用；完整路径的独立延迟收益待配对测量，同时观察代码体积和布局 | OSTD 与安全内核的接口职责、创建时的类型检查、handler 生命周期和虚拟 IRQ 顺序继续成立；跨 image 的服务绑定另行讨论 |
| O5 | **CPU-local 访问**：D6 已实现 IRQ 保护区间内的 record/私有基址复用，以及 IRQ mask 的组合访问 | 指定操作的定位已由两次合并为一次；Release 与启用调试断言的镜像均通过审计和运行回归，独立延迟收益待配对测量 | 地址使用受 IRQ guard 生命周期限制，可变字段按需要读取；任务切换和重新启用 IRQ 后按相应规则重新定位。Docker 容器内验证受当前权限限制 |
| O6 | **虚拟 IRQ、抢占与返回握手**：D3 已选定 PR #3 既有协议，所有虚拟中断发布路径均设置 Linux 通知标志，移除返回前 pending 检查及其屏障；其余重复访问另行核对 | 列出生产者、通知清除和 exit hook 的允许交错；检查返回路径的 locked 指令是否消失，再测完整路径及真实事件负载 | 通知必须在 hook 前清除，新通知不能丢失；tick、自 kick、跨核 kick、idle 唤醒、异常、kill 和虚拟内核抢占仍正确。不能只删旧屏障，也不能以本项推定其他屏障均可删除 |
| O7 | **Endovisor 验证与状态写回**：在不改变信任边界的前提下内联、合并读取；把真正不可变的校验移到建立关联时 | 查看栈认证、carrier 状态检查、返回地址/flags 检查中哪些值可证明不变；做单项完整路径对照 | 栈槽释放/复用、伪造地址、异常返回和非法 SYSRET 条件仍被拒绝。不能拿初始化时验证代替会变化的每次验证 |
| O8 | **FPU、FS/GS 与 CpuSync**：保留惰性状态机，合并有证据的重复检查或硬件访问 | 按计时窗口分别统计状态检查、实际保存/恢复、任务切换与相关 MSR 操作；看是否存在预期外的逐调用操作 | 信号/ptrace/`arch_prctl` 更新、首次运行、跨核迁移、宿主抢占和 Task 切换都使状态正确失效；SSE/AVX 数据与 TLS 不泄漏 |
| O9 | **ptrace、信号和 syscall 分派快路径**：保留功能，用有效的无事件标志减少无跟踪/空队列路径上的重复工作 | 先确认提前返回分支；只把实际残留的 load/branch/锁计入候选，对信号/跟踪状态改变做对照 | Linux carrier 检查不能代替 tenant 检查；新增 pending/tracing 缓存必须明确更新者、失效条件与并发发布顺序 |
| O10 | **编译参数、内联和代码布局**：分别比较 `-Os`/`-O2`、函数布局、LTO 和日志消除；审计自动栈初始化的实际写入 | L 和 K 都重建并各自对照，比较绝对 ns 与 `K−L`；`sub rsp` 的栈预留不能算成同大小内存清零 | 缓解、清零和栈保护的变化分别报告；放松保护属于配置取舍。Rust 的 release 与 C 的优化级别分别核实 |
| O11 | **Linux hook 与用户态返回**：在现有 fast path 上精简可证明重复的工作，保持其他 syscall-work 位的慢路径 | 用正常 SYSRET、强制慢返回、启用 ptrace/seccomp/work 位的分别诊断，确认是否重复执行入口/出口工作 | Linux 必需的 tracing、signal、调度、RCU/context tracking、缓解、异常地址处理与 kill 语义不被绕过；检查整个返回协议，不只数几条汇编 |
| O12 | **固定栈步长的除法改成位运算** | 当前 `.ko` 已是 `bt`/`shr`，不存在所声称的除法指令 | 不作为新优化实施；若后续改变步长或编译配置，重新检查对应产物 |

SMP 增减、绑核、关闭追踪或关闭缓解属于对照条件；把 getpid 特判成常量、跳过 ptrace/信号/抢占、禁用 FPU 隔离或栈认证属于功能/保护变化，不混入完整 K 的等语义优化表。`smp_mb()` 不能单凭一轮更快就删除。页表异步销毁也不能用于掩盖尚未满足的 RCU 回收条件。

### 6.6 讨论、实施与验收顺序

```text
核实旧结果来源、时钟、绑核与工作负载
  → 讨论四组对照与各候选的不变量
  → O1/O2/O3：Context、panic、寄存器与入口寿命
  → O4/O5：分派与 CPU-local 访问
  → O6/O7/O8/O11：通知、验证、CPU 状态与 Linux 进出协议
  → O9/O10：剩余常规检查、编译与布局
  → 补齐 L/A/S/K 基线 → 按数据选择单项对照
  → 有效候选组合复测 → 受影响功能回归
```

先讨论所有候选的目的、语义和可选方式；涉及实测才能决定的项记为“待测”，不为凑齐结论而推定瓶颈。顺序不是收益排名；后续测量可调整优先级。一个候选只有在讨论清楚其工作与不变量后才进入实现。每次只改一个语义独立的因素；O2/O6 若需要成组协议变更，明确作为一个整体假设，不拆出会破坏正确性的中间性能版本。

| 阶段 | 交付物与完成条件 | 当前状态 |
|---|---|---|
| P0：证据与讨论 | 来源清单、CPU/时钟核对方案、四组定义、O1–O12 的待测预测与不变量；逐项记录用户决定和保留问题 | 已建立本节与源码核对记录；候选选择待讨论 |
| P1：基线准备 | 对称的绑核/套件选择/多窗口记录，A 原生启动与 S 最小处理器；来源与产物清单完整 | 未实现、未运行 |
| P2：归因 | 无插桩四组数据，受支持的独立诊断与扰动记录；明确未测项，不能伪造细分耗时 | 未运行 |
| P3：单项与组合 | 每项原版/候选配对结果、机器码差异和正确性记录；无可重复收益的项不纳入性能改动 | 待讨论后执行 |
| P4：回归与结果 | 下述对应回归全部通过；新结果使用独立来源标识，保留旧 `results.md` 的原始数据 | 未执行 |

回归按受影响的语义选择：基础项覆盖返回值、所有应保留 GPR、SYSRET/IRET 条件和两个 vCPU；O1/O2/O3/O4 追加 exec、fork/clone、睡眠后恢复、ptrace、信号与 oops；O5/O6/O7/O11 追加跨核 kick、tick、抢占/迁移、kill 与拆卸、栈保护和异常边界；O8 追加 x87/SSE/AVX、同核与跨核 A↔B、TLS/FS/GS 修改及 `rt_sigreturn` 合法/非法状态。已知缺少的测试先列出并实现，不能将现有套件通过当作已覆盖所有这些条件。任何进入正式 image 的改动仍需通过 OSDK 安全/FP/ABI 审计；缓解开启后的功能与性能另列。

同时用已有 `poc-mm` 的 VMA/Direct 场景做受影响回归，检查 syscall 优化是否改变缺页、并发和回收结果。`prototype/ make mem-*` 的移植仍是独立未完成项，不以 PoC 测试替代它。

后续采集工具放在 `poc/linux/bench/`，一次性脚本放在项目内专用临时目录，将该目录加入 `.git/info/exclude`，完成后删除并检查残留。正式性能实验的来源清单、无诊断代码的计时数据、诊断数据与说明归档到 `research/user-page-table/results/syscall-<run-id>/`，说明诊断与正式构建的对应关系。逐项实现的镜像、机器码和功能验证保存在 `overhead-review/` 下相应的专用验证目录；它们与独立性能结果分别记录。
