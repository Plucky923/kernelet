/*
 * sandbox: the client of the endovisor UAPI (linux/endovisor/uapi/endovisor.h).
 *
 * A kernelet runtime, like a container runtime, has one process per sandbox
 * that creates it, keeps its descriptor open for as long as it lives, and
 * destroys it: the sandbox's holder. These are its steps: open the device
 * (open_system), register an image as a kind (register_kind, the operator's
 * step) or find one (find_kind), move into the sandbox's control group
 * (join_cgroup), create the sandbox and start one carrier per virtual CPU
 * (run_sandbox, start_carrier), wait for its end (wait_sandbox), and destroy
 * it. holder.c is the command around them; the experiment drivers
 * (run-sched.c, run-mem.c) and uapi-check.c use them too.
 *
 * Built static, with -I linux/endovisor/uapi.
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <poll.h>
#include <sched.h>
#include <signal.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "sandbox.h"

const char *sandbox_who = "holder";

/* ------------------------------------------------------------------ */
/* Output                                                             */
/* ------------------------------------------------------------------ */

/*
 * One line, written whole into the kernel's log through /dev/kmsg, so that on
 * the serial console it is in order with the endovisor's own messages and
 * never broken by one in the middle, as a line written to the console's
 * terminal can be (printk drives the port directly, the terminal by
 * interrupt). Without /dev/kmsg, to standard output, drained.
 */
void sandbox_say(const char *fmt, ...)
{
	static int kmsg = -2;
	char buf[1024];
	va_list ap;
	int n = snprintf(buf, sizeof(buf), "%s: ", sandbox_who);

	va_start(ap, fmt);
	if (n > 0 && n < (int)sizeof(buf))
		n += vsnprintf(buf + n, sizeof(buf) - n, fmt, ap);
	va_end(ap);
	if (n >= (int)sizeof(buf) - 1)
		n = sizeof(buf) - 2;
	buf[n++] = '\n';
	if (kmsg == -2)
		kmsg = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
	if (kmsg >= 0 && write(kmsg, buf, n) == n)
		return;
	if (write(1, buf, n) < 0)
		return;
	tcdrain(1);
}

static void die(const char *what)
{
	sandbox_say("%s: %s", what, strerror(errno));
	exit(127);
}

/* The same, in a forked child: no flushing of the parent's buffers. */
static void die_child(const char *what)
{
	int err = errno;
	char msg[256];
	int n = snprintf(msg, sizeof(msg), "%s: carrier: %s: %s\n", sandbox_who, what,
			 strerror(err));

	if (n > 0)
		n = (int)write(2, msg, (size_t)n);	/* and nothing better to do if that fails */
	_exit(127);
}

void msleep(int ms)
{
	struct timespec ts = { .tv_sec = ms / 1000, .tv_nsec = (long)(ms % 1000) * 1000000L };

	while (nanosleep(&ts, &ts) < 0 && errno == EINTR)
		;
}

long long now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* ------------------------------------------------------------------ */
/* The interface                                                      */
/* ------------------------------------------------------------------ */

void sandbox_opts_init(struct sandbox_opts *opt)
{
	memset(opt, 0, sizeof(*opt));
	opt->cpu_hi = -1;
	opt->seccomp_kill_nr = -1;
	opt->kill_after_ms = -1;
	opt->klet_kill_after_ms = -1;
	opt->memory_initial = 4 << 20;
	opt->memory_max = 64 << 20;
	opt->max_tasks = 256;
}

/* Open the device and refuse an interface this program does not know. */
int open_system(void)
{
	int sys_fd = open("/dev/endovisor", O_RDWR | O_CLOEXEC);

	if (sys_fd < 0)
		die("/dev/endovisor");
	if (ioctl(sys_fd, KLET_GET_API_VERSION) != KLET_API_VERSION) {
		sandbox_say("/dev/endovisor speaks another version");
		exit(127);
	}
	return sys_fd;
}

