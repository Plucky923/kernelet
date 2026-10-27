// Check the endovisor UAPI against the running prototype during `make hello`.
//
// Run `uapi-check IMAGE`, where `IMAGE` is the hello kernelet image.
// Every check prints `UAPI-CHECK: ok` or `UAPI-CHECK: FAIL` with its result.
// The final line counts the results;
// the Makefile's `check-log` target requires the expected number of successes and no failures.
//
// Registration checks cover the API version, malformed PIE images,
// `KLET_KIND_REGISTER`, `KLET_KIND_LIST`, and `KLET_KIND_UNREGISTER`.
// Creation checks cover control groups, unknown kinds, flags,
// and the bounds on virtual CPUs, memory, and command lines.
// Exec checks cover file permissions, no-new-privileges, control group membership,
// repeated arrivals, and attempts to join a killed sandbox.
// A missing virtual CPU keeps a sandbox from booting until `KLET_KILL` ends it.
// Operations restricted after startup and the prototype's `EOPNOTSUPP` cases are checked too.
//
// Descriptor checks cover blocking, interruptible, and nonblocking reads,
// immutable exit records, `poll`/`select`/`epoll`, and exit statistics.
// Duplicated descriptors retain live and exited sandboxes until their final close,
// which destroys them immediately or after the remaining carriers exit.
// Concurrent sandboxes of the same and different kinds each have their own console.
//
// Build statically with `sandbox.c` and `-I linux/endovisor/uapi`.

#define _GNU_SOURCE

#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/epoll.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include "sandbox.h"

#define CG_SELF  "/sys/fs/cgroup/uapi-check"
#define CG_OTHER "/sys/fs/cgroup/uapi-other"

static int nr_ok, nr_fail;

static void ok(int cond, const char *what, const char *how)
{
	if (cond) {
		nr_ok++;
		sandbox_say("ok %s", what);
	} else {
		nr_fail++;
		sandbox_say("FAIL %s: %s", what, how);
	}
}

/* An ioctl expected to fail with err. */
static void refused(int ret, int err, const char *what)
{
	char how[128];

	snprintf(how, sizeof(how), "returned %d, errno %d (%s), not %d", ret,
		 ret < 0 ? errno : 0, ret < 0 ? strerror(errno) : "-", err);
	ok(ret < 0 && errno == err, what, how);
}

