// SPDX-License-Identifier: GPL-2.0
/*
 * vCPU carriers, the coroutine, the gate hooks, and the service table.
 *
 * The whole control flow of the prototype is here:
 *
 *   root carrier          vCPU 0 carrier            vCPU 1 carrier
 *   ------------          --------------            --------------
 *   load_binary()
 *   resume hook ->
 *     clone N vCPUs ----> klet_carrier_main()
 *                          klet_enter() -> coroutine
 *                            kernelet_entry()
 *                              __ostd_main() -> main()
 *                                inject_scheduler
 *                                register_ap_entry
 *                                  -> vcpu_boot(1) --> (was waiting) klet_enter()
 *                                                        vcpu_entry(1)
 *                                                          idle loop / tasks
 *                                Task::run, Task::yield_now
 *                                  -> OSTD's own scheduler, OSTD's own stacks
 *                                     user_run
 *                          <- Linux stack
 *                          resume hook: adopt the space's mm, apply regs, iret
 *                          syscall hook: -> coroutine
 *     wait to die
 *
 * Three rules the code exists to keep:
 *
 *  - no kernelet code runs on a carrier's Linux stack;
 *  - no Linux function runs on a kernelet stack. What the endovisor runs there
 *    is the stub of each service: the C wrapper the service table points at
 *    (klet_svc_log_write, klet_svc_vm_map, ..., and klet_svc_enter or
 *    klet_svc_enter5 behind it), which finds the carrier through `current`,
 *    packs the arguments and calls klet_run_on_linux_stack, the few
 *    instructions that move to the Linux stack and call klet_svc_body there;
 *    the wrappers of vm_wait, vcpu_yield and stop, which on the way back look
 *    at the carrier's flags and leave the kernelet for good if the sandbox is
 *    dying; user_run and klet_leave, which take the mirror off Linux's
 *    preemption count and switch to the Linux stack; klet_yield_body and
 *    klet_evict_leave, the same for the yield and exit stubs; klet_coro_main,
 *    which calls the kernelet's entry point on a vCPU's first coroutine and
 *    leaves if it ever returns; and, once, on the first log line,
 *    klet_measure_switch's timing loop. None of it calls a function of the
 *    Linux kernel: what it uses of Linux are the header helpers compiled into
 *    the module itself (`current`, the preemption count, the interrupt flag,
 *    the time-stamp counter, the signal bits), and a warning it would print
 *    waits for the Linux stack (see mirror_fault_pc); and
 *  - nothing the kernelet writes decides how much the endovisor changes Linux's
 *    own state. The mirrored preemption count is un-mirrored by measuring
 *    Linux's count, not by believing the kernelet's `masked`.
 */

#include <linux/compat.h>
#include <linux/entry-common.h>
#include <linux/fdtable.h>
#include <linux/file.h>
#include <linux/kernel.h>
#include <linux/kernelet.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/preempt.h>
#include <linux/resume_user_mode.h>
#include <linux/sched.h>
#include <linux/sched/mm.h>
#include <linux/sched/signal.h>
#include <linux/sched/task.h>
#include <linux/signal.h>
#include <linux/slab.h>
#include <linux/thread_info.h>
#include <linux/vmalloc.h>
#include <linux/freezer.h>
#include <linux/hrtimer.h>

#include <asm/asm.h>
#include <asm/cpufeature.h>
#include <asm/fpu/api.h>
#include <asm/msr.h>
#include <asm/processor.h>
#include <asm/ptrace.h>
#include <asm/segment.h>
#include <asm/trapnr.h>

#include "kernelet.h"

const char *klet_kind_name(enum klet_kind kind)
{
	return kind == KLET_ROOT ? "root" : "vcpu";
}

/* ------------------------------------------------------------------ */
/* Carrier records                                                    */
/* ------------------------------------------------------------------ */

struct klet_carrier *klet_carrier_get(struct klet_carrier *c)
{
	refcount_inc(&c->refs);
	return c;
}

/*
 * A carrier record has two references for as long as its carrier lives: the
 * carrier's own, taken by klet_carrier_new() and dropped by
 * klet_carrier_lifeline_closed(), and the lifeline file's, dropped when the
 * file is released. Anyone else who looks a carrier up (a kick) takes one of
 * its own under inst->lock.
 */
void klet_carrier_put(struct klet_carrier *c)
{
	struct klet_inst *inst = c->inst;

	if (!refcount_dec_and_test(&c->refs))
		return;
	if (c->task)
		put_task_struct(c->task);
	kfree(c);
	atomic_inc(&inst->carriers_freed);
}

/*
 * Builds the bootstrap coroutine stack so that the first klet_switch() into it
 * lands in klet_coro_trampoline with the carrier in %r12.
 */
static void klet_coro_prepare(struct klet_carrier *c)
{
	u64 *sp = (u64 *)((char *)c->stack + KLET_STACK_SIZE);

	*--sp = 0;				/* fake return address */
	*--sp = (u64)klet_coro_trampoline;	/* klet_switch's `ret` target */
	*--sp = 0;				/* rbp */
	*--sp = 0;				/* rbx */
	*--sp = (u64)c;				/* r12: the carrier */
	*--sp = 0;				/* r13 */
	*--sp = 0;				/* r14 */
	*--sp = 0;				/* r15 */
	c->coro_sp = sp;
	c->state = KLET_NEW;
}

struct klet_carrier *klet_carrier_new(struct klet_inst *inst, enum klet_kind kind,
				      int vcpu)
{
	struct klet_carrier *c;

	c = kzalloc(sizeof(*c), GFP_KERNEL);
	if (!c)
		return NULL;

	c->gate.ops = &klet_gate_ops;
	c->inst = inst;
	c->kind = kind;
	c->vcpu = vcpu;
	c->mirror_fault_pc = -1;
	refcount_set(&c->refs, 1);
	INIT_LIST_HEAD(&c->link);
	init_waitqueue_head(&c->idle_wq);

	/* The kernelet's own view of this virtual CPU. */
	c->vrec.vcpu_id = vcpu < 0 ? 0 : vcpu;
	c->vrec.nr_vcpus = inst->nr_vcpus;
	atomic_set(&c->vrec.pending, 0);
	c->vrec.irq_off = 0;
	/* OSTD's preemption word starts at "no guards, no preemption wanted". */
	c->vrec.preempt_info = 0x80000000u;

	if (kind != KLET_ROOT) {
		c->stack = (void *)(unsigned long)klet_kstack_alloc(inst);
		if (!c->stack) {
			kfree(c);
			return NULL;
		}
		c->fpu_stage = (void *)__get_free_page(GFP_KERNEL | __GFP_ZERO);
		if (!c->fpu_stage) {
			klet_kstack_put(inst, (u64)(unsigned long)c->stack);
			kfree(c);
			return NULL;
		}
		klet_coro_prepare(c);
		/* Until the kernelet runs its first task, the stack an upcall may be
		 * pushed onto is this vCPU's bootstrap stack. */
		c->vrec.stack_limit = (u64)(unsigned long)c->stack;
	} else {
		c->state = KLET_RUNNING;
	}

	c->task = get_task_struct(current);

	spin_lock(&inst->lock);
	list_add_tail(&c->link, &inst->carriers);
	spin_unlock(&inst->lock);
	atomic_inc(&inst->nr_carriers);
	atomic_inc(&inst->carriers_made);

	return c;
}

/*
 * Attaches the carrier to the current task: this is what makes it a carrier.
 * Installs the carrier's lifeline too, an open file of the endovisor in the
 * carrier's own descriptor table whose ->release is Linux's notice that the
 * carrier has died, however it died.
 */
int klet_carrier_attach(struct klet_carrier *c)
{
	struct file *file;
	int fd;

	file = klet_lifeline_create(c);
	if (IS_ERR(file))
		return PTR_ERR(file);

	fd = get_unused_fd_flags(0);
	if (fd < 0) {
		/*
		 * The caller sends the death notice itself, so the file's release
		 * must not send a second one: it gives back only its reference.
		 */
		file->private_data = NULL;
		fput(file);
		klet_carrier_put(c);
		return fd;
	}
	fd_install(fd, file);
	if (c->kind == KLET_ROOT)
		c->inst->root_lifeline_fd = fd;

	current->kernelet = &c->gate;
	set_syscall_work(KERNELET);
	return 0;
}

/*
 * Unbinds the carrier from its Linux task. The record itself lives until the
 * lifeline is closed.
 */
static void klet_detach(struct klet_carrier *c)
{
	clear_syscall_work(KERNELET);
	current->kernelet = NULL;

	klet_sched_detach(c);
	klet_leave_space(c);

	{
		void *stack = xchg(&c->stack, NULL);
		void *stage = xchg(&c->fpu_stage, NULL);
		struct mm_struct *mm = xchg(&c->blank_mm, NULL);

		if (stack) {
			c->coro_sp = NULL;
			c->state = KLET_DEAD;
			klet_kstack_put(c->inst, (u64)(unsigned long)stack);
		}
		if (stage)
			free_page((unsigned long)stage);
		if (mm)
			mmput(mm);
	}
}

