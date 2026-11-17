# vOSTD 与 POSIX 事件路径的开销审查

- 日期：2026-11-16。
- 范围：普通 `getpid`、条件事件、逻辑 Task 切换，以及与同一 checkout 原生 Asterinas 用户执行循环的比较。仅审查，未修改实现、构建或运行实验。
- 源码基准：主代理于 `2026-11-17T05:32:23.979156Z` 保存的源码快照；本地 unwinding crate 于 `05:34:29Z` 补入。引用使用仓库根目录相对路径，路径后的行号针对该快照。
- 产物证据：现有 `poc/target/kernelet-unsafe-audit-cbd11506de9495a6/kernelet-image.elf`，SHA-256 `fe2758e3491923a1fb6110a479d8bf93cd07c156da9f99e9eacab6832831e63a`。它早于当前清理和本地 unwinding 改动；未建立其与快照的完整构建对应关系。下文地址仅描述这个旧 ELF，不能代替新构建或旧五轮测试的来源证明。

## 1. 结论与归因边界

当前实现确有可以减少的额外工作。最明确的例子是：为零参数 syscall 仍然读取并打包六个参数；通过大 `Owned/Frame` 枚举访问活跃寄存器；每次事件重新进行类型擦除后的查询；固定单个实现却走多个回调。它们属于实现与接口选择，不能当作 Kernelet 固有成本。

也有功能上仍需维持的工作：正确的当前 Task 身份、线程退出、信号/ptrace、抢占、CPU 状态归属和活跃 `pt_regs` 的独占使用。可以改变这些工作的表示与检查位置，但不能把删除其语义当作优化。没有分段计时，本报告不把任何项目分配为若干 ns，也不承诺它们消掉现有全部差值。

需要同时标明来源：有些工作是 K 相对原生 Asterinas 新增的，有些是两种 Asterinas 模式共有、但相对 Linux 仍然可能多余的实现开销。优化后必须分别报告完整 K 的改善和 `K−A`、`K−L` 的变化。

## 2. 每次普通 syscall 的实际时间线

```text
user_event_entry
  → Once 查询回调表、取得本 vCPU 的 pt_regs
  → 解码事件、取得当前 Task 和 handler_data、构造 Frame 视图
  → 开启虚拟 IRQ（快路径也查询 pending / preempt）
  → 间接 handle
      → 每次进入 panic 捕获
      → Thread/ThreadLocal 类型查询、process RefCell 借用、Context
      → ptrace 入口检查、参数读取与分派、返回值写入、ptrace 出口检查
      → 退出/信号/停止状态处理
  → 间接 should_exit
  → shared guard 断言、might_preempt、disable_local
  → sync_to_frame（Frame 通常不复制）
  → 间接 pre_user_run（再次取得 ThreadLocal，检查 FPU/FS/GS 状态）
  → 取得 ServiceTable、调用 user_run 返回 Linux
```

来源：`poc/ostd/src/user.rs:277-301,341-379`；`poc/kernel/core/src/thread/task.rs:110-209`。

原生路径的 `create_new_user_task` 于执行循环外取得 Task/Thread/ThreadLocal、持有 Process、建立 `Context`；`catch_panics_as_oops` 包围整个用户执行函数。K 路径按事件重新进入并正常结束每次 `Thread::handle` 的借用。来源：`poc/kernel/core/src/thread/task.rs:220-265,340-359`。这是真实结构差异，不能说原生也逐次重建相同边界。

## 3. 可操作的审查结果

### E1：六参数预取和打包对 getpid 没有语义用途

**判断：可以消除无用工作，适合先做局部改动。** `SyscallArgument::new_from_context` 无条件取得 syscall number 和全部六个参数，随后才调用大型分派函数；宏其实已经知道每个 handler 的参数数目。来源：`poc/kernel/core/src/syscall/mod.rs:308-341,361-385,407-418`。

旧 ELF 的 `handle_syscall` 在 `0x572fd5..0x573091` 保留 7 次 `Owned/Frame` 地址选择（`cmov`）、读取 number 与六个参数，并把 number/参数全部写到临时栈位置，然后调用 `syscall_dispatch`。因此不能期待编译器已经替零参数 syscall 自动去掉这些动作。该组工作对每次调用都执行；六参数预取为 Asterinas 公用实现，`Owned/Frame` 选择则是 K 表示带来的额外工作。

