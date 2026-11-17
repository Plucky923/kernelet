# Linux / Endovisor 可避免开销审查

本报告审查 Linux 承载 Kernelet 额外引入的工作，覆盖正常 syscall、异常与虚拟中断、宿主服务、切换、启动及回收。结论分为“可直接删”“可合并或移出热路径”“需协议改造”“必要”“当前不存在”。分类描述代码处理方向，不代表已经实现、测得收益或证明是现有性能差值的主要来源。本轮未修改实现、构建、采样或运行实验。

## 1. 来源与证据边界

主审来源是协调者在 **2026-11-17T05:32:23.979156Z** 建立的源码快照，包含 1,245 个文件，复制过程没有单文件漂移。仓库根提交为 `a5ec4b875d0a17890321a362fbc3fd16859b7eb4`，`poc/` 提交为 `7f8476ab463f1dcdf901fd650ee4f127298d28ef`；两者均有未提交修改，因此提交号不能代替内容哈希。下面的路径和行号均相对于仓库根，指该快照，而非移动中的工作目录。

| 快照来源 | SHA-256 |
|---|---|
| `prototype/linux/patches/0001-carrier-hooks.patch` | `4b96ab2964ea8ce6f30d8dfff9db5b8597f309fd74835ea0c0ce86139fb2bce5` |
| `poc/linux/endovisor/poc_carrier.c` | `2a6b0d90093f45c32314e7878ef955bd4216d01c7da9a80401b60146524cddaa` |
| `poc/linux/endovisor/poc_switch.S` | `7095c485c2405fcbef1d547fd71835fb6bc6999104cceaca65ae00f7eb738df8` |
| `poc/linux/endovisor/poc_grant.c` | `e618e96f978954ad47113cdf10cc51e130a6fc6a6f1d3e6b9a38cf2fcbc37e46` |
| `poc/linux/endovisor/poc_space.c` | `b0db37b65b0ef154b2822aec530622e2cdcb493aeb2c7dc12f77d57449b2474e` |
| `poc/linux/endovisor/poc_watch.c` | `c7e1f1c0fd68a6ef2b314c721897ab090fa6304dab1feedbe8b4a3ad4d05b2d1` |
| `poc/linux/endovisor/poc_endovisor.h` | `cf7032a1a798512f203ad7fbfd8772798ce0126102bc8fc375b4f36e78e44868` |
| `poc/linux/runner/run-poc.c` | `3f405484201460b0ba41b60dec8ddc529e3f81bef0336608c0964d9545e0f7c4` |
| `poc/linux/endovisor/poc_main.c` | `082aa65776a53098c1f897866879f05420a157ca535cc478109fbeac1a804c78` |
| `poc/linux/endovisor/poc_image.c` | `c51a94cda794c43597a51f39952b7761dfe1ac54ff656b5c3d45a5b2a332260b` |
| `prototype/.build/linux-6.12/arch/x86/entry/common.c` | `1824cb4aad43efe96b08ff460bf21aaa3137ee4a3fa329bb0bd3866346fe5acf` |
| `prototype/.build/linux-6.12/arch/x86/entry/entry_64.S` | `6730c51220c99e26ec00e2e854de44ba8dcc2d77bd0ae2661faa0610080657d3` |
| `prototype/.build/linux-6.12/arch/x86/entry/calling.h` | `7af242e37965c0821649cca9213b54fa6d4b57a2af882dceb6114e9fdf95775f` |
| `prototype/.build/linux-6.12/include/linux/entry-common.h` | `e3de2d0cb63216e93ff39f599d215caa9fbfc8cf53f50e9c9e5f5fd352c094d1` |
| `prototype/.build/linux-6.12/kernel/entry/common.c` | `18d3eb5c531bd2d16be1548c2dfa58182fa5749fa04ae8990fe7832db07b97d5` |
| `prototype/.build/linux-6.12/arch/x86/kernel/fpu/core.c` | `5f22de035ed04d1441cb38261b0fa44513ac21b52a6ad399dae942b61e9a012a` |
| `prototype/.build/linux-6.12/.config` | `ac9ce6d2e6b53690110d3e5f90bed83002d03a57b1d16b480bdd8547d9885c42` |

末次比对时间为 **2026-11-17T05:42:26Z**，表内 17 个快照文件在工作目录均无内容漂移；下面五项补充来源的哈希也没有变化。Rust Host 模块的大量删除属于工作区现状，本报告没有恢复这些文件，也没有把旧模块仍在执行作为前提。

以下补充来源不在快照内，直接只读访问原目录并记录内容哈希：

