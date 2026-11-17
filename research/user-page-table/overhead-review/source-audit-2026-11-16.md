# Source audit snapshot: 2026-11-16

This file preserves the source audit at the timestamp below. Current implementation and validation are described in [the review index](README.md).

- 日期：2026-11-16。
- 对象：当前 `poc/` 中的 Linux Endovisor + Asterinas Image，重点为普通 syscall、虚拟事件/服务、Direct PTE、分配和回收；以同 checkout 原生 Asterinas 和 Linux 的职责作对照。
- 源码基准：`2026-11-17T05:32:23.979156Z` 的只读快照，含主仓库 `a5ec4b8`、`poc/` `7f8476a` 上的本地修改；本地 unwinding 和额外依赖的补充读取另有时间与 hash。工作区正在清理，不能只用两个提交号描述本轮对象。
- 验证：源码审查、现存 ELF/模块反汇编、配置与历史日志核对。未修改实现、构建、采样或重跑实验，未测量候选收益。旧产物与本轮源码尚无完整构建对应关系。

## 结论

当前额外工作中，有一批并非 Kernelet 模型要求，可以删除、在创建时确定，或用更窄的接口合并。最具体的是：零参数 syscall 仍取得六个参数、活跃寄存器经过 Owned/Frame 通用表示、每次事件重复做 Any 类型查询、单例实现走多次间接回调、反复解析 CPU-local record、重写稳定的 carrier 栈锚点，以及事件生产者叠加了不必要的屏障。这些不能作为不可避免的 Kernelet 成本接受。

“保持功能”也不意味着保持当前所有检查和调用。应保留的是 Task/地址空间身份、寄存器所有权、通知不丢失、FPU/TLS 隔离、TLB 与回收完成条件等不变量；它们不强制要求当前的数据表示、检查次数、屏障位置或批次大小。

但审查不支持“把现有差值全部删掉”的保证。部分工作来自 Asterinas 与 Linux 共有功能的不同实现，部分是当前协议确实依赖的排序和生命周期，部分开销先前并不存在于普通 syscall。现有 `83.96 ns` 差值没有组件归因，内存对照还存在工作量不等价的问题。

细节按独立路径记录在：

- [Linux / Endovisor](linux-endovisor.md)：carrier 入口/返回、切栈、服务、通知、watch 与 kick。
- [vOSTD / POSIX 事件处理](event-dispatch.md)：E1–E10，寄存器表示、参数、类型、回调、CPU-local、panic、CPU 状态与信号。
- [内存与生命周期](memory-lifecycle.md)：M1–M8 与 B1–B3，页表、TLB、grant、堆、栈、回收及基准语义。

审查后的用户确认与实施要求见 [逐项讨论决定](decisions.md)。D2 的 carrier 固定地址初始化、D3 的通知协议已确认，尚未实施或重测。D5 的固定事件入口见[验证记录](direct-handler-validation/README.md)；D6 的 CPU-local 地址复用见[验证记录](cpu-local-validation/README.md)；D7 的捕获包装和冷错误处理见[验证记录](panic-cold-validation/README.md)。记录包括源码、机器码和真实镜像回归。源码审查中的 S6 / E4、S7 / E6 与 S9 / E5 应结合这些记录阅读；独立延迟收益仍待测量。

## 1. 先区分执行频度和比较对象

```text
普通 syscall：
Linux 保存 pt_regs / entry work
  → Endovisor 固定 carrier 状态与事件栈
  → vOSTD 事件入口、虚拟 IRQ 与当前 Task
  → Asterinas syscall / signal / thread 处理
  → vOSTD 返回准备、CPU 状态与 user_run
  → Endovisor pending 握手、Linux exit work、SYSRET/IRET

条件工作：tick/kick、Task 切换、异常、Host 服务、地址空间激活
批量/生命周期工作：PTE 更新、TLB 同步、grant/栈分配、RCU 与销毁
```

