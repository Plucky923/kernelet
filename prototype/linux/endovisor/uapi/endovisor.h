/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
// The endovisor UAPI defines what host user space may ask of a Linux that runs kernelets.
// It has one device node, `/dev/endovisor`, and three kinds of descriptor:
//
// - The system descriptor, from `open("/dev/endovisor")`, registers kinds and creates sandboxes.
// - A sandbox descriptor, returned by `KLET_CREATE`, controls one sandbox.
//   Closing its last copy kills the sandbox and destroys it once it has exited.
// - An exec descriptor, returned by `KLET_GET_VCPU_EXEC_FD`, starts one virtual CPU.
//   Executing it with `execveat` and `AT_EMPTY_PATH` makes the caller that virtual CPU's carrier.
//
// The operations defined below are ioctls.
// They return -1 with `errno` set on failure,
// and otherwise return what their comments specify, or zero when nothing is specified.
//
// An argument shown as `__u32` or `__s32` is passed by pointer, as the `_IOW` encoding specifies.
// Names follow one rule:
// operations on a kind name that object first (`KLET_KIND_REGISTER`);
// other operations are named for what they do
// (`KLET_GET_API_VERSION`, `KLET_KILL`, `KLET_SET_CONSOLE`, `KLET_GET_VCPU_EXEC_FD`).
//
// This header is shared by the endovisor and host programs such as `host/runtime/holder.c`,
// which includes it with `-I linux/endovisor/uapi`.
#ifndef _UAPI_LINUX_KLET_H
#define _UAPI_LINUX_KLET_H

#include <linux/ioctl.h>
#include <linux/types.h>

// Returned by `KLET_GET_API_VERSION`; a runtime refuses any other value.
#define KLET_API_VERSION	1

// The ioctl type byte is chosen for the prototype.
// `0xEB` is unassigned in `Documentation/userspace-api/ioctl/ioctl-number.rst` at v6.12.
#define KLET_IOC		0xEB

#define KLET_NAME_LEN	32
#define KLET_MESSAGE_LEN	128
#define KLET_CMDLINE_MAX	4096

// ------------------------------------------------------------------
// The system descriptor
// ------------------------------------------------------------------

// The ioctl for querying the endovisor UAPI version.
//
// The ioctl takes no argument and returns `KLET_API_VERSION`.
// This operation cannot fail.
#define KLET_GET_API_VERSION	_IO(KLET_IOC, 0x00)

// The ioctl for registering a new kernelet kind by providing a new image.
//
// `image_fd` is an open descriptor on the image file:
// an ELF relocatable object (`ET_REL`, x86-64) holding the kernel proper and vOSTD,
// built so that it has no undefined symbol,
// only relocations of the kinds the endovisor's loader applies,
// and one exported symbol, `kernelet_entry_table`.
// The endovisor repeats those checks on the file and refuses it (`EINVAL`, `ENOEXEC`) if any fails;
// it also refuses an image whose ABI version is not its own (`EPROTO`).
// It copies the image's code into pages it keeps for the kind's life,
// shared by every sandbox of the kind.
//
// The name of the new kind is given in `name`, which `KLET_KIND_LIST` reports.
// This name must be unique among all registered kinds (`EEXIST` otherwise).
// Currently, `flags` must be zero (`EINVAL` otherwise).
//
// The ioctl returns the kind's identifier, a small non-negative integer.
//
// # Security
//
// An image is kernel code,
// so registering asks what loading a module asks (`EPERM` otherwise):
// `CAP_SYS_MODULE` in the initial user namespace
// and module loading not disabled (`kernel.modules_disabled`).
// Because images carry no signature,
// neither signature enforcement (`module.sig_enforce`) nor lockdown may be in force.
// The file is read as a module file is read,
// so that the host's security modules see it.
struct klet_kind_register {
	__s32	image_fd;
	__u32	flags;				// must be 0 (`EINVAL`)
	char	name[KLET_NAME_LEN];	// NUL-terminated
};
#define KLET_KIND_REGISTER		_IOW(KLET_IOC, 0x01, struct klet_kind_register)

