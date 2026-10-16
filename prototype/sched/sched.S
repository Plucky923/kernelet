# SPDX-License-Identifier: MPL-2.0
#
# The sched kernel's tenant program.
#
# No stack is used, because the kernel proper maps none: every instruction here
# runs out of registers only. The kernel proper puts a role in %rdi before the
# first entry to user mode.
#
#   rdi = 0            be CPU-bound and yield through a system call
#   rdi = 1            the same, but measure nothing (the kernel times it)
#   rdi = seed != 0    the floating-point test: keep four distinct values in
#                      xmm0..xmm3 across every trip through the kernel and
#                      report the moment one of them changes
#
# System calls the kernel proper understands (its own numbers, not Linux's):
#   3000  yield: give up the processor
#   3001  fpu check-in: the values in xmm0..3 are still right
#   3002  fpu failure
#   3003  user-space cycle report, rsi = cycles

	.global _start
	.section .text
_start:
	testq	%rdi, %rdi
	jnz	fpu_start

	# --- a plain CPU-bound tenant thread ---------------------------------
cpu_loop:
	movq	$3000, %rax		# yield
	syscall
	movl	$400000, %ecx		# then burn some user time
burn:
	decl	%ecx
	jnz	burn
	jmp	cpu_loop

	# --- the floating-point tenant thread --------------------------------
	# Four distinct values derived from the seed, one per xmm register. If
	# the kernel proper's FpuContext save/load did not work, another thread's
	# values would show up here.
	# r12..r15, not r8..r11: the `syscall` instruction itself puts the return
	# address in rcx and RFLAGS in r11, so r11 cannot hold anything across it.
fpu_start:
	movq	%rdi, %r12		# r12 = seed
	movabsq	$0x1111111111111111, %rax
	movq	%rdi, %r13
	xorq	%rax, %r13
	movabsq	$0x2222222222222222, %rax
	movq	%rdi, %r14
	xorq	%rax, %r14
	movabsq	$0x3333333333333333, %rax
	movq	%rdi, %r15
	xorq	%rax, %r15

	movq	%r12, %xmm0
	movq	%r13, %xmm1
	movq	%r14, %xmm2
	movq	%r15, %xmm3

fpu_loop:
	movq	$3001, %rax		# check in: the kernel switches threads
	syscall

	movq	%xmm0, %rax
	cmpq	%r12, %rax
	jne	fpu_bad
	movq	%xmm1, %rax
	cmpq	%r13, %rax
	jne	fpu_bad
	movq	%xmm2, %rax
	cmpq	%r14, %rax
	jne	fpu_bad
	movq	%xmm3, %rax
	cmpq	%r15, %rax
	jne	fpu_bad

	movl	$20000, %ecx		# burn a little user time between checks
fpu_burn:
	decl	%ecx
	jnz	fpu_burn
	jmp	fpu_loop

fpu_bad:
	movq	$3002, %rax
	movq	%rax, %rsi		# rsi is ignored; rax carries the news
	movq	$3002, %rax
	syscall
	jmp	fpu_bad
