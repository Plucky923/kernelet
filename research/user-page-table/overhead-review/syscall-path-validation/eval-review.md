# eval 实现审查与真实协议验证

本报告覆盖 `poc/eval/` 的 Python 驱动、guest C 程序、shell/Nix 构建及依赖。现行实现包含 `non_sysret`、copy-files、verify-exec、skip、artifact 归档及声明式 case 清单。

**本次被测 K ELF 是现有打包文件，不是主代理最终的 release/debug 镜像。** 本轮没有从最终 Rust 源码重建该 ELF，下面的运行只验证实际工具链、输入身份和结果协议，不能用来证明最终 Kernelet 的性能。

## 当前实现

- 统计类型统一为 `SandboxStats`。缺失的 `non_sysret` 保留为未知；启用对应限制时拒绝缺失观测，不能将它当作零。
- 每个选定 case 必须恰好有一条结果，K/K_vma 必须有对应 stats。未知 case/group、空或重复 target、孤立或重复 stats、缺少必需字段均不能静默通过。页表模式、vCPU 数量和 grant 大小按实际请求校验。
- Native 每次启动按当次单一 case 校验，L/K 按完整 runnable 清单校验。显式 skip 不产生测量值。
- host overlay 携带本次指定的 payload。基础 initrd 中实际嵌入的 payload、模块、runner 和 ELF 由 GNU gzip/cpio 读取并计算 hash；当前实现不手写 newc 解析器。
- native payload 使用真实 hwloc/libtirpc，不保留 hwloc shim 或将 RPC 接口指向 `abort` 的替代实现。依赖源码的版本与 SHA 固定在 `configs/payload-sources.json`，will-it-scale 固定为 commit `75f66e45697e6f5f49c33dd950c4e6b289198f8f`。hwloc 使用官方 `--disable-libudev` 选项保留 CPU topology 能力，构建指纹包含源码、编译器身份和配置选项。
- 收尾 C 检查修复了 `waitpid` / `wait4` 非 EINTR 错误可能被初始 `status=0` 当作成功的问题。时间读取失败会明确退出；poll/read、输出超限或内存分配失败会终止采集、关闭 pipe、终止并等待 child，且不发布成功记录。procfs 路径缓冲区按实际界限分配。这些最终 C helper 已真实编译，但本次 VM 仍使用先前打包的 helper，身份差异单独记录。

## 已执行的检查

| 检查 | 实际结果 |
| --- | --- |
| 现有 `python3 -m unittest discover -s host/tests -v` | 26 项全部通过，见 [unit-check.log](eval-protocol-smoke/unit-check.log) |
| 三个 guest C helper，`gcc -O2 -Wall -Wextra -Werror -static -pthread` | 全部成功编译为 static x86-64 ELF |
| `bash -n poc/eval/scripts/*.sh` | 通过 |
| 16 个现行 host/test Python 文件的 AST 语法检查 | 通过 |
| `JOBS=4 bash poc/eval/scripts/build_payload_deps.sh` | 实际 exit 0，见 [dependency-build.log](eval-protocol-smoke/dependency-build.log) |
| 三份依赖源码 archive 与 pins 比较 | 全部匹配，见 [inputs.json](eval-protocol-smoke/inputs.json) |
| 外部 payload 与真实 initrd 内嵌 payload 比较 | SHA 一致，为 `7497ce18273f2a2b1fb336acc856d64a24c35ee1ed7ffa0e3a9a580fb2c7f99a` |

static benchmark ELF 中存在真实 hwloc 和 RPC 符号，RPC 函数地址与 `abort` 不同。这里验证的是构建、链接及观察到的运行路径，没有验证所有 hwloc/RPC 功能。环境未安装 Nix，因此没有声称 Nix 配方构建通过。

## 真实 QEMU 结果

首次 CLI 启动在 QMP 就绪前因宿主 QEMU `io_uring` 初始化失败而退出，没有产生 guest case。随后在一次性验证 wrapper 中将该进程及其 CLI/QEMU 子进程的 memlock soft limit 设为 0，hard limit 保持 8388608 bytes。相应 run 的 `resource-limits.json` 记录了实际设置；该 workaround 没有写入产品默认策略。