/* The lifeline was closed: this is the death notice. */
void klet_carrier_lifeline_closed(struct klet_carrier *c)
{
	struct klet_inst *inst = c->inst;
	bool was_root = (c->kind == KLET_ROOT);
	/* Read without the lock, as everywhere but klet_kill_instance (see there). */
	bool live = !READ_ONCE(inst->stopped) && !READ_ONCE(inst->dying);
	bool last;

	spin_lock(&inst->lock);
	list_del_init(&c->link);
	if (c->vcpu >= 0 && c->vcpu < KLET_MAX_VCPUS && inst->vcpus[c->vcpu] == c)
		inst->vcpus[c->vcpu] = NULL;
	spin_unlock(&inst->lock);

	last = atomic_dec_and_test(&inst->nr_carriers);
	if (c->kind == KLET_ROOT)
		pr_info("kernelet: root carrier (pid %d) lifeline closed%s\n",
			c->task ? c->task->pid : 0,
			last ? ", the last one" : live ? ", the sandbox is dying" : "");
	else
		pr_info("kernelet: vcpu %d carrier (pid %d) lifeline closed%s\n",
			c->vcpu, c->task ? c->task->pid : 0,
			last ? ", the last one" : live ? ", the sandbox is dying" : "");

	/*
	 * The root carrier's death is always the sandbox's death: everything else
	 * is killed, and whatever is spinning inside the kernelet is evicted. That
	 * holds after the kernelet stopped itself too, because a vCPU it left
	 * spinning in kernel mode on a lock the stopped vCPU held never returns to
	 * the gate to die: only eviction gets it out.
	 *
	 * A vCPU carrier's death while the sandbox is live is the sandbox's death
	 * as well: killed by the OOM killer or an operator, it takes its virtual
	 * CPU with it, and the others would spin for ever on whatever locks it
	 * held.
	 */
	if ((was_root || live) && !last)
		klet_kill_instance(inst);

	/*
	 * A carrier killed from outside while in user mode dies in Linux's exit
	 * path without the gate ever running again, so klet_detach() never ran
	 * for it. Whatever detach did not release is released here, which runs
	 * however the carrier died (the lifeline is closed in exit_files(), in the
	 * dying task's context): the blank mm's reference, and with it the module
	 * reference its binfmt holds, the kernelet stack and the FPU staging page.
	 */
	{
		struct mm_struct *mm = xchg(&c->blank_mm, NULL);
		void *stack = xchg(&c->stack, NULL);
		void *stage = xchg(&c->fpu_stage, NULL);

		if (stack)
			klet_kstack_put(inst, (u64)(unsigned long)stack);
		if (stage)
			free_page((unsigned long)stage);
		if (mm) {
			pr_info("kernelet: vcpu %d carrier died without detaching; its records released\n",
				c->vcpu);
			mmput(mm);
		}
	}

	if (last)
		klet_spaces_destroy(inst);

	/*
	 * The carrier's own reference, and with it, once the lifeline file has
	 * given back its own, the record and the task_struct reference it holds.
	 *
	 * Nothing may still reach the record through the task first. A carrier
	 * killed in user mode never ran klet_detach(): its task_struct still
	 * points at the gate, and its preempt notifier is still registered, and
	 * both would be used after the free, by the watch timer's and the sweep's
	 * look at `current` in the rest of do_exit(), and by the final
	 * schedule()'s sched_out notifier. The lifeline is released in
	 * exit_task_work(), in the dying task's own context, before that final
	 * schedule(), so they are undone here. A notifier may only be
	 * unregistered by its own task: if the lifeline is released anywhere
	 * else (a copy of the descriptor taken with pidfd_getfd(), closed after
	 * the carrier died), a record still attached is kept rather than freed,
	 * and the unload counts it.
	 */
	if (c->task == current) {
		clear_syscall_work(KERNELET);
		WRITE_ONCE(current->kernelet, NULL);
		barrier();
		klet_sched_detach(c);
	}
	if (!c->pnotifier_on &&
	    !(c->task && READ_ONCE(c->task->kernelet) == &c->gate))
		klet_carrier_put(c);
	else
		pr_warn("kernelet: %s carrier record (pid %d) released away from its task; kept\n",
			klet_kind_name(c->kind), c->task ? c->task->pid : 0);
}

/*
 * The carrier gives up. Unbinds the gate, frees the coroutine and kills itself:
 * returning to user mode is not an option, because the registers on the way out
 * belong to the kernelet and may be nonsense by now.
 */
static void klet_carrier_die(struct klet_carrier *c)
{
	if (c->kind == KLET_ROOT)
		pr_info("kernelet: root carrier (pid %d) dying\n", current->pid);
	else
		pr_info("kernelet: vcpu %d carrier (pid %d) dying%s%s\n", c->vcpu,
			current->pid,
			c->killed_in ? ", killed in " : c->evicted ? " (evicted)" : "",
			c->killed_in ? c->killed_in : "");
	klet_detach(c);
	if (!fatal_signal_pending(current))
		force_sig(SIGKILL);
}

/* ------------------------------------------------------------------ */
/* The kernelet-stack pool                                            */
/* ------------------------------------------------------------------ */

/*
 * Every kernelet stack is KLET_STACK_SIZE and comes from a per-sandbox pool that
 * is not given back to vmalloc until the sandbox is destroyed.
 *
 * The reason is the host's, not the kernelet's: a kernel that forks and exits
 * churns task stacks, and every vfree() of a vmalloc area eventually costs the
 * whole machine a lazy-purge TLB shootdown. A pool costs the sandbox a few
 * megabytes of address space and the machine nothing, and it makes the cost of
 * creating a kernelet task a list operation.
 */
struct klet_kstack {
	struct list_head link;
	void *base;
	bool busy;
};

u64 klet_kstack_alloc(struct klet_inst *inst)
{
	struct klet_kstack *k;
	void *base;

	spin_lock(&inst->lock);
	list_for_each_entry(k, &inst->kstack_all, link) {
		if (!k->busy) {
			k->busy = true;
			spin_unlock(&inst->lock);
			return (u64)(unsigned long)k->base;
		}
	}
	/*
	 * A new stack: within the pool's bound, reserved before the allocation
	 * so that two vCPUs cannot both take the last one. Beyond the bound the
	 * answer is 0, which vOSTD turns into Error::NoMemory.
	 */
	if (inst->kstack_made >= KLET_MAX_KSTACKS) {
		spin_unlock(&inst->lock);
		return 0;
	}
	inst->kstack_made++;
	spin_unlock(&inst->lock);

	/*
	 * vmalloc's own guard page is the stack's guard page. The pages are
	 * charged to the memory cgroup of the carrier that asked, which is the
	 * sandbox's.
	 */
	base = __vmalloc(KLET_STACK_SIZE, GFP_KERNEL_ACCOUNT);
	k = base ? kzalloc(sizeof(*k), GFP_KERNEL) : NULL;
	if (!k) {
		vfree(base);
		spin_lock(&inst->lock);
		inst->kstack_made--;
		spin_unlock(&inst->lock);
		return 0;
	}
	k->base = base;
	k->busy = true;
	spin_lock(&inst->lock);
	list_add_tail(&k->link, &inst->kstack_all);
	spin_unlock(&inst->lock);
	return (u64)(unsigned long)base;
}

void klet_kstack_put(struct klet_inst *inst, u64 base)
{
	struct klet_kstack *k;

	if (!base)
		return;
	spin_lock(&inst->lock);
	list_for_each_entry(k, &inst->kstack_all, link) {
		if ((u64)(unsigned long)k->base == base) {
			k->busy = false;
			spin_unlock(&inst->lock);
			return;
		}
	}
	spin_unlock(&inst->lock);
	pr_warn("kernelet: kstack_free of %#llx, which is not ours\n", base);
}

void klet_kstack_pool_destroy(struct klet_inst *inst)
{
	struct klet_kstack *k, *tmp;
	LIST_HEAD(dead);

	spin_lock(&inst->lock);
	list_splice_init(&inst->kstack_all, &dead);
	spin_unlock(&inst->lock);

	list_for_each_entry_safe(k, tmp, &dead, link) {
		list_del(&k->link);
		vfree(k->base);
		kfree(k);
	}
}

/* ------------------------------------------------------------------ */
/* The mirror                                                         */
/* ------------------------------------------------------------------ */

/*
 * On the way into kernelet code: remember what Linux's preemption count is now,
 * and put back whatever the kernelet had raised it by when it last left.
 */
static void klet_mirror_in(struct klet_carrier *c)
{
	c->pc_base = preempt_count();
	if (c->excess > 0) {
		preempt_count_add(c->excess);
		c->excess = 0;
	}
}

/*
 * On the way out of kernelet code, in task context: whatever Linux's count is
 * above what it was on the way in is the kernelet's, so take it off. Remember it
 * unless the carrier is leaving the kernelet for good.
 *
 * Measuring Linux's count rather than reading the kernelet's `masked` is
 * deliberate: a kernelet that wrote a wrong depth could otherwise make the
 * endovisor corrupt Linux's per-processor state.
 */
