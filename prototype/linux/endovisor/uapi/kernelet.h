/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
/*
 * The kernelet UAPI: what a program in the host's user space may ask of a
 * Linux that runs kernelets. One device node, /dev/kernelet, and three kinds
 * of descriptor made from it:
 *
 *   the system descriptor   open("/dev/kernelet"): register kinds, create
 *                           sandboxes
 *   a sandbox descriptor    returned by KERNELET_CREATE: everything about one
 *                           sandbox; when its last copy closes, the sandbox is
 *                           killed, and destroyed once it has exited
 *   an exec descriptor      returned by KERNELET_VCPU_GET_EXEC_FD: execute it
 *                           (execveat with AT_EMPTY_PATH) and the executing
 *                           process becomes that virtual CPU's carrier
 *
 * Every operation is an ioctl. It returns -1 with errno set on failure, and
 * otherwise what its comment says, 0 when nothing is said. An argument shown
 * as a __u32 or __s32 is passed by pointer, as the _IOW encoding says. Names
 * follow one rule: an operation on the sandbox is named for what it does
 * (KERNELET_KILL, KERNELET_SET_CONSOLE); an operation on a kind or a virtual
 * CPU names that object first (KERNELET_KIND_REGISTER,
 * KERNELET_VCPU_GET_EXEC_FD). KERNELET_GET_API_VERSION, on the device itself,
 * is the one exception.
 *
 * This header is shared by the endovisor and by host programs such as
 * host/runtime/holder.c, which includes it with -I linux/endovisor/uapi.
 */
#ifndef _UAPI_LINUX_KERNELET_H
#define _UAPI_LINUX_KERNELET_H

#include <linux/ioctl.h>
#include <linux/types.h>

/* Returned by KERNELET_GET_API_VERSION; a runtime refuses any other value. */
#define KERNELET_API_VERSION	1

/* The ioctl type byte, chosen for the prototype; 0xEB is unassigned in
 * Documentation/userspace-api/ioctl/ioctl-number.rst at v6.12. */
#define KERNELET_IOC		0xEB

#define KERNELET_NAME_LEN	32
#define KERNELET_MESSAGE_LEN	128
#define KERNELET_CMDLINE_MAX	4096

/* ------------------------------------------------------------------ */
/* The system descriptor                                              */
/* ------------------------------------------------------------------ */

/* Returns KERNELET_API_VERSION. The one operation that cannot fail. */
#define KERNELET_GET_API_VERSION	_IO(KERNELET_IOC, 0x00)

/*
 * KERNELET_KIND_REGISTER: hand over a kernelet image, and get a kind.
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
 * name is for people and for KERNELET_KIND_LIST, and must be unique among
 * the registered kinds (EEXIST otherwise).
 *
 * Returns the kind's identifier, a small non-negative integer.
 */
struct kernelet_kind_register {
	__s32	image_fd;
	__u32	flags;				/* must be 0 (EINVAL) */
	char	name[KERNELET_NAME_LEN];	/* NUL-terminated */
};
#define KERNELET_KIND_REGISTER		_IOW(KERNELET_IOC, 0x01, struct kernelet_kind_register)

/*
 * KERNELET_KIND_LIST: the registered kinds. The caller supplies an array of
 * capacity entries at kinds; the endovisor fills in up to that many, sets
 * count to the number registered (which may exceed capacity: call again with
 * a larger array), and returns 0.
 */
struct kernelet_kind_info {
	__u32	id;
	__u32	nr_sandboxes;			/* sandboxes of this kind that exist now */
	__u64	text_bytes;			/* the shared code's size */
	char	name[KERNELET_NAME_LEN];
};
struct kernelet_kind_list {
	__u64	kinds;				/* struct kernelet_kind_info *, user memory */
	__u32	capacity;			/* entries available at kinds */
	__u32	count;				/* out: kinds registered */
};
#define KERNELET_KIND_LIST		_IOWR(KERNELET_IOC, 0x02, struct kernelet_kind_list)

