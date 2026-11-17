# Direct attach 的旧用户空间注册状态

本次修复只修改 `poc/linux/endovisor/main.c`，并在 Linux cold path 增加 `kernelet_attach_mm`（`include/linux/kernelet.h`、`kernel/fork.c` 与对应 root patch）。没有修改 `carrier.c`、runner、bench 或 Rust，也没有关闭 rseq。

## 故障机制与证据范围

父代理的真实 QEMU 诊断表明：同一 payload 经 exec 启动通过，经 `--attach-ioctl` 在用户入口 `ip=0x4037c0` 收到重复 `SIGSEGV, si_code=SI_KERNEL`；没有相应硬件非 PF exception hook，`thread.trap_nr` 仍为 0，因而又被错误转译为 SIGFPE。

源码确认 direct attach 缺失了退出原 Linux 用户空间的协议：原实现只调用 `kernelet_switch_mm`，未释放 task 中仍指向旧用户空间的注册。当前 `CONFIG_RSEQ=y`；普通 fork 会继承父任务的 rseq 指针及注册字段（`include/linux/rseq.h::rseq_fork:68`）。Linux 原生 exec 在成功后调用 `rseq_execve` 清除这些字段（`fs/exec.c::bprm_execve:1853`）；原 attach 没有这一步。

Linux `resume_user_mode_work` 会调用 `rseq_handle_notify_resume`（`include/linux/resume_user_mode.h:62`）。`kernel/rseq.c::__rseq_handle_notify_resume:315` 读取或更新旧 rseq 地址失败时，经 `force_sigsegv` 产生 SIGSEGV；`kernel/signal.c::force_sig:1666` 设置 SI_KERNEL，却不写 `thread.trap_nr`。这条路径直接解释了诊断结果。若旧地址恰好在 tenant 中有效，还可能形成错误写入，不能只处理生成的信号。

本记录没有独立采集 rseq 函数的动态 trace；明确证实的是缺失的注册清理及其匹配故障机制。父代理已报告：新 helper 的真实 QEMU attach syscall、FPU、SMP、fork 和 rt_sigreturn 回归通过。最终 release/debug 矩阵及对应 module hash 由父代理的最终 manifest 记录，本代理没有独立运行这些回归。

## 使用原生清理流程

新增 `kernel/fork.c::kernelet_attach_mm:1734` 是一次性提交 helper，不进入普通 syscall 或反复 `pt_activate` 的路径。

| 原注册或状态 | 复用的 Linux 流程与理由 |
|---|---|
| rseq | `rseq_execve` 清除指针、长度、签名和事件 mask；不是只改一个指针。来源：`include/linux/rseq.h:83`。 |
| native/compat robust list、PI futex | `exec_mm_release → futex_exec_release` 在旧 mm 仍有效时处理 robust futex、清除两种 list 并释放 PI 状态，最后恢复 `FUTEX_STATE_OK`。不以 `futex_exit_release` 把仍将运行的 task 标成 DEAD。来源：`kernel/futex/core.c:1041,1124`。 |
| clear_child_tid、vfork completion、uprobe、arch cached state | 原生 `mm_release` 在旧地址空间中完成必要的清零/wake，清除 `clear_child_tid`、释放 uprobe task state、执行 `deactivate_mm` 并完成 vfork 通知。来源：`kernel/fork.c:1686,1725`。 |
| io_uring | `io_uring_task_cancel`，对应 `begin_new_exec:1255`。当前配置未启用 IO_URING，但使用原生配置相关接口。 |
| POSIX timer 注册 | 按 `begin_new_exec:1290` 的顺序执行 `posix_cpu_timers_exit`、`exit_itimers`、`flush_itimer_signals`。不自行删除 exec 本来保留的其他 Host task 属性。 |
| user-events 的旧 mm 注册 | `user_events_execve` 移除 task 关联，并通过其原生同步流程结束旧 mm 的 enable 写入。来源：`include/linux/user_events.h:54`、`kernel/trace/trace_events_user.c::user_event_mm_remove:787`。 |
| signal altstack | `sas_ss_reset` 清除地址、大小并设置 `SS_DISABLE`。来源：`include/linux/sched/signal.h:609`。 |
| syscall-user-dispatch 的旧用户 selector | 与原生 exec 相同，清除其 syscall work，使 Linux 不再读取旧 selector。来源：`fs/exec.c:1310`。 |
| TLS、ptrace hardware breakpoint、FPU、PKRU | `flush_thread` 复用 x86 exec 的体系结构清理；切换后 main 调用原生 `start_thread(...,0,0)`，初始化新的 64-bit frame 和线程特性。来源：`arch/x86/kernel/process.c:272`、`process_64.c:530`。 |
| 旧 mm 仍被其他 Linux task 共享 | 切换后调用 `mm_update_next_owner(old_mm)`，对应 `exec_mmap:1013`，避免 owner 仍错误指向已经离开这个 mm 的 carrier。 |

