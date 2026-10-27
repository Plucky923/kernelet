/*
 * uapi-check: the endovisor UAPI's promises, checked one by one against the
 * running endovisor, before the hello boot's own sandbox (make hello).
 *
 *   uapi-check IMAGE
 *
 * IMAGE is a kernelet image (the hello kernel's). Every check prints
 * "UAPI-CHECK ok <what>" or "UAPI-CHECK FAIL <what>: <what happened>", and the
 * last line counts them; the Makefile's check-log requires no FAIL and the
 * number of oks it expects. What is checked: the version; the refusals of
 * KLET_KIND_REGISTER (flags, an empty name, a file that is not an image, a
 * name taken); KLET_KIND_LIST; KLET_CREATE's (the root control group, an
 * unknown kind, the bounds of nr_vcpus, of the memory and of the command line,
 * flags, a second live sandbox of a kind); the exec descriptor's file (root's,
 * execute-only, unreadable and unwritable through the descriptor); an exec's
 * refusals (no no-new-privileges, another control group, a virtual CPU started
 * already, a sandbox killed); a sandbox that never boots because one of its
 * virtual CPUs never arrives, ended by KLET_KILL; the operations that are
 * refused before the exit (KLET_DESTROY) or after the start (KLET_SET_CONSOLE);
 * the prototype's EOPNOTSUPP; poll; the exit record after KLET_DESTROY; the
 * destroy that the last close does, at once or once the carriers are gone; two
 * sandboxes of two kinds running at once, each with its own console; and
 * KLET_KIND_UNREGISTER.
 *
 * Built static, with sandbox.c: gcc -static -O2 -I linux/endovisor/uapi ...
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/stat.h>
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

/* Two sandboxes of two kinds, each with one virtual CPU, run at once. */
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
		ok(ioctl(fds[i], KLET_DESTROY) == 0, "two sandboxes at once: KLET_DESTROY", strerror(errno));
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
	ok(ioctl(sys_fd, KLET_GET_API_VERSION) == KLET_API_VERSION, "KLET_GET_API_VERSION is 1", "not 1");

	/* KLET_KIND_REGISTER */
	refused(register_as(sys_fd, "check", argv[1], 1), EINVAL, "KLET_KIND_REGISTER refuses nonzero flags (EINVAL)");
	refused(register_as(sys_fd, "", argv[1], 0), EINVAL, "KLET_KIND_REGISTER refuses an empty name (EINVAL)");
	refused(register_as(sys_fd, "notanimage", "/holder", 0), ENOEXEC,
		"KLET_KIND_REGISTER refuses an executable that is not a relocatable image (ENOEXEC)");
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
	refused(create(sys_fd, kind, 1, 4 << 20, 4 << 20, 0, 0), EBUSY,
		"KLET_CREATE refuses a second live sandbox of a kind (EBUSY, the prototype's limit)");
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
	refused(ioctl(fd, KLET_DESTROY), EBUSY, "KLET_DESTROY refuses a sandbox that has not exited (EBUSY)");
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
	   rows[1].state == KLET_VCPU_UNSTARTED,
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
	ok(ioctl(fd, KLET_WAIT, &ex) == 0 && ex.how == KLET_END_KILLED && ex.reason == 7,
	   "KLET_WAIT: KILLED, reason 7", "another end");
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
	ok(ioctl(fd, KLET_DESTROY) == 0, "KLET_DESTROY once exited", strerror(errno));
	memset(&ex, 0, sizeof(ex));
	ok(ioctl(fd, KLET_WAIT, &ex) == 0 && ex.how == KLET_END_KILLED && ex.reason == 7,
	   "the exit record stays readable after KLET_DESTROY", "it does not");
	close(e0);
	close(e0b);
	close(e1);
	close(fd);

	/* The last close of a sandbox that never had a carrier: killed and destroyed at once. */
	fd = create(sys_fd, kind, 1, 4 << 20, 4 << 20, 0, 0);
	close(fd);
	fd = create(sys_fd, kind, 1, 4 << 20, 4 << 20, 0, 0);
	ok(fd >= 0, "the last close kills and destroys a sandbox with no carrier: its kind is free again at once",
	   strerror(errno));
	close(fd);

	/* The last close of a sandbox with a carrier: killed, destroyed when the carrier is gone. */
	fd = create(sys_fd, kind, 2, 4 << 20, 4 << 20, 0, 0);
	e0 = get_exec(fd, 0);
	carrier = exec_child(e0, 1, NULL);
	close(e0);
	ok(vcpu_state_becomes(fd, 0, KLET_VCPU_WAITING, 3000), "a second sandbox's vcpu 0 arrives", "never");
	close(fd);
	{
		int status = 0;

		waitpid(carrier, &status, 0);
		ok(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL,
		   "the last close kills a sandbox's carrier (SIGKILL)", "not");
	}
	for (i = 0, fd2 = -1; i < 200 && fd2 < 0; i++) {
		fd2 = create(sys_fd, kind, 1, 4 << 20, 4 << 20, 0, 0);
		if (fd2 < 0)
			msleep(5);
	}
	snprintf(how, sizeof(how), "still EBUSY after %d ms", i * 5);
	ok(fd2 >= 0, "... and the endovisor destroys it itself once the carrier is gone", how);
	if (fd2 >= 0)
		sandbox_say("the kind was free again after %d retry(ies) of 5 ms", i - 1);
	close(fd2);

	/* Two at once, and the end. */
	two_at_once(sys_fd, kind, kind2);
	ok(ioctl(sys_fd, KLET_KIND_UNREGISTER, &(__u32){ (__u32)kind }) == 0 &&
	   ioctl(sys_fd, KLET_KIND_UNREGISTER, &(__u32){ (__u32)kind2 }) == 0,
	   "KLET_KIND_UNREGISTER both kinds", strerror(errno));
	refused(ioctl(sys_fd, KLET_KIND_UNREGISTER, &(__u32){ (__u32)kind }), ENOENT,
		"KLET_KIND_UNREGISTER refuses an unknown kind (ENOENT)");
	close(sys_fd);
	sandbox_say("done: %d ok, %d failed", nr_ok, nr_fail);
	return nr_fail ? 1 : 0;
}
