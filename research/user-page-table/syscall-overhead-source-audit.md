# Syscall 开销：Linux / Endovisor 源码核对

- 日期：2026-11-16。
- 用途：为 `experiment-plan.md` 的 syscall 归因与优化讨论提供本地源码、当前机器码和既有日志证据。
- 范围：只读核对，未修改实现、未构建、未重跑实验。下列候选均没有新增的耗时或收益测量。

## 1. 证据范围与产物对应关系

需要分别记录源码事实、当前构建产物、旧运行日志和待验证假设。当前工作目录中的 `.ko` 或 `.config`，不能自动证明就是旧日志对应的产物。

| 本次读取的证据 | 可确认的内容 | 尚未确认的内容 |
|---|---|---|
| `poc/target/tmp/stage3_v3_native_b5.log:3-4,242,258` | 该次记录为 Linux 6.12 `#3`，`native-syscall`，`getpid_ns=39.20`，`suite_done=1`。 | 本次没有重放该启动，也没有从日志核对内核、测试程序或 initramfs 的内容哈希。 |
| `poc/target/tmp/stage3_v3_poc_b5.log:3-4,306,326-333` | 同样标识为 Linux 6.12 `#3`，`poc-syscall`、Direct、2 vCPU，`getpid_ns=122.91`，`suite_done=1`；整套运行统计为 `fpu_saves=905`、`fpu_restores=907`。 | 整套计数不等于只在 `getpid` 计时区采集的计数。 |
| `poc/target/tmp/diag_syscall.log:304` | 一次诊断运行记录 `cnt=1049921`、`non_sysret=0`、`cx_ne=0`、`r11_ne=0`、`rflags_bad=0`。 | 该诊断不是最终无插桩的五次启动；其分段周期不能直接移作最终归因。 |
| 当前 `poc/linux/endovisor/poc_endovisor.ko` | 80,816 B；SHA-256 为 `b4b9d2ea22892c544928dbb10f81831274d2b597d6b6829f1783a48ce95a5aa8`。本次对该文件作了 `objdump` 核对。 | 没有证明它与 Stage 3 日志使用的模块逐字节相同。 |
| 当前 `prototype/.build/linux-6.12/.config` | SHA-256 为 `ac9ce6d2e6b53690110d3e5f90bed83002d03a57b1d16b480bdd8547d9885c42`；设置 `CONFIG_CC_OPTIMIZE_FOR_SIZE=y`、`CONFIG_INIT_STACK_ALL_ZERO=y`、`CONFIG_PREEMPT_DYNAMIC=y`，未设置 `CONFIG_CPU_MITIGATIONS` 和 `CONFIG_FTRACE`。 | 不代表已核对旧轮次的构建命令、运行期 CPU alternatives 或当前加载的内核机器码。 |

上述日志仍可访问。后续每个实验组都应把源码提交与工作区补丁、配置、构建命令、内核 / 模块 / Rust ELF / 测试程序 / initramfs 哈希与启动命令一起保存，避免原位重编覆盖证据。

## 2. 入口和返回：存在 Linux 工作，但不是重复执行两个 Linux syscall

当前 Linux 入口 `syscall_enter_from_user_mode()` 先建立入口状态、开启物理中断，然后处理 `syscall_work`。当它恰好只有 `SYSCALL_WORK_KERNELET` 时，内联路径直接调用 `on_syscall`，不会进入 `syscall_trace_enter()`。因此，不能把这条快路径描述为每次完整执行 Linux 的 ptrace、seccomp 和 audit 处理；有其他工作标志时仍需检查慢路径。来源：`prototype/.build/linux-6.12/include/linux/entry-common.h:171-189,209-220`；对应可维护补丁为 `prototype/linux/patches/0001-carrier-hooks.patch:192-209`。

`poc_on_syscall()` 检查 carrier 状态、ABI、终止状态，写 syscall 约定所需的寄存器和载体字段，再经 `poc_enter_user_event()` 校验事件栈、标记虚拟关中断与内核状态，进入镜像。`poc_enter_image` 与 `poc_jump_linux_stack` 是两次明确的栈交接；它们自身没有调用 Linux 调度器或切换地址空间。来源：`poc/linux/endovisor/poc_carrier.c:542-591`；`poc/linux/endovisor/poc_switch.S:18-40`。

返回经过 `poc_do_user_run_on_linux()` 的终止检查、用户地址和 flags 规范化、事件握手，再进入 `kernelet_return_to_user()`。后者调用 Linux 的退出准备和 `can_return_via_sysret()`，成功时跳到共用的 `syscall_return_via_sysret`。原先 `on_syscall` 路径在此正常情况下不返回，不能据函数列表认为 `do_syscall_64()` 的正常退出部分还会额外再执行一次。来源：`poc/linux/endovisor/poc_carrier.c:1166-1211`；`prototype/.build/linux-6.12/arch/x86/entry/common.c:81-155`；`prototype/.build/linux-6.12/arch/x86/entry/entry_64.S:1558-1569`。

