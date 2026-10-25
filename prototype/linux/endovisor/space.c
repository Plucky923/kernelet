// SPDX-License-Identifier: GPL-2.0
/*
 * Tenant memory on Linux's own page tables.
 *
 * vOSTD's VmSpace is a Linux address space. Its page table is the only page
 * table the tenant process has: the endovisor writes it through Linux's own
 * functions, in the vm_* services, and vOSTD reads it through the direct map.
 *
 * Per space: an mm from mm_alloc(), on which the endovisor keeps the user
 * reference until vm_destroy (that reference is what keeps exit_mmap(), the one
 * place the area's page-table pages are freed, from running while vOSTD reads
 * them locklessly); a file with an inode of its own; and the one PFN-mapped
 * area over the whole user range, made at vm_create so that vm_map has
 * somewhere to insert before any carrier runs the process.
 *
 * The area's ->fault and ->pfn_mkwrite only record the fault for the kernel
 * proper and return VM_FAULT_NOPAGE. No ->map_pages (no fault-around by Linux)
 * and no ->access (ptrace and /proc/pid/mem, refused by get_user_pages() for a
 * VM_IO | VM_PFNMAP area, fall back to it).
 *
 * A carrier runs the threads of more than one tenant process, so the address
 * space it is in is not its own: on its way to user mode it adopts the one its
 * virtual CPU has activated (klet_space_adopt), with the patch's
 * kernelet_switch_mm(), and when it dies it goes back to its own empty one
 * (klet_leave_space).
 */

#include <linux/anon_inodes.h>
#include <linux/delay.h>
#include <linux/file.h>
#include <linux/fs.h>
#include <linux/kernel.h>
#include <linux/kernelet.h>
#include <linux/mm.h>
#include <linux/mman.h>
#include <linux/module.h>
#include <linux/pfn.h>
#include <linux/pgtable.h>
#include <linux/sched.h>
#include <linux/sched/coredump.h>
#include <linux/sched/mm.h>
#include <linux/sched/signal.h>
#include <linux/sched/task.h>
#include <linux/rcupdate.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/wait.h>
#include <linux/wait_bit.h>

#include <asm/pgtable.h>
#include <asm/tlbflush.h>
#include <asm/trapnr.h>

#include "kernelet.h"

/*
 * The patch exports flush_tlb_mm_range(), but asm/tlbflush.h declares it only
 * #ifndef MODULE: Linux hides its TLB internals from modules on purpose, so the
 * export alone does not make it callable. The prototype is repeated here,
 * exactly as arch/x86/include/asm/tlbflush.h has it in v6.12.
 */
extern void flush_tlb_mm_range(struct mm_struct *mm, unsigned long start,
			       unsigned long end, unsigned int stride_shift,
			       bool freed_tables);

/*
 * The tree's user range exactly, [VMAR_LOWEST_ADDR, MAX_USERSPACE_VADDR): 64 KiB
 * up to 2^47 minus one page, which is TASK_SIZE_MAX under four-level paging, so
 * that every page the kernel proper can map, the top one included, is inside
 * the area. A space's mm from mm_alloc() has no exec stack to leave room for.
 */
#define KLET_AREA_START KLET_WINDOW_START
#define KLET_AREA_END	TASK_SIZE_MAX

#define KSTAT_INC(inst, f) atomic64_inc(&(inst)->mem_stats->f)

/* ------------------------------------------------------------------ */
/* Finding a space                                                    */
/* ------------------------------------------------------------------ */

/*
 * Takes a reference that keeps the space from being destroyed under the
 * caller. Every service but vm_create goes through this: it is the check that
 * the space is this kernelet's.
 */
static struct klet_space *klet_space_get(struct klet_inst *inst, u64 id)
{
	struct klet_space *sp;

	if (id == 0 || id > KLET_MAX_SPACES)
		return NULL;
	sp = &inst->spaces[id - 1];
	if (sp->inst != inst || !atomic_inc_not_zero(&sp->users))
		return NULL;
	if (!READ_ONCE(sp->live)) {
		if (atomic_dec_and_test(&sp->users))
			wake_up_var(&sp->users);
		return NULL;
	}
	return sp;
}

static void klet_space_put(struct klet_space *sp)
{
	if (atomic_dec_and_test(&sp->users))
		wake_up_var(&sp->users);
}

/* ------------------------------------------------------------------ */
/* The area                                                           */
/* ------------------------------------------------------------------ */

