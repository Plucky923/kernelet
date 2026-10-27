// SPDX-License-Identifier: GPL-2.0
/*
 * run-mem: the runtime of the memory test kernel (mem/).
 *
 * Registers /mem.image as the kind "mem" and runs a sandbox of it through the
 * endovisor UAPI (sandbox.c), as the holder does, from the sandbox's control
 * group /sys/fs/cgroup/sandbox. What else it does around the sandbox is named
 * on the first line of /tests/10-mem.arg (the second is the number of virtual
 * CPUs, the third the sandbox's command line):
 *
 *  - "pressure" (E7): turns on swap on /dev/vda and, once the kernelet has
 *    printed E7-MAPPED (watched in /dev/kmsg), runs a memory hog in a host
 *    process until /proc/vmstat shows that reclaim has run and swapped out at
 *    least HOG_SWAP_PAGES pages, then frees it. The kernelet's tenant is
 *    spinning in user mode all that time; afterwards it reads every page back.
 *  - "kill" (E11): once the kernelet has said it is ready, has Linux preempt
 *    the carrier of virtual CPU 1 (a competitor pinned to its processor),
 *    reads both carriers' signal dispositions (SigIgn, SigBlk) from
 *    /proc/<pid>/status, sends it SIGTERM and SIGUSR1 (and the carrier of
 *    virtual CPU 0 a SIGTERM), and then a burst of the core-dump and stop
 *    signals, SIGQUIT, SIGABRT, SIGTSTP, SIGTTIN and SIGTTOU (and the carrier
 *    of virtual CPU 0 a SIGQUIT and a SIGTSTP), all of which must leave both
 *    alive and running,
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

#include "sandbox.h"

#define IMAGE_PATH "/mem.image"
#define CGROUP "/sys/fs/cgroup/sandbox"
#define HOG_SWAP_PAGES 30000UL		/* 117 MiB swapped out */
#define HOG_MAX_MB 900UL
#define HOG_CHUNK (4UL << 20)

/*
 * One report line, written whole into the kernel's log through /dev/kmsg, so
 * that it is in order with the endovisor's lines on the serial console; to
 * standard output if there is no /dev/kmsg.
 */
