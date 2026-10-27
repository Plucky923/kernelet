// SPDX-License-Identifier: GPL-2.0
// The restricted PIE loader and per-sandbox image mappings.
//
// Registration validates a self-contained x86-64 `ET_DYN` image and keeps
// an unrelocated template plus one set of immutable backing pages.
// Each sandbox maps those same immutable pages at a different virtual base,
// allocates its own writable pages, and applies `R_X86_64_RELATIVE` there.
// `e_entry` names the `kernelet_entry_table` object, not executable startup code.
// No image code runs while registering or mapping the image.

#include <linux/elf.h>
#include <linux/mm.h>
#include <linux/overflow.h>
#include <linux/slab.h>
#include <linux/sort.h>
#include <linux/string.h>
#include <linux/vmalloc.h>

#include <asm/set_memory.h>

#include "kernelet.h"

// Values specified by the ELF ABI but absent from Linux's exported ELF header.
#ifndef DT_GNU_HASH
#define DT_GNU_HASH 0x6ffffef5
#endif
#ifndef DT_FLAGS
#define DT_FLAGS 30
#endif
#ifndef DF_BIND_NOW
#define DF_BIND_NOW 0x8
#endif
#ifndef DF_1_NOW
#define DF_1_NOW 0x1
#endif
#ifndef DF_1_PIE
#define DF_1_PIE 0x08000000
#endif
#ifndef SHT_INIT_ARRAY
#define SHT_INIT_ARRAY 14
#define SHT_FINI_ARRAY 15
#define SHT_PREINIT_ARRAY 16
#endif
#ifndef SHF_TLS
#define SHF_TLS 0x400
#endif

// Does an interval fit in a bounded buffer without wrapping?
static bool klet_image_range(u64 offset, u64 size, u64 limit)
{
	return offset <= limit && size <= limit - offset;
}

// Find a segment containing an entire interval, excluding page padding.
static const struct klet_image_segment *klet_image_segment(
	const struct klet_kind *kind, u64 offset, u64 size)
{
	unsigned int i;

	for (i = 0; i < kind->nr_segments; i++) {
		const struct klet_image_segment *seg = &kind->segments[i];

		if (offset >= seg->offset &&
		    klet_image_range(offset - seg->offset, size, seg->memsz))
			return seg;
	}
	return NULL;
}

// Validate optional section metadata; loading itself uses program headers.
static int klet_image_sections(const void *buf, size_t len, const Elf64_Ehdr *eh)
{
	const Elf64_Shdr *sh;
	unsigned int i;

	if (!eh->e_shoff && !eh->e_shnum)
		return 0;
	if (!eh->e_shnum || eh->e_shentsize != sizeof(*sh) ||
	    !IS_ALIGNED(eh->e_shoff, __alignof__(*sh)) ||
	    !klet_image_range(eh->e_shoff, (u64)eh->e_shnum * sizeof(*sh), len))
		return -ENOEXEC;
	sh = buf + eh->e_shoff;
	for (i = 0; i < eh->e_shnum; i++) {
		const Elf64_Shdr *s = &sh[i];
		unsigned int j;

		if (s->sh_type != SHT_NOBITS &&
		    !klet_image_range(s->sh_offset, s->sh_size, len))
			return -ENOEXEC;
		if (s->sh_flags & SHF_ALLOC) {
			if ((s->sh_flags & SHF_TLS) ||
			    s->sh_type == SHT_INIT_ARRAY || s->sh_type == SHT_FINI_ARRAY ||
			    s->sh_type == SHT_PREINIT_ARRAY)
				return -ENOEXEC;
		}
		if (s->sh_type != SHT_SYMTAB && s->sh_type != SHT_DYNSYM)
			continue;
		if (s->sh_entsize != sizeof(Elf64_Sym) || s->sh_size % sizeof(Elf64_Sym) ||
		    !IS_ALIGNED(s->sh_offset, __alignof__(Elf64_Sym)))
			return -ENOEXEC;
		for (j = 1; j < s->sh_size / sizeof(Elf64_Sym); j++) {
			const Elf64_Sym *sym = buf + s->sh_offset + j * sizeof(*sym);

			if (sym->st_shndx == SHN_UNDEF || sym->st_shndx == SHN_COMMON ||
			    ELF64_ST_TYPE(sym->st_info) == STT_TLS)
				return -ENOEXEC;
		}
	}
	return 0;
}

