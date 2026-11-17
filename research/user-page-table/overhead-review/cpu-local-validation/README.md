# CPU-local 地址复用：实现与验证

验证日期：2026-11-16（本地）；UTC 时间与输入身份见 [manifest.json](manifest.json)。

本项实现 D6，范围是禁止 Task 切换期间的 CPU-local 地址复用，以及 IRQ mask 操作中的重复定位。设计沿用 [PR #3](https://github.com/tatetian/kernelet/pull/3) 的 vCPU 绑定和虚拟 IRQ 约束。

## 地址与保护区间

[`CpuLocalAccess<'irq>`](../../../../poc/ostd/src/arch/x86/cpu/kernelet_local.rs) 借用 `DisabledLocalIrqGuard`，一次取得当前 `VcpuRecord` 与私有 CPU-local 基址。其生命周期受 guard 限制，类型不能跨线程传递；调用者通过标量 `load`、`store` 访问已有的 `CpuLocalCell`。方法要求 `Copy` 和相应的单指令访问 trait，读取及写入使用 volatile 操作。

记录地址与私有基址由 Host 在实例初始化时建立并保持映射。关闭虚拟 IRQ 阻止内部 Task 切换；Linux 对 carrier 的物理 CPU 调度保持其 vCPU 身份。地址复用限定在 guard 生存期内。`pending`、`guards` 和 `PREEMPT_INFO` 等可变字段按各操作需要读取。

## 使用位置

- 普通用户事件入口根据 Host 已关闭虚拟 IRQ 的契约建立 guard，共同取得事件记录和当前 Task。
- 首次任务进入在 `after_switching_to` 后使用实际的 IRQ guard，再共同捕获当前 Task 与 `pt_regs` 地址。该 guard 在调用 `init` 前结束。
- 抢占 guard 的建立和释放在一个 IRQ 保护区间内更新私有 `PREEMPT_INFO` 与共享 `guards`，共同使用一组地址。私有计数字段保持 CPU-local 标量接口的显式 wrapping 算术；有效计数位于其低位字段，独立标志保留在高位。
- `disable_local_save` 在同一受保护片段内读取原 mask，并在需要时关闭虚拟 IRQ，保持嵌套 guard 的恢复语义。
- `enable_local` 在一次受保护定位内开启虚拟 IRQ 并读取 pending；后续抢占判定、调度后的 pending 查询与事件处理继续在各自位置执行。

共享 mask 的发布与 pending 的读取保持原有 Release/Acquire 要求，使用具有编译器内存约束的 x86 标量汇编。受保护代码区和 Host 重定向规则继续生效。

## 机器码观察

下表对应默认 Release 配置，统计指定操作的 vCPU 定位次数，包括其调用的定位函数；次数限定在所列操作和条件内。

| 操作 | D5 对照 ELF | 本次 ELF |
|---|---:|---:|
| 普通事件入口捕获事件记录与当前 Task | 2 | 1 |
| 开启虚拟 IRQ 并读取初始 pending | 2 | 1 |
| 原 mask 为开启状态时，保存状态并关闭 IRQ | 2 | 1 |
| IRQ 已关闭后，更新私有与共享抢占计数 | 2 | 1 |

已关闭 IRQ 的嵌套 guard 仍执行一次 mask 定位。首次任务进入使用实际的 IRQ guard，其获取和恢复属于该入口的处理。

[对照反汇编](assembly-baseline/)与[候选反汇编](assembly-candidate/)保留了函数体和相应受保护片段；[结构数据](assembly.json)同时记录静态访问位置、调用与函数大小。`user_event_entry` 的函数体为 930 → 1025 字节，`enable_local` 为 249 → 239 字节，抢占 guard 的 `Drop` 为 106 → 123 字节；这些大小不包含被跳入的受保护片段。定位次数减少和内联后的函数大小分别报告。

## 构建与运行验证

| 检查 | 结果 |
|---|---|
| 原生 OSTD | `cargo check -p ostd --no-default-features --target x86_64-unknown-none --locked` 完成；[日志](native-ostd-check.log) |
| Kernelet Clippy | `cargo clippy -p ostd --no-default-features --features kernelet --target x86_64-unknown-none --locked` 完成，告警保留在[日志](ostd-clippy.log) |
| Release 镜像 | 编译、链接、unsafe、浮点及 ABI 审计通过；[日志](image-build-release.log) |
| 启用调试断言的 Release 镜像 | 使用 `--config profile.release.debug-assertions=true`，同样通过镜像审计；[日志](image-build-debug-assertions.log) |
| Release syscall 回归 | SMP、fork、寄存器、睡眠恢复、SSE/AVX、任务切换及合法/非法 `rt_sigreturn` 均通过；[日志](qemu-syscall.log) |
| Release 内存安全回归 | 异常、页访问权限、双 vCPU 页表操作与内核 EFAULT 回归通过；[日志](qemu-safety.log) |
| Release 终止回归 | 100 ms 终止请求得到 `exit_kind=killed exit_code=9`，模块正常卸载；[日志](qemu-kill.log) |
| 调试断言运行回归 | syscall、SMP、FPU 和 `rt_sigreturn` 套件通过；[日志](qemu-debug-assertions.log) |

运行验证使用实际的 Kernelet ELF、Endovisor 模块、Linux 6.12 和 QEMU/KVM，配置为 `-cpu host -smp 2 -m 1024M`、Direct 页表模式、256 MiB grant 和 `mitigations=off`。QEMU 子进程的 `RLIMIT_MEMLOCK` 软限额为 0。

本轮编译和运行验证在主机环境执行，使用项目固定工具链。当前账号无法访问 Docker，非交互 sudo 需要密码；尚未完成 [poc/AGENTS.md](../../../../poc/AGENTS.md) 规定的容器内验证。

## 结果身份与验证边界

保留的 [Release ELF](kernelet-image.elf) 的 SHA-256 为 `cafde2788ce0857f688340b8c02bf919d48e20d44c93c257dbe5560198b14890`。[启用调试断言的 ELF](kernelet-image-debug-assertions.elf) 的 SHA-256 为 `eb5eff1d318755bd60cd70180d9300734f97e76a9c8ec4c542d0bbb7130ab05f`。两次 OSDK 冻结输入及最终工作区的源码 SHA-256 分别保存在 manifest。相关的 11 个文件经项目固定 rustfmt 规范化后的内容一致。

本轮确认了定位操作减少和上述运行行为。日志中的耗时属于功能回归，尚未完成独立的延迟配对实验。ptrace、oops、原生 Asterinas 启动、其他处理器架构和真实硬件运行未在本轮单独验证。

本目录保留实现验证所用的 ELF、输入身份、反汇编和日志，直到该项被新的验证记录替换。
