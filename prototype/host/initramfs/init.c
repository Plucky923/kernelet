/*
 * init for the kernelet-in-Linux prototype initramfs.
 *
 * No busybox, no shell: this is PID 1. It mounts the pseudo filesystems,
 * loads the staged modules, runs the staged tests, unloads the modules and
 * powers the machine off, so that a `make run` is a self-terminating test.
 *
 * Built static: gcc -static -O2 -o init init.c
 *
 * Output goes through write(2) rather than stdio, so that nothing sits in a
 * buffer when the machine powers off or a test crashes the kernel.
 */

#define _GNU_SOURCE

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#define MODULE_DIR "/modules"
#define TEST_DIR   "/tests"
#define MAX_MODULES 64
#define NAME_MAX_LEN 256

/* --- output ----------------------------------------------------------- */

/*
 * Writes to the console tty are queued and transmitted by interrupt, while
 * printk drives the same UART synchronously, so kernel output can overtake
 * ours and the serial log stops reflecting the true order of events.
 * Draining after each line costs nothing here and keeps the log readable.
 */
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
	char buf[512];
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	if (n < 0)
		return;
	if ((size_t)n >= sizeof(buf))
		buf[sizeof(buf) - 1] = '\0';
	out(buf);
}

/* --- syscalls without a glibc wrapper --------------------------------- */

static int finit_module(int fd, const char *args, int flags)
{
	return (int)syscall(SYS_finit_module, fd, args, flags);
}

static int delete_module(const char *name, int flags)
{
	return (int)syscall(SYS_delete_module, name, flags);
}

/* --- early setup ------------------------------------------------------ */

static void mount_one(const char *src, const char *target, const char *type)
{
	mkdir(target, 0755);
	if (mount(src, target, type, 0, NULL) != 0 && errno != EBUSY)
		outf("INIT: mount %s on %s failed: %s\n",
		     type, target, strerror(errno));
}

/*
 * CONFIG_DEVTMPFS_MOUNT does not apply to an initramfs, so /dev is ours to
 * mount. If the kernel could not give us a console (no /dev/console in the
 * archive), pick one up now that devtmpfs is there.
 */
static void ensure_console(void)
{
	int fd;

	if (fcntl(1, F_GETFD) >= 0)
		return;
	fd = open("/dev/console", O_RDWR);
	if (fd < 0)
		return;
	dup2(fd, 0);
	dup2(fd, 1);
	dup2(fd, 2);
	if (fd > 2)
		close(fd);
}

/* --- modules ---------------------------------------------------------- */

static char mod_files[MAX_MODULES][NAME_MAX_LEN];	/* e.g. "smoke.ko" */
static char mod_args[MAX_MODULES][NAME_MAX_LEN];	/* e.g. "klet_tick=0" */
static int  mod_count;
static char loaded[MAX_MODULES][NAME_MAX_LEN];		/* e.g. "smoke" */
static int  loaded_count;

/* dir + "/" + name, with name capped so the compiler can see the bound. */
static void path_join(char *buf, size_t buflen, const char *dir, const char *name)
{
	snprintf(buf, buflen, "%s/%.*s", dir, NAME_MAX_LEN - 1, name);
}

static int ends_with_ko(const char *name)
{
	size_t len = strlen(name);

	return len > 3 && strcmp(name + len - 3, ".ko") == 0;
}

static void add_module_file_args(const char *name, const char *args);

static void add_module_file(const char *name)
{
	add_module_file_args(name, "");
}

/* A line of MODULE_DIR/order is "<file>.ko [args...]"; the args go to
 * finit_module, which is how a module parameter gets set from here. */
static void add_module_file_args(const char *name, const char *args)
{
	if (mod_count >= MAX_MODULES) {
		outf("INIT: too many modules, ignoring %s\n", name);
		return;
	}
	snprintf(mod_files[mod_count], NAME_MAX_LEN, "%s", name);
	snprintf(mod_args[mod_count], NAME_MAX_LEN, "%s", args);
	mod_count++;
}

/* Reads MODULE_DIR/order: one module file name per line, blanks and
 * '#' comments ignored. Returns 0 if there is no such file. */