/*
 * Records a fault of the tenant's for the kernel proper: the carrier's pending
 * exception, picked up by the resume hook, which returns from user_run with a
 * page fault. Nothing is inserted; the kernel proper's handler maps, which
 * inserts, and the instruction is retried with no second fault.
 */
static vm_fault_t klet_space_report(struct vm_fault *vmf, bool mkwrite)
{
	struct vm_area_struct *vma = vmf->vma;
	struct klet_space *sp = vma->vm_file ? vma->vm_file->private_data : NULL;
	struct klet_carrier *c = current->carrier_hooks ? klet_current_carrier() : NULL;
	bool user = !!(vmf->flags & FAULT_FLAG_USER);
	bool write = mkwrite || !!(vmf->flags & FAULT_FLAG_WRITE);
	bool exec = !!(vmf->flags & FAULT_FLAG_INSTRUCTION);
	struct klet_inst *inst;

	if (!sp)
		return VM_FAULT_SIGBUS;
	inst = sp->inst;
	if (mkwrite)
		KSTAT_INC(inst, mkwrites);
	else
		KSTAT_INC(inst, faults);

	if (!c || c->inst != inst || inst->stopped || inst->dying)
		return VM_FAULT_SIGBUS;

	/*
	 * A kernel-mode access is Linux's own (get_user() on an area address): the
	 * kernelet is never told, and Linux's exception table turns the SIGBUS
	 * into -EFAULT.
	 */
	if (!user) {
		KSTAT_INC(inst, kernel_faults);
		return VM_FAULT_SIGBUS;
	}

	c->exc_trap = X86_TRAP_PF;
	c->exc_addr = vmf->address;
	c->exc_error = (mkwrite ? 1 : 0) | (write ? 2 : 0) | 4 | (exec ? 16 : 0);
	c->exc_pending = true;
	set_thread_flag(TIF_NOTIFY_RESUME);
	KSTAT_INC(inst, reported);
	return VM_FAULT_NOPAGE;
}

static vm_fault_t klet_space_fault(struct vm_fault *vmf)
{
	return klet_space_report(vmf, false);
}

/*
 * A write to a present, read-only entry of a VM_SHARED area. Without this op
 * wp_pfn_shared() would make the entry writable on Linux's own authority;
 * VM_FAULT_NOPAGE stops it (mm/memory.c, wp_pfn_shared, v6.12).
 */
static vm_fault_t klet_space_pfn_mkwrite(struct vm_fault *vmf)
{
	return klet_space_report(vmf, true);
}

static const struct vm_operations_struct klet_space_vm_ops = {
	.fault = klet_space_fault,
	.pfn_mkwrite = klet_space_pfn_mkwrite,
	/* deliberately no .map_pages and no .access */
};

static int klet_space_mmap(struct file *file, struct vm_area_struct *vma)
{
	struct klet_space *sp = file->private_data;

	if (!current->carrier_hooks)
		return -EPERM;
	/* The area belongs in its own space's address space and nowhere else. */
	if (!sp || vma->vm_mm != sp->mm) {
		pr_err("kernelet: space %u's area would be mapped into mm %p, not its own %p (current->mm %p)\n",
		       sp ? sp->id : 0, vma->vm_mm, sp ? sp->mm : NULL, current->mm);
		return -EINVAL;
	}

	vm_flags_set(vma, VM_PFNMAP | VM_IO | VM_DONTEXPAND | VM_DONTDUMP |
			  VM_DONTCOPY);
	vma->vm_ops = &klet_space_vm_ops;
	return 0;
}

/* .owner: the last fput() of the file may run after the mm's module
 * reference has gone, and the file's operations must not outlive the module. */
static const struct file_operations klet_space_fops = {
	.owner = THIS_MODULE,
	.mmap = klet_space_mmap,
	.llseek = noop_llseek,
};

/*
 * Makes the area in @sp's mm. vm_mmap() works on current->mm only, so the
 * calling carrier adopts the new address space for the length of the call and
 * goes back to whatever it had: two page-table loads per process creation.
 */
