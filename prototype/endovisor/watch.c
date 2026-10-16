// SPDX-License-Identifier: GPL-2.0
/*
 * The per-processor watch timer: this sandbox's timer interrupt, the delivery
 * point for its virtual interrupts, and the bound on how long the kernelet may
 * keep a processor it has said it is not ready to give up.
 *
 * One HRTIMER_MODE_REL_PINNED_HARD timer per CPU, in per-cpu data. The rule is as
 * simple as it can be: **a CPU's watch timer runs exactly while `current` there is
 * a vCPU carrier**, whatever that carrier is doing — kernelet code, a host
 * service, user mode. The callback keeps itself alive iff that is still true, so a
 * carrier that migrates leaves no stale timer behind on the CPU it came from, and
 * the CPU it lands on arms its own from the carrier's preempt notifier.
 *
 * The preempt notifier is what makes this rule enough. A carrier that Linux
 * preempts *inside* kernelet code at preempt_count zero resumes at the
 * interrupted instruction, possibly on another CPU, without passing through any
 * of the endovisor's ways into the kernelet; arming the timer only on those ways
 * in would leave such a carrier unwatched. The notifier's sched_in runs however
 * the carrier came to be on a processor, so no per-cpu record of "the carrier
 * being watched" is needed at all.
 *
 * Every tick does three things, in this order:
 *
 * 1. **The tick.** Raise TICK on the carrier's vCPU. That is the kernelet's timer
 *    interrupt, and it drives its scheduler's `update_current(Tick)`.
 *
 * 2. **Delivery.** Decide where the kernelet can take it:
 *    - in user mode: klet_virq_raise has already flagged the carrier, and the
 *      resume hook re-enters the kernelet with `user_run` returning 2;
 *    - in kernelet text with its virtual interrupts unmasked, at depth 0, with
 *      room left on the current task's stack: store the interrupted instruction
 *      pointer in the vCPU record, set the record's `irq_off` as hardware clears
 *      IF, and point regs->ip at the image's own `virq_entry`. The interrupt's own
 *      iret does the rest. Note that a *preemption guard* does not stop this: on
 *      bare metal it would not stop an interrupt either;
 *    - masked, or too little stack, or in a service, or in Linux's own code: leave
 *      it pending. vOSTD delivers it itself when it unmasks.
 *
 * 3. **The bound (two strikes).** If the tick found the carrier in kernelet text in
 *    a critical section *and* Linux wanting the processor, note when. At the first
 *    tick at least a millisecond later, preempt it anyway: redirect into the yield
 *    stub with `forced` set, which reschedules on the carrier's Linux stack with
 *    the mirrored count taken off, and comes back to the interrupted instruction.
 *    The grace is at most two ticks, and the borrowed time is charged to the
 *    sandbox's control group by Linux like any other.
 */

#include <linux/hrtimer.h>
#include <linux/kernel.h>
#include <linux/kernelet.h>
#include <linux/moduleparam.h>
#include <linux/percpu.h>
#include <linux/sched.h>
#include <linux/smp.h>

#include <asm/irq_regs.h>
#include <asm/ptrace.h>

#include "kernelet.h"

/*
 * The watch can be turned off, which is how a test shows what happens without it:
 * `insmod kernelet.ko klet_watch=0`.
 */
bool klet_watch = true;
module_param(klet_watch, bool, 0444);
MODULE_PARM_DESC(klet_watch,
		 "tick each processor, deliver virtual interrupts and bound how long kernelet code may keep it (default on)");

static DEFINE_PER_CPU(struct hrtimer, klet_watch_timer);
static bool klet_watch_ready;

/*
 * Points the interrupted instruction pointer at the image's virtual-interrupt
 * stub, if the kernelet can take an interrupt right now. Returns true if it did.
 *
 * `irq_off` is set here rather than by the stub, so that a second redirect cannot
 * happen before the stub has taken the interrupted instruction pointer onto the
 * task's stack. That is exactly what hardware does to IF, and the stub clears it at
 * the end, as `iret` would.
 */
bool klet_virq_redirect(struct klet_carrier *c, struct pt_regs *regs)
{
	u64 limit;

	if (user_mode(regs) || !klet_in_image_text(regs->ip))
		return false;
	if (!klet_in_kernelet(c))
		return false;
	if (klet_irq_off(c))
		return false;

	/*
	 * The upcall is pushed onto whichever kernelet stack the current OSTD task
	 * is on, which vOSTD publishes. Leave Linux its own reserve on that stack —
	 * a hard interrupt can land there too — plus room for the upcall itself.
	 */
	limit = READ_ONCE(c->vrec.stack_limit);
	if (!limit || regs->sp < limit ||
	    regs->sp - limit < KLET_UPCALL_HEADROOM)
		return false;

	WRITE_ONCE(c->vrec.virq_ip, regs->ip);
	/* Order: mask first, then divert, so the stub always sees it masked. */
	WRITE_ONCE(c->vrec.irq_off, 1);
	regs->ip = (unsigned long)kernelet_entry_table.virq_entry;
	atomic_inc(&c->inst->virqs);
	return true;
}

