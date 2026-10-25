# Carriers

Chapter 5 attached two hooks to a Linux task. This chapter is about those tasks: where they come from, what they inherit, and how the endovisor learns when one dies.

A **carrier** is a Linux task that carries one of a sandbox's virtual CPUs: it runs the kernelet's code and enters user mode on the kernelet's behalf, and a virtual CPU is one of the processors the kernelet believes it has. Linux schedules carriers like any tasks; it does not know what they carry. A sandbox has a fixed number of them, one per virtual CPU, chosen when it is created, and nothing else of the sandbox is a task: the holder of chapter 2, which created the sandbox, is a process of the runtime and runs no kernelet code. Chapter 9 says what a virtual CPU is in full; for now, a sandbox with one virtual CPU, like the hundred-line kernel's, has one carrier.

## Why a carrier is not a kernel thread

Linux has a kind of task that runs only kernel code, the *kernel thread*, and it is the natural first thought for "a task that runs the kernelet". It is the wrong one. A kernel thread has no user address space and can never return to user mode, and a carrier must: entering user mode to run the tenant's program is the one thing the kernelet cannot do for itself. So a carrier is an ordinary user task, with an address space and a `pt_regs`, which happens to spend most of its time in kernel mode.

<div class="linux">

**Linux: how tasks are made.** Almost every task is created by one function, [`kernel_clone()`](https://elixir.bootlin.com/linux/v6.12/source/kernel/fork.c#L2745), which underlies `fork`, `clone` and kernel-thread creation. It copies the parent's task structure and then, depending on flags, shares or copies the address space, open files and so on. A child made by `fork` is therefore a copy of its parent in every property Linux keeps on the task: control group, credentials, namespaces, processor mask, priority, resource limits, seccomp filter, and the hooks pointer the patch added. The other way to give a task a fresh address space is [`execve`](https://elixir.bootlin.com/linux/v6.12/source/fs/exec.c#L2097): Linux offers the file to each registered **binary-format handler** ([`struct linux_binfmt`](https://elixir.bootlin.com/linux/v6.12/source/include/linux/binfmts.h#L82)) in turn, and the one that recognizes the file replaces the process's address space and sets its starting registers. A module can register a handler of its own. What `exec` keeps of the task and what it resets is the box of chapter 2.

</div>

## A carrier is born by fork and exec

Chapter 2 showed the user-space half. For each virtual CPU the holder asks the sandbox for an exec descriptor, forks a child, and the child, after arranging itself with ordinary system calls, executes the descriptor with `execveat`. Everything the child set on itself before the exec is what the carrier has, because `exec` keeps the task's properties and replaces only its program: its control group, which the holder joined before creating the sandbox; its processor mask and priority; its seccomp filter, if the runtime installed one. The prototype's holder sets the no-new-privileges bit, which the endovisor insists on, and whatever its options ask for.

<div class="linux">

**Linux: control groups.** A control group is a set of tasks that Linux accounts and limits together: their share of the processors, their memory, and more. A child starts in its parent's group, and `exec` does not change it. Containers are built on them, and so is a sandbox: `KLET_CREATE` records the holder's group, the exec of an exec descriptor is refused from any other group, and because every carrier is in the sandbox's group, the processor time the kernelet burns is charged to the tenant by machinery Linux already has, and so is any memory allocated on a carrier with the flag that asks for it (`__GFP_ACCOUNT`). Linux charges the tenant's page tables that way by itself, to the carrier whose fault or mapping causes them; the endovisor charges the grant, the pages of the kernelet's stacks and its heap with the same flag (`GFP_KERNEL_ACCOUNT`), all of them allocated on a carrier of the sandbox.

</div>

<div class="linux">

**Linux: `TIF_NOTIFY_RESUME`.** Linux enters the exit loop of chapter 5, and so runs the resume hook, only if the task has a work flag set (chapter 5's box). So the hook runs for every kind of exit work, not only the kernelet's, and must be written to find nothing of its own to do. Kernel code that wants the loop to run sets the flag [`TIF_NOTIFY_RESUME`](https://elixir.bootlin.com/linux/v6.12/source/arch/x86/include/asm/thread_info.h#L87) on the task: a plain flag-set on the current task, or `set_notify_resume()` on another, which also nudges the processor that task is on. The book says the endovisor *flags the carrier* when it means this.

</div>

The endovisor's half is the binary-format handler, where the child becomes the carrier:

*Simplified from `prototype/linux/endovisor/main.c`: `klet_load_binary`, `klet_empty_mm`, `klet_ignore_signals`.*

```c
static int klet_load_binary(struct linux_binprm *bprm)
{
	if (memcmp(bprm->buf, KLET_EXEC_MAGIC, KLET_EXEC_MAGIC_LEN) != 0)
		return -ENOEXEC;                        /* not ours: the next handler's turn */
	inst = klet_exec_lookup(bprm, &vcpu);       /* which sandbox and virtual CPU, by the file's inode */
	if (!inst)
		return -ENOEXEC;
	err = klet_exec_claim(inst, vcpu);          /* not killed; not started; the sandbox's group; no new privileges */
	if (err)
		return err;                             /* ESRCH, EBUSY or EPERM: the exec fails and the process lives on */

	begin_new_exec(bprm);                       /* the point of no return: a fresh address space, signal handlers reset */
	klet_personality_64bit();
	setup_new_exec(bprm);
	klet_empty_mm();                            /* unmap the one area exec left: the argument stack */
	set_binfmt(&klet_format);
	finalize_exec(bprm);
	start_thread(current_pt_regs(), 0, 0);      /* valid 64-bit user registers, though it never uses them */
	klet_ignore_signals();                      /* every signal that can be ignored is: chapter 8 says why */
	set_mask_bits(&current->mm->flags, MMF_DUMPABLE_MASK, SUID_DUMP_DISABLE);   /* not dumpable, whoever the holder is */
	snprintf(comm, sizeof(comm), "kernelet/%d/%u", inst->slot, vcpu);          /* the name ps shows */
	strscpy_pad(current->comm, comm, sizeof(current->comm));

	c = klet_carrier_new(inst, vcpu);
	klet_carrier_attach(c);                     /* the hooks and the lifeline */
	mmget(current->mm);                         /* keep a reference to the empty address space ... */
	c->blank_mm = current->mm;                  /* ... which chapter 13 drops when a tenant's replaces it */
	inst->vcpus[vcpu] = c;

	if (!inst->started)                         /* the first arrival starts the sandbox: */
		klet_sandbox_start(inst);               /* the image's data restored, the grant, the boot arguments */
	inst->arrived++;
	wake_up_all(&inst->arrive_wq);              /* virtual CPU 0 may be waiting for this one */

	set_thread_flag(TIF_NOTIFY_RESUME);         /* make the resume hook run on the way out */
	return 0;
}
```

Each line does what any program loader does, with one difference. The ELF loader would now map the program and its stack into the new address space; this handler maps nothing, and even unmaps the temporary page that holds the `execveat` arguments, so that the address space is empty. Nothing of the host's is left in it for a tenant to read.

Two lines undo what the holder's identity would otherwise leave. Linux makes a process that executed a file it cannot read non-dumpable, but root can read an execute-only file, so for a root holder the rule would leave the carrier dumpable; the handler clears the dumpable bits itself, for the carrier and, later, for every address space the kernelet creates. And `start_thread` gives the task a valid 64-bit user register frame, as every loader must; the resume hook will overwrite it before the task ever reaches user mode.

The last line is the handoff. The carrier returns from the handler and heads for user mode, as every `execve` does. On the way it passes through the exit loop, and because the flag is set, the resume hook runs. The carrier never arrives in user mode on its own account: from here on it goes there only when the kernelet sends it.

```mermaid
flowchart TB
    h["the holder<br/>(a process of the runtime)"] -- "fork" --> ch["a child: pins itself,<br/>sets no-new-privileges,<br/>installs a filter if asked"]
    ch -- "execveat(exec fd i)" --> hd["the binary-format handler:<br/>checks the group and the bit,<br/>empties the address space"]
    hd --> c["the carrier of virtual CPU i<br/>named kernelet/slot/i"]
    subgraph kept["kept across the exec, because they belong to the task"]
        direction TB
        k1[control group] --- k2[seccomp filter] --- k3[processor mask, priority] --- k4[credentials, namespaces]
    end
    subgraph set["set by the handler"]
        direction TB
        s1["an empty address space"] --- s2["every signal ignored"] --- s3["not dumpable"] --- s4["the hooks pointer and a lifeline"]
    end
    ch -.-> kept
    hd -.-> set
```

## Entering the kernelet

The resume hook is where a new carrier enters the kernelet, once every carrier of the sandbox has arrived. Its first trip through the hook finds the carrier in the state `NEW`:

*Simplified from `prototype/linux/endovisor/carrier.c`: `klet_on_resume`, `klet_vcpu_await`.*

```c
		if (c->state == KLET_NEW) {                 /* the carrier's first way out to user mode, from the exec */
			if (!klet_vcpu_await(c)) {              /* wait until this virtual CPU may enter the image */
				klet_carrier_die(c);                /* the sandbox died while it waited */
				return;
			}
			klet_enter(c, KLET_RUN_EVENT);          /* switch to a kernelet stack and run kernelet code */
			continue;
		}

static bool klet_vcpu_await(struct klet_carrier *c)
{
	if (c->vcpu == 0)                           /* virtual CPU 0 boots the kernelet, once every carrier has arrived */
		wait_event_state(inst->arrive_wq, inst->arrived == inst->nr_vcpus || inst->dying,
				 TASK_KILLABLE | TASK_NOLOAD);
	else                                        /* the others wait for the kernel proper to start their processor */
		wait_event_state(c->idle_wq, c->boot_requested || inst->dying,
				 TASK_KILLABLE | TASK_NOLOAD);
	return !inst->dying && (c->vcpu == 0 ? inst->arrived == inst->nr_vcpus : c->boot_requested);
}
```

The kernelet boots only when every virtual CPU's carrier has arrived, because a kernel that starts its other processors expects each of them to answer. `wait_event_state` is Linux's ordinary way to sleep until a condition holds: a waker *wakes* the queue the sleeper named, and the sleeper checks its condition again. The sleep is *killable*, ended only by `SIGKILL`, because a `SIGSTOP` sent to a carrier stays pending until the carrier next heads for user mode (chapter 8) and must not end the wait early; and *no-load*, so that a waiting carrier is not counted in the load average.

`klet_enter` is the subject of the next chapter. For virtual CPU 0 it leads to `kernelet_entry` from chapter 4, and so to the kernel proper's `main`; for the others, to `vcpu_entry`, once the kernel proper has asked for that processor through the service `vcpu_boot`. The carrier returns from `klet_enter` only when the kernelet has asked to run a user program, and then the hook's loop puts the right registers in place and lets Linux return to user mode, which is chapter 8.

## Lifelines

A carrier can die without the endovisor's involvement: the operator kills it, or Linux's out-of-memory killer does. Losing a carrier is losing a processor with whatever the kernelet was doing on it, and the sandbox cannot continue. The endovisor needs to *hear* of the death, however it happened, and Linux offers a clean way.

<div class="linux">

**Linux: descriptors and release.** Every process has a table of open file descriptors. When a task exits for any reason, Linux closes them all, and when the last reference to an open file goes, the file's `release` operation runs. A module can make an open file of its own with [`anon_inode_getfile()`](https://elixir.bootlin.com/linux/v6.12/source/fs/anon_inodes.c#L143), with whatever operations it likes.

</div>

So each carrier holds, in its descriptor table, one open file of the endovisor's that nothing ever reads or writes: its **lifeline**. Its `release` is the death notice.

*Simplified from `prototype/linux/endovisor/carrier.c` and `prototype/linux/endovisor/main.c`: `klet_carrier_attach`, `klet_lifeline_release`.*

```c
int klet_carrier_attach(struct klet_carrier *c)
{
	struct file *file = anon_inode_getfile("[kernelet-carrier]", &klet_lifeline_fops, c, O_RDWR);
	int fd = get_unused_fd_flags(0);
	fd_install(fd, file);                       /* into this task's own table: the exec gave it a fresh one */

	current->carrier_hooks = &c->hooks;         /* attach the hooks ... */
	set_syscall_work(KERNELET);                 /* ... and ask for the syscall hook */
	return 0;
}

static int klet_lifeline_release(struct inode *inode, struct file *file)
{
	klet_carrier_lifeline_closed(file->private_data);   /* the carrier is gone */
	return 0;
}
```

The lifeline is installed after the `exec`, so no other task holds a copy of it: the holder's descriptors were the child's before the exec, and the child's table is its own. A tenant cannot close a lifeline, because closing a descriptor is a Linux system call, and the syscall hook takes those.

When a lifeline closes, the endovisor takes the carrier off its lists. If the sandbox was still running, whichever carrier's lifeline it was, the sandbox is over: the endovisor marks the kernelet dying and ends every other carrier, which is chapter 12. When the last lifeline closes, no carrier is left and the sandbox has exited, which is what the holder's `KLET_WAIT` was waiting for.

<div class="recap">

**Recap.** A carrier is an ordinary Linux user task that runs kernelet code and enters user mode for it. The holder forks one child per virtual CPU, and each child executes that virtual CPU's exec descriptor, which the endovisor's binary-format handler claims: it checks the child's control group and its no-new-privileges bit, gives it an empty address space, ignores every signal that can be ignored, makes it non-dumpable, names it, and attaches the hooks and a lifeline. The child keeps what it set on itself before the exec, by the ordinary rules of `exec`. On its way out the resume hook holds it until every carrier has arrived, then enters the kernelet. Every carrier holds a lifeline, an open file whose release tells the endovisor that the carrier has died.

</div>
