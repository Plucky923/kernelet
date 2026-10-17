/* SPDX-License-Identifier: GPL-2.0 */
/*
 * The coroutine switch.
 *
 * Kernelet code for a carrier runs on a kernelet stack (vmalloc'ed, 256 KiB),
 * not on the carrier's 16 KiB Linux stack. This saves the callee-saved
 * registers, swaps rsp, and restores the other stack's callee-saved registers:
 * a plain SysV-ABI function as far as the compiler is concerned, which happens
 * to return on a different stack.
 *
 * Both stacks belong to the same Linux task, and rsp is valid at every
 * instruction, so being preempted in the middle is harmless.
 *
 * objtool cannot follow this, hence OBJECT_FILES_NON_STANDARD_switch.o in the
 * Kbuild file.
 */

#include <linux/linkage.h>

/* void klet_switch(void **save_sp, void *new_sp) */
SYM_FUNC_START(klet_switch)
	pushq	%rbp
	pushq	%rbx
	pushq	%r12
	pushq	%r13
	pushq	%r14
	pushq	%r15
	movq	%rsp, (%rdi)
	movq	%rsi, %rsp
	popq	%r15
	popq	%r14
	popq	%r13
	popq	%r12
	popq	%rbx
	popq	%rbp
	RET
SYM_FUNC_END(klet_switch)

/*
 * The first thing a fresh coroutine executes. klet_carrier_new() plants this
 * address where klet_switch's `ret` will find it, and the carrier pointer where
 * the `popq %r12` will.
 */
SYM_FUNC_START(klet_coro_trampoline)
	movq	%r12, %rdi
	call	klet_coro_main
	/* klet_coro_main never returns. */
	ud2
SYM_FUNC_END(klet_coro_trampoline)

/*
 * void klet_run_on_linux_stack(void *linux_sp, struct klet_svc_args *args)
 *
 * Runs klet_svc_body(args) on the carrier's Linux stack and comes back. Every
 * service in the table but user_run (which leaves the kernelet stack by itself,
 * through klet_switch) goes through here, stop included, so that no host code
 * ever runs on a kernelet stack.
 *
 * `linux_sp` is where klet_enter's klet_switch parked the Linux stack, i.e. the
 * lowest byte of it that is in use; everything below is free. The call is
 * direct, so no retpoline thunk is needed.
 */
SYM_FUNC_START(klet_run_on_linux_stack)
	pushq	%rbp
	movq	%rsp, %rbp
	movq	%rdi, %rsp
	andq	$-16, %rsp
	movq	%rsi, %rdi
	call	klet_svc_body
	movq	%rbp, %rsp
	popq	%rbp
	RET
SYM_FUNC_END(klet_run_on_linux_stack)

/*
 * The eviction exit stub.
 *
 * The sweep's hrtimer callback points the interrupted regs->ip here, so this is
 * entered by the interrupt's own `iret`, on the kernelet stack, at whatever rsp
 * the kernelet happened to have. Realign and make the ordinary switch back to
 * the carrier's Linux stack, never to return.
 */
SYM_FUNC_START(klet_exit_stub)
	andq	$-16, %rsp
	call	klet_evict_leave
	/* klet_evict_leave never returns. */
	ud2
SYM_FUNC_END(klet_exit_stub)

/*
 * The yield stub.
 *
 * The watch timer points the interrupted regs->ip here when kernelet code
 * has been running long enough that Linux wants the CPU back and the kernel it is
 * running on will not take it: so this is entered by the interrupt's own `iret`,
 * on the kernelet stack, at an arbitrary instruction boundary in kernelet code,
 * and it has to look like nothing happened.
 *
 * That means every general register *and* RFLAGS must come back untouched, which
 * is why the flags are pushed first and the return address is a slot reserved
 * before them: the last two instructions are `popfq; ret`, and neither touches a
 * register or a flag that the interrupted code can see. The slot is reserved
 * with `leaq`, which writes no flag; a `subq` there would change the arithmetic
 * flags before `pushfq` saves them, and kernelet code interrupted between a
 * compare and the branch that reads it would resume with the wrong result.
 *
 * Kernel code has no red zone, so pushing below the interrupted rsp is safe, and
 * the alignment of that rsp is unknown, so rsp is aligned for the call out of
 * %rbp (already saved) and restored from it afterwards.
 *
 * Stack, with S the rsp the interrupt returned with:
 *
 *   S-8    return address slot, filled in with the saved ip
 *   S-16   RFLAGS
 *   S-24 .. S-136   rax rcx rdx rbx rbp rsi rdi r8 r9 r10 r11 r12 r13 r14 r15
 */
SYM_FUNC_START(klet_yield_stub)
	leaq	-8(%rsp), %rsp		/* the return address slot; not subq, see above */
	pushfq
	pushq	%rax
	pushq	%rcx
	pushq	%rdx
	pushq	%rbx
	pushq	%rbp
	pushq	%rsi
	pushq	%rdi
	pushq	%r8
	pushq	%r9
	pushq	%r10
	pushq	%r11
	pushq	%r12
	pushq	%r13
	pushq	%r14
	pushq	%r15

	movq	%rsp, %rbp		/* rbp is saved above, so it is scratch now */
	andq	$-16, %rsp
	call	klet_yield_body		/* 0: leave for good; else the ip to resume */
	movq	%rbp, %rsp

	testq	%rax, %rax
	jz	.Lklet_yield_leave
	movq	%rax, 128(%rsp)		/* the return address slot at S-8 */

	popq	%r15
	popq	%r14
	popq	%r13
	popq	%r12
	popq	%r11
	popq	%r10
	popq	%r9
	popq	%r8
	popq	%rdi
	popq	%rsi
	popq	%rbp
	popq	%rbx
	popq	%rdx
	popq	%rcx
	popq	%rax
	popfq
	ret

.Lklet_yield_leave:
	/* The kernelet died while we were away. Do not go back. */
	call	klet_evict_leave
	ud2
SYM_FUNC_END(klet_yield_stub)
