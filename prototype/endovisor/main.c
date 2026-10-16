// SPDX-License-Identifier: GPL-2.0
/*
 * Module init and exit, the grant, the carrier lifeline, the four host offsets
 * the kernelet needs in order to find its own vCPU record and Linux's
 * preemption count without a call, and the binary-format
 * handler that turns a Linux task into the root carrier of a sandbox.
 */

#include <linux/anon_inodes.h>
#include <linux/binfmts.h>
#include <linux/file.h>
#include <linux/fs.h>
#include <linux/gfp.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/personality.h>
#include <linux/preempt.h>
#include <linux/ptrace.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/sched/task.h>
#include <linux/sched/task_stack.h>
#include <linux/signal.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/thread_info.h>

#include <asm/current.h>
#include <asm/io.h>
#include <asm/msr.h>
#include <asm/processor.h>
#include <asm/ptrace.h>
#include <asm/tsc.h>

#include "kernelet.h"

struct klet_inst klet_inst;

static struct linux_binfmt klet_format;

/*
 * Whether the kernelet mirrors its guard depth into Linux's per-processor
 * preemption count. On is the design; off is the control for the experiment that
 * shows what it buys.
 */
bool klet_mirror = true;
module_param(klet_mirror, bool, 0444);
MODULE_PARM_DESC(klet_mirror,
		 "mirror the kernelet's guard depth into Linux's preemption count (default on)");

/*
 * The test hook, off by default and no part of the design. With
 * klet_test_hooks=1, a vm_map whose protection carries KLET_PROT_TEST_SLEEP
 * sleeps klet_test_sleep_ms in Linux, standing in for direct reclaim inside a
 * page-table allocation, so that the contended-cursor test has a holder that
 * sleeps inside vm_map and a second cursor has to take the range lock's slow
 * path.
 */
bool klet_test_hooks;
module_param(klet_test_hooks, bool, 0444);
MODULE_PARM_DESC(klet_test_hooks, "enable the test hook: test-flagged vm_map calls sleep (default off)");
unsigned int klet_test_sleep_ms = 20;
module_param(klet_test_sleep_ms, uint, 0444);
MODULE_PARM_DESC(klet_test_sleep_ms, "how long a test-flagged vm_map sleeps (default 20 ms)");

/* ------------------------------------------------------------------ */
/* The carrier lifeline                                               */
/* ------------------------------------------------------------------ */

static int klet_lifeline_release(struct inode *inode, struct file *file)
{
	struct klet_carrier *c = file->private_data;

	file->private_data = NULL;
	if (c) {
		klet_carrier_lifeline_closed(c);
		/* The file's own reference (klet_lifeline_create). */
		klet_carrier_put(c);
	}
	return 0;
}

static const struct file_operations klet_lifeline_fops = {
	/* The last fput() may be the last module reference to go. */
	.owner = THIS_MODULE,
	.release = klet_lifeline_release,
	.llseek = noop_llseek,
};

struct file *klet_lifeline_create(struct klet_carrier *c)
{
	return anon_inode_getfile("[kernelet-carrier]", &klet_lifeline_fops,
				  klet_carrier_get(c), O_RDWR);
}

/* ------------------------------------------------------------------ */
/* The four host offsets vOSTD needs without a service call           */
/* ------------------------------------------------------------------ */

/*
 * `CpuId::current()` is on the hottest path the kernelet has, so it cannot be a
 * service call. What vOSTD does instead is two dependent loads: the host's
 * per-processor current-task pointer through `gs:`, the gate pointer inside that
 * task, and then the vCPU record, which is embedded in the carrier record the gate
 * belongs to. The mirror is a third: one `inc`/`dec` of the host's preemption count
 * through `gs:`.
 *
 * The `gs:`-relative offsets are derived at run time from the segment base rather
 * than from the linkage value of the per-cpu symbol, and then checked: a wrong
 * offset here would have the kernelet reading and writing arbitrary host memory, so
 * the module refuses to load if the check fails.
 */
