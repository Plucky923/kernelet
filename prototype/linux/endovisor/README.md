# endovisor: the kernel module that hosts the kernelet

The endovisor is the component inside the host kernel that creates, runs,
schedules and destroys kernelets. Here it is one loadable Linux module,
`kernelet.ko`, that carries exactly one kernelet image, statically linked in as
`image.o`. It serves the image ABI's other half: it allocates the grant, writes
the boot arguments, publishes the host offsets that let vOSTD find its own
virtual-CPU record, implements every service in the service table, and calls
the image through its entry table. It also registers the binary-format handler
that turns a Linux task exec'ing a `.klet` file into the root carrier of a
sandbox, and the two carrier hooks, through which every carrier enters and
leaves kernelet code.

It depends on the patch (`../patches`) and on nothing else that is not
exported to modules, bar the one prototype it repeats for `flush_tlb_mm_range`.

`uapi/kernelet.h` is the kernelet UAPI: the device node `/dev/kernelet`, its
`ioctl`s and their structures, which the book's chapter 2 specifies and
`../../host/runtime/holder.c` uses. This module does not implement it yet;
the header is the interface's definition, shared with host programs.

## How it is built

`make kernelet-module` from the top level: first `make image`, which builds
vOSTD and the kernel proper named by `KLET_KERNEL` and pre-links them into
`image.o_shipped` here, then an ordinary out-of-tree module build against the
patched tree in `.build/linux-6.12` (`make module DIR=endovisor`). `Makefile`
in this directory is the Kbuild file.

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
| `Makefile` | the Kbuild file: which objects make `kernelet.ko` | 3 |
| `kernelet.h` | the C mirror of the image ABI (`struct klet_boot_args`, `klet_services`, `klet_entry_table`, `klet_vcpu_rec`, `klet_space_rec`, `klet_mem_stats`), the carrier and instance records (the heap's table among them), and every internal declaration | 3 |
| `main.c` | module init and exit (including the refusal to load on a kernel that emulates the vsyscall page), the grant, the lifeline file, `klet_publish_host_offsets`, `klet_load_binary` and `klet_empty_mm` (the `.klet` loader, which also ignores every signal a carrier can be sent), the module parameters, and the counters printed at unload | 3, 5, 7 |
| `carrier.c` | carriers (`klet_carrier_new`, `klet_carrier_attach`, `klet_carrier_die`), the root carrier's `klet_root_loop` and `klet_spawn_vcpu` (`kernel_clone`), `klet_enter`/`klet_leave`, the mirror (`klet_mirror_in`/`out`), the carrier hooks `klet_on_syscall` and `klet_on_resume`, signals (`klet_drain_signals`, which also ignores again a fault signal Linux forced, and leaves a signal Linux made fatal for good, such as seccomp's kill, for Linux to deliver; `klet_is_fault_signal`), registers, the kernelet-stack pool and its bound, the heap (`klet_do_mem_alloc`, `klet_do_mem_free`: `kmalloc` with every block recorded, so that what the kernelet still holds is freed when the sandbox ends; no request beyond what `kmalloc` can give, and no warning from Linux for one that fails), `klet_sandbox_gone` (the sandbox's end: its spaces, heap and stack pool go back to Linux when its last carrier dies), the service table and `klet_svc_body`, `user_run`, idle, kick, yield, the floating-point services, stop and kill (`klet_carrier_doom`: a fatal signal found in a service ends the sandbox), the carrier records' two references, and the one-off measurement of a service's cost | 5, 6, 7, 8, 10, 11 |
| `space.c` | tenant memory: a `VmSpace` as a Linux address space with one PFN-mapped area; the area's fault handlers; `vm_create`, `vm_destroy`, `vm_activate`, `vm_map`, `vm_unmap`, `vm_protect`, `vm_flush`, `vm_wait`, `vm_wake`; adoption (`klet_space_adopt`) and `klet_leave_space` | 12, 13 |
| `watch.c` | the per-processor watch timer `klet_watch_fn`, which also evicts a carrier it finds running kernelet code with a fatal signal pending; `klet_virq_redirect`, which points an interrupted instruction pointer at the image's upcall stub; `klet_watch_fire_now`, which makes the timer fire at once for a kick | 9, 10 |
| `sched.c` | the preempt notifiers (`klet_sched_in`/`out`: arming the watch, counting involuntary deschedules in a critical section, stolen time), `vcpu_on_spin`, and the kick IPI (`klet_kick_remote`, `klet_kick_ipi`) | 8, 9, 10 |
| `evict.c` | the eviction sweep: taking a processor back from kernelet code of a dying sandbox | 11 |
| `switch.S` | `klet_switch` (the coroutine switch between a carrier's Linux stack and a kernelet stack), `klet_run_on_linux_stack`, the yield stub and the eviction exit stub | 6, 10, 11 |
| `image_start.S`, `image_end.S` | the two symbols that bracket the image's text, which the watch timer and the sweep use to tell kernelet code from everything else | 3, 11 |

Build products (`*.o`, `*.ko`, `image.o_shipped`, Kbuild's own files) are
not in the repository.