// Record load segments and copy their file contents into the zeroed template.
static int klet_image_layout(struct klet_kind *kind, const void *buf, size_t len,
			     Elf64_Phdr *dynamic)
{
	const Elf64_Ehdr *eh = buf;
	const Elf64_Phdr *ph;
	u64 end = 0;
	unsigned int i, executable = 0, writable = 0, dynamics = 0;
	int err;

	if (len < sizeof(*eh) || memcmp(eh->e_ident, ELFMAG, SELFMAG) ||
	    eh->e_ident[EI_CLASS] != ELFCLASS64 || eh->e_ident[EI_DATA] != ELFDATA2LSB ||
	    eh->e_ident[EI_VERSION] != EV_CURRENT || eh->e_version != EV_CURRENT ||
	    eh->e_type != ET_DYN || eh->e_machine != EM_X86_64 ||
	    eh->e_ehsize != sizeof(*eh) || eh->e_phentsize != sizeof(*ph) ||
	    !eh->e_phnum || eh->e_phnum > 32 ||
	    !IS_ALIGNED(eh->e_phoff, __alignof__(*ph)) ||
	    !klet_image_range(eh->e_phoff, (u64)eh->e_phnum * sizeof(*ph), len))
		return -ENOEXEC;
	err = klet_image_sections(buf, len, eh);
	if (err)
		return err;
	ph = buf + eh->e_phoff;
	for (i = 0; i < eh->e_phnum; i++) {
		const Elf64_Phdr *p = &ph[i];
		struct klet_image_segment *seg;

		if (p->p_type == PT_DYNAMIC) {
			if (++dynamics != 1 || p->p_filesz != p->p_memsz ||
			    !p->p_filesz || p->p_filesz % sizeof(Elf64_Dyn) ||
			    !IS_ALIGNED(p->p_vaddr, __alignof__(Elf64_Dyn)) ||
			    !klet_image_range(p->p_offset, p->p_filesz, len))
				return -ENOEXEC;
			*dynamic = *p;
			continue;
		}
		if (p->p_type == PT_GNU_STACK) {
			if (p->p_flags & PF_X)
				return -ENOEXEC;
			continue;
		}
		if (p->p_type == PT_NULL || p->p_type == PT_PHDR || p->p_type == PT_NOTE ||
		    p->p_type == PT_GNU_RELRO)
			continue;
		if (p->p_type != PT_LOAD || kind->nr_segments == KLET_IMAGE_SEGMENTS ||
		    !p->p_memsz || p->p_filesz > p->p_memsz ||
		    !IS_ALIGNED(p->p_vaddr, PAGE_SIZE) || !IS_ALIGNED(p->p_offset, PAGE_SIZE) ||
		    p->p_align != PAGE_SIZE || p->p_vaddr != end ||
		    !klet_image_range(p->p_offset, p->p_filesz, len) ||
		    !klet_image_range(p->p_vaddr, p->p_memsz, KLET_IMAGE_SPAN_MAX) ||
		    (p->p_flags != PF_R && p->p_flags != (PF_R | PF_X) &&
		     p->p_flags != (PF_R | PF_W)))
			return -ENOEXEC;
		seg = &kind->segments[kind->nr_segments++];
		seg->offset = p->p_vaddr;
		seg->filesz = p->p_filesz;
		seg->memsz = p->p_memsz;
		seg->flags = p->p_flags;
		end = PAGE_ALIGN(p->p_vaddr + p->p_memsz);
		if (p->p_flags & PF_X) {
			if (++executable != 1)
				return -ENOEXEC;
			kind->text_lo = p->p_vaddr;
			kind->text_hi = p->p_vaddr + p->p_memsz;
		}
		if (p->p_flags & PF_W) {
			writable++;
			kind->data_size += PAGE_ALIGN(p->p_memsz);
		} else {
			kind->text_size += PAGE_ALIGN(p->p_memsz);
		}
	}
	if (!executable || !writable || dynamics != 1)
		return -ENOEXEC;
	kind->image_size = end;
	kind->nr_pages = end >> PAGE_SHIFT;
	kind->entry_offset = eh->e_entry;
	kind->image = vzalloc(end);
	if (!kind->image)
		return -ENOMEM;
	for (i = 0; i < eh->e_phnum; i++)
		if (ph[i].p_type == PT_LOAD)
			memcpy(kind->image + ph[i].p_vaddr, buf + ph[i].p_offset, ph[i].p_filesz);
	if (!klet_image_segment(kind, dynamic->p_vaddr, dynamic->p_memsz) ||
	    memcmp(kind->image + dynamic->p_vaddr, buf + dynamic->p_offset, dynamic->p_filesz))
		return -ENOEXEC;
	return 0;
}