static int klet_publish_host_offsets(struct klet_inst *inst)
{
	unsigned long gsbase, hot, off_cur, off_pc;
	struct task_struct *seen;

	preempt_disable();
	rdmsrl(MSR_GS_BASE, gsbase);
	hot = (unsigned long)this_cpu_ptr(&pcpu_hot);
	off_cur = hot - gsbase + offsetof(struct pcpu_hot, current_task);
	off_pc = hot - gsbase + offsetof(struct pcpu_hot, preempt_count);
	seen = *(struct task_struct **)(gsbase + off_cur);
	preempt_enable();

	if (seen != current) {
		pr_err("kernelet: the gs: offset of the current-task pointer looks wrong (%#lx gives %p, expected %p)\n",
		       off_cur, seen, current);
		return -ELIBBAD;
	}

	inst->boot.gs_current_task = off_cur;
	inst->boot.gs_preempt_count = off_pc;
	inst->boot.task_gate_off = offsetof(struct task_struct, kernelet);
	inst->boot.gate_vrec_off = offsetof(struct klet_carrier, vrec) -
				   offsetof(struct klet_carrier, gate);

	pr_info("kernelet: host offsets: gs:current %#llx, gs:preempt_count %#llx, task->kernelet +%llu, gate->vrec +%llu\n",
		inst->boot.gs_current_task, inst->boot.gs_preempt_count,
		inst->boot.task_gate_off, inst->boot.gate_vrec_off);
	return 0;
}

/* How big a floating-point save area the enabled features need. */
static u64 klet_fpu_area_size(void)
{
	u32 eax, ebx, ecx, edx;

	if (!boot_cpu_has(X86_FEATURE_XSAVE))
		return 512;
	cpuid_count(0xd, 0, &eax, &ebx, &ecx, &edx);
	if (ebx < 512)
		return 512;
	if (ebx > 4096)
		return 4096;
	return ebx;
}

/* ------------------------------------------------------------------ */
/* load_binary                                                        */
/* ------------------------------------------------------------------ */

/*
 * Unmaps everything the exec machinery left in the fresh address space: one
 * one-page VMA at STACK_TOP_MAX holding the argument strings. The kernelet is the
 * loader here, so nothing else belongs in the mm, not even a vDSO.
 */
static void klet_empty_mm(void)
{
	struct mm_struct *mm = current->mm;
	unsigned long start[8], len[8];
	struct vm_area_struct *vma;
	int n = 0, i;

	VMA_ITERATOR(vmi, mm, 0);

	mmap_read_lock(mm);
	for_each_vma(vmi, vma) {
		if (n == ARRAY_SIZE(start))
			break;
		start[n] = vma->vm_start;
		len[n] = vma->vm_end - vma->vm_start;
		n++;
	}
	mmap_read_unlock(mm);

	for (i = 0; i < n; i++)
		vm_munmap(start[i], len[i]);
}

/*
 * set_personality_64bit() is not exported, so the part of it that matters to a
 * carrier is open-coded. The vsyscall bit is deliberately left clear.
 */
static void klet_personality_64bit(void)
{
	clear_thread_flag(TIF_ADDR32);
	current_thread_info()->status &= ~TS_COMPAT;
	current->personality &= ~READ_IMPLIES_EXEC;
}

/*
 * A `.klet` file is the sandbox's configuration: the magic, an ABI version, and
 * how many virtual CPUs the sandbox has.
 */
