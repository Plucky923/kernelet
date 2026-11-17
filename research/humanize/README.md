# 用 Humanize 运行实验

本目录保存 Kernelet 实验的 Humanize 启动说明与交接任务，供后续实验复用；模型、实验范围或入口变化时更新。原始测量结果仍按 `research/user-page-table/experiment-plan.md` 的约定归档。

本机已安装 `hmz 0.2.2`，通过 `uv tool upgrade hmz` 核对更新。AGY 和 Codex 均使用本机已有登录。模型名称已由各自 CLI 的当前模型列表核对，后续可用性以账户实际返回为准。

2026-11-16 的临时目录联动检查已通过：AGY 写入并读取测试文件，Codex 独立核对其精确字节，返回结构化 `done=true`，`rlar` 正常结束。此检查验证后端接入、文件工具和流程交接；正式构建、QEMU 和基准测量尚未在这个流程中运行。

本仓库的交互配置已经保存到 `~/.hmz/settings.yaml` 对应 `/mnt/data/projects/kernelet` 的条目：当前默认是 `chat`，由 `agy/gemini-4-hydrogen-high` 回答；`rlar` 的两个角色与一小时预算也已填好。重新打开 `hmz` 后开启新对话即可使用该配置：

```bash
cd /mnt/data/projects/kernelet
hmz
```

讨论实验方案时，第一条消息可以这样写：

> 先阅读 `research/user-page-table/experiment-plan.md` 第 6 节和 `syscall-overhead-source-audit.md`。这轮只讨论方案，不修改代码、不启动实验。每次讨论一个问题，等我回复后继续。

`chat` 具备文件和命令工具，这段消息限定当前任务范围，并不改变工具权限。首次启动可能询问是否发送错误报告，按个人偏好选择；模型和流程已经配置完成。

建议使用内置 `rlar`。执行者在同一个会话中维护构建和实验上下文，每轮结束后由一个新的审阅者检查文件与证据；审阅通过、运行失败或预算耗尽时结束。当前角色分配为：

| 角色 | 配置 | 职责 |
|---|---|---|
| `actor` | `agy/gemini-4-carbon-high` | 实现测量准备、运行实验、保留原始数据 |
| `reviewer` | `codex/gpt-6.1-sol:high` | 核对来源、条件、原始日志、统计和结论 |

这沿用已有实验会话使用的模型。一次只运行一个测量任务，避免两个流程同时修改同一份源码或争用测量资源。`flame_chase` 每轮更换执行者并新开会话，通常持续到预算耗尽，适合探索；当前需要有限目标与独立验收，因此选择 `rlar`。

首次启动正式测量前，确认现有 AGY 会话的诊断代码清理已经完成。主仓库和 `poc/` 都有未提交修改；仅从 HEAD 创建 worktree 不会包含这些修改。正式实验需要保留并冻结两边的实际源码和构建配置。

准备好的[任务](syscall-baseline-task.md)是重建虚拟机内 Linux（L）与完整 Asterinas Kernelet（K）的 syscall 对照，补齐绑核、套件和采样窗口，并记录原生 Asterinas（A）与最小处理器（S）的缺口。任务从读取当前计划与检查源码稳定性开始；尚未决定的内核设计不在这个任务内。

```bash
cd /mnt/data/projects/kernelet
hmz exec -f rlar \
  -a actor=agy/gemini-4-carbon-high \
  -a reviewer=codex/gpt-6.1-sol:high \
  -p budget.duration=1h \
  "$(cat research/humanize/syscall-baseline-task.md)"
```

`budget.duration=1h` 默认允许到时正在执行的 turn 结束，不是严格的一小时中断。运行成功退出也可能只是预算耗尽，需阅读最后的审阅结论和结果文件，确认实验是否完成。

从交互对话切换到审阅流程时，输入 `/flow`，选择 `rlar`，检查已填好的角色和预算，保存后发送任务。之后会记住最后保存的流程；要继续普通对话，选择 `chat` 并保存。运行中可以输入补充要求，使用 `/stop` 或连续两次 `Ctrl+C` 停止。命令行 `hmz exec` 的配置由参数独立指定，不继承 `/flow` 的选择。

浏览运行记录可使用 `hmz web`，或在 `hmz` 中输入 `/epics`。要继续本目录最近一次 `rlar`，在相同启动命令中加入 `--resume`；它使用该流程保存的审阅记录启动新的执行者。

Humanize 会新建会话。已有 AGY、Codex 对话的上下文不会因为使用相同 CLI 和登录而自动导入；交接任务通过以下文件恢复必要背景：

- `research/user-page-table/experiment-plan.md` 第 6 节：四组对照、测量规范与阶段边界。
- `research/user-page-table/syscall-overhead-source-audit.md`：源码和机器码核对、尚未验证的归因。
- `research/user-page-table/results.md`：已有测量，保留历史来源与限制。

后续任务按一个问题划定范围，例如补齐 A 原生基线或验证一个已讨论的优化候选；分别设定完成条件、输出目录和回归要求。`rlar` 的审阅通过属于 Agent 的检查结果，性能结论仍以可复现的实验数据和适用的功能检查为依据。

参考：[RLAR](https://humanfia.ai/flows/rlar)、[命令行运行](https://docs.humanfia.ai/humanize/user/unattended)、[首次运行](https://docs.humanfia.ai/humanize/user/first-run)。
