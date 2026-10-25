/*
 * holder: a sandbox's holder process, the user of the endovisor UAPI.
 *
 * A kernelet runtime, like a container runtime, has one process per sandbox
 * that creates it, keeps its descriptor open for as long as it lives, and
 * destroys it. This is the smallest such process. Two commands:
 *
 *   holder register NAME IMAGE          register the image file as kind NAME
 *                                       (needs the right to load kernel code)
 *   holder run [-c CGROUP] [-p] NAME NR_VCPUS [CMDLINE...]
 *                                       create a sandbox of kind NAME with
 *                                       NR_VCPUS virtual CPUs and run it until
 *                                       it ends; -c moves the holder, and so
 *                                       the carriers, into the control group
 *                                       at CGROUP first; -p pins the carrier
 *                                       of virtual CPU i to processor i
 *
 * The holder's console and log are its own standard output and error (the
 * console then carries output only; a terminal or a socket would carry both
 * directions). The exit status is the kernel proper's exit code, 128 for a
 * panic, 129 for a kill.
 *
 * This program is the interface's first user and is built with the other
 * runtimes (make runtime); the endovisor of this prototype does not offer
 * /dev/endovisor yet, so it cannot run against it.
 *
 * Built static: gcc -static -O2 -I ../../linux/endovisor/uapi -o holder holder.c
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <endovisor.h>

static void die(const char *what)
{
	fprintf(stderr, "holder: %s: %s\n", what, strerror(errno));
	exit(127);
}

/* The same, in a forked child: no flushing of the parent's buffers. */
static void die_child(const char *what)
{
	int err = errno;
	char msg[256];
	int n = snprintf(msg, sizeof(msg), "holder: carrier: %s: %s\n", what, strerror(err));

	if (n > 0)
		n = (int)write(2, msg, (size_t)n);	/* and nothing better to do if that fails */
	_exit(127);
}

/* Open the device and refuse an interface this program does not know. */
static int open_system(void)
{
	int sys_fd = open("/dev/endovisor", O_RDWR | O_CLOEXEC);

	if (sys_fd < 0)
		die("/dev/endovisor");
	if (ioctl(sys_fd, KLET_GET_API_VERSION) != KLET_API_VERSION) {
		fprintf(stderr, "holder: /dev/endovisor speaks another version\n");
		exit(127);
	}
	return sys_fd;
}

/* The operator's step: hand over an image file and name the kind. */
static int register_kind(int sys_fd, const char *name, const char *image_path)
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
static int find_kind(int sys_fd, const char *name)
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
	fprintf(stderr, "holder: no kind named %s is registered\n", name);
	exit(127);
}

/* Join a control group: write our process identifier into its cgroup.procs. */
static void join_cgroup(const char *dir)
{
	char path[4096], pid[32];
	int fd, n;

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
 * The child's side: arrange the task with Linux's own system calls, then
 * execute the exec descriptor. Everything set here survives the exec, and
 * the process never returns from it: the endovisor makes it the carrier.
 */
static void start_carrier(int exec_fd, unsigned int vcpu, int pin)
{
	char *argv[] = { "carrier", NULL };
	char *envp[] = { NULL };

	if (pin) {					/* virtual CPU i on processor i */
		cpu_set_t set;

		CPU_ZERO(&set);
		CPU_SET(vcpu, &set);
		if (sched_setaffinity(0, sizeof(set), &set) < 0)
			die_child("sched_setaffinity");
	}
	if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0)	/* the endovisor insists on it */
		die_child("PR_SET_NO_NEW_PRIVS");
	/* A seccomp filter would be installed here; this kernel is built without
	 * the legacy vsyscall page, so there is nothing for one to close. */
	execveat(exec_fd, "", argv, envp, AT_EMPTY_PATH);
	die_child("execveat");
}

/*
 * Wait for the sandbox to end. A child that dies before its exec succeeded
 * never became a carrier, so the endovisor does not know it is gone; watch
 * the children through process descriptors and kill the sandbox ourselves
 * if one of them goes while the sandbox is still alive.
 */
static void wait_sandbox(int sandbox_fd, const pid_t *pids, unsigned int nr_vcpus, struct klet_exit *ex)
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
				pfd[i + 1].fd = -1;		/* polled no more */
			}
	}
	for (i = 0; i < nr_vcpus; i++)
		if (pfd[i + 1].fd >= 0)
			close(pfd[i + 1].fd);
	if (ioctl(sandbox_fd, KLET_WAIT, ex) < 0)
		die("KLET_WAIT");
}