static int klet_read_config(struct klet_inst *inst, struct linux_binprm *bprm,
			    unsigned int *nr_vcpus)
{
	u32 version, vcpus;
	const char *line;
	size_t len;

	if (memcmp(bprm->buf, KLET_MAGIC, KLET_MAGIC_LEN) != 0)
		return -ENOEXEC;

	memcpy(&version, bprm->buf + 4, sizeof(version));
	memcpy(&vcpus, bprm->buf + 8, sizeof(vcpus));

	if (version != 2) {
		pr_err("kernelet: .klet version %u, expected 2\n", version);
		return -ENOEXEC;
	}
	if (vcpus < 1 || vcpus > KLET_MAX_VCPUS) {
		pr_err("kernelet: .klet asks for %u virtual CPUs (1..%d)\n", vcpus,
		       KLET_MAX_VCPUS);
		return -ENOEXEC;
	}
	*nr_vcpus = vcpus;

	/*
	 * The rest of the header, up to a newline, is the sandbox's command line:
	 * what a bootloader's kernel command line is to a machine, and how the
	 * runtime tells one kernel proper which scenario to run.
	 */
	line = bprm->buf + 12;
	len = strnlen(line, sizeof(bprm->buf) - 12);
	if (len > 0) {
		const char *nl = memchr(line, '\n', len);

		if (nl)
			len = nl - line;
	}
	kfree(inst->cmdline);
	inst->cmdline = NULL;
	inst->boot.cmdline_ptr = 0;
	inst->boot.cmdline_len = 0;
	if (len > 0) {
		inst->cmdline = kmemdup_nul(line, len, GFP_KERNEL);
		if (!inst->cmdline)
			return -ENOMEM;
		inst->boot.cmdline_ptr = (u64)(unsigned long)inst->cmdline;
		inst->boot.cmdline_len = len;
	}
	return 0;
}

static int klet_load_binary(struct linux_binprm *bprm)
{
	struct klet_inst *inst = &klet_inst;
	struct klet_carrier *root;
	unsigned int nr_vcpus;
	int err;

	err = klet_read_config(inst, bprm, &nr_vcpus);
	if (err)
		return err;
	if (inst->stopped || inst->dying)
		return -ENOEXEC;
	if (atomic_read(&inst->nr_carriers) != 0)
		return -EBUSY;	/* exactly one instance in this prototype */

	err = begin_new_exec(bprm);
	if (err)
		return err;

	klet_personality_64bit();
	setup_new_exec(bprm);
	klet_empty_mm();
	set_binfmt(&klet_format);
	finalize_exec(bprm);

	/*
	 * The root carrier never runs tenant code, but its pt_regs are the template
	 * copy_thread() gives every carrier cloned from it, so they must be valid
	 * 64-bit user-mode registers.
	 */
	start_thread(current_pt_regs(), 0, 0);

	err = klet_publish_host_offsets(inst);
	if (err) {
		force_sig(SIGSEGV);
		return err;
	}

	inst->nr_vcpus = nr_vcpus;
	inst->boot.nr_vcpus = nr_vcpus;
	/* The owner of every address space the sandbox will have. */
	if (inst->owner)
		put_task_struct(inst->owner);
	inst->owner = get_task_struct(current);

	root = klet_carrier_new(inst, KLET_ROOT, -1);
	if (!root) {
		force_sig(SIGSEGV);
		return -ENOMEM;
	}
	err = klet_carrier_attach(root);
	if (err) {
		klet_carrier_lifeline_closed(root);
		force_sig(SIGSEGV);
		return err;
	}

	/* Children are reaped without anybody waiting for them. */
	kernel_sigaction(SIGCHLD, SIG_IGN);

	/*
	 * begin_new_exec() reset every handler to SIG_DFL, except the ones the
	 * runtime had set to SIG_IGN, which flush_signal_handlers() keeps; the
	 * signal mask survives the exec too. Neither matters: an ignored signal is
	 * discarded when it is sent, where the drain would have dropped it, and a
	 * fault signal Linux raises for the tenant's instruction un-ignores and
	 * unblocks itself (force_sig_info_to_task()), so it still reaches the
	 * drain. A signal whose default action is to terminate without a core
	 * dump is fatal at the moment it is sent (complete_signal() turns it into
	 * SIGKILL): it would never reach the drain. An operator's SIGTERM to a carrier, or a stray
	 * SIGPIPE, would end the sandbox. So they are ignored, here, and the
	 * vCPU carriers inherit it from the root; SIGKILL and SIGSTOP cannot be,
	 * and keep their meaning. The core-dump class (SIGQUIT, SIGABRT, the
	 * fault signals, SIGSYS, SIGXCPU, SIGXFSZ) still goes through the queue
	 * and the drain.
	 */
	{
		static const int terminate[] = {
			SIGHUP, SIGINT, SIGTERM, SIGUSR1, SIGUSR2, SIGALRM, SIGPIPE,
			SIGIO, SIGPROF, SIGVTALRM, SIGSTKFLT, SIGPWR,
		};
		int i;

		for (i = 0; i < ARRAY_SIZE(terminate); i++)
			kernel_sigaction(terminate[i], SIG_IGN);
		for (i = SIGRTMIN; i <= SIGRTMAX; i++)
			kernel_sigaction(i, SIG_IGN);
	}

	pr_info("kernelet: root carrier exec (pid %d), address space emptied, %u virtual CPU(s), cmdline \"%s\"\n",
		current->pid, nr_vcpus, inst->cmdline ? inst->cmdline : "");

	/*
	 * On the way out to user mode the resume hook runs, and for the root carrier
	 * it never returns: it brings up the vCPU carriers and then waits to die.
	 */
	set_thread_flag(TIF_NOTIFY_RESUME);
	return 0;
}