Linux 退出准备保留了 `syscall_work`、信号、调度和通知的条件处理。Kernelet `on_resume` 也受退出工作循环约束，并非无待处理事件时无条件调用。来源：`prototype/.build/linux-6.12/kernel/entry/common.c:106-174,221-262`。精简宿主检查必须说明哪些状态已经由哪一层维护，保留异常、信号、强杀和慢返回；单凭“检查重复”不足以删除。

## 3. 返回屏障：已观察到 locked 指令，尚未测出其贡献

当前 `.ko` 的 `poc_do_user_run_on_linux` 在偏移 `+0xd6` 有 `lock addl $0x0,-0x4(%rsp)`，对应源码 `smp_mb()`。它确实处于返回路径，而不是一个只在出错时执行的操作。来源：`poc/linux/endovisor/poc_carrier.c:1195-1199`；本次命令为 `objdump -d --disassemble=poc_do_user_run_on_linux poc/linux/endovisor/poc_endovisor.ko`。

但其前后有协议关系：

| 参与者 | 发布状态 | 随后观察 |
|---|---|---|
| 事件生产者 `poc_virq_raise` | 原子置 `pending`，再作屏障 | 观察 `idle` / `state`，唤醒或设置用户返回通知。 |
| 事件生产者 `poc_do_vcpu_kick` | 原子置 `POC_VIRQ_KICK`，再作屏障 | 观察目标状态，执行 self-kick、唤醒、通知或 remote kick。 |
| 返回用户态的 carrier | 设置 `state=USER`、`irq_off=0`，再作屏障 | 观察 `pending`，决定是否设置 `TIF_NOTIFY_RESUME`。 |

来源：`poc/linux/endovisor/poc_carrier.c:416-425,808-843,1195-1199`。这里需要防止“返回者未看到新事件，生产者仍看到旧的 KERNEL 状态而未通知”的交错。不能把消费者侧屏障直接改为普通 store、仅 release-store 或只保留编译器屏障，并据单线程 `getpid` 跑通认定正确。idle 的握手另在 `poc_do_vcpu_idle:865-878`，也不能随同批量删除。

可证伪的实验预测：若这项工作贡献显著，在先证明等价事件协议后，保留其他路径不变的变体应同时减少对应 locked 指令和无插桩端到端时间；若时间不变或收益落在噪声内，应否定其为主要瓶颈。必须回归返回窗口内的远程 kick、self-kick、时钟 tick、阻塞唤醒、信号与强杀；检查丢失通知、延迟和超时，不能只看最终程序退出码。

## 4. 栈检查：当前产物没有所称“运行时除法”

源码的 `% POC_KSTACK_STRIDE` 和 `/ POC_KSTACK_STRIDE` 使用 512 KiB 常量步长。当前 `.ko` 中，前者的 guard 区判断被编成 `bt $0x12,%esi`，后者为 `shr $0x13,%rsi`，没有 `div` / `idiv`。来源：`poc/linux/endovisor/poc_endovisor.h:219-222`；`poc/linux/endovisor/poc_grant.c:303-315`；本次命令为 `objdump -d --disassemble=poc_stack_pool_contains poc/linux/endovisor/poc_endovisor.ko`。

因此，手工把这两个表达式改成位运算，没有已证实的机器码优化空间。范围检查、bitmap 查询、跨函数调用仍存在，能否合并检查或缓存可信栈描述符是另外的候选。事件栈地址来自 `urec.event_rsp`，缓存方案须解释任务切换、栈释放 / 复用和边界验证，不可仅在启动时检查一次后永久信任可变化的栈地址。来源：`poc/linux/endovisor/poc_carrier.c:545-549`；`poc/linux/endovisor/poc_grant.c:278-315`。

可证伪的预测：手工位运算变体若产生相同机器码，就应关闭“消除除法”这个候选；实际减少边界工作时另测完整 handoff，并回归非法栈、guard page、栈溢出、任务切换和回收。

## 5. FPU、MSR、CR3 与 KVM：先确认每轮是否执行

`poc_restore_carrier_fpu()` 只有在 `TIF_NEED_FPU_LOAD` 置位时才加恢复计数并调用 Linux 恢复函数。`kernelet_fpu_restore_carrier()` 再检查该状态并恢复，preempt notifier 的 `sched_in` 走另一条恢复路径。因此，“每次进入都会调用一个含 FPU 字样的辅助函数”不能推导成每次执行 XSAVE / XRSTOR。来源：`poc/linux/endovisor/poc_carrier.c:41-46,317-336,557`；`prototype/.build/linux-6.12/arch/x86/kernel/fpu/core.c:920-947`。需要计时区前后计数与正常 / 抢占 / 任务切换分别观测；保留 x87、SSE、AVX、signal-return 与切换隔离回归。