| 补充来源 | SHA-256 | 用途 |
|---|---|---|
| `prototype/.build/linux-6.12/Documentation/atomic_t.txt` | `717673f723f57ea07ca03d919e2a21e8fc2ce8c8808d3a1c6a9c36ae79885fe0` | 原子操作与屏障契约。 |
| `prototype/.build/linux-6.12/arch/x86/include/asm/atomic64_64.h` | `493daf163b6e63faaeecca409af96dbd481a1402c9445a92a35f006a702c728d` | x86 原子 RMW 实现。 |
| `prototype/.build/linux-6.12/arch/x86/include/asm/barrier.h` | `90a2ef1a5d4801f97d3f3d27af19e9abb5a9d08917f6b34dd5975ca6c8fb7970` | x86 full barrier 与 atomic 后屏障实现。 |
| `poc/linux/endovisor/poc_endovisor.ko` | `b4b9d2ea22892c544928dbb10f81831274d2b597d6b6829f1783a48ce95a5aa8` | 旧构建的机器码观察，文件 80,816 B，mtime 为 2026-11-16 20:33:50 PST。 |
| `poc/target/tmp/diag_syscall.log` | `7575619fc9af471b3d61a290df2245bbfe2ad0b8499a7086d7928cd6b07ef0d8` | 旧诊断运行的返回方式计数。 |

没有验证旧 `.ko` 的构建输入与快照逐字节对应，也没有运行它；机器码观察只描述这个产物。诊断日志不能追认最终无插桩五轮，也不能作为当前清理后源码的运行结果。

## 2. 正常 syscall 的实际时间线

正常 64 位 `getpid` 的 Linux / Endovisor 部分为：

1. CPU 进入 `entry_SYSCALL_64`，构造 Linux `pt_regs`，进入 `do_syscall_64`。
2. `syscall_enter_from_user_mode_work` 看到只有 `SYSCALL_WORK_KERNELET`，直接调用 `on_syscall`。这条路径不完整执行 `syscall_trace_enter` 中的 ptrace、seccomp、audit。
3. `poc_on_syscall` 建立 syscall 约定，`poc_enter_user_event` 校验栈、发布 `KERNEL` / 虚拟关中断状态，`poc_enter_image` 切到镜像栈。
4. Rust 处理事件；随后调用 `poc_svc_user_run`，`poc_jump_linux_stack` 切回 Linux 栈。
5. `poc_do_user_run_on_linux` 规范化返回帧、发布 `USER`、检查 `pending`，调用返回包装。
6. `kernelet_return_to_user` 调用 `kernelet_do_return_to_user`，完成一次 Linux 出口准备和一次 `can_return_via_sysret` 检查，跳到公共 `SYSRET` 或 `IRET` 出口。

来源：`prototype/.build/linux-6.12/arch/x86/entry/entry_64.S:91-166,1558-1569`；`include/linux/entry-common.h:171-189,209-220`；`arch/x86/entry/common.c:119-155`；`poc/linux/endovisor/poc_carrier.c:542-591,1166-1211`。本节后续简写 Linux 路径仍以 `prototype/.build/linux-6.12/` 为前缀。

`poc_on_syscall` 正常成功路径不返回，因此原来 `do_syscall_64` 的 `syscall_exit_to_user_mode` 和 `can_return_via_sysret` 不会再跑一次。正常 syscall 的两次栈交接也不是两次 Linux 调度或两个 VM 入口。旧 `diag_syscall.log:304` 的 `non_sysret=0` 仅说明那次插桩运行的 1,049,921 次计数没有走非 SYSRET 返回；当前静态调用图仍只有一个公共出口。**“每次重复执行两轮 Linux syscall 出口”分类为当前不存在。**

## 3. 普通 syscall 热路径

### LH01：重复写入稳定的 `pt_regs` 与 Linux 栈锚点

**分类：可合并或移出热路径。频度：每次正常 syscall。** `poc_on_resume(NEW)` 已在 `poc_carrier.c:658-660` 设置 `c->user_regs`、`c->linux_sp` 和 `urec->pt_regs`；`urec->pt_regs` 在该 C 文件中没有其他运行期写入。异常入口 `612-616` 遇到不同的临时帧时也将其复制回原锚点。但 `poc_on_syscall:587-588` 仍每次重写 `user_regs` 与由它计算的 `linux_sp`。

对运行期不再对 carrier 执行 Linux exec 的正常载体，可把这两个字段设为每 carrier 的稳定属性，初始化一次，syscall 入口仅在调试构建断言 `regs == c->user_regs`。这直接移出两次字段 store 和栈地址计算。反例是载体在运行期确实更换 Linux 内核栈或恢复机制改变帧位置；若要支持这种机制，必须在它的状态转换点更新锚点。复核入口、首次启动、异常临时帧、迁移及退出即可验证该契约，不能只删赋值而不固定契约。

