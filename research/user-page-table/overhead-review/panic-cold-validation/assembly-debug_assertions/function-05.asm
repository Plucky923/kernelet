
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-debug-assertions.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000079d4b0 <user_event_entry>:
  79d4b0:	endbr64
  79d4b4:	push   %rbp
  79d4b5:	push   %r15
  79d4b7:	push   %r14
  79d4b9:	push   %r12
  79d4bb:	push   %rbx
  79d4bc:	sub    $0x100,%rsp
  79d4c3:	mov    %rdi,0x20(%rsp)
  79d4c8:	jmp    22ae76 <__kernelet_cpu_access_start+0x2ac55>
  79d4cd:	test   %edx,%edx
  79d4cf:	je     79d6c2 <user_event_entry+0x212>
  79d4d5:	mov    0x462b4c(%rip),%rcx        # c00028 <_DYNAMIC+0x1d09b8>
  79d4dc:	jmp    22aea5 <__kernelet_cpu_access_start+0x2ac84>
  79d4e1:	mov    %rax,0x10(%rsp)
  79d4e6:	mov    %rdi,0x18(%rsp)
  79d4eb:	mov    (%rcx),%rdx
  79d4ee:	test   %rdx,%rdx
  79d4f1:	je     79d6df <user_event_entry+0x22f>
  79d4f7:	mov    0x58(%rax),%eax
  79d4fa:	mov    0x8f0(%rdx),%ecx
  79d500:	movzwl 0x3a(%rdx),%esi
  79d504:	lea    (%rsi,%rsi,2),%rsi
  79d508:	shl    $0x6,%esi
  79d50b:	shl    $0x6,%rax
  79d50f:	add    %rdx,%rcx
  79d512:	add    %rsi,%rcx
  79d515:	mov    (%rax,%rcx,1),%rbx
  79d519:	test   %rbx,%rbx
  79d51c:	je     79d6fc <user_event_entry+0x24c>
  79d522:	mov    $0xffffffffffffffff,%r14
  79d529:	mov    0x20(%rsp),%rdx
  79d52e:	test   %rdx,%rdx
  79d531:	je     79d58f <user_event_entry+0xdf>
  79d533:	cmp    $0x1,%rdx
  79d537:	je     79d54b <user_event_entry+0x9b>
  79d539:	cmp    $0x2,%rdx
  79d53d:	jne    79d746 <user_event_entry+0x296>
  79d543:	mov    $0x2,%bpl
  79d546:	mov    $0x1,%r12b
  79d549:	jmp    79d594 <user_event_entry+0xe4>
  79d54b:	mov    0x18(%rcx,%rax,1),%rsi
  79d550:	mov    0x20(%rcx,%rax,1),%rdx
  79d555:	mov    0x28(%rcx,%rax,1),%rcx
  79d55a:	lea    0x38(%rsp),%rdi
  79d55f:	call   7b6aa0 <<ostd::arch::cpu::context::CpuException>::from_raw>
  79d564:	mov    0x38(%rsp),%r14
  79d569:	cmp    $0xffffffffffffffff,%r14
  79d56d:	je     79d776 <user_event_entry+0x2c6>
  79d573:	mov    0x40(%rsp),%rax
  79d578:	mov    0x48(%rsp),%rcx
  79d57d:	mov    %rcx,0x30(%rsp)
  79d582:	mov    %rax,0x28(%rsp)
  79d587:	mov    $0x1,%bpl
  79d58a:	xor    %r12d,%r12d
  79d58d:	jmp    79d594 <user_event_entry+0xe4>
  79d58f:	xor    %r12d,%r12d
  79d592:	xor    %ebp,%ebp
  79d594:	lea    0x10(%rsp),%rdi
  79d599:	call   79e560 <<ostd::task::Task>::current_with>
  79d59e:	test   %rax,%rax
  79d5a1:	je     79d70c <user_event_entry+0x25c>
  79d5a7:	cmpb   $0x0,0x9b(%rax)
  79d5ae:	je     79d729 <user_event_entry+0x279>
  79d5b4:	mov    0x60(%rax),%r15
  79d5b8:	mov    %rax,0x10(%rsp)
  79d5bd:	movq   $0x1,0x38(%rsp)
  79d5c6:	mov    %rbx,0x40(%rsp)
  79d5cb:	mov    %r14,0xe8(%rsp)
  79d5d3:	mov    0x28(%rsp),%rax
  79d5d8:	mov    0x30(%rsp),%rcx
  79d5dd:	mov    %rax,0xf0(%rsp)
  79d5e5:	mov    %rcx,0xf8(%rsp)
  79d5ed:	call   79c0d0 <ostd::arch::irq::ops::enable_local>
  79d5f2:	test   %r12b,%r12b
  79d5f5:	je     79d60c <user_event_entry+0x15c>
  79d5f7:	mov    (%r15),%rdi
  79d5fa:	add    $0x10,%rdi
  79d5fe:	lea    0x10(%rsp),%rsi
  79d603:	call   3137f0 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::has_kernel_event>
  79d608:	test   %al,%al
  79d60a:	je     79d626 <user_event_entry+0x176>
  79d60c:	mov    (%r15),%rdi
  79d60f:	add    $0x10,%rdi
  79d613:	movzbl %bpl,%edx
  79d617:	lea    0x10(%rsp),%rsi
  79d61c:	lea    0x38(%rsp),%rcx
  79d621:	call   3140d0 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle>
  79d626:	mov    (%r15),%rdi
  79d629:	add    $0x10,%rdi
  79d62d:	lea    0x10(%rsp),%rsi
  79d632:	call   313480 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::should_exit>
  79d637:	test   %al,%al
  79d639:	je     79d645 <user_event_entry+0x195>
  79d63b:	call   79fdc0 <ostd::task::exit_current_task>
  79d640:	jmp    79d7d1 <user_event_entry+0x321>
  79d645:	jmp    22aed8 <__kernelet_cpu_access_start+0x2acb7>
  79d64a:	mov    0x50(%rdx),%eax
  79d64d:	mov    %eax,0xc(%rsp)
  79d651:	test   %eax,%eax
  79d653:	jne    79d790 <user_event_entry+0x2e0>
  79d659:	lea    0x4a5498(%rip),%rdi        # c42af8 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.22.llvm.11761605922429748139+0x18>
  79d660:	call   7a6810 <ostd::task::scheduler::might_preempt>
  79d665:	jmp    22af07 <__kernelet_cpu_access_start+0x2ace6>
  79d66a:	test   %edx,%edx
  79d66c:	sete   0xc(%rsp)
  79d671:	lea    0x38(%rsp),%rdi
  79d676:	mov    %rbx,%rsi
  79d679:	call   7b6d20 <<ostd::arch::cpu::context::UserContext>::sync_to_frame>
  79d67e:	lea    0x10(%rsp),%rsi
  79d683:	lea    0xc(%rsp),%rdx
  79d688:	call   313630 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::pre_user_run>
  79d68d:	mov    0x4629cc(%rip),%rax        # c00060 <_DYNAMIC+0x1d09f0>
  79d694:	mov    (%rax),%rax
  79d697:	test   %rax,%rax
  79d69a:	je     79d7b9 <user_event_entry+0x309>
  79d6a0:	xor    %edi,%edi
  79d6a2:	call   *0x68(%rax)
  79d6a5:	lea    0x106fc9(%rip),%rdi        # 8a4675 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.20.llvm.11761605922429748139+0x31>
  79d6ac:	lea    0x4a545d(%rip),%rdx        # c42b10 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.22.llvm.11761605922429748139+0x30>
  79d6b3:	mov    $0xb3,%esi
  79d6b8:	call   768ac0 <core::panicking::panic_fmt>
  79d6bd:	jmp    79d7d1 <user_event_entry+0x321>
  79d6c2:	lea    0x10cd15(%rip),%rdi        # 8aa3de <anon.48726e619213f9dcf02d04207e373d3f.45.llvm.4604410296242810154>
  79d6c9:	lea    0x4a82a8(%rip),%rdx        # c45978 <anon.48726e619213f9dcf02d04207e373d3f.47.llvm.4604410296242810154>
  79d6d0:	mov    $0x2f,%esi
  79d6d5:	call   768aa0 <core::panicking::panic>
  79d6da:	jmp    79d7d1 <user_event_entry+0x321>
  79d6df:	lea    0x10729b(%rip),%rdi        # 8a4981 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.62.llvm.11761605922429748139>
  79d6e6:	lea    0x4a5633(%rip),%rdx        # c42d20 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.63.llvm.11761605922429748139>
  79d6ed:	mov    $0x4d,%esi
  79d6f2:	call   768ac0 <core::panicking::panic_fmt>
  79d6f7:	jmp    79d7d1 <user_event_entry+0x321>
  79d6fc:	lea    0x4a5735(%rip),%rdx        # c42e38 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.70.llvm.11761605922429748139+0xd0>
  79d703:	lea    0x107524(%rip),%rdi        # 8a4c2e <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.67.llvm.11761605922429748139+0x1b1>
  79d70a:	jmp    79d737 <user_event_entry+0x287>
  79d70c:	lea    0x107543(%rip),%rdi        # 8a4c56 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.67.llvm.11761605922429748139+0x1d9>
  79d713:	lea    0x4a5736(%rip),%rdx        # c42e50 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.70.llvm.11761605922429748139+0xe8>
  79d71a:	mov    $0x28,%esi
  79d71f:	call   770970 <core::option::expect_failed>
  79d724:	jmp    79d7d1 <user_event_entry+0x321>
  79d729:	lea    0x4a5738(%rip),%rdx        # c42e68 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.70.llvm.11761605922429748139+0x100>
  79d730:	lea    0x1074cf(%rip),%rdi        # 8a4c06 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.67.llvm.11761605922429748139+0x189>
  79d737:	mov    $0x28,%esi
  79d73c:	call   768aa0 <core::panicking::panic>
  79d741:	jmp    79d7d1 <user_event_entry+0x321>
  79d746:	lea    0x20(%rsp),%rax
  79d74b:	mov    %rax,0x38(%rsp)
  79d750:	mov    0x462901(%rip),%rax        # c00058 <_DYNAMIC+0x1d09e8>
  79d757:	mov    %rax,0x40(%rsp)
  79d75c:	lea    0x64ea5(%rip),%rdi        # 802608 <anon.0f07536b0d45be47616a55719dcc44e0.44.llvm.7092992479102621400+0x1c2>
  79d763:	lea    0x4a5716(%rip),%rdx        # c42e80 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.70.llvm.11761605922429748139+0x118>
  79d76a:	lea    0x38(%rsp),%rsi
  79d76f:	call   768ac0 <core::panicking::panic_fmt>
  79d774:	jmp    79d7d1 <user_event_entry+0x321>
  79d776:	lea    0x106e37(%rip),%rdi        # 8a45b4 <anon.e07f08680952a81bdd214844bdef2536.89.llvm.4295080565535924109+0x278>
  79d77d:	lea    0x4a52e4(%rip),%rdx        # c42a68 <anon.e07f08680952a81bdd214844bdef2536.187.llvm.4295080565535924109+0x48>
  79d784:	mov    $0x36,%esi
  79d789:	call   770970 <core::option::expect_failed>
  79d78e:	jmp    79d7d1 <user_event_entry+0x321>
  79d790:	lea    0x87ce1(%rip),%rdx        # 825478 <anon.0ddf6eea0652d5b5f8c6d4b0cdbc36f5.155.llvm.17058317916221415436>
  79d797:	lea    0x106f30(%rip),%rcx        # 8a46ce <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.20.llvm.11761605922429748139+0x8a>
  79d79e:	lea    0x4a5383(%rip),%r9        # c42b28 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.22.llvm.11761605922429748139+0x48>
  79d7a5:	lea    0xc(%rsp),%rsi
  79d7aa:	mov    $0x67,%r8d
  79d7b0:	xor    %edi,%edi
  79d7b2:	call   768838 <core::panicking::assert_failed::<u32, u32>>
  79d7b7:	jmp    79d7d1 <user_event_entry+0x321>
  79d7b9:	lea    0x107198(%rip),%rdi        # 8a4958 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.60.llvm.11761605922429748139>
  79d7c0:	lea    0x4a5541(%rip),%rdx        # c42d08 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.61.llvm.11761605922429748139>
  79d7c7:	mov    $0x53,%esi
  79d7cc:	call   768ac0 <core::panicking::panic_fmt>
  79d7d1:	ud2
  79d7d3:	endbr64
  79d7d7:	lea    0xc(%rsp),%rdi
  79d7dc:	call   7c2b20 <<ostd::irq::guard::DisabledLocalIrqGuard as core::ops::drop::Drop>::drop>
  79d7e1:	jmp    79d800 <user_event_entry+0x350>
  79d7e3:	endbr64
  79d7e7:	call   7688cb <core::panicking::panic_in_cleanup>
  79d7ec:	endbr64
  79d7f0:	call   768a5f <core::panicking::panic_cannot_unwind>
  79d7f5:	endbr64
  79d7f9:	xor    %edi,%edi
  79d7fb:	call   79a870 <core::ptr::drop_glue::<ostd::irq::guard::DisabledLocalIrqGuard>>
  79d800:	call   768a5f <core::panicking::panic_cannot_unwind>
  79d805:	endbr64
  79d809:	call   7688cb <core::panicking::panic_in_cleanup>
