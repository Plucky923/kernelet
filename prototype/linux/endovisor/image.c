// SPDX-License-Identifier: GPL-2.0
/*
 * The kernelet image loader: KLET_KIND_REGISTER's half that turns a file into
 * a kind.
 *
 * An image is an ELF relocatable object for x86-64 (ET_REL), the `ld -r` of
 * the kernel proper and vOSTD, built with `relocation-model=static` and
 * `code-model=kernel`. Loading it is what the module loader does for a module,
 * with three differences: every symbol is resolved within the image itself
 * (an undefined symbol is refused, so an image can name nothing of Linux's);
 * the one symbol looked up is kernelet_entry_table, which must be the image's
 * only global symbol; and nothing in it is run at load.
 *
 *  - Every SHF_ALLOC section is laid out: the executable ones first and the
 *    read-only ones after them, in one allocation from execmem's module
 *    range (EXECMEM_MODULE_TEXT), and the writable ones and the bss in a
 *    second (EXECMEM_MODULE_DATA). code-model=kernel puts every address the
 *    image's code forms in the top 2 GiB (R_X86_64_32S), which is where the
 *    module range is, and the two allocations are within 2 GiB of each other
 *    for the PC-relative relocations; each relocation checks that its value
 *    fits, as arch/x86/kernel/module.c does.
 *  - The relocations are applied as apply_relocate_add() applies them, for
 *    the kinds the build emits: R_X86_64_NONE, 64, 32, 32S, PC32, PLT32 and
 *    PC64. Any other kind, a REL section against a loaded section, a TLS or
 *    common symbol, or a constructor section is refused (ENOEXEC).
 *  - The text is made read-only and executable (set_memory_rox()); the data
 *    stays writable and non-executable. A copy of the writable data as
 *    relocated is kept, pristine: the image is position-dependent, its text
 *    reaches its data at the addresses fixed here, so one loaded copy serves
 *    one sandbox at a time, and every sandbox of the kind starts from that
 *    copy (klet_image_restore), with the bss zeroed.
 *
 * execmem_alloc(), execmem_free() and set_memory_rox() are not exported to
 * modules in v6.12; the patch exports them.
 */

#include <linux/elf.h>
#include <linux/execmem.h>
#include <linux/kernel.h>
#include <linux/mm.h>
#include <linux/overflow.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/vmalloc.h>

#include <asm/set_memory.h>

#include "kernelet.h"

/* Not in Linux's elf.h: the ELF specification's values. */
#ifndef SHF_TLS
#define SHF_TLS			0x400
#endif
#ifndef SHT_X86_64_UNWIND
#define SHT_X86_64_UNWIND	0x70000001
#endif

struct klet_loader {
	const u8 *buf;
	size_t len;
	const Elf64_Ehdr *eh;
	const Elf64_Shdr *sh;
	unsigned int shnum;
	const Elf64_Sym *sym;
	unsigned int nsym, symtab;
	const char *str;
	size_t strsz;
	/* Where each section went: 0 if it is not loaded. */
	unsigned long *addr;
	/* Its offset in its region, during the layout. */
	size_t *off;
	unsigned int nr_relocs;
};

static bool klet_sec_alloc(const Elf64_Shdr *s)
{
	return (s->sh_flags & SHF_ALLOC) && s->sh_size;
}

static bool klet_sec_exec(const Elf64_Shdr *s)
{
	return s->sh_flags & SHF_EXECINSTR;
}

static bool klet_sec_write(const Elf64_Shdr *s)
{
	return s->sh_flags & SHF_WRITE;
}