/* The operator's step: hand over an image file and name the kind. */
int register_kind(int sys_fd, const char *name, const char *image_path)
{
	struct klet_kind_register reg = { .image_fd = open(image_path, O_RDONLY | O_CLOEXEC) };
	int kind;

	if (reg.image_fd < 0)
		die(image_path);
	snprintf(reg.name, sizeof(reg.name), "%s", name);	/* the name KLET_KIND_LIST reports; unique */
	kind = ioctl(sys_fd, KLET_KIND_REGISTER, &reg);
	if (kind < 0)
		die("KLET_KIND_REGISTER");
	close(reg.image_fd);
	return kind;
}

/* Find a kind by name among those registered. */
int find_kind(int sys_fd, const char *name)
{
	struct klet_kind_info *info = NULL;
	struct klet_kind_list list = { .capacity = 16 };
	unsigned int i;

	do {						/* until the array is large enough */
		free(info);
		info = calloc(list.capacity, sizeof(*info));
		if (!info)
			die("calloc");
		list.kinds = (__u64)(unsigned long)info;
		if (ioctl(sys_fd, KLET_KIND_LIST, &list) < 0)
			die("KLET_KIND_LIST");
		if (list.count > list.capacity)
			list.capacity = list.count;
	} while (list.count > list.capacity);
	for (i = 0; i < list.count; i++)
		if (strcmp(info[i].name, name) == 0) {
			int id = (int)info[i].id;

			free(info);
			return id;
		}
	sandbox_say("no kind named %s is registered", name);
	exit(127);
}

/*
 * Join a control group: write our process identifier into its cgroup.procs.
 * The group is made first if it does not exist yet, which is the runtime's
 * job in a real deployment; the prototype has no runtime above the holder.
 */
void join_cgroup(const char *dir)
{
	char path[4096], pid[32];
	int fd, n;

	if (mkdir(dir, 0755) < 0 && errno != EEXIST)
		die(dir);
	snprintf(path, sizeof(path), "%s/cgroup.procs", dir);
	fd = open(path, O_WRONLY | O_CLOEXEC);
	if (fd < 0)
		die(path);
	n = snprintf(pid, sizeof(pid), "%d\n", getpid());
	if (write(fd, pid, (size_t)n) != n)
		die(path);
	close(fd);
}

/*
 * A seccomp filter that kills the process on system call nr and allows
 * everything else. The architecture is tested first, as every filter must,
 * so that a 32-bit call with the same number is not mistaken for it.
 */
static int install_seccomp_kill(int nr)
{
	struct sock_filter filter[] = {
		BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 1, 0),
		BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
		BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, (unsigned int)nr, 0, 1),
		BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
		BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
	};
	struct sock_fprog prog = {
		.len = sizeof(filter) / sizeof(filter[0]),
		.filter = filter,
	};

	return prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog, 0, 0);
}

/*
 * The child's side: arrange the task with Linux's own system calls, then
 * execute the exec descriptor. Everything set here survives the exec, and
 * the process never returns from it: the endovisor makes it the carrier.
 */
void start_carrier(int exec_fd, unsigned int vcpu, const struct sandbox_opts *opt)
{
	char *argv[] = { "carrier", NULL };
	char *envp[] = { NULL };

	if (opt->pin || opt->cpu_hi >= 0) {		/* virtual CPU i on processor i, or a range */
		cpu_set_t set;
		int cpu;

		CPU_ZERO(&set);
		if (opt->pin)
			CPU_SET(vcpu, &set);
		else
			for (cpu = opt->cpu_lo; cpu <= opt->cpu_hi; cpu++)
				CPU_SET(cpu, &set);
		if (sched_setaffinity(0, sizeof(set), &set) < 0)
			die_child("sched_setaffinity");
	}
	if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0)	/* the endovisor insists on it */
		die_child("PR_SET_NO_NEW_PRIVS");
	/* A seccomp filter bounds what the tenant may ask of its kernelet. */
	if (opt->seccomp_kill_nr >= 0) {
		if (install_seccomp_kill(opt->seccomp_kill_nr) < 0)
			die_child("seccomp");
		sandbox_say("carrier of vcpu %u: seccomp filter installed: system call %d kills the process",
			    vcpu, opt->seccomp_kill_nr);
	}
	execveat(exec_fd, "", argv, envp, AT_EMPTY_PATH);
	die_child("execveat");
}

