# Carriers

The gate attaches a hook to a Linux task. This chapter is about those tasks: where they come from, what they inherit, and how the endovisor learns when one dies. The word for them is the book's first Linux-specific term.

A **carrier** is a Linux task that runs a kernelet's code and enters user mode on the kernelet's behalf. Linux schedules carriers like any tasks; it does not know what they carry. A sandbox has a fixed number of carriers, chosen when it is created: one **root carrier**, which never runs kernelet code, and one carrier per **virtual CPU**, each of which is one of the processors the kernelet believes it has. Chapter 8 says what a virtual CPU is in full; for now, a sandbox with one virtual CPU, like the hundred-line kernel's, has a root carrier and one other.

## Why a carrier is not a kernel thread

Linux has a kind of task that runs only kernel code, the *kernel thread*, and it is the natural first thought for "a task that runs the kernelet". It is the wrong one. A kernel thread has no user address space and can never return to user mode, and a carrier must: entering user mode to run the tenant's program is the one thing the kernelet cannot do for itself. So a carrier is an ordinary user task, with an address space and a `pt_regs`, which happens to spend most of its time in kernel mode.

<div class="linux">

**Linux: how tasks are made.** Every task is created by one function, [`kernel_clone()`](https://elixir.bootlin.com/linux/v6.12/source/kernel/fork.c#L2745), which underlies `fork`, `clone` and kernel-thread creation. It copies the parent's task structure and then, depending on flags, shares or copies the address space, open files and so on. Called with a function pointer in its arguments and *without* the kernel-thread flag, it makes a task that starts in that function in kernel mode and, when the function returns, continues to user mode with whatever is in its saved registers. That is how Linux itself starts `init`. The function is not exported to modules; the patch exports it.

The other way to give a task a fresh address space is [`execve`](https://elixir.bootlin.com/linux/v6.12/source/fs/exec.c#L1222): Linux offers the file to each registered **binary-format handler** ([`struct linux_binfmt`](https://elixir.bootlin.com/linux/v6.12/source/include/linux/binfmts.h#L82)) in turn, and the one that recognizes the file replaces the process's address space and sets its starting registers. A module can register a handler of its own.

</div>

## The root carrier is born by exec

The endovisor registers a binary-format handler for files that begin with the four bytes `KLET`. A **sandbox file** is such a file: the magic, an ABI version, the number of virtual CPUs, and a command line for the kernel. The *kernelet runtime*, the host program that creates sandboxes, is in this prototype a tiny C program that forks a child, drops the child's ability to gain privileges, and executes the sandbox file:

*Simplified from `prototype/runtime/run-hello.c`: `main`.*

```c
pid = fork();
if (pid == 0) {
	prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
	execve("/hello.klet", argv, envp);
	_exit(127);
}
waitpid(pid, &status, 0);          /* until the sandbox has ended */
```

Everything the runtime set up on that child before the `execve`, such as its control group, its user identity and its seccomp filter, is inherited by every carrier, because every carrier descends from it. The prototype sets only the one `prctl`; a real runtime would set them all.

The handler is where the child becomes the root carrier:

*Simplified from `prototype/endovisor/main.c`: `klet_load_binary`, `klet_empty_mm`.*

```c
static int klet_load_binary(struct linux_binprm *bprm)
{
	klet_read_config(inst, bprm, &nr_vcpus);   /* the magic, the version, the vCPU count */

	begin_new_exec(bprm);                       /* a fresh, empty address space; signal handlers reset */
	klet_personality_64bit();
	setup_new_exec(bprm);
	klet_empty_mm();                            /* unmap the one area exec left: the argument stack */
	set_binfmt(&klet_format);
	finalize_exec(bprm);

	start_thread(current_pt_regs(), 0, 0);      /* valid 64-bit user registers, even though it never uses them */

	root = klet_carrier_new(inst, KLET_ROOT, -1);
	klet_carrier_attach(root);                  /* install the gate and the lifeline */
	kernel_sigaction(SIGCHLD, SIG_IGN);         /* children are reaped without a wait */

	set_thread_flag(TIF_NOTIFY_RESUME);         /* make the resume hook run on the way out */
	return 0;
}
```

Each line does what any program loader does, with one difference. The ELF loader would now map the program and its stack into the new address space; this handler maps nothing, and even unmaps the temporary page that holds the `execve` arguments, so that the address space is empty. Nothing of the host's is left in it for a tenant to read.

The call to `start_thread` looks pointless for a task that will never run user code, and is not: a task cloned from this one copies its saved registers, segment selectors and flags included, and those clones *will* run user code. The root carrier's registers are the template.

The last line is the handoff. The root carrier returns from the handler and heads for user mode, as every `execve` does. On the way it passes through the exit loop, and because the flag is set, the gate's resume hook runs. For the root carrier that hook never returns: it is where the root carrier does its work.

## The root carrier starts the others

*Simplified from `prototype/endovisor/carrier.c`: `klet_root_loop`, `klet_spawn_vcpu`.*

```c
static void klet_root_loop(struct klet_carrier *root)
{
	for (i = 0; i < inst->nr_vcpus; i++)
		klet_spawn_vcpu(inst, i);

	for (;;) {                                   /* then stay alive until the sandbox ends */
		wait_event_interruptible(inst->root_wq,
			inst->stopped || inst->dying || fatal_signal_pending(current));
		if (inst->stopped || inst->dying || fatal_signal_pending(current))
			break;
		klet_drain_signals(root);                /* discard anything but SIGKILL */
	}
	klet_carrier_die(root);
}

static int klet_spawn_vcpu(struct klet_inst *inst, int vcpu)
{
	struct kernel_clone_args args = {
		.flags = CLONE_UNTRACED,
		.exit_signal = SIGCHLD,
		.fn = klet_carrier_main,                 /* the child starts here, in kernel mode */
		.fn_arg = (void *)(long)vcpu,
	};
	return kernel_clone(&args) >= 0 ? 0 : -EAGAIN;
}
```

Each clone is a separate process, not a thread: no `CLONE_VM`, no `CLONE_FILES`, no `CLONE_THREAD`. It gets a *copy* of the root's empty address space, a copy of its descriptor table, and, because Linux copies the task structure, the root's gate pointer, syscall-work bit, control group, credentials and seccomp filter. The endovisor sets none of those up per carrier; `fork` does.

```mermaid
flowchart TB
    rt["kernelet runtime<br/>(run-hello)"] -- "fork + execve(/hello.klet)" --> root["root carrier<br/>(the binary-format handler claimed it)<br/>never runs kernelet code"]
    root -- "kernel_clone(.fn = klet_carrier_main)" --> v0["carrier of virtual CPU 0<br/>enters the image at kernelet_entry"]
    root -- "kernel_clone(...)" --> v1["carrier of virtual CPU 1<br/>waits for vcpu_boot"]
    subgraph inherited["inherited by every clone, because Linux copies it"]
        direction LR
        i1[gate pointer] --- i2[empty address space] --- i3[control group] --- i4[seccomp filter] --- i5[lifeline, see below]
    end
```

The child's start function builds the carrier's record and enters the kernelet:

*Simplified from `prototype/endovisor/carrier.c`: `klet_carrier_main`.*

```c
static int klet_carrier_main(void *arg)
{
	int vcpu = (int)(long)arg;

	close_fd(inst->root_lifeline_fd);           /* the inherited copy of the root's lifeline */
	c = klet_carrier_new(inst, KLET_VCPU, vcpu);
	klet_carrier_attach(c);                     /* this task's own gate record and lifeline */
	c->blank_mm = current->mm;                  /* keep a reference to the empty address space */
	inst->vcpus[vcpu] = c;

	if (vcpu != 0)                              /* virtual CPU 0 boots; the others wait to be started */
		wait_event_interruptible(c->idle_wq, c->boot_requested || inst->dying);

	klet_enter(c, KLET_RUN_EVENT);              /* switch to a kernelet stack and run kernelet code */

	set_thread_flag(TIF_NOTIFY_RESUME);         /* when the kernelet first wants user mode: the resume hook applies the registers */
	return 0;
}
```

`klet_enter` is the subject of the next chapter. For virtual CPU 0 it leads to `kernelet_entry` from chapter 3, and so to the kernel proper's `main`. The carrier returns from `klet_enter` only when the kernelet has asked to run a user program, and then the function returns, Linux's fork-return path takes the task to user mode, and the resume hook, requested by the flag, puts the right registers in place first.

## Lifelines

A carrier can die without the endovisor's involvement: the operator kills it, or Linux's out-of-memory killer does. Losing a carrier is losing a processor with whatever the kernelet was doing on it, and the sandbox cannot continue. The endovisor needs to *hear* of the death, however it happened, and Linux offers a clean way.

<div class="linux">

**Linux: descriptors and release.** Every process has a table of open file descriptors. When a task exits for any reason, Linux closes them all, and when the last reference to an open file goes, the file's `release` operation runs. A module can make an open file of its own with [`anon_inode_getfile()`](https://elixir.bootlin.com/linux/v6.12/source/fs/anon_inodes.c#L148), with whatever operations it likes.

</div>

So each carrier holds, in its descriptor table, one open file of the endovisor's that nothing ever reads or writes: its **lifeline**. Its `release` is the death notice.

*Simplified from `prototype/endovisor/carrier.c` and `prototype/endovisor/main.c`: `klet_carrier_attach`, `klet_lifeline_release`.*

```c
int klet_carrier_attach(struct klet_carrier *c)
{
	struct file *file = anon_inode_getfile("[kernelet-carrier]", &klet_lifeline_fops, c, O_RDWR);
	int fd = get_unused_fd_flags(0);
	fd_install(fd, file);

	current->kernelet = &c->gate;               /* attach the gate ... */
	set_syscall_work(KERNELET);                 /* ... and ask for the syscall hook */
	return 0;
}

static int klet_lifeline_release(struct inode *inode, struct file *file)
{
	klet_carrier_lifeline_closed(file->private_data);   /* the carrier is gone */
	return 0;
}
```

A clone starts with a copy of its parent's descriptor table, which is why `klet_carrier_main` closes the inherited copy of the root's lifeline first: otherwise the root's death notice would wait until the last carrier died. A tenant cannot close a lifeline, because closing a descriptor is a Linux system call, and the gate takes those.

When a lifeline closes, the endovisor takes the carrier off its lists. If it was the *root's* lifeline, the sandbox is over: the endovisor marks the kernelet dying and ends every other carrier, which is chapter 11.

<div class="recap">

**Recap.** A carrier is an ordinary Linux user task that runs kernelet code and enters user mode for it. The root carrier is made by `execve` of a sandbox file, which the endovisor's binary-format handler claims, giving it an empty address space and the gate; it never runs user code and it never returns from the resume hook. It clones one carrier per virtual CPU with `kernel_clone`, and each clone inherits the gate, the empty address space, the control group and the seccomp filter by the ordinary rules of `fork`. Every carrier holds a lifeline, an open file whose release tells the endovisor that the carrier has died.

</div>