// Order relocation targets so overlapping writes can be rejected in linear time.
static int klet_reloc_compare(const void *a, const void *b)
{
	const struct klet_image_reloc *x = a, *y = b;

	return x->offset < y->offset ? -1 : x->offset > y->offset;
}

// Accept only metadata needed by a self-contained PIE with relative relocations.
static int klet_image_dynamic(struct klet_kind *kind, const Elf64_Phdr *ph)
{
	const Elf64_Dyn *dyn = (const void *)(kind->image + ph->p_vaddr);
	const struct klet_image_segment *rela_seg;
	u64 rela = 0, relasz = 0, relaent = 0;
	bool found_rela = false, found_size = false, found_ent = false, terminated = false;
	bool found_pie = false;
	unsigned int i;

	for (i = 0; i < ph->p_filesz / sizeof(*dyn); i++) {
		u64 val = dyn[i].d_un.d_val;

		switch (dyn[i].d_tag) {
		case DT_NULL:
			terminated = true;
			goto done;
		case DT_RELA:
			if (found_rela)
				return -ENOEXEC;
			found_rela = true;
			rela = val;
			break;
		case DT_RELASZ:
			if (found_size)
				return -ENOEXEC;
			found_size = true;
			relasz = val;
			break;
		case DT_RELAENT:
			if (found_ent)
				return -ENOEXEC;
			found_ent = true;
			relaent = val;
			break;
		case DT_FLAGS:
			if (val & ~DF_BIND_NOW)
				return -ENOEXEC;
			break;
		case DT_FLAGS_1:
			if (found_pie || !(val & DF_1_PIE) || (val & ~(DF_1_PIE | DF_1_NOW)))
				return -ENOEXEC;
			found_pie = true;
			break;
		case DT_DEBUG:
			if (val)
				return -ENOEXEC;
			break;
		case DT_HASH:
		case DT_GNU_HASH:
		case DT_STRTAB:
		case DT_SYMTAB:
			if (!klet_image_segment(kind, val, 1))
				return -ENOEXEC;
			break;
		case DT_SYMENT:
			if (val != sizeof(Elf64_Sym))
				return -ENOEXEC;
			break;
		case DT_STRSZ:
		case DT_RELACOUNT:
			if (val > kind->image_size)
				return -ENOEXEC;
			break;
		default:
			return -ENOEXEC;
		}
	}
done:
	rela_seg = klet_image_segment(kind, rela, relasz);
	if (!terminated || !found_pie || !found_rela || !found_size || !found_ent ||
	    relaent != sizeof(Elf64_Rela) || relasz % sizeof(Elf64_Rela) ||
	    !IS_ALIGNED(rela, __alignof__(Elf64_Rela)) ||
	    !rela_seg || (rela_seg->flags & PF_W) ||
	    !klet_image_range(rela - rela_seg->offset, relasz, rela_seg->filesz))
		return -ENOEXEC;
	kind->nr_relocs = relasz / sizeof(Elf64_Rela);
	kind->relocs = kvcalloc(kind->nr_relocs, sizeof(*kind->relocs), GFP_KERNEL);
	if (!kind->relocs)
		return -ENOMEM;
	for (i = 0; i < kind->nr_relocs; i++) {
		const Elf64_Rela *r = (const void *)(kind->image + rela + i * sizeof(*r));
		const struct klet_image_segment *seg = klet_image_segment(kind, r->r_offset, sizeof(u64));

		if (ELF64_R_TYPE(r->r_info) != R_X86_64_RELATIVE || ELF64_R_SYM(r->r_info) ||
		    !IS_ALIGNED(r->r_offset, sizeof(u64)) || !seg || !(seg->flags & PF_W) ||
		    r->r_addend < 0 || !klet_image_segment(kind, r->r_addend, 1))
			return -ENOEXEC;
		kind->relocs[i].offset = r->r_offset;
		kind->relocs[i].addend = r->r_addend;
	}
	sort(kind->relocs, kind->nr_relocs, sizeof(*kind->relocs), klet_reloc_compare, NULL);
	for (i = 1; i < kind->nr_relocs; i++)
		if (kind->relocs[i - 1].offset == kind->relocs[i].offset)
			return -ENOEXEC;
	return 0;
}

