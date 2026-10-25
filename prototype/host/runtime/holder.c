/*
 * holder: a sandbox's holder process, the command around sandbox.c.
 *
 * A kernelet runtime, like a container runtime, has one process per sandbox
 * that creates it, keeps its descriptor open for as long as it lives, and
 * destroys it. This is the smallest such process. Two commands:
 *
 *   holder register NAME IMAGE          register the image file as kind NAME
 *                                       (needs the right to load kernel code)
 *   holder run [OPTIONS] NAME NR_VCPUS [CMDLINE...]
 *                                       create a sandbox of kind NAME with
 *                                       NR_VCPUS virtual CPUs and run it until
 *                                       it ends
 *
 * The options of run:
 *
 *   -c CGROUP           move the holder, and so the carriers, into the control
 *                       group at CGROUP first (made if it does not exist); the
 *                       endovisor refuses a sandbox in the root group
 *   -p                  pin the carrier of virtual CPU i to processor i
 *   -k                  give the sandbox neither console nor log: the endovisor
 *                       writes both to the host's kernel log, prefixed
 *                       "kernelet:" (what the tests use)
 *   --console FILE      the console is FILE, created or truncated
 *   --log FILE          the log is FILE, likewise
 *   --seccomp-kill NR   install in each carrier, between fork and exec, a
 *                       seccomp filter that kills the process on system call NR
 *   --kill-after MS     after MS milliseconds, SIGKILL the carrier of virtual
 *                       CPU 0, as an operator would
 *   --klet-kill-after MS  after MS milliseconds, KLET_KILL with reason 1
 *
 * Without -k, --console or --log, the console and log are the holder's own
 * standard output and error (the console then carries output only; a
 * terminal or a socket would carry both directions). After the sandbox is
 * destroyed, the holder closes its descriptor on the device and reports the
 * endovisor module's reference count, read once from /proc/modules: with
 * every carrier reaped and every descriptor closed, it must be 0. The exit
 * status is the kernel proper's exit code, 128 for a panic, 129 for a kill.
 *
 * Built static: gcc -static -O2 -I ../../linux/endovisor/uapi -o holder holder.c sandbox.c
 */

#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "sandbox.h"

static void usage(void)
{
	fprintf(stderr, "usage: holder register NAME IMAGE\n"
			"       holder run [-c CGROUP] [-p] [-k] [--console FILE] [--log FILE]\n"
			"                  [--seccomp-kill NR] [--kill-after MS] [--klet-kill-after MS]\n"
			"                  NAME NR_VCPUS [CMDLINE...]\n");
	exit(2);
}

int main(int argc, char **argv)
{
	struct sandbox_opts opt;
	int sys_fd, status, refs;

	sandbox_opts_init(&opt);
	if (argc >= 4 && strcmp(argv[1], "register") == 0) {
		sys_fd = open_system();
		sandbox_say("kind %d registered: %s from %s",
			    register_kind(sys_fd, argv[2], argv[3]), argv[2], argv[3]);
		return 0;
	}
	if (argc < 2 || strcmp(argv[1], "run") != 0)
		usage();
	argv += 2; argc -= 2;
	while (argc > 0 && argv[0][0] == '-') {
		const char *o = argv[0];

		if (strcmp(o, "-p") == 0) {
			opt.pin = 1; argv++; argc--;
		} else if (strcmp(o, "-k") == 0) {
			opt.kernel_log = 1; argv++; argc--;
		} else if (argc > 1 && strcmp(o, "-c") == 0) {
			opt.cgroup = argv[1]; argv += 2; argc -= 2;
		} else if (argc > 1 && strcmp(o, "--console") == 0) {
			opt.console_path = argv[1]; argv += 2; argc -= 2;
		} else if (argc > 1 && strcmp(o, "--log") == 0) {
			opt.log_path = argv[1]; argv += 2; argc -= 2;
		} else if (argc > 1 && strcmp(o, "--seccomp-kill") == 0) {
			opt.seccomp_kill_nr = atoi(argv[1]); argv += 2; argc -= 2;
		} else if (argc > 1 && strcmp(o, "--kill-after") == 0) {
			opt.kill_after_ms = atoi(argv[1]); argv += 2; argc -= 2;
		} else if (argc > 1 && strcmp(o, "--klet-kill-after") == 0) {
			opt.klet_kill_after_ms = atoi(argv[1]); argv += 2; argc -= 2;
		} else {
			usage();
		}
	}
	if (argc < 2)
		usage();
	{
		char cmdline[KLET_CMDLINE_MAX] = "";
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
		status = run_sandbox(sys_fd, argv[0], nr_vcpus, cmdline, &opt);
	}
	close(sys_fd);
	refs = module_references("endovisor");
	sandbox_say("no carrier left (module references: %d)", refs < 0 ? 0 : refs);
	return status;
}
