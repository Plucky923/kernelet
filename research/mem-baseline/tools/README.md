# 工具

## forkbench.c

原生 Linux 的 fork 测试，作为 kernelet `make mem-perf` 中 `fork_64m` 那几行的对照。它有三种布局：

- `anon`：64 MiB 私有匿名内存，`MADV_NOHUGEPAGE`，fork 时立即复制 PTE；
- `shared`：一个 1 MiB 的 memfd 映射 64 次，fork 时 Linux 跳过不复制；
- `anon-thp`：允许透明大页的匿名内存（2026-11-13 在虚拟机里大页没有生效）。

每种布局 fork 31 次，打印 fork、子进程第一次读完、父进程重读这三项的中位数，以及缺页次数。

构建（静态链接，放进 initramfs 用）：

```sh
gcc -O2 -Wall -static -o forkbench-static forkbench.c
```

在虚拟机里跑（在 `prototype/` 目录下，不加载 endovisor）：

```sh
# 先备份 .build/stage/modules 和 .build/stage/tests，再清空它们
cp forkbench-static .build/stage/tests/10-forkbench
LD_PRELOAD=<本目录>/nouring.so make run QEMU_EXTRA="-nic none" TIMEOUT=300
grep FORKBENCH .build/serial.log
# 跑完把 modules 和 tests 恢复成原样
```

## nouring.c / nouring.so

一个 `LD_PRELOAD` 垫片，让 `io_uring_queue_init` 直接返回 `-ENOSYS`，QEMU 就会退回到 ppoll 事件循环。

为什么需要它：本机 `~/.local/bin/qemu-system-x86_64` 包装的是一个用户本地安装的 QEMU 11.1.3，它启动时要创建一个较大的 io_uring。io_uring 的锁定内存是按用户统计的，而当前用户 8 MiB 的 memlock 额度装不下这么大的 ring，于是 QEMU 报 `Failed to initialize io_uring: Cannot allocate memory` 并退出。

用法：

```sh
gcc -shared -fPIC -O2 -o nouring.so nouring.c     # nouring.so 已经编译好了，一般不用重新构建
LD_PRELOAD=$PWD/nouring.so make mem-perf JOBS=16 QEMU_EXTRA="-nic none"
```

另外，这个本地 QEMU 缺 `efi-e1000.rom`，所以一定要加 `-nic none`。

## iouring-probe.c

诊断工具：用不同的条目数调用 `io_uring_setup`，看哪些规模能成功。2026-11-13 的结果是 1 和 8 能成功，128 及以上都返回 `ENOMEM`，由此确认了上面说的 memlock 问题。

```sh
gcc -O2 -o iouring-probe iouring-probe.c && ./iouring-probe
```
