# 在另一台机器上继续实验

## 获取仓库

主仓库记录研究文档、实验结果、书籍和 Linux 补丁；`poc/` 是 Asterinas fork 的 Git 子模块，记录在主仓库指定的提交上。新机器可以运行：

```bash
git clone --recurse-submodules https://github.com/Plucky923/kernelet.git
cd kernelet
git submodule status
```

如果已经克隆主仓库，运行 `git submodule update --init --recursive`。`poc/` 默认以子模块指定的提交检出；需要在 PoC 上继续开发时，在该目录创建自己的工作分支。修改 PoC 并推送后，需要在主仓库更新子模块版本并提交。

## 准备 Linux 参考源码

构建产物、依赖缓存和 `reference/` 未保存在仓库中。`poc/eval/scripts/build_kernels.sh` 需要未打补丁的 Linux 6.12 源码位于 `reference/linux-6.12/`。从 [kernel.org](https://cdn.kernel.org/pub/linux/kernel/v6.x/) 下载 `linux-6.12.tar.xz`，校验 [官方 SHA-256 清单](https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc)，再解压到 `reference/`：

```bash
mkdir -p reference
curl -fL https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.tar.xz -o reference/linux-6.12.tar.xz
printf '%s  %s\n' b1a2562be56e42afb3f8489d4c2a7ac472ac23098f1ef1c1e40da601f54625eb reference/linux-6.12.tar.xz | sha256sum -c -
tar -xJf reference/linux-6.12.tar.xz -C reference
rm reference/linux-6.12.tar.xz
```

源码包校验失败时停止解压。下载和解压需要网络、磁盘空间及 `curl`、`sha256sum`、`tar`、`xz`。其他参考源码的版本和位置见 [research 目录说明](../README.md#参考源码)。

## 继续实验

先阅读[执行计划](execution-plan.md)，在新主机检查 KVM、CPU 拓扑和时钟状态，再使用 `poc/AGENTS.md` 指定的构建容器重新生成产物。旧机器上的构建产物与新机器的工具链不必一致，不能直接把旧构建记录当作新机器上的验证。

旧机器的 Linux 客户机 vDSO 自检失败；相关记录仅用于诊断，不能作为正式性能结果。新机器必须重新完成三端自检，才能开始五轮采集。