static void klet_mirror_out(struct klet_carrier *c, bool forever)
{
	int now = preempt_count();
	int excess = now - c->pc_base;

	/*
	 * The mirror is boolean: the kernelet raises Linux's count by exactly one
	 * when it enters a critical section and lowers it when it leaves, however
	 * deeply its own guards nest, because Linux has only eight bits for the
	 * count and 256 nested guards would spill into its soft-interrupt field.
	 * So the only legal values here are 0 and 1, and anything else means the
	 * kernelet has corrupted host state: stop it rather than guess.
	 */
	if (excess < 0 || excess > 1) {
		/*
		 * Re-normalise rather than guess. Linux's count is the endovisor's
		 * business: whatever the kernelet did to it, what leaves here must be
		 * exactly what came in, or the next sleep in this service is a
		 * "scheduling while atomic" and the processor's count is wrong for
		 * every task that follows.
		 */
		atomic_inc(&c->inst->mirror_faults);
		c->mirror_fault_pc = now;
		preempt_count_set(c->pc_base);
		c->excess = 0;
		return;
	}
	if (excess > 0)
		preempt_count_sub(excess);
	c->excess = forever ? 0 : excess;
}

/* ------------------------------------------------------------------ */
/* The coroutine                                                      */
/* ------------------------------------------------------------------ */

/* Runs on the Linux stack: gives control to the vCPU's kernelet code. */
static void klet_enter(struct klet_carrier *c, u64 run_ret)
{
	c->run_ret = run_ret;
	c->state = KLET_RUNNING;
	c->depth = 0;
	c->strike1_ns = 0;
	/*
	 * The invariant the whole mirror rests on: when a carrier passes from
	 * endovisor code into kernelet code, none of Linux's preemption count is the
	 * kernelet's.
	 */
	if (c->excess != 0)
		pr_warn_once("kernelet: entering the kernelet with %d borrowed from Linux's preempt count\n",
			     c->excess);
	klet_mirror_in(c);
	klet_watch_arm(c);
	klet_switch(&c->linux_sp, c->coro_sp);

	/* Back on the Linux stack, where a warning may be printed. */
	if (unlikely(c->mirror_fault_pc >= 0)) {
		pr_warn_once("kernelet: Linux's preempt count was %d, expected %d or %d; re-normalised\n",
			     c->mirror_fault_pc, c->pc_base, c->pc_base + 1);
		c->mirror_fault_pc = -1;
	}
}

/* Runs on a kernelet stack: gives control back to the Linux stack. */
static void klet_leave(struct klet_carrier *c, enum klet_state state)
{
	klet_mirror_out(c, state == KLET_DEAD);
	c->state = state;
	klet_switch(&c->coro_sp, c->linux_sp);
}

/* The body of a vCPU's bootstrap coroutine. Entered from klet_coro_trampoline. */
void klet_coro_main(struct klet_carrier *c)
{
	struct klet_inst *inst = c->inst;

	if (c->vcpu == 0)
		kernelet_entry_table.kernelet_entry(&inst->boot, &klet_services);
	else
		kernelet_entry_table.vcpu_entry(c->vcpu);

	/* The kernelet came back out of its entry point. Abandon this stack. */
	for (;;)
		klet_leave(c, KLET_DEAD);
}

/*
 * Called from klet_yield_stub, on the current kernelet stack, with every register
 * of the interrupted kernelet code saved above us. All it does is leave the
 * kernelet stack, exactly as a service stub does, so that Linux's scheduler runs
 * where Linux expects to be.
 *
 * Returns the instruction pointer to go back to, or zero if the kernelet died
 * while we were away, in which case the stub must not resume it.
 */
unsigned long klet_yield_body(void)
{
	struct klet_carrier *c = klet_current_carrier();
	struct klet_svc_args args = { .op = KLET_SVC_VCPU_YIELD };
	unsigned long ip = c->yield_ip;

	klet_run_on_linux_stack(c->linux_sp, &args);
	if (args.ret || READ_ONCE(c->doomed))
		return 0;
	return ip;
}

/*
 * Called from klet_exit_stub, on a kernelet stack, after the eviction sweep
 * pointed the interrupted instruction pointer at the stub. The only thing left to
 * do is the ordinary switch back, with a flag that says "do not come back".
 *
 * Note that the evicted kernelet may have been holding guards, so Linux's
 * preemption count may be above what it was when the carrier entered. klet_leave
 * takes the whole difference off and does not remember it, which is what makes
 * eviction safe from a critical section.
 */
void klet_evict_leave(void)
{
	struct klet_carrier *c = klet_current_carrier();

	c->evicted = true;
	for (;;)
		klet_leave(c, KLET_DEAD);
}

/* ------------------------------------------------------------------ */
/* Registers                                                          */
/* ------------------------------------------------------------------ */

/*
 * The RFLAGS bits a kernelet may ask for. IOPL, NT, AC, RF, VM, VIF and VIP are
 * dropped; IF is forced on so that the carrier stays interruptible in user mode,
 * and the always-one bit 1 is set.
 */
#define KLET_RFLAGS_USER                                                       \
	(X86_EFLAGS_CF | X86_EFLAGS_PF | X86_EFLAGS_AF | X86_EFLAGS_ZF |        \
	 X86_EFLAGS_SF | X86_EFLAGS_TF | X86_EFLAGS_DF | X86_EFLAGS_OF |        \
	 X86_EFLAGS_ID)

static void klet_ctx_to_regs(struct klet_carrier *c, struct pt_regs *regs)
{
	struct klet_user_ctx *x = c->ctx;

	regs->ax = x->rax;
	regs->bx = x->rbx;
	regs->cx = x->rcx;
	regs->dx = x->rdx;
	regs->si = x->rsi;
	regs->di = x->rdi;
	regs->bp = x->rbp;
	regs->sp = x->rsp;
	regs->r8 = x->r8;
	regs->r9 = x->r9;
	regs->r10 = x->r10;
	regs->r11 = x->r11;
	regs->r12 = x->r12;
	regs->r13 = x->r13;
	regs->r14 = x->r14;
	regs->r15 = x->r15;
	regs->ip = x->rip;
	regs->flags = (x->rflags & KLET_RFLAGS_USER) | X86_EFLAGS_IF |
		      X86_EFLAGS_FIXED;
	regs->cs = __USER_CS;
	regs->ss = __USER_DS;
	/* Never let Linux's system-call restart logic fire on a carrier. */
	regs->orig_ax = -1;
}

static void klet_regs_to_ctx(struct klet_carrier *c, struct pt_regs *regs)
{
	struct klet_user_ctx *x = c->ctx;

	/* The system call number as issued; ax itself holds -ENOSYS by now. */
	x->rax = regs->orig_ax;
	x->rbx = regs->bx;
	x->rcx = regs->cx;
	x->rdx = regs->dx;
	x->rsi = regs->si;
	x->rdi = regs->di;
	x->rbp = regs->bp;
	x->rsp = regs->sp;
	x->r8 = regs->r8;
	x->r9 = regs->r9;
	x->r10 = regs->r10;
	x->r11 = regs->r11;
	x->r12 = regs->r12;
	x->r13 = regs->r13;
	x->r14 = regs->r14;
	x->r15 = regs->r15;
	x->rip = regs->ip;
	x->rflags = regs->flags;
	x->trap_num = 0;
	x->error_code = 0;
	x->fault_addr = 0;
}

/* Copies the user's registers out without treating this as a system call. */
static void klet_regs_snapshot(struct klet_carrier *c, struct pt_regs *regs)
{
	klet_regs_to_ctx(c, regs);
	c->ctx->rax = regs->ax;
}

static void klet_ctx_set_exception(struct klet_carrier *c)
{
	struct klet_user_ctx *x = c->ctx;

	x->trap_num = c->exc_trap;
	x->error_code = c->exc_error;
	x->fault_addr = c->exc_addr;
}

/* ------------------------------------------------------------------ */
/* Virtual interrupts                                                 */
/* ------------------------------------------------------------------ */

/*
 * Raises a virtual interrupt on a vCPU.
 *
 * The ordering closes the window in which the kernelet is on its way out to user
 * mode: user_run marks the carrier KLET_USER *before* it looks at the pending
 * word, and this sets the pending word before it looks at the state, so at least
 * one of the two sees the other and the interrupt is never lost.
 *
 * Nor is the set_notify_resume(): the gate clears TIF_NOTIFY_RESUME *before* it
 * runs the resume hook, in the same pass of the exit loop, so a request made
 * while the hook runs, after its last look at the pending word, is still set
 * when the loop reads the flags again, and the loop runs the hook once more.
 * Cleared after the hook, it would be swallowed, and the carrier would enter
 * user mode with the interrupt pending until the next watch tick.
 */
void klet_virq_raise(struct klet_carrier *c, u32 bit)
{
	atomic_or(bit, &c->vrec.pending);
	smp_mb();

	/* The idle protocol's other half: set the bit, then look at the mark. */
	if (READ_ONCE(c->idle) && c->task)
		wake_up_process(c->task);

	if (READ_ONCE(c->state) == KLET_USER && c->task)
		set_notify_resume(c->task);
}

/* ------------------------------------------------------------------ */
/* Signals                                                            */
/* ------------------------------------------------------------------ */

