// SPDX-License-Identifier: GPL-2.0
/*
 * The kernelet runtime for the scheduler experiments.
 *
 *   run-sched policy   just create the sandbox and wait
 *   run-sched coop     plus competitors in a sibling control group on the same CPUs
 *   run-sched fair     plus one competitor, and measure its share of the CPUs
 *   run-sched perf     plus the same measurements on native Linux threads
 *
 * Everything the sandbox does is inside its own control group; the competitors are
 * in a sibling group with the same weight, confined to the same two CPUs. That is
 * the only way a statement about fairness means anything.
 *
 * The sandbox is run through the endovisor UAPI (sandbox.c) by a holder: a
 * child of this driver that registers the kind, joins the sandbox's group
 * (/sys/fs/cgroup/klet), creates the sandbox and forks its carriers, every one
 * on CPUs 0 and 1, and waits for it, so that the driver itself stays outside
 * the sandbox's group, as it was outside it before. The holder hands the
 * carriers' pids over through the shared page, and the driver watches them.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "sandbox.h"

#define CG "/sys/fs/cgroup"
#define CG_KLET CG "/klet"
#define CG_SIB CG "/sib"

/* One report line, through the kernel's log (sandbox_say): in order with the endovisor's. */
static void say(const char *fmt, ...)
{
	char buf[900];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	sandbox_say("%s", buf);
}

static uint64_t rdtsc(void)
{
	uint32_t lo, hi;

	__asm__ __volatile__("rdtsc" : "=a"(lo), "=d"(hi));
	return ((uint64_t)hi << 32) | lo;
}


static int write_file(const char *path, const char *value)
{
	int fd = open(path, O_WRONLY);
	ssize_t n;

	if (fd < 0)
		return -1;
	n = write(fd, value, strlen(value));
	close(fd);
	return n < 0 ? -1 : 0;
}

static long read_key(const char *path, const char *key)
{
	char buf[4096];
	int fd = open(path, O_RDONLY);
	ssize_t n;
	char *p;

	if (fd < 0)
		return -1;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return -1;
	buf[n] = 0;
	p = strstr(buf, key);
	if (!p)
		return -1;
	return strtol(p + strlen(key), NULL, 10);
}

/* Two control groups with the same weight, so that "equal share" has a meaning. */
static int cgroups_up;

static void setup_cgroups(void)
{
	mkdir(CG, 0755);
	if (mount("none", CG, "cgroup2", 0, NULL) != 0 && errno != EBUSY) {
		say("no cgroup2 (%s); shares will be reported, not enforced",
		    strerror(errno));
		return;
	}
	if (write_file(CG "/cgroup.subtree_control", "+cpu") != 0) {
		say("cannot enable the cpu controller: %s", strerror(errno));
		return;
	}
	mkdir(CG_KLET, 0755);
	mkdir(CG_SIB, 0755);
	write_file(CG_KLET "/cpu.weight", "100");
	write_file(CG_SIB "/cpu.weight", "100");
	cgroups_up = 1;
	say("control groups up: %s and %s, cpu.weight 100 each", CG_KLET, CG_SIB);
}

static void join_group(const char *cg)
{
	char path[256], pid[32];

	if (!cgroups_up)
		return;
	snprintf(path, sizeof(path), "%s/cgroup.procs", cg);
	snprintf(pid, sizeof(pid), "%d", getpid());
	if (write_file(path, pid) != 0)
		say("cannot join %s: %s", cg, strerror(errno));
}

static void pin_to(int lo, int hi)
{
	cpu_set_t set;
	int i;

	CPU_ZERO(&set);
	for (i = lo; i <= hi; i++)
		CPU_SET(i, &set);
	sched_setaffinity(0, sizeof(set), &set);
}

/* ------------------------------------------------------------------ */
/* Competitors                                                        */
/* ------------------------------------------------------------------ */

struct shared {
	volatile uint64_t rounds[8];
	volatile int stop;
	/* the holder's: the carriers' pids, once every one is forked */
	volatile pid_t carriers[KLET_MAX_VCPUS];
	volatile unsigned int nr_carriers;
	/* for the native ping-pong */
	volatile uint32_t turn;
	volatile uint64_t stamp;
	volatile uint64_t samples;
};

static struct shared *shm;

/* ------------------------------------------------------------------ */
/* The sandbox                                                        */
/* ------------------------------------------------------------------ */

/* In the holder: publish the carriers' pids to the driver. */
static void publish_carriers(struct sandbox *sb, void *arg)
{
	unsigned int i;

	(void)arg;
	for (i = 0; i < sb->nr_vcpus; i++)
		shm->carriers[i] = sb->pids[i];
	__sync_synchronize();
	shm->nr_carriers = sb->nr_vcpus;
}

