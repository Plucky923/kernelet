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
 *                           killed and destroyed
 *   an exec descriptor      returned by KERNELET_VCPU_GET_EXEC_FD: execute it
 *                           (execveat with AT_EMPTY_PATH) and the executing
 *                           process becomes that virtual CPU's carrier
 *
 * Every operation is an ioctl. It returns -1 with errno set on failure, and
 * otherwise what its comment says, 0 when nothing is said. Names follow one
 * rule: an operation whose target is the sandbox is KERNELET_<verb>; one whose
 * target is another object is KERNELET_<object>_<verb>.
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
 * Needs CAP_SYS_MODULE (EPERM otherwise) and a kernel that is not locked
 * down (EPERM): an image is kernel code, and this is what loading a module
 * asks. name is for people and for KERNELET_KIND_LIST; it need not be unique.
 *
 * Returns the kind's identifier, a small non-negative integer.
 */
struct kernelet_kind_register {
	__s32	image_fd;
	__u32	flags;				/* must be 0 */
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
 * Needs CAP_SYS_MODULE. EBUSY while any sandbox of the kind exists.
 */
#define KERNELET_KIND_UNREGISTER	_IOW(KERNELET_IOC, 0x03, __u32)

/*
 * KERNELET_CREATE: create a sandbox of a kind, and get its descriptor.
 *
 * The calling task's control group becomes the sandbox's: every later exec of
 * one of its exec descriptors, and every KERNELET_ATTACH_DEVICE, must come
 * from a task in that group. The root group is refused (EPERM). The calling
 * thread's group leader is pinned as the owner of every address space the
 * kernelet will create, so that the memory controller charges them to this
 * group even after the leader has exited.
 *
 * memory_initial is what the kernelet is given before it boots and
 * memory_max what KERNELET_GRANT and the kernelet's own requests may raise
 * it to, both in bytes, rounded up to whole 2 MiB units; max_tasks bounds the
 * kernelet's own tasks, each of which costs the host a kernelet stack. The
 * command line is passed to the kernel proper as a machine's boot loader
 * would pass it.
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
 * The descriptor is on an in-memory file owned by root and execute-only, so
 * that the process which executes it is not dumpable afterwards. Execute it
 * with execveat(fd, "", argv, envp, AT_EMPTY_PATH); the arguments and the
 * environment are discarded. The executing process must be in the sandbox's
 * control group, must have no-new-privileges set, and must not gain
 * privileges by the exec; it becomes the carrier of virtual CPU i, named
 * kernelet/<sandbox>/<i>. Each virtual CPU's descriptor may be executed
 * once; a second exec of it, or of another copy of it, fails with EBUSY.
 *
 * The sandbox starts at the first such exec, which loads the kind's image as
 * this sandbox's instance and grants memory_initial, charged to the group.
 * The kernelet boots when every virtual CPU's carrier has arrived.
 *
 * Returns the exec descriptor, close-on-exec. EINVAL for an i beyond
 * nr_vcpus, EBUSY for a virtual CPU already started.
 */
#define KERNELET_VCPU_GET_EXEC_FD	_IOW(KERNELET_IOC, 0x10, __u32)

/*
 * KERNELET_ATTACH_DEVICE: give the sandbox a virtio device, backed by a file
 * the caller opened. Legal until the sandbox starts (EBUSY after). The
 * endovisor takes its own reference to the open file; the caller may close
 * fd afterwards. Returns the device's index, which the kernelet sees as the
 * order of devices on its command line.
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
 * served through (a terminal, a pipe, a socket: what the tenant writes to its
 * console is written there, what is written there is its console input), and
 * the file the kernelet's kernel log is written to. The argument is the
 * descriptor; the endovisor takes its own reference. Legal until the sandbox
 * starts. Without a log file, the log is kept only in a bounded ring that
 * KERNELET_GET_STATS counts drops from.
 */
#define KERNELET_SET_CONSOLE		_IOW(KERNELET_IOC, 0x12, __s32)
#define KERNELET_SET_LOG		_IOW(KERNELET_IOC, 0x13, __s32)

/*
 * KERNELET_GRANT: give the sandbox add more bytes of memory now, and/or raise
 * its ceiling to max; a zero leaves that field alone. Rounded to 2 MiB.
 * ENOMEM if add cannot be found, EINVAL if max is below what is granted.
 */
struct kernelet_grant {
	__u64	add;
	__u64	max;
};
#define KERNELET_GRANT			_IOW(KERNELET_IOC, 0x14, struct kernelet_grant)

/*
 * KERNELET_KILL: mark the kernelet dying, with a reason the exit status
 * carries, and return at once; stopping the carriers is asynchronous and
 * KERNELET_WAIT says when it is done. Idempotent.
 */
#define KERNELET_KILL			_IOW(KERNELET_IOC, 0x15, __u32)

/*
 * KERNELET_WAIT: sleep until the sandbox has exited, then report how. The
 * descriptor is also pollable: POLLIN once the sandbox has exited.
 *
 * how says which of three things ended it; code is the kernel proper's exit
 * code (EXITED); reason is the caller's own code from KERNELET_KILL or one of
 * KERNELET_KILLED_* when the endovisor killed it (KILLED); message is the
 * panic message (PANICKED) or empty.
 */
enum kernelet_end {
	KERNELET_END_EXITED	= 1,		/* the kernel proper powered off */
	KERNELET_END_PANICKED	= 2,		/* a panic nothing in it caught */
	KERNELET_END_KILLED	= 3,		/* the host decided */
};
#define KERNELET_KILLED_REQUESTED	0x80000000u	/* KERNELET_KILL, or the descriptor closed */
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
 * KERNELET_GET_STATS: counters, and one row per virtual CPU. The caller
 * supplies an array of capacity rows at vcpus; nr_vcpus is set to the
 * sandbox's number, and min(capacity, nr_vcpus) rows are filled.
 */
enum kernelet_state {
	KERNELET_STATE_CREATED	= 1,		/* no carrier yet */
	KERNELET_STATE_STARTING	= 2,		/* some carriers have arrived */
	KERNELET_STATE_RUNNING	= 3,
	KERNELET_STATE_DYING	= 4,		/* marked; carriers being stopped */
	KERNELET_STATE_EXITED	= 5,		/* no task of the sandbox is left */
};
enum kernelet_vcpu_state {
	KERNELET_VCPU_UNSTARTED	= 0,		/* its exec descriptor has not been executed */
	KERNELET_VCPU_WAITING	= 1,		/* arrived; waiting for the boot, or for vcpu_boot */
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
	__u32	pad;
};
#define KERNELET_GET_STATS		_IOWR(KERNELET_IOC, 0x17, struct kernelet_stats)

/*
 * KERNELET_DESTROY: give everything back: the memory, the instance, the
 * records. Legal once the sandbox has exited (EBUSY before). The exit status
 * stays readable through the descriptor until it is closed. Closing the last
 * copy of the descriptor does KERNELET_KILL, waits, and does this.
 */
#define KERNELET_DESTROY		_IO(KERNELET_IOC, 0x18)

#endif /* _UAPI_LINUX_KERNELET_H */
