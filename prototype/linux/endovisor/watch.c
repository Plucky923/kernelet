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
 *      iret does the rest. This is done only outside a critical section, which
 *      is a preemption guard held *or* interrupts masked (klet_critical): the
 *      upcall may switch tasks, which a guard forbids;
 *    - in a critical section, or with too little stack, or in a service, or in
 *      Linux's own code: leave it pending. vOSTD delivers it itself when it
 *      unmasks or drops its last guard.
 *
 * 3. **The bound (two strikes).** If the tick found the carrier in kernelet text in
 *    a critical section *and* Linux wanting the processor, note when (the note is
 *    dropped when the carrier leaves the processor, sched.c). At the first tick
 *    at least a millisecond later, preempt it anyway: redirect into the yield
 *    stub with `forced` set, which reschedules on the carrier's Linux stack with
 *    the mirrored count taken off, and comes back to the interrupted instruction.
 *    The grace is at most two ticks, and the borrowed time is charged to the
 *    sandbox's control group by Linux like any other.
 *
 * The timer also fires on request. A kick of a vCPU whose carrier is running
 * kernelet code on another processor is an inter-processor interrupt, and the
 * handler of the vector smp_call_function_single() uses is not given the
 * interrupted registers (it never calls set_irq_regs()), so it cannot redirect
 * anything itself. What it can do is make this timer expire at once:
 * klet_watch_fire_now(). The callback, which does see the registers, then
 * performs step 2 for the KICK the kicker has already raised. Such a firing is
 * not a tick: it raises no TICK, takes no strike, counts no deferral, and puts
 * the timer back on the expiry of the period it interrupted, so a kick neither
 * advances the kernelet's clock nor delays its next tick.
 */

#include <linux/hrtimer.h>
#include <linux/kernel.h>
#include <linux/kernelet.h>
#include <linux/moduleparam.h>
#include <linux/percpu.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
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
 * Set by klet_watch_fire_now() and cleared by the callback: the next firing on
 * this processor was requested, and `klet_watch_period_end` is the expiry of
 * the period that the request cut short.
 */
static DEFINE_PER_CPU(bool, klet_watch_requested);
static DEFINE_PER_CPU(ktime_t, klet_watch_period_end);

/*
 * When this processor's timer last ticked while it kept running, 0 when it was
 * (re)started: the longest gap between two ticks of a running timer is how late
 * Linux, or the machine beneath it, delivered one.
 */