static enum hrtimer_restart klet_watch_fn(struct hrtimer *timer)
{
	struct klet_inst *inst = &klet_inst;
	struct pt_regs *regs = get_irq_regs();
	struct klet_carrier *c;
	u64 now;

	atomic_inc(&inst->ticks);

	/*
	 * The timer lives exactly as long as this processor is running a carrier of
	 * a live sandbox. Nothing else has to be tracked.
	 */
	if (!current->kernelet)
		return HRTIMER_NORESTART;
	c = klet_current_carrier();
	if (c->kind == KLET_ROOT || c->inst != inst || c->state == KLET_DEAD ||
	    inst->dying || inst->stopped)
		return HRTIMER_NORESTART;

	/* 1. The tick: this sandbox's timer interrupt. */
	klet_virq_raise(c, KLET_VIRQ_TICK);

	if (!regs)
		goto again;

	/* 2. Delivery, and 3. the bound. */
	if (user_mode(regs) || !klet_in_image_text(regs->ip) ||
	    !klet_in_kernelet(c)) {
		/* User mode, a service, or Linux's own code. Leave it pending. */
		c->strike1_ns = 0;
		goto again;
	}

	if (!klet_critical(c)) {
		c->strike1_ns = 0;
		if (klet_virq_redirect(c, regs))
			goto again;
		/*
		 * The kernelet could not take the interrupt — no room on its stack.
		 * If Linux wants the processor anyway, yield it through the yield
		 * stub: kernelet code has no voluntary preemption point of its own.
		 */
		if (need_resched()) {
			c->yield_ip = regs->ip;
			c->forced = false;
			regs->ip = (unsigned long)klet_yield_stub;
		}
		goto again;
	}

	/*
	 * A critical section. The interrupt stays pending and vOSTD delivers it when
	 * it unmasks. But if Linux wants the processor, the grace is bounded.
	 */
	if (!need_resched()) {
		c->strike1_ns = 0;
		goto again;
	}

	now = ktime_get_mono_fast_ns();
	atomic_inc(&inst->deferrals);
	if (!c->strike1_ns) {
		c->strike1_ns = now;
		goto again;
	}

	{
		u32 held_us = (u32)((now - c->strike1_ns) / 1000);

		if (held_us > (u32)atomic_read(&inst->longest_defer_us))
			atomic_set(&inst->longest_defer_us, held_us);
	}
	if (now - c->strike1_ns < NSEC_PER_MSEC)
		goto again;	/* strike one was less than a tick ago */
	c->strike1_ns = 0;
	c->yield_ip = regs->ip;
	c->forced = true;
	regs->ip = (unsigned long)klet_yield_stub;
	if (atomic_read(&inst->forced_yields) < 3)
		pr_info("kernelet: forced yield of vcpu %d (pid %d) on cpu %d at ip %#lx (%pS), guards %u, irq_off %u\n",
			c->vcpu, current->pid, smp_processor_id(), c->yield_ip,
			(void *)c->yield_ip, klet_guards(c), klet_irq_off(c));

again:
	hrtimer_forward_now(timer, ns_to_ktime(KLET_WATCH_INTERVAL_NS));
	return HRTIMER_RESTART;
}

/*
 * Arms this processor's watch timer if it is not already running. Called when a
 * carrier starts and from its preempt notifier's sched_in, which together cover
 * every way a carrier can come to be on a processor: a wake-up, a migration, and
 * resuming after Linux preempted it inside kernelet code.
 */
void klet_watch_arm(struct klet_carrier *c)
{
	struct hrtimer *timer;

	if (!klet_watch || !klet_watch_ready || c->kind == KLET_ROOT)
		return;

	timer = this_cpu_ptr(&klet_watch_timer);
	if (!hrtimer_active(timer))
		hrtimer_start(timer, ns_to_ktime(KLET_WATCH_INTERVAL_NS),
			      HRTIMER_MODE_REL_PINNED_HARD);
}

int klet_watch_init(void)
{
	int cpu;

	for_each_possible_cpu(cpu) {
		struct hrtimer *timer = per_cpu_ptr(&klet_watch_timer, cpu);

		hrtimer_init(timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL_HARD);
		timer->function = klet_watch_fn;
	}
	klet_watch_ready = true;
	return 0;
}

/*
 * hrtimer_cancel() waits for a running callback, so after this no callback is
 * running or will start, which is what makes it safe for the module's text to go
 * away next.
 */
void klet_watch_exit(void)
{
	int cpu;

	klet_watch_ready = false;
	for_each_possible_cpu(cpu)
		hrtimer_cancel(per_cpu_ptr(&klet_watch_timer, cpu));
}