Kernelet 在这条路径中没有引入第二次用户态 `syscall` 指令，也不是重新进入一台嵌套 VM；两次栈交接本身不是两次 Linux 调度或 CR3 切换。是否有特定指令引发 KVM exit 仍需另测。Linux 正常退出部分也不会在非返回式 hook 返回之后再完整执行一遍：正常情况下该 hook 已转入专用用户返回路径，不再返回原 C 调用链。

“原生 Asterinas 也做类似检查”不能证明耗时相同；“Linux 已检查 carrier”也不能代替 tenant 的线程状态与 ptrace/信号语义。下表中的“共有”项可以改善完整 K，但不能全部记为 Kernelet 新增成本。

## 2. 普通 syscall 中值得消除或缩减的工作

“可直接去重”指在已列明的现有调用契约下有源码证明，仍须实际修改、构建和回归；不表示本轮已经安全删除。“改接口”指职责仍在，但可以消除当前通用层。“改协议”需要同时调整生产、发布、消费与回收规则。

| 项目 | 可确认的工作与来源 | 归属 / 处理方向 | 边界 |
|---|---|---|---|
| S1：稳定 carrier 锚点逐次写回 | `poc_carrier.c:587-588` 每次重写 `user_regs/linux_sp`；NEW 分支 `658-660` 已建立这两个值和 `urec.pt_regs`，异常入口把临时 frame 复制回锚点 | K 新增；可移到 carrier 初始化，普通 syscall 使用稳定锚点 | 把 frame 地址固定写成契约，验证所有入口、首次 exec、异常和栈寿命；保留 frame 不一致时的处理 |
| S2：重复对齐与跳板 | `poc_switch.S:20,34,52` 重新对齐已有前置保证的 RSP；`68-70` 包装层仅调用非返回 helper 后 `ud2` | K 新增；在封闭调用者和 ABI 下去重/尾跳 | 首次启动、服务与事件入口的前置对齐分别核对；保留 objtool、unwind、缓解与故障栈契约 |
| S3：零参数调用预取六参数 | `syscall/mod.rs:379-385,407-418` 在分派前取完整参数数组；旧 ELF 保留 number+六参数的表示选择、读取和落栈 | 参数预取为 A/K 共有，Frame 选择为 K 新增；先按 syscall number 分派，再按 handler arity 读取 | 对所有 syscall 通用化，不特判 getpid 常量；覆盖六参数、errno、NoReturn、信号与 restart |
| S4：活跃 frame 带 Owned 快照表示 | `context/mod.rs:106-143,570-614,633-645` 的 getter/setter 匹配 Owned/Frame；旧 ELF 分支仍在 | K 新增；分离 borrowed 运行视图与 owned snapshot，或提供内部专用分派 | 明确 snapshot、fork、ptrace、signal 和 `PT_REGS_OWNER` 切换点；不是删除寄存器保存 |
| S5：每次重新发现已建立的类型关联 | `thread/task.rs:110-123,198-202` 的 Thread/ThreadLocal downcast、process 借用；旧 ELF 保留两个动态 type_id 调用 | 相对 A 执行循环新增；用 typed 用户 Task 关联，在发布时验证、入口借用 | Task/Process/Thread 的拥有者、exec/exit 更新、释放次序和引用环须明确；不能跨用户态持有 RefCell 借用 |
| S6：单例回调的多次动态分派 | `user.rs:198-275,278-301,341-379` 的 Once、handle、should_exit、pre_user_run，旧 ELF 保留三次间接 call | K 新增；OSTD 生成 H 专用入口/bridge，注册时完成类型与初始化绑定 | OSTD 继续封装 unsafe frame，安全内核保持 safe；pre_user_run 必须留在正确 IRQ 状态，不能只把三个调用强行拼起来 |
| S7：CPU-local 每字段重复定位 | `arch/x86/cpu/kernelet_local.rs:17-72` 每次读 BootArgs、GS slot、解码编号、计算 record，再跳回 | K 新增；同一安全窗口内批量访问，或由 Host 提供更直接的 record 定位 | 不跨可能调度的 handler 缓存旧 vCPU 指针；保护区与产物审计一同修改 |
| S8：重复 IRQ/preempt/退出 gate | `kernelet_ops.rs:12-46` 与 `user.rs:289-300`；handler 与 should_exit 重复取得退出状态 | 部分 K 新增、部分 A/K 共有；用有前置状态的返回准备操作合并查询和结果 | handler 可产生新事件，远端也可更新 pending；末尾检查不能因为入口已检查就直接去掉 |
| S9：逐次 catch 的包装和冷路径空间 | K 的捕获按事件建立，A 在循环外；旧 ELF 的 `0x430` frame 包括错误分支的 1 KiB stashed message 临时空间 | 相对 A 新增；先外提冷报告路径，比较更窄包装；持久 catch 另作入口模型设计 | 成功路径不是逐次展开或复制 1 KiB。当前事件栈会被重新进入，不能把 catch 搬到一个已放弃的帧 |
| S10：CpuSync 对 OnCpu 状态自写 | `cpu_sync.rs:204-218` 无条件写回 OnCpu，旧 ELF 保留三份正常路径 store | A/K 共有；合并 dirty 判定或减少冗余 store | 增加分支可能更慢；InMemory/Both 转移、首次运行、切换、信号、ptrace、TLS 更新都要正确 |
| S11：关闭日志仍检查 Debug 站点 | `log/logger.rs:151-164` 静态上限 Debug、动态 Off；旧 ELF dispatcher 仍读动态等级 | A/K 共有的构建政策；提供一致的编译期上限 | 影响运行期诊断能力，属于明示配置取舍；不能说 runtime Off 仍逐次格式化字符串 |

