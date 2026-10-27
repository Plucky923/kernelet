// SPDX-License-Identifier: GPL-2.0

// Runs concurrent sandboxes of one PIE kind and checks their private state.
//
// The test kernel checks initialized data, BSS, and relocated references.
// The endovisor checks every shared and private image page when mappings overlap.
// This driver kills and destroys one instance while its peer keeps running,
// then starts another instance to check initialization and reuse.
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>

#include "sandbox.h"

struct instance {
	int fd;
	pid_t pid;
	unsigned int id;
	char console[64];
};

static void check(int condition, const char *what)
{
	if (!condition) {
		sandbox_say("FAIL %s: %s", what, strerror(errno));
		exit(1);
	}
	sandbox_say("ok %s", what);
}

// Reads the latest heartbeat and rejects any reported data corruption.
static unsigned long long progress(const struct instance *inst, int *ready)
{
	char data[65536], marker[80];
	unsigned long long value = 0, latest = 0;
	int fd = open(inst->console, O_RDONLY | O_CLOEXEC);
	ssize_t length;
	char *at;

	if (fd < 0)
		return 0;
	length = read(fd, data, sizeof(data) - 1);
	close(fd);
	if (length <= 0)
		return 0;
	data[length] = 0;
	if (strstr(data, "FAIL") != NULL)
		check(0, "kernel state remains private");
	snprintf(marker, sizeof(marker), "PIE-CHECK id=%u ready fresh-data relocated-pointers", inst->id);
	*ready = strstr(data, marker) != NULL;
	snprintf(marker, sizeof(marker), "PIE-CHECK id=%u progress=", inst->id);
	at = data;
	while ((at = strstr(at, marker)) != NULL) {
		at += strlen(marker);
		if (sscanf(at, "%llu", &value) == 1 && value > latest)
			latest = value;
	}
	return latest;
}

static unsigned long long wait_progress(const struct instance *inst, unsigned long long previous)
{
	long long deadline = now_ms() + 5000;

	while (now_ms() < deadline) {
		int ready = 0;
		unsigned long long value = progress(inst, &ready);
		struct pollfd pfd = { .fd = inst->fd, .events = POLLIN };

		if (ready && value > previous)
			return value;
		if (poll(&pfd, 1, 0) != 0)
			check(0, "instance remains alive while awaiting progress");
		msleep(20);
	}
	check(0, "instance made fresh progress before timeout");
	return 0;
}

static struct instance start_instance(int sys_fd, int kind, unsigned int id)
{
	struct instance inst = { .id = id };
	struct sandbox_opts opt;
	char command[32];
	struct klet_create cr = {
		.kind = kind, .nr_vcpus = 1,
		.memory_initial = 4 << 20, .memory_max = 4 << 20, .max_tasks = 16,
		.cmdline = (__u64)(unsigned long)command,
	};
	unsigned int vcpu = 0;
	int output, exec_fd;

	snprintf(command, sizeof(command), "%u", id);
	cr.cmdline_len = strlen(command);
	inst.fd = ioctl(sys_fd, KLET_CREATE, &cr);
	check(inst.fd >= 0, "create another sandbox of the same kind");
	snprintf(inst.console, sizeof(inst.console), "/pie-%u.console", id);
	output = open(inst.console, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
	check(output >= 0 && ioctl(inst.fd, KLET_SET_CONSOLE, &output) == 0, "attach instance console");
	close(output);
	exec_fd = ioctl(inst.fd, KLET_GET_VCPU_EXEC_FD, &vcpu);
	check(exec_fd >= 0, "obtain instance exec descriptor");
	sandbox_opts_init(&opt);
	inst.pid = fork();
	check(inst.pid >= 0, "fork instance carrier");
	if (inst.pid == 0)
		start_carrier(exec_fd, 0, &opt);
	close(exec_fd);
	wait_progress(&inst, 0);
	sandbox_say("instance %u booted with fresh state and working relocated pointers", id);
	return inst;
}

static void stop_instance(struct instance *inst)
{
	__u32 reason = inst->id;
	struct klet_exit ended;
	struct pollfd pfd = { .fd = inst->fd, .events = POLLIN };
	int status = 0, ready = 0;

	check(ioctl(inst->fd, KLET_KILL, &reason) == 0, "kill one instance");
	check(poll(&pfd, 1, 5000) == 1 && (pfd.revents & POLLIN), "killed instance exits before timeout");
	check(read(inst->fd, &ended, sizeof(ended)) == sizeof(ended) &&
	      ended.how == KLET_END_KILLED && ended.reason == reason,
	      "killed instance reports its own reason");
	check(waitpid(inst->pid, &status, 0) == inst->pid && WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL,
	      "reap killed carrier");
	progress(inst, &ready);
	check(close(inst->fd) == 0, "close the last descriptor to destroy killed instance");
	sandbox_say("instance %u destroyed", inst->id);
}

int main(int argc, char **argv)
{
	struct instance first, survivor, replacement;
	unsigned long long before;
	int sys_fd, kind, ready;

	sandbox_who = "PIE-TEST";
	if (argc != 2) {
		sandbox_say("usage: run-pie IMAGE");
		return 2;
	}
	sys_fd = open_system();
	kind = register_kind(sys_fd, "piecheck", argv[1]);
	join_cgroup("/sys/fs/cgroup/pie-test");
	first = start_instance(sys_fd, kind, 1);
	survivor = start_instance(sys_fd, kind, 2);
	wait_progress(&first, 2);
	wait_progress(&survivor, 2);
	stop_instance(&first);
	before = progress(&survivor, &ready);
	wait_progress(&survivor, before + 2);
	sandbox_say("survivor progressed after its peer was destroyed");
	replacement = start_instance(sys_fd, kind, 3);
	wait_progress(&survivor, 5);
	wait_progress(&replacement, 2);
	stop_instance(&replacement);
	before = progress(&survivor, &ready);
	wait_progress(&survivor, before + 2);
	stop_instance(&survivor);
	check(ioctl(sys_fd, KLET_KIND_UNREGISTER, &(__u32){ kind }) == 0,
	      "unregister kind after every instance is destroyed");
	close(sys_fd);
	check(module_references("endovisor") == 0, "endovisor has no remaining references");
	sandbox_say("no carrier left (module references: 0)");
	sandbox_say("PASS concurrent same-kind instances, private state, relocated pointers, survivor and restart");
	return 0;
}
