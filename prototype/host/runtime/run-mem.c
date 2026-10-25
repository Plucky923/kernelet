// SPDX-License-Identifier: GPL-2.0
/*
 * run-mem: the runtime of the memory test kernel (mem/).
 *
 * Creates a sandbox from /mem.klet and waits for it, as run-hello does. What
 * else it does around the sandbox is named in /tests/10-mem.arg:
 *
 *  - "pressure" (E7): turns on swap on /dev/vda and, once the kernelet has
 *    printed E7-MAPPED (watched in /dev/kmsg), runs a memory hog in a host
 *    process until /proc/vmstat shows that reclaim has run and swapped out at
 *    least HOG_SWAP_PAGES pages, then frees it. The kernelet's tenant is
 *    spinning in user mode all that time; afterwards it reads every page back.
 *  - "kill" (E11): once the kernelet has said it is ready, has Linux preempt
 *    the carrier of virtual CPU 1 (a competitor pinned to its processor),
 *    reads both carriers' signal dispositions (SigIgn, SigBlk) from
 *    /proc/<pid>/status, sends it SIGTERM and SIGUSR1 (and the root carrier
 *    a SIGTERM), and then a burst of the core-dump and stop signals,
 *    SIGQUIT, SIGABRT, SIGTSTP, SIGTTIN and SIGTTOU (and the root carrier a
 *    SIGQUIT and a SIGTSTP), all of which must leave both alive and running,
 *    stops it with SIGSTOP and lets it go on with SIGCONT,
 *    and then kills it with SIGKILL, while vCPU 0's tenant thread keeps
 *    faulting in the same address space. The kill must end the whole
 *    sandbox. Meanwhile vCPU 1's tenant runs the rewind check.
 *  - "killidle" and "killspin": once the kernelet says vCPU 1 is idle in
 *    vcpu_idle, or spinning in a kernel task, kills the carrier of vCPU 1 with
 *    SIGKILL and reports how long the sandbox took to end. Linux acts on a
 *    SIGKILL only on the way to user mode, where neither carrier is going.
 */
#define _GNU_SOURCE

#include <errno.h>
#include <sched.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define KLET_PATH "/mem.klet"
#define MODULE_NAME "endovisor"
#define HOG_SWAP_PAGES 30000UL		/* 117 MiB swapped out */
#define HOG_MAX_MB 900UL
#define HOG_CHUNK (4UL << 20)

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
	char buf[512];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	out(buf);
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
	struct timespec ts = { .tv_sec = 0, .tv_nsec = 5 * 1000 * 1000 };
	int waited = 0, refs;

	for (;;) {
		refs = module_refcount();
		if (refs <= 0)
			break;
		if (waited >= timeout_ms) {
			outf("RUN-MEM: module still has %d reference(s) after %d ms\n",
			     refs, waited);
			return;
		}
		nanosleep(&ts, NULL);
		waited += 5;
	}
	outf("RUN-MEM: no carrier left (module references: %d)\n", refs < 0 ? 0 : refs);
}

/* --- /proc/vmstat ------------------------------------------------------ */

static const char *const vm_keys[] = {
	"pswpout", "pswpin", "pgscan_kswapd", "pgscan_direct", "pgsteal_kswapd",
	"pgsteal_direct", "pgsteal_anon", "allocstall_normal", "allocstall_dma32",
	"compact_stall", "compact_migrate_scanned", "thp_fault_alloc",
	"oom_kill", "pgfault", "workingset_refault_anon",
};
#define NKEYS (sizeof(vm_keys) / sizeof(vm_keys[0]))

static void vmstat(unsigned long v[NKEYS])
{
	char name[128];
	unsigned long val;
	FILE *f = fopen("/proc/vmstat", "re");
	size_t i;

	memset(v, 0, NKEYS * sizeof(v[0]));
	if (!f)
		return;
	while (fscanf(f, "%127s %lu", name, &val) == 2)
		for (i = 0; i < NKEYS; i++)
			if (strcmp(name, vm_keys[i]) == 0)
				v[i] = val;
	fclose(f);
}

static void vmstat_print(const char *tag, const unsigned long a[NKEYS],
			 const unsigned long b[NKEYS])
{
	char line[1024];
	size_t i, n = 0;

	n += snprintf(line + n, sizeof(line) - n, "RUN-MEM: %s", tag);
	for (i = 0; i < NKEYS && n < sizeof(line) - 64; i++)
		n += snprintf(line + n, sizeof(line) - n, " %s=%lu", vm_keys[i],
			      b[i] - a[i]);
	snprintf(line + n, sizeof(line) - n, "\n");
	out(line);
}