/*
 * KERNELET_KIND_UNREGISTER: drop a kind and return its pages to Linux.
 * Needs the same rights as registering. ENOENT for an unknown kind, EBUSY
 * while any sandbox of the kind exists.
 */
#define KERNELET_KIND_UNREGISTER	_IOW(KERNELET_IOC, 0x03, __u32)

/*
 * KERNELET_CREATE: create a sandbox of a kind, and get its descriptor.
 *
 * The calling task's control group, on the unified (v2) hierarchy, becomes
 * the sandbox's: every later exec of one of its exec descriptors, and every
 * KERNELET_ATTACH_DEVICE, must come from a task in that group. The root group
 * is refused (EPERM). The calling thread's group leader is held, by a task
 * reference, as the owner of every address space the kernelet will create,
 * so that the memory controller charges their pages to this group.
 *
 * memory_initial is what the kernelet is given before it boots and
 * memory_max what KERNELET_GRANT and the kernelet's own requests may raise
 * it to, both in bytes, rounded up to whole 2 MiB units; max_tasks bounds the
 * kernelet's own tasks, each of which costs the host a kernelet stack. The
 * command line is passed to the kernel proper as a machine's boot loader
 * would pass it.
 *
 * Errors: ENOENT for an unknown kind; EINVAL for nr_vcpus outside 1 to
 * KERNELET_MAX_VCPUS, memory_initial above memory_max, cmdline_len above
 * KERNELET_CMDLINE_MAX, or nonzero flags; ENOSPC when the endovisor's table
 * of sandboxes is full.
 *
 * Creating needs no privilege beyond access to the device node: a sandbox
 * can reach nothing its creator could not, since its memory is charged to
 * the creator's group and the files it is given are files its creator
 * opened.
 *
 * Returns the sandbox descriptor, close-on-exec. Nothing is allocated for the
 * kernelet itself until its first carrier arrives.
 */
struct kernelet_create {
	__u32	kind;
	__u32	nr_vcpus;			/* 1 to KERNELET_MAX_VCPUS */
	__u64	memory_initial;
	__u64	memory_max;
	__u64	max_tasks;
	__u64	cmdline;			/* const char *, user memory; need not be NUL-terminated */
	__u32	cmdline_len;
	__u32	flags;				/* must be 0 */
};
#define KERNELET_MAX_VCPUS	64
#define KERNELET_CREATE			_IOW(KERNELET_IOC, 0x04, struct kernelet_create)

/* ------------------------------------------------------------------ */
/* The sandbox descriptor                                             */
/* ------------------------------------------------------------------ */

/*
 * KERNELET_VCPU_GET_EXEC_FD: the exec descriptor of virtual CPU i.
 *
 * The descriptor is on a file that lives only in memory, one per virtual
 * CPU, owned by root and execute-only: it can be executed, not read or
 * written, and a process that has executed it is not dumpable afterwards.
 * The endovisor knows which sandbox and which virtual CPU each such file is
 * for by the file's identity, not by its contents. Execute it with
 * execveat(fd, "", argv, envp, AT_EMPTY_PATH); the arguments and the
 * environment are discarded.
 *
 * The exec is refused (EPERM) unless the executing process is in the
 * sandbox's control group and has no-new-privileges set, which is what
 * guarantees that it gains nothing by the exec; it fails with EBUSY if this
 * virtual CPU has been started already, by this descriptor or by another
 * copy of it, and with ESRCH if the sandbox has been killed. Otherwise the
 * process becomes the carrier of virtual CPU i, named kernelet/<slot>/<i>,
 * where slot is the sandbox's slot: its index in the endovisor's table of
 * sandboxes, a small number given at KERNELET_CREATE and reported by
 * KERNELET_GET_STATS.
 *
 * The sandbox starts at the first such exec, which loads the kind's image as
 * this sandbox's instance and grants memory_initial, charged to the group.
 * The kernelet boots when every virtual CPU's carrier has arrived, because a
 * kernel that starts its other processors expects each of them to answer.
 * Until then KERNELET_GET_STATS reports the sandbox as STARTING; a holder
 * that never starts one of its virtual CPUs has a sandbox that never boots,
 * which KERNELET_KILL ends. A carrier that dies while the others are still
 * arriving ends the sandbox, as any carrier's death does.
 *
 * Returns the exec descriptor, close-on-exec. EINVAL for an i beyond
 * nr_vcpus, EBUSY for a virtual CPU already started, ESRCH once the sandbox
 * has been killed.
 */
