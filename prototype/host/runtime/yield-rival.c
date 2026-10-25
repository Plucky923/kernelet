/*
 * yield-rival: the two Linux processes the yield test runs beside the
 * sandbox, started by run-test before the holder (kernels/yield).
 *
 *  - `yield-rival competitor`: an ordinary Linux process pinned to CPU 0,
 *    where the holder pins the sandbox's one carrier (-p), doing the *same*
 *    computation as the yield kernel in user space and printing a progress
 *    line every quarter second of wall clock. It is both the thing that
 *    starves and the independent reference for the checksum. If kernelet code
 *    cannot be preempted, the competitor prints nothing at all while the
 *    kernelet computes, and the gap in its timestamps is the stall. If the
 *    watch timer works, it keeps printing, and its final checksum is
 *    bit-identical to the kernelet's.
 *  - `yield-rival prodder`: the grace-period prodder, on CPU 1, until it is
 *    killed.
 *
 * Built static: gcc -static -O2 -o yield-rival yield-rival.c
 */

#define _GNU_SOURCE

#include <errno.h>
#include <sched.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>


/* Must match yield/src/lib.rs. */
#define ROUNDS 800000000ULL
#define MUL 0x5851f42d4c957f2dULL

/* How often the competitor reports, in milliseconds of wall clock. */
#define REPORT_MS 250

/* membarrier(MEMBARRIER_CMD_GLOBAL) is synchronize_rcu(). */
#define MEMBARRIER_CMD_GLOBAL 1

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

static long long now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (long long)ts.tv_sec * 1000 + ts.tv_nsec / (1000 * 1000);
}

static void pin_to(int cpu)
{
	cpu_set_t set;

	CPU_ZERO(&set);
	CPU_SET(cpu, &set);
	if (sched_setaffinity(0, sizeof(set), &set) != 0)
		outf("RUN-YIELD: sched_setaffinity(cpu %d) failed: %s\n", cpu,
		     strerror(errno));
}

/*
 * The competitor. The same eight-lane mixer the yield kernel runs, in chunks, so
 * that it can look at the clock between chunks and say how it is getting on. When
 * it is starved there are no lines at all, and the next line's timestamp shows how
 * long for.
 */
static void competitor(void)
{
	unsigned long long s0 = 0x123456789abcdef0ULL;
	unsigned long long s1 = 0x0fedcba987654321ULL;
	unsigned long long s2 = 0xdeadbeefcafebabeULL;
	unsigned long long s3 = 0x0123456789abcdefULL;
	unsigned long long s4 = 0xa5a55a5a3c3cc3c3ULL;
	unsigned long long s5 = 0x1111222233334444ULL;
	unsigned long long s6 = 0xffff0000ffff0000ULL;
	unsigned long long s7 = 0x0f1e2d3c4b5a6978ULL;
	unsigned long long acc = 0;
	unsigned long long done = 0;
	long long t0 = now_ms();
	long long next = t0 + REPORT_MS;
	int lines = 0;

	pin_to(0);
	outf("RUN-YIELD: competitor on cpu 0, %llu rounds of the same mixer\n",
	     ROUNDS);

	while (done < ROUNDS) {
		unsigned long long chunk = ROUNDS - done;
		unsigned long long i;

		if (chunk > 2000000ULL)
			chunk = 2000000ULL;
		for (i = 0; i < chunk; i++) {
			s0 ^= s0 << 13; s0 ^= s0 >> 7; s0 ^= s0 << 17;
			s1 ^= s1 << 13; s1 ^= s1 >> 7; s1 ^= s1 << 17;
			s2 ^= s2 << 13; s2 ^= s2 >> 7; s2 ^= s2 << 17;
			s3 ^= s3 << 13; s3 ^= s3 >> 7; s3 ^= s3 << 17;
			s4 ^= s4 << 13; s4 ^= s4 >> 7; s4 ^= s4 << 17;
			s5 ^= s5 << 13; s5 ^= s5 >> 7; s5 ^= s5 << 17;
			s6 ^= s6 << 13; s6 ^= s6 >> 7; s6 ^= s6 << 17;
			s7 ^= s7 << 13; s7 ^= s7 >> 7; s7 ^= s7 << 17;
			acc = acc * MUL + (s0 ^ s1 ^ s2 ^ s3 ^ s4 ^ s5 ^ s6 ^ s7);
		}
		done += chunk;

		if (now_ms() >= next) {
			long long t = now_ms();

			outf("RUN-YIELD: competitor progress %llu/%llu at t+%lldms\n",
			     done, ROUNDS, t - t0);
			lines++;
			next = t + REPORT_MS;
		}
	}

	acc ^= s0 ^ s1 ^ s2 ^ s3 ^ s4 ^ s5 ^ s6 ^ s7;
	outf("RUN-YIELD: competitor reference checksum 0x%016llx after %lld ms, %d progress line(s)\n",
	     acc, now_ms() - t0, lines);
	_exit(0);
}

/*
 * The grace-period prodder, on the *other* CPU. Every
 * membarrier(MEMBARRIER_CMD_GLOBAL) is a synchronize_rcu(), which cannot
 * complete until every CPU has reported a quiescent state. A carrier that
 * monopolises its CPU in kernel mode never reports one, so this is what turns
 * "the competitor starves" into "RCU stalls", which is the other half of what the
 * book says goes wrong.
 */
static void prodder(void)
{
	long long t0 = now_ms();
	long long next = t0 + REPORT_MS;
	unsigned long long grace = 0;

	pin_to(1);
	if (syscall(SYS_membarrier, MEMBARRIER_CMD_GLOBAL, 0, 0) != 0) {
		outf("RUN-YIELD: membarrier not available (%s); no RCU prodding\n",
		     strerror(errno));
		_exit(0);
	}
	out("RUN-YIELD: prodder on cpu 1, one synchronize_rcu() per turn\n");

	for (;;) {
		if (syscall(SYS_membarrier, MEMBARRIER_CMD_GLOBAL, 0, 0) == 0)
			grace++;
		if (now_ms() >= next) {
			long long t = now_ms();

			outf("RUN-YIELD: prodder %llu grace period(s) at t+%lldms\n",
			     grace, t - t0);
			next = t + REPORT_MS;
		}
	}
}

int main(int argc, char **argv)
{
	if (argc == 2 && strcmp(argv[1], "competitor") == 0)
		competitor();
	if (argc == 2 && strcmp(argv[1], "prodder") == 0)
		prodder();
	out("usage: yield-rival competitor|prodder\n");
	return 2;
}