具体方案：先按 syscall number 分派，在各宏分支按已知 arity 获取所需参数，零参数分支只传 `Context`。这对所有 syscall 统一生效，避免为 getpid 单独返回常量。可继续评估把正常返回值写回放进分支、将 errno/`NoReturn` 转换保留在共同 helper，以减少分派边界的通用 `Result<SyscallReturn>` 栈上中间结果；当前 ELF `0x573081` 确实向 dispatcher 传入栈上输出地址，但未测其独立贡献。必须保留六参数 syscall、可变寄存器 syscall、errno、restart、信号与 `NoReturn` 语义。

### E2：活跃寄存器视图不应承担 owned 快照的完整表示成本

**判断：可通过接口/表示调整消除热路径的通用选择，需要保持借用边界。** `UserContextRepr::Owned(LinuxPtRegs)` 与 `Frame(*mut LinuxPtRegs)` 共享一种类型；每个 getter/setter 都匹配表示。普通事件用 `from_frame` 构造 Frame，但它经多个非内联/间接处理器传递，分支并未普遍消除。来源：`poc/ostd/src/arch/x86/cpu/context/mod.rs:106-143,570-614,633-645,951-978`。

旧 ELF `user_event_entry` 在 `0x6ed3fc` 预留 `0xe0` 字节总栈空间，并在 `0x6ed55b` 检查表示；Owned 分支 `0x6ed585..0x6ed5bf` 才执行复制与控制字段规范化，Frame 分支跳过它。**不能把静态存在的 `memcpy` 算成普通 getpid 每次复制整帧。** 但 E1 所见的 getter 选择与返回时的表示判断确实保留。

方案是把当前运行的 borrowed frame 与可发送/存储的 owned snapshot 分为类型，公开安全字段访问，复制只在显式 snapshot/Task 换入换出时发生；也可以先只增加内部 borrowed 专用分派，不立即改所有用户接口。`OwnedUserContext` 的线程安全快照、fork/ptrace/信号返回、Task 切换时 `PT_REGS_OWNER` 的转移仍要保留。`LinuxPtRegs` 是 168 字节的完整结构（`context/kernelet.rs:26-62`），不能把 136 字节通用寄存器部分当作完整结构大小。

### E3：每次重做 Any 类型查询和 process 借用，不是五个引用本身的必然成本

**判断：可移到建立用户 Task 关联时，或使用保持所有权的专用关联表示。** `Thread::handle` 每次调用 `self.as_posix_thread`、`task.as_thread_local`、`thread_local.process().borrow()`；`pre_user_run` 再次 downcast ThreadLocal。原生执行循环将前两种关联查询和 Context 构造放在循环外。来源：`poc/kernel/core/src/thread/task.rs:110-123,198-202,220-252`；`thread/mod.rs:84-95,176-190`；`process/posix_thread/thread_local.rs:368-376`。

旧 ELF `0x2f9174..0x2f9242` 保留两个动态 `type_id` 调用、128 位 TypeId 比较和 process 借用计数/Option 检查，并非只有五次廉价指针赋值。`Context` 本身仅五个借用字段，不分配堆内存（`poc/kernel/core/src/context.rs:23-30`）；`Task::current` 也只是读取 CPU-local 指针并构造非拥有 wrapper，没有逐次 Arc clone（`poc/ostd/src/task/mod.rs:308-315`、`task/processor.rs:45-50`）。

可以在用户 Task 创建时同时验证 handler 与 local data 类型，保持一个专用、拥有稳定关联的用户执行状态；事件入口由它创建短期 `Context`，无需重新发现类型。当前 Task builder 只预先验证 handler data 的 TypeId（`poc/ostd/src/task/mod.rs:672-707`），不能未经补足 local-data 不变量就取消其检查。该状态须明确 Process/Thread 的拥有者、exec/退出的更新点、释放顺序以及是否产生引用环；不要跨用户态保存 `RefCell::Ref` 或依赖旧 vCPU 的引用。此改法可以保留逐次事件入口，不必先恢复持久栈循环。

### E4：单例注册却逐次进行三次回调和表初始化状态检查