/*
 * The holder: a child that registers the kind, joins the sandbox's group and
 * runs the sandbox, every carrier on CPUs 0 and 1. Its exit status is the
 * holder's, the kernel proper's exit code.
 */
static pid_t spawn_holder(unsigned int nr_vcpus, const char *cmdline)
{
	pid_t pid = fork();

	if (pid < 0) {
		say("fork failed: %s", strerror(errno));
		exit(1);
	}
	if (pid == 0) {
		struct sandbox_opts opt;
		int sys_fd, status;

		sandbox_who = "RUN-SCHED holder";
		sandbox_opts_init(&opt);
		opt.cgroup = cgroups_up ? CG_KLET : CG "/sandbox";
		opt.cpu_lo = 0;
		opt.cpu_hi = 1;	/* the carriers inherit nothing else */
		opt.kernel_log = 1;
		opt.during = publish_carriers;
		sys_fd = open_system();
		register_kind(sys_fd, "schedk", "/schedk.image");
		status = run_sandbox(sys_fd, "schedk", nr_vcpus, cmdline, &opt);
		close(sys_fd);
		_exit(status);
	}
	say("the holder is pid %d; the sandbox's carriers will be on cpu 0-1, in %s", pid,
	    cgroups_up ? CG_KLET : CG "/sandbox");
	return pid;
}

/* How many of a sandbox's carriers Linux sees as runnable, by reading /proc. */
static int count_running(void)
{
	unsigned int i, n = shm->nr_carriers;
	int r = 0;

	for (i = 0; i < n; i++)
		if (proc_task_state(shm->carriers[i]) == 'R')
			r++;
	return r;
}

static uint64_t mix_round(uint64_t x)
{
	x ^= x << 13;
	x ^= x >> 7;
	x ^= x << 17;
	return x;
}

static pid_t spawn_competitor(int slot)
{
	pid_t pid = fork();

	if (pid == 0) {
		uint64_t x = 0x1234567 + slot;

		join_group(CG_SIB);
		pin_to(0, 1);
		while (!shm->stop) {
			int i;

			for (i = 0; i < 100000; i++)
				x = mix_round(x);
			shm->rounds[slot] += 100000;
		}
		_exit((int)(x & 1));
	}
	return pid;
}

/* ------------------------------------------------------------------ */
/* Native Linux, for comparison                                       */
/* ------------------------------------------------------------------ */

static int cmp_u64(const void *a, const void *b)
{
	uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;

	return x < y ? -1 : (x > y ? 1 : 0);
}

static void report(const char *name, uint64_t *s, int n)
{
	if (n <= 0) {
		printf("NATIVE-PERF %s n=0\n", name);
		return;
	}
	qsort(s, n, sizeof(*s), cmp_u64);
	printf("NATIVE-PERF %s n=%d median=%llu p99=%llu min=%llu\n", name, n,
	       (unsigned long long)s[n / 2], (unsigned long long)s[(n * 99) / 100],
	       (unsigned long long)s[0]);
	fflush(stdout);
}

#define PERF_N 2000
/* Nothing here may hang: every loop has a wall-clock cap as well as a count. */
#define PERF_CAP_MS 4000

/*
 * Two processes on one CPU yielding to each other, and two processes on one CPU
 * where one wakes the other through a pipe. Both are `fork` and shared memory
 * rather than threads: a statically linked pthread in this guest is one more thing
 * that can go wrong, and neither measurement needs a shared address space.
 */
static void native_process_yield(void)
{
	uint64_t *s = malloc(sizeof(uint64_t) * PERF_N);
	uint64_t deadline = now_ms() + PERF_CAP_MS;
	int n = 0;
	pid_t pid;

	shm->turn = 0;
	shm->stop = 0;
	pid = fork();
	if (pid == 0) {
		pin_to(0, 0);
		while (!shm->stop) {
			shm->turn = 1;
			sched_yield();
		}
		_exit(0);
	}
	pin_to(0, 0);
	while (n < PERF_N && (uint64_t)now_ms() < deadline) {
		uint64_t t0 = rdtsc();

		sched_yield();
		if (shm->turn) {
			shm->turn = 0;
			s[n++] = rdtsc() - t0;
		}
	}
	shm->stop = 1;
	waitpid(pid, NULL, 0);
	pin_to(0, 1);
	shm->stop = 0;
	report("linux_process_yield_roundtrip_cycles", s, n);
	free(s);
}