/* The checks on the headers: everything later indexes through them. */
static int klet_image_check(struct klet_loader *l)
{
	const Elf64_Ehdr *eh = (const Elf64_Ehdr *)l->buf;
	size_t sh_end;
	unsigned int i;

	if (l->len < sizeof(*eh) || memcmp(eh->e_ident, ELFMAG, SELFMAG) != 0 ||
	    eh->e_ident[EI_CLASS] != ELFCLASS64 ||
	    eh->e_ident[EI_DATA] != ELFDATA2LSB || eh->e_type != ET_REL ||
	    eh->e_machine != EM_X86_64 ||
	    eh->e_shentsize != sizeof(Elf64_Shdr) || eh->e_shnum == 0 ||
	    eh->e_shnum >= SHN_LORESERVE) {
		pr_err("kernelet: image: not an x86-64 ELF relocatable object\n");
		return -ENOEXEC;
	}
	if (check_mul_overflow((size_t)eh->e_shnum, sizeof(Elf64_Shdr), &sh_end) ||
	    check_add_overflow(sh_end, (size_t)eh->e_shoff, &sh_end) ||
	    sh_end > l->len) {
		pr_err("kernelet: image: section headers outside the file\n");
		return -ENOEXEC;
	}
	l->eh = eh;
	l->sh = (const Elf64_Shdr *)(l->buf + eh->e_shoff);
	l->shnum = eh->e_shnum;

	for (i = 0; i < l->shnum; i++) {
		const Elf64_Shdr *s = &l->sh[i];
		size_t end;

		if (s->sh_type != SHT_NOBITS &&
		    (check_add_overflow((size_t)s->sh_offset, (size_t)s->sh_size, &end) ||
		     end > l->len)) {
			pr_err("kernelet: image: section %u outside the file\n", i);
			return -ENOEXEC;
		}
		if (s->sh_addralign > PAGE_SIZE ||
		    (s->sh_addralign && !is_power_of_2(s->sh_addralign))) {
			pr_err("kernelet: image: section %u has alignment %llu\n", i,
			       s->sh_addralign);
			return -ENOEXEC;
		}
		if (s->sh_type == SHT_SYMTAB) {
			if (l->sym || s->sh_entsize != sizeof(Elf64_Sym) ||
			    s->sh_link >= l->shnum ||
			    l->sh[s->sh_link].sh_type != SHT_STRTAB) {
				pr_err("kernelet: image: a second or malformed symbol table\n");
				return -ENOEXEC;
			}
			l->sym = (const Elf64_Sym *)(l->buf + s->sh_offset);
			l->nsym = s->sh_size / sizeof(Elf64_Sym);
			l->symtab = i;
			l->str = (const char *)(l->buf + l->sh[s->sh_link].sh_offset);
			l->strsz = l->sh[s->sh_link].sh_size;
		}
		if (!klet_sec_alloc(s))
			continue;
		/* Nothing in an image runs at load, so nothing may ask to. */
		if (s->sh_flags & SHF_TLS) {
			pr_err("kernelet: image: section %u is thread-local\n", i);
			return -ENOEXEC;
		}
		switch (s->sh_type) {
		case SHT_PROGBITS:
		case SHT_NOBITS:
		case SHT_NOTE:
		case SHT_X86_64_UNWIND:
			break;
		default:
			pr_err("kernelet: image: loaded section %u of type %u (constructors?)\n",
			       i, s->sh_type);
			return -ENOEXEC;
		}
	}
	if (!l->sym || !l->strsz || l->str[l->strsz - 1] != '\0') {
		pr_err("kernelet: image: no usable symbol table\n");
		return -ENOEXEC;
	}
	return 0;
}

/* Lays out one region: the sections @pick selects, each at its alignment. */
static size_t klet_layout(struct klet_loader *l, int pick, size_t off)
{
	unsigned int i;

	for (i = 0; i < l->shnum; i++) {
		const Elf64_Shdr *s = &l->sh[i];
		int what;

		if (!klet_sec_alloc(s))
			continue;
		what = klet_sec_write(s) ? 2 : klet_sec_exec(s) ? 0 : 1;
		if (what != pick)
			continue;
		off = ALIGN(off, s->sh_addralign ? s->sh_addralign : 1);
		l->off[i] = off;
		off += s->sh_size;
	}
	return off;
}

/* Places every loaded section of one region at base + its offset, and copies it in. */
static void klet_place(struct klet_loader *l, bool writable, void *base)
{
	unsigned int i;

	for (i = 0; i < l->shnum; i++) {
		const Elf64_Shdr *s = &l->sh[i];

		if (!klet_sec_alloc(s) || klet_sec_write(s) != writable)
			continue;
		l->addr[i] = (unsigned long)base + l->off[i];
		if (s->sh_type != SHT_NOBITS)
			memcpy((void *)l->addr[i], l->buf + s->sh_offset, s->sh_size);
	}
}

/* A symbol's address, or 0 if it is not one an image may refer to. */
static int klet_sym_value(struct klet_loader *l, unsigned int idx, u64 *val)
{
	const Elf64_Sym *sym;

	if (idx == 0 || idx >= l->nsym)
		return -ENOEXEC;
	sym = &l->sym[idx];
	if (sym->st_shndx == SHN_UNDEF) {
		pr_err("kernelet: image: undefined symbol %s\n",
		       sym->st_name < l->strsz ? l->str + sym->st_name : "?");
		return -ENOEXEC;
	}
	if (sym->st_shndx == SHN_ABS) {
		*val = sym->st_value;
		return 0;
	}
	if (sym->st_shndx >= l->shnum || !l->addr[sym->st_shndx]) {
		pr_err("kernelet: image: symbol %u in section %u, which is not loaded\n",
		       idx, sym->st_shndx);
		return -ENOEXEC;
	}
	*val = l->addr[sym->st_shndx] + sym->st_value;
	return 0;
}

