#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static void trigger_oops(void)
{
	int fd = open("/oops-resource", O_CREAT | O_RDWR, 0600);
	if (fd < 0 || flock(fd, LOCK_EX) != 0)
		_exit(80);
	void *memory = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
			    MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (memory == MAP_FAILED)
		_exit(81);
	*(volatile int *)memory = 42;
	struct sigevent event = { .sigev_notify = SIGEV_THREAD };
	int timer_id = -1;
	(void)syscall(SYS_timer_create, CLOCK_MONOTONIC, &event, &timer_id);
	_exit(82);
}

int main(void)
{
	int recovered = 1;
	int released = 1;
	alarm(30);
	for (int iteration = 0; iteration < 2; iteration++) {
		pid_t child = fork();
		if (child == 0)
			trigger_oops();
		if (child < 0) {
			perror("fork");
			return 1;
		}
		int status = 0;
		if (waitpid(child, &status, 0) != child ||
		    !WIFSIGNALED(status) || WTERMSIG(status) != SIGKILL) {
			printf("OOPS_CHECK unexpected_status=%d iteration=%d\n",
			       status, iteration);
			recovered = 0;
			break;
		}
		int fd = open("/oops-resource", O_RDWR);
		if (fd < 0 || flock(fd, LOCK_EX | LOCK_NB) != 0) {
			perror("post-oops flock");
			released = 0;
		}
		if (fd >= 0)
			close(fd);
		unlink("/oops-resource");
	}
	pid_t parent = getpid();
	int progress = parent > 0;
	for (int iteration = 0; iteration < 10000; iteration++)
		progress &= syscall(SYS_getpid) == parent;
	pid_t child = fork();
	if (child == 0)
		_exit(0);
	int status = -1;
	progress &= child > 0 && waitpid(child, &status, 0) == child &&
		    WIFEXITED(status) && WEXITSTATUS(status) == 0;
	int ok = recovered && released && progress;
	printf("RESULT oops_recovery %d bool\n", recovered);
	printf("RESULT oops_resource_release %d bool\n", released);
	printf("RESULT oops_parent_progress %d bool\n", progress);
	printf("RESULT suite_done %d bool\n", ok);
	return !ok;
}