**判断：可去间接化/合并派发，需重新设计公开入口的类型绑定。** 注册接口只允许一个 `H`，Task 构建也验证关联类型；然而运行期每次仍读取 `USER_EVENT_OPS::Once`，再分别调用 `handle`、`should_exit`、`pre_user_run`。正常 syscall 不调用 `has_kernel_event`，它仅在 KernelEvent 分支使用。来源：`poc/ostd/src/user.rs:198-275,278-301,341-379`。

旧 ELF 的 `0x6ed408..0x6ed411` 保留 Once 状态检查，`0x6ed4ff`、`0x6ed50d`、`0x6ed5d1` 三个间接 call 确实存在；不能用 ThinLTO 假定已经去虚调用。ServiceTable 另有 `0x6ed5ec` 间接 `user_run`。`entry::services` 的非空断言也保留（`poc/ostd/src/kernelet/entry.rs:423-429`）。

可比较由 OSTD 生成 `H` 专用的事件入口/bridge、注册时把其地址绑定到审计后的 EntryTable，使 OSTD 内部保留 unsafe frame 构造而安全内核保持 safe。初始化状态可由已验证的注册 token/Task 发布协议保证，减少逐事件探测。合并回调时必须保留中间抢占和关 IRQ 顺序，不能把 `pre_user_run` 提到开 IRQ 的 handler 中；Host 服务是跨 image 的动态绑定，不应随便绕过服务授权或修改 Linux 私有地址。

### E5：逐事件 catch 的框架层数和冷路径栈空间可缩减，但不是每次展开

**判断：冷路径外提可局部评估；把 catch 整体搬到 Task 生命周期需要入口模型改造。** K 的 `Thread::handle` 逐事件经过 `oops::catch_panics_as_oops → ostd::panic::catch_unwind → unwinding::panic::catch_unwind`。原生模式在循环外捕获。来源：`poc/kernel/core/src/thread/task.rs:110-165,340-359`；`thread/oops.rs:44-75`；`poc/ostd/src/panic.rs:190-200`。

旧 ELF `0x5378a9` 的 `sub $0x430,%rsp` 主要为 error 分支的 1 KiB stashed message 等临时空间预留；成功返回在 `0x5378bb..0x5378be` 跳到 `0x537937`，不格式化/复制该消息。可以把 message/report 单独外提为 cold、非内联 helper，观察新的正常路径是否减少 frame 和包装调用；这不改变捕获能力。栈预留不是同大小内存清零，也不是每次走一次 unwinder。

本地 unwinding crate 的 `panicking.rs:28-46` 正常路径使用 `core::intrinsics::catch_unwind` 调用闭包；`do_catch` 为冷路径。`unwinder/arch/x86_64.rs:94-129` 的 `save_context` 才涉及 FP control；它由 Raise/Resume/Backtrace 等 `with_context` 路径调用（`unwinder/mod.rs:155,261,347,374,392-396`），不能算成每次 getpid 的 FP 保存。快照已加入 `kernelet-no-fp-control` feature（`poc/ostd/Cargo.toml:79`、本地 crate `arch/x86_64.rs:7-36`），尚无对应新产物证据；它不能被直接记作已证明的 syscall 收益。

当前 host 每次按 `event_rsp` 重新进入，旧事件调用栈被放弃。要捕获到 Task 生命周期末尾，必须真正保留可恢复 continuation 和其引用/Drop 边界；把 catch 搬到已不存在的栈帧不成立。展开正确性、oops 资源释放与 host 报告仍是要求；panic=abort 属于语义变化。

### E6：CPU-local 的额外地址解析和代码段往返是具体机制成本

**判断：可批量合并访问，或改变 Host/vOSTD 的定位接口；不能裸缓存可迁移指针。** 每个 `record_asm` 先跳进受保护代码区，读取 BootArgs、读取 Linux GS slot、右移/截取 vCPU 编号、乘 record stride、计算 record 地址，再访问实际字段并跳回。CPU-local 还需从 record 取 replica base。来源：`poc/ostd/src/arch/x86/cpu/kernelet_local.rs:11-72`；原生 GS 单指令实现为 `arch/x86/cpu/local.rs`。

旧 ELF 的 `0x24804e..0x24807f` 是取得 `CURRENT_TASK_PTR` 的真实访问块，含上述解析和往返跳转；`0x248084..0x2480ae` 又重新算一次 record 地址以读 guards。普通返回又检查 preemption、IRQ mask，多次使用同一机制。这部分是 K 相对原生直接 GS 访问新增的工作，语义目标是避免中间被虚拟 upcall 打断后继续使用旧 vCPU 的地址。