`set_child_tid` 只在 native `ret_from_fork` 中首次写一次（`kernel/sched/core.c:5262`），原生 exec 也不重新清除它；它不构成 attach 之后的延迟访问，本次未发明额外字段清零。清理后仍可能有 Linux 通知标志，不能一并抹掉：例如其中可能包含 task work；rseq 注册为空后，原生 rseq resume 检查会正确跳过它。

direct attach 仍保留其已有 task/fd/credentials 接口；这个 helper 没有伪装成一次完整的 ELF exec。它复用离开旧用户空间所需的原生注册与体系结构清理，调用者仍必须满足当前的独占 files/sighand、单线程以及有效旧/new mm 前提。

## 提交点与失败路径

`main.c::attach_vcpu:584` 先完成 mm、carrier、boot stack 和 lifeline fd 的所有可失败准备；在 `c->own_mm` 引用已经建立后，才调用 `kernelet_attach_mm`。该 helper 消耗新 mm 的任务引用，返回旧 mm 的引用给调用者 `mmput`。所有清理旧用户注册的工作都发生在切换之前，旧 mm 仍可以被原生 futex/uprobe 等代码正确访问。

因此共享 files/sighand、无效参数、ENOMEM 和 EMFILE 等早期失败不调用 helper，不损坏调用者仍使用的 rseq、robust list 或 altstack。lifeline 安装失败仍由创建者清理一次 carrier。helper 本身无 errno 返回；提交之后的 `carrier_mark_arrived` 失败沿用 stop + fatal signal，不能返回原程序继续使用已经释放的注册。mutex、最后 carrier 的 cleanup claim 和 `on_exit` 协议保持不变。

## SI_KERNEL 不是 trap 编号的证明

以下 Linux 来源会生成 fault signal，但不提供一个新的、可直接从 `thread.trap_nr` 取得的 tenant trap。除当前 rseq 机制外，其余是源码上的可能来源，不表示本轮 QEMU 都启用了或触发了它们。

| 来源 | 源码位置 |
|---|---|
| rseq resume 读写失败 | `kernel/rseq.c:328–339`。 |
| Host signal frame 建立失败或 native sigreturn 校验失败 | `kernel/signal.c::signal_setup_done:2961`、`arch/x86/kernel/signal.c::signal_fault:368`。 |
| task 申请 L1D flush 后，运行于不满足 SMT 条件的 CPU | `arch/x86/mm/tlb.c::l1d_flush_force_sigbus:337` 的 task work。 |
| uretprobe/XOL 模拟或返回地址修复失败 | `kernel/events/uprobes.c:2244,2362`、`arch/x86/kernel/uprobes.c:1197`。 |
| MCE 或 SGX 内存错误的恢复通知 | `arch/x86/kernel/cpu/mce/core.c::kill_me_now:1347`、`cpu/sgx/main.c:699`；不是当前 tenant 普通 fault 的寄存器记录。 |
| Linux XFD feature 启用失败 | `arch/x86/kernel/traps.c:1357`。它虽有 `#NM` 背景，但这里的 SIGSEGV 并不建立一个新的 tenant trap 记录。 |

