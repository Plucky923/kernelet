/*
 * run-probe: the kernelet runtime for the probe kernel.
 *
 * Like run-hello it forks, drops the ability to gain privileges, and execs the
 * sandbox's .klet file, which the endovisor's binary-format handler turns into
 * the root carrier of a kernelet. What it does next depends on the word in
 * /tests/10-probe.arg.
 *
 * With no word, it waits a second, in which the probe's tenant takes its four
 * faults, each a signal Linux forced on the carrier by setting it back to its
 * default; then it reads the vCPU carrier's signal dispositions from
 * /proc/<pid>/status, where every signal but SIGKILL and SIGSTOP must be
 * ignored again, none blocked and none pending. Then it does the one thing
 * run-hello does not: it destroys the sandbox from outside, by killing the
 * root carrier. The probe kernel's last system call spins inside the kernelet
 * for ever, so the only way that carrier's CPU comes back is for the
 * endovisor to evict it. Success is that everything dies, the module's
 * reference count reaches zero, and init can unload it.
 *
 * With "seccomp", the child also installs, before the exec, a seccomp filter
 * that kills the process on system call 1000, the probe's endless one; every
 * carrier inherits it. Seccomp runs before the gate's syscall hook, so the
 * kernelet never sees that call: Linux kills the carrier with SIGSYS, and the
 * carrier's death must end the sandbox by itself, with nobody killing the
 * root carrier, and leave no warning behind.
 *
 * Built static: gcc -static -O2 -o run-probe run-probe.c
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define KLET_PATH "/probe.klet"
/* The probe's endless system call, the one the seccomp filter kills on. */
#define SYS_SPIN 1000
#define MODULE_NAME "kernelet"

/* How long the sandbox is left running before it is destroyed. The probe
 * reaches its spinning system call in microseconds; this is generous. */
#define RUN_MS 1000

static void out(const char *s)
{
	size_t len = strlen(s);
	ssize_t n;

	while (len > 0) {
		n = write(1, s, len);
		if (n <= 0)
			return;
		s += n;
		len -= (size_t)n;
	}
	tcdrain(1);
}

__attribute__((format(printf, 1, 2)))
static void outf(const char *fmt, ...)
{
	char buf[256];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	out(buf);
}

static void msleep(int ms)
{
	struct timespec ts = {
		.tv_sec = ms / 1000,
		.tv_nsec = (long)(ms % 1000) * 1000 * 1000,
	};

	nanosleep(&ts, NULL);
}

static int module_refcount(void)
{
	char line[512];
	FILE *f;
	int refs = -1;

	f = fopen("/proc/modules", "re");
	if (!f)
		return -1;
	while (fgets(line, sizeof(line), f)) {
		char name[128];
		unsigned long size;
		int n;

		if (sscanf(line, "%127s %lu %d", name, &size, &n) != 3)
			continue;
		if (strcmp(name, MODULE_NAME) == 0) {
			refs = n;
			break;
		}
	}
	fclose(f);
	return refs;
}

static void wait_for_module_idle(int timeout_ms)
{
	int waited = 0;
	int refs;

	for (;;) {
		refs = module_refcount();
		if (refs <= 0)
			break;
		if (waited >= timeout_ms) {
			outf("RUN-PROBE: module still has %d reference(s) after %d ms\n",
			     refs, waited);
			return;
		}
		msleep(5);
		waited += 5;
	}
	outf("RUN-PROBE: no carrier left (module references: %d)\n",
	     refs < 0 ? 0 : refs);
}

/* The pid of the carrier of vCPU 0, from the endovisor's line in /dev/kmsg. */
static long vcpu0_pid(void)
{
	static const char needle[] = "vcpu 0 carrier starting (pid ";
	char rec[1024];
	long pid = -1;
	int fd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);

	if (fd < 0)
		return -1;
	for (;;) {
		ssize_t n = read(fd, rec, sizeof(rec) - 1);
		char *p;

		if (n < 0 && errno == EPIPE)
			continue;
		if (n <= 0)
			break;
		rec[n] = 0;
		p = strstr(rec, needle);
		if (p) {
			pid = strtol(p + sizeof(needle) - 1, NULL, 10);
			break;
		}
	}
	close(fd);
	return pid;
}

/* The value of one line of /proc/<pid>/status ("SigIgn", ...), as text. */
static void status_field(long pid, const char *key, char *buf, size_t len)
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

/*
 * Kills the process on SYS_SPIN, allows everything else. The architecture is
 * tested first, as every filter must, so that a 32-bit call with the same
 * number is not mistaken for it.
 */