static struct linux_binfmt klet_format = {
	.module = THIS_MODULE,
	.load_binary = klet_load_binary,
};

/* ------------------------------------------------------------------ */
/* Module init and exit                                               */
/* ------------------------------------------------------------------ */

static void klet_grant_free(struct klet_inst *inst)
{
	if (inst->grant_pages) {
		__free_pages(inst->grant_pages, KLET_GRANT_ORDER);
		inst->grant_pages = NULL;
	}
}

static int klet_grant_alloc(struct klet_inst *inst)
{
	inst->grant_pages = alloc_pages(GFP_KERNEL | __GFP_ZERO, KLET_GRANT_ORDER);
	if (!inst->grant_pages)
		return -ENOMEM;

	inst->boot.abi_version = KLET_ABI_VERSION;
	inst->boot.grant_paddr = page_to_phys(inst->grant_pages);
	inst->boot.grant_len = KLET_GRANT_LEN;
	inst->boot.linear_map_base = (u64)(unsigned long)__va(0);
	inst->boot.nr_vcpus = 1;
	inst->boot.fpu_area_size = klet_fpu_area_size();
	inst->boot.fpu_area_align = 64;
	inst->boot.tsc_khz = tsc_khz;
	inst->boot.mirror_preempt = klet_mirror ? 1 : 0;
	inst->boot.image_text_lo = (u64)(unsigned long)__klet_image_text_start;
	inst->boot.image_text_hi = (u64)(unsigned long)__klet_image_text_end;
	inst->boot.pgtable_levels = pgtable_l5_enabled() ? 5 : 4;
	return 0;
}

/*
 * The eviction sweep and the watch timer decide what is kernelet code by the two
 * symbols that image_start.S and image_end.S put around the pre-linked image.
 * Check it rather than assume it.
 */
static int klet_check_image_text(void)
{
	unsigned long lo = (unsigned long)__klet_image_text_start;
	unsigned long hi = (unsigned long)__klet_image_text_end;
	unsigned long entry = (unsigned long)kernelet_entry_table.kernelet_entry;
	unsigned long vcpu_entry = (unsigned long)kernelet_entry_table.vcpu_entry;
	unsigned long virq = (unsigned long)kernelet_entry_table.virq_entry;
	unsigned long ours = (unsigned long)klet_coro_main;

	if (lo >= hi || !klet_in_image_text(entry) ||
	    !klet_in_image_text(vcpu_entry) || !klet_in_image_text(virq) ||
	    klet_in_image_text(ours)) {
		pr_err("kernelet: the image text bounds are wrong: [%#lx, %#lx), entry %#lx, vcpu_entry %#lx, virq_entry %#lx, endovisor %#lx\n",
		       lo, hi, entry, vcpu_entry, virq, ours);
		return -ELIBBAD;
	}
	pr_info("kernelet: kernelet image text [%#lx, %#lx), %lu bytes; virq_entry at +%#lx\n",
		lo, hi, hi - lo, virq - lo);
	return 0;
}