/*
 * Wait for the sandbox to end. A child that dies before its exec succeeded
 * never became a carrier, so the endovisor does not know it is gone; watch
 * the children through process descriptors and kill the sandbox ourselves
 * if one of them goes while the sandbox is still alive.
 */
void wait_sandbox(int sandbox_fd, const pid_t *pids, unsigned int nr_vcpus, struct klet_exit *ex)
{
	struct pollfd pfd[KLET_MAX_VCPUS + 1];
	unsigned int i;

	pfd[0].fd = sandbox_fd;
	pfd[0].events = POLLIN;				/* readable once the sandbox has exited */
	for (i = 0; i < nr_vcpus; i++) {
		pfd[i + 1].fd = (int)syscall(SYS_pidfd_open, pids[i], 0);
		pfd[i + 1].events = POLLIN;			/* readable once the child has exited */
		if (pfd[i + 1].fd < 0)
			die("pidfd_open");
	}
	for (;;) {
		if (poll(pfd, nr_vcpus + 1, -1) < 0 && errno != EINTR)
			die("poll");
		if (pfd[0].revents & POLLIN)
			break;
		for (i = 0; i < nr_vcpus; i++)
			if (pfd[i + 1].revents & POLLIN) {	/* a child is gone: end the sandbox */
				__u32 reason = 1;

				ioctl(sandbox_fd, KLET_KILL, &reason);
				close(pfd[i + 1].fd);
				pfd[i + 1].fd = -1;		/* polled no more */
			}
	}
	for (i = 0; i < nr_vcpus; i++)
		if (pfd[i + 1].fd >= 0)
			close(pfd[i + 1].fd);
	if (ioctl(sandbox_fd, KLET_WAIT, ex) < 0)
		die("KLET_WAIT");
}

/* ------------------------------------------------------------------ */
/* Helpers for the tests                                              */
/* ------------------------------------------------------------------ */

/* Whether the sandbox has exited, waiting up to timeout_ms for it. */
int sandbox_exited(const struct sandbox *sb, int timeout_ms)
{
	struct pollfd pfd = { .fd = sb->fd, .events = POLLIN };

	return poll(&pfd, 1, timeout_ms) == 1 && (pfd.revents & POLLIN);
}

static const char *const state_name[] = {
	"?", "created", "starting", "running", "dying", "exited",
};
static const char *const vcpu_state_name[] = {
	"unstarted", "waiting", "running", "gone",
};

/* One line of KLET_GET_STATS, and one per virtual CPU. */
void sandbox_print_stats(const struct sandbox *sb, const char *when)
{
	struct klet_vcpu_stat rows[KLET_MAX_VCPUS];
	struct klet_stats st = {
		.vcpus = (__u64)(unsigned long)rows,
		.capacity = KLET_MAX_VCPUS,
	};
	unsigned int i;

	if (ioctl(sb->fd, KLET_GET_STATS, &st) < 0) {
		sandbox_say("KLET_GET_STATS: %s", strerror(errno));
		return;
	}
	sandbox_say("sandbox %u %s: state %u (%s), %u vcpu(s), %llu KiB granted, %llu service call(s), %llu virtual interrupt(s), %llu line(s) dropped",
		    st.slot, when, st.state, st.state <= 5 ? state_name[st.state] : "?",
		    st.nr_vcpus, (unsigned long long)st.memory_granted >> 10,
		    (unsigned long long)st.service_calls, (unsigned long long)st.virqs_raised,
		    (unsigned long long)st.log_dropped);
	for (i = 0; i < st.nr_vcpus && i < KLET_MAX_VCPUS; i++)
		sandbox_say("sandbox %u %s: vcpu %u pid %d state %u (%s), ran %llu ms, waited %llu ms runnable",
			    st.slot, when, i, rows[i].pid, rows[i].state,
			    rows[i].state <= 3 ? vcpu_state_name[rows[i].state] : "?",
			    (unsigned long long)rows[i].run_ns / 1000000,
			    (unsigned long long)rows[i].stolen_ns / 1000000);
}

