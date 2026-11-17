
/mnt/data/projects/kernelet/poc/target/kernelet-unsafe-audit-3ca09e6d066ee3cf/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006cc290 <user_event_entry>:
  6cc290:	f3 0f 1e fa          	endbr64
  6cc294:	55                   	push   %rbp
  6cc295:	41 57                	push   %r15
  6cc297:	41 56                	push   %r14
  6cc299:	41 54                	push   %r12
  6cc29b:	53                   	push   %rbx
  6cc29c:	48 81 ec e0 00 00 00 	sub    $0xe0,%rsp
  6cc2a3:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
  6cc2a8:	e8 93 c2 ff ff       	call   6c8540 <ostd::kernelet::entry::user_event_record>
  6cc2ad:	48 8b 18             	mov    (%rax),%rbx
  6cc2b0:	48 c7 c1 ff ff ff ff 	mov    $0xffffffffffffffff,%rcx
  6cc2b7:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
  6cc2bc:	48 85 d2             	test   %rdx,%rdx
  6cc2bf:	74 4f                	je     6cc310 <user_event_entry+0x80>
  6cc2c1:	48 83 fa 01          	cmp    $0x1,%rdx
  6cc2c5:	74 12                	je     6cc2d9 <user_event_entry+0x49>
  6cc2c7:	48 83 fa 02          	cmp    $0x2,%rdx
  6cc2cb:	0f 85 bd 02 00 00    	jne    6cc58e <user_event_entry+0x2fe>
  6cc2d1:	40 b5 02             	mov    $0x2,%bpl
  6cc2d4:	41 b7 01             	mov    $0x1,%r15b
  6cc2d7:	eb 3c                	jmp    6cc315 <user_event_entry+0x85>
  6cc2d9:	48 8b 48 18          	mov    0x18(%rax),%rcx
  6cc2dd:	48 8b 50 20          	mov    0x20(%rax),%rdx
  6cc2e1:	48 8b 40 28          	mov    0x28(%rax),%rax
  6cc2e5:	40 b5 01             	mov    $0x1,%bpl
  6cc2e8:	48 83 f9 1f          	cmp    $0x1f,%rcx
  6cc2ec:	0f 87 4a 02 00 00    	ja     6cc53c <user_event_entry+0x2ac>
  6cc2f2:	45 31 ff             	xor    %r15d,%r15d
  6cc2f5:	48 8d 35 14 66 19 00 	lea    0x196614(%rip),%rsi        # 862910 <anon.c25f29b7a7b48a9d99b68ffd5c2b443e.60.llvm.17932337005181077852+0x8c>
  6cc2fc:	48 63 3c 8e          	movslq (%rsi,%rcx,4),%rdi
  6cc300:	48 01 f7             	add    %rsi,%rdi
  6cc303:	3e ff e7             	notrack jmp *%rdi
  6cc306:	b9 18 00 00 00       	mov    $0x18,%ecx
  6cc30b:	45 31 ff             	xor    %r15d,%r15d
  6cc30e:	eb c7                	jmp    6cc2d7 <user_event_entry+0x47>
  6cc310:	45 31 ff             	xor    %r15d,%r15d
  6cc313:	31 ed                	xor    %ebp,%ebp
  6cc315:	48 8d 3d 24 e3 36 00 	lea    0x36e324(%rip),%rdi        # a3a640 <ostd::task::processor::CURRENT_TASK_PTR>
  6cc31c:	48 2b 3d fd 3c 33 00 	sub    0x333cfd(%rip),%rdi        # a00020 <_DYNAMIC+0x5ee40>
  6cc323:	e9 f9 51 b7 ff       	jmp    241521 <__kernelet_cpu_access_start+0x41300>
  6cc328:	48 85 f6             	test   %rsi,%rsi
  6cc32b:	0f 84 43 02 00 00    	je     6cc574 <user_event_entry+0x2e4>
  6cc331:	4c 8b 76 60          	mov    0x60(%rsi),%r14
  6cc335:	48 89 94 24 d0 00 00 00 	mov    %rdx,0xd0(%rsp)
  6cc33d:	48 89 84 24 d8 00 00 00 	mov    %rax,0xd8(%rsp)
  6cc345:	48 89 74 24 08       	mov    %rsi,0x8(%rsp)
  6cc34a:	48 c7 44 24 18 01 00 00 00 	movq   $0x1,0x18(%rsp)
  6cc353:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
  6cc358:	48 89 8c 24 c8 00 00 00 	mov    %rcx,0xc8(%rsp)
  6cc360:	e8 cb c6 ff ff       	call   6c8a30 <ostd::arch::irq::ops::enable_local>
  6cc365:	45 84 ff             	test   %r15b,%r15b
  6cc368:	74 15                	je     6cc37f <user_event_entry+0xef>
  6cc36a:	49 8b 3e             	mov    (%r14),%rdi
  6cc36d:	48 83 c7 10          	add    $0x10,%rdi
  6cc371:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
  6cc376:	e8 d5 eb cb ff       	call   38af50 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::has_kernel_event>
  6cc37b:	84 c0                	test   %al,%al
  6cc37d:	74 16                	je     6cc395 <user_event_entry+0x105>
  6cc37f:	40 0f b6 d5          	movzbl %bpl,%edx
  6cc383:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
  6cc388:	48 8d 4c 24 18       	lea    0x18(%rsp),%rcx
  6cc38d:	4c 89 f7             	mov    %r14,%rdi
  6cc390:	e8 6b 38 cc ff       	call   38fc00 <__ostd_user_handle>
  6cc395:	49 8b 3e             	mov    (%r14),%rdi
  6cc398:	48 83 c7 10          	add    $0x10,%rdi
  6cc39c:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
  6cc3a1:	e8 ca ea cb ff       	call   38ae70 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::should_exit>
  6cc3a6:	84 c0                	test   %al,%al
  6cc3a8:	74 0a                	je     6cc3b4 <user_event_entry+0x124>
  6cc3aa:	e8 11 9e ff ff       	call   6c61c0 <ostd::task::exit_current_task>
  6cc3af:	e9 57 02 00 00       	jmp    6cc60b <user_event_entry+0x37b>
  6cc3b4:	e9 9e 51 b7 ff       	jmp    241557 <__kernelet_cpu_access_start+0x41336>
  6cc3b9:	8b 42 50             	mov    0x50(%rdx),%eax
  6cc3bc:	89 44 24 04          	mov    %eax,0x4(%rsp)
  6cc3c0:	85 c0                	test   %eax,%eax
  6cc3c2:	0f 85 f4 01 00 00    	jne    6cc5bc <user_event_entry+0x32c>
  6cc3c8:	48 8d 3d 51 23 36 00 	lea    0x362351(%rip),%rdi        # a2e720 <anon.e0af733efa188d9da4104a951dd93b7e.31.llvm.15477716685929987621+0x18>
  6cc3cf:	e8 3c 99 00 00       	call   6d5d10 <ostd::task::scheduler::might_preempt>
  6cc3d4:	e9 ad 51 b7 ff       	jmp    241586 <__kernelet_cpu_access_start+0x41365>
  6cc3d9:	85 c0                	test   %eax,%eax
  6cc3db:	75 0a                	jne    6cc3e7 <user_event_entry+0x157>
  6cc3dd:	b9 01 00 00 00       	mov    $0x1,%ecx
  6cc3e2:	e9 ce 51 b7 ff       	jmp    2415b5 <__kernelet_cpu_access_start+0x41394>
  6cc3e7:	85 c0                	test   %eax,%eax
  6cc3e9:	0f 94 44 24 04       	sete   0x4(%rsp)
  6cc3ee:	80 7c 24 18 00       	cmpb   $0x0,0x18(%rsp)
  6cc3f3:	75 62                	jne    6cc457 <user_event_entry+0x1c7>
  6cc3f5:	48 8d 74 24 20       	lea    0x20(%rsp),%rsi
  6cc3fa:	4c 8b bc 24 b0 00 00 00 	mov    0xb0(%rsp),%r15
  6cc402:	4c 8b a4 24 b8 00 00 00 	mov    0xb8(%rsp),%r12
  6cc40a:	41 81 e7 d5 0d 24 00 	and    $0x240dd5,%r15d
  6cc411:	49 81 cf 02 02 00 00 	or     $0x202,%r15
  6cc418:	ba 88 00 00 00       	mov    $0x88,%edx
  6cc41d:	48 89 df             	mov    %rbx,%rdi
  6cc420:	e8 5b b1 02 00       	call   6f7580 <memcpy>
  6cc425:	48 c7 83 88 00 00 00 33 00 00 00 	movq   $0x33,0x88(%rbx)
  6cc430:	4c 89 bb 90 00 00 00 	mov    %r15,0x90(%rbx)
  6cc437:	4c 89 a3 98 00 00 00 	mov    %r12,0x98(%rbx)
  6cc43e:	48 c7 83 a0 00 00 00 2b 00 00 00 	movq   $0x2b,0xa0(%rbx)
  6cc449:	48 c7 44 24 18 01 00 00 00 	movq   $0x1,0x18(%rsp)
  6cc452:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
  6cc457:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
  6cc45c:	48 8d 54 24 04       	lea    0x4(%rsp),%rdx
  6cc461:	4c 89 f7             	mov    %r14,%rdi
  6cc464:	e8 07 39 cc ff       	call   38fd70 <__ostd_user_pre_user_run>
  6cc469:	48 8b 05 c8 3b 33 00 	mov    0x333bc8(%rip),%rax        # a00038 <_DYNAMIC+0x5ee58>
  6cc470:	48 8b 00             	mov    (%rax),%rax
  6cc473:	48 85 c0             	test   %rax,%rax
  6cc476:	0f 84 69 01 00 00    	je     6cc5e5 <user_event_entry+0x355>
  6cc47c:	31 ff                	xor    %edi,%edi
  6cc47e:	ff 50 68             	call   *0x68(%rax)
  6cc481:	48 8d 15 b0 22 36 00 	lea    0x3622b0(%rip),%rdx        # a2e738 <anon.e0af733efa188d9da4104a951dd93b7e.31.llvm.15477716685929987621+0x30>
  6cc488:	be b3 00 00 00       	mov    $0xb3,%esi
  6cc48d:	48 8d 3d 70 66 19 00 	lea    0x196670(%rip),%rdi        # 862b04 <anon.e0af733efa188d9da4104a951dd93b7e.10.llvm.15477716685929987621+0xf2>
  6cc494:	e8 57 c7 fd ff       	call   6a8bf0 <core::panicking::panic_fmt>
  6cc499:	e9 6d 01 00 00       	jmp    6cc60b <user_event_entry+0x37b>
  6cc49e:	b9 10 00 00 00       	mov    $0x10,%ecx
  6cc4a3:	45 31 ff             	xor    %r15d,%r15d
  6cc4a6:	e9 2c fe ff ff       	jmp    6cc2d7 <user_event_entry+0x47>
  6cc4ab:	b9 13 00 00 00       	mov    $0x13,%ecx
  6cc4b0:	45 31 ff             	xor    %r15d,%r15d
  6cc4b3:	e9 1f fe ff ff       	jmp    6cc2d7 <user_event_entry+0x47>
  6cc4b8:	b9 17 00 00 00       	mov    $0x17,%ecx
  6cc4bd:	45 31 ff             	xor    %r15d,%r15d
  6cc4c0:	e9 12 fe ff ff       	jmp    6cc2d7 <user_event_entry+0x47>
  6cc4c5:	b9 15 00 00 00       	mov    $0x15,%ecx
  6cc4ca:	45 31 ff             	xor    %r15d,%r15d
  6cc4cd:	e9 05 fe ff ff       	jmp    6cc2d7 <user_event_entry+0x47>
  6cc4d2:	b9 14 00 00 00       	mov    $0x14,%ecx
  6cc4d7:	45 31 ff             	xor    %r15d,%r15d
  6cc4da:	e9 f8 fd ff ff       	jmp    6cc2d7 <user_event_entry+0x47>
  6cc4df:	b9 11 00 00 00       	mov    $0x11,%ecx
  6cc4e4:	45 31 ff             	xor    %r15d,%r15d
  6cc4e7:	e9 eb fd ff ff       	jmp    6cc2d7 <user_event_entry+0x47>
  6cc4ec:	b9 16 00 00 00       	mov    $0x16,%ecx
  6cc4f1:	45 31 ff             	xor    %r15d,%r15d
  6cc4f4:	e9 de fd ff ff       	jmp    6cc2d7 <user_event_entry+0x47>
  6cc4f9:	31 f6                	xor    %esi,%esi
  6cc4fb:	48 85 d2             	test   %rdx,%rdx
  6cc4fe:	40 0f 95 c6          	setne  %sil
  6cc502:	b9 0d 00 00 00       	mov    $0xd,%ecx
  6cc507:	45 31 ff             	xor    %r15d,%r15d
  6cc50a:	48 89 d0             	mov    %rdx,%rax
  6cc50d:	48 89 f2             	mov    %rsi,%rdx
  6cc510:	e9 00 fe ff ff       	jmp    6cc315 <user_event_entry+0x85>
  6cc515:	b9 0f 00 00 00       	mov    $0xf,%ecx
  6cc51a:	45 31 ff             	xor    %r15d,%r15d
  6cc51d:	e9 b5 fd ff ff       	jmp    6cc2d7 <user_event_entry+0x47>
  6cc522:	48 f7 c2 00 7f ff ff 	test   $0xffffffffffff7f00,%rdx
  6cc529:	0f 85 d0 00 00 00    	jne    6cc5ff <user_event_entry+0x36f>
  6cc52f:	b9 0e 00 00 00       	mov    $0xe,%ecx
  6cc534:	45 31 ff             	xor    %r15d,%r15d
  6cc537:	e9 d9 fd ff ff       	jmp    6cc315 <user_event_entry+0x85>
  6cc53c:	48 83 c1 ea          	add    $0xffffffffffffffea,%rcx
  6cc540:	48 83 f9 06          	cmp    $0x6,%rcx
  6cc544:	0f 82 bc fd ff ff    	jb     6cc306 <user_event_entry+0x76>
  6cc54a:	48 8d 3d 0d 65 19 00 	lea    0x19650d(%rip),%rdi        # 862a5e <anon.e0af733efa188d9da4104a951dd93b7e.10.llvm.15477716685929987621+0x4c>
  6cc551:	48 8d 15 e8 20 36 00 	lea    0x3620e8(%rip),%rdx        # a2e640 <anon.e0af733efa188d9da4104a951dd93b7e.11.llvm.15477716685929987621+0x18>
  6cc558:	be 36 00 00 00       	mov    $0x36,%esi
  6cc55d:	e8 de a2 fd ff       	call   6a6840 <core::option::expect_failed>
  6cc562:	e9 a4 00 00 00       	jmp    6cc60b <user_event_entry+0x37b>
  6cc567:	b9 12 00 00 00       	mov    $0x12,%ecx
  6cc56c:	45 31 ff             	xor    %r15d,%r15d
  6cc56f:	e9 63 fd ff ff       	jmp    6cc2d7 <user_event_entry+0x47>
  6cc574:	48 8d 3d 0e 68 19 00 	lea    0x19680e(%rip),%rdi        # 862d89 <anon.e0af733efa188d9da4104a951dd93b7e.51.llvm.15477716685929987621+0x5b>
  6cc57b:	48 8d 15 de 22 36 00 	lea    0x3622de(%rip),%rdx        # a2e860 <anon.e0af733efa188d9da4104a951dd93b7e.54.llvm.15477716685929987621+0x50>
  6cc582:	be 28 00 00 00       	mov    $0x28,%esi
  6cc587:	e8 b4 a2 fd ff       	call   6a6840 <core::option::expect_failed>
  6cc58c:	eb 7d                	jmp    6cc60b <user_event_entry+0x37b>
  6cc58e:	48 8d 44 24 10       	lea    0x10(%rsp),%rax
  6cc593:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
  6cc598:	48 8b 05 c1 3a 33 00 	mov    0x333ac1(%rip),%rax        # a00060 <_DYNAMIC+0x5ee80>
  6cc59f:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  6cc5a4:	48 8d 15 cd 22 36 00 	lea    0x3622cd(%rip),%rdx        # a2e878 <anon.e0af733efa188d9da4104a951dd93b7e.54.llvm.15477716685929987621+0x68>
  6cc5ab:	48 8d 74 24 18       	lea    0x18(%rsp),%rsi
  6cc5b0:	48 8d 3d 72 52 13 00 	lea    0x135272(%rip),%rdi        # 801829 <anon.cd7581bfce33bf31eaff2843d00bee92.10.llvm.13422294949452720248+0x105>
  6cc5b7:	e9 d8 fe ff ff       	jmp    6cc494 <user_event_entry+0x204>
  6cc5bc:	48 8d 15 09 62 15 00 	lea    0x156209(%rip),%rdx        # 8227cc <anon.45e5aa24a1f7492fd813e4484e513d71.67.llvm.3441646032486278169>
  6cc5c3:	48 8d 0d 93 65 19 00 	lea    0x196593(%rip),%rcx        # 862b5d <anon.e0af733efa188d9da4104a951dd93b7e.10.llvm.15477716685929987621+0x14b>
  6cc5ca:	4c 8d 0d 7f 21 36 00 	lea    0x36217f(%rip),%r9        # a2e750 <anon.e0af733efa188d9da4104a951dd93b7e.31.llvm.15477716685929987621+0x48>
  6cc5d1:	48 8d 74 24 04       	lea    0x4(%rsp),%rsi
  6cc5d6:	41 b8 67 00 00 00    	mov    $0x67,%r8d
  6cc5dc:	31 ff                	xor    %edi,%edi
  6cc5de:	e8 99 ba 01 00       	call   6e807c <core::panicking::assert_failed::<u32, u32>>
  6cc5e3:	eb 26                	jmp    6cc60b <user_event_entry+0x37b>
  6cc5e5:	48 8d 3d 3c 61 19 00 	lea    0x19613c(%rip),%rdi        # 862728 <anon.c25f29b7a7b48a9d99b68ffd5c2b443e.31.llvm.17932337005181077852>
  6cc5ec:	48 8d 15 e5 1e 36 00 	lea    0x361ee5(%rip),%rdx        # a2e4d8 <anon.c25f29b7a7b48a9d99b68ffd5c2b443e.32.llvm.17932337005181077852>
  6cc5f3:	be 53 00 00 00       	mov    $0x53,%esi
  6cc5f8:	e8 f3 c5 fd ff       	call   6a8bf0 <core::panicking::panic_fmt>
  6cc5fd:	eb 0c                	jmp    6cc60b <user_event_entry+0x37b>
  6cc5ff:	48 8d 3d a2 22 36 00 	lea    0x3622a2(%rip),%rdi        # a2e8a8 <anon.3935b81a5ff619a1c05e68d25bc5ccec.3.llvm.7417983477140250550>
  6cc606:	e8 75 a2 fd ff       	call   6a6880 <core::option::unwrap_failed>
  6cc60b:	0f 0b                	ud2
  6cc60d:	f3 0f 1e fa          	endbr64
  6cc611:	48 8d 7c 24 04       	lea    0x4(%rsp),%rdi
  6cc616:	e8 b5 11 01 00       	call   6dd7d0 <<ostd::irq::guard::DisabledLocalIrqGuard as core::ops::drop::Drop>::drop>
  6cc61b:	e8 6f c5 fd ff       	call   6a8b8f <core::panicking::panic_cannot_unwind>
  6cc620:	f3 0f 1e fa          	endbr64
  6cc624:	e8 d2 c3 fd ff       	call   6a89fb <core::panicking::panic_in_cleanup>
  6cc629:	f3 0f 1e fa          	endbr64
  6cc62d:	e8 5d c5 fd ff       	call   6a8b8f <core::panicking::panic_cannot_unwind>