// Registers corrupted copies of a valid PIE without executing them.
//
// Each mutation changes one format requirement. A successful registration is
// cleaned up, so a broken refusal cannot leave an image resident after the test.
static void malformed_images(int sys_fd, const char *path)
{
	enum mutation {
		REL_OBJECT, INTERPRETER, TLS_SEGMENT, OVERLAP, UNALIGNED, WRITE_EXEC,
		DEPENDENCY, CONSTRUCTORS, WRONG_RELOCATION, SYMBOL_RELOCATION,
		SHARED_RELOCATION, END_RELOCATION, OUTSIDE_RELOCATION, OUTSIDE_ADDEND, BAD_ENTRY,
		MISSING_PIE, CLEARED_PIE, ABI_RELOCATION, WRITABLE_RELOCATIONS,
		NR_MUTATIONS
	};
	static const char *names[NR_MUTATIONS] = {
		"ET_REL object", "ELF interpreter", "TLS segment", "overlapping segments",
		"unaligned load segment", "writable executable segment", "dynamic dependency", "constructor array",
		"non-RELATIVE relocation", "symbol-bearing RELATIVE relocation",
		"relocation into shared code", "relocation crossing the image end", "relocation outside the image",
		"relocation addend outside the image", "entry table in code",
		"missing PIE flag", "cleared PIE flag", "relocation over entry ABI version",
		"writable relocation table",
	};
	struct stat st;
	unsigned char *original, *copy;
	Elf64_Ehdr *eh;
	Elf64_Phdr *ph;
	size_t length, extra_phoff, copy_capacity, dyn_off = 0, rela_off = 0, rx = 0, second_load = 0;
	size_t null_dynamic = 0, image_end = 0, flags_dynamic = 0, rela_segment = 0;
	int image_fd = open(path, O_RDONLY | O_CLOEXEC), i;

	if (image_fd < 0 || fstat(image_fd, &st) || st.st_size < (off_t)sizeof(*eh))
		exit(1);
	length = st.st_size;
	original = malloc(length);
	if (!original || read(image_fd, original, length) != (ssize_t)length)
		exit(1);
	close(image_fd);
	eh = (Elf64_Ehdr *)original;
	if (eh->e_phoff > length || eh->e_phnum >= 32 ||
	    eh->e_phnum > (length - eh->e_phoff) / sizeof(*ph))
		exit(1);
	extra_phoff = (length + 7) & ~(size_t)7;
	copy_capacity = extra_phoff + (eh->e_phnum + 1) * sizeof(*ph);
	copy = malloc(copy_capacity);
	if (!copy)
		exit(1);
	ph = (Elf64_Phdr *)(original + eh->e_phoff);
	for (i = 0; i < eh->e_phnum; i++) {
		if (ph[i].p_type == PT_DYNAMIC)
			dyn_off = ph[i].p_offset;
		if (ph[i].p_type == PT_LOAD) {
			if (ph[i].p_flags & PF_X)
				rx = i;
			else if (!second_load)
				second_load = i;
			if (ph[i].p_vaddr + ph[i].p_memsz > image_end)
				image_end = ph[i].p_vaddr + ph[i].p_memsz;
		}
	}
	if (!dyn_off || !second_load)
		exit(1);
	for (size_t at = dyn_off; at <= length - sizeof(Elf64_Dyn); at += sizeof(Elf64_Dyn)) {
		Elf64_Dyn *dyn = (Elf64_Dyn *)(original + at);
		if (dyn->d_tag == DT_RELA) {
			for (i = 0; i < eh->e_phnum; i++)
				if (ph[i].p_type == PT_LOAD && dyn->d_un.d_ptr >= ph[i].p_vaddr &&
				    dyn->d_un.d_ptr - ph[i].p_vaddr < ph[i].p_filesz) {
					rela_off = ph[i].p_offset + dyn->d_un.d_ptr - ph[i].p_vaddr;
					rela_segment = i;
				}
		}
		if (dyn->d_tag == DT_FLAGS_1)
			flags_dynamic = at;
		if (dyn->d_tag == DT_NULL) {
			null_dynamic = at;
			break;
		}
	}
	if (!null_dynamic || !flags_dynamic || !rela_off || rela_off > length - sizeof(Elf64_Rela) ||
	    ph[rela_segment].p_flags != PF_R)
		exit(1);

	for (i = 0; i < NR_MUTATIONS; i++) {
		struct klet_kind_register reg = { 0 };
		Elf64_Ehdr *header;
		Elf64_Phdr *segments;
		Elf64_Rela *rel;
		Elf64_Dyn *dyn;
		char what[128];
		size_t copy_length = length;
		int result, saved;

		memcpy(copy, original, length);
		header = (Elf64_Ehdr *)copy;
		segments = (Elf64_Phdr *)(copy + header->e_phoff);
		rel = (Elf64_Rela *)(copy + rela_off);
		dyn = (Elf64_Dyn *)(copy + null_dynamic);
		switch (i) {
		case REL_OBJECT: header->e_type = ET_REL; break;
		case INTERPRETER:
		case TLS_SEGMENT:
			// Add a forbidden header while preserving every required load segment.
			memset(copy + length, 0, copy_capacity - length);
			memcpy(copy + extra_phoff, segments, header->e_phnum * sizeof(*segments));
			header->e_phoff = extra_phoff;
			segments = (Elf64_Phdr *)(copy + extra_phoff);
			segments[header->e_phnum] = segments[second_load];
			segments[header->e_phnum++].p_type = i == INTERPRETER ? PT_INTERP : PT_TLS;
			copy_length = copy_capacity;
			break;
		case OVERLAP: segments[second_load].p_vaddr = segments[rx].p_vaddr; break;
		case UNALIGNED: segments[rx].p_vaddr++; break;
		case WRITE_EXEC: segments[rx].p_flags |= PF_W; break;
		case DEPENDENCY: dyn->d_tag = DT_NEEDED; break;
		case CONSTRUCTORS: dyn->d_tag = DT_INIT_ARRAY; break;
		case WRONG_RELOCATION: rel->r_info = ELF64_R_INFO(0, R_X86_64_64); break;
		case SYMBOL_RELOCATION: rel->r_info = ELF64_R_INFO(1, R_X86_64_RELATIVE); break;
		case SHARED_RELOCATION: rel->r_offset = segments[rx].p_vaddr; break;
		case END_RELOCATION: rel->r_offset = image_end - 4; break;
		case OUTSIDE_RELOCATION: rel->r_offset = UINT64_MAX - 7; break;
		case OUTSIDE_ADDEND: rel->r_addend = image_end; break;
		case BAD_ENTRY: header->e_entry = segments[rx].p_vaddr; break;
		case MISSING_PIE:
			((Elf64_Dyn *)(copy + flags_dynamic))->d_tag = DT_DEBUG;
			((Elf64_Dyn *)(copy + flags_dynamic))->d_un.d_val = 0;
			break;
		case CLEARED_PIE:
			((Elf64_Dyn *)(copy + flags_dynamic))->d_un.d_val &= ~DF_1_PIE;
			break;
		case ABI_RELOCATION: rel->r_offset = header->e_entry; break;
		case WRITABLE_RELOCATIONS: segments[rela_segment].p_flags |= PF_W; break;
		}
		reg.image_fd = memfd_create("bad-pie", MFD_CLOEXEC);
		if (reg.image_fd < 0 || write(reg.image_fd, copy, copy_length) != (ssize_t)copy_length)
			exit(1);
		snprintf(reg.name, sizeof(reg.name), "bad-pie-%d", i);
		result = ioctl(sys_fd, KLET_KIND_REGISTER, &reg);
		saved = errno;
		if (result >= 0)
			ioctl(sys_fd, KLET_KIND_UNREGISTER, &(__u32){ result });
		close(reg.image_fd);
		errno = saved;
		snprintf(what, sizeof(what), "PIE loader refuses %s (ENOEXEC)", names[i]);
		refused(result, ENOEXEC, what);
	}
	free(copy);
	free(original);
}

