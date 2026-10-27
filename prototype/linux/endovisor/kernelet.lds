/* SPDX-License-Identifier: GPL-2.0 */
/* The freestanding PIE layout consumed by the endovisor. */
/*  */
/* All load segments have fixed, page-aligned offsets from the image base. */
/* Code and read-only data can share physical pages across mappings; */
/* writable data, including relocated pointers, belongs to each sandbox. */
OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(kernelet_entry_table)

PHDRS
{
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
    rodata PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
    dynamic PT_DYNAMIC FLAGS(6);
}

SECTIONS
{
    . = SIZEOF_HEADERS;
    .text : { *(.text .text.*) } :text

    . = ALIGN(4096);
    .rodata : { *(.rodata .rodata.*) } :rodata
    .eh_frame : { *(.eh_frame) } :rodata
    .eh_frame_hdr : { *(.eh_frame_hdr) } :rodata
    .dynsym : { *(.dynsym) } :rodata
    .dynstr : { *(.dynstr) } :rodata
    .hash : { *(.hash) } :rodata
    .gnu.hash : { *(.gnu.hash) } :rodata
    .rela.dyn : { *(.rela.*) } :rodata

    . = ALIGN(4096);
    .data.rel.ro : { *(.data.rel.ro .data.rel.ro.*) } :data
    .dynamic : { *(.dynamic) } :data :dynamic
    .got : { *(.got .got.*) } :data
    .data : { *(.data .data.*) } :data
    .bss (NOLOAD) : { *(.bss .bss.*) *(COMMON) } :data

    /* Keep unsupported sections so that garbage collection cannot hide them. */
    .unsupported : {
        KEEP(*(.tdata .tdata.* .tbss .tbss.*))
        KEEP(*(.preinit_array .preinit_array.* .init_array .init_array.*))
        KEEP(*(.fini_array .fini_array.* .ctors .ctors.* .dtors .dtors.*))
        KEEP(*(.init .fini))
    } :data
    ASSERT(SIZEOF(.unsupported) == 0, "kernelet images do not support TLS or constructors")
    ASSERT(. <= 0x1000000, "kernelet image exceeds the 16 MiB virtual span limit")

    /DISCARD/ : { *(.comment .note.GNU-stack .debug* .zdebug* .llvm*) }
}