/* The holder's side: create, configure, start every virtual CPU, wait, destroy. */
static int run_sandbox(int sys_fd, const char *name, unsigned int nr_vcpus, const char *cmdline,
		       const char *cgroup, int pin)
{
	struct klet_create create = {
		.kind = (__u32)find_kind(sys_fd, name),
		.nr_vcpus = nr_vcpus,
		.memory_initial = 4 << 20,
		.memory_max = 64 << 20,
		.max_tasks = 256,
		.cmdline = (__u64)(unsigned long)cmdline,
		.cmdline_len = (__u32)strlen(cmdline),
	};
	struct klet_exit ex;
	pid_t pids[KLET_MAX_VCPUS];
	int sandbox_fd, out = 1, err = 2;
	unsigned int i;

	if (cgroup)					/* before the create: the group becomes the sandbox's */
		join_cgroup(cgroup);
	sandbox_fd = ioctl(sys_fd, KLET_CREATE, &create);
	if (sandbox_fd < 0)
		die("KLET_CREATE");
	if (ioctl(sandbox_fd, KLET_SET_CONSOLE, &out) < 0 || ioctl(sandbox_fd, KLET_SET_LOG, &err) < 0)
		die("KLET_SET_CONSOLE");
	/* A disk would be attached here: KLET_ATTACH_DEVICE with its open file. */

	for (i = 0; i < nr_vcpus; i++) {
		int exec_fd = ioctl(sandbox_fd, KLET_VCPU_GET_EXEC_FD, &i);

		if (exec_fd < 0)
			die("KLET_VCPU_GET_EXEC_FD");
		pids[i] = fork();
		if (pids[i] < 0)
			die("fork");
		if (pids[i] == 0)
			start_carrier(exec_fd, i, pin);	/* does not return */
		close(exec_fd);
	}

	wait_sandbox(sandbox_fd, pids, nr_vcpus, &ex);		/* until the sandbox has ended */
	for (i = 0; i < nr_vcpus; i++)
		waitpid(pids[i], NULL, 0);		/* the carriers died by SIGKILL */
	if (ioctl(sandbox_fd, KLET_DESTROY) < 0)
		die("KLET_DESTROY");
	close(sandbox_fd);

	switch (ex.how) {
	case KLET_END_EXITED:
		return ex.code;
	case KLET_END_PANICKED:
		fprintf(stderr, "holder: the kernelet panicked: %.*s\n", KLET_MESSAGE_LEN, ex.message);
		return 128;
	default:
		fprintf(stderr, "holder: the kernelet was killed: reason %#x\n", ex.reason);
		return 129;
	}
}

static void usage(void)
{
	fprintf(stderr, "usage: holder register NAME IMAGE\n"
			"       holder run [-c CGROUP] [-p] NAME NR_VCPUS [CMDLINE...]\n");
	exit(2);
}

int main(int argc, char **argv)
{
	const char *cgroup = NULL;
	int pin = 0, sys_fd;

	if (argc >= 4 && strcmp(argv[1], "register") == 0) {
		sys_fd = open_system();
		printf("kind %d\n", register_kind(sys_fd, argv[2], argv[3]));
		return 0;
	}
	if (argc < 2 || strcmp(argv[1], "run") != 0)
		usage();
	argv += 2; argc -= 2;
	while (argc > 0 && argv[0][0] == '-') {
		if (strcmp(argv[0], "-c") == 0 && argc > 1) {
			cgroup = argv[1]; argv += 2; argc -= 2;
		} else if (strcmp(argv[0], "-p") == 0) {
			pin = 1; argv++; argc--;
		} else {
			usage();
		}
	}
	if (argc < 2)
		usage();
	{
		char cmdline[1024] = "";
		unsigned int nr_vcpus = (unsigned int)atoi(argv[1]);
		int i;

		for (i = 2; i < argc; i++) {
			if (i > 2)
				strncat(cmdline, " ", sizeof(cmdline) - strlen(cmdline) - 1);
			strncat(cmdline, argv[i], sizeof(cmdline) - strlen(cmdline) - 1);
		}
		if (nr_vcpus < 1 || nr_vcpus > KLET_MAX_VCPUS)
			usage();
		sys_fd = open_system();
		return run_sandbox(sys_fd, argv[0], nr_vcpus, cmdline, cgroup, pin);
	}
}
