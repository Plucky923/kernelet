/* SPDX-License-Identifier: GPL-2.0 */
/*
 * The low bound of the kernelet image's text.
 *
 * Linked first in the pre-link of image.o, in a section whose name sorts and,
 * more importantly, is *placed* before every `.text.*` of the Rust staticlib,
 * because `ld -r` emits output sections in the order it first meets them and
 * the module loader then lays out MOD_TEXT in section-table order. The eviction
 * sweep uses these two symbols to decide whether an interrupted instruction
 * pointer was inside kernelet code; klet_init() refuses to load the module if
 * they do not actually bracket the image (see klet_check_image_text).
 */
	.section .text.00_klet_image_start, "ax", @progbits
	.globl __klet_image_text_start
	.hidden __klet_image_text_start
__klet_image_text_start:
	nop
