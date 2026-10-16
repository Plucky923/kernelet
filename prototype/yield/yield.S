# SPDX-License-Identifier: MPL-2.0
#
# The yield kernel's tenant program: ask the kernel proper for a long
# computation, then exit. It touches no memory beyond its own text, which the
# kernel proper maps before the first entry to user mode.

	.global _start
	.section .text
_start:
	movq	$2000, %rax		# the kernel proper's "compute" call
	syscall
	movq	$60, %rax		# exit
	xorq	%rdi, %rdi
	syscall