static int klet_space_make_area(struct klet_space *sp)
{
	struct mm_struct *prev, *back;
	struct vm_area_struct *vma;
	unsigned long ret;
	bool ok = false;

	mmget(sp->mm);
	prev = kernelet_switch_mm(sp->mm);	/* we now own prev's reference */

	ret = vm_mmap(sp->file, KLET_AREA_START, KLET_AREA_END - KLET_AREA_START,
		      PROT_READ | PROT_WRITE | PROT_EXEC, MAP_SHARED | MAP_FIXED,
		      KLET_AREA_START);
	if (!IS_ERR_VALUE(ret) && ret == KLET_AREA_START) {
		mmap_read_lock(sp->mm);
		vma = vma_lookup(sp->mm, KLET_AREA_START);
		ok = vma && vma->vm_start == KLET_AREA_START &&
		     vma->vm_end == KLET_AREA_END &&
		     (vma->vm_flags & VM_PFNMAP) && (vma->vm_flags & VM_SHARED);
		mmap_read_unlock(sp->mm);
	}

	back = kernelet_switch_mm(prev);	/* consumes prev's, returns ours */
	if (back)
		mmput(back);

	if (IS_ERR_VALUE(ret))
		return (int)ret;
	if (!ok)
		return -EINVAL;
	sp->start = KLET_AREA_START;
	sp->end = KLET_AREA_END;
	return 0;
}

/*
 * Every service that edits a space's page table takes the address space's
 * read lock and finds the area afresh rather than keeping a pointer to it,
 * because a vm_area_struct is only guaranteed to exist while that lock is
 * held. Returns the area
 * with the lock held, or NULL with it released.
 */
static struct vm_area_struct *klet_space_lock_area(struct klet_space *sp)
{
	struct vm_area_struct *vma;

	mmap_read_lock(sp->mm);
	vma = vma_lookup(sp->mm, sp->start);
	if (!vma || vma->vm_file != sp->file || !(vma->vm_flags & VM_PFNMAP)) {
		mmap_read_unlock(sp->mm);
		return NULL;
	}
	return vma;
}

/*
 * The pmd for @va if a page table exists there, else NULL. Page-table pages
 * of the area are freed only in exit_mmap(), which the endovisor's
 * reference holds off, so the walk needs no lock to stay valid.
 */
static pmd_t *klet_space_pmd(struct mm_struct *mm, unsigned long va)
{
	pgd_t *pgd;
	p4d_t *p4d;
	pud_t *pud;
	pmd_t *pmd, pmdv;

	pgd = pgd_offset(mm, va);
	if (pgd_none(READ_ONCE(*pgd)))
		return NULL;
	p4d = p4d_offset(pgd, va);
	if (p4d_none(READ_ONCE(*p4d)))
		return NULL;
	pud = pud_offset(p4d, va);
	if (pud_none(READ_ONCE(*pud)) || pud_leaf(READ_ONCE(*pud)))
		return NULL;
	pmd = pmd_offset(pud, va);
	pmdv = pmdp_get_lockless(pmd);
	if (pmd_none(pmdv) || pmd_leaf(pmdv))
		return NULL;
	return pmd;
}

/*
 * Runs @fn on the entries of [va, va + len), which must lie within one page
 * table that already exists, under that table's PTE lock.
 *
 * pte_offset_map_lock() is what the design names, but __pte_offset_map_lock()
 * is not exported to modules in v6.12, and follow_pfnmap_start(), which is,
 * "must not be used to modify PTE content". apply_to_page_range() is exported
 * and, in its create variant, calls @fn for every slot (the v6.12 bug of the
 * apply_to_existing_page_range() loop is on the !create path only); with the
 * pmd known to exist it allocates nothing.
 */
static int klet_space_ptes(struct mm_struct *mm, unsigned long va,
			   unsigned long len, pte_fn_t fn, void *data)
{
	if (!klet_space_pmd(mm, va))
		return -ENOENT;
	return apply_to_page_range(mm, va, len, fn, data);
}

struct klet_pte_ctx {
	unsigned long pfn;
	pgprot_t prot;
	bool done;
};

static int klet_pte_is_pfn(pte_t *pte, unsigned long addr, void *data)
{
	struct klet_pte_ctx *ctx = data;
	pte_t e = ptep_get(pte);

	ctx->done = pte_present(e) && pte_special(e) && pte_pfn(e) == ctx->pfn;
	return 0;
}


/*
 * Rewrites one present entry's protection in place with one compare-and-swap,
 * so that a lockless reader never sees it absent (Linux's own
 * ptep_modify_prot_start() clears it first) and the hardware's accessed and
 * dirty updates are not lost. pte_modify() keeps the frame number, the special
 * bit and A/D.
 */