/*
 * Whether a signal is Linux's report of a fault of the tenant's own making,
 * which the kernelet must see as the CPU exception it was. Those are the
 * synchronous fault signals with a fault's si_code (0 < si_code < SI_KERNEL),
 * and four of them with SI_KERNEL too, which is what x86's do_trap(),
 * do_general_protection() and the XFD path send through force_sig() when
 * there is no finer code (arch/x86/kernel/traps.c): SIGSEGV for #GP, #TS, #OF
 * (the `into` instruction is gone in 64-bit mode, but `int $4` reaches the
 * DPL-3 gate), #BR (from a compatibility code segment), and an #NM whose
 * extended feature (XFD) could not be enabled; SIGBUS for #NP and #SS;
 * SIGTRAP for #BP (int3); SIGFPE for #MF on the legacy coprocessor vector.
 * Every one but the XFD #NM records its vector in thread.trap_nr first; that
 * one does not (handle_xfd_event()), so it reaches the kernelet with whatever
 * trap number the tenant's last fault left behind. A process cannot forge
 * SI_KERNEL: kill() and sigqueue() send SI_USER or a negative code. SIGILL is
 * a fault only with a fault code. Everything else is not a trap, and
 * thread.trap_nr is stale for it: SIGXCPU from RLIMIT_CPU and the other
 * SI_KERNEL signals, and seccomp's SIGSYS (SYS_SECCOMP).
 */
static bool klet_is_fault_signal(int signr, int si_code)
{
	switch (signr) {
	case SIGSEGV:
	case SIGBUS:
	case SIGTRAP:
	case SIGFPE:
		if (si_code == SI_KERNEL)
			return true;
		fallthrough;
	case SIGILL:
		return si_code > 0 && si_code < SI_KERNEL;
	default:
		return false;
	}
}

/*
 * Drains the carrier's pending signals and turns the ones Linux raised for a
 * fault of the tenant's own making into a kernelet exception; every other
 * signal is dropped. SIGKILL is never drained, so that Linux kills the carrier
 * as it would any task. Nor is a vCPU carrier's SIGSTOP: Linux's own stop
 * handling applies to it on its way to user mode, as to any task, and a
 * stopped vCPU carrier is a stopped virtual CPU. The root carrier never
 * returns to user mode, so a stop could never take effect on it, and one left
 * pending would make every kernel_clone() of its vCPU carriers fail; it drops
 * SIGSTOP like any other signal.
 *
 * Returns true if an exception is now pending on the carrier.
 */
static bool klet_drain_signals(struct klet_carrier *c)
{
	kernel_siginfo_t info;
	enum pid_type type;
	sigset_t mask;
	bool exception = false;
	int signr;

	if (!signal_pending(current))
		return false;

	mask = current->blocked;
	sigaddset(&mask, SIGKILL);
	if (c->kind != KLET_ROOT)
		sigaddset(&mask, SIGSTOP);

	spin_lock_irq(&current->sighand->siglock);
	while ((signr = dequeue_signal(&mask, &info, &type)) != 0) {
		spin_unlock_irq(&current->sighand->siglock);

		if (klet_is_fault_signal(signr, info.si_code) && !exception) {
			c->exc_trap = current->thread.trap_nr;
			c->exc_error = current->thread.error_code;
			c->exc_addr = (unsigned long)info.si_addr;
			c->exc_pending = true;
			exception = true;
			pr_info("kernelet: signal %d (si_code %d) from pid %d is trap %llu -> exception\n",
				signr, info.si_code, current->pid, c->exc_trap);
		} else {
			pr_info("kernelet: signal %d (si_code %d) to pid %d dropped\n",
				signr, info.si_code, current->pid);
		}

		spin_lock_irq(&current->sighand->siglock);
	}
	spin_unlock_irq(&current->sighand->siglock);

	return exception;
}

/* ------------------------------------------------------------------ */
/* The root carrier                                                   */
/* ------------------------------------------------------------------ */

static int klet_carrier_main(void *arg);

static int klet_spawn_vcpu(struct klet_inst *inst, int vcpu)
{
	int tries;

	for (tries = 0; tries < 8; tries++) {
		struct kernel_clone_args args = {
			.flags = CLONE_UNTRACED,
			.exit_signal = SIGCHLD,
			.fn = klet_carrier_main,
			.fn_arg = (void *)(long)vcpu,
		};
		pid_t pid;

		/*
		 * copy_process() refuses to fork while a signal is pending, with
		 * -ERESTARTNOINTR, which only makes sense for a system call that
		 * can be restarted. The root carrier is not in a system call, so
		 * it drains its own signals first and retries.
		 */
		klet_drain_signals(klet_current_carrier());

		pid = kernel_clone(&args);
		if (pid >= 0)
			return 0;
		if (pid != -ERESTARTNOINTR)
			return pid;
		if (fatal_signal_pending(current))
			return -EINTR;
		pr_info("kernelet: clone deferred by a pending signal, retrying\n");
	}
	return -EAGAIN;
}

/*
 * The root carrier's whole job: bring up the sandbox's N vCPU carriers, then
 * stay alive so that its death is the sandbox's death.
 */
static void klet_root_loop(struct klet_carrier *root)
{
	struct klet_inst *inst = root->inst;
	unsigned int i;

	for (i = 0; i < inst->nr_vcpus; i++) {
		int err = klet_spawn_vcpu(inst, i);

		if (err) {
			pr_err("kernelet: cannot clone the carrier of vcpu %u: %d\n",
			       i, err);
			klet_stop_instance(inst, 1);
			klet_carrier_die(root);
			return;
		}
	}

	for (;;) {
		wait_event_interruptible(inst->root_wq,
					 inst->stopped || inst->dying ||
					 fatal_signal_pending(current));
		if (inst->stopped || inst->dying || fatal_signal_pending(current))
			break;
		klet_drain_signals(root);
	}

	klet_carrier_die(root);
}

/* The entry point of every vCPU carrier, via kernel_clone's .fn. */
static int klet_carrier_main(void *arg)
{
	int vcpu = (int)(long)arg;
	struct klet_inst *inst = &klet_inst;
	struct klet_carrier *c;
	int err;

	/*
	 * The clone copied the root carrier's gate pointer and syscall-work bit.
	 * This task is not a carrier until klet_carrier_attach() makes it one,
	 * and must not reach the root's record through them meanwhile, nor after
	 * a failure below, when the root's record may be gone.
	 */
	clear_syscall_work(KERNELET);
	current->kernelet = NULL;

	/*
	 * Drop the copy of the root carrier's lifeline that came with the fresh
	 * descriptor table, so that the root's death notice is the root's alone.
	 */
	if (inst->root_lifeline_fd >= 0)
		close_fd(inst->root_lifeline_fd);

	c = klet_carrier_new(inst, KLET_VCPU, vcpu);
	if (!c) {
		pr_err("kernelet: no memory for the carrier of vcpu %d\n", vcpu);
		klet_stop_instance(inst, 1);
		force_sig(SIGKILL);
		return 0;
	}
	pr_info("kernelet: vcpu %d carrier starting (pid %d)\n", vcpu, current->pid);

	err = klet_carrier_attach(c);
	if (err) {
		pr_err("kernelet: cannot attach a carrier: %d\n", err);
		klet_stop_instance(inst, 1);
		klet_carrier_lifeline_closed(c);
		force_sig(SIGKILL);
		return 0;
	}

	/* The carrier's own, empty address space, to fall back to. */
	if (current->mm) {
		mmget(current->mm);
		c->blank_mm = current->mm;
		c->cur_mm = current->mm;
	}

	spin_lock(&inst->lock);
	inst->vcpus[vcpu] = c;
	spin_unlock(&inst->lock);

	klet_sched_attach(c);

	/*
	 * vCPU 0 enters the image at kernelet_entry. The others wait until the
	 * kernel proper asks for them through the vcpu_boot service, which is
	 * where OSTD would have started an application processor.
	 */
	if (vcpu != 0) {
		/*
		 * Killable rather than interruptible: a SIGSTOP stays pending on a
		 * vCPU carrier until it goes to user mode, and must not cut this
		 * wait short. TASK_NOLOAD: waiting to be booted is not load on the
		 * host.
		 */
		wait_event_state(c->idle_wq,
				 c->boot_requested || inst->stopped ||
				 inst->dying || fatal_signal_pending(current),
				 (TASK_KILLABLE | TASK_NOLOAD));
		if (!c->boot_requested) {
			klet_carrier_die(c);
			return 0;
		}
	}

	klet_enter(c, KLET_RUN_EVENT);

	/*
	 * ret_from_fork() zeroes regs->ax after this function returns, so the
	 * registers cannot be applied here: ask for the resume hook, which runs
	 * after that, on the way out to user mode, to apply them.
	 */
	set_thread_flag(TIF_NOTIFY_RESUME);
	return 0;
}

static void klet_kill_carriers(struct klet_inst *inst)
{
	struct klet_carrier *c;

	klet_spaces_wake_all(inst);

	spin_lock(&inst->lock);
	list_for_each_entry(c, &inst->carriers, link) {
		if (c->task)
			send_sig(SIGKILL, c->task, 1);
		wake_up_all(&c->idle_wq);
	}
	spin_unlock(&inst->lock);

	wake_up_all(&inst->root_wq);
}

/* The kernelet asked to power off. */
void klet_stop_instance(struct klet_inst *inst, u64 code)
{
	bool first;

	/* Decided under the lock, as `dying` is (klet_kill_instance). */
	spin_lock(&inst->lock);
	first = !inst->stopped;
	if (first) {
		inst->exit_code = code;
		WRITE_ONCE(inst->stopped, true);
	}
	spin_unlock(&inst->lock);
	if (first)
		pr_info("kernelet: stopped, exit code %llu\n", code);
	klet_kill_carriers(inst);
}