### LH02：汇编再次对已经对齐的栈地址取整

**分类：可直接删，条件是保持当前封闭调用契约。频度：进入 / 离开镜像和每次普通服务切栈。** `poc_switch.S:20,34,52` 的 `andq $-16,%rsp` 重复处理已经对齐的输入。事件入口 `poc_carrier.c:548` 拒绝非 16 字节对齐 `event_rsp`；boot 栈由 `poc_grant.c:208-215,239,533-545` 的页对齐、512 KiB 步长池生成；所有 `linux_sp` 赋值 `poc_carrier.c:588,616,659` 都显式 `& ~15UL`。旧 `.ko` 的 `poc_jump_linux_stack+3` 确实保留了这条 `and`，不是已被编译器消除的源码形式。

这只能消去冗余取整，不能取消保存 Linux 栈锚点、镜像栈隔离或调用前的 ABI 对齐。引入新的未校验调用者时，反例是直接传入非对齐栈并破坏 callee ABI；应将输入对齐作为汇编函数契约，而非恢复每次取整来掩盖调用错误。需要重新跑 ABI 审计与 `objtool`。

### LH03：纯 `call` 返回包装

**分类：可合并或移出热路径。频度：每次返回用户态。** `poc_switch.S:68-72` 的 `poc_return_to_user` 仅 `call kernelet_return_to_user; ud2`；真正 helper 一开始就把 `%rsp` 改成 `regs`，不使用包装的返回地址。旧 `.ko` 同样是该两条指令。

可将包装并入统一返回入口，或在正确的 `noreturn` / `objtool` / unwind 标注下改为尾跳，消去额外的 call 和返回地址 store。`ud2` 正常路径不执行，不应计作稳态指令成本；它的故障防护作用也不是性能瓶颈。不能为了尾跳而省略 Linux 出口准备和异常情况下的 IRET。

### LH04：重复的 `orig_ax`、CS / SS、flags 与用户地址工作

**分类：可合并或移出热路径；通用验证仍有必要。频度：每次返回用户态。** `poc_on_syscall:585-586` 已设置 syscall 号和 `orig_ax=-1`，返回 `1178-1185` 又检查 IP / SP、规范化 flags、重写 CS、SS、`orig_ax`；紧接着 Linux `can_return_via_sysret` 又核对 IP、CS / SS、RCX / R11 与 flags（`arch/x86/entry/common.c:81-115`）。普通 `getpid` 不改变这些控制字段，因此存在按“未改控制状态”路径合并写入 / 验证的空间。

可把“规范化并选择返回方式”放在一个拥有完整契约的宿主 helper 中，区分保持原帧的 syscall 与修改 PC / SP / flags 的 signal-return、异常恢复和新任务。不能根据 `from_syscall=true` 就省略所有检查：`rt_sigreturn` 同样是 syscall。非 canonical RIP 的 SYSRET、错误 CS / SS 及 signal-return 改帧是反例；SP 提前转发 `#GP` 还涉及当前 PoC 的可见异常语义，需先决定是否保留。`orig_ax=-1` 使 Linux 不把 tenant syscall 当成可重启的 Linux syscall，至少应在建立约定的位置保留。

### LH05：入口、宿主服务结束和最终返回的终止检查

**分类：可合并或移出热路径；不能把跨执行阶段的检查全部当作重复。频度：入口和最终返回每 syscall；服务出口每服务。** `poc_carrier.c:580-582,1069-1071,1174-1176` 分别读 `stopped` / `dying` 和 `fatal_signal_pending`，`on_resume:643-646` 再检查一次。

返回位置的 `fatal_signal_pending` 可考虑统一到 Linux 出口：`exit_to_user_mode_prepare` 在关中断后读取最新 TIF；有信号工作时进入循环，而 Kernelet `on_resume` 在 `arch_do_signal_or_restart` 之前处理载体（`include/linux/entry-common.h:336-349`；`kernel/entry/common.c:113-158`）。须证明 syscall 和异常两种返回都保持这个顺序，保留 `stopped` / `dying` 尚未转为 TIF 时的终止语义。入口与出口之间可以有任意长的 Kernelet 执行或阻塞，异步终止状态会改变；反例是只保留入口检查导致阻塞期间收到强杀后继续返回。普通服务出口的 `doomed` 又负责在回到镜像前退出，不能无条件挪到最终用户返回。

### LH06：载体身份与分派层数

