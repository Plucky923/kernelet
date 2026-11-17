# 固定用户事件入口：实现与验证

验证时间：2026-11-16（本地），2026-11-17 06:36 UTC。

本项采用 [PR #3](https://github.com/tatetian/kernelet/pull/3) 的固定符号方案，提案版本为 `Plucky923/kernelet@ee1b2267e6178c6afaf22d73ad961f0c227ec8db`。范围是用户事件回调的链接与分派。

## 实现

[`#[ostd::user_event_handler]`](../../../../poc/ostd/libs/ostd-macros/src/user_event.rs) 为具体的 `UserEventHandler` 实现生成六个 Rust ABI 符号：`__ostd_user_data_type_id`、`__ostd_user_init`、`__ostd_user_handle`、`__ostd_user_should_exit`、`__ostd_user_has_kernel_event` 和 `__ostd_user_pre_user_run`。

[Asterinas 的 `Thread` 实现](../../../../poc/kernel/core/src/thread/task.rs) 使用该属性。[OSTD 事件入口](../../../../poc/ostd/src/user.rs) 直接调用固定符号；首次进入调用 `init`，普通事件按既定顺序执行 handler、退出判定、抢占检查和 `pre_user_run`。读取当前 Task 与事件记录期间保持虚拟中断关闭，`pre_user_run` 也在关闭虚拟中断后执行。

Task 创建时比较最终 task data 的类型与导出的 `TypeId::of::<Arc<H>>()`。Task 生命周期内保留该 data，安全接口不能替换它；OSTD 生成的入口据此借用具体 handler。Asterinas 保持 `#![deny(unsafe_code)]`。运行时注册接口、`UserEventOps` 和 `Once<UserEventOps>` 已删除。

编译接口使用 `HasVmReaderWriter::writer(&segment)` 访问 `Segment`；原生 x86 IRQ 模块在原生配置下导入 `cpu` 与 `kernel`。

## 验证结果

| 检查 | 结果与范围 |
|---|---|
| 宏 Clippy | `cargo clippy -p ostd-macros --all-targets --locked -- -D warnings` 通过 |
| 原生 OSTD 编译 | `cargo check -p ostd --no-default-features --target x86_64-unknown-none --locked` 通过；[日志](native-ostd-check.log) |
| Kernelet 镜像 | `cargo-osdk osdk build --kernelet --release` 通过编译、链接和 OSDK 的 unsafe、浮点与 ABI 审计；[日志](image-build.log) |
| 机器码 | `user_event_entry` 中 `handle`、`should_exit`、`pre_user_run` 均为直接调用；该函数唯一的间接调用对应 `ServiceTable::user_run`；[反汇编](user_event_entry.asm) |
| QEMU/KVM | 双 vCPU 的 SMP、fork、syscall 寄存器、睡眠恢复、SSE/AVX、A↔B 调度与合法/非法 `rt_sigreturn` 验证通过；`suite_done=1`，`RUN_POC exit_code=0`，模块正常卸载；[日志](qemu-syscall.log) |

真实系统验证使用 QEMU 11.1.3、KVM、`-cpu host -smp 2 -m 1024M`、已打补丁的 Linux 6.12、Direct 页表模式和 256 MiB grant。Linux 启动参数包含 `mitigations=off`。QEMU 子进程的 `RLIMIT_MEMLOCK` 软限额为 0。具体命令、输入 SHA-256、源码 SHA-256、OSDK 输入快照编号及全部 `RESULT` 字段保存在 [manifest.json](manifest.json)。

保留的 [Kernelet ELF](kernelet-image.elf) 的 SHA-256 为 `17c004a17bfa9dc0da04b46cc79e3a1e309db78d1de4bf5d64b2fa36b3728ab5`。编译器优化后，部分生成入口已内联或合并为具体 trait 方法调用；源码仍生成完整的六个绑定。

## 验证边界与保留期限

本轮验证了真实镜像的事件分派和现有 syscall 套件；原生 OSTD 完成目标编译。ptrace、oops、原生 Asterinas 启动及真实硬件运行仍未单独验证。日志中的时间数值属于功能回归，延迟收益需要同一输入版本的旧版/新版配对测量。

本目录保留该项实现的 ELF、输入身份、反汇编和验证日志，直到该项被新的验证记录替换。其他优化项按[讨论决定](../decisions.md)分别处理。