static int install_seccomp_filter(void)
{
	struct sock_filter filter[] = {
		BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 1, 0),
		BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
		BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
		BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_SPIN, 0, 1),
		BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
		BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
	};
	struct sock_fprog prog = {
		.len = sizeof(filter) / sizeof(filter[0]),
		.filter = filter,
	};

	return prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog, 0, 0);
}

/* Waits up to timeout_ms for the root carrier to end by itself. */
static pid_t wait_for_root(pid_t pid, int *status, int timeout_ms, int *waited)
{
	pid_t done;

	for (*waited = 0;; *waited += 5) {
		done = waitpid(pid, status, WNOHANG);
		if (done != 0 || *waited >= timeout_ms)
			return done;
		msleep(5);
	}
}

static void report_root(pid_t pid, pid_t done, int status)
{
	if (done < 0)
		outf("RUN-PROBE: waitpid failed: %s\n", strerror(errno));
	else if (WIFEXITED(status))
		outf("RUN-PROBE: root carrier (pid %d) exited %d\n", pid,
		     WEXITSTATUS(status));
	else if (WIFSIGNALED(status))
		outf("RUN-PROBE: root carrier (pid %d) killed by signal %d\n",
		     pid, WTERMSIG(status));
}

int main(void)
{
	char *const argv[] = { (char *)KLET_PATH, NULL };
	char *const envp[] = { NULL };
	int status = 0, seccomp = 0;
	char arg[64] = "";
	pid_t pid, done;
	int fd;

	fd = open("/tests/10-probe.arg", O_RDONLY);
	if (fd >= 0) {
		ssize_t n = read(fd, arg, sizeof(arg) - 1);

		if (n > 0)
			arg[n] = 0;
		close(fd);
	}
	arg[strcspn(arg, "\n")] = 0;
	seccomp = strcmp(arg, "seccomp") == 0;

	out("RUN-PROBE: creating a sandbox from " KLET_PATH "\n");

	pid = fork();
	if (pid < 0) {
		outf("RUN-PROBE: fork failed: %s\n", strerror(errno));
		return 1;
	}
	if (pid == 0) {
		if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0)
			outf("RUN-PROBE: PR_SET_NO_NEW_PRIVS failed: %s\n",
			     strerror(errno));
		if (seccomp) {
			if (install_seccomp_filter() != 0)
				outf("RUN-PROBE: the seccomp filter failed: %s\n",
				     strerror(errno));
			else
				outf("RUN-PROBE: seccomp filter installed: system call %d kills the process\n",
				     SYS_SPIN);
		}
		execve(KLET_PATH, argv, envp);
		outf("RUN-PROBE: execve %s failed: %s\n", KLET_PATH,
		     strerror(errno));
		_exit(127);
	}

	if (seccomp) {
		int waited;

		/*
		 * Nobody kills anything: the filter's kill of the vCPU carrier
		 * must end the sandbox, the root carrier included, by itself.
		 */
		done = wait_for_root(pid, &status, 10000, &waited);
		if (done == 0) {
			outf("RUN-PROBE: the sandbox outlived the seccomp kill by %d ms; killing the root carrier (pid %d)\n",
			     waited, pid);
			kill(pid, SIGKILL);
			do {
				done = waitpid(pid, &status, 0);
			} while (done < 0 && errno == EINTR);
		} else {
			outf("RUN-PROBE: the sandbox ended by itself, %d ms after it was created\n",
			     waited);
		}
		report_root(pid, done, status);
		wait_for_module_idle(10000);
		out("RUN-PROBE: done\n");
		return 0;
	}

	msleep(RUN_MS);

	{
		long vpid = vcpu0_pid();
		char ign[32], blk[32], pnd[32];

		status_field(vpid, "SigIgn", ign, sizeof(ign));
		status_field(vpid, "SigBlk", blk, sizeof(blk));
		status_field(vpid, "SigPnd", pnd, sizeof(pnd));
		outf("RUN-PROBE: vcpu 0 carrier SigIgn %s SigBlk %s SigPnd %s (pid %ld)\n",
		     ign, blk, pnd, vpid);
	}

	outf("RUN-PROBE: destroying the sandbox: SIGKILL to the root carrier (pid %d)\n",
	     pid);
	if (kill(pid, SIGKILL) != 0)
		outf("RUN-PROBE: kill failed: %s\n", strerror(errno));

	do {
		done = waitpid(pid, &status, 0);
	} while (done < 0 && errno == EINTR);

	report_root(pid, done, status);

	wait_for_module_idle(10000);
	out("RUN-PROBE: done\n");
	return 0;
}
