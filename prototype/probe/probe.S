# SPDX-License-Identifier: MPL-2.0
#
# The probe kernel's tenant program. No stack is used, because the kernel proper
# maps none: every page this program touches beyond its own text is a deliberate
# demand-paging fault.

	.global _start
	.section .text
_start:
	# 1. Demand paging. 0x900000 is a page the kernel has not mapped.
	movq	$0x900000, %rbx
	movabsq	$0x4b4f2d45424f5250, %rax	# "PROBE-OK", little-endian
	movq	%rax, (%rbx)			# -> page fault, then retried
	movq	(%rbx), %rcx			# read it back
	movq	%rcx, 8(%rbx)			# store the copy, same page
	movq	$1, %rax			# write(1, 0x900008, 8)
	movq	$1, %rdi
	leaq	8(%rbx), %rsi
	movq	$8, %rdx
	syscall

	# 2. A non-page-fault exception: Linux turns #UD into SIGILL, and the
	#    gate's resume hook must hand it to the kernel proper as trap 6.
	#    The kernel proper advances rip by these two bytes.
	ud2

	# 2a. The same fault again, at once. The endovisor ignores SIGILL, as
	#     every signal; Linux un-ignores it to force the first one, and the
	#     drain ignores it again, so this one is forced, and handed over as
	#     trap 6, in exactly the same way.
	ud2

	# 2b. A breakpoint: Linux turns #BP into SIGTRAP with SI_KERNEL, which
	#     the resume hook must also hand over, as trap 3. int3 is a trap, so
	#     rip is already past it and the kernel proper changes nothing.
	int3

	# 2c. A general-protection fault: hlt is privileged, so user mode gets
	#     #GP, which Linux turns into SIGSEGV with SI_KERNEL, handed over as
	#     trap 13. A fault: rip is still at the hlt, and the kernel proper
	#     steps over its one byte.
	hlt

	# 3. A system call whose handler spins inside the kernelet for ever, so
	#    that the only way to get the CPU back is eviction.
	movq	$1000, %rax
	syscall

	# Not reached.
	movq	$60, %rax
	xorq	%rdi, %rdi
	syscall