#define KERNELET_VCPU_GET_EXEC_FD	_IOW(KERNELET_IOC, 0x10, __u32)

/*
 * KERNELET_ATTACH_DEVICE: give the sandbox a virtio device, backed by a file
 * the caller opened. Legal until the sandbox starts (EBUSY after), from a
 * task in the sandbox's control group (EPERM otherwise). The endovisor takes
 * its own reference to the open file; the caller may close fd afterwards.
 * Returns the device's index, which the kernelet sees as the order of
 * devices on its command line.
 */
enum kernelet_device_type {
	KERNELET_DEVICE_BLOCK	= 1,		/* fd: a regular file or a block device */
	KERNELET_DEVICE_NET	= 2,		/* fd: a TAP interface */
};
#define KERNELET_DEVICE_READONLY	0x1
struct kernelet_device {
	__u32	type;				/* enum kernelet_device_type */
	__s32	fd;
	__u32	flags;				/* KERNELET_DEVICE_* */
	__u32	pad;				/* must be 0 */
};
#define KERNELET_ATTACH_DEVICE		_IOW(KERNELET_IOC, 0x11, struct kernelet_device)

/*
 * KERNELET_SET_CONSOLE, KERNELET_SET_LOG: the file the sandbox's console is
 * served through, and the file the kernelet's kernel log is written to. The
 * argument is the descriptor; the endovisor takes its own reference. The
 * console carries both directions, what the tenant writes to it and what it
 * reads from it, so its file must be one that does: a terminal or a socket; a
 * pipe carries output only. Legal until the sandbox starts (EBUSY after).
 * Without a log file, the log is kept only in a bounded ring that
 * KERNELET_GET_STATS counts drops from.
 */
#define KERNELET_SET_CONSOLE		_IOW(KERNELET_IOC, 0x12, __s32)
#define KERNELET_SET_LOG		_IOW(KERNELET_IOC, 0x13, __s32)

/*
 * KERNELET_GRANT: give the sandbox add more bytes of memory now, and/or raise
 * its ceiling to max; a zero leaves that field alone. Both rounded up to
 * 2 MiB. ENOMEM if add cannot be found, EINVAL if max is below what is
 * granted, ESRCH once the sandbox has been killed.
 */
struct kernelet_grant {
	__u64	add;
	__u64	max;
};
#define KERNELET_GRANT			_IOW(KERNELET_IOC, 0x14, struct kernelet_grant)

/*
 * KERNELET_KILL: mark the kernelet dying, with a reason the exit status
 * carries, and return at once; stopping the carriers is asynchronous and
 * KERNELET_WAIT says when it is done. The reason is the caller's, below
 * 0x80000000; values with the high bit set are the endovisor's own and are
 * refused (EINVAL). A sandbox that has no carrier yet exits at once.
 * Idempotent: a second kill changes nothing.
 */
#define KERNELET_KILL			_IOW(KERNELET_IOC, 0x15, __u32)

/*
 * KERNELET_WAIT: sleep until the sandbox has exited, then report how. The
 * descriptor is also pollable: POLLIN once the sandbox has exited.
 *
 * A sandbox has exited when, after it was marked dying, every carrier it had
 * is gone, or at once if it never had one. how says which of three things
 * ended it; code is the kernel proper's exit code (EXITED); reason is the
 * caller's own code from KERNELET_KILL, or KERNELET_KILLED_REQUESTED when the
 * last copy of the descriptor closed, or one of the other KERNELET_KILLED_*
 * when the endovisor killed it (KILLED); message is the panic message
 * (PANICKED) or empty.
 */
