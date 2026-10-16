/* SPDX-License-Identifier: GPL-2.0 */
/* The high bound of the kernelet image's text. See image_start.S. */
	.section .text.zz_klet_image_end, "ax", @progbits
	.globl __klet_image_text_end
	.hidden __klet_image_text_end
__klet_image_text_end:
	nop