其中 S3/S4/S5/S6/S7 是更值得围绕完整 syscall 链路形成设计方案的项目；S1/S2 是边界较小的去重候选。这个顺序按可避免性与职责清晰度排列，不是未测量的收益排名。`Context` 的五个借用字段本身不分配堆；主要应审的是围绕它反复进行的类型发现、借用建立和接口通用化。

## 3. 事件、服务与调度中的具体冗余

这些项目在相应事件或服务触发时执行，不能按普通 getpid 每次发生计费。

| 项目 | 审查判断 | 需要保持的语义 |
|---|---|---|
| I1：`atomic64_fetch_or` 后再次 `smp_mb` | `poc_carrier.c:824-829` 的默认返回值 RMW 已 fully ordered；其后的显式 full barrier 是重复排序。依据 Linux 6.12 `Documentation/atomic_t.txt:163-206` | 保留 atomic fetch-or、重复 pending 合并和后续目标状态检查，不改成 relaxed |
| I2：`atomic64_or` 后通用 full barrier | `poc_virq_raise:418-419` 可使用紧邻 RMW 的 `smp_mb__after_atomic()` 表达所需排序；x86 此 helper 无额外指令，当前模块可见 locked RMW 后又有 locked barrier | 保持 API 级 ordering；不是把所有 `smp_mb` 都删掉，也不在 RMW 与 helper 之间插新访问 |
| I3：self-kick 查自身、取锁和引用计数 | 已持有有效 caller 时，可先识别目标就是 caller，绕开通用远端查找/引用路径 | 当前实例身份、caller 存活、dying 检查、pending 合并与 self-watch 仍成立；remote 路径继续持引用 |
| I4：通用服务参数先清零再覆盖 | 旧模块显示服务参数对象清零后覆写多个字段；可构造一次初始化和专用服务数据 | 所有会被读出的参数、返回值和错误字段仍初始化；不以未初始化内存换速度 |
| I5：服务 wrapper/dispatch 重复查 carrier | 两层都取得同一个当前 carrier，可在受控调用链传递已验证对象 | 不能在可能切换/退出后继续使用失效身份；服务授权与生命周期检查保持 |
| I6：watch/rearm 与重定向检查位置 | 通用服务重新 arm、watch callback 与 redirect helper 的部分前置检查可集中 | 是否可移出取决于 timer/notifier 的完整运行期契约；不删除长运行/关虚拟 IRQ 时的宿主控制权 |
| I7：时钟转换的通用算术与全局水位 | `kernelet/entry.rs:179-186` 与 `clock.rs:16-26` 每次取时钟用 u128 乘除和 atomic fetch-max；可研究启动时预计算换算系数、在精度边界内使用较窄运算，以及更合适的单调水位所有权 | 只在实际取时钟时发生；不是 raw getpid 每次工作。保持跨 CPU 单调性、频率校准和误差/溢出界限，先确认实际机器码 |
| I8：实际日志服务逐字节工作 | `poc_carrier.c:928-994` 的 nofault 字节复制、逐字符 console 锁与临时分配，可改有界批量复制和段追加 | 保留故障前缀、长度、并发输出与锁外 printk；runtime 关闭 Debug 时没有这整条日志服务 |