`poc_do_pt_activate()` 将地址空间切换放在服务调用中，且只在 `current->mm != target` 时调用 `kernelet_switch_mm()`。不能仅因同时存在 Linux 和 Kernelet 就断言每次 `getpid` 必然额外切换一次 CR3。来源：`poc/linux/endovisor/poc_space.c:338-379`。Linux 公共入口 / 出口也含 PTI 条件宏，其运行期形态与 PTI / alternatives 有关，不能按汇编源中的宏名直接计费。来源：`prototype/.build/linux-6.12/arch/x86/entry/entry_64.S:91-95,158-166`；`prototype/.build/linux-6.12/arch/x86/entry/calling.h:172-177`。

另有潜在 MSR 路径：Kernelet `GsBase::save_inactive()` / `load_inactive()` 使用 `rdmsr` / `wrmsr(IA32_KERNEL_GS_BASE)`，但是否在稳态每次 `getpid` 执行，依赖调用者的补充上下文状态管理，不能仅凭函数存在就当成逐调用成本。来源：`poc/ostd/src/arch/x86/cpu/context/mod.rs:298-318`。KVM 是否拦截这些指令、发生多少 VM exit，以及外部抢占 / EPT 等是否影响结果，都需要外层宿主上的可用事件与计数证据；本次未做这项测量。

## 6. 优化前先核对实验绑核

当前 `run_getpid_bench()` 预热后包围一百万次 raw `syscall` 计时，没有自行调用 `pin_to_cpu()`。完整套件先执行 `run_smp_check()`，其末段把主线程 affinity 恢复为所有 CPU，随后直接进入 `run_getpid_bench()`。因此，当前 C 源码不能支持“getpid 计时线程已固定在 Guest CPU 0”这一断言；外层若另有限制，必须单独保存并核对。来源：`poc/linux/bench/bench_syscall_fpu.c:58-70,219,252-264,354-363,1059-1064`。

PoC runner 默认给 carrier 0 / 1 设置 Guest Linux CPU 0 / 1 affinity，这属于另一层。它不能证明 tenant 测试线程固定在某个 Kernelet vCPU，也不能证明 QEMU 的 vCPU 线程固定在物理宿主的某个 CPU。来源：`poc/linux/runner/run-poc.c:321-323,334-360`。

下一轮需要同时记录：测试线程的逻辑 CPU / affinity、carrier 到 Guest Linux CPU 的映射、QEMU vCPU 线程到物理宿主 CPU 的映射。固定测量 CPU 后，还应保存计时前后 CPU 与迁移计数；不要用“两侧都配置 `-smp 2`”代替这些证据。

## 7. 讨论与实验的顺序

| 候选 | 当前证据支持的判断 | 可证伪的下一步 | 最低回归范围 |
|---|---|---|---|
| `-Os` → `-O2` | 当前配置选择 size 优化，尚无收益测量。 | 仅改变该选项，同时重建 Linux 与模块，比较两组和新机器码。 | syscall、SMP、FPU、signal-return、MM、安全套件；分别保留缓解关闭与开启组。 |
| 自动栈清零 | 当前配置开启；没有对热路径实际新增清零指令作逐函数计量。 | 先找实际清零写入，单独做诊断消融；不能与 `-O2` 合并后归因。 | 不能把减少初始化保障默认作为可接受部署方案；先界定用户数据可见性与不变量。 |
| 宿主入口 / 退出辅助函数合并 | 当前有多次检查、栈交接和调用，尚无分段时间。 | 极简处理器与完整处理器分别测，检查实际减少的调用 / load / store。 | ptrace / seccomp 工作标志慢路径、信号、异常、SYSRET 不合法时的 IRET、强杀。 |
| 栈验证缓存 / 内联 | 当前无除法；保留了范围与生存状态验证。 | 对照机器码与可信缓存生命周期，再比较完整 handoff。 | 栈边界、释放复用、guard、切换和故障回收。 |
| 事件屏障重设计 | 返回路径确有 locked 指令；握手等价性未证明。 | 先写完整并发协议，再实现单一变体、测延迟与通知正确性。 | 返回窗口事件、remote / self kick、tick、idle 唤醒、抢占与强杀。 |
| FPU / GS / CR3 状态减少同步 | 有条件恢复和独立状态管理路径，逐 syscall 频率未核对。 | 先给每次真实硬件操作计数，与稳态、切换和异常分组对应。 | TLS / GS、跨任务隔离、宿主抢占、FPU、signal-return、SMP。 |

开始实现前还需分别讨论完整 Asterinas 事件处理、`Context` / `UserContext`、`catch_unwind`、分派和 CPU-local 访问。这份记录没有把这些未测项分摊成纳秒，也没有证明它们是主要瓶颈。极简处理器 / 原生 Asterinas 两组对照能约束问题范围，但其耗时差也不能直接当作互相独立、可线性相加的成本项。