/* The module's reference count from /proc/modules, read once; -1 if not loaded. */
int module_references(const char *name)
{
	char line[512];
	FILE *f = fopen("/proc/modules", "re");
	int refs = -1;

	if (!f)
		return -1;
	while (fgets(line, sizeof(line), f)) {
		char mod[128];
		unsigned long size;
		int n;

		if (sscanf(line, "%127s %lu %d", mod, &size, &n) == 3 && strcmp(mod, name) == 0) {
			refs = n;
			break;
		}
	}
	fclose(f);
	return refs;
}

/* The value of one line of /proc/<pid>/status ("SigIgn", ...), as text. */
void proc_status_field(long pid, const char *key, char *buf, size_t len)
{
	char path[64], line[256];
	size_t klen = strlen(key);
	FILE *f;

	snprintf(buf, len, "?");
	snprintf(path, sizeof(path), "/proc/%ld/status", pid);
	f = fopen(path, "re");
	if (!f)
		return;
	while (fgets(line, sizeof(line), f))
		if (strncmp(line, key, klen) == 0 && line[klen] == ':') {
			char *v = line + klen + 1;

			v += strspn(v, " \t");
			v[strcspn(v, "\n")] = 0;
			snprintf(buf, len, "%s", v);
			break;
		}
	fclose(f);
}

/* The state letter of /proc/<pid>/stat: R, S, T, ... or '?'. */
char proc_task_state(long pid)
{
	char buf[512], *p;
	ssize_t n;
	int fd;

	snprintf(buf, sizeof(buf), "/proc/%ld/stat", pid);
	fd = open(buf, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return '?';
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return '?';
	buf[n] = 0;
	p = strrchr(buf, ')');
	return p && p[1] && p[2] ? p[2] : '?';
}

/* What --kill-after and --klet-kill-after do: wait, report, end the sandbox. */
static void end_after(struct sandbox *sb, const struct sandbox_opts *opt)
{
	char ign[32], blk[32], pnd[32];
	int ms = opt->kill_after_ms >= 0 ? opt->kill_after_ms : opt->klet_kill_after_ms;

	if (sandbox_exited(sb, ms)) {
		sandbox_say("the sandbox ended by itself within %d ms", ms);
		return;
	}
	sandbox_print_stats(sb, "before the end");
	proc_status_field(sb->pids[0], "SigIgn", ign, sizeof(ign));
	proc_status_field(sb->pids[0], "SigBlk", blk, sizeof(blk));
	proc_status_field(sb->pids[0], "SigPnd", pnd, sizeof(pnd));
	sandbox_say("vcpu 0 carrier (pid %d) SigIgn %s SigBlk %s SigPnd %s", sb->pids[0], ign, blk, pnd);
	if (opt->kill_after_ms >= 0) {
		sandbox_say("SIGKILL to the carrier of vcpu 0 (pid %d) after %d ms", sb->pids[0], ms);
		if (kill(sb->pids[0], SIGKILL) < 0)
			sandbox_say("kill: %s", strerror(errno));
	} else {
		__u32 reason = 1;

		sandbox_say("KLET_KILL(1) after %d ms", ms);
		if (ioctl(sb->fd, KLET_KILL, &reason) < 0)
			sandbox_say("KLET_KILL: %s", strerror(errno));
	}
}

/* ------------------------------------------------------------------ */
/* The holder's side                                                  */
/* ------------------------------------------------------------------ */

/* Open a console or log file for the sandbox, or use one of ours. */
static int out_fd(const char *path, int ours)
{
	int fd;

	if (!path)
		return ours;
	fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0)
		die(path);
	return fd;
}

