
research/user-page-table/results/syscall-2026-11-17/baseline/image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000003542e0 <aster_core::syscall::getpid::sys_getpid>:
  3542e0:	f3 0f 1e fa          	endbr64
  3542e4:	41 56                	push   %r14
  3542e6:	53                   	push   %rbx
  3542e7:	48 81 ec c8 04 00 00 	sub    $0x4c8,%rsp
  3542ee:	48 89 fb             	mov    %rdi,%rbx
  3542f1:	48 8b 06             	mov    (%rsi),%rax
  3542f4:	48 8b 00             	mov    (%rax),%rax
  3542f7:	8b 80 a0 06 00 00    	mov    0x6a0(%rax),%eax
  3542fd:	89 44 24 04          	mov    %eax,0x4(%rsp)
  354301:	0f b6 0d 28 8c 6e 00 	movzbl 0x6e8c28(%rip),%ecx        # a3cf30 <ostd::log::logger::DYNAMIC_MAX_LEVEL>
  354308:	80 f9 07             	cmp    $0x7,%cl
  35430b:	0f 86 b6 01 00 00    	jbe    3544c7 <aster_core::syscall::getpid::sys_getpid+0x1e7>
  354311:	48 8d 44 24 04       	lea    0x4(%rsp),%rax
  354316:	48 89 44 24 58       	mov    %rax,0x58(%rsp)
  35431b:	48 8d 05 ce 01 39 00 	lea    0x3901ce(%rip),%rax        # 6e44f0 <<u32 as core::fmt::Display>::fmt>
  354322:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  354327:	c6 44 24 54 07       	movb   $0x7,0x54(%rsp)
  35432c:	48 c7 44 24 10 01 00 	movq   $0x1,0x10(%rsp)
  354333:	00 00 
  354335:	48 c7 44 24 18 00 00 	movq   $0x0,0x18(%rsp)
  35433c:	00 00 
  35433e:	48 8d 05 eb 73 4b 00 	lea    0x4b73eb(%rip),%rax        # 80b730 <anon.3a176f640b1e7f25de65cfbb3b7dff0e.570.llvm.2955434022838963355>
  354345:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  35434a:	48 8d 44 24 58       	lea    0x58(%rsp),%rax
  35434f:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  354354:	48 8d 05 90 33 4e 00 	lea    0x4e3390(%rip),%rax        # 8376eb <anon.3a176f640b1e7f25de65cfbb3b7dff0e.571.llvm.2955434022838963355>
  35435b:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  354360:	48 c7 44 24 38 1b 00 	movq   $0x1b,0x38(%rsp)
  354367:	00 00 
  354369:	48 8d 05 96 33 4e 00 	lea    0x4e3396(%rip),%rax        # 837706 <anon.3a176f640b1e7f25de65cfbb3b7dff0e.572.llvm.2955434022838963355>
  354370:	48 89 44 24 40       	mov    %rax,0x40(%rsp)
  354375:	48 c7 44 24 48 b7 00 	movq   $0xb7,0x48(%rsp)
  35437c:	00 00 
  35437e:	c7 44 24 50 08 00 00 	movl   $0x8,0x50(%rsp)
  354385:	00 
  354386:	0f b6 05 9b 8b 6e 00 	movzbl 0x6e8b9b(%rip),%eax        # a3cf28 <ostd::log::logger::LOGGER+0x10>
  35438d:	3c 02                	cmp    $0x2,%al
  35438f:	75 1b                	jne    3543ac <aster_core::syscall::getpid::sys_getpid+0xcc>
  354391:	48 8b 3d 80 8b 6e 00 	mov    0x6e8b80(%rip),%rdi        # a3cf18 <ostd::log::logger::LOGGER>
  354398:	48 8b 05 81 8b 6e 00 	mov    0x6e8b81(%rip),%rax        # a3cf20 <ostd::log::logger::LOGGER+0x8>
  35439f:	48 8d 74 24 10       	lea    0x10(%rsp),%rsi
  3543a4:	ff 50 18             	call   *0x18(%rax)
  3543a7:	e9 17 01 00 00       	jmp    3544c3 <aster_core::syscall::getpid::sys_getpid+0x1e3>
  3543ac:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  3543b1:	0f b6 4c 24 54       	movzbl 0x54(%rsp),%ecx
  3543b6:	88 4c 24 03          	mov    %cl,0x3(%rsp)
  3543ba:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
  3543bf:	48 8b 54 24 18       	mov    0x18(%rsp),%rdx
  3543c4:	48 89 4c 24 68       	mov    %rcx,0x68(%rsp)
  3543c9:	48 89 54 24 70       	mov    %rdx,0x70(%rsp)
  3543ce:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  3543d3:	48 8d 44 24 03       	lea    0x3(%rsp),%rax
  3543d8:	48 89 44 24 78       	mov    %rax,0x78(%rsp)
  3543dd:	48 8b 05 4c bc 6a 00 	mov    0x6abc4c(%rip),%rax        # a00030 <_DYNAMIC+0x56300>
  3543e4:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  3543eb:	00 
  3543ec:	48 8d 44 24 68       	lea    0x68(%rsp),%rax
  3543f1:	48 89 84 24 88 00 00 	mov    %rax,0x88(%rsp)
  3543f8:	00 
  3543f9:	48 8d 05 20 22 3d 00 	lea    0x3d2220(%rip),%rax        # 726620 <<&str as core::fmt::Display>::fmt>
  354400:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  354407:	00 
  354408:	48 8d 44 24 08       	lea    0x8(%rsp),%rax
  35440d:	48 89 84 24 98 00 00 	mov    %rax,0x98(%rsp)
  354414:	00 
  354415:	48 8d 05 e4 21 3d 00 	lea    0x3d21e4(%rip),%rax        # 726600 <<&core::fmt::Arguments as core::fmt::Display>::fmt>
  35441c:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
  354423:	00 
  354424:	4c 8d b4 24 b8 00 00 	lea    0xb8(%rsp),%r14
  35442b:	00 
  35442c:	ba 00 04 00 00       	mov    $0x400,%edx
  354431:	4c 89 f7             	mov    %r14,%rdi
  354434:	31 f6                	xor    %esi,%esi
  354436:	e8 95 2c 3e 00       	call   7370d0 <memset>
  35443b:	c7 84 24 c0 04 00 00 	movl   $0x8,0x4c0(%rsp)
  354442:	08 00 00 00 
  354446:	48 8d 05 23 e8 4c 00 	lea    0x4ce823(%rip),%rax        # 822c70 <anon.e71e009e68217682812176527d749be9.26.llvm.16832139775764504509>
  35444d:	48 89 84 24 a8 00 00 	mov    %rax,0xa8(%rsp)
  354454:	00 
  354455:	48 c7 84 24 b0 00 00 	movq   $0x4,0xb0(%rsp)
  35445c:	00 04 00 00 00 
  354461:	48 c7 84 24 b8 04 00 	movq   $0x0,0x4b8(%rsp)
  354468:	00 00 00 00 00 
  35446d:	48 8d 35 54 a7 6d 00 	lea    0x6da754(%rip),%rsi        # a2ebc8 <anon.e71e009e68217682812176527d749be9.24.llvm.16832139775764504509>
  354474:	48 8d 15 6e 6d 4b 00 	lea    0x4b6d6e(%rip),%rdx        # 80b1e9 <anon.e432324cf268df37f99277e0b05f8fd8.38.llvm.8321110487740406943>
  35447b:	48 8d bc 24 a8 00 00 	lea    0xa8(%rsp),%rdi
  354482:	00 
  354483:	48 8d 4c 24 78       	lea    0x78(%rsp),%rcx
  354488:	e8 73 b3 38 00       	call   6df800 <core::fmt::write>
  35448d:	4c 8b 84 24 b8 04 00 	mov    0x4b8(%rsp),%r8
  354494:	00 
  354495:	4d 85 c0             	test   %r8,%r8
  354498:	74 29                	je     3544c3 <aster_core::syscall::getpid::sys_getpid+0x1e3>
  35449a:	48 8b 05 97 bb 6a 00 	mov    0x6abb97(%rip),%rax        # a00038 <_DYNAMIC+0x56308>
  3544a1:	48 8b 00             	mov    (%rax),%rax
  3544a4:	8b bc 24 c0 04 00 00 	mov    0x4c0(%rsp),%edi
  3544ab:	48 8b b4 24 a8 00 00 	mov    0xa8(%rsp),%rsi
  3544b2:	00 
  3544b3:	8b 94 24 b0 00 00 00 	mov    0xb0(%rsp),%edx
  3544ba:	4c 89 f1             	mov    %r14,%rcx
  3544bd:	ff 90 80 00 00 00    	call   *0x80(%rax)
  3544c3:	8b 44 24 04          	mov    0x4(%rsp),%eax
  3544c7:	89 c0                	mov    %eax,%eax
  3544c9:	48 c7 03 00 00 00 00 	movq   $0x0,(%rbx)
  3544d0:	48 89 43 08          	mov    %rax,0x8(%rbx)
  3544d4:	c7 43 10 00 00 00 00 	movl   $0x0,0x10(%rbx)
  3544db:	48 89 d8             	mov    %rbx,%rax
  3544de:	48 81 c4 c8 04 00 00 	add    $0x4c8,%rsp
  3544e5:	5b                   	pop    %rbx
  3544e6:	41 5e                	pop    %r14
  3544e8:	c3                   	ret
