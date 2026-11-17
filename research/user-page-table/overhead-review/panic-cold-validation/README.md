# Panic 捕获：正常路径优化与验证

本项实现 D7，对应 S9 / E5 / O2。范围是消除用户事件正常路径中的捕获包装调用，以及错误报告带来的临时空间预留。异常保护范围、Rust 展开与进程清理继续生效。验证时间、输入身份和命令见 [manifest.json](manifest.json) 与各项 QEMU JSON 记录。

## Linux 参考与实现

对照本实验使用的 Linux 6.12：[`page_fault_oops`](../../../../prototype/.build/linux-6.12/arch/x86/mm/fault.c) 使用 `noinline`，[`panic`](../../../../prototype/.build/linux-6.12/include/linux/panic.h) 的声明使用 `__cold`。错误报告保留在独立函数中，普通执行路径无需为报告函数预留局部空间。这些 C 错误处理函数用于参考代码组织；Rust 展开负责的 `Drop` 和借用释放由现有 unwinding 实现继续执行。

- [`ostd::panic::catch_unwind`](../../../../poc/ostd/src/panic.rs) 内联正常路径，独立的 `report_caught_panic` 使用 `#[cold]` 与 `#[inline(never)]`，仅在捕获到 panic 后读取保留消息并报告 Host。
- [`catch_panics_as_oops`](../../../../poc/kernel/core/src/thread/oops.rs) 在 Kernelet 配置下内联；payload 类型检查、Host 报告、日志和 oops 计数由独立的冷函数 `handle_oops` 完成。
- 本地 [`unwinding::panic`](../../../../poc/ostd/libs/unwinding/src/panic.rs) 与 [`unwinding::panicking`](../../../../poc/ostd/libs/unwinding/src/panicking.rs) 的泛型捕获函数在 Kernelet 配置下内联。异常类型、展开算法和清理行为保留，变更范围记录在该依赖的适配说明中。
- [`exit_current_after_oops`](../../../../poc/kernel/core/src/thread/task.rs) 保持独立冷函数，继续执行 POSIX 退出和 Process 引用释放。

Host 仍按固定 `event_rsp` 进入每个事件，handler 返回后再交接用户态。编译器为当前调用生成的异常信息仍有效；本项没有引入跨事件悬挂的调用，也没有逐事件注册异常环境。

## 机器码结果

对照镜像从修改前的当前源码重新构建，候选镜像使用相同构建命令和 Release 配置。两份源码由 OSDK 分别冻结；对应 ID 和源码摘要见 manifest。

| 检查项 | 对照 Release | 候选 Release |
|---|---|---|
| 事件处理中的三层具名捕获包装调用 | 保留 | 消除；事件入口直接调用 `Thread::handle` |
| 正常路径上 OSTD 报告包装预留的局部空间 | 3096 字节 | 该包装消除；3096 字节仅由冷报告函数预留 |
| 实际事件处理函数自身的局部空间 | 位于多层包装内 | 168 字节，包含事件处理和异常清理所需的局部值 |
| `.eh_frame_hdr`、`.eh_frame`、`.gcc_except_table` | 保留 | 保留 |

启用调试断言的 Release 也未保留三层具名捕获包装。`do_catch`、panic payload 处理及错误报告函数仍用于异常分支。[反汇编与结构数据](assembly.json)记录各函数的地址、大小、调用和首次 call 前的显式空间预留；原始反汇编保存在对应的 `assembly-*` 目录。

表中的空间预留是机器指令调整 RSP 的数值，不表示逐次清零或复制该大小的内存，也不表示整条 syscall 路径的全部内存使用量。

## 构建与真实运行验证

| 检查 | 结果与证据 |
|---|---|
| 修改前 Release | 构建与镜像审计通过；[日志](image-build-baseline.log) |
| 候选 Release | 构建及 unsafe、浮点、ABI 审计通过；[日志](image-build-release.log) |
| 启用调试断言的候选 Release | 构建与同一组镜像审计通过；[日志](image-build-debug-assertions.log) |
| 原生 OSTD 目标检查 | `cargo check -p ostd --no-default-features --target x86_64-unknown-none --locked` 完成；[日志](native-ostd-check.log) |
| Kernelet 内核 Clippy | `cargo clippy -p aster-core --no-default-features --features kernelet --target x86_64-unknown-none --locked` 完成，已有告警保留；[日志](kernelet-clippy.log) |
| Release 与调试断言 syscall 回归 | SMP、fork、GPR、睡眠恢复、SSE/AVX、任务切换和合法/非法 `rt_sigreturn` 通过；[Release](qemu-release-syscall.log)、[调试断言](qemu-debug-syscall.log) |
| Release 内存安全回归 | 异常、访问权限、双 vCPU 页表操作及内核 EFAULT 通过；[日志](qemu-release-safety.log) |
| Release 终止回归 | 100 ms 终止请求得到 `exit_kind=killed exit_code=9`，模块正常卸载；[日志](qemu-release-kill.log) |
| 修改前、候选和调试断言的真实 panic | 两次 panic 均使相应子进程按 SIGKILL 退出，文件锁释放，父进程继续 syscall 并成功创建新进程；[对照](qemu-baseline-oops.log)、[Release](qemu-release-oops.log)、[调试断言](qemu-debug-oops.log) |

panic 回归的[输入源码](oops-regression-input.c)直接调用当前内核的 `timer_create`，使用 `SIGEV_THREAD` 触发现有 `unimplemented!()`。子进程在该调用前持有文件锁和匿名内存映射；父进程通过 `waitpid` 检查终止状态，再重新取得文件锁，执行 10000 次 `getpid` 并创建正常退出的子进程。本项没有给生产代码增加故障注入入口。该检查依赖当前未实现的通知方式，仅作为本次真实展开验证输入。

运行使用新编译的 Endovisor 模块、runner 和 C 程序，在 Linux 6.12 与 QEMU/KVM 中执行，配置为 `-cpu host -smp 2 -m 1024M`、Direct 页表、256 MiB grant 和 `mitigations=off`。QEMU 子进程的 memlock 软限额为 0。

## 验证边界与保留目的

本次确认了包装调用消除、正常路径报告空间移除，以及上述功能与 panic 恢复行为。功能回归日志中的计时字段不作为独立的延迟收益结果。原生 Asterinas 启动、ptrace、启动期 panic、展开期间再次 panic 和 oops 数量上限未在本次单独运行验证。

编译使用本机的项目固定工具链；当前账号仍无法访问 Docker，容器内验证未完成。

本目录保留三个 ELF、输入身份、panic 回归输入、构建日志、反汇编和实际运行记录，供复核本项实现，直到被新的验证记录替换。项目内的专用临时构建目录在验证完成后删除。