/* The holder's side: create, configure, start every virtual CPU, wait, destroy. */
int run_sandbox(int sys_fd, const char *name, unsigned int nr_vcpus, const char *cmdline,
		const struct sandbox_opts *opt)
{
	struct klet_create create = {
		.kind = (__u32)find_kind(sys_fd, name),
		.nr_vcpus = nr_vcpus,
		.memory_initial = opt->memory_initial,
		.memory_max = opt->memory_max,
		.max_tasks = opt->max_tasks,
		.cmdline = (__u64)(unsigned long)cmdline,
		.cmdline_len = (__u32)strlen(cmdline),
	};
	struct klet_stats st = { 0 };
	struct sandbox sb = { .sys_fd = sys_fd, .nr_vcpus = nr_vcpus };
	unsigned int i;

	if (opt->cgroup)				/* before the create: the group becomes the sandbox's */
		join_cgroup(opt->cgroup);
	sb.fd = ioctl(sys_fd, KLET_CREATE, &create);
	if (sb.fd < 0)
		die("KLET_CREATE");
	if (!opt->kernel_log) {
		int out = out_fd(opt->console_path, 1), err = out_fd(opt->log_path, 2);

		if (ioctl(sb.fd, KLET_SET_CONSOLE, &out) < 0)
			die("KLET_SET_CONSOLE");
		if (ioctl(sb.fd, KLET_SET_LOG, &err) < 0)
			die("KLET_SET_LOG");
		if (out != 1)
			close(out);			/* the endovisor holds its own reference */
		if (err != 2)
			close(err);
	}
	/* A disk would be attached here: KLET_ATTACH_DEVICE with its open file. */
	if (ioctl(sb.fd, KLET_GET_STATS, &st) < 0)
		die("KLET_GET_STATS");
	sb.slot = (int)st.slot;
	sandbox_say("sandbox %d created: kind %s, %u vcpu(s), cmdline \"%s\"", sb.slot, name,
		    nr_vcpus, cmdline);

	for (i = 0; i < nr_vcpus; i++) {
		int exec_fd = ioctl(sb.fd, KLET_GET_VCPU_EXEC_FD, &i);

		if (exec_fd < 0)
			die("KLET_GET_VCPU_EXEC_FD");
		sb.pids[i] = fork();
		if (sb.pids[i] < 0)
			die("fork");
		if (sb.pids[i] == 0)
			start_carrier(exec_fd, i, opt);	/* does not return */
		close(exec_fd);
	}

	if (opt->during)
		opt->during(&sb, opt->arg);
	if (opt->kill_after_ms >= 0 || opt->klet_kill_after_ms >= 0)
		end_after(&sb, opt);

	wait_sandbox(sb.fd, sb.pids, nr_vcpus, &sb.ex);		/* until the sandbox has ended */
	for (i = 0; i < nr_vcpus; i++)
		waitpid(sb.pids[i], NULL, 0);		/* the carriers died by SIGKILL */
	sandbox_print_stats(&sb, "at its end");
	if (ioctl(sb.fd, KLET_DESTROY) < 0)
		die("KLET_DESTROY");
	close(sb.fd);

	switch (sb.ex.how) {
	case KLET_END_EXITED:
		sandbox_say("sandbox %d exited: the kernel proper powered off, exit code %d", sb.slot,
			    sb.ex.code);
		return sb.ex.code;
	case KLET_END_PANICKED:
		sandbox_say("sandbox %d: the kernelet panicked: %.*s", sb.slot, KLET_MESSAGE_LEN,
			    sb.ex.message);
		return 128;
	default:
		sandbox_say("sandbox %d was killed: reason %#x", sb.slot, sb.ex.reason);
		return 129;
	}
}

/*
 * What the Makefile stages beside a driver, in /tests/10-<name>.arg: the
 * driver's mode on the first line, the number of virtual CPUs on the second,
 * the sandbox's command line on the third. Returns 0, or -1 if the file is
 * missing.
 */
int sandbox_read_staged(const char *path, char *mode, size_t mode_len, unsigned int *nr_vcpus,
			char *cmdline, size_t cmdline_len)
{
	char line[KLET_CMDLINE_MAX];
	FILE *f = fopen(path, "re");
	int n = 0;

	snprintf(mode, mode_len, "plain");
	*nr_vcpus = 1;
	snprintf(cmdline, cmdline_len, "%s", "");
	if (!f)
		return -1;
	while (fgets(line, sizeof(line), f)) {
		line[strcspn(line, "\n")] = 0;
		if (n == 0)
			snprintf(mode, mode_len, "%s", line);
		else if (n == 1)
			*nr_vcpus = (unsigned int)atoi(line);
		else if (n == 2)
			snprintf(cmdline, cmdline_len, "%s", line);
		n++;
	}
	fclose(f);
	return 0;
}