正常 Step 0 的真实日志显示，L/K 的 vDSO probe 均观测到 200000 次 fallback syscall。K runner 还位于 CPU 1，而规格只允许 CPU 0。严格 gate 因此失败，未进入正式轮次，见 [selfcheck-gate](eval-protocol-smoke/selfcheck-gate/)。probe 调用 libc 时间接口并以真实 ptrace/SYS_getpid 边界计数；当前证据不能将失败直接归因于 probe 实现错误。

随后通过显式 `--skip-selfcheck` 执行诊断性的真实 `sys.lm.null`，保留自动加入的 noop baseline。源码确认 LMbench null 实际调用 `getppid`。这次运行不满足正式公平性 gate，不能当作公平性能对比通过。

| 目标 | 真实记录 | 协议完整性 | invariant 结果 |
| --- | --- | --- | --- |
| L | `selfcheck.noop`、`sys.lm.null` | 两条 case 完整 | 两条均 valid |
| K | `selfcheck.noop`、`sys.lm.null` | 两条 case 与两条 stats 完整配对 | 两条因 CPU 1 不在允许集合而 invalid；null 还比 noop 多 2500 次 FPU save，当前上限为 0 |

CLI 实际 exit 1；[records.jsonl](eval-protocol-smoke/protocol-smoke/records.jsonl)、[report.md](eval-protocol-smoke/protocol-smoke/report.md) 和原始串口日志均保留。FPU 数量覆盖整个实例与 benchmark 调度，不能由此推断每次 getppid 都产生了不必要的保存操作。

一次性脚本随后读取这些原始日志，重现 L 通过、K 拒绝，并使用 GNU cpio 检查真实 archive，见 [real-log-check.json](eval-protocol-smoke/real-log-check.json)。另两份真实旧日志缺少 `EVAL_CASE_JSON`，严格解析拒绝它们，见 [legacy-log-check.json](eval-protocol-smoke/legacy-log-check.json)。这些检查没有模拟 QEMU 或制造测量值。

## 输入身份与源码边界

| 输入 | SHA-256 |
| --- | --- |
| 现有打包 K ELF | `fbeebee8b0f18486baf2744f1d5f8daee05a1a80960dd6c80f843a0a88f1247a` |
| host Linux bzImage | `05baf6a37aee29813271e66acdc5fe261c1f15858db52327b164a125bb523dbb` |
| host initrd | `a6139c5037144537621cc006861e29bd5a35a4d0a45ae3b9c0425f02eee1b891` |
| 被测 payload | `7497ce18273f2a2b1fb336acc856d64a24c35ee1ed7ffa0e3a9a580fb2c7f99a` |
| 运行期间观察的 1192 文件源码快照 | `4ad6186c3deb4ff28e694da4de6713c0655d2a36031def28819a990b47e7e374` |

[inputs.json](eval-protocol-smoke/inputs.json) 保存源码文件 hash、依赖 pins 和嵌入 artifact hash；[source-snapshot.tar.gz](eval-protocol-smoke/source-snapshot.tar.gz) 保留该源码观察快照。这个快照不建立旧 ELF 的构建来源。[final-code-and-helpers.json](eval-protocol-smoke/final-code-and-helpers.json) 另列最终 eval 源码 hash、最终编译检查的 helper hash，以及真实运行中旧打包 helper 的 hash，避免混淆两者。[final-eval-source.tar.gz](eval-protocol-smoke/final-eval-source.tar.gz) 保存最终 27 个 eval 源文件，SHA 为 `e90269e73a07182854cd681513ff10d47a5e859ae0622fb3690794bac7849d1b`。

## 交接

实现范围为 `poc/eval/host/`、`guest/{eval_guest_runner,eval_init,vdso_selfcheck}.c`、构建脚本、依赖 pins 和 Nix 配方。Python 文件没有顶部 module docstring 或 shebang，入口通过显式 `python3` 调用。

尚未完成的实验前提是 vDSO 路径、固定 vCPU 与 affinity 规格的关系，以及整个实例的 FPU 次数限制如何表达原本要检查的条件。复验需要与最终源码对应的 release/debug 镜像。验证交付物与源码快照保存在 `eval-protocol-smoke/`；独占临时验证目录已清理，软件源码和构建 cache 保留。