/* One RELA section against a loaded section, as apply_relocate_add() applies it. */
static int klet_relocate(struct klet_loader *l, const Elf64_Shdr *rs)
{
	const Elf64_Shdr *target = &l->sh[rs->sh_info];
	const Elf64_Rela *rel = (const Elf64_Rela *)(l->buf + rs->sh_offset);
	unsigned int i, n = rs->sh_size / sizeof(*rel);
	unsigned long base = l->addr[rs->sh_info];

	if (rs->sh_entsize != sizeof(*rel) || rs->sh_link != l->symtab)
		return -ENOEXEC;
	for (i = 0; i < n; i++) {
		u32 type = ELF64_R_TYPE(rel[i].r_info);
		unsigned int width;
		void *loc;
		u64 val;
		int err;

		switch (type) {
		case R_X86_64_NONE:
			continue;
		case R_X86_64_64:
		case R_X86_64_PC64:
			width = 8;
			break;
		case R_X86_64_32:
		case R_X86_64_32S:
		case R_X86_64_PC32:
		case R_X86_64_PLT32:
			width = 4;
			break;
		default:
			pr_err("kernelet: image: relocation of kind %u, which the loader does not apply\n",
			       type);
			return -ENOEXEC;
		}
		if (rel[i].r_offset > target->sh_size ||
		    target->sh_size - rel[i].r_offset < width)
			return -ENOEXEC;
		err = klet_sym_value(l, ELF64_R_SYM(rel[i].r_info), &val);
		if (err)
			return err;
		loc = (void *)(base + rel[i].r_offset);
		val += rel[i].r_addend;

		switch (type) {
		case R_X86_64_64:
			*(u64 *)loc = val;
			break;
		case R_X86_64_32:
			if (val != (u32)val)
				goto overflow;
			*(u32 *)loc = val;
			break;
		case R_X86_64_32S:
			if ((s64)val != (s32)val)
				goto overflow;
			*(s32 *)loc = val;
			break;
		case R_X86_64_PC32:
		case R_X86_64_PLT32:
			val -= (u64)loc;
			if ((s64)val != (s32)val)
				goto overflow;
			*(s32 *)loc = val;
			break;
		case R_X86_64_PC64:
			val -= (u64)loc;
			*(u64 *)loc = val;
			break;
		}
		l->nr_relocs++;
		continue;
overflow:
		pr_err("kernelet: image: relocation %u of kind %u overflows (value %#llx at %px)\n",
		       i, type, val, loc);
		return -ENOEXEC;
	}
	return 0;
}

/*
 * The one global symbol, kernelet_entry_table: an image exports nothing else,
 * and refers to nothing it does not define.
 */
static int klet_find_entry(struct klet_loader *l, const struct klet_entry_table **entry)
{
	const Elf64_Sym *found = NULL;
	unsigned int i, globals = 0;
	u64 val;
	int err;

	for (i = 1; i < l->nsym; i++) {
		const Elf64_Sym *sym = &l->sym[i];
		unsigned int bind = ELF64_ST_BIND(sym->st_info);

		if (sym->st_name >= l->strsz)
			return -ENOEXEC;
		if (sym->st_shndx == SHN_UNDEF) {
			pr_err("kernelet: image: undefined symbol %s\n", l->str + sym->st_name);
			return -ENOEXEC;
		}
		if (sym->st_shndx == SHN_COMMON) {
			pr_err("kernelet: image: common symbol %s\n", l->str + sym->st_name);
			return -ENOEXEC;
		}
		if (bind != STB_GLOBAL && bind != STB_WEAK)
			continue;
		globals++;
		if (strcmp(l->str + sym->st_name, "kernelet_entry_table") == 0)
			found = sym;
	}
	if (!found || globals != 1 || ELF64_ST_TYPE(found->st_info) != STT_OBJECT ||
	    found->st_size < sizeof(struct klet_entry_table)) {
		pr_err("kernelet: image: %u global symbol(s); the one allowed is kernelet_entry_table, %s\n",
		       globals, found ? "malformed" : "missing");
		return -ENOEXEC;
	}
	err = klet_sym_value(l, found - l->sym, &val);
	if (err)
		return err;
	*entry = (const struct klet_entry_table *)(unsigned long)val;
	return 0;
}

