/*
 * run-test: the test steps of one boot, in place of a shell.
 *
 * init runs every executable under /tests with no arguments; a test that is
 * a sequence of holder invocations is this program, staged as
 * /tests/10-<name>, which reads its steps from /tests/10-<name>.cmd, one per
 * line (blank lines and lines starting with # are skipped):
 *
 *   run PROG ARGS...         run PROG and wait for it; report its exit status
 *   start NAME PROG ARGS...  run PROG in the background, known as NAME
 *   wait NAME                wait for NAME to end by itself
 *   kill NAME                SIGKILL NAME and reap it
 *   sleep MS                 sleep
 *   pin CPU                  pin this process, and so what it runs later, to CPU
 *   show FILE                print FILE, each line prefixed with "RUN-TEST: FILE: "
 *
 * Every step is reported on a line starting with "RUN-TEST:", and whatever
 * was started and is still running at the end is killed.
 *
 * Built static: gcc -static -O2 -o run-test run-test.c
 */

#define _GNU_SOURCE

#include <errno.h>
#include <sched.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define MAX_ARGS 64
#define MAX_BG 8

static struct {
	char name[32];
	pid_t pid;
} bg[MAX_BG];

static void say(const char *fmt, ...)
{
	char buf[1024];
	va_list ap;
	int n = snprintf(buf, sizeof(buf), "RUN-TEST: ");

	va_start(ap, fmt);
	n += vsnprintf(buf + n, sizeof(buf) - n, fmt, ap);
	va_end(ap);
	if (n >= (int)sizeof(buf) - 1)
		n = sizeof(buf) - 2;
	buf[n++] = '\n';
	if (write(1, buf, n) < 0)
		return;
	tcdrain(1);
}

static pid_t spawn(char **argv)
{
	char *envp[] = { "PATH=/tests:/", "HOME=/", NULL };
	pid_t pid = fork();

	if (pid == 0) {
		execve(argv[0], argv, envp);
		say("execve %s: %s", argv[0], strerror(errno));
		_exit(127);
	}
	if (pid < 0)
		say("fork: %s", strerror(errno));
	return pid;
}

static void report(const char *what, int status)
{
	if (WIFEXITED(status))
		say("%s exited %d", what, WEXITSTATUS(status));
	else if (WIFSIGNALED(status))
		say("%s killed by signal %d", what, WTERMSIG(status));
}

static int reap(pid_t pid)
{
	int status = 0;

	while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
		;
	return status;
}

static int find_bg(const char *name)
{
	int i;

	for (i = 0; i < MAX_BG; i++)
		if (bg[i].pid > 0 && strcmp(bg[i].name, name) == 0)
			return i;
	say("no background process named %s", name);
	return -1;
}

static void show(const char *path)
{
	char line[1024];
	FILE *f = fopen(path, "re");
	int n = 0;

	if (!f) {
		say("show %s: %s", path, strerror(errno));
		return;
	}
	while (fgets(line, sizeof(line), f)) {
		line[strcspn(line, "\n")] = 0;
		say("%s: %s", path, line);
		n++;
	}
	fclose(f);
	say("%s: %d line(s)", path, n);
}

static void step(char *line)
{
	char *argv[MAX_ARGS + 1], *save = NULL, *tok;
	int argc = 0, i;

	for (tok = strtok_r(line, " \t\n", &save); tok && argc < MAX_ARGS;
	     tok = strtok_r(NULL, " \t\n", &save))
		argv[argc++] = tok;
	argv[argc] = NULL;
	if (argc == 0 || argv[0][0] == '#')
		return;

	if (strcmp(argv[0], "run") == 0 && argc >= 2) {
		char what[512] = "";
		pid_t pid;

		for (i = 1; i < argc; i++) {
			strncat(what, argv[i], sizeof(what) - strlen(what) - 2);
			if (i + 1 < argc)
				strcat(what, " ");
		}
		say("running %s", what);
		pid = spawn(argv + 1);
		if (pid > 0)
			report(what, reap(pid));
	} else if (strcmp(argv[0], "start") == 0 && argc >= 3) {
		for (i = 0; i < MAX_BG && bg[i].pid > 0; i++)
			;
		if (i == MAX_BG) {
			say("too many background processes");
			return;
		}
		snprintf(bg[i].name, sizeof(bg[i].name), "%s", argv[1]);
		bg[i].pid = spawn(argv + 2);
		say("started %s (pid %d): %s", argv[1], bg[i].pid, argv[2]);
	} else if (strcmp(argv[0], "wait") == 0 && argc == 2) {
		i = find_bg(argv[1]);
		if (i >= 0) {
			report(argv[1], reap(bg[i].pid));
			bg[i].pid = 0;
		}
	} else if (strcmp(argv[0], "kill") == 0 && argc == 2) {
		i = find_bg(argv[1]);
		if (i >= 0) {
			kill(bg[i].pid, SIGKILL);
			report(argv[1], reap(bg[i].pid));
			bg[i].pid = 0;
		}
	} else if (strcmp(argv[0], "sleep") == 0 && argc == 2) {
		int ms = atoi(argv[1]);
		struct timespec ts = { .tv_sec = ms / 1000, .tv_nsec = (long)(ms % 1000) * 1000000L };

		nanosleep(&ts, NULL);
	} else if (strcmp(argv[0], "pin") == 0 && argc == 2) {
		cpu_set_t set;

		CPU_ZERO(&set);
		CPU_SET(atoi(argv[1]), &set);
		if (sched_setaffinity(0, sizeof(set), &set) < 0)
			say("pin %s: %s", argv[1], strerror(errno));
	} else if (strcmp(argv[0], "show") == 0 && argc == 2) {
		show(argv[1]);
	} else {
		say("unknown step: %s", argv[0]);
	}
}

int main(int argc, char **argv)
{
	char path[512], line[1024];
	FILE *f;
	int i;

	(void)argc;
	snprintf(path, sizeof(path), "%s.cmd", argv[0]);
	f = fopen(path, "re");
	if (!f) {
		say("%s: %s", path, strerror(errno));
		return 1;
	}
	while (fgets(line, sizeof(line), f))
		step(line);
	fclose(f);
	for (i = 0; i < MAX_BG; i++)
		if (bg[i].pid > 0) {
			kill(bg[i].pid, SIGKILL);
			reap(bg[i].pid);
		}
	say("done");
	return 0;
}