/*
 * The sandbox is being destroyed from outside: one of its carriers has died, or
 * has been sent a fatal signal.
 *
 * Two carriers can get here at once. Only the setting of `dying` has to be
 * decided between them, so that the message is printed once: it is a
 * test-and-set under inst->lock. The rest may run twice: a second SIGKILL to a
 * carrier, a second wake-up and a second arming of the sweep change nothing.
 * `dying` and `stopped` are read without the lock everywhere else, and that is
 * enough: each only ever goes from false to true, and every reader that acts
 * on one either runs again later (a loop, the watch timer, the sweep) or is
 * woken by klet_kill_carriers(), which comes after the store.
 */
void klet_kill_instance(struct klet_inst *inst)
{
	bool first;

	spin_lock(&inst->lock);
	first = !inst->dying;
	WRITE_ONCE(inst->dying, true);
	spin_unlock(&inst->lock);
	if (first)
		pr_info("kernelet: a carrier is gone, the sandbox is dying; %d carrier(s) left\n",
			atomic_read(&inst->nr_carriers));
	klet_kill_carriers(inst);
	klet_evict_arm(inst);
}

/*
 * A fatal signal was found pending on this carrier on the Linux stack, in a
 * service: end the sandbox if it is still live, and mark the carrier, so that
 * the stub leaves the kernelet for good instead of returning into it. Linux
 * acts on SIGKILL only on the way to user mode, and a carrier asleep in
 * vcpu_idle, or running only kernel tasks, may never go there: without this, a
 * kill (an operator's, or the OOM killer's) would end nothing, and vcpu_idle,
 * which does not sleep with a fatal signal pending, would return at once into
 * an idle loop that calls it again, burning a host processor for the rest of
 * the sandbox's life.
 */
static void klet_carrier_doom(struct klet_carrier *c)
{
	struct klet_inst *inst = c->inst;

	if (c->doomed)
		return;
	c->doomed = true;
	if (READ_ONCE(inst->stopped) || READ_ONCE(inst->dying))
		return;
	c->killed_in = "a service";
	atomic_inc(&inst->kills_in_service);
	pr_info("kernelet: vcpu %d carrier (pid %d) has a fatal signal pending in a service\n",
		c->vcpu, current->pid);
	klet_kill_instance(inst);
}

/* ------------------------------------------------------------------ */
/* The gate                                                           */
/* ------------------------------------------------------------------ */

static bool klet_gate_syscall(struct pt_regs *regs)
{
	struct klet_carrier *c = klet_current_carrier();

	if (c->kind == KLET_ROOT || c->state != KLET_USER || !c->ctx)
		return false;

	if (regs->cs != __USER_CS || in_compat_syscall()) {
		/*
		 * Not a 64-bit entry. On the other host that instruction raises a
		 * general-protection fault, so report one.
		 */
		c->exc_trap = X86_TRAP_GP;
		c->exc_error = 0;
		c->exc_addr = 0;
		c->exc_pending = true;
		set_thread_flag(TIF_NOTIFY_RESUME);
		return true;
	}

	klet_regs_to_ctx(c, regs);
	c->user_live = false;
	regs->orig_ax = -1;

	klet_enter(c, KLET_RUN_SYSCALL);

	if (c->state == KLET_USER) {
		/*
		 * The kernelet may have activated another address space while it
		 * handled the call (a task switch, or a kernel proper running a
		 * second process's thread), and this path returns to user mode
		 * without passing the resume hook, so it adopts too. Without this the
		 * tenant would resume in the previous address space.
		 */
		if (klet_space_adopt(c, READ_ONCE(c->vrec.space))) {
			pr_err("kernelet: pid %d cannot adopt the address space %#llx\n",
			       current->pid, c->vrec.space);
			klet_stop_instance(c->inst, 1);
			klet_carrier_die(c);
			return true;
		}
		klet_ctx_to_regs(c, regs);
		c->user_live = true;
	}
	else
		klet_carrier_die(c);

	return true;
}

static void klet_gate_resume(struct pt_regs *regs)
{
	struct klet_carrier *c = klet_current_carrier();

	if (c->kind == KLET_ROOT) {
		klet_root_loop(c);
		return;
	}

	for (;;) {
		if (c->state == KLET_DEAD || c->inst->stopped || c->inst->dying) {
			klet_carrier_die(c);
			return;
		}

		if (c->state == KLET_NEW) {
			klet_enter(c, KLET_RUN_EVENT);
			continue;
		}

		/*
		 * A synchronous fault of the tenant's that Linux turned into a
		 * signal (an illegal instruction, say) arrives here, because this
		 * hook runs before arch_do_signal_or_restart().
		 */
		if (c->state == KLET_USER && c->ctx && !c->exc_pending) {
			if (klet_drain_signals(c) && c->user_live) {
				klet_regs_snapshot(c, regs);
				c->user_live = false;
			}
		}

		if (c->exc_pending) {
			c->exc_pending = false;
			/*
			 * An exception the fault handler recorded must be reported with
			 * the registers of the faulting instruction, which are in
			 * pt_regs now, not with the ones the carrier last entered user
			 * mode with (ctx): the kernel proper resumes the tenant at the
			 * faulting instruction, not at its last system call's return.
			 */
			if (c->state == KLET_USER && c->ctx && c->user_live) {
				klet_regs_snapshot(c, regs);
				c->user_live = false;
			}
			klet_ctx_set_exception(c);
			klet_enter(c, KLET_RUN_EXCEPTION);
			continue;
		}

		/*
		 * A virtual interrupt arrived while the carrier was on its way to
		 * user mode, or the watch timer set one in user mode. Let the
		 * kernelet take it: user_run returns 2 and vOSTD's execute loop
		 * runs its own pending-interrupt handler and might_preempt().
		 */
		if (atomic_read(&c->vrec.pending)) {
			/*
			 * The tenant was interrupted, so its registers are in pt_regs;
			 * without this snapshot the kernelet would send it back with the
			 * registers of its last system call, and a tenant in a long loop
			 * would restart it at every tick.
			 */
			if (c->state == KLET_USER && c->ctx && c->user_live) {
				klet_regs_snapshot(c, regs);
				c->user_live = false;
			}
			klet_enter(c, KLET_RUN_EVENT);
			continue;
		}

		/*
		 * Nothing for the kernelet, and the tenant's own registers are live
		 * in pt_regs: the exit loop is running this hook for work of Linux's
		 * own (a reschedule, a signal the drain dropped, a stop and continue,
		 * ...). Leave them alone, or the tenant would restart at its last
		 * system call's return. The carrier is in the right address space
		 * already: it went to user mode in it, and only this vCPU's kernelet
		 * code, which has not run since, could have activated another.
		 */
		if (c->state == KLET_USER && c->user_live)
			return;

		/*
		 * KLET_USER, with a context the kernelet has just handed over through
		 * user_run: the kernelet wants this carrier in user mode, in the
		 * address space its vCPU has activated.
		 */
		if (klet_space_adopt(c, READ_ONCE(c->vrec.space))) {
			pr_err("kernelet: pid %d cannot adopt the address space %#llx\n",
			       current->pid, c->vrec.space);
			klet_stop_instance(c->inst, 1);
			klet_carrier_die(c);
			return;
		}
		klet_ctx_to_regs(c, regs);
		c->user_live = true;
		return;
	}
}

const struct kernelet_gate_ops klet_gate_ops = {
	.syscall = klet_gate_syscall,
	.resume = klet_gate_resume,
};

/* ------------------------------------------------------------------ */
/* The service bodies, which all run on the carrier's Linux stack      */
/* ------------------------------------------------------------------ */

static void klet_do_log_write(struct klet_inst *inst, const char *ptr, u64 len)
{
	/* The measurement klet_svc_log_write made on the first call, if any. */
	if (inst->stub_cycles && !inst->stub_reported) {
		inst->stub_reported = true;
		pr_info("kernelet: service stub: %llu cycles through the stack switch, %llu for the service body alone (least of %d rounds of %d, rdtsc, interrupts off)\n",
			inst->stub_cycles, inst->body_cycles, KLET_MEASURE_ROUNDS,
			KLET_MEASURE_N);
	}
	printk(KERN_INFO "kernelet: %.*s\n", (int)len, ptr);
}

/*
 * kmalloc only promises natural alignment for power-of-two sizes, so the block
 * is over-allocated and the base pointer parked just below the aligned address.
 */
static void *klet_do_mem_alloc(u64 size, u64 align)
{
	void *base;
	unsigned long aligned;

	if (align < sizeof(void *))
		align = sizeof(void *);
	if (size == 0)
		size = 1;

	/* Charged to the memory cgroup of the calling carrier, the sandbox's. */
	base = kmalloc(size + align + sizeof(void *), GFP_KERNEL_ACCOUNT);
	if (!base)
		return NULL;

	aligned = ALIGN((unsigned long)base + sizeof(void *), align);
	((void **)aligned)[-1] = base;
	return (void *)aligned;
}