// Gets the number of extant sandboxes, including ones still being destroyed.
static int kind_sandboxes(int sys_fd, int kind)
{
	struct klet_kind_info kinds[16];
	struct klet_kind_list list = {
		.kinds = (__u64)(unsigned long)kinds, .capacity = 16,
	};

	if (ioctl(sys_fd, KLET_KIND_LIST, &list) < 0)
		return -1;
	for (unsigned int i = 0; i < list.count && i < list.capacity; i++)
		if (kinds[i].id == (unsigned int)kind)
			return kinds[i].nr_sandboxes;
	return -1;
}

static int create(int sys_fd, int kind, unsigned int nr, unsigned long long mem,
		  unsigned long long max, unsigned int cmdline_len, unsigned int flags)
{
	static char cmdline[KLET_CMDLINE_MAX + 2];
	struct klet_create cr = {
		.kind = (__u32)kind, .nr_vcpus = nr, .memory_initial = mem, .memory_max = max,
		.max_tasks = 16, .cmdline = (__u64)(unsigned long)cmdline,
		.cmdline_len = cmdline_len, .flags = flags,
	};

	memset(cmdline, 'x', sizeof(cmdline));
	return ioctl(sys_fd, KLET_CREATE, &cr);
}

static int register_as(int sys_fd, const char *name, const char *path, unsigned int flags)
{
	struct klet_kind_register reg = { .image_fd = open(path, O_RDONLY | O_CLOEXEC),
					  .flags = flags };
	int r, e;

	snprintf(reg.name, sizeof(reg.name), "%s", name);
	r = ioctl(sys_fd, KLET_KIND_REGISTER, &reg);
	e = errno;
	close(reg.image_fd);
	errno = e;
	return r;
}

static struct klet_stats stats(int fd, struct klet_vcpu_stat *rows, unsigned int cap)
{
	struct klet_stats st = { .vcpus = (__u64)(unsigned long)rows, .capacity = cap };

	if (ioctl(fd, KLET_GET_STATS, &st) < 0)
		memset(&st, 0xff, sizeof(st));
	return st;
}

static int get_exec(int fd, unsigned int vcpu)
{
	return ioctl(fd, KLET_GET_VCPU_EXEC_FD, &vcpu);
}

/*
 * A child that executes exec_fd: with or without no-new-privileges, from
 * another control group or not. Returns its pid; if the exec fails, the
 * child's exit status is the errno.
 */
static pid_t exec_child(int exec_fd, int nnp, const char *cgroup)
{
	pid_t pid = fork();

	if (pid == 0) {
		char *argv[] = { "carrier", NULL }, *envp[] = { NULL };

		if (cgroup)
			join_cgroup(cgroup);
		if (nnp)
			prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
		execveat(exec_fd, "", argv, envp, AT_EMPTY_PATH);
		_exit(errno);
	}
	return pid;
}