static int read_order(void)
{
	char path[NAME_MAX_LEN * 2];
	char line[NAME_MAX_LEN];
	FILE *f;

	snprintf(path, sizeof(path), "%s/order", MODULE_DIR);
	f = fopen(path, "re");
	if (!f)
		return 0;

	while (fgets(line, sizeof(line), f)) {
		char *p = line;
		char *end;
		char *args;

		while (*p == ' ' || *p == '\t')
			p++;
		end = p + strlen(p);
		while (end > p && (end[-1] == '\n' || end[-1] == '\r' ||
				   end[-1] == ' ' || end[-1] == '\t'))
			*--end = '\0';
		if (*p == '\0' || *p == '#')
			continue;
		/* Split "<file>.ko args..." at the first blank. */
		args = strpbrk(p, " \t");
		if (args) {
			*args++ = '\0';
			while (*args == ' ' || *args == '\t')
				args++;
		} else {
			args = "";
		}
		if (!ends_with_ko(p)) {
			outf("INIT: /modules/order: ignoring '%s' (not a .ko)\n", p);
			continue;
		}
		add_module_file_args(p, args);
	}
	fclose(f);
	outf("INIT: module order from %s/order (%d entr%s)\n",
	     MODULE_DIR, mod_count, mod_count == 1 ? "y" : "ies");
	return 1;
}

static int name_cmp(const void *a, const void *b)
{
	return strcmp(*(const char **)a, *(const char **)b);
}

/* Fallback: every *.ko in MODULE_DIR, in name order. */
static void scan_modules(void)
{
	struct dirent *de;
	DIR *d;

	d = opendir(MODULE_DIR);
	if (!d) {
		if (errno != ENOENT)
			outf("INIT: opendir %s failed: %s\n",
			     MODULE_DIR, strerror(errno));
		return;
	}
	while ((de = readdir(d)) != NULL) {
		if (ends_with_ko(de->d_name))
			add_module_file(de->d_name);
	}
	closedir(d);

	if (mod_count > 1) {
		const char *ptrs[MAX_MODULES];
		char sorted[MAX_MODULES][NAME_MAX_LEN];
		int i;

		for (i = 0; i < mod_count; i++)
			ptrs[i] = mod_files[i];
		qsort(ptrs, (size_t)mod_count, sizeof(ptrs[0]), name_cmp);
		for (i = 0; i < mod_count; i++)
			snprintf(sorted[i], NAME_MAX_LEN, "%s", ptrs[i]);
		for (i = 0; i < mod_count; i++)
			snprintf(mod_files[i], NAME_MAX_LEN, "%s", sorted[i]);
	}
}

/* Module name as the kernel knows it: basename without .ko, '-' -> '_'. */
static void module_name(const char *file, char *buf, size_t buflen)
{
	size_t len = strlen(file);
	size_t i;

	if (len > 3)
		len -= 3;			/* drop ".ko" */
	if (len >= buflen)
		len = buflen - 1;
	for (i = 0; i < len; i++)
		buf[i] = file[i] == '-' ? '_' : file[i];
	buf[len] = '\0';
}

static void load_modules(void)
{
	char path[NAME_MAX_LEN * 2];
	int i, fd;

	if (mod_count == 0) {
		out("INIT: no modules to load\n");
		return;
	}
	for (i = 0; i < mod_count; i++) {
		path_join(path, sizeof(path), MODULE_DIR, mod_files[i]);
		fd = open(path, O_RDONLY | O_CLOEXEC);
		if (fd < 0) {
			outf("INIT: open %s failed: %s\n", path, strerror(errno));
			continue;
		}
		if (mod_args[i][0] != '\0')
			outf("INIT: loading %s %s\n", mod_files[i], mod_args[i]);
		else
			outf("INIT: loading %s\n", mod_files[i]);
		if (finit_module(fd, mod_args[i], 0) != 0) {
			outf("INIT: finit_module %s failed: %s (errno %d)\n",
			     mod_files[i], strerror(errno), errno);
		} else {
			module_name(mod_files[i], loaded[loaded_count],
				    NAME_MAX_LEN);
			loaded_count++;
		}
		close(fd);
	}
}

static void unload_modules(void)
{
	int i;

	for (i = loaded_count - 1; i >= 0; i--) {
		outf("INIT: unloading %s\n", loaded[i]);
		if (delete_module(loaded[i], 0) != 0)
			outf("INIT: delete_module %s failed: %s (errno %d)\n",
			     loaded[i], strerror(errno), errno);
	}
}