// The ioctl for listing registered kinds.
//
// The caller supplies an array of `capacity` entries at `kinds`.
// The endovisor fills in up to that many entries
// and sets `count` to the number of registered kinds.
// If `count` exceeds `capacity`, call again with a larger array.
//
// The ioctl returns zero on success.
struct klet_kind_info {
	__u32	id;
	__u32	nr_sandboxes;			// sandboxes of this kind that exist now
	__u64	text_bytes;			// the shared code's size
	char	name[KLET_NAME_LEN];
};
struct klet_kind_list {
	__u64	kinds;				// `struct klet_kind_info *`, user memory
	__u32	capacity;			// entries available at `kinds`
	__u32	count;				// out: kinds registered
};
#define KLET_KIND_LIST		_IOWR(KLET_IOC, 0x02, struct klet_kind_list)

// The ioctl for unregistering a kind and returning its pages to Linux.
//
// The argument points to the kind's identifier.
// An unknown kind is refused with `ENOENT`;
// a kind with any sandbox still in existence is refused with `EBUSY`.
//
// The ioctl returns zero on success.
//
// # Security
//
// Unregistering requires the same rights as `KLET_KIND_REGISTER`.
#define KLET_KIND_UNREGISTER	_IOW(KLET_IOC, 0x03, __u32)

// The ioctl for creating a sandbox of a registered kind.
//
// `kind` identifies the registered image (`ENOENT` for an unknown kind).
// `nr_vcpus` must be between one and `KLET_MAX_VCPUS`.
// `memory_initial` is what the kernelet is given before it boots;
// `memory_max` is the ceiling for memory granted in response to the kernelet's own requests.
// Both are in bytes, rounded up to whole 2 MiB units.
// `max_tasks` bounds the kernelet's own tasks,
// each of which costs the host a kernelet stack.
// The command line at `cmdline`, of length `cmdline_len`,
// is passed to the kernel proper as a machine's boot loader would pass it.
// Currently, `flags` must be zero.
//
// The ioctl fails with `EINVAL` if `nr_vcpus` is out of range,
// `memory_initial` exceeds `memory_max`, `cmdline_len` exceeds `KLET_CMDLINE_MAX`,
// or `flags` is nonzero.
// It fails with `ENOSPC` if the endovisor's table of sandboxes is full.
//
// The ioctl returns the sandbox descriptor, marked close-on-exec.
// Nothing is allocated for the kernelet itself until its first carrier arrives.
//
// # Security
//
// The calling task's control group, on the unified (v2) hierarchy, becomes the sandbox's.
// Every later exec of one of its exec descriptors, and every `KLET_ATTACH_DEVICE`,
// must come from a task in that group.
// The root group is refused (`EPERM`).
// The calling thread's group leader is held, by a task reference,
// as the owner of every address space the kernelet will create,
// so that the memory controller charges their pages to this group.
//
// Creating needs no privilege beyond access to the device node:
// a sandbox can reach nothing its creator could not,
// since its memory is charged to the creator's group
// and the files it is given are files its creator opened.
//
// # Prototype limitations
//
// A kind has at most one sandbox at a time,
// because its one loaded copy is position-dependent (`EBUSY` while one exists).
// `memory_initial` must round to 2 or 4 MiB,
// the grant being one physically contiguous run (`EINVAL` otherwise).
struct klet_create {
	__u32	kind;
	__u32	nr_vcpus;			// 1 to `KLET_MAX_VCPUS`
	__u64	memory_initial;
	__u64	memory_max;
	__u64	max_tasks;
	__u64	cmdline;			// `const char *`, user memory; need not be NUL-terminated
	__u32	cmdline_len;
	__u32	flags;				// must be 0
};
#define KLET_MAX_VCPUS	64
#define KLET_CREATE			_IOW(KLET_IOC, 0x04, struct klet_create)

// ------------------------------------------------------------------
// The sandbox descriptor
// ------------------------------------------------------------------

