# The kernelet UAPI

Before any mechanism, the view from the host's user space. Linux calls the set of system calls, device nodes and file formats that user space may use its **UAPI**, the user-space application programming interface, and keeps the headers that define it in a directory of that name. A kernelet's is one header, `prototype/linux/endovisor/uapi/kernelet.h`: one device node, three kinds of file descriptor, and one rule about who creates the tasks.

This chapter first shows the interface in use, by the prototype's own holder program, then says why it has the shape it has, and then specifies every operation. Everything the rest of the book builds is behind this interface, and nothing a tenant does ever touches it.

## Creating a sandbox

The program that drives a sandbox is its **holder**: the one process of the kernelet runtime that creates the sandbox, keeps its descriptor open for as long as the sandbox lives, and destroys it. A container runtime has such a process per container; the prototype's is `holder.c`, a static C program of two commands, `register` and `run`.

<div class="linux">

**Linux: device nodes and `ioctl`.** A *device node* is a file under `/dev` that stands for a driver rather than for data; opening it gives a descriptor on which the driver answers `read`, `write` and, for everything that is neither, [`ioctl`](https://elixir.bootlin.com/linux/v6.12/source/fs/ioctl.c#L893): one system call that takes a descriptor, a command number and an argument, and hands both to whatever code is behind the descriptor. A driver's interface is therefore a list of command numbers, and a module may define its own. A descriptor need not come from a file system at all: a module can make an *anonymous* file, with operations of its choosing, and hand out a descriptor on it; every descriptor in this chapter but the first is one of those.

</div>

**The operator's step.** Once per boot, someone with the right to load kernel code registers each kernelet image the machine will run, and names it:

*Simplified from `prototype/host/runtime/holder.c`: `open_system`, `register_kind`.*

```c
static int open_system(void)
{
	int sys = open("/dev/kernelet", O_RDWR | O_CLOEXEC);

	if (ioctl(sys, KERNELET_GET_API_VERSION) != KERNELET_API_VERSION)
		exit(127);                                  /* an interface this program does not know */
	return sys;
}

static int register_kind(int sys, const char *name, const char *image_path)
{
	struct kernelet_kind_register reg = { .image_fd = open(image_path, O_RDONLY | O_CLOEXEC) };

	snprintf(reg.name, sizeof(reg.name), "%s", name);
	return ioctl(sys, KERNELET_KIND_REGISTER, &reg);    /* the kind's identifier */
}
```

A registered image is a **kind**, and a kind is what sandboxes are made of. Registering it is the privileged act, and it happens once; creating sandboxes of it is not privileged and happens as often as the runtime likes.

**The holder's step.** To run a sandbox, the holder creates it, gives it its console and log, and then makes one carrier per virtual CPU:

*Simplified from `prototype/host/runtime/holder.c`: `run_sandbox`.*

```c
static int run_sandbox(int sys, const char *name, unsigned int nr_vcpus, const char *cmdline,
		       const char *cgroup, int pin)
{
	struct kernelet_create create = {
		.kind = find_kind(sys, name),               /* KERNELET_KIND_LIST, matched by name */
		.nr_vcpus = nr_vcpus,
		.memory_initial = 4 << 20,
		.memory_max = 64 << 20,
		.max_tasks = 256,
		.cmdline = (__u64)(unsigned long)cmdline,
		.cmdline_len = strlen(cmdline),
	};
	struct kernelet_exit ex;
	int sb, out = 1, err = 2;

	if (cgroup)
		join_cgroup(cgroup);                        /* before the create: this group becomes the sandbox's */
	sb = ioctl(sys, KERNELET_CREATE, &create);      /* the sandbox descriptor */
	ioctl(sb, KERNELET_SET_CONSOLE, &out);          /* the sandbox's console: our standard output */
	ioctl(sb, KERNELET_SET_LOG, &err);              /* its kernel log: our standard error */
	/* a disk would be attached here: KERNELET_ATTACH_DEVICE with its open file */

	for (i = 0; i < nr_vcpus; i++) {
		int exec_fd = ioctl(sb, KERNELET_VCPU_GET_EXEC_FD, &i);

		pids[i] = fork();
		if (pids[i] == 0)
			start_carrier(exec_fd, i, pin);         /* the child; does not return */
		close(exec_fd);
	}

	ioctl(sb, KERNELET_WAIT, &ex);                  /* until the sandbox has ended */
	for (i = 0; i < nr_vcpus; i++)
		waitpid(pids[i], NULL, 0);                  /* the carriers died by SIGKILL */
	ioctl(sb, KERNELET_DESTROY);
	close(sb);
	return ex.how == KERNELET_END_EXITED ? ex.code : 128;
}
```

The loop in the middle is the heart of the interface. A **carrier**, chapter 1's term for a Linux task that carries one of the sandbox's virtual CPUs, is not made by the kernel. The holder forks a child for it, the child arranges itself with ordinary system calls, and then the child *executes* a descriptor the sandbox handed out:

*Simplified from `prototype/host/runtime/holder.c`: `start_carrier`, `join_cgroup`.*

```c
static void start_carrier(int exec_fd, unsigned int vcpu, int pin)
{
	char *argv[] = { "carrier", NULL }, *envp[] = { NULL };

	if (pin) {                                      /* virtual CPU i on processor i */
		cpu_set_t set;
		CPU_ZERO(&set);
		CPU_SET(vcpu, &set);
		sched_setaffinity(0, sizeof(set), &set);
	}
	prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);         /* the endovisor insists on it */
	execveat(exec_fd, "", argv, envp, AT_EMPTY_PATH);   /* the endovisor takes it from here */
}

static void join_cgroup(const char *dir)             /* write our process identifier into cgroup.procs */
{
	snprintf(path, sizeof(path), "%s/cgroup.procs", dir);
	fd = open(path, O_WRONLY | O_CLOEXEC);
	n = snprintf(pid, sizeof(pid), "%d\n", getpid());
	write(fd, pid, n);
	close(fd);
}
```

Between the `fork` and the `execveat` the child is an ordinary process of the holder's user, and anything Linux lets a process set on itself can go there: the processor it is pinned to, as here; its priority or scheduling class; the user it runs as; the namespaces it is in; its resource limits; a seccomp filter (chapter 5 says what the filter is for). All of it survives the `exec`, for a reason the next section gives, and all of it is per carrier, so two virtual CPUs can be pinned to two processors and given two priorities.

<div class="linux">

**Linux: control groups.** A control group is a set of tasks that Linux accounts and limits together: their share of the processors, their memory, and more. A task joins a group when its process identifier is written into the group's `cgroup.procs` file, and a child starts in its parent's group. Containers are built on them, and so is a sandbox: because every task of the sandbox is in the sandbox's group, the processor time the kernelet burns and the memory Linux allocates for it are charged to the tenant by machinery Linux already has.

</div>

The whole life of a sandbox, then, in order:

1. When the machine is set up, the operator registers each kind with `KERNELET_KIND_REGISTER`.
2. The runtime makes a control group for the sandbox with the limits the operator chose, and starts the holder in it.
3. The holder creates the sandbox with `KERNELET_CREATE`, opens the disk image and whatever else the sandbox is to have and passes each with `KERNELET_ATTACH_DEVICE`, and passes its console and log with `KERNELET_SET_CONSOLE` and `KERNELET_SET_LOG`.
4. For each virtual CPU, the holder asks for the exec descriptor with `KERNELET_VCPU_GET_EXEC_FD` and forks a child, which arranges itself and executes the descriptor. The first of those `exec`s loads the kind's image as this sandbox's instance and gives the kernelet its memory, charged to the group. When the last carrier has arrived, the carrier of virtual CPU 0 enters the image and the kernel proper boots; the others wait until the kernel proper starts their processor (`vcpu_boot`, chapter 9).
5. The sandbox runs. Linux schedules each carrier with the processors and the class its creator gave it; the kernelet schedules its own tasks on them (chapter 9).
6. The kernel proper powers off, or the holder calls `KERNELET_KILL`, or a carrier is killed. The endovisor stops every carrier (chapter 12) and records why. The holder's `KERNELET_WAIT` returns, it reaps the carriers, calls `KERNELET_DESTROY`, and exits; the runtime removes the group.

```mermaid
flowchart TB
    h["the holder<br/>(a process of the kernelet runtime, in the sandbox's control group)<br/>holds the sandbox descriptor"]
    h -- "fork; pin, renice, filter;<br/>execveat(exec fd 0)" --> c0["kernelet/7/0<br/>the carrier of virtual CPU 0<br/>enters the image"]
    h -- "fork; ...; execveat(exec fd 1)" --> c1["kernelet/7/1<br/>the carrier of virtual CPU 1<br/>waits for vcpu_boot"]
```

What the operator sees on the host is that figure: a control group containing the holder and one process per virtual CPU, named `kernelet/<sandbox>/<i>`, all children of the holder. `ps` and `top` list them; `taskset` and `chrt` move a virtual CPU to other processors or change its class while the sandbox runs; `perf` profiles one; `kill -KILL` on any of them ends the sandbox, as does `cgroup.kill` on the group. Nothing in the group corresponds to the tenant's own processes, which only the kernelet knows about.

## Why it is shaped so

Four things the interface has to allow decide its shape.

1. **Every Linux task of a sandbox is created by user space, and user space can find it and govern it with Linux's own system calls.** A carrier is a special task, since its system calls go to the kernelet and not to Linux (chapter 5), but it is still a task, and the host's tools for tasks, `sched_setaffinity`, `setpriority`, `sched_setattr`, control groups, namespaces, resource limits, `perf`, `/proc`, must apply to it as to any other. They can only apply to a task that user space made and knows.
2. **Resources reach a sandbox as descriptors.** A disk image, a network interface, a console and a log file are things the runtime opens itself, under its own user's permissions, and passes down. Nothing is named by path inside the kernel, and a sandbox can reach exactly what its runtime could open.
3. **An image is kernel code.** Loading one is allowed to whoever may load a module; creating a sandbox of a loaded image is allowed to whoever may open the device. And one copy of an image's code serves every sandbox of it.
4. **A sandbox dies whole, and dies with its runtime.** Nothing a crashed runtime held keeps a sandbox alive.

**The model is KVM.** Linux has one interface that meets the first, second and fourth already, and it is the one to copy. KVM, Linux's hypervisor, is a module that runs virtual machines whose virtual processors are ordinary user threads: a program such as QEMU opens `/dev/kvm`, asks it for a descriptor that stands for a virtual machine, asks that for a descriptor per virtual processor, and runs each virtual processor from a thread of its own by calling an operation on its descriptor ([`KVM_CREATE_VM`](https://elixir.bootlin.com/linux/v6.12/source/Documentation/virt/kvm/api.rst#L138), [`KVM_CREATE_VCPU`](https://elixir.bootlin.com/linux/v6.12/source/Documentation/virt/kvm/api.rst#L294), [`KVM_RUN`](https://elixir.bootlin.com/linux/v6.12/source/Documentation/virt/kvm/api.rst#L379)). The threads are QEMU's: it created them, it can pin them and renice them, `ps` shows them, and the machine dies when QEMU does, because closing the last descriptor destroys it. A kernelet's interface has the same three levels: a system descriptor, a sandbox descriptor, and a descriptor per virtual CPU, each made from the one above it.

```mermaid
flowchart TB
    dev["/dev/kernelet<br/>the system descriptor"] -- "KERNELET_CREATE" --> sb["a sandbox descriptor<br/>held by the sandbox's holder"]
    dev -- "KERNELET_KIND_REGISTER<br/>(needs the right to load kernel code)" --> kind["a kind: one image,<br/>its code shared by every sandbox of it"]
    sb -- "KERNELET_VCPU_GET_EXEC_FD(i)" --> ex["an exec descriptor<br/>for virtual CPU i, used once"]
    ex -- "fork, configure, execveat" --> car["the carrier of virtual CPU i<br/>a child of the holder"]
```

**Why a carrier is made by `exec` and not by a call.** This is the one place the two interfaces differ. A KVM virtual processor is run by a thread that *calls* `KVM_RUN` and returns from it, keeping its own address space throughout; the guest's memory is elsewhere, in a mapping the thread set up. A carrier runs the tenant's program in Linux's own user mode, on Linux's own page tables (chapter 13), so the carrier's address space *is* the tenant's, and it must start holding nothing of the host's: not the holder's program, not its heap, not a stack with the holder's secrets on it. The one operation in Linux that gives a process a fresh address space is `execve`. So the per-virtual-CPU descriptor is not called; it is executed. It is a small file that lives only in memory, created by the endovisor with [`shmem_file_setup()`](https://elixir.bootlin.com/linux/v6.12/source/mm/shmem.c#L5265), that the endovisor recognizes when it is executed *by the file object*, not by anything written in it; possession of the descriptor is the right to start that virtual CPU, once.

<div class="linux">

**Linux: what `exec` keeps.** A new program gets a new address space, and [`begin_new_exec()`](https://elixir.bootlin.com/linux/v6.12/source/fs/exec.c#L1222) resets what belongs to the old one: signal handlers, timers, the descriptors marked close-on-exec, and a few registrations by which Linux would later write into user memory. It does *not* touch the task's control group, credentials, namespaces, processor mask, priority, resource limits, the no-new-privileges bit or the seccomp filter; those are properties of the task, not of the program, and the two last are kept by design so that a program cannot shed them by executing another. That is what makes the holder's child work: everything it set on itself is still set when the endovisor sees it.

</div>

Linux lets a module teach it a new executable format, and the endovisor registers one for exec descriptors; chapter 6 reads the handler line by line. Offered the file, it checks that the sandbox has been created and not killed, that this virtual CPU has not been started already, that the executing process is in the sandbox's control group, and that it has *no new privileges* set and gains none by this `exec`. Then it does what every program loader does, with one difference: it gives the process a fresh address space and maps *nothing* into it, not even the program's arguments. It marks the task as a carrier, by the one pointer chapter 5 adds to Linux's task structure, gives it a **lifeline**, an open file by whose closing the endovisor will learn that the carrier has died (chapter 6), and names it `kernelet/<sandbox>/<i>` so that `ps` shows which sandbox and which virtual CPU it is. The carrier never reaches the user mode the `exec` was heading for: on the way there the endovisor takes it, and from then on the task is the kernelet's, to run kernelet code on and to enter user mode from on the kernelet's behalf (chapters 6 to 8).

Two consequences of `exec` are worth having. The exec descriptor's file can be executed but not read, and Linux's rule is that a process which has executed a file it cannot read is not *dumpable*: nobody of the same user may attach a debugger to it or read its memory through `/proc` ([`begin_new_exec()`](https://elixir.bootlin.com/linux/v6.12/source/fs/exec.c#L1342) applies the rule). A tenant's memory is reachable from a carrier's `/proc` entries, so this is what keeps one sandbox's user from reading it, and it costs nothing to arrange; root can still attach, as root can read any container's memory. And since the carrier arrived by a system call rather than by being cloned inside the kernel, its first trip to user mode needs nothing special: the resume hook that takes it (chapter 5) overwrites the registers Linux saved, as it will on every later trip.

**The holder is the sandbox's anchor.** The fourth requirement and the first together put four things on the holder.

- **The sandbox's control group is the holder's.** `KERNELET_CREATE` records the calling task's control group and refuses the root group. Every later `exec` of an exec descriptor, and every device attached, is checked against it and refused from any other group. The runtime therefore puts the holder in the sandbox's group *before* the holder creates the sandbox, and the holder's own processor time and memory count against the tenant, as a container's shim process does. The guarantee that everything a sandbox costs is charged to its group comes from a check at the one place a task joins the sandbox.
- **The holder's main thread owns the tenant's address spaces.** Linux records in each address space an *owner* task, through which its memory controller finds the group to charge page tables and faults to, and the task that creates an address space for a tenant is a carrier, which may die before the address space does. So the endovisor pins the holder's main thread with a task reference at `KERNELET_CREATE` and names it as the owner of every address space the kernelet creates (chapter 13). A pinned task still names its control group after it has exited, so even a holder that crashed charges to the right group until the sandbox is destroyed.
- **The sandbox dies with the holder.** When the holder exits, however it exits, Linux closes its sandbox descriptor; when the last copy of that descriptor closes, the sandbox is killed and destroyed.
- **The end of a sandbox is the endovisor's bookkeeping, not a task's.** When the last carrier's lifeline closes, the sandbox has exited in chapter 12's sense; the endovisor records why, and whoever is in `KERNELET_WAIT` wakes.

So a sandbox has exactly one process that is not a carrier, the holder, and the word *carrier* means one thing throughout the book: a Linux task that carries a virtual CPU and may run the tenant's program. Two things the holder cannot do, for reasons chapters 8 and 12 give: signals other than `SIGKILL` are discarded before they could reach a carrier, so a single carrier cannot be stopped or terminated politely, and a `SIGKILL` to any one of them ends the whole sandbox.

## The operations

Every operation is an `ioctl`. It returns `-1` with `errno` set on failure and otherwise what its entry says, `0` where nothing is said. Names follow one rule: an operation whose target is the sandbox is `KERNELET_` and a verb (`KERNELET_KILL`); one whose target is some other object is `KERNELET_`, the object, and a verb (`KERNELET_KIND_REGISTER`). The header is `prototype/linux/endovisor/uapi/kernelet.h`; each structure below is quoted from it with its comments cut.

### On the system descriptor

The system descriptor is `open("/dev/kernelet")`. The node is owned by root; an operator who runs sandboxes as an unprivileged user gives that user access to it, as is done for `/dev/kvm`.

**`KERNELET_GET_API_VERSION`.** No argument. Returns `KERNELET_API_VERSION`, so that a runtime can refuse a kernel it does not understand; the one operation that cannot fail.

**`KERNELET_KIND_REGISTER`.** Hands over a kernelet image and names it; returns the **kind** identifier, a small non-negative integer.

*Simplified from `prototype/linux/endovisor/uapi/kernelet.h`: `kernelet_kind_register`.*

```c
struct kernelet_kind_register {
	__s32	image_fd;                   /* an open descriptor on the image file */
	__u32	flags;                      /* must be 0 */
	char	name[KERNELET_NAME_LEN];    /* for people and for KERNELET_KIND_LIST */
};
```

The image file is an ELF relocatable object for x86-64 holding the kernel proper and the framework beneath it (chapter 4 says what those are), built so that it has **no undefined symbols**, only relocations of the kinds the endovisor's loader applies, and one exported symbol, `kernelet_entry_table`. The build makes it like this and checks it:

```mermaid
flowchart TB
    src["the kernel proper and vOSTD<br/>(Rust)"] --> cargo["cargo build<br/>one static library"] --> ld["ld -r<br/>one relocatable object"]
    ld --> check{"nm -u empty?<br/>relocations the loader applies?"}
    check -- yes --> image["the kernelet image<br/>one file"]
    image -- "KERNELET_KIND_REGISTER" --> dev["/dev/kernelet"]
    endo["linux/endovisor/*.c<br/>(the endovisor, C)"] --> kbuild["kbuild<br/>kernelet.ko"] --> insmod["insmod"] --> dev
```

"No undefined symbols" is the whole security story of the build, so it deserves a sentence. A symbol is undefined in an object when the code calls a function the object does not contain; the linker fills it in later. An image with none cannot call anything outside itself. It *calls* Linux in exactly one way: through a table of function pointers the endovisor hands it when it starts. That is the service table, and the kernelet cannot call what is not in it, because it cannot name anything else. (It also reads two words of Linux's and writes one, at offsets the endovisor publishes, for reasons chapters 10 and 12 give; those are the whole of its contact with Linux's own variables. It shares small records with the endovisor, one per virtual CPU and one per address space (chapters 9 and 14), and it reads the tenant's page tables through Linux's direct map (chapter 14); every one of those is memory the endovisor chose to show it.)

The endovisor repeats the checks on the file and refuses it (`EINVAL`, `ENOEXEC`) if any fails, or if the image's ABI version is not its own (`EPROTO`); then it copies the image's code into pages it keeps for the kind's life, which every sandbox of the kind executes, each placed at an address of its own with data of its own after it. That sharing is why registration and creation are two operations and not one: an `execve` of the image file itself, with the sandbox's parameters as arguments, would have nowhere to keep the one shared copy.

<div class="linux">

**Linux: capabilities and lockdown.** Root's powers are divided into named *capabilities*, and a privileged operation asks for the one it needs with [`capable()`](https://elixir.bootlin.com/linux/v6.12/source/kernel/capability.c#L434). Loading a module asks for `CAP_SYS_MODULE` ([`init_module`](https://elixir.bootlin.com/linux/v6.12/source/kernel/module/main.c#L2646)). A kernel can also be *locked down*, a mode in which nothing may add code to the running kernel unless it is signed, and every loader asks [`security_locked_down()`](https://elixir.bootlin.com/linux/v6.12/source/security/security.c#L5766) before it proceeds.

</div>

Registering needs `CAP_SYS_MODULE` and a kernel that is not locked down (`EPERM` otherwise), because an image is kernel code. The checks establish that an image *cannot name* anything in Linux; they do not establish that its machine code is harmless, and no check made on a file could. What makes an image trustworthy is who built it, which is exactly Linux's position on modules, so registering asks what `init_module` asks. The operator does it when the machine is set up; the runtime, which runs as an ordinary user, only creates sandboxes.

**`KERNELET_KIND_LIST`.** Lists the registered kinds. The caller supplies an array of `capacity` entries; the endovisor fills in up to that many, sets `count` to the number registered, which may exceed `capacity`, and returns `0`.

*Simplified from `prototype/linux/endovisor/uapi/kernelet.h`: `kernelet_kind_info`, `kernelet_kind_list`.*

```c
struct kernelet_kind_info {
	__u32	id;
	__u32	nr_sandboxes;               /* sandboxes of this kind that exist now */
	__u64	text_bytes;                 /* the shared code's size */
	char	name[KERNELET_NAME_LEN];
};
struct kernelet_kind_list {
	__u64	kinds;                      /* struct kernelet_kind_info *, user memory */
	__u32	capacity;
	__u32	count;                      /* out */
};
```

**`KERNELET_KIND_UNREGISTER`.** The argument is a kind identifier. Drops the kind and returns its pages to Linux. Needs `CAP_SYS_MODULE`; `EBUSY` while any sandbox of the kind exists.

**`KERNELET_CREATE`.** Creates a sandbox of a kind and returns its **sandbox descriptor**, close-on-exec.

*Simplified from `prototype/linux/endovisor/uapi/kernelet.h`: `kernelet_create`.*

```c
struct kernelet_create {
	__u32	kind;
	__u32	nr_vcpus;                   /* 1 to KERNELET_MAX_VCPUS */
	__u64	memory_initial;             /* bytes, given before it boots */
	__u64	memory_max;                 /* what KERNELET_GRANT and its own requests may raise it to */
	__u64	max_tasks;                  /* the kernelet's own tasks: each costs a kernelet stack */
	__u64	cmdline;                    /* const char *, user memory */
	__u32	cmdline_len;
	__u32	flags;                      /* must be 0 */
};
```

The calling task's control group becomes the sandbox's; the root group is refused (`EPERM`). The calling thread's group leader is pinned as the owner of every address space the kernelet will create. Memory amounts are rounded up to whole 2 MiB units. The command line is passed to the kernel proper as a boot loader would pass it. Nothing is allocated for the kernelet itself until its first carrier arrives, so that everything is charged to the group. Creating needs no privilege beyond access to the node, because a sandbox can reach nothing its creator could not: its memory is charged to the creator's group, and the files it is given are files its creator opened.

### On the sandbox descriptor

**`KERNELET_VCPU_GET_EXEC_FD`.** The argument is a virtual CPU's index, `0` to `nr_vcpus - 1`. Returns that virtual CPU's **exec descriptor**, close-on-exec; `EINVAL` beyond the count, `EBUSY` for a virtual CPU already started. The descriptor is on an in-memory file owned by root and execute-only. It is used by executing it, `execveat(fd, "", argv, envp, AT_EMPTY_PATH)`; the arguments and the environment are discarded. The executing process must be in the sandbox's control group, must have no-new-privileges set, and must not gain privileges by the `exec`; it becomes the carrier of that virtual CPU. Each virtual CPU's descriptor may be executed once; a second `exec`, of it or of another copy, fails with `EBUSY`. The sandbox starts at the first such `exec`, which loads the kind's image as this sandbox's instance and grants `memory_initial`, and after which no device may be attached. The kernelet boots when every virtual CPU's carrier has arrived: a kernel that starts its other processors expects each of them to answer, and the simplest way to keep that true is not to enter the image until every virtual CPU has a task. A holder that never starts one of them has a sandbox that never boots, which `KERNELET_GET_STATS` shows as *starting*, and `KERNELET_KILL` ends. A carrier that dies while the others are still arriving ends the sandbox, as any carrier's death does.

**`KERNELET_ATTACH_DEVICE`.** Gives the sandbox a virtio device backed by a file the caller opened. Returns the device's index, which the kernelet sees as the order of devices on its command line. Legal until the sandbox starts (`EBUSY` after). The endovisor takes its own reference to the open file, so the caller may close its descriptor.

*Simplified from `prototype/linux/endovisor/uapi/kernelet.h`: `kernelet_device`.*

```c
struct kernelet_device {
	__u32	type;                       /* KERNELET_DEVICE_BLOCK: a file or block device; KERNELET_DEVICE_NET: a TAP interface */
	__s32	fd;
	__u32	flags;                      /* KERNELET_DEVICE_READONLY */
	__u32	pad;                        /* must be 0 */
};
```

**`KERNELET_SET_CONSOLE`, `KERNELET_SET_LOG`.** The argument is a descriptor. The first names the file the sandbox's console is served through, a terminal, a pipe or a socket: what the tenant writes to its console is written there, and what is written there arrives as its console input. The second names the file the kernelet's kernel log is written to. The endovisor takes its own reference; legal until the sandbox starts. Without a log file the log is kept only in a bounded ring, and `KERNELET_GET_STATS` counts what was dropped from it.

**`KERNELET_GRANT`.** Gives the sandbox memory now, raises its ceiling, or both; a zero field leaves that side alone. `ENOMEM` if `add` cannot be found, `EINVAL` if `max` is below what is granted.

*Simplified from `prototype/linux/endovisor/uapi/kernelet.h`: `kernelet_grant`.*

```c
struct kernelet_grant {
	__u64	add;                        /* bytes to give now */
	__u64	max;                        /* the new ceiling */
};
```

**`KERNELET_KILL`.** The argument is a reason, a 32-bit value of the caller's choosing that the exit status will carry. Marks the kernelet dying and returns at once; stopping the carriers is asynchronous (chapter 12), and `KERNELET_WAIT` says when it is done. Idempotent.

**`KERNELET_WAIT`, and `poll`.** Sleeps until the sandbox has exited and reports how; the descriptor is also pollable, readable once the sandbox has exited.

*Simplified from `prototype/linux/endovisor/uapi/kernelet.h`: `kernelet_exit`, `kernelet_end`.*

```c
enum kernelet_end {
	KERNELET_END_EXITED	= 1,            /* the kernel proper powered off */
	KERNELET_END_PANICKED	= 2,        /* a panic nothing in it caught */
	KERNELET_END_KILLED	= 3,            /* the host decided */
};
struct kernelet_exit {
	__u32	how;                        /* enum kernelet_end */
	__s32	code;                       /* EXITED: the kernel proper's exit code */
	__u32	reason;                     /* KILLED: KERNELET_KILL's argument, or KERNELET_KILLED_* */
	__u32	pad;
	char	message[KERNELET_MESSAGE_LEN];  /* PANICKED: the message */
};
```

The reasons the endovisor itself kills with are a carrier lost (`SIGKILL` from outside, or the out-of-memory killer), a fault in kernelet code, a kernelet stack nearly exhausted, and Linux's preemption count found wrong on leaving kernelet code; chapter 12 is about each, and `KERNELET_KILLED_REQUESTED` is what `KERNELET_KILL` and the closing of the last descriptor report.

**`KERNELET_GET_STATS`.** Counters, and one row per virtual CPU. The caller supplies an array of `capacity` rows; `nr_vcpus` is set to the sandbox's number and that many rows, or `capacity` if fewer, are filled.

*Simplified from `prototype/linux/endovisor/uapi/kernelet.h`: `kernelet_vcpu_stat`, `kernelet_stats`.*

```c
struct kernelet_vcpu_stat {
	__s32	pid;                        /* the carrier's process identifier, 0 if unstarted */
	__u32	state;                      /* UNSTARTED, WAITING, RUNNING, GONE */
	__u64	run_ns;                     /* time the carrier has run */
	__u64	stolen_ns;                  /* time it was runnable but not running */
};
struct kernelet_stats {
	__u32	state;                      /* CREATED, STARTING, RUNNING, DYING, EXITED */
	__u32	nr_vcpus;                   /* out */
	__u64	memory_granted;
	__u64	service_calls;
	__u64	virqs_raised;
	__u64	log_dropped;
	__u64	vcpus;                      /* struct kernelet_vcpu_stat *, user memory */
	__u32	capacity;
	__u32	pad;
};
```

The rows are how an operator's tool finds a sandbox's carriers without walking the control group; the per-carrier identifiers are what `taskset` and `chrt` take.

**`KERNELET_DESTROY`.** No argument. Gives everything back: the memory, the instance, the records. Legal once the sandbox has exited (`EBUSY` before); the exit status stays readable through the descriptor until it is closed. Closing the last copy of the sandbox descriptor does `KERNELET_KILL`, waits, and does this, so that a crashed holder leaves nothing behind.

<div class="recap">

**Recap.** A kernelet's user-space interface is one device node and three descriptors. The system descriptor, from `/dev/kernelet`, is where an operator with the right to load kernel code registers an image file as a kind, and where anyone with the node creates a sandbox of a kind. The sandbox descriptor is what the holder keeps: through it the holder attaches files, asks for one exec descriptor per virtual CPU, waits for the end and destroys, and when its last copy closes the sandbox dies. An exec descriptor is executed, not called, by a child the holder forked and configured with Linux's ordinary system calls, because a carrier needs an address space that holds nothing of the host's; the endovisor turns that child into the virtual CPU's carrier. The holder's control group is the sandbox's, its main thread owns the tenant's address spaces, and every task of a sandbox is one that user space made and can govern.

</div>