方案是把同一不可迁移安全区间内的多个字段读写合并成一个保护块，或让 Host 发布直接 record/replica 定位，减少 slot 解码链；仍保留读写与 Task/vCPU 迁移的原子关系。只有 Host 物理抢占不会导致内部 Task 迁移，并不能证明后续虚拟 IRQ 后指针仍有效。不能把取得 record 的地址缓存跨越可能调度的 `handle`。保护块生成和 OSDK 审计必须一起更新。

### E7：无事件快路径已有短路，但入口/出口重复 gate 值得合并

**判断：保持职责并合并检查，需要列清可能插入事件的位置。** `enable_local` 已在 `pending==0 && !should_preempt()` 时返回，普通 getpid 不进入全部 `can_receive_virtual_interrupts` gate 和 pending 派发。它仍需要设置 irq mask、选择 record、读 pending、读 CPU-local PREEMPT_INFO；随后 `enter_user_mode` 另读 shared guards、调用 `might_preempt`，再经 IRQ guard 读取 mask 并关闭它。来源：`poc/ostd/src/arch/x86/irq/kernelet_ops.rs:12-46,63-73`；`poc/ostd/src/user.rs:289-300`；`task/scheduler/mod.rs:450-475`；`irq/guard.rs:53-59`。

可以构造内部带明确前置状态的“准备返回用户态”操作，将同一安全窗口内的共享 gate 与 IRQ 状态访问合并，避免通用 guard 对已知状态再查询。不能因 syscall 短就删除末尾 preempt/pending 检查：事件可在入口检查后到达，handler 自己也可唤醒任务。shared guard 断言可能在安全 API/注册状态加强后移动，但本轮没有可直接删去的证明。Host 返回握手的屏障由 Linux/Endovisor 报告另审。

### E8：CpuSync 的三次状态检查与已是 OnCpu 的重复写入可重排

**判断：检查职责必要，表示与冗余 store 可优化；这一核心实现也为原生模式共有。** `SuppUserContext::before_user_exec` 对 FPU、FS、GS 各调用一次状态机，只有 `InMemory` 恢复；每次无条件把 location 写成 OnCpu。来源：`poc/kernel/core/src/process/posix_thread/thread_local.rs:308-315`；`cpu_sync.rs:204-218`。

旧 ELF `0x449255..0x4492dd` 的正常 OnCpu 路径保留三个状态字节比较和三个 OnCpu store；实际 `FpuContext::load`、`wrfsbase`、`GsBase::load_inactive` 都在 InMemory 分支。可以合并 dirty 状态，使全 OnCpu 快路径整体短路，或消除已是 OnCpu 的自写；分别增加三次分支未必更快，须看机器码和数据。InMemory 与 Both 都要正确转成 OnCpu，首次进入、切换、信号、ptrace、`arch_prctl` 必须失效。`CpuSync::get/set` 上的 preempt guard 在普通 getpid 不会无条件执行，不能把它们的全部成本也计入这三次 hook。

### E9：退出、ptrace、信号的空路径可以集中，不能把功能去掉

**判断：可合并状态采样/派发；需要并发更新与状态结果契约。** `Thread::handle` 在 syscall 后读 `is_exited`，处理信号，再在 stop 循环条件读它；返回 OSTD 又经 `should_exit` 读它。用 handler 明确返回继续/退出结果，可能省去额外间接回调和重复身份查询，但必须保证信号、oops、调度后发生的状态变化不会遗漏。原生循环也有多次退出检查，不能把这些检查全部标成 K 独有。来源：`poc/kernel/core/src/thread/task.rs:147-179,261,314-335`；`thread/mod.rs:139-146`。

未跟踪时 `ptrace_may_stop_on_syscall` 查询 Once 并直接返回；无信号队列时在 dispositions 锁前返回。信号函数在检查队列前还处理 restart/saved mask，这些需要一起覆盖。来源：`poc/kernel/core/src/process/posix_thread/ptrace/mod.rs:106-116`；`process/signal/mod.rs:50-73,236-244`。可以用由所有生产者维护的统一 work/pending 标志，让无 work 的路径跳过独立 helper；tracer attach/detach、signal queue、restart、saved mask、stop/continue 的更新者与发布时序必须完整。carrier 的 Linux 检查作用于另一层任务，不能替代这里。