static void klet_do_mem_free(void *ptr)
{
	if (!ptr)
		return;
	kfree(((void **)ptr)[-1]);
}

static void klet_do_vcpu_boot(struct klet_inst *inst, u64 id)
{
	struct klet_carrier *target;

	if (id == 0 || id >= inst->nr_vcpus)
		return;

	spin_lock(&inst->lock);
	target = inst->vcpus[id];
	if (target)
		klet_carrier_get(target);
	spin_unlock(&inst->lock);
	if (!target)
		return;

	target->boot_requested = true;
	wake_up_all(&target->idle_wq);
	klet_carrier_put(target);
}

static void klet_do_vcpu_kick(struct klet_inst *inst, u64 id)
{
	struct klet_carrier *target;

	if (id >= inst->nr_vcpus)
		return;

	spin_lock(&inst->lock);
	target = inst->vcpus[id];
	if (target)
		klet_carrier_get(target);
	spin_unlock(&inst->lock);
	if (!target)
		return;

	/* Already asked: nothing to do, and no interrupt to send. */
	if (atomic_fetch_or(KLET_VIRQ_KICK, &target->vrec.pending) & KLET_VIRQ_KICK) {
		klet_carrier_put(target);
		return;
	}
	smp_mb();
	if (READ_ONCE(target->idle) && target->task)
		wake_up_process(target->task);
	if (READ_ONCE(target->state) == KLET_USER && target->task)
		set_notify_resume(target->task);
	/*
	 * If the target is running kernelet code right now, an inter-processor
	 * interrupt gets the upcall in within microseconds instead of waiting for
	 * that processor's next watch tick. This is the reschedule IPI.
	 */
	klet_kick_remote(target);
	klet_carrier_put(target);
}

/*
 * OSTD's idle. Sleeps until this vCPU has a pending virtual interrupt, the
 * deadline passes, or the sandbox is dying.
 *
 * The unconditional timeout is a safety net, not a mechanism: a kick that got
 * lost would otherwise cost liveness rather than latency.
 */
static void klet_do_vcpu_idle(struct klet_carrier *c, u64 deadline_ns)
{
	struct klet_inst *inst = c->inst;
	ktime_t timeout;
	u64 ns = deadline_ns;

	/*
	 * OSTD has only a periodic tick, so a vCPU with nothing to run sleeps to the
	 * next one unless the kernelet named a deadline of its own. Never for less
	 * than the floor: arming an hrtimer costs more than a very short sleep saves.
	 */
	if (!ns || ns > KLET_IDLE_MAX_NS)
		ns = KLET_IDLE_MAX_NS;
	if (ns < KLET_IDLE_MIN_NS)
		ns = KLET_IDLE_MIN_NS;
	timeout = ns_to_ktime(ns);

	/*
	 * The idle protocol, in this order: announce that we are going to sleep,
	 * mark ourselves idle, *then* look at the pending word. A raiser sets the bit
	 * and then looks at the mark, so one of the two always sees the other.
	 */
	/* TASK_NOLOAD: an idle virtual CPU is not load on the host. */
	set_current_state(TASK_KILLABLE | TASK_FREEZABLE | TASK_NOLOAD);
	WRITE_ONCE(c->idle, true);
	smp_mb();

	if (!atomic_read(&c->vrec.pending) && !inst->stopped && !inst->dying &&
	    !fatal_signal_pending(current))
		schedule_hrtimeout(&timeout, HRTIMER_MODE_REL);

	__set_current_state(TASK_RUNNING);
	WRITE_ONCE(c->idle, false);

	/*
	 * However the sleep ended, the kernelet's tick callbacks are owed a run: time
	 * has passed and its scheduler accounts by the clock, not by counting ticks.
	 */
	atomic_or(KLET_VIRQ_TICK, &c->vrec.pending);
}

/*
 * Gives the CPU back.
 *
 * Which of the two calls does the work depends on the preemption model, and with
 * CONFIG_PREEMPT_DYNAMIC that is a boot parameter:
 *
 *  - `preempt=none` and `preempt=voluntary` enable the cond_resched static call,
 *    so cond_resched() is __cond_resched() and reschedules.
 *  - `preempt=full` *disables* it (__static_call_return0), because Linux already
 *    preempts on the way out of the interrupt; cond_resched() then returns 0
 *    without doing anything, and the schedule() below is what yields.
 *  - Without CONFIG_PREEMPT_DYNAMIC and with CONFIG_PREEMPTION=y, cond_resched()
 *    compiles to a literal `return 0`, so again only the schedule() works.
 *
 * By the time this runs, the service prologue has already taken the kernelet's
 * mirrored depth off Linux's preemption count, so schedule() is legal here even
 * when the kernelet is deep inside a critical section. That is what makes the
 * forced yield possible.
 */
static void klet_do_yield(struct klet_carrier *c)
{
	if (c->forced) {
		c->forced = false;
		atomic_inc(&c->inst->forced_yields);
	} else {
		atomic_inc(&c->inst->yields);
	}
	if (!cond_resched() && need_resched())
		schedule();
}

/* ------------------------------------------------------------------ */
/* Floating-point state                                               */
/* ------------------------------------------------------------------ */

/*
 * The kernelet's FpuContext::save() and ::load() are XSAVE and XRSTOR on bare
 * metal. Here the registers may not be live at all — Linux defers loading a task's
 * floating-point state until it returns to user mode — so the two operations are
 * these two services, which make the registers live first and then do the same
 * instruction.
 *
 * Two rules, both because the buffer is the *kernelet's*:
 *
 *  - XSAVE never writes into it and XRSTOR never reads out of it. Everything goes
 *    through a per-carrier staging page, and the kernelet's bytes are copied in or
 *    out around that. XRSTOR reads a header and acts on it; letting it read memory
 *    another processor may be writing is not something to reason about.
 *  - The staged header is validated before XRSTOR sees it. Linux's own validator
 *    and its notion of the permitted feature set are private to its FPU code, so
 *    the endovisor carries its own.
 */

/* The header of the standard (non-compacted) XSAVE area. */
#define KLET_XSAVE_HDR_OFF	512
#define KLET_XSTATE_BV_OFF	(KLET_XSAVE_HDR_OFF + 0)
#define KLET_XCOMP_BV_OFF	(KLET_XSAVE_HDR_OFF + 8)
#define KLET_XSAVE_RSVD_OFF	(KLET_XSAVE_HDR_OFF + 16)
#define KLET_XSAVE_RSVD_LEN	48
#define KLET_MXCSR_OFF		24

/*
 * The features a tenant may restore: the legacy x87 and SSE state, AVX, and
 * AVX-512's opmask and upper halves — and only those of them the processor's XCR0
 * actually has. Deliberately *not* here:
 *
 *  - PKRU (bit 9), which Linux keeps out of its own user restore mask;
 *  - AMX and anything else behind XFD, because XRSTOR of a component whose
 *    XFD bit is armed raises #NM in kernel mode;
 *  - every supervisor state.
 */
#define KLET_XFEATURE_MASK_USER                                                \
	(BIT_ULL(0) | BIT_ULL(1) | BIT_ULL(2) | BIT_ULL(5) | BIT_ULL(6) |      \
	 BIT_ULL(7))

/* The MXCSR bits that exist. Anything else set makes XRSTOR raise #GP. */
#define KLET_MXCSR_MASK 0xffbfu

static u64 klet_xcr0(void)
{
	u32 lo, hi;

	asm volatile("xgetbv" : "=a"(lo), "=d"(hi) : "c"(0));
	return ((u64)hi << 32) | lo;
}

static u64 klet_allowed_features(void)
{
	return KLET_XFEATURE_MASK_USER & klet_xcr0();
}

/* True if the staged area is something XRSTOR may safely be given. */
static bool klet_fpu_validate(struct klet_carrier *c, void *stage, u64 len)
{
	u64 xstate_bv, xcomp_bv, allowed = klet_allowed_features();
	const u8 *rsvd;
	u32 *mxcsr;
	int i;

	if (len < KLET_XSAVE_HDR_OFF + 64)
		return false;

	xstate_bv = *(u64 *)((char *)stage + KLET_XSTATE_BV_OFF);
	xcomp_bv = *(u64 *)((char *)stage + KLET_XCOMP_BV_OFF);

	if (xstate_bv & ~allowed)
		goto bad;
	/* The standard format only. The compacted format's bit 63 must be clear. */
	if (xcomp_bv != 0)
		goto bad;

	rsvd = (const u8 *)stage + KLET_XSAVE_RSVD_OFF;
	for (i = 0; i < KLET_XSAVE_RSVD_LEN; i++)
		if (rsvd[i])
			goto bad;

	/* Sanitise rather than refuse: a stale MXCSR is a mistake, not an attack. */
	mxcsr = (u32 *)((char *)stage + KLET_MXCSR_OFF);
	*mxcsr &= KLET_MXCSR_MASK;

	return true;
bad:
	atomic_inc(&c->inst->fpu_rejects);
	pr_warn_once("kernelet: refusing an fpu_load: xstate_bv %#llx (allowed %#llx), xcomp_bv %#llx\n",
		     xstate_bv, allowed, xcomp_bv);
	return false;
}

