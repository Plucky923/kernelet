// Native Linux reference for the kernelet `fork` row of "What it costs":
// fork a process with 64 MiB mapped, then time the child's first read pass
// and the parent's re-read.
//
// Layouts:
//   anon   - 64 MiB private anonymous memory, every page written first.
//   shared - one 1 MiB memfd (256 frames) mapped 64 times MAP_SHARED,
//            the kernelet test's shape (256 frames, each mapped 64 times).
#define _GNU_SOURCE
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MIB (1UL << 20)
#define TOTAL (64 * MIB)
#define PAGE 4096UL
#define ROUNDS 31

static uint64_t now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static char **regions;
static size_t nregions, region_len;

static uint64_t read_pass(void)
{
	volatile uint64_t sum = 0;
	for (size_t r = 0; r < nregions; r++)
		for (size_t off = 0; off < region_len; off += PAGE)
			sum += *(volatile uint64_t *)(regions[r] + off);
	return sum;
}

static int cmp(const void *a, const void *b)
{
	uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
	return x < y ? -1 : x > y;
}

static long minflt(void)
{
	struct rusage ru;
	getrusage(RUSAGE_SELF, &ru);
	return ru.ru_minflt;
}

static int bench(const char *mode)
{
	cpu_set_t set;

	CPU_ZERO(&set);
	CPU_SET(1, &set); // the guest has CPUs 0 and 1
	sched_setaffinity(0, sizeof(set), &set);

	if (!strncmp(mode, "anon", 4)) {
		nregions = 1;
		region_len = TOTAL;
		regions = malloc(sizeof(char *));
		regions[0] = mmap(NULL, TOTAL, PROT_READ | PROT_WRITE,
				  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (!strcmp(mode, "anon"))
			madvise(regions[0], TOTAL, MADV_NOHUGEPAGE); // 4 KiB pages, as in the kernelet
		memset(regions[0], 1, TOTAL);
	} else {
		int fd = memfd_create("frames", 0);
		nregions = 64;
		region_len = MIB;
		regions = malloc(nregions * sizeof(char *));
		if (fd >= 0 && ftruncate(fd, MIB) == 0) {
			for (size_t r = 0; r < nregions; r++)
				regions[r] = mmap(NULL, MIB, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		} else {
			// No memfd: one shared anonymous region, duplicated with mremap(old_size = 0).
			regions[0] = mmap(NULL, MIB, PROT_READ | PROT_WRITE,
					  MAP_SHARED | MAP_ANONYMOUS, -1, 0);
			for (size_t r = 1; r < nregions; r++)
				regions[r] = mremap(regions[0], 0, MIB, MREMAP_MAYMOVE);
		}
		for (size_t r = 0; r < nregions; r++) {
			if (regions[r] == MAP_FAILED) { perror("map"); exit(1); }
			memset(regions[r], 1, MIB);
		}
	}

	uint64_t fork_ns[ROUNDS], child_ns[ROUNDS], reread_ns[ROUNDS];
	long child_flt[ROUNDS];

	for (int i = 0; i < ROUNDS; i++) {
		int p[2];
		pipe(p);
		read_pass(); // warm the parent's TLB and caches
		uint64_t t0 = now_ns();
		pid_t pid = fork();
		if (pid == 0) {
			long f0 = minflt();
			uint64_t c0 = now_ns();
			read_pass();
			uint64_t res[2] = { now_ns() - c0, (uint64_t)(minflt() - f0) };
			write(p[1], res, sizeof(res));
			_exit(0);
		}
		fork_ns[i] = now_ns() - t0;
		uint64_t res[2];
		read(p[0], res, sizeof(res));
		waitpid(pid, NULL, 0);
		child_ns[i] = res[0];
		child_flt[i] = (long)res[1];
		uint64_t r0 = now_ns();
		read_pass();
		reread_ns[i] = now_ns() - r0;
		close(p[0]);
		close(p[1]);
	}
	long flt = child_flt[ROUNDS / 2];
	qsort(fork_ns, ROUNDS, sizeof(uint64_t), cmp);
	qsort(child_ns, ROUNDS, sizeof(uint64_t), cmp);
	qsort(reread_ns, ROUNDS, sizeof(uint64_t), cmp);
	printf("FORKBENCH %-8s fork (parent side) median %8.3f ms  [min %.3f, max %.3f]\n", mode,
	       fork_ns[ROUNDS / 2] / 1e6, fork_ns[0] / 1e6, fork_ns[ROUNDS - 1] / 1e6);
	printf("FORKBENCH %-8s child first read pass  median %8.3f ms  (%ld minor faults)\n", mode,
	       child_ns[ROUNDS / 2] / 1e6, flt);
	printf("FORKBENCH %-8s parent re-read          median %8.3f ms\n", mode, reread_ns[ROUNDS / 2] / 1e6);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc > 1)
		return bench(argv[1]);
	// One process per layout, so that each starts from a fresh address space.
	const char *modes[] = { "anon", "shared", "anon-thp" };
	for (int i = 0; i < 3; i++) {
		pid_t pid = fork();
		if (pid == 0) {
			bench(modes[i]);
			fflush(stdout);
			_exit(0);
		}
		waitpid(pid, NULL, 0);
	}
	return 0;
}
