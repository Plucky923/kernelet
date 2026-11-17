# 退出清理与 carrier 生命周期复核

本记录描述 Host 侧资源和 carrier 的最终所有权协议。Host 在最后一条 lifeline 关闭后回收剩余资源，完成后才发布退出结果；保留结果 fd 不会延迟重资源回收。完整运行验证和产物身份见[验证记录](README.md)。

## 最终协议

1. `sandbox_stop` 在 `sandbox->lock` 下只记录第一次退出原因并发布 `dying`。`dying && nr_carriers == 0 && !exit_claimed` 是唯一 cleanup claim 条件；claim 同时取得 work 的一份 `sandbox` 引用。`released` 和 `destroy_queued` 已删除，work 在构造时只初始化一次。来源：`poc/linux/endovisor/main.c::sandbox_claim_cleanup_locked:134`、`sandbox_stop:149`、`dev_sandbox_create:857`。
2. Linux `do_exit` 在 `exit_mm` 之后、`exit_files` 之前调用 `carrier_event_hooks::on_exit`。该回调在原 carrier 上清除 syscall work、hooks 指针、preempt notifier 和 CPU slot，并标记 `CARRIER_DEAD`；它不切换 `mm`。来源：`prototype/.build/linux-6.12/kernel/exit.c:927`、`include/linux/kernelet.h::carrier_event_hooks`；`poc/linux/endovisor/carrier.c::carrier_detach_hooks:180`、`on_exit:192`。
3. `carrier_lifeline_closed` 在完成 hook 脱离后释放 `own_mm`、移出 carrier 列表并减少计数。若最后一个 carrier 是非预期丢失，则由 `sandbox_stop` 发布 `dying` 并 claim；已有 `dying` 时直接 claim。queue 在锁外执行，最后无条件释放 lifeline 所拥有的 carrier 引用。来源：`carrier.c:212`。
4. `cleanup_work` 取得 `sandbox->mutex`，依次执行 `image_stop`、`spaces_destroy`、`grant_destroy`、registry 取消发布及 kind 引用释放，再释放 cgroup/owner。`spaces_destroy` 真正清除剩余 root，并经 Host TLB/RCU 完成后释放 `mm`；grant 页最后才释放。worker 解锁后 `smp_store_release(exited, true)`，唤醒 reader/poller，最后释放 work 引用。来源：`main.c::sandbox_cleanup_resources:102`、`cleanup_work:119`；`space.c::space_teardown:246`。
5. fd 保留结果对象的引用；`release` 仅请求 stop 并 `put`，不再决定资源何时回收。`read`/`poll` 以 acquire 读取 `exited`。`SANDBOX_STATS` 仍是即时快照；最终统计须等待 `read`/`poll` 完成，不能仅凭 `waitpid` 已返回就假定 worker 已结束。来源：`main.c::sandbox_read:663`、`sandbox_poll:684`、`sandbox_release:692`。

## 锁和引用为何足够

`sandbox->mutex` 保护创建/获取 exec fd、直接 attach、exec 完成后建立 carrier，以及最终资源回收。启动者先取得该 mutex、确认 `dying == false`，才读取 owner、共享页和 Image 地址；`carrier_new` 的 lockdep assertion 明确要求这个条件。若 stop 已 claim cleanup，worker 等待此前启动者退出互斥区；启动者若已被计入 `nr_carriers`，则 cleanup 根本不能 claim。若尚未计入，`carrier_new` 在 `sandbox->lock` 下重查 `dying`，拒绝启动。来源：`main.c::get_vcpu_exec_fd:475`、`attach_vcpu:526`；`carrier.c::carrier_new:98`。

exec 的预占 slot 不等于资源引用。`exec_lookup` 持有 `sandbox` 对象引用，`exec_claim` 只预占 slot；随后 `begin_new_exec` 不持 sandbox mutex，因为它可能等待旧线程退出，旧线程也可能正在等待这个 mutex。exec 完成后才取得 mutex，并重新检查 `dying`。cleanup 若已在此期间完成，启动者只撤销预占并走不可返回点之后的失败退出，不再读取已释放的资源。来源：`main.c::load_carrier_binary:388`。

锁顺序为资源路径的 `sandbox->mutex → sandbox->lock` 或 `sandbox->mutex → registry_lock`。`exec_lookup` 先释放 registry lock 才进入启动路径。stop 和 lifeline 路径只在短临界区持有 `sandbox->lock`，不持它等待 mutex；worker 不重新取得 `sandbox->lock`。本实现没有 `evict_disarm` 函数，也没有在持有同一锁时调用重新加锁的 disarm helper。

初始 `sandbox` 引用交给 fd；每个已注册 carrier 持有一份；exec lookup 单独取得临时引用；唯一 cleanup claim 单独取得 work 引用。queue 的调用者在 claim 到入队之间仍持有 fd、carrier 或 lookup 的引用。fd 提前关闭不会释放 worker 的对象；fd 长期保持打开也不会阻碍重资源回收。carrier 的初始引用只在成功安装 lifeline 时交给文件；fd 分配失败时由调用者统一清理，避免额外 `put`。来源：`carrier.c::carrier_attach:156`。