// Validate entry pointers before any sandbox maps or executes the image.
static int klet_image_entry(struct klet_kind *kind)
{
	const struct klet_image_segment *seg;
	const struct klet_entry_table *entry;
	const size_t offsets[] = {
		offsetof(struct klet_entry_table, kernelet_entry),
		offsetof(struct klet_entry_table, vcpu_entry),
		offsetof(struct klet_entry_table, virq_entry),
	};
	unsigned int i, j;

	seg = klet_image_segment(kind, kind->entry_offset, sizeof(*entry));
	if (!seg || !(seg->flags & PF_W) || !IS_ALIGNED(kind->entry_offset, __alignof__(*entry)))
		return -ENOEXEC;
	entry = (const void *)(kind->image + kind->entry_offset);
	if (entry->abi_version != KLET_ABI_VERSION)
		return -EPROTO;
	for (j = 0; j < kind->nr_relocs; j++)
		if (kind->relocs[j].offset == kind->entry_offset)
			return -ENOEXEC;
	for (i = 0; i < ARRAY_SIZE(offsets); i++) {
		bool found = false;

		for (j = 0; j < kind->nr_relocs; j++) {
			const struct klet_image_reloc *r = &kind->relocs[j];

			if (r->offset != kind->entry_offset + offsets[i])
				continue;
			seg = klet_image_segment(kind, r->addend, 1);
			if (!seg || !(seg->flags & PF_X))
				return -ENOEXEC;
			found = true;
		}
		if (!found)
			return -ENOEXEC;
	}
	return 0;
}

// Validate a PIE and allocate immutable backing pages for the kind's lifetime.
int klet_image_load(struct klet_kind *kind, const void *buf, size_t len)
{
	Elf64_Phdr dynamic = {};
	unsigned int i, j;
	int err;

	err = klet_image_layout(kind, buf, len, &dynamic);
	if (err)
		goto fail;
	err = klet_image_dynamic(kind, &dynamic);
	if (err)
		goto fail;
	err = klet_image_entry(kind);
	if (err)
		goto fail;
	kind->shared_pages = kvcalloc(kind->nr_pages, sizeof(*kind->shared_pages), GFP_KERNEL);
	err = -ENOMEM;
	if (!kind->shared_pages)
		goto fail;
	for (i = 0; i < kind->nr_segments; i++) {
		const struct klet_image_segment *seg = &kind->segments[i];

		if (seg->flags & PF_W)
			continue;
		for (j = seg->offset >> PAGE_SHIFT; j < PAGE_ALIGN(seg->offset + seg->memsz) >> PAGE_SHIFT; j++) {
			struct page *page = alloc_page(GFP_KERNEL | __GFP_ZERO);

			if (!page)
				goto fail;
			kind->shared_pages[j] = page;
			memcpy(page_address(page), kind->image + ((size_t)j << PAGE_SHIFT), PAGE_SIZE);
		}
	}
	pr_info("kernelet: PIE image loaded: %zu bytes, %zu shared, %zu private per instance, %u relative relocations\n",
		kind->image_size, kind->text_size, kind->data_size, kind->nr_relocs);
	return 0;
fail:
	klet_image_free(kind);
	return err;
}

// Unmap before releasing pages; executable aliases must leave every CPU's TLB.
static void klet_image_stop_locked(struct klet_inst *inst)
{
	unsigned int i;

	if (inst->image_base) {
		vunmap(inst->image_base);
		vm_unmap_aliases();
	}
	if (inst->image_pages)
		for (i = 0; i < inst->kind->nr_pages; i++)
			if (!inst->kind->shared_pages[i] && inst->image_pages[i])
				__free_page(inst->image_pages[i]);
	kvfree(inst->image_pages);
	inst->image_pages = NULL;
	inst->image_base = NULL;
	inst->entry = NULL;
	inst->text_lo = inst->text_hi = 0;
}

// Serialize instance mapping lifetimes with registration and sharing checks.
void klet_image_stop(struct klet_inst *inst)
{
	mutex_lock(&klet_table_lock);
	klet_image_stop_locked(inst);
	mutex_unlock(&klet_table_lock);
}