/* --- tests ------------------------------------------------------------ */

static void run_one(const char *path)
{
	char *const argv[] = { (char *)path, NULL };
	char *const envp[] = { (char *)"PATH=/tests:/",
			       (char *)"HOME=/", NULL };
	int status = 0;
	pid_t pid, done;

	outf("INIT: running %s\n", path);
	pid = fork();
	if (pid < 0) {
		outf("INIT: fork failed: %s\n", strerror(errno));
		return;
	}
	if (pid == 0) {
		execve(path, argv, envp);
		outf("INIT: execve %s failed: %s\n", path, strerror(errno));
		_exit(127);
	}
	do {
		done = waitpid(pid, &status, 0);
	} while (done < 0 && errno == EINTR);
	if (done < 0) {
		outf("INIT: waitpid %s failed: %s\n", path, strerror(errno));
		return;
	}
	if (WIFEXITED(status))
		outf("INIT: %s exited %d\n", path, WEXITSTATUS(status));
	else if (WIFSIGNALED(status))
		outf("INIT: %s killed by signal %d\n", path, WTERMSIG(status));
	else
		outf("INIT: %s ended with status 0x%x\n", path, status);
}

static void run_tests(void)
{
	char names[MAX_MODULES][NAME_MAX_LEN];
	const char *ptrs[MAX_MODULES];
	char path[NAME_MAX_LEN * 2];
	struct dirent *de;
	struct stat st;
	DIR *d;
	int count = 0, i;

	d = opendir(TEST_DIR);
	if (!d) {
		if (errno != ENOENT)
			outf("INIT: opendir %s failed: %s\n",
			     TEST_DIR, strerror(errno));
		out("INIT: no tests to run\n");
		return;
	}
	while ((de = readdir(d)) != NULL && count < MAX_MODULES) {
		if (de->d_name[0] == '.')
			continue;
		path_join(path, sizeof(path), TEST_DIR, de->d_name);
		if (stat(path, &st) != 0 || !S_ISREG(st.st_mode))
			continue;
		if (access(path, X_OK) != 0)
			continue;
		snprintf(names[count], NAME_MAX_LEN, "%s", de->d_name);
		count++;
	}
	closedir(d);

	if (count == 0) {
		out("INIT: no tests to run\n");
		return;
	}
	for (i = 0; i < count; i++)
		ptrs[i] = names[i];
	qsort(ptrs, (size_t)count, sizeof(ptrs[0]), name_cmp);
	for (i = 0; i < count; i++) {
		path_join(path, sizeof(path), TEST_DIR, ptrs[i]);
		run_one(path);
	}
}

/* --- main ------------------------------------------------------------- */

int main(void)
{
	mount_one("proc", "/proc", "proc");
	mount_one("sysfs", "/sys", "sysfs");
	/* The unified hierarchy: the endovisor refuses a sandbox in its root group. */
	mount_one("cgroup2", "/sys/fs/cgroup", "cgroup2");
	/*
	 * The runtimes write their report lines into the kernel's log through
	 * /dev/kmsg, so that they are in order with the endovisor's on the
	 * serial console; by default Linux rate-limits those writes to ten
	 * every five seconds.
	 */
	{
		int fd = open("/proc/sys/kernel/printk_devkmsg", O_WRONLY | O_CLOEXEC);

		if (fd >= 0) {
			if (write(fd, "on\n", 3) != 3)
				out("INIT: cannot turn printk_devkmsg on\n");
			close(fd);
		}
	}
	mount_one("devtmpfs", "/dev", "devtmpfs");
	ensure_console();

	out("\n");
	out("========================================\n");
	out("INIT: kernelet-in-Linux prototype harness\n");
	out("========================================\n");

	if (!read_order())
		scan_modules();
	load_modules();

	run_tests();

	unload_modules();

	out("INIT: done\n");
	sync();

	reboot(RB_POWER_OFF);
	outf("INIT: reboot(RB_POWER_OFF) failed: %s\n", strerror(errno));
	/* Last resort: a reboot, which QEMU's -no-reboot turns into an exit. */
	reboot(RB_AUTOBOOT);
	outf("INIT: reboot(RB_AUTOBOOT) failed: %s\n", strerror(errno));
	for (;;)
		pause();
}
