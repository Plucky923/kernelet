# SPDX-License-Identifier: MPL-2.0
#
# The mem kernel's tenant program: a command loop. The kernel proper puts a
# command in rdi and its arguments in rsi (base address), rdx (pages), r8 (a
# seed or a cycle count) and r9 (a results array, or 0), returns from the
# report system call, and the program runs the command and reports its result
# in rdi with system call 3100.
#
# Every timed access is bracketed by lfence; rdtsc, so the per-page cycle count
# a command writes into the results array includes whatever the access cost:
# a TLB miss and walk, or a Linux fault and everything behind it.

	.global _start
	.section .text
_start:
dispatch:
	cmpq	$1, %rdi
	je	touch_read
	cmpq	$2, %rdi
	je	touch_write
	cmpq	$3, %rdi
	je	check
	cmpq	$4, %rdi
	je	spin_wait
	cmpq	$5, %rdi
	je	read_one
	cmpq	$6, %rdi
	je	write_one
	movq	$-1, %rbx
	jmp	report

# 1: read one qword of each page, timed per page.
touch_read:
	movq	%rdx, %r12
	xorq	%r13, %r13
	xorq	%rbx, %rbx
1:	cmpq	%r12, %r13
	jae	report
	movq	%r13, %r15
	shlq	$12, %r15
	addq	%rsi, %r15
	lfence
	rdtsc
	shlq	$32, %rdx
	orq	%rax, %rdx
	movq	%rdx, %r14
	movq	(%r15), %rax		# the touch
	addq	%rax, %rbx
	lfence
	rdtsc
	shlq	$32, %rdx
	orq	%rax, %rdx
	subq	%r14, %rdx
	testq	%r9, %r9
	jz	2f
	movq	%rdx, (%r9,%r13,8)
2:	incq	%r13
	jmp	1b

# 2: write seed+i at offsets 0, 2048 and 4088 of page i, the first timed.
touch_write:
	movq	%rdx, %r12
	xorq	%r13, %r13
	xorq	%rbx, %rbx
1:	cmpq	%r12, %r13
	jae	report
	movq	%r13, %r15
	shlq	$12, %r15
	addq	%rsi, %r15
	movq	%r8, %r10
	addq	%r13, %r10
	lfence
	rdtsc
	shlq	$32, %rdx
	orq	%rax, %rdx
	movq	%rdx, %r14
	movq	%r10, (%r15)		# the touch
	mfence
	rdtsc
	shlq	$32, %rdx
	orq	%rax, %rdx
	subq	%r14, %rdx
	movq	%r10, 2048(%r15)
	movq	%r10, 4088(%r15)
	testq	%r9, %r9
	jz	2f
	movq	%rdx, (%r9,%r13,8)
2:	incq	%r13
	jmp	1b

# 3: count the pages whose three qwords are not seed+i.
check:
	movq	%rdx, %r12
	xorq	%r13, %r13
	xorq	%rbx, %rbx
1:	cmpq	%r12, %r13
	jae	report
	movq	%r13, %r15
	shlq	$12, %r15
	addq	%rsi, %r15
	movq	%r8, %r10
	addq	%r13, %r10
	cmpq	%r10, (%r15)
	jne	3f
	cmpq	%r10, 2048(%r15)
	jne	3f
	cmpq	%r10, 4088(%r15)
	je	2f
3:	incq	%rbx
2:	incq	%r13
	jmp	1b

# 4: spin for r8 cycles in user mode.
spin_wait:
	lfence
	rdtsc
	shlq	$32, %rdx
	orq	%rax, %rdx
	movq	%rdx, %r14
1:	pause
	rdtsc
	shlq	$32, %rdx
	orq	%rax, %rdx
	subq	%r14, %rdx
	cmpq	%r8, %rdx
	jb	1b
	xorq	%rbx, %rbx
	jmp	report

# 5: one read. The kernel proper may answer a fault on it by stepping rip over
# the three bytes of the load and putting a marker in rax.
read_one:
	.byte	0x48, 0x8b, 0x06	# movq (%rsi), %rax
	movq	%rax, %rbx
	jmp	report

# 6: one write of r8, the same way.
write_one:
	.byte	0x4c, 0x89, 0x06	# movq %r8, (%rsi)
	xorq	%rbx, %rbx
	jmp	report

report:
	movq	%rbx, %rdi
	movq	$3100, %rax
	syscall
	jmp	dispatch