/* --- the hog ----------------------------------------------------------- */

static char kmsg_hit[2048];

/* Reads /dev/kmsg from its oldest record until one contains `needle`. */
static int wait_kmsg(const char *needle, int timeout_s)
{
	char rec[2048];
	time_t end = time(NULL) + timeout_s;
	int fd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);

	if (fd < 0) {
		outf("RUN-MEM: /dev/kmsg: %s\n", strerror(errno));
		return -1;
	}
	while (time(NULL) < end) {
		ssize_t n = read(fd, rec, sizeof(rec) - 1);

		if (n < 0) {
			if (errno == EAGAIN) {
				usleep(10000);
				continue;
			}
			if (errno == EPIPE)
				continue;
			break;
		}
		rec[n] = 0;
		if (strstr(rec, needle)) {
			snprintf(kmsg_hit, sizeof(kmsg_hit), "%s", strstr(rec, needle));
			close(fd);
			return 0;
		}
	}
	close(fd);
	return -1;
}

static void hog(void)
{
	unsigned long v0[NKEYS], v[NKEYS];
	unsigned long mb = 0;
	size_t i;

	vmstat(v0);
	while (mb < HOG_MAX_MB) {
		char *p = mmap(NULL, HOG_CHUNK, PROT_READ | PROT_WRITE,
			       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);

		if (p == MAP_FAILED)
			break;
		for (i = 0; i < HOG_CHUNK; i += 4096)
			p[i] = (char)(i >> 12);
		mb += HOG_CHUNK >> 20;
		vmstat(v);
		if (v[0] - v0[0] >= HOG_SWAP_PAGES)
			break;
	}
	vmstat(v);
	outf("RUN-MEM: HOG: allocated and touched %lu MiB\n", mb);
	vmstat_print("HOG: done, vmstat delta", v0, v);
	_exit(0);
}

/* --- stopping a carrier -------------------------------------------------- */

