# 内存服务基线：测量计划

- 开始日期：2026-11-14
- 服务对象：`book/src/design-proposals/2026-11-13-direct-page-table-updates-in-vostd.md`（原 `2026-11-13-batched-memory-services.md`）的 Problem and motivation
- 状态：计划已定，尚未开始实现（已有的 fork 结果见第 4 节）
- 后续更新（2026-11-15）：更新并定稿的完整实验计划（基于 PR #3 PoC + 256 MiB grant + Intel PT）已记录在 `../user-page-table/experiment-plan.md`。

## 1. 目的

提案现在直接拿 `make mem-perf` 的数字开头，读者不知道该拿它和什么比。Problem 一节要先回答三个问题：

1. Linux 自己什么时候写用户页表，每次写多少；
2. 在同一台虚拟机、同一个内核里，Linux 做同一件事每页要多少；
3. kernelet 做语义相同的事每页要多少，差距落在哪一类操作上。

## 2. 背景：Linux 什么时候写 PTE（讨论结论）

- `mmap` 只登记 VMA，不写 PTE。PTE 在第一次访问触发缺页时才写入。
  - 匿名页：一次缺页装 1 个 PTE，还要分配并清零一个物理页。
  - 文件页和共享内存的读缺页：fault-around 一次最多装 16 个 PTE（64 KiB）。
- 一个 syscall 改一大段的情况有 `fork`、`mprotect`、`munmap`、`exit`、`MAP_POPULATE`、`mlock`。
  - Linux 每张最底层页表（512 项，覆盖 2 MiB）只遍历一次、拿一次 PTE 锁。
  - 整个操作只刷一次 TLB。
- `fork` 有两种策略：
  - 私有匿名内存：逐项复制 PTE，父子两边都改成只读，给物理页加引用，最后刷父进程的 TLB（COW）。
  - 没有私有页的共享映射：整段跳过，等子进程缺页时再补。
  - 这是两种不同的策略，不是同一件事的快慢之分。
- COW 写缺页：复制 4 KiB 的物理页，把 PTE 改成指向新页并可写，再刷这一页的 TLB。
  - 只有一个映射者时走 reuse 路径，不复制页，直接改回可写。

kernelet 在语义上做同样的事，区别是：

- 每写一个 PTE 都要调用一次服务（`map`、`protect`），只有 endovisor 能写 Linux 的页表；
- 刷 TLB 也要调用服务。

## 3. 测量矩阵

按"对 PTE 做的事"分成四类。每一项 Linux 和 kernelet 各测一份，都按**每次操作**和**每页**报告。

| # | 类别 | 场景 | Linux 侧做法 | kernelet 侧做法 | 状态 |
|---|---|---|---|---|---|
| A1 | 装入 | 匿名页缺页，每次 1 页 | 64 MiB 私有匿名内存，`MADV_NOHUGEPAGE`，每 4 KiB 写一次 | 新增策略 `FaultOne`：缺页时分配 1 个清零的 frame 并 `map` | 待做（两侧都要写） |
| A2 | 装入 | fault-around，每次 16 页 | 64 MiB 的 memfd，先填满 page cache，再映射，然后按 4 KiB 步长读 | 已有 `Policy::FaultAround`（每次 16 页），需要加一个 perf 行 | 待做 |
| A3 | 装入 | 一次装入一整段 | `mmap(MAP_POPULATE)` 64 MiB，分匿名和 memfd 两种 | 已有：一个 cursor 下 `map` 64 MiB（e9 的准备阶段），需要单独计时 | 待做 |
| B1 | 复制 | fork，立即复制 | forkbench `anon` | 已有 `fork_64m`（`cow_copy_pt`） | **已测** |
| B2 | 复制 | fork，推迟到缺页 | forkbench `shared` | 无对应实现，只作为策略对照 | **已测**（Linux 侧） |
| C1 | 改权限 | mprotect 可写改只读，2 MiB 和 64 MiB | `mprotect`，测前先写一遍 | 已有 `protect_2m`；加一个 64 MiB 的行 | 待做 |
| C2 | 改权限 | 写缺页改回可写，不复制（reuse） | fork 后子进程退出，父进程逐页写 | 已有 `Policy::MakeWritable`，需要加一个 perf 行 | 待做 |
| C3 | 改权限 | COW 写缺页，要复制页 | fork 后子进程逐页写（父进程还活着） | 新增策略 `CowCopy`：分配 frame，复制 4 KiB，`map` 覆盖旧项，刷单页 TLB | 待做（两侧都要写） |
| D1 | 清除 | munmap 64 MiB | 写满后 `munmap` | 已有 `munmap_64m` | 待做（Linux 侧） |
| D2 | 清除 | 进程退出时拆掉 64 MiB | fork 出一个写满 64 MiB 的子进程，测 `exit` 到 `waitpid` 返回 | 销毁一个 64 MiB 的 `VmSpace`（e9 里的 `drop(child)`），需要计时 | 待做 |

先不测、以后再说的：

- **多 vCPU 的 TLB shootdown**：两个线程分别在两个 vCPU 上运行，测 C1 和 D1。先把单线程的基线做出来。
- **exec**：它本质上是 A1/A2 和 D2 的组合。

## 4. 已有结果（2026-11-13，同一台虚拟机）