// The ioctl for obtaining a virtual CPU's exec descriptor.
//
// The argument points to the virtual CPU's index, `i`.
// The ioctl returns its exec descriptor, marked close-on-exec.
// It fails with `EINVAL` for an `i` beyond `nr_vcpus`,
// `EBUSY` for a virtual CPU already started,
// or `ESRCH` once the sandbox has been killed.
//
// The descriptor refers to a file that lives only in memory, one per virtual CPU.
// The endovisor identifies the sandbox and virtual CPU by the file's identity,
// not by its contents.
// Execute it with `execveat(fd, "", argv, envp, AT_EMPTY_PATH)`;
// the arguments and the environment are discarded.
// The process becomes the carrier of virtual CPU `i`, named `kernelet/<slot>/<i>`,
// where `slot` is the sandbox's index in the endovisor's table,
// given at `KLET_CREATE` and reported by `KLET_GET_STATS`.
//
// The sandbox starts at the first such exec,
// which loads the kind's image as this sandbox's instance
// and grants `memory_initial`, charged to the sandbox's control group.
// The kernelet boots when every virtual CPU's carrier has arrived,
// because a kernel that starts its other processors expects each of them to answer.
// Until then, `KLET_GET_STATS` reports the sandbox as `KLET_STATE_STARTING`.
// A holder that never starts one of its virtual CPUs has a sandbox that never boots;
// `KLET_KILL` ends it.
// A carrier that dies while the others are still arriving ends the sandbox,
// as any carrier's death does.
//
// # Security
//
// The file is owned by root and execute-only.
// The descriptor is an `O_PATH` descriptor, which `execveat` accepts;
// it cannot be used to read or write the file.
// A process that executes it is made non-dumpable.
//
// The exec is refused with `EPERM` unless the executing process
// is in the sandbox's control group and has no-new-privileges set,
// which guarantees that it gains nothing by the exec.
// It fails with `EBUSY` if this virtual CPU has already been started,
// by this descriptor or by another copy of it,
// and with `ESRCH` if the sandbox has been killed.
#define KLET_GET_VCPU_EXEC_FD	_IOW(KLET_IOC, 0x10, __u32)

// The ioctl for attaching a virtio device backed by an open file.
//
// `type` selects the device type, and `fd` is a file the caller opened.
// The endovisor takes its own reference to the file;
// the caller may close `fd` afterwards.
// Attaching is legal until the sandbox starts (`EBUSY` after).
//
// The ioctl returns the device's index,
// which the kernelet sees as the order of devices on its command line.
//
// # Security
//
// The calling task must be in the sandbox's control group (`EPERM` otherwise).
// The device is backed by a file the caller opened under its own permissions.
//
// # Prototype limitations
//
// The prototype has no devices, so this ioctl fails with `EOPNOTSUPP`.
enum klet_device_type {
	KLET_DEVICE_BLOCK	= 1,		// `fd`: a regular file or a block device
	KLET_DEVICE_NET	= 2,		// `fd`: a TAP interface
};
#define KLET_DEVICE_READONLY	0x1
struct klet_device {
	__u32	type;				// `enum klet_device_type`
	__s32	fd;
	__u32	flags;				// `KLET_DEVICE_*`
	__u32	pad;				// must be 0
};
#define KLET_ATTACH_DEVICE		_IOW(KLET_IOC, 0x11, struct klet_device)

// The ioctls for setting the sandbox's console and kernel log files.
//
// The argument points to a file descriptor.
// The endovisor takes its own reference to the file.
// `KLET_SET_CONSOLE` sets the file serving the sandbox's console;
// `KLET_SET_LOG` sets the file receiving its kernel log.
// Both operations are legal until the sandbox starts (`EBUSY` after)
// and return zero on success.
//
// The console carries both directions, what the tenant writes and what it reads,
// so its file must be one that does: a terminal or a socket.
// A pipe carries output only.
// Without a log file, the log is kept only in a bounded ring;
// `KLET_GET_STATS` counts drops from that ring.
//
// # Prototype limitations
//
// The console carries output only.
// A console or log not given goes to the host's kernel log, prefixed `kernelet:`.
#define KLET_SET_CONSOLE		_IOW(KLET_IOC, 0x12, __s32)
#define KLET_SET_LOG		_IOW(KLET_IOC, 0x13, __s32)

// The ioctl for marking a kernelet dying and recording the reason.
//
// The argument points to the caller's reason, which the exit status carries.
// It must be below `0x80000000`;
// values with the high bit set are reserved for the endovisor and refused with `EINVAL`.
//
// The ioctl returns zero without waiting for the carriers to stop.
// Stopping is asynchronous; `KLET_WAIT` says when it is done.
// A sandbox that has no carrier exits at once.
// The operation is idempotent: a second kill changes nothing.
#define KLET_KILL			_IOW(KLET_IOC, 0x15, __u32)