static int __init klet_init(void)
{
	struct klet_inst *inst = &klet_inst;
	int err;

	if (kernelet_entry_table.abi_version != KLET_ABI_VERSION) {
		pr_err("kernelet: image ABI %llu, endovisor ABI %llu\n",
		       kernelet_entry_table.abi_version, KLET_ABI_VERSION);
		return -EINVAL;
	}

	err = klet_check_image_text();
	if (err)
		return err;

	spin_lock_init(&inst->lock);
	INIT_LIST_HEAD(&inst->carriers);
	INIT_LIST_HEAD(&inst->kstack_all);
	init_waitqueue_head(&inst->root_wq);
	atomic_set(&inst->nr_carriers, 0);
	atomic_set(&inst->sweeps, 0);
	atomic_set(&inst->evictions, 0);
	atomic_set(&inst->ticks, 0);
	atomic_set(&inst->watch_fires, 0);
	atomic_set(&inst->kick_ipis, 0);
	atomic_set(&inst->fires_redirected, 0);
	atomic_set(&inst->fires_elsewhere, 0);
	atomic_set(&inst->fires_masked, 0);
	atomic_set(&inst->virqs, 0);
	atomic_set(&inst->deferrals, 0);
	atomic_set(&inst->longest_defer_us, 0);
	atomic_set(&inst->longest_tick_gap_us, 0);
	atomic_set(&inst->forced_yields, 0);
	atomic_set(&inst->forced_recorded, 0);
	atomic_set(&inst->yields, 0);
	atomic_set(&inst->bad_preempt, 0);
	atomic_set(&inst->on_spins, 0);
	atomic_set(&inst->yield_tos, 0);
	atomic_set(&inst->mm_switches, 0);
	atomic_set(&inst->fpu_swaps, 0);
	atomic_set(&inst->fpu_rejects, 0);
	atomic_set(&inst->mirror_faults, 0);
	atomic_set(&inst->kills_in_service, 0);
	atomic_set(&inst->kills_in_kernelet, 0);
	atomic_set(&inst->carriers_made, 0);
	atomic_set(&inst->carriers_freed, 0);
	atomic_set(&inst->stolen_ms, 0);
	inst->root_lifeline_fd = -1;
	inst->nr_vcpus = 1;

	err = klet_grant_alloc(inst);
	if (err) {
		pr_err("kernelet: cannot allocate a %lu KiB grant: %d\n",
		       (unsigned long)(KLET_GRANT_LEN >> 10), err);
		return err;
	}
	err = klet_spaces_init(inst);
	if (err) {
		klet_grant_free(inst);
		return err;
	}

	klet_evict_init();
	klet_watch_init();
	klet_sched_init();
	register_binfmt(&klet_format);

	pr_info("kernelet: endovisor loaded: grant %lu KiB at %#llx, linear map %#llx, watch %s, mirror %s, fpu area %llu B, tsc %llu kHz%s\n",
		(unsigned long)(KLET_GRANT_LEN >> 10), inst->boot.grant_paddr,
		inst->boot.linear_map_base, klet_watch ? "on" : "off",
		klet_mirror ? "on" : "off", inst->boot.fpu_area_size,
		inst->boot.tsc_khz,
		klet_test_hooks ? ", TEST HOOK on" : "");
	return 0;
}