**分类：可合并或移出热路径。频度：每 syscall 及每服务。** Linux 内联入口检查 `current->carrier_hooks`、`on_syscall` 指针后间接调用；模块又从 `current` 取得载体（`include/linux/entry-common.h:177-183`；`poc_carrier.c:562-569`）。`poc_current_carrier` 只把 `carrier_hooks` 作 `container_of`，且 `hooks` 是结构第一个字段（`poc_endovisor.h:317-320,530-537`），不是复杂的身份验证或多层查表。

可给 hook 传已经取得的宿主上下文，或用受约束的直接分派减少同一指针的重新读取。是否值得改变公共 Linux hook ABI，要看实际机器码和可维护性。注册 / detach 必须保证 work bit、非空 hook 与生命期一致（`poc_carrier.c:226-230`）；Linux 上其他载体类型和外部追踪使“看到 KERNELET bit 就无条件解释成某一模块结构”成为反例。正常入口已有 only-KERNELET 快路径，不能再把它列成尚未做的优化。

### LH07：事件栈范围、guard 与 live bitmap

**分类：可合并或移出热路径。频度：每次 syscall / 异常 / 内核事件入镜像。** `poc_enter_user_event:545-549` 读取 `event_rsp` / `event_stack_limit`，检查对齐、预留空间和 `poc_stack_pool_contains`；后者检查全池、guard、槽位数和 live bitmap（`poc_grant.c:303-315`）。当前源码有这些真实验证。

可由任务激活时发布宿主认可的栈描述符及 generation，使每次入口只验证该任务栈的必要边界，避免重新解码全池和读独立 bitmap。`poc_kstack_free:278-300` 允许槽位释放复用，因此“启动检查一次后永远信任 event_rsp”不成立；缓存要与任务切换、释放、复用、故障回收相连。旧 `.ko` 已把 `%` / `/` 编成 `bt` / `shr`，**“通过改成位运算消除运行时除法”分类为当前不存在**。不能由这一点否定其他范围判断和访存开销。

### LH08：`state`、`irq_off`、`pending` 的多份状态

**分类：需协议改造。频度：每次入镜像和返回用户态。** `poc_enter_user_event:555-556` 写 `irq_off=1` 和 `state=KERNEL`；返回 `1195-1199` 写 `state=USER`、`irq_off=0` 并读取 `pending`。两字段不是同一事实：`state` 区分载体处于镜像 / 用户 / 死亡，`irq_off` 则还描述镜像内部虚拟中断临界区。watch 按 `state` / `depth` 判断能否重定向，按 `irq_off` / `guards` / `irq_level` 判断虚拟临界区（`poc_watch.c:133-137,164-220`）。

可把交接所需状态放入同一宿主拥有的原子状态字，或重新定义“退出镜像后谁消费 pending”，以减少分散 store / load 和屏障。不得直接将 `state` 替换成 `irq_off`：两者在镜像开虚拟中断、宿主服务中、返回交接窗口的组合不同。Rust 返回前的虚拟关中断与 C 交接后的开中断也不是写同一个值的连续重复操作，需与 Rust 事件审查一起核对。

### LH09：每次用户返回的 full barrier

**分类：需协议改造；当前协议下有必要。频度：每次正常用户返回。** `poc_carrier.c:1197` 的 `smp_mb()` 位于 `state=USER` / `irq_off=0` 与读取 `pending` 之间。旧 `.ko` 中为 `poc_do_user_run_on_linux+0xd6: lock addl $0,-4(%rsp)`。

消费者先发布 USER 后检查 pending；生产者先写 pending 后观察载体状态并通知。删除消费者 store→load 顺序可能使双方各看到旧值，返回者错过新事件而生产者按 KERNEL 状态省掉用户通知。不能用 `store_release` 直接代替该 store→load 屏障。可以设计合并状态字的 exchange / CAS、pending 事件登记或不同的 Linux 出口握手；是否减少序列化需结合完整协议和机器码，而不是把 locked 指令换成另一条同样序列化的指令。它与下节可去重的生产者屏障不同。

### LH10：FPU 快路径及重复 TIF 测试

**分类：必要；慢路径测试可合并。频度：每次事件入口一次 cheap TIF 判断，真正恢复只在需要时。** `poc_restore_carrier_fpu:41-46` 在 `TIF_NEED_FPU_LOAD` 置位时才计数并调用 Linux；Linux `fpu/core.c:922-932` 在保存 IRQ 状态后再判断并恢复。`poc_sched_in:322-324` 为统计读一次 TIF，`kernelet_fpu_sched_in` 又读一次（`fpu/core.c:939-946`）。