原始数据在 `results/`。

| 64 MiB | fork | 子进程第一次读完 | fork + 子进程读完 | 父进程重读 |
|---|---:|---:|---:|---:|
| kernelet（`cow_copy_pt`，每页 1 次 `protect` + 1 次 `map`） | 7.85 ms | 0.56 ms | 8.40 ms | 0.56 ms |
| Linux anon（立即复制） | 0.34 ms | 0.61 ms | 0.95 ms | 0.095 ms |
| Linux shared（推迟到缺页） | 0.025 ms | 1.19 ms（约 1,089 次缺页） | 1.22 ms | 0.05 ms |

换算成每页：

- Linux 立即复制：约 21 ns，约 66 周期；
- kernelet fork：约 479 ns，约 1,530 周期；
- kernelet 单次 `map`：447 周期。

还没解释的现象：kernelet 里父进程在 fork 后重读要 0.56 ms，是 Linux 的 5 到 10 倍，而且两边都没有缺页。怀疑和 fork 结尾的全量 TLB 刷新以及 vOSTD 的页表布局有关，留到测量做完后再查。

## 5. 测量方法

### 环境（两侧相同）

- Linux 6.12 tinyconfig 加 `prototype/linux/config.fragment`，KVM，`-cpu host -smp 2 -m 512M`。
- 用户本地的 QEMU 11 需要：
  - `LD_PRELOAD=tools/nouring.so`：当前用户的 memlock 额度装不下 io_uring，用这个垫片让 QEMU 退回 ppoll；
  - `QEMU_EXTRA="-nic none"`：本地 QEMU 缺 `efi-e1000.rom`。
- 每项测试绑定到 CPU 1，测之前先预热一轮。
- 每次启动跑 N 轮取中位数，共启动 5 次，报告"各次启动中位数的中位数"，并给出 min 和 max。

### Linux 侧

- 把 `tools/forkbench.c` 扩展成 `tools/membench.c`，用 `argv` 选择场景，场景名和第 3 节的编号对应（a1、a2、……）。
- 计时：
  - 用 `rdtsc` 计周期，并用 `clock_gettime` 交叉校验；
  - TSC 频率用 mem-perf 打印的那个值（3,194,216 kHz）。
- 用 `getrusage` 的 minor fault 数核对缺页次数，确认场景真的按预期走了缺页路径，或者没走。
- 构建成静态二进制，放到 `.build/stage/tests/`，不加载 endovisor。

### kernelet 侧

- 修改 `prototype/kernels/mem/src/lib.rs` 的 `perf_main`：
  - 加 A1、A2、A3、C1（64 MiB）、C2、C3、D2 这几行；
  - 加新的 `Policy` 变体 `FaultOne` 和 `CowCopy`。
- tenant 程序需要支持"按步长写"，`CMD_TOUCH_WRITE` 已经有了，要看它是不是每页都写。
- 新的行要让 `bench/mem-perf.py` 能解析。
- 这些都是仓库代码，先在实验分支或工作区里改，**是否提交另行决定**。

## 6. 已知的不对等之处，写结论时要注明

- **Linux 的 fork 还做了别的事**：它包括创建 mm、复制 VMA 等；kernelet 的 `fork()` 只复制页表。这个差别对 kernelet 有利，所以不影响"kernelet 更慢"这个结论。
- **trap 路径不同**：
  - Linux 的缺页是 CPU 异常直接进入 Linux 内核；
  - kernelet 的缺页是 tenant 异常先进入 kernel proper（通过 vOSTD 的 `UserMode::execute` 返回），由它处理后再调用服务。
  - 所以 A1、A2、C2、C3 比的是整条路径，不只是写 PTE 那一步。
- **frame 的清零**：kernelet 的 `FrameAllocOptions` 默认会清零（`prototype/vostd/src/mm/frame.rs:525`），和 Linux 匿名缺页的语义一致。
- **测量的布局不同**：kernelet 的测试是 256 个物理 frame、每个映射 64 次；Linux 的 anon 是 16,384 个不同的页。缓存行为可能因此不同。

## 7. 待定的问题

- C3 要求 `map` 能覆盖一个已经存在的映射。需要确认 vOSTD 的 `CursorMut::map` 对已映射的槽位怎么处理，以及 endovisor 这时会不会走 `klet_space_insert` 的那条验证路径。
- A2 在 kernelet 里没有 page cache，`FaultAround` 是每页新分配一个 frame。和 Linux"从 page cache 找到已有的页"相比，kernelet 这边多了分配和清零的开销。要么在 kernelet 侧改成映射已有的 frame，要么在结论里注明。
- 要不要顺便测一下 Linux 侧 `remap_pfn_range` 或 `vmf_insert_pfn`（`VM_PFNMAP` 路径）的批量成本。endovisor 用的就是这条路径，它能告诉我们 batch 之后最多能降到多少。

## 8. 讨论记录

- 2026-11-13：在宿主机上测了原生 fork，被指出环境不同，不严谨，改为在 QEMU 虚拟机里测，得到第 4 节的结果。
- 2026-11-14：
  - 讨论 Linux 写 PTE 的时机（第 2 节）；
  - 确定要测装入、复制、改权限、清除四类，每类按场景展开（第 3 节）；
  - 建立这个目录。