尤其要区别 **生产者冗余屏障** 与 **返回用户态的消费者屏障**。`poc_do_user_run_on_linux:1195-1199` 的 `state=USER → barrier → read pending` 与生产者的 `publish pending → barrier → read state` 配对。直接删除返回侧屏障可能让两边同时看见旧值，从而丢通知。它可以成为新通知协议的研究对象，不能按 I1 的证明顺手删除。

终止检查、栈认证、返回地址/flags 规范化也应逐项审查是否可用更窄能力表示、可信发布或已有 Linux 退出工作承担，而不是永久保留当前实现。当前没有证明可跨任意 handler/阻塞/抢占区间取消其全部检查；同样没有证据证明每次完整认证是唯一可行的实现。

## 4. 内存与资源管理：改变表示和粒度

| 项目 | 实现选择及优化方向 | 发生频度 / 限制 |
|---|---|---|
| M2：metadata 重复查询 | `frame/meta.rs::get_slot` 分别执行 has_meta 与 frame_to_meta；可一次验证并返回地址。PageTableGuard 可在持有节点期间缓存 paddr/映射；根专属判断移出叶 PTE 路径 | Frame/PTE 操作；先核对优化后实际机器码，保留地址范围、section、grant 和存活验证 |
| M3：五个操作就全量 flush | `mm/tlb.rs:418-438` 的 `num_ops>4` 在范围判断前选择 full flush，五个连续页也丢整个地址空间 TLB；可按覆盖范围/稀疏度决定 | 小批量 MM；保留失效、同步确认与 Frame 退休时点，64 MiB 结果不能检验这个策略 |
| M4：额外软件根物理页 | 每个 VmSpace 同时分配 Linux PGD 和 grant 中 OSTD 顶层页，并镜像顶层项；可用软件所有权对象加单一硬件根 | 创建/顶层更新；下层不是双份。需重构 Frame/节点析构，不能删掉 Linux mm 或把 Host root 伪装成 grant Frame |
| M5：重复清零与全量预付 | Host 启动分配并清零全部 grain，Frame 初次分配又可能清零；可追踪 known-zero，或分开 initial 与 maximum grant | 创建/首次使用；复用页、slab 元数据与 tenant 写入后必须失效，用户匿名页仍需正确清零 |
| M6：逐 root 等待 RCU | 沙盒整体销毁对每个 root 单独同步等待；可先全部停用、解除顶层和同步 TLB，再合并 Host 宽限期 | 整体销毁；正常 VmSpace drop 不可无条件套用。异步返回要连同下层 Frame 一起推迟复用 |
| M7：栈物理页保留到实例结束 | 释放 Task 栈槽只清 live/allocated，已映射 256 KiB 留作高水位缓存；可有界缓存或退栈后回收 | Task 生命周期/内存密度；不能在旧栈仍可执行或重定向时回收，虚拟 guard 不等于同量物理占用 |
| M8：RunDesc 过量容量与 initramfs 复制 | 当前最多 128 个 run 的 256 MiB 设置却为 8192 项分配 32 页；共同收紧 ABI 可把所需容量降为 1 页。只读 initramfs 可按固定内容对象共享 | 创建期；31 页/124 KiB 是源码容量推导，非实测节省。需要同步 Image 端容量验证和共享对象所有权 |
| M9：BootArgs 再次整页清零 | `poc_grant.c:416-419,481-482` 已以 `__GFP_ZERO` 分配 shared 页，在中间尚未写该页时又 memset BootArgs 整页 | 冷启动的确定重复初始化；可在保持新页保证的契约下去掉第二次清零，与复用页/用户页清零区别处理 |