int klet_image_load(struct klet_kind *kind, const void *buf, size_t len)
{
	struct klet_loader l = { .buf = buf, .len = len };
	const struct klet_entry_table *entry = NULL;
	size_t text_end, ro_end, data_end;
	void *text = NULL, *data = NULL, *pristine = NULL;
	unsigned int i;
	int err;

	err = klet_image_check(&l);
	if (err)
		return err;
	l.addr = kvcalloc(l.shnum, sizeof(*l.addr), GFP_KERNEL);
	l.off = kvcalloc(l.shnum, sizeof(*l.off), GFP_KERNEL);
	err = -ENOMEM;
	if (!l.addr || !l.off)
		goto out;

	/* Text, then read-only data after it; the writable data on its own. */
	text_end = klet_layout(&l, 0, 0);
	ro_end = klet_layout(&l, 1, text_end);
	data_end = klet_layout(&l, 2, 0);
	err = -ENOEXEC;
	if (!text_end) {
		pr_err("kernelet: image: no executable section\n");
		goto out;
	}
	err = -ENOMEM;
	text = execmem_alloc(EXECMEM_MODULE_TEXT, PAGE_ALIGN(ro_end));
	if (!text)
		goto out;
	memset(text, 0, PAGE_ALIGN(ro_end));
	if (data_end) {
		data = execmem_alloc(EXECMEM_MODULE_DATA, PAGE_ALIGN(data_end));
		pristine = vmalloc(PAGE_ALIGN(data_end));
		if (!data || !pristine)
			goto out;
		memset(data, 0, PAGE_ALIGN(data_end));
	}
	klet_place(&l, false, text);
	if (data)
		klet_place(&l, true, data);

	for (i = 0; i < l.shnum; i++) {
		const Elf64_Shdr *rs = &l.sh[i];

		if (rs->sh_type != SHT_RELA && rs->sh_type != SHT_REL)
			continue;
		if (rs->sh_info >= l.shnum) {
			err = -ENOEXEC;
			goto out;
		}
		if (!l.addr[rs->sh_info])
			continue;	/* against a section that is not loaded: debug info */
		if (rs->sh_type == SHT_REL) {
			pr_err("kernelet: image: a REL section; x86-64 uses RELA\n");
			err = -ENOEXEC;
			goto out;
		}
		err = klet_relocate(&l, rs);
		if (err)
			goto out;
	}

	err = klet_find_entry(&l, &entry);
	if (err)
		goto out;
	if (entry->abi_version != KLET_ABI_VERSION) {
		pr_err("kernelet: image ABI %llu, endovisor ABI %llu\n",
		       entry->abi_version, KLET_ABI_VERSION);
		err = -EPROTO;
		goto out;
	}
	kind->text_lo = (unsigned long)text;
	kind->text_hi = (unsigned long)text + text_end;
	if (!klet_in_kernelet_text(kind, (unsigned long)entry->kernelet_entry) ||
	    !klet_in_kernelet_text(kind, (unsigned long)entry->vcpu_entry) ||
	    !klet_in_kernelet_text(kind, (unsigned long)entry->virq_entry)) {
		pr_err("kernelet: image: an entry point outside the image's text\n");
		err = -ENOEXEC;
		goto out;
	}

	if (data)
		memcpy(pristine, data, PAGE_ALIGN(data_end));
	err = set_memory_rox((unsigned long)text, PAGE_ALIGN(ro_end) >> PAGE_SHIFT);
	if (err)
		goto out;

	kind->text = text;
	kind->text_size = PAGE_ALIGN(ro_end);
	kind->data = data;
	kind->data_size = data ? PAGE_ALIGN(data_end) : 0;
	kind->pristine = pristine;
	kind->entry = entry;
	pr_info("kernelet: image loaded: %zu bytes of text at %px, %zu of read-only data, %zu of data and bss at %px, %u relocations applied\n",
		text_end, text, ro_end - text_end, data_end, data, l.nr_relocs);
	text = data = pristine = NULL;
	err = 0;
out:
	if (text)
		execmem_free(text);
	if (data)
		execmem_free(data);
	vfree(pristine);
	kvfree(l.addr);
	kvfree(l.off);
	return err;
}

void klet_image_free(struct klet_kind *kind)
{
	/* execmem's allocations reset their permissions when freed (VM_FLUSH_RESET_PERMS). */
	if (kind->text)
		execmem_free(kind->text);
	if (kind->data)
		execmem_free(kind->data);
	vfree(kind->pristine);
	kind->text = kind->data = kind->pristine = NULL;
	kind->entry = NULL;
	kind->text_lo = kind->text_hi = 0;
}

/* Every sandbox of the kind starts from the data as it was loaded: no kernelet code runs. */
void klet_image_restore(struct klet_kind *kind)
{
	if (kind->data)
		memcpy(kind->data, kind->pristine, kind->data_size);
}