static void out(const char *s)
{
	static int kmsg = -2;
	size_t len = strlen(s);
	ssize_t n;

	if (kmsg == -2)
		kmsg = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
	if (kmsg >= 0 && write(kmsg, s, len) == (ssize_t)len)
		return;
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

#define task_state(pid) proc_task_state(pid)

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

#define task_sigline(pid, key, out, len) proc_status_field(pid, key, out, len)

/*
 * The endovisor ignores every signal a carrier can be sent but SIGKILL and
 * SIGSTOP, so an operator's SIGTERM, a stray SIGUSR1, a SIGQUIT or SIGABRT
 * (whose default is a core dump), or a SIGTSTP, SIGTTIN or SIGTTOU (whose
 * default is a stop) must leave both carriers alive and running. The core-dump and stop signals are sent in a burst while
 * the carrier's tenant runs in user mode, so that some of them land in the
 * exit loop after the resume hook has drained the queue, which is where Linux,
 * not the endovisor, would act on one that was not ignored.
 */
static void signal_and_check(long pid, long other)
{
	static const int burst[] = { SIGQUIT, SIGABRT, SIGTSTP, SIGTTIN, SIGTTOU };
	struct timespec t = { .tv_sec = 0, .tv_nsec = 200 * 1000 * 1000 };
	char ign[32], blk[32], ign_root[32];
	unsigned int i, j;
	char s;

	task_sigline(pid, "SigIgn", ign, sizeof(ign));
	task_sigline(pid, "SigBlk", blk, sizeof(blk));
	task_sigline(other, "SigIgn", ign_root, sizeof(ign_root));
	outf("RUN-MEM: signal dispositions: vcpu 1 carrier SigIgn %s SigBlk %s, vcpu 0 carrier SigIgn %s\n",
	     ign, blk, ign_root);

	kill((pid_t)pid, SIGTERM);
	kill((pid_t)pid, SIGUSR1);
	kill((pid_t)other, SIGTERM);
	nanosleep(&t, NULL);
	s = task_state(pid);
	outf("RUN-MEM: after SIGTERM and SIGUSR1 the carrier of vcpu 1 is %s (state %c), the carrier of vcpu 0 %s\n",
	     kill((pid_t)pid, 0) == 0 && s != 'Z' && s != '?' ? "alive" : "gone", s,
	     kill((pid_t)other, 0) == 0 && task_state(other) != 'Z' ? "alive" : "gone");

	for (j = 0; j < 2000; j++)
		for (i = 0; i < sizeof(burst) / sizeof(burst[0]); i++)
			kill((pid_t)pid, burst[i]);
	kill((pid_t)other, SIGQUIT);
	kill((pid_t)other, SIGTSTP);
	nanosleep(&t, NULL);
	s = task_state(pid);
	outf("RUN-MEM: after 2000 rounds of SIGQUIT, SIGABRT, SIGTSTP, SIGTTIN and SIGTTOU the carrier of vcpu 1 is %s (state %c), the carrier of vcpu 0 %s\n",
	     kill((pid_t)pid, 0) == 0 && s != 'Z' && s != '?' ? "alive" : "gone", s,
	     kill((pid_t)other, 0) == 0 && task_state(other) != 'Z' ? "alive" : "gone");
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

/* --- the sandbox -------------------------------------------------------- */

static char mode[64];

/* What the mode does while the sandbox runs: called once every carrier is forked. */
static void during(struct sandbox *sb, void *arg)
{
	long cpid = sb->nr_vcpus > 1 ? sb->pids[1] : -1;

	(void)arg;
	if (strcmp(mode, "kill") == 0) {
		if (cpid > 0 && wait_kmsg("MEM-KILL-ME", 30) == 0) {
			usleep(500 * 1000);	/* let the sibling fault for a while first */
			preempt_with_competitor(cpid, 1500);
			signal_and_check(cpid, sb->pids[0]);
			stop_and_continue(cpid);
			usleep(300 * 1000);	/* and let the check run after the continue */
			outf("RUN-MEM: killing the carrier of vcpu 1 (pid %ld) from outside\n", cpid);
			kill((pid_t)cpid, SIGKILL);
		} else {
			out("RUN-MEM: could not find the carrier of vcpu 1\n");
		}
	} else if (strcmp(mode, "killidle") == 0 || strcmp(mode, "killspin") == 0) {
		if (cpid > 0 && wait_kmsg("MEM-KILL-READY", 30) == 0) {
			long long t0;

			usleep(300 * 1000);	/* let it settle where it is */
			outf("RUN-MEM: the carrier of vcpu 1 (pid %ld) is in state %c (%s); SIGKILL\n",
			     cpid, task_state(cpid),
			     strcmp(mode, "killidle") == 0 ? "idle in vcpu_idle" : "running a kernel task");
			t0 = now_ms();
			kill((pid_t)cpid, SIGKILL);
			// Exited: a sandbox read would return; every carrier is gone.
			if (sandbox_exited(sb, 10000))
				outf("RUN-MEM: the sandbox ended %lld ms after the kill\n", now_ms() - t0);
			else
				out("RUN-MEM: the sandbox did not end within 10 s of the kill\n");
		} else {
			out("RUN-MEM: could not find the carrier of vcpu 1\n");
		}
	} else if (strcmp(mode, "pressure") == 0) {
		if (wait_kmsg("E7-MAPPED", 60) == 0) {
			pid_t hog_pid;

			out("RUN-MEM: HOG: the kernelet has mapped its pages; allocating until reclaim runs\n");
			hog_pid = fork();
			if (hog_pid == 0)
				hog();
			waitpid(hog_pid, NULL, 0);
		} else {
			out("RUN-MEM: never saw E7-MAPPED\n");
		}
	}
}

/* --- main -------------------------------------------------------------- */

int main(void)
{
	static char cmdline[KLET_CMDLINE_MAX];
	unsigned long v0[NKEYS], v1[NKEYS];
	struct sandbox_opts opt;
	unsigned int nr_vcpus;
	int status, refs, fd, sys_fd;

	sandbox_who = "RUN-MEM";
	sandbox_read_staged("/tests/10-mem.arg", mode, sizeof(mode), &nr_vcpus,
			    cmdline, sizeof(cmdline));

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

	if (strcmp(mode, "pressure") == 0) {
		if (syscall(SYS_swapon, "/dev/vda", 0) != 0) {
			outf("RUN-MEM: swapon /dev/vda failed: %s\n", strerror(errno));
			return 1;
		}
		out("RUN-MEM: swap on /dev/vda\n");
		vmstat(v0);
	}

	outf("RUN-MEM: creating a sandbox of %s, mode %s\n", IMAGE_PATH, mode);
	sandbox_opts_init(&opt);
	opt.cgroup = CGROUP;
	opt.kernel_log = 1;
	opt.during = during;
	sys_fd = open_system();
	register_kind(sys_fd, "mem", IMAGE_PATH);
	status = run_sandbox(sys_fd, "mem", nr_vcpus, cmdline, &opt);
	close(sys_fd);
	outf("RUN-MEM: the sandbox's holder status %d\n", status);
	if (strcmp(mode, "pressure") == 0) {
		vmstat(v1);
		vmstat_print("whole run, vmstat delta", v0, v1);
	}
	refs = module_references("endovisor");
	outf("RUN-MEM: no carrier left (module references: %d)\n", refs < 0 ? 0 : refs);
	out("RUN-MEM: done\n");
	return 0;
}
