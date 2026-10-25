// SPDX-License-Identifier: GPL-2.0
/*
 * Where the endovisor and Linux's scheduler meet.
 *
 * Three things live here:
 *
 * 1. **The counter the cooperative experiment needs.** A preempt notifier per vCPU
 *    carrier, so that the endovisor can count, exactly rather than by sampling,
 *    every time Linux switches a carrier out *involuntarily* while it was running
 *    kernelet code with a guard held. With the mirror on that count must be zero;
 *    with it off it is not. CONFIG_PREEMPT_NOTIFIERS is selected by the patch's
 *    Kconfig entry, which is the one line the patch grew for this.
 *
 * 2. **vcpu_on_spin.** A spin lock that has spun a thousand times may be waiting
 *    for a vCPU Linux has descheduled. yield_to() a sibling vCPU carrier that is
 *    runnable but not running, which is what a paravirtualised guest's
 *    `kvm_vcpu_on_spin` does for the same reason.
 *
 * 3. **The reschedule IPI.** A kick to a vCPU whose carrier is running right now
 *    on another processor does not want to wait for that processor's next watch
 *    tick, so it is an inter-processor interrupt whose handler makes that
 *    processor's watch timer fire at once, and the timer's callback redirects
 *    the interrupted kernelet code into the upcall stub.
 */

#include <linux/kernel.h>
#include <linux/kernelet.h>
#include <linux/preempt.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/smp.h>
#include <linux/jiffies.h>
#include <linux/ktime.h>

#include <asm/ptrace.h>

#include "kernelet.h"

/*
 * "Is this task on a processor right now?"
 *
 * task_curr() is not exported, so this reads the field it is built on.
 * task_struct::on_cpu exists under CONFIG_SMP and is set by the scheduler around
 * a context switch; a stale read only means the endovisor makes a slightly worse
 * choice, never an incorrect one.
 */
static inline bool klet_task_on_cpu(struct task_struct *t)
{
#ifdef CONFIG_SMP
	return READ_ONCE(t->on_cpu) != 0;
#else
	return t == current;
#endif
}

/* ------------------------------------------------------------------ */
/* Counting involuntary switch-outs from a critical section            */
/* ------------------------------------------------------------------ */

#ifdef CONFIG_PREEMPT_NOTIFIERS

static bool klet_notifiers_up;

/*
 * A carrier arrives on a processor here however it arrived — woken, migrated, or resumed after Linux
 * preempted it *inside* kernelet code, which passes through no way in of the
 * endovisor's at all. This is where the processor's watch timer gets armed, and
 * where the time the host kept the vCPU off a processor is charged.
 */
static void klet_sched_in(struct preempt_notifier *pn, int cpu)
{
	struct klet_carrier *c = container_of(pn, struct klet_carrier, pnotifier);

	(void)cpu;

	if (c->off_cpu_ns) {
		u64 now = ktime_get_mono_fast_ns();

		if (now > c->off_cpu_ns) {
			u64 stolen = now - c->off_cpu_ns;

			c->vrec.stolen_ns += stolen;
			atomic_add((int)(stolen / NSEC_PER_MSEC), &c->inst->n.stolen_ms);
		}
		c->off_cpu_ns = 0;
	}

	klet_watch_arm(c);
}

static void klet_sched_out(struct preempt_notifier *pn, struct task_struct *next)
{
	struct klet_carrier *c = container_of(pn, struct klet_carrier, pnotifier);

	(void)next;

	/* Not running kernelet code: a service, user mode, or already dead. */
	if (READ_ONCE(c->state) != KLET_RUNNING || READ_ONCE(c->depth) != 0)
		return;
	/*
	 * Was Linux's count really the kernelet's at this instant? The guard count
	 * alone would over-count: the kernelet drops the mirror a couple of
	 * instructions before it drops its last guard, and a deschedule in that
	 * window is the host's right, not a failure.
	 */
	if (!klet_mirrored(c))
		return;
	/*
	 * Going to sleep rather than being preempted. A carrier that blocks does
	 * so in a service, so this should not happen at depth 0, but the state is
	 * what distinguishes voluntary from involuntary and it costs one load.
	 */
	if (READ_ONCE(current->__state) != TASK_RUNNING)
		return;

	atomic_inc(&c->inst->n.bad_preempt);
}

static void klet_sched_out_common(struct preempt_notifier *pn)
{
	struct klet_carrier *c = container_of(pn, struct klet_carrier, pnotifier);

	/*
	 * Off the processor, the carrier has given it back, so a first strike
	 * the watch timer took on it is over. Otherwise the two-tick bound would
	 * be measured across the time it spent descheduled, and across whatever
	 * critical section it is in when it comes back.
	 */
	c->strike1_ns = 0;

	/* Only time spent off a processor *while running kernelet code* is stolen. */
	if (klet_in_kernelet(c))
		c->off_cpu_ns = ktime_get_mono_fast_ns();
	else
		c->off_cpu_ns = 0;
}

static void klet_sched_out_hook(struct preempt_notifier *pn,
				struct task_struct *next)
{
	klet_sched_out(pn, next);
	klet_sched_out_common(pn);
}

static struct preempt_ops klet_preempt_ops = {
	.sched_in = klet_sched_in,
	.sched_out = klet_sched_out_hook,
};

int klet_sched_init(void)
{
	preempt_notifier_inc();
	klet_notifiers_up = true;
	return 0;
}

