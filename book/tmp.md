Understand how the current prototype works.

---

## Chapter 2

I want a unified format for all ioctl definitions.

Let's take this one as an example:

```rust
/*
 * KLET_KIND_REGISTER: hand over a kernelet image, and get a kind.
 *
 * image_fd is an open descriptor on the image file: an ELF relocatable object
 * (ET_REL, x86-64) holding the kernel proper and vOSTD, built so that it has
 * no undefined symbol, only relocations of the kinds the endovisor's loader
 * applies, and one exported symbol, kernelet_entry_table. The endovisor
 * repeats those checks on the file and refuses it (EINVAL, ENOEXEC) if any
 * fails; it also refuses an image whose ABI version is not its own
 * (EPROTO). It copies the image's code into pages it keeps for the kind's
 * life, shared by every sandbox of the kind.
 *
 * An image is kernel code, so registering asks what loading a module asks
 * (EPERM otherwise): CAP_SYS_MODULE in the initial user namespace, module
 * loading not disabled (kernel.modules_disabled), and, because images carry
 * no signature, neither signature enforcement (module.sig_enforce) nor
 * lockdown in force. The file is read as a module file is read, so that the
 * host's security modules see it.
 *
 * name is for people and for KLET_KIND_LIST, and must be unique among
 * the registered kinds (EEXIST otherwise).
 *
 * Returns the kind's identifier, a small non-negative integer.
 */
struct klet_kind_register {
	__s32	image_fd;
	__u32	flags;				/* must be 0 (EINVAL) */
	char	name[KLET_NAME_LEN];	/* NUL-terminated */
};
#define KLET_KIND_REGISTER		_IOW(KLET_IOC, 0x01, struct klet_kind_register)
```

It would look like below with the new format:

```rust
// The ioctl for registering a kernelet image.
//
// `image_fd` is an open descriptor on the image file: 
// an ELF relocatable object (ET_REL, x86-64) holding the kernel proper and vOSTD,
// built so that it has no undefined symbol,
// only relocations of the kinds the endovisor's loader applies,
// and one exported symbol, `kernelet_entry_table`.
// The endovisor repeats those checks on the file and refuses it (`EINVAL`, `ENOEXEC`) if any fails;
// it also refuses an image whose ABI version is not its own (`EPROTO`).
// It copies the image's code into pages it keeps for the kind's life,
// shared by every sandbox of the kind.
//
// The image file is registered with `name`.
// This name must be unique among all registered images.
//
// Currently, `flags` must be zero.
//
// Registering a new image successfully results in a new _kind_ of kernelets.
// The function returns the kind's identifier, a small non-negative integer.
//
// # Security
//
// An image is kernel code, 
// so registering asks what loading a module asks (`EPERM` otherwise):
// `CAP_SYS_MODULE` in the initial user namespace
// and module loading not disabled (`kernel.modules_disabled`).
// The file is read as a module file is read,
// so that the host's security modules see it. 
struct klet_kind_register {
	__s32	image_fd;
	__u32	flags;				/* must be 0 (EINVAL) */
	char	name[KLET_NAME_LEN];	/* NUL-terminated */
};
#define KLET_KIND_REGISTER		_IOW(KLET_IOC, 0x01, struct klet_kind_register)
```

The new format has the following characteristics:
* It mimics Rust's doc comments
    * It begins with a summary sentence
    * Identifiers are wrapped within backticks
* Prefer `//` over `/**/`
* It adopts the semantic line breaks convention


In comments, wrap identifiers with backticks.

---

## Chapter 6

---

Originally, the book was written to explain the prototype implementation that is just enough to run the 100-lines Rust OS kernel.

But now I want to make the book more scalable so that it can grow into a full book about the design, implementation, and evaluation of kernelet. And I want to facilitate collaboration between more interested developers.

* Part 1: Design v0
  * This part is a tutorial that describes how a working implementation of kernelet in Linux that is just enough to run a miniaml Rust kernel as a kernelet. The job of this part is to build the sufficient know-how about kernelet and its Linux implementation.
* Part 2: Design
  * This part provides the design and implementation of kernelet in Linux and Asterinas. The job of this part is to be comprehensive and guide a final implementation.
* Part 3: Staging
  * This part allows merging 

The tutorial provides enough 