static int klet_pte_protect(pte_t *pte, unsigned long addr, void *data)
{
	struct klet_pte_ctx *ctx = data;
	pte_t old = ptep_get(pte), new;

	if (!pte_present(old))
		return -EINVAL;	/* create=true calls us for an empty slot too */
	do {
		new = pte_modify(old, ctx->prot);
	} while (!try_cmpxchg64((u64 *)&pte->pte, (u64 *)&old.pte, pte_val(new)));
	ctx->done = true;
	return 0;
}

/* ------------------------------------------------------------------ */
/* vm_create, vm_destroy, vm_activate                                 */
/* ------------------------------------------------------------------ */

s64 klet_do_vm_create(struct klet_carrier *c)
{
	struct klet_inst *inst = c->inst;
	struct klet_space *sp = NULL;
	struct mm_struct *mm;
	struct file *file;
	unsigned int i;
	int err;

	mutex_lock(&inst->spaces_lock);
	for (i = 0; i < KLET_MAX_SPACES; i++) {
		if (!inst->spaces[i].live && !inst->spaces[i].mm &&
		    atomic_read(&inst->spaces[i].users) == 0) {
			sp = &inst->spaces[i];
			break;
		}
	}
	if (!sp) {
		mutex_unlock(&inst->spaces_lock);
		return -KLET_LIMIT;
	}

	/* mm_alloc() plus its one addition to the cgroup's MGLRU list. */
	mm = kernelet_mm_alloc(inst->owner);
	if (!mm) {
		mutex_unlock(&inst->spaces_lock);
		return -KLET_NOMEM;
	}

	/*
	 * An inode of its own: anon_inode_getfile() would hand every space the one
	 * shared anonymous inode, and every space's area would then sit in one
	 * i_mmap tree, which every rmap walk over any of them would traverse.
	 */
	file = anon_inode_create_getfile("[kernelet-space]", &klet_space_fops, sp,
					 O_RDWR, NULL);
	if (IS_ERR(file)) {
		/* An LSM may refuse it (security_inode_init_security_anon). */
		pr_err("kernelet: vm_create: anon_inode_create_getfile() refused: %ld\n",
		       PTR_ERR(file));
		mmput(mm);
		mutex_unlock(&inst->spaces_lock);
		return -KLET_NOMEM;
	}

	sp->inst = inst;
	sp->id = i + 1;
	sp->mm = mm;
	sp->file = file;
	sp->dying = false;
	sp->rec = &inst->space_recs[i];
	init_waitqueue_head(&sp->wq);
	memset(sp->rec->lock, 0, sizeof(sp->rec->lock));

	err = klet_space_make_area(sp);
	if (err) {
		pr_err("kernelet: vm_create: cannot make the area: %d\n", err);
		fput(file);
		mmput(mm);
		sp->mm = NULL;
		sp->file = NULL;
		mutex_unlock(&inst->spaces_lock);
		return -KLET_NOMEM;
	}

	/*
	 * Not dumpable, as the carriers are (main.c, klet_load_binary): a
	 * tenant's memory is reachable through a process whose address space
	 * this is, and only root may read it. mm_alloc() copied the flags of
	 * the carrier's own address space already; this does not depend on it.
	 */
	set_mask_bits(&mm->flags, MMF_DUMPABLE_MASK, SUID_DUMP_DISABLE);
	WRITE_ONCE(sp->rec->root_paddr, (u64)__pa(mm->pgd));
	sp->rec->gen++;
	atomic_set(&sp->users, 1);	/* the space's own reference */
	smp_store_release(&sp->live, true);
	KSTAT_INC(inst, spaces);
	mutex_unlock(&inst->spaces_lock);

	if (atomic64_read(&inst->mem_stats->spaces) <= 4)
		pr_info("kernelet: space %u created: root %#llx, area [%#lx, %#lx), its own inode, mm owner %s\n",
			sp->id, sp->rec->root_paddr, sp->start, sp->end,
#ifdef CONFIG_MEMCG
			READ_ONCE(mm->owner) ? "a task" : "none"
#else
			"n/a"
#endif
			);
	return sp->id;
}

/*
 * Clears every entry of the area and flushes, under the read lock, so that no
 * page table anywhere maps a frame of the grant whoever still holds a
 * reference to the address space.
 */
static void klet_space_zap_all(struct klet_space *sp)
{
	struct vm_area_struct *vma = klet_space_lock_area(sp);

	if (!vma)
		return;
	zap_vma_ptes(vma, sp->start, sp->end - sp->start);
	mmap_read_unlock(sp->mm);
}

