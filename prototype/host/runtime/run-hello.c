/*
 * run-hello: the kernelet runtime of this prototype.
 *
 * A container runtime creates and configures a sandbox and then gets out of the
 * way. This one does the smallest version of that: it forks, drops the ability
 * to gain privileges in the child, and execs /hello.klet, the sandbox's
 * configuration: the magic "KLET", a version, the number of virtual CPUs and a
 * command line. The endovisor's binary-format handler recognises the magic and
 * turns the child into the root carrier of a kernelet.
 *
 * The child never returns to user mode again: on its way there the
 * resume hook brings up the sandbox's vCPU carriers and then waits for the
 * sandbox to end. It dies by SIGKILL when the kernelet powers off.
 *
 * Built static: gcc -static -O2 -o run-hello run-hello.c
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define KLET_PATH "/hello.klet"
#define MODULE_NAME "kernelet"

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

/*
 * Every carrier's mm holds a reference to the module (set_binfmt/dup_mm take
 * one, mmput drops it), so the module cannot be unloaded until the last carrier
 * has finished exiting. The reference count is the third field of the module's
 * line in /proc/modules; wait for it to reach zero so that init's delete_module
 * does not race the carriers' deaths.
 */
static int module_refcount(void)
{
	char line[512];
	FILE *f;
	int refs = -1;

	f = fopen("/proc/modules", "re");
	if (!f)
		return -1;
	while (fgets(line, sizeof(line), f)) {
		char name[128];
		unsigned long size;
		int n;

		if (sscanf(line, "%127s %lu %d", name, &size, &n) != 3)
			continue;
		if (strcmp(name, MODULE_NAME) == 0) {
			refs = n;
			break;
		}
	}
	fclose(f);
	return refs;
}

static void wait_for_module_idle(int timeout_ms)
{
	struct timespec ts = { .tv_sec = 0, .tv_nsec = 5 * 1000 * 1000 };
	int waited = 0;
	int refs;

	for (;;) {
		refs = module_refcount();
		if (refs <= 0)
			break;
		if (waited >= timeout_ms) {
			outf("RUN-HELLO: module still has %d reference(s) after %d ms\n",
			     refs, waited);
			return;
		}
		nanosleep(&ts, NULL);
		waited += 5;
	}
	outf("RUN-HELLO: no carrier left (module references: %d)\n",
	     refs < 0 ? 0 : refs);
}

int main(void)
{
	char *const argv[] = { (char *)KLET_PATH, NULL };
	char *const envp[] = { NULL };
	int status = 0;
	pid_t pid, done;

	out("RUN-HELLO: creating a sandbox from " KLET_PATH "\n");

	pid = fork();
	if (pid < 0) {
		outf("RUN-HELLO: fork failed: %s\n", strerror(errno));
		return 1;
	}
	if (pid == 0) {
		if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0)
			outf("RUN-HELLO: PR_SET_NO_NEW_PRIVS failed: %s\n",
			     strerror(errno));
		execve(KLET_PATH, argv, envp);
		outf("RUN-HELLO: execve %s failed: %s\n", KLET_PATH,
		     strerror(errno));
		_exit(127);
	}

	do {
		done = waitpid(pid, &status, 0);
	} while (done < 0 && errno == EINTR);

	if (done < 0)
		outf("RUN-HELLO: waitpid failed: %s\n", strerror(errno));
	else if (WIFEXITED(status))
		outf("RUN-HELLO: root carrier (pid %d) exited %d\n", pid,
		     WEXITSTATUS(status));
	else if (WIFSIGNALED(status))
		outf("RUN-HELLO: root carrier (pid %d) killed by signal %d\n",
		     pid, WTERMSIG(status));

	wait_for_module_idle(5000);
	out("RUN-HELLO: done\n");
	return 0;
}