enum kernelet_end {
	KERNELET_END_EXITED	= 1,		/* the kernel proper powered off */
	KERNELET_END_PANICKED	= 2,		/* a panic nothing in it caught */
	KERNELET_END_KILLED	= 3,		/* the host decided */
};
#define KERNELET_KILLED_REQUESTED	0x80000000u	/* the last copy of the descriptor closed */
#define KERNELET_KILLED_CARRIER_LOST	0x80000001u	/* a carrier died: SIGKILL, the OOM killer */
#define KERNELET_KILLED_FAULT		0x80000002u	/* a fault in kernelet code */
#define KERNELET_KILLED_STACK		0x80000003u	/* a kernelet stack nearly exhausted */
#define KERNELET_KILLED_HOST_COUNT	0x80000004u	/* Linux's preemption count found wrong */
struct kernelet_exit {
	__u32	how;				/* enum kernelet_end */
	__s32	code;
	__u32	reason;
	__u32	pad;
	char	message[KERNELET_MESSAGE_LEN];
};
#define KERNELET_WAIT			_IOR(KERNELET_IOC, 0x16, struct kernelet_exit)

/*
 * KERNELET_GET_STATS: the sandbox's slot and state, counters, and one row
 * per virtual CPU. The caller supplies an array of capacity rows at vcpus;
 * nr_vcpus is set to the sandbox's number, and min(capacity, nr_vcpus) rows
 * are filled. The rows are how a tool finds a sandbox's carriers without
 * walking its control group; pid is what taskset and chrt take.
 */
enum kernelet_state {
	KERNELET_STATE_CREATED	= 1,		/* no carrier yet */
	KERNELET_STATE_STARTING	= 2,		/* some carriers have arrived */
	KERNELET_STATE_RUNNING	= 3,
	KERNELET_STATE_DYING	= 4,		/* marked; carriers being stopped */
	KERNELET_STATE_EXITED	= 5,		/* no carrier of the sandbox is left */
};
enum kernelet_vcpu_state {
	KERNELET_VCPU_UNSTARTED	= 0,		/* its exec descriptor has not been executed */
	KERNELET_VCPU_WAITING	= 1,		/* arrived; waiting for the others, or for vcpu_boot */
	KERNELET_VCPU_RUNNING	= 2,
	KERNELET_VCPU_GONE	= 3,
};
struct kernelet_vcpu_stat {
	__s32	pid;				/* the carrier's process identifier, 0 if unstarted */
	__u32	state;				/* enum kernelet_vcpu_state */
	__u64	run_ns;				/* time the carrier has run */
	__u64	stolen_ns;			/* time it was runnable but not running */
};
struct kernelet_stats {
	__u32	state;				/* enum kernelet_state */
	__u32	nr_vcpus;			/* out */
	__u64	memory_granted;			/* bytes */
	__u64	service_calls;
	__u64	virqs_raised;
	__u64	log_dropped;
	__u64	vcpus;				/* struct kernelet_vcpu_stat *, user memory */
	__u32	capacity;			/* rows available at vcpus */
	__u32	slot;				/* out: the sandbox's index in the endovisor's table; names its carriers */
};
#define KERNELET_GET_STATS		_IOWR(KERNELET_IOC, 0x17, struct kernelet_stats)

/*
 * KERNELET_DESTROY: give everything back: the memory, the instance, the
 * records. Legal once the sandbox has exited (EBUSY before). The exit status
 * stays readable through the descriptor until it is closed. Closing the last
 * copy of the descriptor does KERNELET_KILL; the endovisor then destroys the
 * sandbox itself once it has exited, so that nothing a crashed holder held
 * keeps a sandbox alive. Release never waits.
 */
#define KERNELET_DESTROY		_IO(KERNELET_IOC, 0x18)

#endif /* _UAPI_LINUX_KERNELET_H */