/* Tears a space down. Called with spaces_lock held. */
static void klet_space_teardown(struct klet_inst *inst, struct klet_space *sp)
{
	struct mm_struct *mm = sp->mm;
	struct file *file = sp->file;
	unsigned int i, held = 0;

	WRITE_ONCE(sp->live, false);
	WRITE_ONCE(sp->dying, true);
	wake_up_all(&sp->wq);
	/* Drop the space's own reference and wait for the calls in flight. */
	if (!atomic_dec_and_test(&sp->users))
		wait_var_event(&sp->users, atomic_read(&sp->users) == 0);

	for (i = 0; i < KLET_SPACE_LOCK_WORDS; i++)
		if (READ_ONCE(sp->rec->lock[i]))
			held++;
	if (held && !inst->dying && !inst->stopped)
		pr_warn("kernelet: space %u destroyed with %u range-lock word(s) held\n",
			sp->id, held);

	/*
	 * A vCPU that still has it activated has none any more. Under the lock,
	 * which is what keeps a carrier in inst->vcpus from being freed.
	 */
	spin_lock(&inst->lock);
	for (i = 0; i < inst->nr_vcpus; i++) {
		struct klet_carrier *v = inst->vcpus[i];

		if (v && READ_ONCE(v->vrec.space) == sp->id)
			WRITE_ONCE(v->vrec.space, 0);
	}
	spin_unlock(&inst->lock);

	if (mm)
		klet_space_zap_all(sp);

	WRITE_ONCE(sp->rec->root_paddr, 0);
	sp->mm = NULL;
	sp->file = NULL;
	/*
	 * The endovisor's reference. A carrier that still has this mm adopted keeps
	 * its own and drops it when it next adopts something else, or dies; only
	 * then does exit_mmap() free the page tables.
	 */
	if (file)
		fput(file);
	if (mm)
		mmput(mm);
}

s64 klet_do_vm_destroy(struct klet_carrier *c, u64 id)
{
	struct klet_inst *inst = c->inst;
	struct klet_space *sp;

	if (id == 0 || id > KLET_MAX_SPACES)
		return -KLET_INVALID;
	mutex_lock(&inst->spaces_lock);
	sp = &inst->spaces[id - 1];
	if (!sp->live || sp->inst != inst) {
		mutex_unlock(&inst->spaces_lock);
		return -KLET_INVALID;
	}
	klet_space_teardown(inst, sp);
	mutex_unlock(&inst->spaces_lock);
	return 0;
}

/* Never sleeps: the kernel proper calls activate from its post-schedule
 * handler, with interrupts off. */
s64 klet_do_vm_activate(struct klet_carrier *c, u64 id)
{
	struct klet_space *sp;

	if (id != 0) {
		sp = klet_space_get(c->inst, id);
		if (!sp)
			return -KLET_INVALID;
		klet_space_put(sp);
	}
	WRITE_ONCE(c->vrec.space, id);
	return 0;
}

/* At sandbox destroy: carriers first (their lifelines have closed), then every
 * remaining space, then the grant. A killed kernelet runs none of its drops. */
void klet_spaces_destroy(struct klet_inst *inst)
{
	unsigned int i;

	if (!inst->space_recs)
		return;
	mutex_lock(&inst->spaces_lock);
	/*
	 * The owner pin goes with the sandbox: clear it from every mm that may
	 * outlive this, wait out RCU readers of mm->owner, then unpin.
	 */
	if (inst->owner) {
#ifdef CONFIG_MEMCG
		for (i = 0; i < KLET_MAX_SPACES; i++)
			if (inst->spaces[i].live && inst->spaces[i].mm)
				WRITE_ONCE(inst->spaces[i].mm->owner, NULL);
#endif
		synchronize_rcu();
		put_task_struct(inst->owner);
		inst->owner = NULL;
	}
	for (i = 0; i < KLET_MAX_SPACES; i++)
		if (inst->spaces[i].live)
			klet_space_teardown(inst, &inst->spaces[i]);
	mutex_unlock(&inst->spaces_lock);
}

/* A kill wakes every waiter of the kernelet's spaces. */
void klet_spaces_wake_all(struct klet_inst *inst)
{
	unsigned int i;

	if (!inst->space_recs)
		return;
	for (i = 0; i < KLET_MAX_SPACES; i++)
		if (READ_ONCE(inst->spaces[i].live))
			wake_up_all(&inst->spaces[i].wq);
}