void klet_sched_exit(void)
{
	if (klet_notifiers_up) {
		klet_notifiers_up = false;
		preempt_notifier_dec();
	}
}

void klet_sched_attach(struct klet_carrier *c)
{
	if (!klet_notifiers_up || c->pnotifier_on)
		return;
	preempt_notifier_init(&c->pnotifier, &klet_preempt_ops);
	preempt_notifier_register(&c->pnotifier);
	c->pnotifier_on = true;
}

void klet_sched_detach(struct klet_carrier *c)
{
	if (!c->pnotifier_on)
		return;
	c->pnotifier_on = false;
	preempt_notifier_unregister(&c->pnotifier);
}

#else /* !CONFIG_PREEMPT_NOTIFIERS */

int klet_sched_init(void)
{
	pr_warn("kernelet: no CONFIG_PREEMPT_NOTIFIERS: involuntary preemptions of a critical section cannot be counted\n");
	return 0;
}
void klet_sched_exit(void) { }
void klet_sched_attach(struct klet_carrier *c) { (void)c; }
void klet_sched_detach(struct klet_carrier *c) { (void)c; }

#endif /* CONFIG_PREEMPT_NOTIFIERS */

/* ------------------------------------------------------------------ */
/* vcpu_on_spin                                                       */
/* ------------------------------------------------------------------ */

/*
 * The kernelet has been spinning on a lock. If a sibling vCPU's carrier is
 * runnable but not running, the lock's holder is probably it, so give it the
 * processor.
 */
void klet_do_on_spin(struct klet_carrier *c)
{
	struct klet_inst *inst = c->inst;
	unsigned int i;

	/*
	 * At most once per tick per vCPU. A spin lock that is merely contended calls
	 * this often, and handing the processor away every time would turn a fast
	 * lock into a slow one.
	 */
	if (c->last_on_spin == jiffies)
		return;
	c->last_on_spin = jiffies;

	atomic_inc(&inst->n.on_spins);

	for (i = 0; i < inst->nr_vcpus; i++) {
		struct klet_carrier *o;
		struct task_struct *t;

		spin_lock(&inst->lock);
		o = inst->vcpus[i];
		if (o && o != c)
			klet_carrier_get(o);
		else
			o = NULL;
		spin_unlock(&inst->lock);
		if (!o)
			continue;

		t = o->task;
		if (t && task_is_running(t) && !klet_task_on_cpu(t)) {
			/*
			 * yield_to() may refuse: -ESRCH for a task that is not on a
			 * runqueue, 0 when the target's class has nothing to offer
			 * (NEXT_BUDDY is off by default, a throttled hierarchy
			 * declines). Any of those is fine; fall through to the plain
			 * yield below.
			 */
			int r = yield_to(t, false);

			if (r > 0) {
				atomic_inc(&inst->n.yield_tos);
				klet_carrier_put(o);
				return;
			}
			klet_carrier_put(o);
			break;
		}
		klet_carrier_put(o);
	}

	/*
	 * Nothing to hand the processor to. Give it back anyway rather than spin
	 * the sandbox's share away: the holder may be on another processor
	 * entirely, in which case this costs one reschedule and nothing else.
	 */
	cond_resched();
}

/* ------------------------------------------------------------------ */
/* The reschedule IPI                                                 */
/* ------------------------------------------------------------------ */

/*
 * Runs in hard interrupt context on the processor the target carrier is on.
 * The handler of this vector is not given the interrupted registers
 * (get_irq_regs() is NULL here: smp_call_function_single()'s vector never
 * calls set_irq_regs()), so it cannot redirect the interrupted kernelet code
 * itself. It makes the processor's watch timer fire at once instead, and the
 * timer's callback, which is given the registers, delivers the KICK the caller
 * has already raised: into the upcall stub if the kernelet can take it, and
 * otherwise at its next guard drop or unmask, as for any pending interrupt.
 */
static void klet_kick_ipi(void *arg)
{
	struct klet_carrier *c = arg;

	if (!current->carrier_hooks || current->carrier_hooks != &c->hooks)
		return;
	atomic_inc(&c->inst->n.kick_ipis);
	klet_watch_fire_now();
}

void klet_kick_remote(struct klet_carrier *c)
{
	struct task_struct *t = c->task;
	int cpu;

	if (!t)
		return;
	if (READ_ONCE(c->state) != KLET_RUNNING || READ_ONCE(c->depth) != 0)
		return;
	if (!klet_task_on_cpu(t))
		return;

	/*
	 * A service runs preemptible, so the processor this one is on may change
	 * under the test; raw_smp_processor_id() says so, and a stale answer is
	 * harmless either way. If the caller has moved onto the target's
	 * processor, smp_call_function_single() runs the handler right here, and
	 * it finds the caller, not the target, in `current` and does nothing;
	 * if it has moved off it, the target may go one tick without a kick, as
	 * when it moves itself. The KICK bit is set already, and the next watch
	 * tick or guard drop delivers it.
	 */
	cpu = task_cpu(t);
	if (cpu == raw_smp_processor_id())
		return;

	/*
	 * Fire and forget: if the carrier moved or stopped running kernelet code
	 * in the meantime, the handler simply finds nothing to do.
	 */
	smp_call_function_single(cpu, klet_kick_ipi, c, 0);
}