Direct PTE 的逐页 Host map/protect/unmap 服务已消除；当前 PoC 也已使用本地 OSDK 堆，不是 `prototype/vostd::HostHeap`。这两项不能重复列为本 PoC 尚需移除的开销。小对象/页缓存、COW 的引用和页表算法等原生 Asterinas 共有政策仍可优化，但不能全记作 Kernelet 新增。

## 5. 必须先排除的测量归因问题

| 问题 | 本轮证据 | 对结论的影响 |
|---|---|---|
| B1：4 KiB/THP 前提未成立 | 当前 `.config:235,824-827` 关闭 ADVISE_SYSCALLS、开启 THP always；`bench_mm.c:87,134,158` 忽略 madvise 结果。五份历史 Native MM 日志没有实际页大小或 fault 计数 | 不能把 fork、mprotect、COW1ref 巨大比值全部解释成每 PTE/每 fault 的 Kernelet 增量；当前配置不追认历史实际 THP 布局 |
| B2：MAP_POPULATE 工作不同 | Asterinas 当前 mmap 不执行对应 eager 填页；Native Linux 在 syscall 中完成更多工作 | 比较 mmap 或后续读的单列不等价；需相同 eager 语义或经校验的 mmap+触及总工作 |
| B3：退出计时漏掉前段 | `measure_child_exit:398-405` 先放行 child，之后才开始计时 | 结果是剩余 wait/通知窗口，不能作为完整退出或 RCU 等待费用；需重定计时边界 |
| B4：绑核证据不足 | getpid 计时函数不自行绑核，前序 SMP 测试恢复所有 CPU；carrier 默认绑定只约束另一层 | 需分别验证测试线程、carrier、QEMU vCPU 的位置；未证明旧运行实际迁移或迁移占据全部差值 |
| B5：源码、产物、诊断运行混用 | 当前清理树、现存 release ELF、五轮旧实验和非 SYSRET 计数诊断缺少统一内容哈希对应 | 旧 ELF 可证明该产物的指令，不能证明本轮源码或最终五轮所有返回条件；旧数值不是本轮新验证 |

`pages=16384` 是 C 基准常量与归一化分母，不是实际 PTE/缺页数。单次窗口计一百万次调用得到平均值，不能据此报告一百万个独立延迟样本或可靠单次 syscall p99。修复测量条件会改变比较的解释，不等于已经优化了 Kernelet。

## 6. 明确排除的错误计费

- 正常 `Frame` 返回不是每次整帧 memcpy；Owned/切换等分支另计。完整 `LinuxPtRegs` 是 168 B，136 B 只是通用寄存器部分。
- 普通 catch 的成功路径不是每次运行完整 unwinder，也不因此每次保存/恢复 FP control。主审快照的本地 unwinding 已有不处理 FP control 的配置，没有其普通 syscall 收益证据。
- 1 KiB 冷分支空间导致的栈预留，不等于每次复制或清零 1 KiB。
- `Task::current` 不逐次 Arc clone；`poc_current_carrier` 也只是由当前 hooks 找到结构，不是复杂对象查找。
- 未跟踪、无待处理信号时有提前返回；不能把冷路径的锁、格式化和等待逐次计入。
- 同一地址空间上的 getpid 不是每次额外切换 CR3，FPU 状态 hook 也不是每次 XRSTOR。
- 栈固定步长已编成位操作，不存在待消除的硬件除法。
- 第二次空队列 TLB dispatch 不等于第二次 Host shootdown；Image text/rodata 已按 kind 共享，不是每实例重复制。
- 删除未编入热路径的旧 Rust Host/诊断模块能简化源码，但没有已证明的稳态 syscall 指令节省。