int klet_spaces_init(struct klet_inst *inst)
{
	mutex_init(&inst->spaces_lock);
	inst->space_recs = kcalloc(KLET_MAX_SPACES, sizeof(*inst->space_recs),
				   GFP_KERNEL);
	inst->mem_stats = kzalloc(sizeof(*inst->mem_stats), GFP_KERNEL);
	if (!inst->space_recs || !inst->mem_stats) {
		kfree(inst->space_recs);
		kfree(inst->mem_stats);
		return -ENOMEM;
	}
	inst->boot.space_recs = (u64)(unsigned long)inst->space_recs;
	inst->boot.nr_space_recs = KLET_MAX_SPACES;
	inst->boot.mem_stats = (u64)(unsigned long)inst->mem_stats;
	return 0;
}

void klet_spaces_free(struct klet_inst *inst)
{
	klet_spaces_destroy(inst);
	kfree(inst->space_recs);
	inst->space_recs = NULL;
}

/* ------------------------------------------------------------------ */
/* Adoption at user_run                                               */
/* ------------------------------------------------------------------ */

int klet_space_adopt(struct klet_carrier *c, u64 id)
{
	struct klet_space *sp;
	struct mm_struct *old;

	if (id == 0)
		return 0;	/* no space activated: nothing to adopt */
	sp = klet_space_get(c->inst, id);
	if (!sp)
		return -ENOENT;

	if (current->mm != sp->mm) {
		/* The helper consumes our reference on the new mm and hands back
		 * the old one's. */
		mmget(sp->mm);
		old = kernelet_switch_mm(sp->mm);
		c->cur_mm = sp->mm;
		atomic_inc(&c->inst->n.mm_switches);
		if (old && old != sp->mm)
			mmput(old);
		/*
		 * The carrier's blank mm is dropped at its first adoption: it is
		 * owned by the carrier, and nothing may outlive its owner.
		 */
		old = xchg(&c->blank_mm, NULL);
		if (old)
			mmput(old);
	}
	klet_space_put(sp);
	return 0;
}

/*
 * Puts the dying carrier back in its own empty address space, so that the
 * address space of a space it had adopted is not kept alive by a carrier that
 * will never run in it again.
 */
void klet_leave_space(struct klet_carrier *c)
{
	struct mm_struct *old;

	if (!c->blank_mm || !current->mm || current->mm == c->blank_mm)
		return;

	mmget(c->blank_mm);
	old = kernelet_switch_mm(c->blank_mm);
	c->cur_mm = c->blank_mm;
	if (old && old != c->blank_mm)
		mmput(old);
}

/* ------------------------------------------------------------------ */
/* vm_map                                                             */
/* ------------------------------------------------------------------ */

/*
 * Linux's pgprot_t, built from Linux's own constants and the three bits; the
 * kernelet never supplies page-table bits. R must be set: a page without read
 * permission has no Linux entry at all (vOSTD keeps it in its withheld set).
 * RAM is write-back, which is also what track_pfn_insert() imposes on it.
 */
static int klet_prot_to_pgprot(u32 prot, pgprot_t *out)
{
	unsigned long vm_flags = VM_SHARED | VM_READ;

	if (prot & ~KLET_PROT_VALID)
		return -KLET_INVALID;
	if (!(prot & KLET_PROT_READ))
		return -KLET_INVALID;
	if (prot & KLET_PROT_LARGE)
		return -KLET_INVALID;		/* 4 KiB pages only, in this version */
	if (prot & KLET_PROT_CACHE_MASK)
		return -KLET_INVALID;		/* write-back only */
	if (prot & KLET_PROT_WRITE)
		vm_flags |= VM_WRITE;
	if (prot & KLET_PROT_EXEC)
		vm_flags |= VM_EXEC;
	*out = vm_get_page_prot(vm_flags);
	return 0;
}