static void native_pipe_wake(int same_cpu)
{
	uint64_t *s = malloc(sizeof(uint64_t) * PERF_N);
	uint64_t deadline = now_ms() + PERF_CAP_MS;
	int up[2], down[2];
	int n = 0;
	pid_t pid;

	if (pipe(up) || pipe(down)) {
		free(s);
		return;
	}
	shm->stop = 0;
	pid = fork();
	if (pid == 0) {
		char c;

		pin_to(same_cpu ? 0 : 1, same_cpu ? 0 : 1);
		close(up[0]);
		close(down[1]);
		while (read(down[0], &c, 1) == 1) {
			/* Stamp the moment the woken side actually runs. */
			shm->stamp = rdtsc();
			if (write(up[1], &c, 1) != 1)
				break;
		}
		_exit(0);
	}
	pin_to(0, 0);
	close(up[1]);
	close(down[0]);
	while (n < PERF_N && (uint64_t)now_ms() < deadline) {
		char c = 'x';
		uint64_t t0;

		shm->stamp = 0;
		t0 = rdtsc();
		if (write(down[1], &c, 1) != 1)
			break;
		if (read(up[0], &c, 1) != 1)
			break;
		if (shm->stamp > t0)
			s[n++] = shm->stamp - t0;
	}
	close(down[1]);
	close(up[0]);
	kill(pid, SIGKILL);
	waitpid(pid, NULL, 0);
	pin_to(0, 1);
	report(same_cpu ? "linux_pipe_wake_same_cpu_cycles"
			: "linux_pipe_wake_other_cpu_cycles",
	       s, n);
	free(s);
}

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */

int main(void)
{
	static char mode[32], cmdline[KLET_CMDLINE_MAX];
	pid_t holder, comp[2] = { -1, -1 };
	uint64_t t_start, sib_usec0 = 0;
	int status, i, max_running = 0;
	unsigned int nr_vcpus;

	/* init runs the tests without arguments, so the mode is staged beside the test. */
	sandbox_read_staged("/tests/10-sched.arg", mode, sizeof(mode), &nr_vcpus,
			    cmdline, sizeof(cmdline));

	sandbox_who = "RUN-SCHED";
	shm = mmap(NULL, sizeof(*shm), PROT_READ | PROT_WRITE,
		   MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	memset(shm, 0, sizeof(*shm));

	say("mode %s", mode);
	setup_cgroups();
	pin_to(0, 1);

	if (!strcmp(mode, "coop") || !strcmp(mode, "fair")) {
		int n = !strcmp(mode, "coop") ? 2 : 1;

		for (i = 0; i < n; i++)
			comp[i] = spawn_competitor(i);
		say("%d competitor(s) in %s on cpu 0-1", n, CG_SIB);
		sib_usec0 = read_key(CG_SIB "/cpu.stat", "usage_usec ");
	}

	t_start = now_ms();
	holder = spawn_holder(nr_vcpus, cmdline);

	/* Watch how many of the sandbox's tasks Linux ever sees runnable at once. */
	while (waitpid(holder, &status, WNOHANG) == 0) {
		int r = count_running();

		if (r > max_running)
			max_running = r;
		usleep(5000);
	}

	/*
	 * Take every measurement first: the holder has reaped every carrier and
	 * destroyed the sandbox by now, so no kernel message of the sandbox's
	 * can interleave with these lines on the serial console and break the
	 * lines the checks parse.
	 */
	{
		uint64_t elapsed = now_ms() - t_start;
		unsigned long long total = 0;
		long sib_usec = -1, klet_usec = -1;

		if (comp[0] > 0) {
			sib_usec = read_key(CG_SIB "/cpu.stat", "usage_usec ");
			klet_usec = read_key(CG_KLET "/cpu.stat", "usage_usec ");
			shm->stop = 1;
			for (i = 0; i < 2; i++)
				if (comp[i] > 0)
					waitpid(comp[i], NULL, 0);
			for (i = 0; i < 8; i++)
				total += shm->rounds[i];
		}

		i = module_references("endovisor");
		say("no carrier left (module references: %d)", i < 0 ? 0 : i);

		if (WIFEXITED(status))
			say("the holder (pid %d) exited %d", holder, WEXITSTATUS(status));
		else if (WIFSIGNALED(status))
			say("the holder (pid %d) killed by signal %d", holder,
			    WTERMSIG(status));

		say("the host saw at most %d runnable task(s) of the sandbox at once",
		    max_running);

		if (comp[0] > 0) {
			say("competitor rounds %llu over %llu ms", total,
			    (unsigned long long)elapsed);
			if (sib_usec >= 0 && (long)sib_usec0 >= 0)
				say("SIB-USEC %ld elapsed_ms %llu", sib_usec - (long)sib_usec0,
				    (unsigned long long)elapsed);
			if (klet_usec >= 0)
				say("KLET-USEC %ld", klet_usec);
			shm->stop = 0;
		}
	}

	if (!strcmp(mode, "perf")) {
		say("now the same measurements on native Linux, same cpus, same cgroup");
		native_process_yield();
		native_pipe_wake(1);
		native_pipe_wake(0);
	}

	say("done");
	return 0;
}