## 7. 建议形成的优化批次

1. **确认对照有效**：按 [实验计划](../experiment-plan.md#6-syscall-开销归因与优化讨论) 补齐 L/A/S/K，修复 affinity、实际页大小和计时边界的验证；保留原始数据。
2. **局部去重**：carrier 固定锚点、封闭调用对齐、kick 生产者屏障、服务参数一次初始化。每项保持其余变量不变，检查预期机器码变化；事件项不冒充 syscall 逐次收益。
3. **完整 syscall 接口收窄**：按 arity 读取参数、borrowed/owned 分离、typed 用户 Task、H 专用 OSTD bridge、cold oops helper。先证明状态拥有者与失效边界，再比较各单项及组合。
4. **合并 CPU-local 与通知准备**：在不可迁移窗口合并 record/guard/IRQ 访问。返回 pending 协议另给时序证明，不能与简单冗余屏障混成一次随意删除。
5. **内存和生命周期**：小批次 TLB 策略、metadata 查询/缓存、单硬件根、批量 Host RCU、known-zero 与栈/初始化容量政策；使用相应 MM、冷启动和占用工作负载。

以上批次不是收益承诺，也不授权本轮实现。所有进入完整 K 的优化保留原有正常路径和慢路径功能；最小处理器只作诊断对照。源码/机器码审查可以确定哪些工作没有语义用途，只有受控运行才能回答它们贡献多少 ns、组合后是否仍改善。

## 8. 覆盖范围与保留证据

覆盖的是本 PoC 已实现的 syscall、异常/虚拟事件、Host 服务、MM 和生命周期路径。C 侧 `poc_svc_mmio_read/write` 当前是返回 INVALID 的占位实现（`poc_carrier.c:1214-1228`），本轮没有审出真实磁盘、网络或直通 DMA 的端到端开销，也未把本报告当作完整安全证明。当前清理树是否可构建、候选回归与性能全部未验证。

源码快照、补充读取清单及工作区漂移记录用于把结论绑定到确切来源；各分项报告同时记录代表性 hash 和旧产物地址。临时审查目录在整合后清理；保留的文档与证据仅服务本次审查和后续优化复核。

事件路径增量复核截至 `05:43:57Z`，内存路径截至 `05:44:43Z`；主要变化是删除未启用的诊断、旧 Rust Host 分支和测试，未消除 E1–E10、M1–M8、B1–B3 所述机制。C 侧主审来源没有内容漂移。各项以分项报告的读取时间和 hash 为准，不声称整个仍在变化的工作区已经通过新一轮构建或审查。

主代理另核对了结束归档中的 `poc/ostd/src/arch/x86/cpu/context/mod.rs`（SHA-256 `e56e3306804196476ba087766d4dd7a4a96029de47bbae1e8095e0734f85e8b9`）：相对主审快照的差异仍是旧 Host cfg、未启用探针及 helper 的清理，保留 Owned/Frame 表示、Frame 同步与条件 FPU 保存/恢复；没有据此消除对应审查项。

保留证据为 [sources.manifest.json](sources.manifest.json) 与 [review-evidence.tar.gz](review-evidence.tar.gz)（5,565,911 B，SHA-256 `8f8846a085f0ba05918f8e8522bc1b1627817d127743d0c5c8296e006fe18a85`）。归档包含主审源码范围、补充来源、20 个结束时读取版本，以及 10 个既有构建产物/日志；它不是完整可构建仓库，也不是历史启动的复现。`05:47:07Z` 的结束观察记录到 67 个来源已变化、2 个已删除；这个观察用于标出漂移，不将未逐项复核的新改动自动纳入结论。证据在本目录保留供审查和后续优化复核，不自动删除。