/* Called with the area's read lock held. */
static s64 klet_space_insert(struct klet_space *sp, struct vm_area_struct *vma,
			     u64 va, u64 paddr, pgprot_t pgprot)
{
	unsigned long pfn = paddr >> PAGE_SHIFT;
	struct klet_pte_ctx ctx = { .done = false };
	vm_fault_t ret;

	/* The grant check: the frame must be this kernelet's. */
	if ((paddr & ~PAGE_MASK) || !pfn_valid(pfn) ||
	    !klet_in_grant(sp->inst, paddr, PAGE_SIZE))
		return -KLET_NOT_OWNED;
	if ((va & ~PAGE_MASK) || va < sp->start || va >= sp->end)
		return -KLET_INVALID;

	ret = vmf_insert_pfn_prot(vma, va, pfn, pgprot);
	if (ret & VM_FAULT_OOM)
		return -KLET_LIMIT;	/* no page-table page */
	if (ret != VM_FAULT_NOPAGE)
		return -KLET_INVALID;

	/*
	 * insert_pfn() leaves an existing entry alone and still says
	 * VM_FAULT_NOPAGE, so the slot is checked afterwards, under its PTE lock:
	 * it must hold the entry just made. A different frame there means the
	 * range lock failed to exclude a writer, a vOSTD bug.
	 */
	ctx.pfn = pfn;
	klet_space_ptes(sp->mm, va, PAGE_SIZE, klet_pte_is_pfn, &ctx);
	if (!ctx.done)
		return -KLET_INVALID;
	return 0;
}

static void klet_test_sleep(u32 prot)
{
	if ((prot & KLET_PROT_TEST_SLEEP) && klet_test_hooks)
		msleep(klet_test_sleep_ms);
}

s64 klet_do_vm_map(struct klet_carrier *c, u64 id, u64 va, u64 paddr, u32 prot)
{
	struct vm_area_struct *vma;
	struct klet_space *sp;
	pgprot_t pgprot;
	s64 err;

	err = klet_prot_to_pgprot(prot, &pgprot);
	if (err)
		return err;
	sp = klet_space_get(c->inst, id);
	if (!sp)
		return -KLET_INVALID;
	KSTAT_INC(c->inst, maps);
	klet_test_sleep(prot);
	vma = klet_space_lock_area(sp);
	if (!vma) {
		klet_space_put(sp);
		return -KLET_INVALID;
	}
	err = klet_space_insert(sp, vma, va, paddr, pgprot);
	mmap_read_unlock(sp->mm);
	klet_space_put(sp);
	return err;
}

/* ------------------------------------------------------------------ */
/* vm_unmap: zap_vma_ptes(), flushed before it returns                */
/* ------------------------------------------------------------------ */

/*
 * zap_vma_ptes() clears every present entry of the range, special ones
 * included, and flushes it through Linux's own gather-and-finish before it
 * returns. It is void, and silently does nothing for a range not wholly inside
 * the area, which is why the range is clipped to the area first. The count of
 * entries cleared is vOSTD's own, from its walk before the call.
 */
s64 klet_do_vm_unmap(struct klet_carrier *c, u64 id, u64 va, u64 len)
{
	struct vm_area_struct *vma;
	struct klet_space *sp;
	u64 end;

	if ((va & ~PAGE_MASK) || (len & ~PAGE_MASK) || len == 0 || va + len < va)
		return -KLET_INVALID;
	sp = klet_space_get(c->inst, id);
	if (!sp)
		return -KLET_INVALID;
	KSTAT_INC(c->inst, unmaps);
	/* Clip to the area: nothing outside it is ever mapped. */
	end = min_t(u64, va + len, sp->end);
	if (va < sp->start)
		va = sp->start;
	if (va >= end) {
		klet_space_put(sp);
		return 0;
	}
	vma = klet_space_lock_area(sp);
	if (!vma) {
		klet_space_put(sp);
		return -KLET_INVALID;
	}
	zap_vma_ptes(vma, va, end - va);	/* clears and flushes */
	mmap_read_unlock(sp->mm);
	klet_space_put(sp);
	return 0;
}

/* ------------------------------------------------------------------ */
/* vm_protect: one page, rewritten in place, not flushed              */
/* ------------------------------------------------------------------ */

s64 klet_do_vm_protect(struct klet_carrier *c, u64 id, u64 va, u32 prot)
{
	struct klet_pte_ctx ctx = { .done = false };
	struct vm_area_struct *vma;
	struct klet_space *sp;
	s64 err;

	err = klet_prot_to_pgprot(prot, &ctx.prot);
	if (err)
		return err;
	if (va & ~PAGE_MASK)
		return -KLET_INVALID;
	sp = klet_space_get(c->inst, id);
	if (!sp)
		return -KLET_INVALID;
	KSTAT_INC(c->inst, protects);
	if (va < sp->start || va >= sp->end) {
		klet_space_put(sp);
		return -KLET_INVALID;
	}
	vma = klet_space_lock_area(sp);
	if (!vma) {
		klet_space_put(sp);
		return -KLET_INVALID;
	}
	if (klet_space_ptes(sp->mm, va, PAGE_SIZE, klet_pte_protect, &ctx))
		ctx.done = false;
	mmap_read_unlock(sp->mm);
	klet_space_put(sp);
	if (!ctx.done)
		return -KLET_INVALID;	/* no entry there: a vOSTD bug */
	KSTAT_INC(c->inst, protected_);
	return 1;
}