/* The errno an exec failed with, or -1 if it did not fail. */
static int exec_errno(pid_t pid)
{
	int status = 0;

	waitpid(pid, &status, 0);
	return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static void exec_refused(int exec_fd, int nnp, const char *cgroup, int err, const char *what)
{
	char how[64];
	int e = exec_errno(exec_child(exec_fd, nnp, cgroup));

	snprintf(how, sizeof(how), "errno %d, not %d", e, err);
	ok(e == err, what, how);
}

/* Waits up to ms for the vCPU's state to become want. */
static int vcpu_state_becomes(int fd, unsigned int vcpu, unsigned int want, int ms)
{
	struct klet_vcpu_stat rows[KLET_MAX_VCPUS];

	for (; ms > 0; ms -= 5) {
		stats(fd, rows, KLET_MAX_VCPUS);
		if (rows[vcpu].state == want)
			return 1;
		msleep(5);
	}
	return 0;
}

static int file_has(const char *path, const char *needle)
{
	char buf[4096];
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	ssize_t n = fd < 0 ? -1 : read(fd, buf, sizeof(buf) - 1);

	if (fd >= 0)
		close(fd);
	if (n <= 0)
		return 0;
	buf[n] = 0;
	return strstr(buf, needle) != NULL;
}

// Leave a blocking read interrupted instead of automatically restarting it.
static void read_alarm(int signal)
{
	(void)signal;
}

// Report the failed setup operation before ending the test.
static _Noreturn void setup_failed(const char *operation)
{
	sandbox_say("FAIL descriptor test setup: %s: errno %d (%s)", operation, errno, strerror(errno));
	exit(1);
}

// Bound the wait for the child reader and distinguish timeout from syscall failure.
static void await_reader(struct pollfd *pfd)
{
	int result = poll(pfd, 1, 3000);

	if (result == 1 && (pfd->revents & POLLIN))
		return;
	if (result >= 0)
		errno = result == 0 ? ETIMEDOUT : EPIPE;
	setup_failed("wait for child reader");
}

// Check readiness, immutable exit reads and ownership through ordinary descriptors.
static void descriptor_contract(int sys_fd, int kind)
{
	struct klet_exit ex, second, zero = { 0 };
	struct klet_stats st;
	struct epoll_event event = { .events = EPOLLIN }, observed;
	struct pollfd pfd;
	struct timeval timeout = { 0 };
	fd_set reads;
	unsigned char oversized[sizeof(ex) + 8];
	int fd = create(sys_fd, kind, 1, 4 << 20, 4 << 20, 0, 0);
	int epfd, pipes[2], flags, duplicate, interrupted, status;
	pid_t reader;
	__u32 reason = 19;

	if (fd < 0)
		setup_failed("KLET_CREATE");
	epfd = epoll_create1(EPOLL_CLOEXEC);
	if (epfd < 0)
		setup_failed("epoll_create1");
	if (pipe2(pipes, O_CLOEXEC))
		setup_failed("pipe2");
	refused(lseek(fd, 0, SEEK_SET), ESPIPE, "sandbox descriptors cannot be sought (ESPIPE)");
	st = stats(fd, NULL, 0);
	ok(!memcmp(&st.exit, &zero, sizeof(zero)), "exit statistics are zero before exit", "nonzero record");
	ok(read(fd, &ex, 0) == 0, "zero-length read returns immediately before exit", strerror(errno));
	refused(read(fd, &ex, sizeof(ex) - 1), EINVAL, "short read buffer before exit (EINVAL)");
	flags = fcntl(fd, F_GETFL);
	if (flags < 0)
		setup_failed("fcntl F_GETFL");
	if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0)
		setup_failed("fcntl F_SETFL O_NONBLOCK");
	refused(read(fd, &ex, sizeof(ex)), EAGAIN, "nonblocking read before exit (EAGAIN)");
	if (fcntl(fd, F_SETFL, flags) < 0)
		setup_failed("fcntl F_SETFL restore blocking mode");
	FD_ZERO(&reads);
	FD_SET(fd, &reads);
	ok(select(fd + 1, &reads, NULL, NULL, &timeout) == 0,
	   "select: no readability before exit", "unexpected readiness");
	event.data.fd = fd;
	if (epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &event))
		setup_failed("epoll_ctl ADD");
	ok(epoll_wait(epfd, &observed, 1, 0) == 0, "epoll: no readability before exit", "unexpected readiness");
	reader = fork();
	if (reader < 0)
		setup_failed("fork child reader");
	if (reader == 0) {
		struct sigaction action = { .sa_handler = read_alarm };
		ssize_t size;

		close(pipes[0]);
		if (sigaction(SIGALRM, &action, NULL))
			setup_failed("sigaction SIGALRM");
		alarm(1);
		size = read(fd, &ex, sizeof(ex));
		interrupted = size == -1 && errno == EINTR;
		if (write(pipes[1], &interrupted, sizeof(interrupted)) != sizeof(interrupted))
			setup_failed("write child interruption result");
		size = read(fd, &ex, sizeof(ex));
		if (size != sizeof(ex)) {
			if (size >= 0)
				errno = EIO;
			setup_failed("read child exit record");
		}
		if (write(pipes[1], &ex, sizeof(ex)) != sizeof(ex))
			setup_failed("write child exit record");
		_exit(0);
	}
	close(pipes[1]);
	pfd = (struct pollfd){ .fd = pipes[0], .events = POLLIN };
	await_reader(&pfd);
	ok(read(pipes[0], &interrupted, sizeof(interrupted)) == sizeof(interrupted) && interrupted,
	   "blocking read is interruptible by a signal", "read did not return EINTR");
	ok(poll(&pfd, 1, 100) == 0, "blocking read waits while the sandbox lives", "returned before exit");
	if (ioctl(fd, KLET_KILL, &reason))
		setup_failed("KLET_KILL to release reader");
	await_reader(&pfd);
	ok(read(pipes[0], &ex, sizeof(ex)) == sizeof(ex) && ex.how == KLET_END_KILLED && ex.reason == reason,
	   "blocking read wakes with the final exit record", "missing or wrong record");
	close(pipes[0]);
	if (waitpid(reader, &status, 0) != reader)
		setup_failed("waitpid child reader");
	if (!WIFEXITED(status) || WEXITSTATUS(status)) {
		sandbox_say("FAIL descriptor test child reader: wait status %#x", status);
		exit(1);
	}
	memset(oversized, 0xa5, sizeof(oversized));
	ok(read(fd, oversized, sizeof(oversized)) == sizeof(ex) &&
	   !memcmp(oversized, &ex, sizeof(ex)) && oversized[sizeof(ex)] == 0xa5,
	   "oversized read returns exactly one record", "wrong size, data or overwritten tail");
	ok(read(fd, &second, sizeof(second)) == sizeof(second) && !memcmp(&second, &ex, sizeof(ex)),
	   "repeated reads return the same record without EOF", "record changed or consumed");
	ok(read(fd, &second, 0) == 0, "zero-length read after exit returns zero", strerror(errno));
	refused(read(fd, &second, sizeof(second) - 1), EINVAL, "short read buffer after exit (EINVAL)");
	refused(syscall(SYS_read, fd, (void *)1, sizeof(ex)), EFAULT, "bad exit record destination (EFAULT)");
	pfd = (struct pollfd){ .fd = fd, .events = POLLIN };
	ok(poll(&pfd, 1, 0) == 1 && (pfd.revents & POLLIN),
	   "poll remains readable after repeated and failed reads", "not readable");
	FD_ZERO(&reads);
	FD_SET(fd, &reads);
	timeout = (struct timeval){ 0 };
	ok(select(fd + 1, &reads, NULL, NULL, &timeout) == 1 && FD_ISSET(fd, &reads),
	   "select remains readable after reading the record", "not readable");
	ok(epoll_wait(epfd, &observed, 1, 0) == 1 && (observed.events & EPOLLIN),
	   "epoll reports exit after reading the record", "not readable");
	ok(epoll_wait(epfd, &observed, 1, 0) == 1 && (observed.events & EPOLLIN),
	   "level-triggered epoll keeps reporting exit", "readiness consumed");
	st = stats(fd, NULL, 0);
	ok(st.state == KLET_STATE_EXITED && !memcmp(&st.exit, &ex, sizeof(ex)),
	   "exit statistics match the immutable read record", "wrong state or record");
	close(epfd);
	duplicate = dup(fd);
	if (duplicate < 0)
		setup_failed("dup exited sandbox");
	close(fd);
	ok(kind_sandboxes(sys_fd, kind) == 1 && read(duplicate, &second, sizeof(second)) == sizeof(second) &&
	   !memcmp(&second, &ex, sizeof(ex)), "duplicate retains the sandbox and its record after close", "not retained");
	refused(ioctl(sys_fd, KLET_KIND_UNREGISTER, &(__u32){ kind }), EBUSY,
		"an exited sandbox with an open duplicate retains its kind (EBUSY)");
	close(duplicate);
	ok(kind_sandboxes(sys_fd, kind) == 0, "last duplicate close releases the exited sandbox", "kind still referenced");
}