static DEFINE_PER_CPU(u64, klet_watch_last_tick);

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
	bool tick = true;
	u64 now;

	/*
	 * A requested firing is a tick as well only if the period it cut short
	 * has run out in the meantime.
	 */
	if (this_cpu_read(klet_watch_requested)) {
		this_cpu_write(klet_watch_requested, false);
		atomic_inc(&inst->watch_fires);
		if (ktime_before(hrtimer_cb_get_time(timer),
				 this_cpu_read(klet_watch_period_end)))
			tick = false;
	}
	if (tick) {
		u64 t = ktime_get_mono_fast_ns(), last = this_cpu_read(klet_watch_last_tick);

		atomic_inc(&inst->ticks);
		if (last && t > last) {
			u32 gap_us = (u32)((t - last) / 1000);

			if (gap_us > (u32)atomic_read(&inst->longest_tick_gap_us))
				atomic_set(&inst->longest_tick_gap_us, gap_us);
		}
		this_cpu_write(klet_watch_last_tick, t);
	}

	/*
	 * The timer lives exactly as long as this processor is running a carrier of
	 * a live sandbox. Nothing else has to be tracked.
	 */
	if (!current->carrier_hooks) {
		this_cpu_write(klet_watch_last_tick, 0);
		return HRTIMER_NORESTART;
	}
	c = klet_current_carrier();
	if (c->kind == KLET_ROOT || c->inst != inst || c->state == KLET_DEAD ||
	    inst->dying || inst->stopped) {
		this_cpu_write(klet_watch_last_tick, 0);
		return HRTIMER_NORESTART;
	}

	/*
	 * 0. A fatal signal to a carrier that is running kernelet code. Linux acts
	 * on it only on the way to user mode, and kernelet code that calls no
	 * service never goes there: evict the carrier, as the sweep does, which
	 * sends it back to its Linux stack to die, and its death ends the sandbox
	 * (klet_carrier_lifeline_closed). Whatever the kernelet held, guards
	 * included, is abandoned with it, as on any eviction. A carrier asleep or
	 * in a service is left to klet_svc_body, one in user mode to Linux.
	 */
	if (regs && !user_mode(regs) && klet_in_image_text(regs->ip) &&
	    klet_in_kernelet(c) && fatal_signal_pending(current)) {
		c->evicted = true;
		c->doomed = true;
		c->killed_in = "kernelet code";
		atomic_inc(&inst->kills_in_kernelet);
		regs->ip = (unsigned long)klet_exit_stub;
		this_cpu_write(klet_watch_last_tick, 0);
		return HRTIMER_NORESTART;
	}

	/* 1. The tick: this sandbox's timer interrupt. */
	if (tick)
		klet_virq_raise(c, KLET_VIRQ_TICK);

	if (!regs)
		goto again;

	/* 2. Delivery, and 3. the bound. */
	if (user_mode(regs) || !klet_in_image_text(regs->ip) ||
	    !klet_in_kernelet(c)) {
		/* User mode, a service, or Linux's own code. Leave it pending. */
		c->strike1_ns = 0;
		if (!tick)
			atomic_inc(&inst->fires_elsewhere);
		goto again;
	}

	if (!klet_critical(c)) {
		c->strike1_ns = 0;
		if (klet_virq_redirect(c, regs)) {
			if (!tick)
				atomic_inc(&inst->fires_redirected);
			goto again;
		}
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
	 * it unmasks. But if Linux wants the processor, the grace is bounded; the
	 * bound is the ticks', so a requested firing leaves it alone.
	 */
	if (!tick) {
		atomic_inc(&inst->fires_masked);
		goto again;
	}
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
	/*
	 * The first few are recorded for the log, and printed when the module is
	 * unloaded, not here: a printk from this hard-interrupt callback to a
	 * serial console keeps interrupts off for milliseconds, which holds this
	 * processor's next tick back and lengthens the very deferrals the bound
	 * is about.
	 */
	{
		int i = atomic_inc_return(&inst->forced_recorded) - 1;

		if (i < KLET_FORCED_RECORDS)
			inst->forced_rec[i] = (struct klet_forced_rec) {
				.vcpu = c->vcpu, .pid = current->pid,
				.cpu = smp_processor_id(), .ip = c->yield_ip,
				.guards = klet_guards(c), .irq_off = klet_irq_off(c),
			};
	}

again:
	if (!tick) {
		/* Back to the period the request cut short. */
		hrtimer_set_expires(timer, this_cpu_read(klet_watch_period_end));
		return HRTIMER_RESTART;
	}
	hrtimer_forward_now(timer, ns_to_ktime(KLET_WATCH_INTERVAL_NS));
	return HRTIMER_RESTART;
}

/*
 * Makes this processor's watch timer expire now, for a kick. Called in hard
 * interrupt context on this processor (the kick's IPI handler), where
 * hrtimer_start() of an active timer is legal: the timer is pinned here, and
 * its callback cannot be running, because it too runs in hard interrupt
 * context on this processor. A request already outstanding is enough.
 */
void klet_watch_fire_now(void)
{
	struct hrtimer *timer = this_cpu_ptr(&klet_watch_timer);
	ktime_t end;

	if (!klet_watch || !klet_watch_ready || this_cpu_read(klet_watch_requested))
		return;

	if (hrtimer_active(timer))
		end = hrtimer_get_expires(timer);
	else
		end = ktime_add_ns(ktime_get(), KLET_WATCH_INTERVAL_NS);
	this_cpu_write(klet_watch_period_end, end);
	this_cpu_write(klet_watch_requested, true);
	hrtimer_start(timer, 0, HRTIMER_MODE_REL_PINNED_HARD);
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
	if (!hrtimer_active(timer)) {
		this_cpu_write(klet_watch_last_tick, 0);
		hrtimer_start(timer, ns_to_ktime(KLET_WATCH_INTERVAL_NS),
			      HRTIMER_MODE_REL_PINNED_HARD);
	}
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