/* The state letter of /proc/<pid>/stat: R, S, T, ... or '?'. */
static char task_state(long pid)
{
	char buf[512], *p;
	ssize_t n;
	int fd;

	snprintf(buf, sizeof(buf), "/proc/%ld/stat", pid);
	fd = open(buf, O_RDONLY);
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

/*
 * Linux preempting a vCPU carrier in user mode: the carrier and a CPU-bound
 * competitor, both pinned to processor 1 for `ms`, so that the scheduler takes
 * the processor from the carrier at its ticks and every return to its tenant
 * passes through the exit loop with a reschedule pending.
 */
static void preempt_with_competitor(long pid, int ms)
{
	struct timespec t = { .tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000L };
	cpu_set_t one, all;
	pid_t comp;
	int i;

	CPU_ZERO(&one);
	CPU_SET(1, &one);
	CPU_ZERO(&all);
	for (i = 0; i < 2; i++)
		CPU_SET(i, &all);
	if (sched_setaffinity((pid_t)pid, sizeof(one), &one) != 0) {
		outf("RUN-MEM: cannot pin the carrier of vcpu 1: %s\n", strerror(errno));
		return;
	}
	comp = fork();
	if (comp == 0) {
		volatile unsigned long x = 0;

		sched_setaffinity(0, sizeof(one), &one);
		for (;;)
			x++;
	}
	nanosleep(&t, NULL);
	kill(comp, SIGKILL);
	waitpid(comp, NULL, 0);
	sched_setaffinity((pid_t)pid, sizeof(all), &all);
	outf("RUN-MEM: preempted the carrier of vcpu 1 for %d ms with a competitor on cpu 1\n", ms);
}

/* The SigIgn, SigBlk or SigPnd line of /proc/<pid>/status, as hex text. */
static void task_sigline(long pid, const char *key, char *out, size_t len)
{
	char path[64], line[256];
	size_t klen = strlen(key);
	FILE *f;

	snprintf(out, len, "?");
	snprintf(path, sizeof(path), "/proc/%ld/status", pid);
	f = fopen(path, "re");
	if (!f)
		return;
	while (fgets(line, sizeof(line), f))
		if (strncmp(line, key, klen) == 0 && line[klen] == ':') {
			char *v = line + klen + 1;

			v += strspn(v, " \t");
			v[strcspn(v, "\n")] = 0;
			snprintf(out, len, "%s", v);
			break;
		}
	fclose(f);
}

/*
 * The endovisor ignores every signal a carrier can be sent but SIGKILL and
 * SIGSTOP, so an operator's SIGTERM, a stray SIGUSR1, a SIGQUIT or SIGABRT
 * (whose default is a core dump), or a SIGTSTP, SIGTTIN or SIGTTOU (whose
 * default is a stop) must leave both the vCPU carrier and the root carrier
 * alive and running. The core-dump and stop signals are sent in a burst while
 * the carrier's tenant runs in user mode, so that some of them land in the
 * exit loop after the resume hook has drained the queue, which is where Linux,
 * not the endovisor, would act on one that was not ignored.
 */
static void signal_and_check(long pid, long root)
{
	static const int burst[] = { SIGQUIT, SIGABRT, SIGTSTP, SIGTTIN, SIGTTOU };
	struct timespec t = { .tv_sec = 0, .tv_nsec = 200 * 1000 * 1000 };
	char ign[32], blk[32], ign_root[32];
	unsigned int i, j;
	char s;

	task_sigline(pid, "SigIgn", ign, sizeof(ign));
	task_sigline(pid, "SigBlk", blk, sizeof(blk));
	task_sigline(root, "SigIgn", ign_root, sizeof(ign_root));
	outf("RUN-MEM: signal dispositions: vcpu 1 carrier SigIgn %s SigBlk %s, root carrier SigIgn %s\n",
	     ign, blk, ign_root);

	kill((pid_t)pid, SIGTERM);
	kill((pid_t)pid, SIGUSR1);
	kill((pid_t)root, SIGTERM);
	nanosleep(&t, NULL);
	s = task_state(pid);
	outf("RUN-MEM: after SIGTERM and SIGUSR1 the carrier of vcpu 1 is %s (state %c), the root carrier %s\n",
	     kill((pid_t)pid, 0) == 0 && s != 'Z' && s != '?' ? "alive" : "gone", s,
	     kill((pid_t)root, 0) == 0 && task_state(root) != 'Z' ? "alive" : "gone");

	for (j = 0; j < 2000; j++)
		for (i = 0; i < sizeof(burst) / sizeof(burst[0]); i++)
			kill((pid_t)pid, burst[i]);
	kill((pid_t)root, SIGQUIT);
	kill((pid_t)root, SIGTSTP);
	nanosleep(&t, NULL);
	s = task_state(pid);
	outf("RUN-MEM: after 2000 rounds of SIGQUIT, SIGABRT, SIGTSTP, SIGTTIN and SIGTTOU the carrier of vcpu 1 is %s (state %c), the root carrier %s\n",
	     kill((pid_t)pid, 0) == 0 && s != 'Z' && s != '?' ? "alive" : "gone", s,
	     kill((pid_t)root, 0) == 0 && task_state(root) != 'Z' ? "alive" : "gone");
}

/*
 * SIGSTOP and SIGCONT to a vCPU carrier, as an operator would send them: Linux
 * must stop it like any task (a stopped virtual CPU) and let it go on.
 */
static void stop_and_continue(long pid)
{
	struct timespec half = { .tv_sec = 0, .tv_nsec = 500 * 1000 * 1000 };
	char before = task_state(pid), stopped, after;

	kill((pid_t)pid, SIGSTOP);
	nanosleep(&half, NULL);
	stopped = task_state(pid);
	kill((pid_t)pid, SIGCONT);
	nanosleep(&half, NULL);
	after = task_state(pid);
	outf("RUN-MEM: vcpu 1 carrier state %c, after SIGSTOP %c, after SIGCONT %c\n",
	     before, stopped, after);
}

/* --- main -------------------------------------------------------------- */

int main(void)
{
	char *const argv[] = { (char *)KLET_PATH, NULL };
	char *const envp[] = { NULL };
	unsigned long v0[NKEYS], v1[NKEYS];
	int status = 0, pressure = 0;
	pid_t pid, done, hog_pid = -1;
	char arg[64] = "";
	int fd;

	fd = open("/tests/10-mem.arg", O_RDONLY);
	if (fd >= 0) {
		ssize_t n = read(fd, arg, sizeof(arg) - 1);

		if (n > 0)
			arg[n] = 0;
		close(fd);
	}
	arg[strcspn(arg, "\n")] = 0;
	pressure = strcmp(arg, "pressure") == 0;
	int kill_vcpu1 = strcmp(arg, "kill") == 0;
	int kill_quiet = strcmp(arg, "killidle") == 0 || strcmp(arg, "killspin") == 0;
	struct timespec kill_t0 = { 0, 0 };
	int killed = 0;

	/* The area starts at 0x10000: security_mmap_addr() refuses it below
	 * vm.mmap_min_addr. */
	fd = open("/proc/sys/vm/mmap_min_addr", O_RDONLY);
	if (fd >= 0) {
		char b[32] = "";
		if (read(fd, b, sizeof(b) - 1) > 0 && strtoul(b, NULL, 0) > 0x10000) {
			outf("RUN-MEM: vm.mmap_min_addr is %s, above the area's 0x10000\n", b);
			return 1;
		}
		close(fd);
	}

	if (pressure) {
		if (syscall(SYS_swapon, "/dev/vda", 0) != 0) {
			outf("RUN-MEM: swapon /dev/vda failed: %s\n", strerror(errno));
			return 1;
		}
		out("RUN-MEM: swap on /dev/vda\n");
		vmstat(v0);
	}

	out("RUN-MEM: creating a sandbox from " KLET_PATH "\n");
	pid = fork();
	if (pid < 0) {
		outf("RUN-MEM: fork failed: %s\n", strerror(errno));
		return 1;
	}
	if (pid == 0) {
		prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
		execve(KLET_PATH, argv, envp);
		outf("RUN-MEM: execve %s failed: %s\n", KLET_PATH, strerror(errno));
		_exit(127);
	}

	if (kill_vcpu1) {
		long cpid = -1;

		if (wait_kmsg("vcpu 1 carrier starting (pid ", 30) == 0)
			cpid = strtol(kmsg_hit + strlen("vcpu 1 carrier starting (pid "), NULL, 10);
		if (cpid > 0 && wait_kmsg("MEM-KILL-ME", 30) == 0) {
			usleep(500 * 1000);	/* let the sibling fault for a while first */
			preempt_with_competitor(cpid, 1500);
			signal_and_check(cpid, (long)pid);
			stop_and_continue(cpid);
			usleep(300 * 1000);	/* and let the check run after the continue */
			outf("RUN-MEM: killing the carrier of vcpu 1 (pid %ld) from outside\n", cpid);
			kill((pid_t)cpid, SIGKILL);
		} else {
			out("RUN-MEM: could not find the carrier of vcpu 1\n");
		}
	}

	if (kill_quiet) {
		long cpid = -1;

		if (wait_kmsg("vcpu 1 carrier starting (pid ", 30) == 0)
			cpid = strtol(kmsg_hit + strlen("vcpu 1 carrier starting (pid "), NULL, 10);
		if (cpid > 0 && wait_kmsg("MEM-KILL-READY", 30) == 0) {
			usleep(300 * 1000);	/* let it settle where it is */
			outf("RUN-MEM: the carrier of vcpu 1 (pid %ld) is in state %c (%s); SIGKILL\n",
			     cpid, task_state(cpid),
			     strcmp(arg, "killidle") == 0 ? "idle in vcpu_idle" : "running a kernel task");
			clock_gettime(CLOCK_MONOTONIC, &kill_t0);
			kill((pid_t)cpid, SIGKILL);
			killed = 1;
		} else {
			out("RUN-MEM: could not find the carrier of vcpu 1\n");
		}
	}

	if (pressure) {
		if (wait_kmsg("E7-MAPPED", 60) == 0) {
			out("RUN-MEM: HOG: the kernelet has mapped its pages; allocating until reclaim runs\n");
			hog_pid = fork();
			if (hog_pid == 0)
				hog();
			waitpid(hog_pid, NULL, 0);
		} else {
			out("RUN-MEM: never saw E7-MAPPED\n");
		}
	}

	do {
		done = waitpid(pid, &status, 0);
	} while (done < 0 && errno == EINTR);
	if (killed) {
		struct timespec t1;

		clock_gettime(CLOCK_MONOTONIC, &t1);
		outf("RUN-MEM: the sandbox ended %ld ms after the kill\n",
		     (long)((t1.tv_sec - kill_t0.tv_sec) * 1000 +
			    (t1.tv_nsec - kill_t0.tv_nsec) / 1000000));
	}
	if (WIFSIGNALED(status))
		outf("RUN-MEM: root carrier (pid %d) killed by signal %d\n", pid,
		     WTERMSIG(status));
	else
		outf("RUN-MEM: root carrier (pid %d) exited %d\n", pid,
		     WEXITSTATUS(status));
	if (pressure) {
		vmstat(v1);
		vmstat_print("whole run, vmstat delta", v0, v1);
	}
	wait_for_module_idle(5000);
	out("RUN-MEM: done\n");
	return 0;
}