可让底层“条件恢复”返回是否执行，从而只判断 / 计数一次，或者定义 IRQ 关闭且状态稳定的调用契约；这一优化发生在恢复 / 切换路径，不会去掉普通未抢占 syscall 上的 XSAVE，因为那里原本没有逐次 XSAVE。宿主抢占后恢复载体持有的硬件状态、tenant 之间切换及 signal-return 改状态仍必须正确。不能拿整套运行统计或 SSE 相邻计时差，精确分摊每次 syscall 的 FPU 成本。

### LH11：Linux 公共出口中的最新工作检查

**分类：当前完整语义下有必要；约束载体能力后才可讨论专用出口。频度：每次返回。** `syscall_exit_to_user_mode_prepare` 读 `syscall_work`、处理 rseq 和条件 syscall-exit 工作，随后关 IRQ、读 TIF、处理 signal / reschedule / notify（`kernel/entry/common.c:221-262`；`include/linux/entry-common.h:336-349`）。这是 native Linux 也执行的公共部分，不是全部新增开销。

可以讨论是否明确禁止载体注册 host rseq、host ptrace / audit 等能力，并为 only-KERNELET 定义少做一次性 syscall 工作的返回入口；这属于接口和可见语义选择。不能复用入口的 work 快照来跳过出口读取：追踪附着、信号与调度请求可在执行期间发生。只有 pending 时才进入的 `on_resume`，也不能按每次 syscall 都完整运行来计费。正常返回不存在两个 `syscall_exit_to_user_mode` 调用。

## 4. 宿主服务、事件与切换路径

### LH12：返回值原子 RMW 后的重复 full barrier

**分类：可直接删。频度：每次首次置位的 vCPU kick；普通无事件 getpid 不执行。** `poc_do_vcpu_kick:824-829` 在默认 `atomic64_fetch_or` 后又作 `smp_mb()`。Linux 原子契约规定，无 relaxed / acquire / release 后缀、返回值的 RMW 为 fully ordered，相当于操作前后已有 full barrier（`Documentation/atomic_t.txt:160-185`）。`arch_atomic64_fetch_or` 用 locked cmpxchg 循环实现（`arch/x86/include/asm/atomic64_64.h:137-144`）。

保留默认 ordered RMW 及原来的置位合并语义时，后续独立 `smp_mb` 无需存在。若未来改成 relaxed RMW，此结论随之失效。远程 kick、self-kick、idle 唤醒、返回窗口事件必须仍然正确；这里不允许顺带删除 LH09 的消费者屏障。

### LH13：非返回值原子操作之后用 atomic 专用屏障

**分类：可合并，保持同一协议。频度：每次 `poc_virq_raise`，包括 watch tick；非每 syscall。** `poc_virq_raise:418-419` 为 `atomic64_or` 紧接 `smp_mb`。可换成紧邻的 `smp_mb__after_atomic`，保留所需的 RMW→后续访问顺序；x86 该 helper 为空，而原子指令本身有 memory clobber 与排序（`Documentation/atomic_t.txt:188-206`；`arch/x86/include/asm/atomic64_64.h:129-134`；`asm/barrier.h:74-76`）。旧 `.ko` 确实是 `lock or` 后紧接第二条 `lock addl`。

不能以“atomic64_or 是原子操作”就按通用 Linux API 宣称它本来 fully ordered：无返回 RMW 的通用契约并非如此。用专用 barrier 表达语义比裸删 portable 保证更准确。观察 pending 的代码必须继续位于该操作之后。

### LH14：通用服务参数包、重复载体读取和共享大栈帧

**分类：可合并或移出热路径。频度：每次普通宿主服务，`user_run` 已绕过通用包。** `poc_svc_call:1084-1099` 建立包含五个参数和 MMIO 返回值的 `poc_svc_args`，切栈后 `poc_svc_dispatch:997-1006` 再从 current 取一次载体并按 op 分派。旧 `.ko` 中参数包先 `rep stos` 清零 60 B，再覆写五个参数；dispatch 普通入口保留约 `0x208` 字节栈空间。其 `case OOPS` 的 512 B 清零位于该分支内部，不是每种服务都清零 512 B，不能只按大栈帧归因。

可把已经验证的 carrier 连同参数传给服务端，采用按服务类型的紧凑参数 / thunk，避免所有调用都为未用的参数和返回区初始化，也让 cold OOPS / logging 不扩大常用服务的框架。必须保证 BUFFER 的返回值在每条分支都定义、padding 不泄漏，且 sleeping 服务在 Linux 栈上执行。仅从安全约束清晰的非睡眠服务中寻找直接调用接口；不能把整个 Linux 分派搬到镜像栈上。

### LH15：每次服务结束重复尝试 arm watch