// Two sandboxes, each with one virtual CPU, run at once.
static void two_at_once(int sys_fd, int k1, int k2)
{
	const char *cons[2] = { "/check-1.console", "/check-2.console" };
	int kinds[2] = { k1, k2 }, fds[2], i;
	pid_t pids[2];
	struct klet_exit ex[2];
	struct sandbox_opts opt;
	char what[96];

	sandbox_opts_init(&opt);
	for (i = 0; i < 2; i++) {
		int out, exec_fd;

		fds[i] = create(sys_fd, kinds[i], 1, 4 << 20, 4 << 20, 0, 0);
		if (fds[i] < 0) {
			ok(0, "two sandboxes at once: KLET_CREATE", strerror(errno));
			exit(1);
		}
		out = open(cons[i], O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
		ioctl(fds[i], KLET_SET_CONSOLE, &out);
		close(out);
		exec_fd = get_exec(fds[i], 0);
		pids[i] = fork();
		if (pids[i] == 0)
			start_carrier(exec_fd, 0, &opt);
		close(exec_fd);
	}
	for (i = 0; i < 2; i++) {
		struct klet_stats st;

		wait_sandbox(fds[i], &pids[i], 1, &ex[i]);
		waitpid(pids[i], NULL, 0);
		st = stats(fds[i], NULL, 0);
		snprintf(what, sizeof(what), "two sandboxes at once: sandbox %u (kind %d) powered off with exit code 0",
			 st.slot, kinds[i]);
		ok(ex[i].how == KLET_END_EXITED && ex[i].code == 0, what, "another end");
		ok(st.state == KLET_STATE_EXITED && !memcmp(&st.exit, &ex[i], sizeof(ex[i])),
		   "two sandboxes at once: statistics match the exit record", "wrong record");
		close(fds[i]);
		snprintf(what, sizeof(what), "two sandboxes at once: %s holds \"Hello, world\"", cons[i]);
		ok(file_has(cons[i], "Hello, world"), what, "it does not");
	}
}

int main(int argc, char **argv)
{
	struct klet_kind_info info[8];
	struct klet_kind_list list = { .kinds = (__u64)(unsigned long)info, .capacity = 8 };
	struct klet_vcpu_stat rows[KLET_MAX_VCPUS];
	struct klet_stats st;
	struct klet_exit ex;
	struct stat sb;
	struct pollfd pfd;
	int sys_fd, kind, kind2, fd, fd2, e0, e0b, e1, n, i;
	pid_t carrier;
	char c = 0, how[128];
	__u32 reason;

	sandbox_who = "UAPI-CHECK";
	if (argc != 2) {
		sandbox_say("usage: uapi-check IMAGE");
		return 2;
	}
	sys_fd = open_system();
	ok(ioctl(sys_fd, KLET_GET_API_VERSION) == KLET_API_VERSION, "KLET_GET_API_VERSION is 2", "not 2");

	/* KLET_KIND_REGISTER */
	refused(register_as(sys_fd, "check", argv[1], 1), EINVAL, "KLET_KIND_REGISTER refuses nonzero flags (EINVAL)");
	refused(register_as(sys_fd, "", argv[1], 0), EINVAL, "KLET_KIND_REGISTER refuses an empty name (EINVAL)");
	refused(register_as(sys_fd, "notanimage", "/holder", 0), ENOEXEC,
		"KLET_KIND_REGISTER refuses an executable outside the PIE contract (ENOEXEC)");
	malformed_images(sys_fd, argv[1]);
	kind = register_as(sys_fd, "check", argv[1], 0);
	ok(kind >= 0, "KLET_KIND_REGISTER registers the image", strerror(errno));
	refused(register_as(sys_fd, "check", argv[1], 0), EEXIST, "KLET_KIND_REGISTER refuses a name taken (EEXIST)");
	kind2 = register_as(sys_fd, "check2", argv[1], 0);
	ok(kind2 >= 0 && kind2 != kind, "KLET_KIND_REGISTER registers the same image as a second kind", strerror(errno));

	/* KLET_KIND_LIST */
	list.capacity = 0;
	ok(ioctl(sys_fd, KLET_KIND_LIST, &list) == 0 && list.count == 2,
	   "KLET_KIND_LIST with no room counts both kinds", "not 2");
	list.capacity = 8;
	ok(ioctl(sys_fd, KLET_KIND_LIST, &list) == 0 && list.count == 2 &&
	   strcmp(info[0].name, "check") == 0 && info[0].nr_sandboxes == 0 && info[0].text_bytes > 0,
	   "KLET_KIND_LIST reports the kinds: name, no sandbox, the shared text's size", "wrong");

	/* KLET_CREATE */
	refused(create(sys_fd, kind, 1, 4 << 20, 4 << 20, 0, 0), EPERM,
		"KLET_CREATE refuses the root control group (EPERM)");
	join_cgroup(CG_SELF);
	descriptor_contract(sys_fd, kind);
	refused(create(sys_fd, 99, 1, 4 << 20, 4 << 20, 0, 0), ENOENT, "KLET_CREATE refuses an unknown kind (ENOENT)");
	refused(create(sys_fd, kind, 0, 4 << 20, 4 << 20, 0, 0), EINVAL, "KLET_CREATE refuses 0 virtual CPUs (EINVAL)");
	refused(create(sys_fd, kind, KLET_MAX_VCPUS + 1, 4 << 20, 4 << 20, 0, 0), EINVAL,
		"KLET_CREATE refuses KLET_MAX_VCPUS + 1 virtual CPUs (EINVAL)");
	refused(create(sys_fd, kind, 1, 8 << 20, 8 << 20, 0, 0), EINVAL,
		"KLET_CREATE refuses memory_initial above the prototype's 4 MiB (EINVAL)");
	refused(create(sys_fd, kind, 1, 4 << 20, 2 << 20, 0, 0), EINVAL,
		"KLET_CREATE refuses memory_initial above memory_max (EINVAL)");
	refused(create(sys_fd, kind, 1, 4 << 20, 4 << 20, KLET_CMDLINE_MAX + 1, 0), EINVAL,
		"KLET_CREATE refuses a command line longer than KLET_CMDLINE_MAX (EINVAL)");
	refused(create(sys_fd, kind, 1, 4 << 20, 4 << 20, 0, 1), EINVAL, "KLET_CREATE refuses nonzero flags (EINVAL)");

	/* A sandbox of two virtual CPUs, 3 MiB rounded up to 4. */
	fd = create(sys_fd, kind, 2, 3 << 20, 5 << 20, 12, 0);
	ok(fd >= 0 && (fcntl(fd, F_GETFD) & FD_CLOEXEC), "KLET_CREATE returns a close-on-exec sandbox descriptor", strerror(errno));
	fd2 = create(sys_fd, kind, 1, 4 << 20, 4 << 20, 0, 0);
	ok(fd2 >= 0 && kind_sandboxes(sys_fd, kind) == 2,
	   "KLET_CREATE permits two live sandboxes of the same kind", strerror(errno));
	if (fd2 >= 0)
		close(fd2);
	list.capacity = 8;
	ioctl(sys_fd, KLET_KIND_LIST, &list);
	ok(info[0].nr_sandboxes == 1, "KLET_KIND_LIST counts the kind's sandbox", "not 1");
	refused(ioctl(sys_fd, KLET_KIND_UNREGISTER, &(__u32){ (__u32)kind }), EBUSY,
		"KLET_KIND_UNREGISTER refuses a kind with a sandbox (EBUSY)");
	st = stats(fd, rows, KLET_MAX_VCPUS);
	ok(st.state == KLET_STATE_CREATED && st.nr_vcpus == 2 && st.memory_granted == 0 &&
	   rows[0].state == KLET_VCPU_UNSTARTED && rows[0].pid == 0,
	   "KLET_GET_STATS: CREATED, 2 vcpus, nothing granted, vcpu 0 unstarted", "wrong");

	refused(ioctl(fd, KLET_ATTACH_DEVICE, &(struct klet_device){ .type = KLET_DEVICE_BLOCK, .fd = 0 }),
		EOPNOTSUPP, "KLET_ATTACH_DEVICE: EOPNOTSUPP in this prototype");
	reason = 0x80000000u;
	refused(ioctl(fd, KLET_KILL, &reason), EINVAL, "KLET_KILL refuses the endovisor's own reasons (EINVAL)");
	refused(get_exec(fd, 2), EINVAL, "KLET_GET_VCPU_EXEC_FD refuses a virtual CPU beyond nr_vcpus (EINVAL)");

	/* The exec descriptors. */
	e0 = get_exec(fd, 0);
	e0b = get_exec(fd, 0);
	e1 = get_exec(fd, 1);
	ok(e0 >= 0 && e0b >= 0 && e1 >= 0 && (fcntl(e0, F_GETFD) & FD_CLOEXEC),
	   "KLET_GET_VCPU_EXEC_FD: close-on-exec descriptors, a second one for the same virtual CPU too", strerror(errno));
	ok(fstat(e0, &sb) == 0 && S_ISREG(sb.st_mode) && (sb.st_mode & 07777) == 0111 &&
	   sb.st_uid == 0 && sb.st_gid == 0, "the exec descriptor's file is root's, regular and execute-only (0111)", "not so");
	{
		struct stat sb2;

		ok(fstat(e0b, &sb2) == 0 && sb2.st_ino == sb.st_ino && sb2.st_dev == sb.st_dev,
		   "the two descriptors of virtual CPU 0 are on the same inode", "not");
	}
	n = (int)read(e0, &c, 1);
	refused(n, EBADF, "the exec descriptor cannot be read (EBADF)");
	n = (int)write(e0, &c, 1);
	refused(n, EBADF, "the exec descriptor cannot be written (EBADF)");
	refused(fchmod(e0, 0755), EBADF, "the exec descriptor's mode cannot be changed through it (EBADF)");

	/* An exec's refusals, then a start that never boots. */
	exec_refused(e0, 0, NULL, EPERM, "an exec without no-new-privileges is refused (EPERM)");
	exec_refused(e0, 1, CG_OTHER, EPERM, "an exec from another control group is refused (EPERM)");
	{
		int one = 1;

		ok(ioctl(fd, KLET_SET_CONSOLE, &one) == 0, "KLET_SET_CONSOLE before the start", strerror(errno));
	}
	carrier = exec_child(e0, 1, NULL);
	ok(vcpu_state_becomes(fd, 0, KLET_VCPU_WAITING, 3000),
	   "the exec of vcpu 0 makes a carrier, which waits for vcpu 1", "it never arrived");
	st = stats(fd, rows, KLET_MAX_VCPUS);
	snprintf(how, sizeof(how), "state %u, granted %llu, pid %d", st.state,
		 (unsigned long long)st.memory_granted, rows[0].pid);
	ok(st.state == KLET_STATE_STARTING && st.memory_granted == (4 << 20) && rows[0].pid == carrier &&
	   rows[1].state == KLET_VCPU_UNSTARTED && !memcmp(&st.exit, &(struct klet_exit){ 0 }, sizeof(st.exit)),
	   "KLET_GET_STATS: STARTING, 4 MiB granted at the first arrival, vcpu 0's pid, vcpu 1 unstarted", how);
	{
		char comm[64] = "", path[64];
		int cf;

		snprintf(path, sizeof(path), "/proc/%d/comm", carrier);
		cf = open(path, O_RDONLY | O_CLOEXEC);
		if (cf >= 0) {
			n = (int)read(cf, comm, sizeof(comm) - 1);
			comm[n > 0 ? n : 0] = 0;
			comm[strcspn(comm, "\n")] = 0;
			close(cf);
		}
		snprintf(how, sizeof(how), "kernelet/%u/0", st.slot);
		ok(strcmp(comm, how) == 0, "the carrier is named kernelet/<slot>/0", comm);
	}
	refused(get_exec(fd, 0), EBUSY, "KLET_GET_VCPU_EXEC_FD refuses a virtual CPU started already (EBUSY)");
	exec_refused(e0b, 1, NULL, EBUSY, "an exec of a second descriptor of a started virtual CPU is refused (EBUSY)");
	{
		int one = 1;

		refused(ioctl(fd, KLET_SET_CONSOLE, &one), EBUSY, "KLET_SET_CONSOLE after the start (EBUSY)");
		refused(ioctl(fd, KLET_SET_LOG, &one), EBUSY, "KLET_SET_LOG after the start (EBUSY)");
	}
	pfd.fd = fd;
	pfd.events = POLLIN;
	ok(poll(&pfd, 1, 0) == 0, "poll: no POLLIN while the sandbox lives", "POLLIN");
	msleep(200);
	c = proc_task_state(carrier);
	snprintf(how, sizeof(how), "state %c", c);
	/* TASK_KILLABLE | TASK_NOLOAD, which /proc shows as I, idle */
	ok(c == 'I' || c == 'D' || c == 'S', "a sandbox missing a virtual CPU never boots: its carrier waits, not load", how);
	reason = 7;
	ok(ioctl(fd, KLET_KILL, &reason) == 0, "KLET_KILL(7)", strerror(errno));
	ok(ioctl(fd, KLET_KILL, &reason) == 0, "KLET_KILL again: idempotent", strerror(errno));
	ok(read(fd, &ex, sizeof(ex)) == sizeof(ex) && ex.how == KLET_END_KILLED && ex.reason == 7,
	   "sandbox read: KILLED, reason 7", "another end");
	ok(poll(&pfd, 1, 0) == 1 && (pfd.revents & POLLIN), "poll: POLLIN once the sandbox has exited", "none");
	{
		int status = 0;

		waitpid(carrier, &status, 0);
		ok(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL, "the carrier died by SIGKILL", "not");
	}
	refused(get_exec(fd, 1), ESRCH, "KLET_GET_VCPU_EXEC_FD after the kill (ESRCH)");
	exec_refused(e1, 1, NULL, ESRCH, "an exec into a killed sandbox is refused (ESRCH)");
	st = stats(fd, rows, KLET_MAX_VCPUS);
	ok(st.state == KLET_STATE_EXITED && rows[0].state == KLET_VCPU_GONE, "KLET_GET_STATS: EXITED, vcpu 0 gone", "not");
	ok(!memcmp(&st.exit, &ex, sizeof(ex)), "exit statistics agree with the read record", "wrong record");
	memset(&ex, 0, sizeof(ex));
	ok(read(fd, &ex, sizeof(ex)) == sizeof(ex) && ex.how == KLET_END_KILLED && ex.reason == 7,
	   "the exit record stays readable until the last close", "it does not");
	close(e0);
	close(e0b);
	close(e1);
	close(fd);

	/* The last close of a sandbox that never had a carrier: killed and destroyed at once. */
	fd = create(sys_fd, kind, 1, 4 << 20, 4 << 20, 0, 0);
	close(fd);
	ok(kind_sandboxes(sys_fd, kind) == 0,
	   "the last close destroys a sandbox with no carrier and releases its kind reference",
	   "sandbox count is not zero");

	/* The last close of a sandbox with a carrier: killed, destroyed when the carrier is gone. */
	fd = create(sys_fd, kind, 2, 4 << 20, 4 << 20, 0, 0);
	e0 = get_exec(fd, 0);
	carrier = exec_child(e0, 1, NULL);
	close(e0);
	ok(vcpu_state_becomes(fd, 0, KLET_VCPU_WAITING, 3000), "a second sandbox's vcpu 0 arrives", "never");
	fd2 = dup(fd);
	if (fd2 < 0)
		setup_failed("dup live sandbox");
	close(fd);
	ok(kind_sandboxes(sys_fd, kind) == 1 && stats(fd2, NULL, 0).state == KLET_STATE_STARTING &&
	   waitpid(carrier, NULL, WNOHANG) == 0,
	   "closing a nonfinal duplicate leaves the live sandbox and carrier intact", "premature teardown");
	close(fd2);
	{
		int status = 0;

		waitpid(carrier, &status, 0);
		ok(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL,
		   "the last close kills a sandbox's carrier (SIGKILL)", "not");
	}
	for (i = 0; i < 200 && kind_sandboxes(sys_fd, kind) != 0; i++)
		msleep(5);
	snprintf(how, sizeof(how), "sandbox still counted after %d ms", i * 5);
	ok(kind_sandboxes(sys_fd, kind) == 0,
	   "... and the endovisor releases its kind reference once the carrier is gone", how);

	/* Two at once, and the end. */
	two_at_once(sys_fd, kind, kind2);
	two_at_once(sys_fd, kind, kind);
	ok(ioctl(sys_fd, KLET_KIND_UNREGISTER, &(__u32){ (__u32)kind }) == 0 &&
	   ioctl(sys_fd, KLET_KIND_UNREGISTER, &(__u32){ (__u32)kind2 }) == 0,
	   "KLET_KIND_UNREGISTER both kinds", strerror(errno));
	refused(ioctl(sys_fd, KLET_KIND_UNREGISTER, &(__u32){ (__u32)kind }), ENOENT,
		"KLET_KIND_UNREGISTER refuses an unknown kind (ENOENT)");
	close(sys_fd);
	sandbox_say("done: %d ok, %d failed", nr_ok, nr_fail);
	return nr_fail ? 1 : 0;
}