static void __exit klet_exit(void)
{
	struct klet_inst *inst = &klet_inst;

	unregister_binfmt(&klet_format);
	klet_watch_exit();
	klet_evict_exit();
	klet_sched_exit();
	klet_spaces_free(inst);
	klet_kstack_pool_destroy(inst);
	klet_grant_free(inst);
	kfree(inst->cmdline);
	inst->cmdline = NULL;
	if (atomic_read(&inst->sweeps))
		pr_info("kernelet: eviction: %d sweep(s), %d eviction(s)\n",
			atomic_read(&inst->sweeps), atomic_read(&inst->evictions));
	{
		int i, n = min(atomic_read(&inst->forced_recorded), KLET_FORCED_RECORDS);

		for (i = 0; i < n; i++) {
			struct klet_forced_rec *r = &inst->forced_rec[i];

			pr_info("kernelet: forced yield of vcpu %d (pid %d) on cpu %d at ip %#lx (%pS), guards %u, irq_off %u\n",
				r->vcpu, r->pid, r->cpu, r->ip, (void *)r->ip,
				r->guards, r->irq_off);
		}
	}
	pr_info("kernelet: watch timer: %d tick(s), %d upcall(s), %d voluntary yield(s)\n",
		atomic_read(&inst->ticks), atomic_read(&inst->virqs),
		atomic_read(&inst->yields));
	pr_info("kernelet: kicks: %d IPI(s), %d requested firing(s): %d delivered an upcall, %d found user mode or a service, %d a critical section\n",
		atomic_read(&inst->kick_ipis), atomic_read(&inst->watch_fires),
		atomic_read(&inst->fires_redirected),
		atomic_read(&inst->fires_elsewhere),
		atomic_read(&inst->fires_masked));
	pr_info("kernelet: STATS deferrals=%d longest_defer_us=%d longest_tick_gap_us=%d forced_yields=%d bad_preempt=%d on_spin=%d yield_to=%d mm_switch=%d fpu_swap=%d fpu_reject=%d mirror_fault=%d stolen_ms=%d kstacks=%u\n",
		atomic_read(&inst->deferrals),
		atomic_read(&inst->longest_defer_us),
		atomic_read(&inst->longest_tick_gap_us),
		atomic_read(&inst->forced_yields),
		atomic_read(&inst->bad_preempt),
		atomic_read(&inst->on_spins),
		atomic_read(&inst->yield_tos),
		atomic_read(&inst->mm_switches),
		atomic_read(&inst->fpu_swaps),
		atomic_read(&inst->fpu_rejects),
		atomic_read(&inst->mirror_faults),
		atomic_read(&inst->stolen_ms),
		inst->kstack_made);
	{
		struct klet_mem_stats *m = inst->mem_stats;

		pr_info("kernelet: MEMSTATS faults=%lld mkwrites=%lld reported=%lld kernel_faults=%lld maps=%lld unmaps=%lld unmapped=%lld protects=%lld protected=%lld flushes=%lld flush_alls=%lld waits=%lld wait_sleeps=%lld wakes=%lld spaces=%lld\n",
			atomic64_read(&m->faults), atomic64_read(&m->mkwrites),
			atomic64_read(&m->reported), atomic64_read(&m->kernel_faults),
			atomic64_read(&m->maps),
			atomic64_read(&m->unmaps), atomic64_read(&m->unmapped),
			atomic64_read(&m->protects), atomic64_read(&m->protected_),
			atomic64_read(&m->flushes), atomic64_read(&m->flush_alls),
			atomic64_read(&m->waits), atomic64_read(&m->wait_sleeps),
			atomic64_read(&m->wakes), atomic64_read(&m->spaces));
		kfree(m);
		inst->mem_stats = NULL;
	}
	pr_info("kernelet: kills: %d found in a service, %d in kernelet code by the watch timer\n",
		atomic_read(&inst->kills_in_service),
		atomic_read(&inst->kills_in_kernelet));
	pr_info("kernelet: carrier records: %d made, %d freed, %d live\n",
		atomic_read(&inst->carriers_made), atomic_read(&inst->carriers_freed),
		atomic_read(&inst->carriers_made) - atomic_read(&inst->carriers_freed));
	pr_info("kernelet: endovisor unloaded\n");
}

module_init(klet_init);
module_exit(klet_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Endovisor for the kernelet-in-Linux prototype");
