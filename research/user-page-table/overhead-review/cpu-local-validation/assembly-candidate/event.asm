
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006be0b0 <user_event_entry>:
  6be0b0:	f3 0f 1e fa          	endbr64
  6be0b4:	55                   	push   %rbp
  6be0b5:	41 57                	push   %r15
  6be0b7:	41 56                	push   %r14
  6be0b9:	41 54                	push   %r12
  6be0bb:	53                   	push   %rbx
  6be0bc:	48 81 ec e0 00 00 00 	sub    $0xe0,%rsp
  6be0c3:	48 89 7c 24 10       	mov    %rdi,0x10(%rsp)
  6be0c8:	e9 0a 98 b7 ff       	jmp    2378d7 <__kernelet_cpu_access_start+0x376b6>
  6be0cd:	48 8b 0d 3c 1f 34 00 	mov    0x341f3c(%rip),%rcx        # a00010 <_DYNAMIC+0x5fd68>
  6be0d4:	48 8b 09             	mov    (%rcx),%rcx
  6be0d7:	48 85 c9             	test   %rcx,%rcx
  6be0da:	0f 84 de 02 00 00    	je     6be3be <user_event_entry+0x30e>
  6be0e0:	8b 72 58             	mov    0x58(%rdx),%esi
  6be0e3:	8b b9 f0 08 00 00    	mov    0x8f0(%rcx),%edi
  6be0e9:	0f b7 51 3a          	movzwl 0x3a(%rcx),%edx
  6be0ed:	48 8d 14 52          	lea    (%rdx,%rdx,2),%rdx
  6be0f1:	c1 e2 06             	shl    $0x6,%edx
  6be0f4:	48 c1 e6 06          	shl    $0x6,%rsi
  6be0f8:	48 01 cf             	add    %rcx,%rdi
  6be0fb:	48 01 d7             	add    %rdx,%rdi
  6be0fe:	48 8b 1c 3e          	mov    (%rsi,%rdi,1),%rbx
  6be102:	48 c7 c1 ff ff ff ff 	mov    $0xffffffffffffffff,%rcx
  6be109:	48 8b 54 24 10       	mov    0x10(%rsp),%rdx
  6be10e:	48 85 d2             	test   %rdx,%rdx
  6be111:	74 56                	je     6be169 <user_event_entry+0xb9>
  6be113:	48 83 fa 01          	cmp    $0x1,%rdx
  6be117:	74 12                	je     6be12b <user_event_entry+0x7b>
  6be119:	48 83 fa 02          	cmp    $0x2,%rdx
  6be11d:	0f 85 d2 02 00 00    	jne    6be3f5 <user_event_entry+0x345>
  6be123:	40 b5 02             	mov    $0x2,%bpl
  6be126:	41 b7 01             	mov    $0x1,%r15b
  6be129:	eb 43                	jmp    6be16e <user_event_entry+0xbe>
  6be12b:	48 8b 4c 37 18       	mov    0x18(%rdi,%rsi,1),%rcx
  6be130:	48 8b 54 37 20       	mov    0x20(%rdi,%rsi,1),%rdx
  6be135:	48 8b 7c 37 28       	mov    0x28(%rdi,%rsi,1),%rdi
  6be13a:	40 b5 01             	mov    $0x1,%bpl
  6be13d:	48 83 f9 1f          	cmp    $0x1f,%rcx
  6be141:	0f 87 3f 02 00 00    	ja     6be386 <user_event_entry+0x2d6>
  6be147:	45 31 ff             	xor    %r15d,%r15d
  6be14a:	48 8d 35 e7 47 1a 00 	lea    0x1a47e7(%rip),%rsi        # 862938 <anon.69b61e67870078f7a7a8da36a6021cc0.8.llvm.4207056135023237709+0x302>
  6be151:	4c 63 04 8e          	movslq (%rsi,%rcx,4),%r8
  6be155:	49 01 f0             	add    %rsi,%r8
  6be158:	48 89 d6             	mov    %rdx,%rsi
  6be15b:	3e 41 ff e0          	notrack jmp *%r8
  6be15f:	b9 18 00 00 00       	mov    $0x18,%ecx
  6be164:	45 31 ff             	xor    %r15d,%r15d
  6be167:	eb c0                	jmp    6be129 <user_event_entry+0x79>
  6be169:	45 31 ff             	xor    %r15d,%r15d
  6be16c:	31 ed                	xor    %ebp,%ebp
  6be16e:	48 8d 3d cb c4 37 00 	lea    0x37c4cb(%rip),%rdi        # a3a640 <ostd::task::processor::CURRENT_TASK_PTR>
  6be175:	48 2b 3d a4 1e 34 00 	sub    0x341ea4(%rip),%rdi        # a00020 <_DYNAMIC+0x5fd78>
  6be17c:	48 8b 04 38          	mov    (%rax,%rdi,1),%rax
  6be180:	48 85 c0             	test   %rax,%rax
  6be183:	0f 84 52 02 00 00    	je     6be3db <user_event_entry+0x32b>
  6be189:	4c 8b 70 60          	mov    0x60(%rax),%r14
  6be18d:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  6be192:	48 c7 44 24 18 01 00 00 00 	movq   $0x1,0x18(%rsp)
  6be19b:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
  6be1a0:	48 89 8c 24 c8 00 00 00 	mov    %rcx,0xc8(%rsp)
  6be1a8:	48 89 b4 24 d0 00 00 00 	mov    %rsi,0xd0(%rsp)
  6be1b0:	48 89 94 24 d8 00 00 00 	mov    %rdx,0xd8(%rsp)
  6be1b8:	e8 93 3d 00 00       	call   6c1f50 <ostd::arch::irq::ops::enable_local>
  6be1bd:	45 84 ff             	test   %r15b,%r15b
  6be1c0:	74 15                	je     6be1d7 <user_event_entry+0x127>
  6be1c2:	49 8b 3e             	mov    (%r14),%rdi
  6be1c5:	48 83 c7 10          	add    $0x10,%rdi
  6be1c9:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
  6be1ce:	e8 0d 4e de ff       	call   4a2fe0 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::has_kernel_event>
  6be1d3:	84 c0                	test   %al,%al
  6be1d5:	74 16                	je     6be1ed <user_event_entry+0x13d>
  6be1d7:	40 0f b6 d5          	movzbl %bpl,%edx
  6be1db:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
  6be1e0:	48 8d 4c 24 18       	lea    0x18(%rsp),%rcx
  6be1e5:	4c 89 f7             	mov    %r14,%rdi
  6be1e8:	e8 03 a1 de ff       	call   4a82f0 <__ostd_user_handle>
  6be1ed:	49 8b 3e             	mov    (%r14),%rdi
  6be1f0:	48 83 c7 10          	add    $0x10,%rdi
  6be1f4:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
  6be1f9:	e8 02 4d de ff       	call   4a2f00 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::should_exit>
  6be1fe:	84 c0                	test   %al,%al
  6be200:	74 0a                	je     6be20c <user_event_entry+0x15c>
  6be202:	e8 79 8a ff ff       	call   6b6c80 <ostd::task::exit_current_task>
  6be207:	e9 68 02 00 00       	jmp    6be474 <user_event_entry+0x3c4>
  6be20c:	e9 f9 96 b7 ff       	jmp    23790a <__kernelet_cpu_access_start+0x376e9>
  6be211:	8b 42 50             	mov    0x50(%rdx),%eax
  6be214:	89 44 24 04          	mov    %eax,0x4(%rsp)
  6be218:	85 c0                	test   %eax,%eax
  6be21a:	0f 85 05 02 00 00    	jne    6be425 <user_event_entry+0x375>
  6be220:	48 8d 3d 11 05 37 00 	lea    0x370511(%rip),%rdi        # a2e738 <anon.2556e6359d291468c09e00eda78c61db.22.llvm.15615756070059268768+0x48>
  6be227:	e8 34 1b 00 00       	call   6bfd60 <ostd::task::scheduler::might_preempt>
  6be22c:	e9 08 97 b7 ff       	jmp    237939 <__kernelet_cpu_access_start+0x37718>
  6be231:	85 d2                	test   %edx,%edx
  6be233:	0f 94 44 24 04       	sete   0x4(%rsp)
  6be238:	80 7c 24 18 00       	cmpb   $0x0,0x18(%rsp)
  6be23d:	75 62                	jne    6be2a1 <user_event_entry+0x1f1>
  6be23f:	48 8d 74 24 20       	lea    0x20(%rsp),%rsi
  6be244:	4c 8b bc 24 b0 00 00 00 	mov    0xb0(%rsp),%r15
  6be24c:	4c 8b a4 24 b8 00 00 00 	mov    0xb8(%rsp),%r12
  6be254:	41 81 e7 d5 0d 24 00 	and    $0x240dd5,%r15d
  6be25b:	49 81 cf 02 02 00 00 	or     $0x202,%r15
  6be262:	ba 88 00 00 00       	mov    $0x88,%edx
  6be267:	48 89 df             	mov    %rbx,%rdi
  6be26a:	e8 f1 9e 02 00       	call   6e8160 <memcpy>
  6be26f:	48 c7 83 88 00 00 00 33 00 00 00 	movq   $0x33,0x88(%rbx)
  6be27a:	4c 89 bb 90 00 00 00 	mov    %r15,0x90(%rbx)
  6be281:	4c 89 a3 98 00 00 00 	mov    %r12,0x98(%rbx)
  6be288:	48 c7 83 a0 00 00 00 2b 00 00 00 	movq   $0x2b,0xa0(%rbx)
  6be293:	48 c7 44 24 18 01 00 00 00 	movq   $0x1,0x18(%rsp)
  6be29c:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
  6be2a1:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
  6be2a6:	48 8d 54 24 04       	lea    0x4(%rsp),%rdx
  6be2ab:	4c 89 f7             	mov    %r14,%rdi
  6be2ae:	e8 ad a1 de ff       	call   4a8460 <__ostd_user_pre_user_run>
  6be2b3:	48 8b 05 7e 1d 34 00 	mov    0x341d7e(%rip),%rax        # a00038 <_DYNAMIC+0x5fd90>
  6be2ba:	48 8b 00             	mov    (%rax),%rax
  6be2bd:	48 85 c0             	test   %rax,%rax
  6be2c0:	0f 84 88 01 00 00    	je     6be44e <user_event_entry+0x39e>
  6be2c6:	31 ff                	xor    %edi,%edi
  6be2c8:	ff 50 68             	call   *0x68(%rax)
  6be2cb:	48 8d 3d 2c 48 1a 00 	lea    0x1a482c(%rip),%rdi        # 862afe <anon.2556e6359d291468c09e00eda78c61db.26.llvm.15615756070059268768+0x17>
  6be2d2:	48 8d 15 77 04 37 00 	lea    0x370477(%rip),%rdx        # a2e750 <anon.2556e6359d291468c09e00eda78c61db.22.llvm.15615756070059268768+0x60>
  6be2d9:	be b3 00 00 00       	mov    $0xb3,%esi
  6be2de:	e8 fd b4 fd ff       	call   6997e0 <core::panicking::panic_fmt>
  6be2e3:	e9 8c 01 00 00       	jmp    6be474 <user_event_entry+0x3c4>
  6be2e8:	b9 10 00 00 00       	mov    $0x10,%ecx
  6be2ed:	45 31 ff             	xor    %r15d,%r15d
  6be2f0:	e9 34 fe ff ff       	jmp    6be129 <user_event_entry+0x79>
  6be2f5:	b9 13 00 00 00       	mov    $0x13,%ecx
  6be2fa:	45 31 ff             	xor    %r15d,%r15d
  6be2fd:	e9 27 fe ff ff       	jmp    6be129 <user_event_entry+0x79>
  6be302:	b9 17 00 00 00       	mov    $0x17,%ecx
  6be307:	45 31 ff             	xor    %r15d,%r15d
  6be30a:	e9 1a fe ff ff       	jmp    6be129 <user_event_entry+0x79>
  6be30f:	b9 15 00 00 00       	mov    $0x15,%ecx
  6be314:	45 31 ff             	xor    %r15d,%r15d
  6be317:	e9 0d fe ff ff       	jmp    6be129 <user_event_entry+0x79>
  6be31c:	b9 14 00 00 00       	mov    $0x14,%ecx
  6be321:	45 31 ff             	xor    %r15d,%r15d
  6be324:	e9 00 fe ff ff       	jmp    6be129 <user_event_entry+0x79>
  6be329:	b9 11 00 00 00       	mov    $0x11,%ecx
  6be32e:	45 31 ff             	xor    %r15d,%r15d
  6be331:	e9 f3 fd ff ff       	jmp    6be129 <user_event_entry+0x79>
  6be336:	b9 16 00 00 00       	mov    $0x16,%ecx
  6be33b:	45 31 ff             	xor    %r15d,%r15d
  6be33e:	e9 e6 fd ff ff       	jmp    6be129 <user_event_entry+0x79>
  6be343:	31 f6                	xor    %esi,%esi
  6be345:	48 85 d2             	test   %rdx,%rdx
  6be348:	40 0f 95 c6          	setne  %sil
  6be34c:	b9 0d 00 00 00       	mov    $0xd,%ecx
  6be351:	45 31 ff             	xor    %r15d,%r15d
  6be354:	e9 15 fe ff ff       	jmp    6be16e <user_event_entry+0xbe>
  6be359:	b9 0f 00 00 00       	mov    $0xf,%ecx
  6be35e:	45 31 ff             	xor    %r15d,%r15d
  6be361:	e9 c3 fd ff ff       	jmp    6be129 <user_event_entry+0x79>
  6be366:	48 f7 c2 00 7f ff ff 	test   $0xffffffffffff7f00,%rdx
  6be36d:	0f 85 f5 00 00 00    	jne    6be468 <user_event_entry+0x3b8>
  6be373:	b9 0e 00 00 00       	mov    $0xe,%ecx
  6be378:	45 31 ff             	xor    %r15d,%r15d
  6be37b:	48 89 d6             	mov    %rdx,%rsi
  6be37e:	48 89 fa             	mov    %rdi,%rdx
  6be381:	e9 e8 fd ff ff       	jmp    6be16e <user_event_entry+0xbe>
  6be386:	48 83 c1 ea          	add    $0xffffffffffffffea,%rcx
  6be38a:	48 83 f9 06          	cmp    $0x6,%rcx
  6be38e:	0f 82 cb fd ff ff    	jb     6be15f <user_event_entry+0xaf>
  6be394:	48 8d 3d eb 46 1a 00 	lea    0x1a46eb(%rip),%rdi        # 862a86 <anon.2556e6359d291468c09e00eda78c61db.10.llvm.15615756070059268768+0x4c>
  6be39b:	48 8d 15 16 03 37 00 	lea    0x370316(%rip),%rdx        # a2e6b8 <anon.2556e6359d291468c09e00eda78c61db.11.llvm.15615756070059268768+0x18>
  6be3a2:	be 36 00 00 00       	mov    $0x36,%esi
  6be3a7:	e8 84 90 fd ff       	call   697430 <core::option::expect_failed>
  6be3ac:	e9 c3 00 00 00       	jmp    6be474 <user_event_entry+0x3c4>
  6be3b1:	b9 12 00 00 00       	mov    $0x12,%ecx
  6be3b6:	45 31 ff             	xor    %r15d,%r15d
  6be3b9:	e9 6b fd ff ff       	jmp    6be129 <user_event_entry+0x79>
  6be3be:	48 8d 3d 98 4d 1a 00 	lea    0x1a4d98(%rip),%rdi        # 86315d <anon.b9a81f2eeec052eb13297414241e8ab2.32.llvm.7034704448355070909>
  6be3c5:	48 8d 15 f4 07 37 00 	lea    0x3707f4(%rip),%rdx        # a2ebc0 <anon.b9a81f2eeec052eb13297414241e8ab2.33.llvm.7034704448355070909>
  6be3cc:	be 4d 00 00 00       	mov    $0x4d,%esi
  6be3d1:	e8 0a b4 fd ff       	call   6997e0 <core::panicking::panic_fmt>
  6be3d6:	e9 99 00 00 00       	jmp    6be474 <user_event_entry+0x3c4>
  6be3db:	48 8d 3d a1 49 1a 00 	lea    0x1a49a1(%rip),%rdi        # 862d83 <anon.2556e6359d291468c09e00eda78c61db.46.llvm.15615756070059268768+0x5b>
  6be3e2:	48 8d 15 8f 04 37 00 	lea    0x37048f(%rip),%rdx        # a2e878 <anon.2556e6359d291468c09e00eda78c61db.49.llvm.15615756070059268768+0x50>
  6be3e9:	be 28 00 00 00       	mov    $0x28,%esi
  6be3ee:	e8 3d 90 fd ff       	call   697430 <core::option::expect_failed>
  6be3f3:	eb 7f                	jmp    6be474 <user_event_entry+0x3c4>
  6be3f5:	48 8d 44 24 10       	lea    0x10(%rsp),%rax
  6be3fa:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
  6be3ff:	48 8b 05 5a 1c 34 00 	mov    0x341c5a(%rip),%rax        # a00060 <_DYNAMIC+0x5fdb8>
  6be406:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  6be40b:	48 8d 3d 81 3c 14 00 	lea    0x143c81(%rip),%rdi        # 802093 <anon.6bbc1879cbe514377c4321431c5b6ee0.30.llvm.11246372459317742168+0x1e6>
  6be412:	48 8d 15 77 04 37 00 	lea    0x370477(%rip),%rdx        # a2e890 <anon.2556e6359d291468c09e00eda78c61db.49.llvm.15615756070059268768+0x68>
  6be419:	48 8d 74 24 18       	lea    0x18(%rsp),%rsi
  6be41e:	e8 bd b3 fd ff       	call   6997e0 <core::panicking::panic_fmt>
  6be423:	eb 4f                	jmp    6be474 <user_event_entry+0x3c4>
  6be425:	48 8d 15 a4 43 16 00 	lea    0x1643a4(%rip),%rdx        # 8227d0 <anon.6bbc1879cbe514377c4321431c5b6ee0.67.llvm.11246372459317742168>
  6be42c:	48 8d 0d 24 47 1a 00 	lea    0x1a4724(%rip),%rcx        # 862b57 <anon.2556e6359d291468c09e00eda78c61db.26.llvm.15615756070059268768+0x70>
  6be433:	4c 8d 0d 2e 03 37 00 	lea    0x37032e(%rip),%r9        # a2e768 <anon.2556e6359d291468c09e00eda78c61db.22.llvm.15615756070059268768+0x78>
  6be43a:	48 8d 74 24 04       	lea    0x4(%rsp),%rsi
  6be43f:	41 b8 67 00 00 00    	mov    $0x67,%r8d
  6be445:	31 ff                	xor    %edi,%edi
  6be447:	e8 08 38 01 00       	call   6d1c54 <core::panicking::assert_failed::<u32, u32>>
  6be44c:	eb 26                	jmp    6be474 <user_event_entry+0x3c4>
  6be44e:	48 8d 3d df 4c 1a 00 	lea    0x1a4cdf(%rip),%rdi        # 863134 <anon.b9a81f2eeec052eb13297414241e8ab2.30.llvm.7034704448355070909>
  6be455:	48 8d 15 4c 07 37 00 	lea    0x37074c(%rip),%rdx        # a2eba8 <anon.b9a81f2eeec052eb13297414241e8ab2.31.llvm.7034704448355070909>
  6be45c:	be 53 00 00 00       	mov    $0x53,%esi
  6be461:	e8 7a b3 fd ff       	call   6997e0 <core::panicking::panic_fmt>
  6be466:	eb 0c                	jmp    6be474 <user_event_entry+0x3c4>
  6be468:	48 8d 3d 81 13 37 00 	lea    0x371381(%rip),%rdi        # a2f7f0 <anon.082ecd68ea8c03451d37867fa2a1bede.18.llvm.3514461500855303424>
  6be46f:	e8 fc 8f fd ff       	call   697470 <core::option::unwrap_failed>
  6be474:	0f 0b                	ud2
  6be476:	f3 0f 1e fa          	endbr64
  6be47a:	31 ff                	xor    %edi,%edi
  6be47c:	e8 7f dc ff ff       	call   6bc100 <core::ptr::drop_glue::<ostd::irq::guard::DisabledLocalIrqGuard>>
  6be481:	eb 17                	jmp    6be49a <user_event_entry+0x3ea>
  6be483:	f3 0f 1e fa          	endbr64
  6be487:	e8 5f b1 fd ff       	call   6995eb <core::panicking::panic_in_cleanup>
  6be48c:	f3 0f 1e fa          	endbr64
  6be490:	48 8d 7c 24 04       	lea    0x4(%rsp),%rdi
  6be495:	e8 b6 3e 01 00       	call   6d2350 <<ostd::irq::guard::DisabledLocalIrqGuard as core::ops::drop::Drop>::drop>
  6be49a:	e8 e0 b2 fd ff       	call   69977f <core::panicking::panic_cannot_unwind>
  6be49f:	f3 0f 1e fa          	endbr64
  6be4a3:	e8 43 b1 fd ff       	call   6995eb <core::panicking::panic_in_cleanup>
  6be4a8:	f3 0f 1e fa          	endbr64
  6be4ac:	e8 ce b2 fd ff       	call   69977f <core::panicking::panic_cannot_unwind>