// Check physical sharing against a live peer before publishing the new mapping.
static int klet_image_check_sharing(struct klet_inst *inst)
{
	struct klet_inst *peer;
	unsigned int slot, i, shared, private;
	int err = 0;

	for (slot = 0; slot < KLET_MAX_SANDBOXES; slot++) {
		peer = klet_sandboxes[slot];
		if (!peer || peer == inst || peer->kind != inst->kind || !peer->image_base)
			continue;
		shared = private = 0;
		if (peer->image_base == inst->image_base) {
			err = -EINVAL;
			break;
		}
		for (i = 0; i < inst->kind->nr_pages; i++) {
			struct page *a = vmalloc_to_page(inst->image_base + ((size_t)i << PAGE_SHIFT));
			struct page *b = vmalloc_to_page(peer->image_base + ((size_t)i << PAGE_SHIFT));

			if (!a || !b || a != inst->image_pages[i] || b != peer->image_pages[i] ||
			    (!!inst->kind->shared_pages[i] != (a == b))) {
				err = -EINVAL;
				break;
			}
			if (a == b)
				shared++;
			else
				private++;
		}
		if (err)
			break;
		pr_info("kernelet: PIE sharing: sandboxes %d and %d: distinct mappings, %u shared pages, %u private pages each\n",
			inst->slot, peer->slot, shared, private);
	}
	return err;
}

// Map an independent instance while preserving the linker's relative layout.
int klet_image_start(struct klet_inst *inst)
{
	struct klet_kind *kind = inst->kind;
	unsigned int i;
	int err = -ENOMEM;

	mutex_lock(&klet_table_lock);
	inst->image_pages = kvcalloc(kind->nr_pages, sizeof(*inst->image_pages), GFP_KERNEL);
	if (!inst->image_pages)
		goto fail;
	for (i = 0; i < kind->nr_pages; i++) {
		if (kind->shared_pages[i]) {
			inst->image_pages[i] = kind->shared_pages[i];
			continue;
		}
		inst->image_pages[i] = alloc_page(GFP_KERNEL_ACCOUNT | __GFP_ZERO);
		if (!inst->image_pages[i])
			goto fail;
		memcpy(page_address(inst->image_pages[i]), kind->image + ((size_t)i << PAGE_SHIFT), PAGE_SIZE);
	}
	inst->image_base = vmap(inst->image_pages, kind->nr_pages, VM_MAP, PAGE_KERNEL_RO);
	if (!inst->image_base)
		goto fail;
	// No new writable alias of the shared code is ever created.
	for (i = 0; i < kind->nr_segments; i++) {
		const struct klet_image_segment *seg = &kind->segments[i];

		if (!(seg->flags & PF_W))
			continue;
		err = set_memory_rw((unsigned long)inst->image_base + seg->offset,
				    PAGE_ALIGN(seg->memsz) >> PAGE_SHIFT);
		if (err)
			goto fail;
	}
	for (i = 0; i < kind->nr_relocs; i++) {
		const struct klet_image_reloc *r = &kind->relocs[i];

		*(u64 *)(inst->image_base + r->offset) = (u64)(unsigned long)inst->image_base + r->addend;
	}
	for (i = 0; i < kind->nr_segments; i++) {
		const struct klet_image_segment *seg = &kind->segments[i];
		unsigned long address = (unsigned long)inst->image_base + seg->offset;
		unsigned int pages = PAGE_ALIGN(seg->memsz) >> PAGE_SHIFT;

		if (seg->flags & PF_W)
			continue;
		err = seg->flags & PF_X ? set_memory_rox(address, pages) : set_memory_ro(address, pages);
		if (err)
			goto fail;
	}
	inst->entry = inst->image_base + kind->entry_offset;
	inst->text_lo = (unsigned long)inst->image_base + kind->text_lo;
	inst->text_hi = (unsigned long)inst->image_base + kind->text_hi;
	err = klet_image_check_sharing(inst);
	if (err)
		goto fail;
	pr_info("kernelet: sandbox %d: PIE mapping [%#lx, %#lx), shared %zu bytes, private %zu bytes\n",
		inst->slot, (unsigned long)inst->image_base,
		(unsigned long)inst->image_base + kind->image_size, kind->text_size, kind->data_size);
	mutex_unlock(&klet_table_lock);
	return 0;
fail:
	klet_image_stop_locked(inst);
	mutex_unlock(&klet_table_lock);
	return err;
}

// Release backing pages only after every instance has been destroyed.
void klet_image_free(struct klet_kind *kind)
{
	unsigned int i;

	if (kind->shared_pages)
		for (i = 0; i < kind->nr_pages; i++) {
			struct page *page = kind->shared_pages[i];

			if (!page)
				continue;
			// Permission changes also protected the direct-map alias.
			if (WARN_ON(set_memory_rw((unsigned long)page_address(page), 1)))
				continue;
			__free_page(page);
		}
	kvfree(kind->shared_pages);
	kvfree(kind->relocs);
	vfree(kind->image);
	memset(kind, 0, sizeof(*kind));
}