static void klet_do_fpu_save(struct klet_carrier *c, void *area, u64 len)
{
	void *stage = c->fpu_stage;
	u64 mask = klet_allowed_features();

	if (!stage || !area || len < 512 || len > PAGE_SIZE)
		return;
	atomic_inc(&c->inst->fpu_swaps);

	memset(stage, 0, PAGE_SIZE);
	fpregs_lock();
	/*
	 * Make the registers live first, exactly as Linux's own
	 * fpregs_lock_and_load() does (which is not exported to modules).
	 */
	if (test_thread_flag(TIF_NEED_FPU_LOAD))
		switch_fpu_return();
	if (boot_cpu_has(X86_FEATURE_XSAVE))
		asm volatile("xsave64 %[s]"
			     : [s] "+m"(*(char *)stage)
			     : "a"((u32)mask), "d"((u32)(mask >> 32))
			     : "memory");
	else
		asm volatile("fxsave64 %[s]"
			     : [s] "+m"(*(char *)stage)
			     :
			     : "memory");
	fpregs_unlock();

	memcpy(area, stage, len);
}

static void klet_do_fpu_load(struct klet_carrier *c, const void *area, u64 len)
{
	void *stage = c->fpu_stage;
	u64 mask;

	if (!stage || !area || len < 512 || len > PAGE_SIZE)
		return;
	atomic_inc(&c->inst->fpu_swaps);

	memset(stage, 0, PAGE_SIZE);
	memcpy(stage, area, len);
	if (!klet_fpu_validate(c, stage, len))
		return;

	mask = *(u64 *)((char *)stage + KLET_XSTATE_BV_OFF) & klet_allowed_features();

	fpregs_lock();
	if (test_thread_flag(TIF_NEED_FPU_LOAD))
		switch_fpu_return();
	if (boot_cpu_has(X86_FEATURE_XSAVE))
		/*
		 * The fixup is belt and braces: the area has been validated and lives
		 * in the endovisor's own page, so XRSTOR should not fault. If it does,
		 * the tenant's floating-point state is whatever the fault left and the
		 * machine survives, which is the right trade for a #GP the endovisor
		 * did not foresee.
		 */
		asm volatile("1: xrstor64 %[s]\n"
			     "2:\n"
			     _ASM_EXTABLE(1b, 2b)
			     :
			     : [s] "m"(*(const char *)stage),
			       "a"((u32)mask), "d"((u32)(mask >> 32))
			     : "memory");
	else
		asm volatile("1: fxrstor64 %[s]\n"
			     "2:\n"
			     _ASM_EXTABLE(1b, 2b)
			     :
			     : [s] "m"(*(const char *)stage)
			     : "memory");
	fpregs_unlock();
}

/*
 * The prologue and epilogue that bracket every service, on the carrier's Linux
 * stack:
 *
 *  - while depth is above zero the carrier is inside the host, which is exactly
 *    when the watch timer and the eviction sweep must leave its instruction
 *    pointer alone;
 *  - the kernelet's mirrored preemption count comes off on the way in and goes
 *    back on the way out, so a service may sleep even if the kernelet called it
 *    under a guard.
 *
 * Coming back into kernelet code, the epilogue also makes sure this processor
 * is being watched. That is how the yield stub gets the watch re-armed after
 * its schedule(), possibly on a different CPU.
 */
static inline void klet_svc_prologue(struct klet_carrier *c)
{
	c->depth++;
	klet_mirror_out(c, false);
}

static inline void klet_svc_epilogue(struct klet_carrier *c)
{
	klet_watch_arm(c);
	klet_mirror_in(c);
	c->depth--;
}

/* The one function every service stub lands in, always on the Linux stack. */
void klet_svc_body(struct klet_svc_args *args)
{
	struct klet_carrier *c = klet_current_carrier();

	klet_svc_prologue(c);
	/* Counted for the tests: a memory service the kernelet called with its
	 * mirror raised, which the prologue has just lifted. */
	if (args->op >= KLET_SVC_VM_CREATE && c->excess > 0)
		atomic64_inc(&c->inst->mem_stats->lifted);

	switch (args->op) {
	case KLET_SVC_NOP:
		/*
		 * With a count, the measurement's second half: what the epilogue
		 * and prologue cost on their own, without the stack switch.
		 */
		if (args->a0) {
			u64 t0 = rdtsc_ordered(), i;

			for (i = 0; i < args->a0; i++) {
				klet_svc_epilogue(c);
				klet_svc_prologue(c);
			}
			args->ret = rdtsc_ordered() - t0;
		}
		break;
	case KLET_SVC_LOG_WRITE:
		klet_do_log_write(c->inst, (const char *)args->a0, args->a1);
		break;
	case KLET_SVC_MEM_ALLOC:
		args->ret = (u64)klet_do_mem_alloc(args->a0, args->a1);
		break;
	case KLET_SVC_MEM_FREE:
		klet_do_mem_free((void *)args->a0);
		break;
	case KLET_SVC_KSTACK_ALLOC:
		args->ret = klet_kstack_alloc(c->inst);
		break;
	case KLET_SVC_KSTACK_FREE:
		klet_kstack_put(c->inst, args->a0);
		break;
	case KLET_SVC_VCPU_BOOT:
		klet_do_vcpu_boot(c->inst, args->a0);
		break;
	case KLET_SVC_VCPU_KICK:
		klet_do_vcpu_kick(c->inst, args->a0);
		break;
	case KLET_SVC_VCPU_IDLE:
		klet_do_vcpu_idle(c, args->a0);
		break;
	case KLET_SVC_VCPU_YIELD:
		klet_do_yield(c);
		/* Eviction still wins: tell the stub not to resume. */
		args->ret = (c->inst->stopped || c->inst->dying ||
			     c->evicted) ? 1 : 0;
		break;
	case KLET_SVC_VCPU_ON_SPIN:
		klet_do_on_spin(c);
		break;
	case KLET_SVC_FPU_SAVE:
		klet_do_fpu_save(c, (void *)args->a0, args->a1);
		break;
	case KLET_SVC_FPU_LOAD:
		klet_do_fpu_load(c, (const void *)args->a0, args->a1);
		break;
	case KLET_SVC_STOP:
		klet_stop_instance(c->inst, args->a0);
		break;
	case KLET_SVC_VM_CREATE:
		args->ret = (u64)klet_do_vm_create(c);
		break;
	case KLET_SVC_VM_DESTROY:
		args->ret = (u64)klet_do_vm_destroy(c, args->a0);
		break;
	case KLET_SVC_VM_ACTIVATE:
		args->ret = (u64)klet_do_vm_activate(c, args->a0);
		break;
	case KLET_SVC_VM_MAP:
		args->ret = (u64)klet_do_vm_map(c, args->a0, args->a1, args->a2,
						(u32)args->a3);
		break;
	case KLET_SVC_VM_UNMAP:
		args->ret = (u64)klet_do_vm_unmap(c, args->a0, args->a1, args->a2);
		break;
	case KLET_SVC_VM_PROTECT:
		args->ret = (u64)klet_do_vm_protect(c, args->a0, args->a1,
						    (u32)args->a2);
		break;
	case KLET_SVC_VM_FLUSH:
		args->ret = (u64)klet_do_vm_flush(c, args->a0, args->a1, args->a2);
		break;
	case KLET_SVC_VM_WAIT:
		args->ret = (u64)klet_do_vm_wait(c, args->a0, (u32)args->a1, args->a2);
		break;
	case KLET_SVC_VM_WAKE:
		args->ret = (u64)klet_do_vm_wake(c, args->a0, (u32)args->a1);
		break;
	default:
		pr_err("kernelet: unknown service %llu\n", args->op);
		break;
	}

	/*
	 * Wherever the carrier was in the kernelet, a fatal signal ends it here,
	 * on the way back. Not for the empty service the measurement runs with
	 * interrupts off, where klet_kill_instance() may not run; the next real
	 * service catches it.
	 */
	if (unlikely(args->op != KLET_SVC_NOP && fatal_signal_pending(current)))
		klet_carrier_doom(c);

	klet_svc_epilogue(c);
}

/*
 * The stub proper, on the kernelet stack: find the carrier, pack the arguments,
 * and run the service body on the Linux stack. klet_svc_enter5 is the same for
 * the one service with more than three arguments.
 */
static u64 klet_svc_enter5(u64 op, u64 a0, u64 a1, u64 a2, u64 a3, u64 a4)
{
	struct klet_carrier *c = klet_current_carrier();
	struct klet_svc_args args = { .op = op, .a0 = a0, .a1 = a1, .a2 = a2,
				      .a3 = a3, .a4 = a4 };

	klet_run_on_linux_stack(c->linux_sp, &args);
	/* A fatal signal: abandon the coroutine (klet_carrier_doom). */
	if (unlikely(READ_ONCE(c->doomed)))
		for (;;)
			klet_leave(c, KLET_DEAD);
	return args.ret;
}

static u64 klet_svc_enter(u64 op, u64 a0, u64 a1, u64 a2)
{
	struct klet_carrier *c = klet_current_carrier();
	struct klet_svc_args args = { .op = op, .a0 = a0, .a1 = a1, .a2 = a2 };

	klet_run_on_linux_stack(c->linux_sp, &args);
	if (unlikely(READ_ONCE(c->doomed)))
		for (;;)
			klet_leave(c, KLET_DEAD);
	return args.ret;
}