真实 user `#GP` 也会使用 SI_KERNEL，但会先写 trap/error，并被现有 `on_exception` 接管（`traps.c::gp_user_force_sig_segv:708`）。所以不能把 SI_KERNEL 一概解释成某个 trap，也不能反过来断言它绝不与硬件异常相关。

当前 ABI 没有 HostSignal 事件，书中也没有把上述 Host 失败转译成任意 CPU exception 的约定。最终实现由父代理在 `carrier.c::drain_signals:489` 区分 SI_KERNEL fault：调用独立 cold 函数 `stop_on_host_signal:479` 停止 sandbox，并保留 signum/code，不再把旧 `thread.trap_nr=0` 当作 `#DE`。非 SI_KERNEL 的标准 fault 仍保留既有路径，用于 VMA 错误交付；immutable/fatal/seccomp 继续走 Linux 原生处理。`drain_signals` 直接复用 `exc_pending`，不再维护重复的异常局部状态或无调用者使用的返回值。该文件及最终 module hash 由父代理统一负责。

## 实际构建和 patch 检查

- 实际重建 Linux `bzImage`，生成 `#7`，成功；随后执行原生 `make modules` 更新 `Module.symvers`，再成功构建 `endovisor.ko`。新导出由标准内核构建生成，未手工修改符号表。
- 对独立原始基线副本执行 `git apply --check --whitespace=error`，通过；应用后 18 份源码与实际 Linux 构建树逐字节一致。实际构建树的 reverse verbose check 也通过，没有 offset/fuzz。
- 原 `prototype/linux/endovisor/carrier.c:1279` 使用指定字段初始化 `.on_syscall/.on_resume`。新增可选 `on_exit` 不改变其成员初始化含义，默认 NULL；这只说明初始化兼容，不宣称这份书中参考实现已经采用当前 PoC 的完整退出协议。
- 本代理没有执行新的 QEMU 回归或主机模块加载；上述已报告的 attach 回归由父代理完成，最终矩阵与早期失败回滚验证仍由其统一记录。编译有 `kernelet_do_return_to_user` 缺少 prototype 的 warning，无新错误。

| 本次 helper 的实际内核构建产物 | SHA256 |
|---|---|
| `prototype/.build/linux-6.12/arch/x86/boot/bzImage` | `114963b3e3bda3901938272763ec9ec8e8640ad7143865350b5fd310d8fa93df` |
| `prototype/.build/linux-6.12/vmlinux` | `1dab52fd4c7dfbb5cc3a24af9ebcaaf6a1269b1da015aec43e9c481ab511c5c5` |
| `prototype/linux/patches/0001-carrier-hooks.patch` | `725629b0f75995637fc341c6914cd79a0be8ffe9f3b6ef6e411159ba8b74347c` |

| 本次修改源码 | SHA256 |
|---|---|
| `poc/linux/endovisor/main.c` | `05c824c844bb7d123baedd31e290b6c626616f9bf2c3c9967911a1437732b765` |
| `prototype/.build/linux-6.12/include/linux/kernelet.h` | `b4c0cfe215ff785dd385cdb028aa785661ce81b985b684f88d4341389ab632ba` |
| `prototype/.build/linux-6.12/kernel/fork.c` | `75e4947c6021d46e8cdd45161c691973ec63b28ce226eb62907ff7dca16aa66b` |

独占 `.syscall-overhead-work/attach-registration-patch` 完成检查后删除；共用 `TMPDIR=.syscall-overhead-work/tmp` 保留。随后源码和此报告交回父代理，新的 release/debug 构建须分别记录其产物 hash。