**分类：可移出热路径，依赖 notifier 生命周期。频度：每次普通宿主服务。** `poc_svc_dispatch:1073-1075` 无条件执行条件 FPU 恢复和 `poc_watch_arm`；`poc_watch_arm:253-263` 又判断 enabled / ready / active。首启 `poc_carrier.c:665` 与每次 `sched_in:325` 已负责 arm。

在 `CONFIG_PREEMPT_NOTIFIERS`、载体确实注册 notifier 且所有恢复执行点均覆盖的配置中，可把 rearm 只留在首次运行和调入时；未睡眠、未换 CPU 的普通服务不必重复试 arm。没有 notifier 的编译配置、调度后的不同物理 CPU 或 timer 生命周期变动是反例，不能无条件删。FPU 恢复另有状态契约，不能与 watch 的这个结论一起省略。

### LH16：watch 的重复 guard 检查与每次 upcall 两次全池查询

**分类：可合并或移出事件热路径。频度：watch tick / 立即 kick 触发检查、真正 upcall 时；非普通每 syscall。** `poc_watch_fn:185-194` 已检查 regs、用户 / 内核、depth、state、image text，接着 `poc_redirect_stub:76-89` 又检查同一组条件。在普通非临界分支，`poc_in_critical:133-137` 已确认 `irq_level=0`，helper 仍重复检查。helper 还分别对新帧和原栈地址作全池 / bitmap 验证（`110-112`）。

可将 handler 中已经确定、且 hard-IRQ 期间不会被镜像执行改变的条件作为私有 prechecked helper 的输入，保留 stub / cpu-access 区间、copy-fault、物理 IF、空间预留等剩余约束。forced-yield 分支可能位于临界区，不能直接沿用“irq_level 必为零”的结论。两次栈查询只有在证明属于同一个当前 live 栈后才能合并。编译器也可能内联 / 合并部分重复表达式，新增机器码结论需核对实际构建，而非据源码直接计算省掉的分支数。

### LH17：self-kick 先查自己、加引用再释放

**分类：可合并或移出事件热路径。频度：每次 self-kick；非普通 getpid。** `poc_do_vcpu_kick:813-843` 无论目标是否自己，都先拿 `inst->lock`、查 `inst->vcpus[vcpu]`、取得引用，之后才判断 `target == caller`。

当前载体持有自身生命周期，且 caller 的 `vcpu` 是固定身份时，可在 `vcpu == caller->vcpu` 分支直接以 caller 更新 pending，避免锁、数组读取和一次 get / put；保留“已置位则合并”的行为，以及返回服务后立即 fire watch 的逻辑（`1076-1079`）。远程载体可能退出，不能去掉它的锁和引用；当前载体可能被 unpublish 时是否仍对应同一 vCPU，也必须由 attach / teardown 契约保证。原有 self-kick 修复不能回退为等下一个 1 ms tick。

### LH18：固定 1 ms watch、Linux tick 与计数摊销

**分类：需协议改造。频度：定时 / 事件，不是每 syscall。** `poc_watch_fn` 每 tick 作 task / user / kernel 计数、置虚拟 tick、可能重定向，并每 1 ms 重启；`POC_WATCH_INTERVAL_NS` 是 `poc_endovisor.h:225-229` 的固定值，watch 默认开启（`poc_main.c:51-54`）。这些是 native Linux 调度之外的承载工作；只能说会摊入端到端 wall time，不能在没有时间区间计数时给每 syscall 分配固定纳秒。

可讨论由实际 deadline / pending 事件驱动、合并 Linux 已有时钟事件、运行镜像时才启用监控及降低不必要的 tick 记账。必须保留可抢占与不可合作镜像的两次 strike 上界、虚拟时钟推进、Linux 调度公平性和强杀。`watch=0` 会改变这些语义，不能仅作快版本就当作等价优化。`poc_sweep` 仅在 dying 沙盒的 sweep 被 arm 后工作（`poc_watch.c:293-354`），健康稳态没有同样的一套 sweep 计时开销。

### LH19：idle 的周期唤醒与 on-spin 扫描

**分类：需协议改造。频度：idle 或显式 on-spin 服务。** `poc_do_vcpu_idle:851-878` 对无 deadline 或零 deadline 也使用最多 1 ms 等待，醒来后无条件置虚拟 tick。`poc_do_on_spin:896-925` 按 jiffies 限流后仍遍历载体，每项加锁 / 引用并尝试 `yield_to`。

可用已验证的事件唤醒替代无截止时间的周期 polling，并将 runnable 目标直接登记以避免扫描；必须先保证 remote / self kick、死亡和新任务都能唤醒。没有工作也周期 wake 的情况可以消除，但不能牺牲 wakeup 正确性或把未调度的锁持有者永久饿死。idle 的 `state / idle→pending` 屏障不是 LH12 的 returning-RMW 后重复屏障。