/* ------------------------------------------------------------------ */
/* vm_flush: synchronous, never sleeps                                */
/* ------------------------------------------------------------------ */

/*
 * flush_tlb_mm_range() reaches every processor in the mm's CPU mask, which
 * switch_mm_irqs_off() inside kernelet_switch_mm() keeps current, and returns
 * when they have all flushed. Linux itself calls it under page-table spin
 * locks, so this service may be called while the kernelet holds the cursor.
 */
s64 klet_do_vm_flush(struct klet_carrier *c, u64 id, u64 va, u64 len)
{
	struct klet_space *sp;

	sp = klet_space_get(c->inst, id);
	if (!sp)
		return -KLET_INVALID;
	if (len == U64_MAX) {
		flush_tlb_mm_range(sp->mm, 0, TLB_FLUSH_ALL, 0, false);
		KSTAT_INC(c->inst, flush_alls);
	} else {
		if ((va & ~PAGE_MASK) || (len & ~PAGE_MASK) || va + len < va) {
			klet_space_put(sp);
			return -KLET_INVALID;
		}
		if (len)
			flush_tlb_mm_range(sp->mm, va, va + len, PAGE_SHIFT, false);
		KSTAT_INC(c->inst, flushes);
	}
	klet_space_put(sp);
	return 0;
}

/* ------------------------------------------------------------------ */
/* vm_wait, vm_wake: the range lock's slow path                       */
/* ------------------------------------------------------------------ */

/*
 * A futex whose waiters are carriers. The lock words live in the space's shared
 * record, so the kernelet names one by index and no address crosses. The word
 * is read under the space's wait-queue lock, and the carrier is on the queue
 * before that lock is dropped; a releaser changes the word with one atomic
 * read-modify-write and then wakes under the same lock, so the wake-up cannot
 * be lost. Returns 0 when the caller should retry its compare-and-swap. On a
 * kill the sleep ends and the epilogue leaves the kernelet for good (there is
 * no -KLET_CANCEL).
 */
s64 klet_do_vm_wait(struct klet_carrier *c, u64 id, u32 stripe, u64 expected)
{
	struct klet_inst *inst = c->inst;
	wait_queue_entry_t wait;
	struct klet_space *sp;
	unsigned long flags;

	if (READ_ONCE(c->vrec.irq_off))
		return -KLET_STATE;		/* the sleeping contract */
	if (stripe >= KLET_SPACE_LOCK_WORDS)
		return -KLET_INVALID;
	sp = klet_space_get(inst, id);
	if (!sp)
		return -KLET_INVALID;
	KSTAT_INC(inst, waits);

	init_wait_entry(&wait, 0);
	spin_lock_irqsave(&sp->wq.lock, flags);
	if (READ_ONCE(sp->rec->lock[stripe]) != expected || READ_ONCE(sp->dying) ||
	    inst->stopped || inst->dying) {
		spin_unlock_irqrestore(&sp->wq.lock, flags);
		klet_space_put(sp);
		return 0;
	}
	__add_wait_queue_entry_tail(&sp->wq, &wait);
	set_current_state(TASK_KILLABLE | TASK_FREEZABLE);
	spin_unlock_irqrestore(&sp->wq.lock, flags);

	KSTAT_INC(inst, wait_sleeps);
	schedule();
	finish_wait(&sp->wq, &wait);
	klet_space_put(sp);
	return 0;
}

/* Never sleeps: wakes every waiter, under the same lock. */
s64 klet_do_vm_wake(struct klet_carrier *c, u64 id, u32 stripe)
{
	struct klet_space *sp;

	if (stripe >= KLET_SPACE_LOCK_WORDS)
		return -KLET_INVALID;
	sp = klet_space_get(c->inst, id);
	if (!sp)
		return -KLET_INVALID;
	KSTAT_INC(c->inst, wakes);
	wake_up_all(&sp->wq);
	klet_space_put(sp);
	return 0;
}
