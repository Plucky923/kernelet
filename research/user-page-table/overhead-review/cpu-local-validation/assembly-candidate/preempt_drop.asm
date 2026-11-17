
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006b75b0 <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop>:
  6b75b0:	f3 0f 1e fa          	endbr64
  6b75b4:	55                   	push   %rbp
  6b75b5:	53                   	push   %rbx
  6b75b6:	50                   	push   %rax
  6b75b7:	e9 f1 fc b7 ff       	jmp    2372ad <__kernelet_cpu_access_start+0x3708c>
  6b75bc:	48 8d 0d 15 31 38 00 	lea    0x383115(%rip),%rcx        # a3a6d8 <ostd::task::preempt::cpu_local::PREEMPT_INFO>
  6b75c3:	48 2b 0d 56 8a 34 00 	sub    0x348a56(%rip),%rcx        # a00020 <_DYNAMIC+0x5fd78>
  6b75ca:	e9 18 fd b7 ff       	jmp    2372e7 <__kernelet_cpu_access_start+0x370c6>
  6b75cf:	ff 0c 0f             	decl   (%rdi,%rcx,1)
  6b75d2:	8b 48 50             	mov    0x50(%rax),%ecx
  6b75d5:	85 c9                	test   %ecx,%ecx
  6b75d7:	74 17                	je     6b75f0 <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0x40>
  6b75d9:	ff c9                	dec    %ecx
  6b75db:	89 48 50             	mov    %ecx,0x50(%rax)
  6b75de:	48 83 c4 08          	add    $0x8,%rsp
  6b75e2:	85 ed                	test   %ebp,%ebp
  6b75e4:	74 03                	je     6b75e9 <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0x39>
  6b75e6:	5b                   	pop    %rbx
  6b75e7:	5d                   	pop    %rbp
  6b75e8:	c3                   	ret
  6b75e9:	5b                   	pop    %rbx
  6b75ea:	5d                   	pop    %rbp
  6b75eb:	e9 60 a9 00 00       	jmp    6c1f50 <ostd::arch::irq::ops::enable_local>
  6b75f0:	48 8d 3d 14 bb 1a 00 	lea    0x1abb14(%rip),%rdi        # 86310b <anon.b9a81f2eeec052eb13297414241e8ab2.26.llvm.7034704448355070909>
  6b75f7:	48 8d 15 62 75 37 00 	lea    0x377562(%rip),%rdx        # a2eb60 <anon.b9a81f2eeec052eb13297414241e8ab2.27.llvm.7034704448355070909>
  6b75fe:	be 29 00 00 00       	mov    $0x29,%esi
  6b7603:	e8 28 fe fd ff       	call   697430 <core::option::expect_failed>
  6b7608:	0f 0b                	ud2
  6b760a:	f3 0f 1e fa          	endbr64
  6b760e:	48 89 c3             	mov    %rax,%rbx
  6b7611:	85 ed                	test   %ebp,%ebp
  6b7613:	75 05                	jne    6b761a <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0x6a>
  6b7615:	e8 36 a9 00 00       	call   6c1f50 <ostd::arch::irq::ops::enable_local>
  6b761a:	48 89 df             	mov    %rbx,%rdi
  6b761d:	e8 de 03 03 00       	call   6e7a00 <_Unwind_Resume>
  6b7622:	f3 0f 1e fa          	endbr64
  6b7626:	e8 c0 1f fe ff       	call   6995eb <core::panicking::panic_in_cleanup>
