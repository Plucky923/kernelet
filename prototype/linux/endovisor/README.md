# endovisor: the kernel module that hosts kernelets

The endovisor is the component inside the host kernel that creates, runs,
schedules and destroys kernelets. Here it is one loadable Linux module,
`endovisor.ko`, which offers the endovisor UAPI, `uapi/endovisor.h`: the
device node `/dev/endovisor`, its `ioctl`s and their structures, which the
book's chapter 2 specifies and `../../host/runtime/sandbox.c` uses.

The module carries no kernelet image. An image is a file of its own, the
`ld -r` of a kernel proper and vOSTD; `KLET_KIND_REGISTER` reads it as a
module file is read and the endovisor loads and relocates it itself
(`image.c`), as a *kind*. A sandbox (`KLET_CREATE`) is one instance of a
kind; its carriers are children the holder forked, each of which executed its
virtual CPU's exec descriptor, a file the binary-format handler recognizes by
its inode. The endovisor serves the image ABI's other half for each sandbox:
it allocates the grant at the sandbox's start, writes the boot arguments,
publishes the host offsets that let vOSTD find its own virtual-CPU record,
implements every service in the service table, and calls the image through
its entry table. Every carrier enters and leaves kernelet code through the two
carrier hooks.

It depends on the patch (`../patches`) and on nothing else that is not
exported to modules, bar the one prototype it repeats for `flush_tlb_mm_range`.

## How it is built

`make endovisor-module` from the top level: an ordinary out-of-tree module
build against the patched tree in `.build/linux-6.12` (`make module
DIR=linux/endovisor`). `Makefile` in this directory is the Kbuild file. The
images are built apart, by `make image` (`.build/<kernel>.image`), and one
module serves every kernel proper.

## Module parameters

| parameter | default | what it does |
|---|---|---|
| `klet_watch` | 1 | the per-processor watch timer: the kernelet's tick, the delivery of virtual interrupts into kernelet code, and the bound on a critical section; `make yield` turns it off for its control boot |
| `klet_mirror` | 1 | vOSTD mirrors its guard depth into Linux's preemption count; `make sched-coop` turns it off for its control boot |
| `klet_test_hooks` | 0 | the test hook: a `vm_map` whose protection carries `KLET_PROT_TEST_SLEEP` sleeps in Linux; `make mem-conc` turns it on |
| `klet_test_sleep_ms` | 20 | how long such a `vm_map` sleeps, in milliseconds |

## Files

| file | what it is | chapter |
|---|---|---|
| `Makefile` | the Kbuild file: which objects make `endovisor.ko` | 3 |
| `uapi/endovisor.h` | the endovisor UAPI, shared with host programs | 2 |
| `kernelet.h` | the C mirror of the image ABI (`struct klet_boot_args`, `klet_services`, `klet_entry_table`, `klet_vcpu_rec`, `klet_space_rec`, `klet_mem_stats`), the kind, instance and carrier records (the heap's table among them), the counters and their module totals, and every internal declaration | 3 |
| `main.c` | module init and exit (including the refusal to load on a kernel that emulates the vsyscall page); the device and its system operations (`KLET_GET_API_VERSION`, `KLET_KIND_REGISTER` with the checks of `init_module`, `KLET_KIND_LIST`, `KLET_KIND_UNREGISTER`); the lifeline file; `klet_publish_host_offsets`; the binary-format handler `klet_load_binary`, which makes the executing process the carrier of its virtual CPU: the checks, an emptied address space, every signal it can ignore ignored, not dumpable, named `kernelet/<slot>/<i>`, and the first arrival starting the sandbox; the module parameters; and the totals printed at unload | 2, 3, 5, 7 |
| `image.c` | the image loader: the ELF checks, the layout in execmem's module range, the relocations, `kernelet_entry_table`, and the pristine copy of the data that every sandbox of the kind starts from | 2, 3 |
| `sandbox.c` | `KLET_CREATE` and the table of sandboxes; the sandbox descriptor (`KLET_GET_VCPU_EXEC_FD`, `KLET_SET_CONSOLE`, `KLET_SET_LOG`, `KLET_KILL`, `KLET_WAIT`, `poll`, `KLET_GET_STATS`, `KLET_DESTROY`, `release`); the exec descriptors' files; the start (`klet_sandbox_start`: the kind's data restored, the grant, the boot arguments); the end (`klet_end`, `klet_sandbox_exited`) and the destroy; the console and log rings and the work item that drains them | 2 |
| `carrier.c` | carriers (`klet_carrier_new`, `klet_carrier_attach`, `klet_carrier_die`, the death notice `klet_carrier_lifeline_closed`), the wait of an arrived carrier until its virtual CPU may enter the image (`klet_vcpu_await`), `klet_enter`/`klet_leave`, the mirror (`klet_mirror_in`/`out`), the carrier hooks `klet_on_syscall` and `klet_on_resume`, signals (`klet_drain_signals`, which also ignores again a fault signal Linux forced, and leaves a signal Linux made fatal for good, such as seccomp's kill, for Linux to deliver; `klet_is_fault_signal`), registers, the kernelet-stack pool and its bound, the heap (`klet_do_mem_alloc`, `klet_do_mem_free`: `kmalloc` with every block recorded, so that what the kernelet still holds is freed when the sandbox ends; no request beyond what `kmalloc` can give, and no warning from Linux for one that fails), `klet_sandbox_gone` (what the kernelet held, its spaces, heap and stack pool, goes back to Linux when its last carrier dies), the service table and `klet_svc_body`, the two output services, `user_run`, idle, kick, yield, the floating-point services, stop and kill (`klet_carrier_doom`: a fatal signal found in a service ends the sandbox), the carrier records' two references, and the one-off measurement of a service's cost | 5, 6, 7, 8, 10, 11 |
| `space.c` | tenant memory: a `VmSpace` as a Linux address space with one PFN-mapped area; the area's fault handlers; `vm_create`, `vm_destroy`, `vm_activate`, `vm_map`, `vm_unmap`, `vm_protect`, `vm_flush`, `vm_wait`, `vm_wake`; adoption (`klet_space_adopt`) and `klet_leave_space` | 12, 13 |
| `watch.c` | the per-processor watch timer `klet_watch_fn`, which also evicts a carrier it finds running kernelet code with a fatal signal pending; `klet_virq_redirect`, which points an interrupted instruction pointer at the image's upcall stub; `klet_watch_fire_now`, which makes the timer fire at once for a kick | 9, 10 |
| `sched.c` | the preempt notifiers (`klet_sched_in`/`out`: arming the watch, counting involuntary deschedules in a critical section, stolen time), `vcpu_on_spin`, and the kick IPI (`klet_kick_remote`, `klet_kick_ipi`) | 8, 9, 10 |
| `evict.c` | the eviction sweep: taking a processor back from kernelet code of a dying sandbox, armed by every end of a sandbox while it has carriers | 11 |
| `switch.S` | `klet_switch` (the coroutine switch between a carrier's Linux stack and a kernelet stack), `klet_run_on_linux_stack`, the yield stub and the eviction exit stub | 6, 10, 11 |

Build products (`*.o`, `*.ko`, Kbuild's own files) are not in the repository.