## 已覆盖的反例

| 交错或失败点 | 当前处理 |
|---|---|
| stop 发布 dying 后，最后 carrier 先离开，stop 尾部才调用 `evict_arm` | arm 在同一 `sandbox->lock` 下拒绝 `exit_claimed` 或零 carrier；`sweep_armed` 与全局计数递增在锁内一起完成，claim 在锁内一起取消并递减。不会在 cleanup 后遗留一个新 armed 引用。来源：`watch.c::evict_arm:336`、`main.c:142`。锁外迟到的 `on_each_cpu` 仅操作通用 timer，不再持有 sandbox 指针。 |
| 远端进程通过 `pidfd_getfd` 保留 lifeline，原 task 在 `exit_files` 后尚未完成最后一次 sched_out，远端恰好 final fput | final fput 只可能发生在原 task 已丢弃自身文件引用之后；新的 `on_exit` 在该原始 fput 之前已撤销 notifier。因此远端 release 可以释放 carrier，不需要远端修改仍在调度器中使用的 notifier，也不依赖轮询任务死亡。保留了复制 fd 仅延迟退出通知的行为。 |
| 已有 exec claim，但在 `carrier_new` 前发生 kill | 对象引用保证对象存在；资源 mutex 和后置 `dying` 重查保证不再使用已释放资源。 |
| `carrier_new` 或 fd 安装失败 | 未安装成功的文件不拥有 carrier 引用；创建者手动执行一次 carrier 清理。若 lifeline 已安装，后续启动失败只 stop/发 fatal signal，由真实文件 release 清理，不能手动重复关闭生命周期。 |
| `sandbox_start` 失败，或创建 sandbox fd 失败 | 创建期已提前初始化 spaces 和全部生命周期原语；统一同步回收部分资源并释放创建者引用，不排队一个未发布对象的第二次清理。首 carrier 的 start 错误也会 stop 并退出。Linux `fs/anon_inodes.c:229` 证实 `anon_inode_getfd` 在分配 fd 失败时没有创建会触发 release 的文件。 |
| 退出后仍持有 sandbox fd，再次请求 GET/ATTACH | 取得资源 mutex 后首先检查 `dying`，合法 vCPU 请求返回 `ESRCH`，不访问已回收的 exec file、owner 或共享页。 |
| 最后一个文件关闭后模块卸载，而 cleanup work 尚未运行 | 文件操作和 binfmt 的模块引用覆盖活动入口；最终 release 已安排的 work 在 `endovisor_exit` 中被 flush，之后才销毁 workqueue、释放剩余 kinds。来源：`main.c::endovisor_exit:1044`。 |

`exited` 现在意味着资源清理完成；kind 的 `nr_sandboxes` 也在资源清理时减少。因此结果 fd 仍打开时，若所有运行实例都已清理，`KIND_UNREGISTER` 可以成功。这是需要同步说明的接口语义，不能仍写成“任何结果 fd 存在就返回 EBUSY”。

## Image 注册的策略边界

`main.c::dev_kind_register:716` 和 unregister 均要求 `CAP_SYS_MODULE` 且 `!READ_ONCE(modules_disabled)`。raw Image 无模块签名格式，因此 `is_module_sig_enforced()` 为真时返回 `EKEYREJECTED`，并服从 `security_locked_down(LOCKDOWN_MODULE_SIGNATURE)`；复制 Image 字节前后分别调用原生 `security_kernel_load_data(LOADING_MODULE, true)` 与 `security_kernel_post_load_data(..., LOADING_MODULE, "kernelet image")`。所有拒绝路径释放尚未发布的缓冲区。没有宣称支持带签名 Image 文件或完整 Accepted Design 的 fd 文件加载接口。

## 实际检查与产物

最终 Linux patch 对独立原始基线通过 `git apply --check --whitespace=error`。反向/正向应用后的 18 个文件与实际 Linux 源码逐字节一致。实际 Linux 6.12、release/debug 模块和两个 Rust 配置已重建，最终 14 次 QEMU/KVM 回归通过，包括 attach、exec、异常、panic、终止和清理；所有被测产物均与归档哈希一致。

最终源码、工具链、构建日志、完整运行记录及限制见 [验证记录](README.md)、[final-inputs.json](final-inputs.json) 和 [verification.json](verification.json)。新的 attach 冷路径见 [attach-registration-review.md](attach-registration-review.md)。

当前配置未启用 `CONFIG_MODULE_SIG`、`CONFIG_SECURITY`；启用签名、LSM 和 lockdown 后的拒绝行为尚未运行验证。远端 final fput 的具体交错经过源码和引用关系审查，未专门通过运行时调度控制重现。