### E10：日志 runtime 关闭没有消除站点

**判断：能以明确构建配置去掉 Debug 站点，但这影响运行时诊断能力，且 Asterinas 两种模式共有。** OSTD 的 `STATIC_MAX_LEVEL` 固定为 Debug，runtime 默认 Off；源码已留 TODO 为编译期上限提供功能。`log_syscall_entry`、`sys_getpid` 都含日志站点。来源：`poc/ostd/src/log/logger.rs:151-164`；`log/macros.rs:82-87,110-121`；`poc/kernel/core/src/syscall/mod.rs:436-455`；`syscall/getpid.rs:25-26`。

旧 ELF 的 dispatcher 在 `0x4c1840` 读取 `DYNAMIC_MAX_LEVEL`，说明 runtime Off 仍需要读取和分支；它并不表示关闭日志时还会逐次格式化或走 Process/Thread Arc 查询。可提供 Debug 站点编译期剔除配置，OSTD 与第三方 log crate 一致处理；保留正常错误/故障可观测性，并在 A 与 K 同配置测量。不能只调整 runtime 日志等级后声称机器码已经精简。

## 4. 对“全部额外成本都可删除”的具体回答

| 类别 | 本次识别的项目 | 处理方向 |
|---|---|---|
| 无用的通用工作 | 零参数调用的六参数预取；热路径不需要 owned 快照却携带其分支；已知类型重复 Any 查询；OnCpu 自写 | 优先形成保持语义的局部变体；不是保证端到端必然更快 |
| 可以改变表示或位置的职责 | 单例回调、初始化状态检查、record 解析、重复返回 gate、Context 身份发现 | 强化创建/发布与失效契约，移出或合并热路径 |
| 需要更大设计变更 | Task 生命周期 catch、持久执行循环、直接 CPU-local 定位、统一 work 标志 | 先审所有权/栈与事件时序，再实现成组变体 |
| 不能直接删的语义 | 活跃 frame 所有权、抢占、信号/ptrace、退出、FPU/TLS 失效与恢复、oops 回收 | 保留语义，同时审查是否可用更便宜的协议实现 |
| 不能作为逐 syscall 成本计费 | 整帧复制（仅 Owned/切换等条件）；每次完整 unwind/FP control 保存；每次 FPU 硬件恢复；无信号时 dispositions 锁；Task::current 的 Arc clone | 修正归因，按真实条件计数，不据静态冷路径加总 |

优先讨论 E1 的按 arity 解包、E3 的 typed 用户 Task 关联、E4 的 H 专用入口，再将 E2/E5 与入口寿命设计一起比较。E6/E7 的地址解析和 gate 合并需要主代理与 Host 协议审查整合。E8/E10 可作为独立配置/局部优化，但不应全计为 K 机制成本。所有候选都要保留完整 syscall 功能；最小 stub 仅用于归因。

## 5. 需要的验证与未完成项

- 每项先比较冻结构建的实际 hot-path 指令是否减少，再以相同条件测完整 K 和原生对照；源码行数、静态 frame 大小不是耗时。
- E1/E2：0–6 参数、errno/NoReturn、fork/clone、exec、ptrace、信号、异常寄存器恢复与 Task frame 迁移。
- E3/E4/E5：初始化/注册、Task 切换及跨核恢复、exec/退出、panic/oops 展开与资源释放；保持安全内核无 unsafe、OSTD 内部封装 raw frame。
- E6/E7：入口与返回窗口的 tick/kick、抢占/迁移、guard、kill、嵌套 IRQ、服务返回与 OSDK CPU-access 审计。
- E8/E9：活跃 x87/SSE/AVX、FS/GS/TLS、`arch_prctl`、信号/ptrace 状态改变、跨 Task 和 carrier 抢占，及 pending 标志的并发更新。
- 本轮仅核对源码和旧 ELF；未验证当前清理后的树能够构建，未执行上述回归，也未测量任何候选收益。快照 manifest 由主代理维护；本报告没有恢复被删文件或生成临时源码。

## 6. 关键源码快照摘要

