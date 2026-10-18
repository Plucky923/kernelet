/*
 * holder: a sandbox's holder process, the user of the kernelet UAPI.
 *
 * A kernelet runtime, like a container runtime, has one process per sandbox
 * that creates it, keeps its descriptor open for as long as it lives, and
 * destroys it. This is the smallest such process. Two commands:
 *
 *   holder register NAME IMAGE          register the image file as kind NAME
 *                                       (needs CAP_SYS_MODULE)
 *   holder run [-c CGROUP] [-p] NAME NR_VCPUS [CMDLINE...]
 *                                       create a sandbox of kind NAME with
 *                                       NR_VCPUS virtual CPUs and run it until
 *                                       it ends; -c moves the holder and so
 *                                       the carriers into the control group
 *                                       at CGROUP first; -p pins the carrier
 *                                       of virtual CPU i to processor i
 *
 * The holder's console and log are its own standard output and error. The
 * exit status is the kernel proper's exit code, or 128 plus a reason.
 *
 * This program is the interface's first user and is built with the other
 * runtimes (make runtime); the endovisor of this prototype does not offer
 * /dev/kernelet yet, so it cannot run against it.
 *
 * Built static: gcc -static -O2 -I ../../linux/endovisor/uapi -o holder holder.c
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>

#include <kernelet.h>

static void die(const char *what)
{
	fprintf(stderr, "holder: %s: %s\n", what, strerror(errno));
	exit(127);
}

/* Open the device and refuse an interface this program does not know. */
static int open_system(void)
{
	int sys = open("/dev/kernelet", O_RDWR | O_CLOEXEC);

	if (sys < 0)
		die("/dev/kernelet");
	if (ioctl(sys, KERNELET_GET_API_VERSION) != KERNELET_API_VERSION) {
		fprintf(stderr, "holder: /dev/kernelet speaks another version\n");
		exit(127);
	}
	return sys;
}

/* The operator's step: hand over an image file and name the kind. */
static int register_kind(int sys, const char *name, const char *image_path)
{
	struct kernelet_kind_register reg = { .image_fd = open(image_path, O_RDONLY | O_CLOEXEC) };
	int kind;

	if (reg.image_fd < 0)
		die(image_path);
	snprintf(reg.name, sizeof(reg.name), "%s", name);
	kind = ioctl(sys, KERNELET_KIND_REGISTER, &reg);
	if (kind < 0)
		die("KERNELET_KIND_REGISTER");
	close(reg.image_fd);
	return kind;
}

/* Find a kind by name among those registered. */
static int find_kind(int sys, const char *name)
{
	struct kernelet_kind_info info[16];
	struct kernelet_kind_list list = {
		.kinds = (__u64)(unsigned long)info,
		.capacity = sizeof(info) / sizeof(info[0]),
	};
	unsigned int i;

	if (ioctl(sys, KERNELET_KIND_LIST, &list) < 0)
		die("KERNELET_KIND_LIST");
	for (i = 0; i < list.count && i < list.capacity; i++)
		if (strcmp(info[i].name, name) == 0)
			return (int)info[i].id;
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
			die("sched_setaffinity");
	}
	if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0)	/* the handler insists on it */
		die("PR_SET_NO_NEW_PRIVS");
	/* A seccomp filter would be installed here; this kernel is built without
	 * the legacy vsyscall page, so there is nothing for one to close. */
	execveat(exec_fd, "", argv, envp, AT_EMPTY_PATH);
	die("execveat");
}

/* The holder's side: create, configure, start every virtual CPU, wait, destroy. */
static int run_sandbox(int sys, const char *name, unsigned int nr_vcpus, const char *cmdline,
		       const char *cgroup, int pin)
{
	struct kernelet_create create = {
		.kind = (__u32)find_kind(sys, name),
		.nr_vcpus = nr_vcpus,
		.memory_initial = 4 << 20,
		.memory_max = 64 << 20,
		.max_tasks = 256,
		.cmdline = (__u64)(unsigned long)cmdline,
		.cmdline_len = (__u32)strlen(cmdline),
	};
	struct kernelet_exit ex;
	pid_t pids[KERNELET_MAX_VCPUS];
	int sb, out = 1, err = 2;
	unsigned int i;

	if (cgroup)					/* before the create: the group becomes the sandbox's */
		join_cgroup(cgroup);
	sb = ioctl(sys, KERNELET_CREATE, &create);
	if (sb < 0)
		die("KERNELET_CREATE");
	if (ioctl(sb, KERNELET_SET_CONSOLE, &out) < 0 || ioctl(sb, KERNELET_SET_LOG, &err) < 0)
		die("KERNELET_SET_CONSOLE");
	/* A disk would be attached here: KERNELET_ATTACH_DEVICE with its open file. */

	for (i = 0; i < nr_vcpus; i++) {
		int exec_fd = ioctl(sb, KERNELET_VCPU_GET_EXEC_FD, &i);

		if (exec_fd < 0)
			die("KERNELET_VCPU_GET_EXEC_FD");
		pids[i] = fork();
		if (pids[i] < 0)
			die("fork");
		if (pids[i] == 0)
			start_carrier(exec_fd, i, pin);	/* does not return */
		close(exec_fd);
	}

	if (ioctl(sb, KERNELET_WAIT, &ex) < 0)		/* until the sandbox has ended */
		die("KERNELET_WAIT");
	for (i = 0; i < nr_vcpus; i++)
		waitpid(pids[i], NULL, 0);		/* the carriers died by SIGKILL */
	if (ioctl(sb, KERNELET_DESTROY) < 0)
		die("KERNELET_DESTROY");
	close(sb);

	switch (ex.how) {
	case KERNELET_END_EXITED:
		return ex.code;
	case KERNELET_END_PANICKED:
		fprintf(stderr, "holder: the kernelet panicked: %.*s\n", KERNELET_MESSAGE_LEN, ex.message);
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
	int pin = 0, sys;

	if (argc >= 4 && strcmp(argv[1], "register") == 0) {
		sys = open_system();
		printf("kind %d\n", register_kind(sys, argv[2], argv[3]));
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
		if (nr_vcpus < 1 || nr_vcpus > KERNELET_MAX_VCPUS)
			usage();
		sys = open_system();
		return run_sandbox(sys, argv[0], nr_vcpus, cmdline, cgroup, pin);
	}
}
