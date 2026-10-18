// SPDX-License-Identifier: GPL-2.0
/*
 * Eviction: taking a CPU back from kernelet code that will not give it up.
 *
 * The design's assumption is that the endovisor can always evict a kernelet from
 * a CPU, because kernelet code runs with interrupts enabled, on its own stack,
 * and the endovisor knows the bounds of the kernelet's text. So: arm a hard
 * hrtimer on the CPU the carrier is on, and in the callback look at the
 * registers the interrupt saved. If they are kernel-mode registers whose
 * instruction pointer is inside the kernelet image's text, and the interrupted
 * task is a carrier of a dying kernelet that is not inside a host service, then
 * point the instruction pointer at an exit stub and change nothing else. The
 * interrupt's own iret does the rest.
 *
 * One hrtimer per CPU, because CONFIG_PREEMPT means the carrier may be scheduled
 * away and back between sweeps, possibly on another CPU; the sweep re-arms
 * itself every millisecond until no carrier is left.
 */

#include <linux/hrtimer.h>
#include <asm/irq_regs.h>
#include <linux/kernel.h>
#include <linux/kernelet.h>
#include <linux/percpu.h>
#include <linux/sched.h>
#include <linux/smp.h>

#include <asm/ptrace.h>

#include "kernelet.h"

static DEFINE_PER_CPU(struct hrtimer, klet_sweep_timer);
static bool klet_sweep_ready;

static enum hrtimer_restart klet_sweep(struct hrtimer *timer)
{
	struct klet_inst *inst = &klet_inst;
	struct pt_regs *regs = get_irq_regs();
	struct klet_carrier *c;

	atomic_inc(&inst->sweeps);

	if (atomic_read(&inst->nr_carriers) == 0)
		return HRTIMER_NORESTART;

	if (!regs || user_mode(regs))
		goto again;
	/*
	 * The one test that matters: the interrupted instruction was kernelet
	 * code. Anything in Linux's text or the endovisor's own is off limits.
	 */
	if (!klet_in_image_text(regs->ip))
		goto again;
	if (!current->carrier_hooks)
		goto again;

	c = klet_current_carrier();
	if (c->inst != inst || !inst->dying)
		goto again;
	if (c->depth != 0 || c->evicted || c->state != KLET_RUNNING)
		goto again;

	c->evicted = true;
	atomic_inc(&inst->evictions);
	pr_info("kernelet: evicting %s carrier (pid %d) on cpu %d: ip %#lx (+%#lx in the kernelet image, %pS), sweep %d\n",
		klet_kind_name(c->kind), current->pid, smp_processor_id(),
		regs->ip, regs->ip - (unsigned long)__klet_image_text_start,
		(void *)regs->ip, atomic_read(&inst->sweeps));

	/* The only register the endovisor touches. */
	regs->ip = (unsigned long)klet_exit_stub;

again:
	hrtimer_forward_now(timer, ns_to_ktime(KLET_SWEEP_INTERVAL_NS));
	return HRTIMER_RESTART;
}

static void klet_sweep_arm_local(void *unused)
{
	struct hrtimer *timer = this_cpu_ptr(&klet_sweep_timer);

	if (!hrtimer_active(timer))
		hrtimer_start(timer, ns_to_ktime(KLET_SWEEP_INTERVAL_NS),
			      HRTIMER_MODE_REL_PINNED_HARD);
}

/* Starts the sweep on every CPU. Called from process context. */
void klet_evict_arm(struct klet_inst *inst)
{
	if (!klet_sweep_ready)
		return;
	if (atomic_read(&inst->nr_carriers) == 0)
		return;
	pr_info("kernelet: arming the eviction sweep every %d us on %d cpu(s)\n",
		KLET_SWEEP_INTERVAL_NS / 1000, num_online_cpus());
	on_each_cpu(klet_sweep_arm_local, NULL, 1);
}

int klet_evict_init(void)
{
	int cpu;

	for_each_possible_cpu(cpu) {
		struct hrtimer *timer = per_cpu_ptr(&klet_sweep_timer, cpu);

		hrtimer_init(timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL_HARD);
		timer->function = klet_sweep;
	}
	klet_sweep_ready = true;
	return 0;
}

/*
 * hrtimer_cancel() waits for a running callback, so after this no callback is
 * running or will start, which is what makes it safe for the module's text to go
 * away next.
 */
void klet_evict_exit(void)
{
	int cpu;

	klet_sweep_ready = false;
	for_each_possible_cpu(cpu)
		hrtimer_cancel(per_cpu_ptr(&klet_sweep_timer, cpu));
}
