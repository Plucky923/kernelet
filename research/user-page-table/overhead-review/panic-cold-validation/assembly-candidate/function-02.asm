
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000535470 <aster_core::thread::task::exit_current_after_oops>:
  535470:	push   %r15
  535472:	push   %r14
  535474:	push   %r12
  535476:	push   %rbx
  535477:	sub    $0x48,%rsp
  53547b:	mov    %rsi,%r14
  53547e:	mov    %rdi,%r15
  535481:	mov    0x28(%rdi),%r12
  535485:	mov    0x30(%rdi),%rax
  535489:	lea    0x10(%rsp),%rdi
  53548e:	mov    %r12,%rsi
  535491:	call   *0x18(%rax)
  535494:	movabs $0x3055e825b63270e2,%rax
  53549e:	xor    0x18(%rsp),%rax
  5354a3:	movabs $0x914bd2fe7b2ae461,%rcx
  5354ad:	xor    0x10(%rsp),%rcx
  5354b2:	or     %rax,%rcx
  5354b5:	jne    535607 <aster_core::thread::task::exit_current_after_oops+0x197>
  5354bb:	call   6cc4e0 <<ostd::irq::level::InterruptLevel>::current>
  5354c0:	cmp    $0x2,%al
  5354c2:	jne    535613 <aster_core::thread::task::exit_current_after_oops+0x1a3>
  5354c8:	mov    0x70(%r14),%rbx
  5354cc:	mov    0x78(%r14),%rax
  5354d0:	lea    0x10(%rsp),%rdi
  5354d5:	mov    %rbx,%rsi
  5354d8:	call   *0x18(%rax)
  5354db:	movabs $0x4d7292a1cf721c3f,%rax
  5354e5:	xor    0x18(%rsp),%rax
  5354ea:	movabs $0xa3c1baf054c8d07a,%rcx
  5354f4:	xor    0x10(%rsp),%rcx
  5354f9:	or     %rax,%rcx
  5354fc:	jne    53562b <aster_core::thread::task::exit_current_after_oops+0x1bb>
  535502:	mov    (%r12),%rcx
  535506:	cmp    $0xffffffffffffffff,%rcx
  53550a:	je     535645 <aster_core::thread::task::exit_current_after_oops+0x1d5>
  535510:	mov    (%rcx),%rax
  535513:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  535520:	test   %rax,%rax
  535523:	je     535645 <aster_core::thread::task::exit_current_after_oops+0x1d5>
  535529:	js     5355d7 <aster_core::thread::task::exit_current_after_oops+0x167>
  53552f:	lea    0x1(%rax),%rdx
  535533:	lock cmpxchg %rdx,(%rcx)
  535538:	jne    535520 <aster_core::thread::task::exit_current_after_oops+0xb0>
  53553a:	mov    %rcx,0x8(%rsp)
  53553f:	lea    0x8(%rsp),%rax
  535544:	mov    %rax,0x10(%rsp)
  535549:	mov    %rbx,0x18(%rsp)
  53554e:	mov    %r12,0x20(%rsp)
  535553:	mov    %r15,0x28(%rsp)
  535558:	mov    %r14,0x30(%rsp)
  53555d:	lea    0x10(%rsp),%rcx
  535562:	mov    $0x1,%edi
  535567:	mov    $0x9,%esi
  53556c:	mov    $0x1,%edx
  535571:	xor    %r8d,%r8d
  535574:	call   59fac0 <aster_core::process::posix_thread::exit::exit_internal>
  535579:	cmpq   $0x0,0x20(%rbx)
  53557e:	jne    535637 <aster_core::thread::task::exit_current_after_oops+0x1c7>
  535584:	movq   $0xffffffffffffffff,0x20(%rbx)
  53558c:	mov    0x28(%rbx),%rax
  535590:	mov    %rax,0x40(%rsp)
  535595:	movq   $0x0,0x28(%rbx)
  53559d:	test   %rax,%rax
  5355a0:	je     5355b2 <aster_core::thread::task::exit_current_after_oops+0x142>
  5355a2:	lock decq (%rax)
  5355a6:	jne    5355b2 <aster_core::thread::task::exit_current_after_oops+0x142>
  5355a8:	lea    0x40(%rsp),%rdi
  5355ad:	call   4393b0 <<alloc::sync::Arc<aster_core::process::process::Process>>::drop_slow>
  5355b2:	incq   0x20(%rbx)
  5355b6:	mov    0x8(%rsp),%rax
  5355bb:	lock decq (%rax)
  5355bf:	jne    5355cb <aster_core::thread::task::exit_current_after_oops+0x15b>
  5355c1:	lea    0x8(%rsp),%rdi
  5355c6:	call   4393b0 <<alloc::sync::Arc<aster_core::process::process::Process>>::drop_slow>
  5355cb:	add    $0x48,%rsp
  5355cf:	pop    %rbx
  5355d0:	pop    %r12
  5355d2:	pop    %r14
  5355d4:	pop    %r15
  5355d6:	ret
  5355d7:	lea    0x4dbe6a(%rip),%rax        # a11448 <anon.2694360f09523cfbf7e2089f024ea9fe.229.llvm.12369045332049190093>
  5355de:	mov    %rax,0x10(%rsp)
  5355e3:	lea    0x769b6(%rip),%rax        # 5abfa0 <<&str as core::fmt::Display>::fmt>
  5355ea:	mov    %rax,0x18(%rsp)
  5355ef:	lea    0x2d6198(%rip),%rdi        # 80b78e <anon.044108d607e335c5591a74b09aef36a6.2.llvm.5441273256934702530>
  5355f6:	lea    0x4dbf93(%rip),%rdx        # a11590 <anon.2694360f09523cfbf7e2089f024ea9fe.273.llvm.12369045332049190093>
  5355fd:	lea    0x10(%rsp),%rsi
  535602:	call   696030 <core::panicking::panic_fmt>
  535607:	lea    0x4e73f2(%rip),%rdi        # a1ca00 <anon.b67fb28ca0c888ac7fce900d751e1979.173.llvm.8086507298010013112+0x30>
  53560e:	call   693cc0 <core::option::unwrap_failed>
  535613:	lea    0x32ca89(%rip),%rdi        # 8620a3 <anon.49bf9ad671d8bfc407d32ba9fbfd84b8.5.llvm.15122895417035496165>
  53561a:	lea    0x4f89b7(%rip),%rdx        # a2dfd8 <anon.49bf9ad671d8bfc407d32ba9fbfd84b8.6.llvm.15122895417035496165>
  535621:	mov    $0x3d,%esi
  535626:	call   696010 <core::panicking::panic>
  53562b:	lea    0x4e73e6(%rip),%rdi        # a1ca18 <anon.b67fb28ca0c888ac7fce900d751e1979.173.llvm.8086507298010013112+0x48>
  535632:	call   693cc0 <core::option::unwrap_failed>
  535637:	lea    0x4e73f2(%rip),%rdi        # a1ca30 <anon.b67fb28ca0c888ac7fce900d751e1979.173.llvm.8086507298010013112+0x60>
  53563e:	call   694de0 <core::cell::panic_already_borrowed>
  535643:	ud2
  535645:	lea    0x4df54c(%rip),%rdi        # a14b98 <anon.fd4f000576a8fa6c442e58a489f5f23c.58.llvm.916454310969770843>
  53564c:	call   693cc0 <core::option::unwrap_failed>
  535651:	endbr64
  535655:	mov    %rax,%r14
  535658:	incq   0x20(%rbx)
  53565c:	jmp    535665 <aster_core::thread::task::exit_current_after_oops+0x1f5>
  53565e:	endbr64
  535662:	mov    %rax,%r14
  535665:	mov    0x8(%rsp),%rax
  53566a:	lock decq (%rax)
  53566e:	jne    53567a <aster_core::thread::task::exit_current_after_oops+0x20a>
  535670:	lea    0x8(%rsp),%rdi
  535675:	call   4393b0 <<alloc::sync::Arc<aster_core::process::process::Process>>::drop_slow>
  53567a:	mov    %r14,%rdi
  53567d:	call   6e4320 <_Unwind_Resume>
  535682:	endbr64
  535686:	call   695e3b <core::panicking::panic_in_cleanup>