以下为本报告使用的快照 SHA-256；当前工作区若继续清理，以该摘要对应的读取范围为准。

| 来源 | SHA-256 |
|---|---|
| `poc/ostd/src/user.rs` | `eaef91331a95340eb10f01f71888fcf47de1f073e7c8df0109cbbacb9dba65de` |
| `poc/kernel/core/src/thread/task.rs` | `99135606ad5812f869832aa3360f36d07f2f7958594173e84335dc23d97a6f11` |
| `poc/ostd/src/arch/x86/cpu/context/mod.rs` | `23a9f9848200513965b3d68e324533476a4e232023d184282cc05f94dac415da` |
| `poc/ostd/src/arch/x86/cpu/kernelet_local.rs` | `ad28b6865997508b8605b9a9bfd28b828bc6946985411f6fd412128c8054165a` |
| `poc/ostd/src/task/processor.rs` | `19cb96bf4928c17cee1caaef15f5b75532d0f873fedf5f632c59139510fc7fec` |
| `poc/ostd/src/task/scheduler/mod.rs` | `bda161651558b2bc214f91182f66253d635e4a9a6dba09e972551818ca073b2c` |
| `poc/kernel/core/src/process/posix_thread/cpu_sync.rs` | `18bf1c9926f14e85effe4573d339625425fc1831955d617a4a8b4cdaefd32976` |
| `poc/kernel/core/src/syscall/mod.rs` | `69f8179478067df0855865bffa217f5a7b2013b729cb830900e71974e359368a` |
| `poc/kernel/core/src/process/posix_thread/thread_local.rs` | `c9d9e2cbc86cf5e1a794bccbdf438b0df3358c7a4baa9e5fb38c1ac9cdc04380` |
| `poc/ostd/src/arch/x86/irq/kernelet_ops.rs` | `cb01991f157b9c0f8d3c5acae6357b2ca7201ddfdd385a277228f857c5fd6236` |
| `poc/ostd/libs/unwinding/src/panicking.rs` | `95615fc63aacc0677103abaf29dc2f09e5e4f701aa04c6cfcccb26cd1de30d9d` |
| `poc/ostd/libs/unwinding/src/unwinder/arch/x86_64.rs` | `40f055325e96ddec0c8cb4a67a79fa50706b351891dccae4b154981c8f1e4543` |
| `poc/ostd/src/log/logger.rs` | `93a4a18caa4c37a69b54767c7a4072e60c4f742c60bef1e65f527e97f974d4f6` |

## 7. 结束时增量核对

- 读取截止：`2026-11-17T05:43:57.666095+00:00`。只比较主代理指定的 13 个文件与主审快照，逐文件读取前后 stat 一致；这不是整个工作区的原子快照，也不承诺随后没有变化。
- 本轮差异主要是删除未启用的 `kernelet_getpid_profile` / `kernelet_rq1_diagnostics` 代码、删除旧 Asterinas Host 构建分支/测试，以及重命名本地 unwinding feature。对于原本未启用这些 cfg 的 release Image，这些删除不能被记作消除了逐 syscall 探针成本。代码布局和产物可能随重建变化，尚无新构建对应或性能数据。
- E1–E10 没有一项被这组差异证明已消除；部分结论仅能表述为本次指定差异未触及其机制。原来的源码行号和 ELF 地址继续只针对主审快照/旧 ELF，不能平移为 live 新行号。