/* ------------------------------------------------------------------ */
/* The service table                                                  */
/* ------------------------------------------------------------------ */

/*
 * What a service costs, measured once, on the first log line, with the
 * carrier's interrupts off: KLET_MEASURE_N empty services through the real
 * stub and stack switch, and then the same number of the empty body's
 * prologue and epilogue alone, run on the Linux stack. Only the loop and the
 * cycle counter run here on the kernelet stack; the result is printed by the
 * log service, on the Linux stack.
 *
 * Each half is timed KLET_MEASURE_ROUNDS times and the least round is kept:
 * interrupts off keep Linux out of a round, but not the hypervisor, which can
 * take the processor away in the middle of one, and a single round then
 * reports tens of cycles a call that were never spent on the call.
 */
static void klet_measure_switch(struct klet_carrier *c)
{
	struct klet_svc_args nop = { .op = KLET_SVC_NOP };
	struct klet_svc_args loop = { .op = KLET_SVC_NOP, .a0 = KLET_MEASURE_N };
	u64 viastub = ~0ULL, body = ~0ULL;
	unsigned long flags;
	int r, i;

	for (r = 0; r < KLET_MEASURE_ROUNDS; r++) {
		u64 t0, t;

		local_irq_save(flags);
		t0 = rdtsc_ordered();
		for (i = 0; i < KLET_MEASURE_N; i++)
			klet_run_on_linux_stack(c->linux_sp, &nop);
		t = rdtsc_ordered() - t0;
		klet_run_on_linux_stack(c->linux_sp, &loop);
		local_irq_restore(flags);

		viastub = min(viastub, t);
		body = min(body, loop.ret);
	}

	c->inst->body_cycles = body / KLET_MEASURE_N;
	c->inst->stub_cycles = viastub / KLET_MEASURE_N;
}

static void klet_svc_log_write(const char *ptr, u64 len)
{
	struct klet_carrier *c = klet_current_carrier();

	if (!c->inst->stub_cycles)
		klet_measure_switch(c);
	klet_svc_enter(KLET_SVC_LOG_WRITE, (u64)ptr, len, 0);
}

static void *klet_svc_mem_alloc(u64 size, u64 align)
{
	return (void *)klet_svc_enter(KLET_SVC_MEM_ALLOC, size, align, 0);
}

static void klet_svc_mem_free(void *ptr, u64 size, u64 align)
{
	klet_svc_enter(KLET_SVC_MEM_FREE, (u64)ptr, size, align);
}

static s64 klet_svc_vm_create(void)
{
	return (s64)klet_svc_enter(KLET_SVC_VM_CREATE, 0, 0, 0);
}

static s64 klet_svc_vm_destroy(u64 space)
{
	return (s64)klet_svc_enter(KLET_SVC_VM_DESTROY, space, 0, 0);
}

static s64 klet_svc_vm_activate(u64 space)
{
	return (s64)klet_svc_enter(KLET_SVC_VM_ACTIVATE, space, 0, 0);
}

static s64 klet_svc_vm_map(u64 space, u64 va, u64 paddr, u32 prot)
{
	return (s64)klet_svc_enter5(KLET_SVC_VM_MAP, space, va, paddr, prot, 0);
}

static s64 klet_svc_vm_unmap(u64 space, u64 va, u64 len)
{
	return (s64)klet_svc_enter(KLET_SVC_VM_UNMAP, space, va, len);
}

static s64 klet_svc_vm_protect(u64 space, u64 va, u32 prot)
{
	return (s64)klet_svc_enter(KLET_SVC_VM_PROTECT, space, va, prot);
}

static s64 klet_svc_vm_flush(u64 space, u64 va, u64 len)
{
	return (s64)klet_svc_enter(KLET_SVC_VM_FLUSH, space, va, len);
}

/*
 * A kill wakes the waiters, and the stub then leaves the kernelet for good
 * rather than returning into it: there is no "cancelled" error for vOSTD to
 * handle, because a kernelet that is being killed has nothing left to do. A
 * fatal signal to this carrier is caught by klet_svc_enter (klet_carrier_doom);
 * the test here also catches a sandbox that is stopping or dying because of
 * another carrier, which may wake this one before its own SIGKILL is sent.
 */
static s64 klet_svc_vm_wait(u64 space, u32 stripe, u64 expected)
{
	struct klet_carrier *c = klet_current_carrier();
	s64 ret = (s64)klet_svc_enter(KLET_SVC_VM_WAIT, space, stripe, expected);

	if (c->inst->stopped || c->inst->dying || c->evicted ||
	    fatal_signal_pending(current)) {
		for (;;)
			klet_leave(c, KLET_DEAD);
	}
	return ret;
}

static s64 klet_svc_vm_wake(u64 space, u32 stripe)
{
	return (s64)klet_svc_enter(KLET_SVC_VM_WAKE, space, stripe, 0);
}

static u64 klet_svc_kstack_alloc(void)
{
	return klet_svc_enter(KLET_SVC_KSTACK_ALLOC, 0, 0, 0);
}

static void klet_svc_kstack_free(u64 base)
{
	klet_svc_enter(KLET_SVC_KSTACK_FREE, base, 0, 0);
}

static void klet_svc_vcpu_boot(u64 id)
{
	klet_svc_enter(KLET_SVC_VCPU_BOOT, id, 0, 0);
}

static void klet_svc_vcpu_kick(u64 id)
{
	klet_svc_enter(KLET_SVC_VCPU_KICK, id, 0, 0);
}

static void klet_svc_vcpu_idle(u64 deadline_ns)
{
	klet_svc_enter(KLET_SVC_VCPU_IDLE, deadline_ns, 0, 0);
}

static void klet_svc_vcpu_yield(void)
{
	struct klet_carrier *c = klet_current_carrier();

	if (klet_svc_enter(KLET_SVC_VCPU_YIELD, 0, 0, 0)) {
		/* The sandbox died while we were away. Abandon the coroutine. */
		for (;;)
			klet_leave(c, KLET_DEAD);
	}
}

static void klet_svc_vcpu_on_spin(void)
{
	klet_svc_enter(KLET_SVC_VCPU_ON_SPIN, 0, 0, 0);
}

static void klet_svc_fpu_save(void *area, u64 len)
{
	klet_svc_enter(KLET_SVC_FPU_SAVE, (u64)area, len, 0);
}

static void klet_svc_fpu_load(const void *area, u64 len)
{
	klet_svc_enter(KLET_SVC_FPU_LOAD, (u64)area, len, 0);
}

/*
 * Leaves the kernelet stack by itself: no stub.
 *
 * The carrier is marked as leaving *before* the pending word is read, so that a
 * virtual interrupt raised in the window is either seen here or makes the raiser
 * flag the carrier. Either way it is not lost: a flag raised while the resume
 * hook is still running makes the exit loop run the hook again, because the gate
 * clears TIF_NOTIFY_RESUME before the hook, not after (klet_virq_raise).
 */
static u64 klet_svc_user_run(struct klet_user_ctx *ctx)
{
	struct klet_carrier *c = klet_current_carrier();

	c->ctx = ctx;
	WRITE_ONCE(c->state, KLET_USER);
	smp_mb();
	if (atomic_read(&c->vrec.pending)) {
		WRITE_ONCE(c->state, KLET_RUNNING);
		return KLET_RUN_EVENT;
	}

	klet_mirror_out(c, false);
	klet_switch(&c->coro_sp, c->linux_sp);
	return c->run_ret;
}

/*
 * The stopping itself goes through the stub like every other service; only the
 * final switch does not, because there is nothing to come back to.
 */
static void klet_svc_stop(u64 code)
{
	struct klet_carrier *c = klet_current_carrier();

	klet_svc_enter(KLET_SVC_STOP, code, 0, 0);

	/*
	 * The calling coroutine is abandoned: its stack is freed without
	 * unwinding, as the design says.
	 */
	for (;;)
		klet_leave(c, KLET_DEAD);
}

const struct klet_services klet_services = {
	.abi_version = KLET_ABI_VERSION,
	.log_write = klet_svc_log_write,
	.mem_alloc = klet_svc_mem_alloc,
	.mem_free = klet_svc_mem_free,
	.user_run = klet_svc_user_run,
	.vm_create = klet_svc_vm_create,
	.vm_destroy = klet_svc_vm_destroy,
	.vm_activate = klet_svc_vm_activate,
	.vm_map = klet_svc_vm_map,
	.vm_unmap = klet_svc_vm_unmap,
	.vm_protect = klet_svc_vm_protect,
	.vm_flush = klet_svc_vm_flush,
	.vm_wait = klet_svc_vm_wait,
	.vm_wake = klet_svc_vm_wake,
	.kstack_alloc = klet_svc_kstack_alloc,
	.kstack_free = klet_svc_kstack_free,
	.vcpu_boot = klet_svc_vcpu_boot,
	.vcpu_kick = klet_svc_vcpu_kick,
	.vcpu_idle = klet_svc_vcpu_idle,
	.vcpu_yield = klet_svc_vcpu_yield,
	.vcpu_on_spin = klet_svc_vcpu_on_spin,
	.fpu_save = klet_svc_fpu_save,
	.fpu_load = klet_svc_fpu_load,
	.stop = klet_svc_stop,
};
