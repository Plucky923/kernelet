/*
 * run-probe: the kernelet runtime for the probe kernel.
 *
 * Like run-hello it forks, drops the ability to gain privileges, and execs the
 * sandbox's .klet file, which the endovisor's binary-format handler turns into
 * the root carrier of a kernelet.
 *
 * Before that, it reads the vCPU carrier's signal dispositions from
 * /proc/<pid>/status: after the probe's four faults, each a signal Linux
 * forced on the carrier by setting it back to its default, every signal but
 * SIGKILL and SIGSTOP must be ignored again, none blocked and none pending.
 *
 * Then it does the one thing run-hello does not: it destroys the sandbox from
 * outside, by killing the root carrier. The probe kernel's last system call
 * spins inside the kernelet for ever, so the only way that carrier's CPU comes
 * back is for the endovisor to evict it. Success is that everything dies, the
 * module's reference count reaches zero, and init can unload it.
 *
 * Built static: gcc -static -O2 -o run-probe run-probe.c
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
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

int main(void)
{
	char *const argv[] = { (char *)KLET_PATH, NULL };
	char *const envp[] = { NULL };
	int status = 0;
	pid_t pid, done;

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
		execve(KLET_PATH, argv, envp);
		outf("RUN-PROBE: execve %s failed: %s\n", KLET_PATH,
		     strerror(errno));
		_exit(127);
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

	if (done < 0)
		outf("RUN-PROBE: waitpid failed: %s\n", strerror(errno));
	else if (WIFEXITED(status))
		outf("RUN-PROBE: root carrier (pid %d) exited %d\n", pid,
		     WEXITSTATUS(status));
	else if (WIFSIGNALED(status))
		outf("RUN-PROBE: root carrier (pid %d) killed by signal %d\n",
		     pid, WTERMSIG(status));

	wait_for_module_idle(10000);
	out("RUN-PROBE: done\n");
	return 0;
}