### LH20：全实例原子统计、CPU-slot 与 stolen-time 记账

**分类：可合并或移出相应路径。频度：异常、flush、调度与 tick；不是每次 getpid。** `poc_on_exception:618-620`、`poc_do_tlb_shootdown:405,413` 和 `poc_sched_in/out:312-341` 更新实例共享计数。可按 vCPU / CPU 分片，在停止采样时合并，或把纯诊断项作为明确的独立构建配置；跨 vCPU 共用 cache line 的实际影响未测。

CPU-slot 还供 Rust CPU-local 寻址，`stolen_ns` 供时间语义，不能与纯统计一起删除。迁移或宿主调度后的 slot 发布必须正确。旧构建的寄存器诊断已不在该 C 文件，不能把 `getpid_diag` 的计时开销当作当前代码常驻工作。

## 5. 地址空间、启动和销毁

### LH21：相同 root 的 `pt_activate` 仍查表并改引用

**分类：可合并或移出切换热路径。频度：显式 activate / 任务切换；C syscall 入口没有无条件调用。** `poc_do_pt_activate:358-377` 先 RCU 查表、`mmget_not_zero`，再判断 `current->mm == target`，相同时仍 `mmput_async`。可缓存宿主认可且持有引用的当前 root / generation，在未变化时直接返回，避免查表和引用原子操作。缓存失效须覆盖 root unregister、载体 detach、切换失败和 root 地址复用。不能把未验证 root 与当前 root 数值相同当成永久授权。

真正换 mm 时仍须经 Linux `kernelet_switch_mm` 保持 `task_struct->mm`、TLB 代际和 CPU mask 等状态，不能直接写 CR3 替代。普通 syscall 原本没有这项额外 CR3 切换；PTI 的公共 CR3 宏与是否启用 PTI 有关，也不能按源中出现宏就认定每次已执行。

### LH22：TLB 服务和每 mm 的同步 RCU 等待

**分类：需要的失效 / 等待可批量化；提前归还下层页表需协议改造。频度：shootdown、空间退出与沙盒退出。** `poc_do_tlb_shootdown:396-427` 有 root 查表、权限范围验证和 flush，缺页改权限后不能直接省掉硬件失效。`poc_space_teardown:283-311` 清顶层、`flush_tlb_mm_range(...,freed_tables=true)` 后默认同步 RCU；`poc_spaces_destroy:452-455` 对每个残留 mm 分别等待一次。

整个沙盒已停止时，可分成“全部摘链 / 清 root / flush→一次覆盖这批的 grace period→批量释放”，避免逐 mm 串行等待独立 grace period。单个空间正常退出可引入异步退休队列，但必须把 vOSTD 拥有的下层页表和 grant frame 一起隔离到 safe-to-reuse 时刻。当前 `async_destroy` 只异步释放 `sp/mm`，不能凭这一开关证明先释放下层页表安全。共享 root 的其他载体、perf / NMI 等无锁 walker 是反例；仍需与 Rust 内存生命周期审查合并。

### LH23：启动时可去重的清零，以及应单独报告的初始化工作

**分类：部分可直接删，其他可合并；频度：创建 / 冷启动，不在稳态 getpid 计时区。** `poc_grant_init:416-419` 把所有 shared 页以 `__GFP_ZERO` 分配；到 `481-482` 在没有先写 BootArgs 页的情况下，又 `memset(boot,0,PAGE_SIZE)`。在当前代码顺序下该第二次整页清零是重复的，可删；若以后复用 shared 页则需恢复初始化契约。

256 MiB grant 的逐 grain 分配和安全清零、元数据页映射、initramfs copy / vmap（`poc_grant.c:45-129,441-471,554-578`），以及 image RW 页复制、重定位和 per-vCPU replica（`poc_image.c:627-702`）应分别测创建成本。可以批量映射、共享只读 initramfs、减少临时复制；不能将“删用户可见页的清零”直接当作等价优化，也不能把这些启动工作拿来解释每次 getpid。镜像 RX / RO 页已经从 kind 共享（`poc_image.c:635-637`），该共享不是尚未实现的候选。

### LH24：runner 的监控与绑核

**分类：必要的测量条件应保留；实现可批量化但非每 syscall。** runner 在创建后为每个 carrier fork、Guest Linux CPU 绑核、exec，然后 poll / wait 并在结束时读取统计（`poc/linux/runner/run-poc.c:334-373,390-470`）。runner 本身不在每次 tenant syscall 的处理链中。