> The endovisor creates it with shmem_file_setup(), makes it owned by root and execute-only, and recognizes it when it is executed by its inode, not by anything written in it; execveat reopens the file, so the open file the handler sees is never the one it handed out. Possession of the descriptor is the right to start that virtual CPU, once.

This paragraph is written too denese with info and hard to understand the point.. For example, what exactly does it mean by "executed by its inode"? What does it try to imply by saying "the open file the handler sees is never the one it handed out"?  The paragraph starts with `shmem_file_setup`. This seems to be an implementation detail. It is unclear why it needs to mention `shmem`. To me, the most important statement is "Possession of the descriptor is the right to start that virtual CPU, once." You might want to rephrase the paragraph to make an argument around this topic sentence.

> 


Introduction to Kernelets in Linux
The kernelet UAPI
Before any mechanism, the view from the host’s user space. Linux calls the set of system calls, device nodes and file formats that user space may use its UAPI, the user-space application programming interface, and keeps the headers that define it in a directory of that name. A kernelet’s is one header, prototype/linux/endovisor/uapi/kernelet.h: one device node, three kinds of file descriptor, and one rule about who creates the tasks.

This chapter first shows the interface in use, by the prototype’s own holder program, then says why it has the shape it has, and then specifies every operation. Everything the rest of the book builds is behind this interface, and nothing a tenant does ever touches it. The endovisor of this prototype does not offer the device yet: the holder program is built but not run, and the tests start a sandbox an older way, with one program file and one execve.

A prototype kernelet runtime
The program that drives a kernelet sandbox is its holder: the one process of the kernelet runtime that creates the sandbox, keeps its descriptor open for as long as the sandbox lives, and destroys it. A container runtime has such a process per container; the prototype’s is holder.c, a static C program of two commands, register and run.

Linux: device nodes and ioctl. A device node is a file under /dev that stands for a driver rather than for data; opening it gives a descriptor on which the driver answers read, write and, for everything that is neither, ioctl: one system call that takes a descriptor, a command number and an argument, and hands both to whatever code is behind the descriptor. A driver’s interface is therefore a list of command numbers, and a module may define its own. A descriptor need not come from a file system at all: a module can make an anonymous file, with operations of its choosing, and hand out a descriptor on it; every descriptor in this chapter but the first is one of those.

The operator’s step. Once per boot, someone with the right to load kernel code registers each kernelet image the machine will run, one file holding a compiled kernelet (its format is given with KERNELET_KIND_REGISTER below), and names it:

Simplified from prototype/host/runtime/holder.c: open_system, register_kind.

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

    snprintf(reg.name, sizeof(reg.name), "%s", name);  /* the name KERNELET_KIND_LIST reports; unique */
    return ioctl(sys, KERNELET_KIND_REGISTER, &reg);    /* the kind's identifier */
}
A registered image is a kind, and a kind is what sandboxes are made of. Registering it is the privileged act, and it happens once; creating sandboxes of it is not privileged and happens as often as the runtime likes.

Linux: control groups. A control group is a set of tasks that Linux accounts and limits together: their share of the processors, their memory, and more. Groups form one tree, the unified hierarchy of cgroup v2, which this book means throughout. A process joins a group when its identifier is written into the group’s cgroup.procs file, and a child starts in its parent’s group. Containers are built on them, and so is a sandbox: because every task of the sandbox is in the sandbox’s group, the processor time the kernelet burns and the memory Linux allocates for it are charged to the tenant by machinery Linux already has.

The holder’s step. To run a sandbox, the holder creates it, gives it its console and log, and then makes one carrier per virtual CPU:

Simplified from prototype/host/runtime/holder.c: run_sandbox, wait_sandbox.

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

    wait_sandbox(sb, pids, nr_vcpus, &ex);          /* KERNELET_WAIT, watching the children too: a child that
                                                       dies before its exec never became a carrier, so the
                                                       holder kills the sandbox itself if one does */
    for (i = 0; i < nr_vcpus; i++)
        waitpid(pids[i], NULL, 0);                  /* the carriers died by SIGKILL */
    ioctl(sb, KERNELET_DESTROY);
    close(sb);

    switch (ex.how) {
    case KERNELET_END_EXITED:   return ex.code;     /* the kernel proper's exit code */
    case KERNELET_END_PANICKED: return 128;
    default:                    return 129;         /* killed */
    }
}
The loop in the middle is the heart of the interface. A carrier, chapter 1’s term for a Linux task that carries one of the sandbox’s virtual CPUs and may run the tenant’s programs, is not made by the kernel. The holder forks a child for it, the child arranges itself with ordinary system calls, and then the child executes a descriptor the sandbox handed out:

Simplified from prototype/host/runtime/holder.c: start_carrier, join_cgroup.

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
    die_child("execveat");                           /* reached only if the exec failed */
}

static void join_cgroup(const char *dir)             /* write our process identifier into cgroup.procs */
{
    snprintf(path, sizeof(path), "%s/cgroup.procs", dir);
    fd = open(path, O_WRONLY | O_CLOEXEC);
    n = snprintf(pid, sizeof(pid), "%d\n", getpid());
    write(fd, pid, n);
    close(fd);
}
Between the fork and the execveat the child is an ordinary process of the holder’s user, and anything Linux lets a process set on itself can go there: the processor it is pinned to, as here; its priority or scheduling class; the user it runs as; the namespaces it is in; its resource limits; a seccomp filter, which bounds what the tenant may ask of its kernelet. All of it survives the exec, because these are properties of the task and not of the program it runs, and all of it is per carrier, so two virtual CPUs can be pinned to two processors and given two priorities.

In summary, the whole life of a sandbox is, in order:

When the machine is set up, the operator registers each kind with KERNELET_KIND_REGISTER.
The runtime makes a control group for the sandbox with the limits the operator chose, and starts the holder in it, or the holder moves itself in before it creates anything, as -c does.
The holder creates the sandbox with KERNELET_CREATE, opens the disk image and whatever else the sandbox is to have and passes each with KERNELET_ATTACH_DEVICE, and passes its console and log with KERNELET_SET_CONSOLE and KERNELET_SET_LOG.
For each virtual CPU, the holder asks for the exec descriptor with KERNELET_VCPU_GET_EXEC_FD and forks a child, which arranges itself and executes the descriptor. The first of those execs loads the kind’s image as this sandbox’s instance. From now on, the carrier no longer executes the holder’s code, but the kernelet’s.
The sandbox runs. Linux schedules each carrier with the processors and the class its creator gave it; the kernelet schedules its own tasks on them.
The kernel proper powers off, or the holder calls KERNELET_KILL, or a carrier is killed. The endovisor marks the kernelet dying, stops every carrier, and when the last of them is gone records why. The holder’s KERNELET_WAIT returns, it reaps the carriers, calls KERNELET_DESTROY, and exits; the runtime removes the group.
Why it is shaped so
The kernelet UAPI is designed with four requirements in mind:

Every Linux task of a sandbox is created by user space, and user space can find it and govern it with Linux’s own system calls. A carrier is a special task, since its system calls go to the kernelet and not to Linux, but it is still a task, and the host’s tools for tasks, sched_setaffinity, setpriority, sched_setattr, control groups, namespaces, resource limits, perf, /proc, must apply to it as to any other. Linux applies them to any task; only user space can apply them before the task carries a virtual CPU, and only a task user space made is one whose identifier it knows without searching.
Resources reach a sandbox as descriptors. A disk image, a network interface, a console and a log file are things the runtime opens itself, under its own user’s permissions, and passes down. Nothing is named by path inside the kernel, and a sandbox can reach exactly what its runtime could open.
A sandbox dies whole, and dies with its runtime. Nothing a crashed runtime held keeps a sandbox alive.
An image is kernel code. Loading one is allowed to whoever may load a module; creating a sandbox of a loaded image is allowed to whoever may open the device. And one copy of an image’s code serves every sandbox of it.
Learning from the KVM UAPI
Linux has one pre-existing interface that meets the first three considerations already—KVM, Linux’s hypervisor—and thus its interface is the one that we should draw inspirations from. The KVM module runs virtual machines whose virtual processors are ordinary user threads: a program such as QEMU opens /dev/kvm, asks it for a descriptor that stands for a virtual machine, asks that for a descriptor per virtual processor, and runs each virtual processor from a thread of its own by calling an operation on its descriptor (KVM_CREATE_VM, KVM_CREATE_VCPU, KVM_RUN). The threads are QEMU’s: it created them, it can pin them and renice them, ps shows them, and the machine dies when QEMU does, because closing the last descriptor destroys it. A kernelet’s interface has the same three levels: a system descriptor, a sandbox descriptor, and a descriptor per virtual CPU, each made from the one above it using ioctl, as shown by the diagram below:

KERNELET_CREATE

KERNELET_KIND_REGISTER
(needs the right to load kernel code)

of a kind

KERNELET_VCPU_GET_EXEC_FD(i)

fork, configure, execveat

/dev/kernelet
the system descriptor

a sandbox descriptor
held by the sandbox's holder

a kind: one image,
its code shared by every sandbox of it

an exec descriptor
for virtual CPU i, used once

the carrier of virtual CPU i
a child of the holder

Differing from the KVM UAPI
KVM runs a virtual processor by a call: a thread invokes KVM_RUN and returns from it. A kernelet starts a virtual CPU by an exec: a process executes the descriptor and never returns. This is the one place the two interfaces differ, and the reason is what each thread’s address space is for.

A KVM thread keeps its own address space throughout. The guest’s memory is elsewhere, in a mapping the thread set up; the thread only drives the guest.

A carrier is to the kernelet what a processor is to an ordinary kernel: the kernelet runs its tenant’s processes on it, one at a time. Those processes run in Linux’s own user mode, on Linux’s own page tables, so at every switch the kernelet switches the carrier’s address space to the current process’s, and the carrier’s address space is always one of the tenant’s. It must therefore start holding nothing of the host’s: not the holder’s program, not its heap, not a stack with the holder’s secrets on it. The one operation in Linux that gives a process a fresh address space is execve. So the per-virtual-CPU descriptor is not called; it is executed.

Possession of the vCPU descriptor is the right to start that virtual CPU, once. The descriptor refers to a file that exists only in memory and holds nothing of interest: no program, no data. What matters is the file’s identity. The endovisor remembers which sandbox and which virtual CPU it created each such file for, and when a process executes a file, the endovisor checks whether it is one of those. A file with the same bytes elsewhere is not one; a second exec of the same file is refused, because its virtual CPU has already been started. The file is owned by root and can be executed but neither read nor written, so the holder can hand the descriptor to a child but cannot read it or change it.

Linux: what exec keeps. A new program gets a new address space, and begin_new_exec() resets what belongs to the old one: signal handlers, timers, the descriptors marked close-on-exec, and a few registrations by which Linux would later write into user memory. It does not touch the task’s control group, its user and group identities, its namespaces (bar a time namespace chosen for its children, which it enters), its processor mask, priority, resource limits, the no-new-privileges bit or the seccomp filter; those are properties of the task, not of the program, and the two last are kept by design so that a program cannot shed them by executing another. Two things it does recompute: the task’s capabilities, of which a process that is not root keeps only those it marked ambient, and whatever domain the host’s security module assigns the new program. That is what makes the holder’s child work: everything it set on itself is still set when the endovisor sees it, and nothing it could not have had is added.



---

> `cursor_mut`... ask Linux to put the page in a Linux page table

----


> `read_fallible`...walk the page table itself and copy through the kernel’s own map of memory (chapter 13)

This is undesirable.

---

> the component of the host kernel that creates, serves and destroys kernelets. Endo- because it sits inside the host kernel, beside the kernelets, where a hypervisor sits beneath its guests.

Is the correctness of an endovisor part of the TCB?

---

> The heap. Rust’s Vec, Box and Arc need a heap. vOSTD’s is the host’s: a global allocator that forwards each allocation to the services mem_alloc and mem_free, which the endovisor implements with Linux’s kmalloc and kfree.

Should we do that? I mean, why not let vOSTD itself manage its own heap? The memory accounting can be simplified.

---

> The hook is placed after seccomp, which means the filter a sandbox was started with runs on every one of the tenant’s system calls before the kernelet sees them. That is a tool for the kernelet runtime, the host program that creates sandboxes (chapter 5), with a sharp edge: a filter that allows a call lets the kernelet serve it; one that returns an error answers the call in Linux, and the kernelet never hears of it; one that kills ends a carrier, and with it, as chapter 11 shows, the whole sandbox. A filter for a sandbox therefore bounds what the tenant may ask of its kernelet, and must be written for that, not copied from a host process. The prototype’s runtime installs one only in a boot of make probe that checks that a killing filter ends the sandbox.

Host's seccomp to filter what syscall may reach the kernelet? If the syscall was issued from the user mode of a process managed by the kernelet, then why the filter set up by the host should filter such syscalls?

---