| 主审项 | 本次状态 | 差异核对 |
|---|---|---|
| E1：六参数预取 | 仍成立 | `syscall/mod.rs` 仅删除 profiling/diagnostic cfg 块，`SyscallArgument::new_from_context → syscall_args → dispatcher` 未改。 |
| E2：Owned/Frame 表示 | 仍成立 | `context/mod.rs` 清除探针和旧 Host cfg，未改变表示、寄存器访问选择或 Frame/Owned 同步。 |
| E3：类型查询与 Context | 仍成立 | ThreadLocal 只删除诊断 timeline；handle 的 Any 查询、process 借用与短期 Context 仍在。 |
| E4：回调与注册检查 | 本次差异未消除 | `Thread::pre_user_run` 仅删除诊断调用；本次指定的 13 文件差异没有改变主审所示回调协议。 |
| E5：catch/冷路径 | 仍成立，feature 名称更新 | oops 只删除旧 Host hook 的 panic 条件；逐事件 catch 与 1 KiB message 冷路径未改。本地 unwinding feature 从 `kernelet-no-fp-control` 改名为 `kernelet`，所选 save/restore 汇编内容未变。 |
| E6：CPU-local 解析 | 本次差异未消除 | 本次差异主要清理旧 Host 与诊断代码，没有替换主审所述保护块地址解析；未扩大到其余文件的新一轮审查。 |
| E7：IRQ/preempt gate | 本次差异未消除 | scheduler 删除旧 Host ktest 和诊断 cfg，未改 `should_preempt`/`might_preempt` 的热路径；Task accounting 在 `feature=kernelet` 下仍保留。 |
| E8：CpuSync OnCpu 自写 | 仍成立 | 所有被删语句均为诊断计数；状态比较、条件硬件恢复与无条件写 OnCpu 均保留。 |
| E9：退出/ptrace/信号 | 仍成立 | task.rs 删除 timeline/profile 块，未改正常 handler 的退出检查和 ptrace/信号调用。 |
| E10：Debug 站点 | 仍成立 | `getpid.rs` 删除探针但保留 `debug!("pid = {}", pid)`；分派宏的日志站点未改变。 |

删除旧 `kernelet-host` 的 carrier context/worker 身份字段，不等于 Linux-hosted Image 的 Task 关联查找已改为 typed 接口；这些分支在本轮 Image 的 `feature=kernelet` 配置下原本就不执行。`task/processor.rs` 仍在 Kernelet 逻辑切换处进行 accounting sample/resume，不能声称已移除这项运行工作。对 unwinding 的改名也不新增“每次 catch 不保存 FP”的性能结论：主审已区分正常 catch 与真正展开路径。

本次 live 读取的 SHA-256 如下；对应快照摘要保留在第 6 节及公共 manifest。未运行构建、回归、剖析或性能测量。

| 来源 | Live SHA-256 |
|---|---|
| `poc/kernel/core/src/process/posix_thread/cpu_sync.rs` | `b4e454d6da8e43bbe6ceefeb822016dd616d57e072eb594f6544bb7d7a28a4a4` |
| `poc/kernel/core/src/process/posix_thread/thread_local.rs` | `f084add5eba7f182bb5bf72f42c01901dec721bffc3aff9a97612890b210e64c` |
| `poc/kernel/core/src/syscall/getpid.rs` | `ff74de95dd1e6675e47a4dc2d6dd4cc212c09dc62135717b3698da35541246f2` |
| `poc/kernel/core/src/syscall/mod.rs` | `99a459881e0d685370fb4d5428ddd78bdf682f689a65472ffd99a2b09ae708a9` |
| `poc/kernel/core/src/thread/oops.rs` | `05d3beef43ce93a23d6228017cc2a13a5c991c1c50de53ccdeb21085186df182` |
| `poc/kernel/core/src/thread/task.rs` | `c7ce8a3b3b446de5e89b07f365cf17694e6d18f1a34803d6fe84c86b458a4fa4` |
| `poc/ostd/src/arch/x86/cpu/context/mod.rs` | `589cc0c93282141621577e46b44c55e4af56d7f2bd4efb43474f22564e19b3f3` |
| `poc/ostd/src/task/mod.rs` | `e63e926ca528adad3219a50071e38b6dc4d7edd3aa6f61d93c733a00ad0d41bd` |
| `poc/ostd/src/task/processor.rs` | `108ca3ea6fa47ca0d65197769f42fce3dcb4fe97773310e406847f55b8139c5d` |
| `poc/ostd/src/task/scheduler/mod.rs` | `fce488ff3d85b8878b680ea20f04edf09c16d78d613444f9cea307fd78a8d5d6` |
| `poc/ostd/Cargo.toml` | `267368e9e474984ac64d06ef377f6487db009b8fa72f8f4e6b76be1daf4af9ac` |
| `poc/ostd/libs/unwinding/Cargo.toml` | `03d3a18abc20c3176c8ee19ba7649ca2255868dba42720ac975b0e24a4e082b1` |
| `poc/ostd/libs/unwinding/src/unwinder/arch/x86_64.rs` | `757168b3f3d41d1b793418c6c186339fd4ff48e5d10ff9424eb92687115dbf72` |