// The ioctl for waiting until a sandbox has exited and reporting how it ended.
//
// A sandbox has exited when, after it was marked dying, every carrier it had is gone,
// or at once if it never had one.
// The sandbox descriptor is also pollable: it reports `POLLIN` once the sandbox has exited.
//
// The ioctl fills in the exit record and returns zero on success.
// `how` identifies which of three things ended the sandbox:
//
// - `KLET_END_EXITED`: `code` is the kernel proper's exit code.
// - `KLET_END_PANICKED`: `message` is the panic message.
// - `KLET_END_KILLED`: `reason` is the caller's reason from `KLET_KILL`,
//   `KLET_KILLED_REQUESTED` if the last copy of the sandbox descriptor closed,
//   or another `KLET_KILLED_*` reason if the endovisor killed it.
//
// `message` is empty when there is no panic message.
//
// # Prototype limitations
//
// The prototype reports a panic as `KLET_END_EXITED`, as a power-off, with no message.
// Of the endovisor's own reasons, it detects only `KLET_KILLED_CARRIER_LOST`.
enum klet_end {
	KLET_END_EXITED	= 1,		// the kernel proper powered off
	KLET_END_PANICKED	= 2,		// a panic nothing in it caught
	KLET_END_KILLED	= 3,		// the host decided
};
#define KLET_KILLED_REQUESTED	0x80000000u	// the last copy of the descriptor closed
#define KLET_KILLED_CARRIER_LOST	0x80000001u	// a carrier died: `SIGKILL`, the OOM killer
#define KLET_KILLED_FAULT		0x80000002u	// a fault in kernelet code
#define KLET_KILLED_STACK		0x80000003u	// a kernelet stack nearly exhausted
#define KLET_KILLED_HOST_COUNT	0x80000004u	// Linux's preemption count found wrong
struct klet_exit {
	__u32	how;				// `enum klet_end`
	__s32	code;
	__u32	reason;
	__u32	pad;
	char	message[KLET_MESSAGE_LEN];
};
#define KLET_WAIT			_IOR(KLET_IOC, 0x16, struct klet_exit)

// The ioctl for reading a sandbox's state, counters, and virtual CPU statistics.
//
// The caller supplies an array of `capacity` rows at `vcpus`.
// The endovisor sets `nr_vcpus` to the sandbox's number of virtual CPUs
// and fills in `min(capacity, nr_vcpus)` rows.
// It also reports the sandbox's `slot`, `state`, and counters.
// The rows let a tool find the sandbox's carriers without walking its control group;
// `pid` is the process identifier that `taskset` and `chrt` take.
//
// The ioctl returns zero on success.
enum klet_state {
	KLET_STATE_CREATED	= 1,		// no carrier yet
	KLET_STATE_STARTING	= 2,		// some carriers have arrived
	KLET_STATE_RUNNING	= 3,
	KLET_STATE_DYING	= 4,		// marked; carriers being stopped
	KLET_STATE_EXITED	= 5,		// no carrier of the sandbox is left
};
enum klet_vcpu_state {
	KLET_VCPU_UNSTARTED	= 0,		// its exec descriptor has not been executed
	KLET_VCPU_WAITING	= 1,		// arrived; waiting for the others, or for `vcpu_boot`
	KLET_VCPU_RUNNING	= 2,
	KLET_VCPU_GONE	= 3,
};
struct klet_vcpu_stat {
	__s32	pid;				// the carrier's process identifier, 0 if unstarted
	__u32	state;				// `enum klet_vcpu_state`
	__u64	run_ns;				// time the carrier has run
	__u64	stolen_ns;			// time it was runnable but not running
};
struct klet_stats {
	__u32	state;				// `enum klet_state`
	__u32	nr_vcpus;			// out
	__u64	memory_granted;			// bytes
	__u64	service_calls;
	__u64	virqs_raised;
	__u64	log_dropped;
	__u64	vcpus;				// `struct klet_vcpu_stat *`, user memory
	__u32	capacity;			// rows available at `vcpus`
	__u32	slot;				// out: the sandbox's index in the endovisor's table; names its carriers
};
#define KLET_GET_STATS		_IOWR(KLET_IOC, 0x17, struct klet_stats)

// The ioctl for destroying an exited sandbox and releasing its resources.
//
// The operation returns the memory, instance, and records to Linux.
// It is legal once the sandbox has exited (`EBUSY` before)
// and returns zero on success.
// The exit status stays readable through the sandbox descriptor until it is closed.
//
// Closing the last copy of the sandbox descriptor performs `KLET_KILL`;
// the endovisor then destroys the sandbox once it has exited.
// Release never waits.
//
// # Security
//
// Automatic cleanup ensures that nothing a crashed holder held keeps a sandbox alive.
#define KLET_DESTROY		_IO(KLET_IOC, 0x18)

#endif // `_UAPI_LINUX_KLET_H`
