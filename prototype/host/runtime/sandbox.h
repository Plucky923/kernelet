/*
 * sandbox: the client of the endovisor UAPI, for the holder and the
 * experiment drivers (run-sched, run-mem, uapi-check).
 *
 * The functions the book reads are these: open_system, register_kind,
 * find_kind, join_cgroup, start_carrier, wait_sandbox and run_sandbox. The
 * rest is what the prototype's tests need around them.
 */
#ifndef KLET_SANDBOX_H
#define KLET_SANDBOX_H

#include <sys/types.h>

#include <endovisor.h>

struct sandbox;

/* How run_sandbox() sets the sandbox and its carriers up. */
struct sandbox_opts {
	const char *cgroup;		/* -c: join this group before KLET_CREATE */
	int pin;			/* -p: the carrier of virtual CPU i on processor i */
	int cpu_lo, cpu_hi;		/* every carrier on processors [lo, hi]; hi < 0: no mask */
	/*
	 * -k: set neither console nor log, so that the endovisor writes both to
	 * the host's kernel log, in order with its own lines; otherwise the
	 * console and the log are console_path and log_path, files opened here,
	 * or the holder's standard output and standard error.
	 */
	int kernel_log;
	const char *console_path, *log_path;
	int seccomp_kill_nr;		/* --seccomp-kill: a filter that kills on this call; -1 */
	int kill_after_ms;		/* --kill-after: SIGKILL to vCPU 0's carrier; -1 */
	int klet_kill_after_ms;		/* --klet-kill-after: KLET_KILL(1); -1 */
	unsigned long long memory_initial, memory_max, max_tasks;
	/* Called once every carrier has been forked, before the wait. */
	void (*during)(struct sandbox *sb, void *arg);
	void *arg;
};

/* A sandbox being run. */
struct sandbox {
	int sys_fd, fd, slot;
	unsigned int nr_vcpus;
	pid_t pids[KLET_MAX_VCPUS];
	struct klet_exit ex;
};

void sandbox_opts_init(struct sandbox_opts *opt);

int open_system(void);
int register_kind(int sys_fd, const char *name, const char *image_path);
int find_kind(int sys_fd, const char *name);
void join_cgroup(const char *dir);
void start_carrier(int exec_fd, unsigned int vcpu, const struct sandbox_opts *opt);
void wait_sandbox(int sandbox_fd, const pid_t *pids, unsigned int nr_vcpus, struct klet_exit *ex);
int run_sandbox(int sys_fd, const char *name, unsigned int nr_vcpus, const char *cmdline,
		const struct sandbox_opts *opt);

/* For the drivers. */
int sandbox_exited(const struct sandbox *sb, int timeout_ms);
void sandbox_print_stats(const struct sandbox *sb, const char *when);
void sandbox_say(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
int module_references(const char *name);
void proc_status_field(long pid, const char *key, char *buf, size_t len);
char proc_task_state(long pid);
void msleep(int ms);
int sandbox_read_staged(const char *path, char *mode, size_t mode_len, unsigned int *nr_vcpus,
			char *cmdline, size_t cmdline_len);
long long now_ms(void);

/* The prefix of every line sandbox_say() prints: "holder", "RUN-MEM", ... */
extern const char *sandbox_who;

#endif /* KLET_SANDBOX_H */
