
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-debug-assertions.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000079d240 <first_user_task_entry>:
  79d240:	endbr64
  79d244:	push   %rbp
  79d245:	push   %r15
  79d247:	push   %r14
  79d249:	push   %r12
  79d24b:	push   %rbx
  79d24c:	sub    $0xe0,%rsp
  79d253:	call   7a0390 <ostd::task::processor::after_switching_to>
  79d258:	jmp    22ad9e <__kernelet_cpu_access_start+0x2ab7d>
  79d25d:	xor    %ebx,%ebx
  79d25f:	test   %r15d,%r15d
  79d262:	sete   %bpl
  79d266:	jmp    22adda <__kernelet_cpu_access_start+0x2abb9>
  79d26b:	mov    %r12,0x18(%rsp)
  79d270:	mov    %rdx,0x20(%rsp)
  79d275:	lea    0x18(%rsp),%rdi
  79d27a:	call   79e560 <<ostd::task::Task>::current_with>
  79d27f:	mov    %rax,%r14
  79d282:	test   %rax,%rax
  79d285:	je     79d3b8 <first_user_task_entry+0x178>
  79d28b:	mov    0x462d96(%rip),%rax        # c00028 <_DYNAMIC+0x1d09b8>
  79d292:	mov    (%rax),%rax
  79d295:	test   %rax,%rax
  79d298:	je     79d3d5 <first_user_task_entry+0x195>
  79d29e:	mov    0x58(%r12),%ecx
  79d2a3:	mov    0x8f0(%rax),%edx
  79d2a9:	movzwl 0x3a(%rax),%esi
  79d2ad:	lea    (%rsi,%rsi,2),%rsi
  79d2b1:	shl    $0x6,%esi
  79d2b4:	shl    $0x6,%rcx
  79d2b8:	add    %rax,%rdx
  79d2bb:	add    %rsi,%rdx
  79d2be:	mov    (%rcx,%rdx,1),%rbx
  79d2c2:	test   %r15d,%r15d
  79d2c5:	jne    79d2cc <first_user_task_entry+0x8c>
  79d2c7:	call   79c0d0 <ostd::arch::irq::ops::enable_local>
  79d2cc:	mov    %r14,0x10(%rsp)
  79d2d1:	cmpb   $0x0,0x9b(%r14)
  79d2d9:	je     79d3ef <first_user_task_entry+0x1af>
  79d2df:	test   %rbx,%rbx
  79d2e2:	je     79d3ff <first_user_task_entry+0x1bf>
  79d2e8:	mov    0x60(%r14),%r14
  79d2ec:	movq   $0x1,0x18(%rsp)
  79d2f5:	mov    %rbx,0x20(%rsp)
  79d2fa:	movq   $0xffffffffffffffff,0xc8(%rsp)
  79d306:	mov    (%r14),%rdi
  79d309:	add    $0x10,%rdi
  79d30d:	lea    0x10(%rsp),%rsi
  79d312:	lea    0x18(%rsp),%rdx
  79d317:	call   3139d0 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::init>
  79d31c:	mov    (%r14),%rdi
  79d31f:	add    $0x10,%rdi
  79d323:	lea    0x10(%rsp),%rsi
  79d328:	call   313480 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::should_exit>
  79d32d:	test   %al,%al
  79d32f:	je     79d33b <first_user_task_entry+0xfb>
  79d331:	call   79fdc0 <ostd::task::exit_current_task>
  79d336:	jmp    79d45a <first_user_task_entry+0x21a>
  79d33b:	jmp    22ae0d <__kernelet_cpu_access_start+0x2abec>
  79d340:	mov    0x50(%rdx),%eax
  79d343:	mov    %eax,0xc(%rsp)
  79d347:	test   %eax,%eax
  79d349:	jne    79d419 <first_user_task_entry+0x1d9>
  79d34f:	lea    0x4a57a2(%rip),%rdi        # c42af8 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.22.llvm.11761605922429748139+0x18>
  79d356:	call   7a6810 <ostd::task::scheduler::might_preempt>
  79d35b:	jmp    22ae3c <__kernelet_cpu_access_start+0x2ac1b>
  79d360:	test   %edx,%edx
  79d362:	sete   0xc(%rsp)
  79d367:	lea    0x18(%rsp),%rdi
  79d36c:	mov    %rbx,%rsi
  79d36f:	call   7b6d20 <<ostd::arch::cpu::context::UserContext>::sync_to_frame>
  79d374:	lea    0x10(%rsp),%rsi
  79d379:	lea    0xc(%rsp),%rdx
  79d37e:	call   313630 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::pre_user_run>
  79d383:	mov    0x462cd6(%rip),%rax        # c00060 <_DYNAMIC+0x1d09f0>
  79d38a:	mov    (%rax),%rax
  79d38d:	test   %rax,%rax
  79d390:	je     79d442 <first_user_task_entry+0x202>
  79d396:	xor    %edi,%edi
  79d398:	call   *0x68(%rax)
  79d39b:	lea    0x1072d3(%rip),%rdi        # 8a4675 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.20.llvm.11761605922429748139+0x31>
  79d3a2:	lea    0x4a5767(%rip),%rdx        # c42b10 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.22.llvm.11761605922429748139+0x30>
  79d3a9:	mov    $0xb3,%esi
  79d3ae:	call   768ac0 <core::panicking::panic_fmt>
  79d3b3:	jmp    79d45a <first_user_task_entry+0x21a>
  79d3b8:	lea    0x10781a(%rip),%rdi        # 8a4bd9 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.67.llvm.11761605922429748139+0x15c>
  79d3bf:	lea    0x4a5a2a(%rip),%rdx        # c42df0 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.70.llvm.11761605922429748139+0x88>
  79d3c6:	mov    $0x2d,%esi
  79d3cb:	call   770970 <core::option::expect_failed>
  79d3d0:	jmp    79d45a <first_user_task_entry+0x21a>
  79d3d5:	lea    0x1075a5(%rip),%rdi        # 8a4981 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.62.llvm.11761605922429748139>
  79d3dc:	lea    0x4a593d(%rip),%rdx        # c42d20 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.63.llvm.11761605922429748139>
  79d3e3:	mov    $0x4d,%esi
  79d3e8:	call   768ac0 <core::panicking::panic_fmt>
  79d3ed:	jmp    79d45a <first_user_task_entry+0x21a>
  79d3ef:	lea    0x4a5a12(%rip),%rdx        # c42e08 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.70.llvm.11761605922429748139+0xa0>
  79d3f6:	lea    0x107809(%rip),%rdi        # 8a4c06 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.67.llvm.11761605922429748139+0x189>
  79d3fd:	jmp    79d40d <first_user_task_entry+0x1cd>
  79d3ff:	lea    0x4a5a1a(%rip),%rdx        # c42e20 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.70.llvm.11761605922429748139+0xb8>
  79d406:	lea    0x107821(%rip),%rdi        # 8a4c2e <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.67.llvm.11761605922429748139+0x1b1>
  79d40d:	mov    $0x28,%esi
  79d412:	call   768aa0 <core::panicking::panic>
  79d417:	jmp    79d45a <first_user_task_entry+0x21a>
  79d419:	lea    0x88058(%rip),%rdx        # 825478 <anon.0ddf6eea0652d5b5f8c6d4b0cdbc36f5.155.llvm.17058317916221415436>
  79d420:	lea    0x1072a7(%rip),%rcx        # 8a46ce <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.20.llvm.11761605922429748139+0x8a>
  79d427:	lea    0x4a56fa(%rip),%r9        # c42b28 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.22.llvm.11761605922429748139+0x48>
  79d42e:	lea    0xc(%rsp),%rsi
  79d433:	mov    $0x67,%r8d
  79d439:	xor    %edi,%edi
  79d43b:	call   768838 <core::panicking::assert_failed::<u32, u32>>
  79d440:	jmp    79d45a <first_user_task_entry+0x21a>
  79d442:	lea    0x10750f(%rip),%rdi        # 8a4958 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.60.llvm.11761605922429748139>
  79d449:	lea    0x4a58b8(%rip),%rdx        # c42d08 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.61.llvm.11761605922429748139>
  79d450:	mov    $0x53,%esi
  79d455:	call   768ac0 <core::panicking::panic_fmt>
  79d45a:	ud2
  79d45c:	endbr64
  79d460:	lea    0xc(%rsp),%rdi
  79d465:	call   7c2b20 <<ostd::irq::guard::DisabledLocalIrqGuard as core::ops::drop::Drop>::drop>
  79d46a:	jmp    79d48c <first_user_task_entry+0x24c>
  79d46c:	endbr64
  79d470:	call   7688cb <core::panicking::panic_in_cleanup>
  79d475:	endbr64
  79d479:	call   768a5f <core::panicking::panic_cannot_unwind>
  79d47e:	endbr64
  79d482:	mov    %bpl,%bl
  79d485:	mov    %ebx,%edi
  79d487:	call   79a870 <core::ptr::drop_glue::<ostd::irq::guard::DisabledLocalIrqGuard>>
  79d48c:	call   768a5f <core::panicking::panic_cannot_unwind>
  79d491:	endbr64
  79d495:	call   7688cb <core::panicking::panic_in_cleanup>
  79d49a:	endbr64
  79d49e:	call   768a5f <core::panicking::panic_cannot_unwind>