减少 runner 创建 / 监控开销应以创建吞吐和 idle CPU 单独报告，不能计成 syscall handler 优化。carrier→Guest CPU affinity 也不等于 tenant 线程或 QEMU vCPU→物理 CPU 的绑核；后两者未证实前，不能将历史结果描述为全部固定物理核，更不能据此断言历史已经发生迁移。

### LH25：日志服务的逐字节 nofault copy、锁与临时分配

**分类：可合并或移出 I/O 路径。频度：每次实际日志服务；普通 getpid 是否发日志必须另行确认。** `poc_copy_str_nofault:928-938` 对每个字节调用一次 `copy_from_kernel_nofault`；`poc_do_log_write:950-994` 每次分配 msg，console 模式再分配 line，每个非 CR 字节均拿一次 `con_lock`，然后复制完成行、调用 printk。

可用有边界的批量 copy，故障边界再退到较小块；一次锁内追加一段文本；将 scratch 放到有明确并发与生命周期的 per-vCPU 区，避免每条消息两次 kmalloc / kfree。需要保留最大长度、故障时已有前缀的处理、跨载体输出顺序和锁外 printk，不能扩大关 IRQ 的最长时间。禁用所有日志只属于工作负载 / 配置变化，不是该服务的等价实现优化。

### LH26：hook 对 native Linux 对照组的影响

**分类：通用 hook 的必要分支可缩短，部分检查可按启用状态移出。频度：对应 syscall work / 异常 / 出口慢路径。** 补丁在用户异常、页故障、内核 fault 与退出工作循环增加 hook 检查（`prototype/linux/patches/0001-carrier-hooks.patch:264-270,627-631,679-683,737-742,752-761,775-779`）。正常 native getpid 的 `syscall_work==0` 不走 Kernelet hook；异常路径即使当前 task 没有 hook，也会多一个被否定的条件。

可用配置关闭、静态分支或受约束的 per-task 入口组织避免未使用服务时的工作，但须保留启用载体时的分派。当前 Native Linux 对照使用同一打补丁内核；它适合比较两种执行方式，却不能单独证明补丁对未承载 native Linux 的影响为零。若要声称该性质，需要未打补丁内核的独立控制组，且不能将两组内核差异混进 Kernelet 本体归因。

### LH27：全局编译选择与精简实际热代码

**分类：可讨论独立构建变体；不是已经证实的 Kernelet 固有成本。频度：影响编译后的所有对应路径。** 快照 `.config:209-210,436,1948` 选择 `CONFIG_CC_OPTIMIZE_FOR_SIZE=y`、关闭 `CONFIG_CPU_MITIGATIONS`、开启 `CONFIG_INIT_STACK_ALL_ZERO`。`-O2` 是可单独比较的构建选择，但也会改变 Native Linux 对照，不能只重编模块后把差值全归于 Kernelet。Rust 的优化和缓解设置需另行核对，不能从 Linux 的一个开关推导整个镜像的生成代码相同。

优先把 cold 大对象移出热 helper，再核对实际保留的清零 / spill / 调用；LH14 已说明“大栈帧”不等于逐次清零全部空间。全局取消自动栈初始化需要独立讨论信息暴露语义，不能与 `-O2` 和路径重构一次改变后分别报告收益。

## 6. 可落实的优先顺序与验证边界

静态上最明确、无需先改变整个调度协议的对象是 **LH01 的稳定锚点重复 store、LH02 的重复栈对齐、LH03 的纯返回包装、LH12 的 ordered-RMW 后重复屏障、LH13 的 atomic 专用屏障、LH17 的 self-kick 自查锁 / 引用，以及 LH23 的重复 BootArgs 清零**。它们作用于不同频度；不能把事件、服务和冷启动项全部加到普通 getpid 的成本上。

结构性候选是 **LH04 / LH05 的返回工作统一、LH07 的可信栈描述符、LH08 / LH09 的合并交接协议、LH14 / LH15 的服务框架精简、LH18 / LH19 的事件与 deadline 驱动、LH21 / LH22 的切换与退休批量化**。这些有可避免工作，但都需要明确所有权、发布顺序和失效条件；不能仅删除分支或等待后用一次成功退出证明等价。

本次验证为：读取快照源码、检查调用点与字段写入、核对 Linux 原子契约和 x86 实现、对旧 `.ko` 指定符号作 `objdump`，以及检查既有诊断日志。没有新增动态证据、没有确认旧产物与当前 Rust 清理状态匹配，也没有给出任何未测的耗时分摊或速度承诺。建议后续按单一候选实施，在保留无插桩计时的独立构建中核对机器码，再分别验证正常 syscall、慢返回、异常、信号 / ptrace、host 抢占、跨 vCPU 事件、idle、强杀和资源回收。
