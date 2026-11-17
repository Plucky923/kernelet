
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000004ca580 <aster_core::thread::oops::handle_oops>:
  4ca580:	endbr64
  4ca584:	push   %r15
  4ca586:	push   %r14
  4ca588:	push   %r12
  4ca58a:	push   %rbx
  4ca58b:	sub    $0x58,%rsp
  4ca58f:	mov    %rdx,%r12
  4ca592:	mov    %rsi,%r15
  4ca595:	mov    %rdi,%r14
  4ca598:	mov    %rsi,0x48(%rsp)
  4ca59d:	mov    %rdx,0x50(%rsp)
  4ca5a2:	mov    %rsp,%rdi
  4ca5a5:	call   *0x18(%rdx)
  4ca5a8:	movabs $0x97886d2cb797b216,%rax
  4ca5b2:	xor    0x8(%rsp),%rax
  4ca5b7:	movabs $0xcf3ecd36b2a96e1c,%rcx
  4ca5c1:	xor    (%rsp),%rcx
  4ca5c5:	or     %rax,%rcx
  4ca5c8:	mov    %r12,%rbx
  4ca5cb:	cmove  %r15,%rbx
  4ca5cf:	jne    4ca736 <aster_core::thread::oops::handle_oops+0x1b6>
  4ca5d5:	mov    0x8(%r15),%rdi
  4ca5d9:	mov    0x10(%r15),%rcx
  4ca5dd:	cmp    $0x400,%rcx
  4ca5e4:	mov    $0x400,%esi
  4ca5e9:	mov    $0x400,%eax
  4ca5ee:	cmovb  %rcx,%rax
  4ca5f2:	test   %rcx,%rcx
  4ca5f5:	je     4ca612 <aster_core::thread::oops::handle_oops+0x92>
  4ca5f7:	nopw   0x0(%rax,%rax,1)
  4ca600:	cmp    %rcx,%rax
  4ca603:	jae    4ca612 <aster_core::thread::oops::handle_oops+0x92>
  4ca605:	cmpb   $0xbf,(%rdi,%rax,1)
  4ca609:	jg     4ca612 <aster_core::thread::oops::handle_oops+0x92>
  4ca60b:	dec    %rax
  4ca60e:	jne    4ca600 <aster_core::thread::oops::handle_oops+0x80>
  4ca610:	jmp    4ca640 <aster_core::thread::oops::handle_oops+0xc0>
  4ca612:	cmp    $0x400,%rax
  4ca618:	cmovb  %rax,%rsi
  4ca61c:	test   %rax,%rax
  4ca61f:	je     4ca642 <aster_core::thread::oops::handle_oops+0xc2>
  4ca621:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  4ca630:	cmp    %rax,%rsi
  4ca633:	jae    4ca642 <aster_core::thread::oops::handle_oops+0xc2>
  4ca635:	cmpb   $0xbf,(%rdi,%rsi,1)
  4ca639:	jg     4ca642 <aster_core::thread::oops::handle_oops+0xc2>
  4ca63b:	dec    %rsi
  4ca63e:	jne    4ca630 <aster_core::thread::oops::handle_oops+0xb0>
  4ca640:	xor    %esi,%esi
  4ca642:	mov    0x5359ef(%rip),%rax        # a00038 <_DYNAMIC+0x60210>
  4ca649:	mov    (%rax),%rax
  4ca64c:	test   %rax,%rax
  4ca64f:	je     4ca766 <aster_core::thread::oops::handle_oops+0x1e6>
  4ca655:	call   *0x88(%rax)
  4ca65b:	movzbl 0x572826(%rip),%eax        # a3ce88 <ostd::log::logger::DYNAMIC_MAX_LEVEL>
  4ca662:	cmp    $0x3,%al
  4ca664:	jbe    4ca6dd <aster_core::thread::oops::handle_oops+0x15d>
  4ca666:	mov    %rbx,0x48(%rsp)
  4ca66b:	lea    0x1a14e(%rip),%rax        # 4e47c0 <<alloc::string::String as core::fmt::Display>::fmt>
  4ca672:	mov    %rax,0x50(%rsp)
  4ca677:	movb   $0x3,0x44(%rsp)
  4ca67c:	movq   $0x1,(%rsp)
  4ca684:	movq   $0x0,0x8(%rsp)
  4ca68d:	lea    0x34c61e(%rip),%rax        # 816cb2 <anon.fd4f000576a8fa6c442e58a489f5f23c.51.llvm.916454310969770843+0x10f>
  4ca694:	mov    %rax,0x10(%rsp)
  4ca699:	lea    0x48(%rsp),%rax
  4ca69e:	mov    %rax,0x18(%rsp)
  4ca6a3:	lea    0x379cb1(%rip),%rax        # 84435b <anon.fd4f000576a8fa6c442e58a489f5f23c.185.llvm.916454310969770843+0x55>
  4ca6aa:	mov    %rax,0x20(%rsp)
  4ca6af:	movq   $0x18,0x28(%rsp)
  4ca6b8:	lea    0x379cb4(%rip),%rax        # 844373 <anon.fd4f000576a8fa6c442e58a489f5f23c.185.llvm.916454310969770843+0x6d>
  4ca6bf:	mov    %rax,0x30(%rsp)
  4ca6c4:	movq   $0xb4,0x38(%rsp)
  4ca6cd:	movl   $0x41,0x40(%rsp)
  4ca6d5:	mov    %rsp,%rdi
  4ca6d8:	call   6bdae0 <ostd::log::logger::__write_log_record>
  4ca6dd:	mov    $0x1,%eax
  4ca6e2:	lock xadd %rax,0x570cb5(%rip)        # a3b3a0 <aster_core::thread::oops::OOPS_COUNT>
  4ca6eb:	cmp    $0x270f,%rax
  4ca6f1:	ja     4ca780 <aster_core::thread::oops::handle_oops+0x200>
  4ca6f7:	mov    0x18(%rbx),%rax
  4ca6fb:	mov    %rax,0x18(%r14)
  4ca6ff:	mov    0x10(%rbx),%rax
  4ca703:	mov    %rax,0x10(%r14)
  4ca707:	mov    (%rbx),%rax
  4ca70a:	mov    0x8(%rbx),%rcx
  4ca70e:	mov    %rcx,0x8(%r14)
  4ca712:	mov    %rax,(%r14)
  4ca715:	mov    $0x8,%edx
  4ca71a:	mov    $0x20,%ecx
  4ca71f:	mov    %rbx,%rsi
  4ca722:	call   6c82a0 <<ostd::mm::heap::AllocDispatch as core::alloc::global::GlobalAlloc>::dealloc>
  4ca727:	mov    %r14,%rax
  4ca72a:	add    $0x58,%rsp
  4ca72e:	pop    %rbx
  4ca72f:	pop    %r12
  4ca731:	pop    %r14
  4ca733:	pop    %r15
  4ca735:	ret
  4ca736:	mov    %r15,(%rsp)
  4ca73a:	mov    %r12,0x8(%rsp)
  4ca73f:	lea    0x37953f(%rip),%rdi        # 843c85 <anon.fd4f000576a8fa6c442e58a489f5f23c.47.llvm.916454310969770843>
  4ca746:	lea    0x54a38b(%rip),%rcx        # a14ad8 <anon.fd4f000576a8fa6c442e58a489f5f23c.41.llvm.916454310969770843+0x50>
  4ca74d:	lea    0x54c2fc(%rip),%r8        # a16a50 <anon.fd4f000576a8fa6c442e58a489f5f23c.186.llvm.916454310969770843+0x18>
  4ca754:	mov    %rsp,%rdx
  4ca757:	mov    $0x2b,%esi
  4ca75c:	call   6953f0 <core::result::unwrap_failed>
  4ca761:	jmp    4ca7f5 <aster_core::thread::oops::handle_oops+0x275>
  4ca766:	lea    0x3988c7(%rip),%rdi        # 863034 <anon.640ee05cbc79ee72d993a22be3c2086a.30.llvm.10029247957258186659>
  4ca76d:	lea    0x56443c(%rip),%rdx        # a2ebb0 <anon.640ee05cbc79ee72d993a22be3c2086a.31.llvm.10029247957258186659>
  4ca774:	mov    $0x53,%esi
  4ca779:	call   696030 <core::panicking::panic_fmt>
  4ca77e:	jmp    4ca7f5 <aster_core::thread::oops::handle_oops+0x275>
  4ca780:	movzbl 0x572701(%rip),%eax        # a3ce88 <ostd::log::logger::DYNAMIC_MAX_LEVEL>
  4ca787:	cmp    $0x3,%al
  4ca789:	jbe    4ca7f0 <aster_core::thread::oops::handle_oops+0x270>
  4ca78b:	movb   $0x3,0x44(%rsp)
  4ca790:	movq   $0x1,(%rsp)
  4ca798:	movq   $0x0,0x8(%rsp)
  4ca7a1:	lea    0x379c7f(%rip),%rax        # 844427 <anon.fd4f000576a8fa6c442e58a489f5f23c.185.llvm.916454310969770843+0x121>
  4ca7a8:	mov    %rax,0x10(%rsp)
  4ca7ad:	movq   $0x43,0x18(%rsp)
  4ca7b6:	lea    0x379b9e(%rip),%rax        # 84435b <anon.fd4f000576a8fa6c442e58a489f5f23c.185.llvm.916454310969770843+0x55>
  4ca7bd:	mov    %rax,0x20(%rsp)
  4ca7c2:	movq   $0x18,0x28(%rsp)
  4ca7cb:	lea    0x379ba1(%rip),%rax        # 844373 <anon.fd4f000576a8fa6c442e58a489f5f23c.185.llvm.916454310969770843+0x6d>
  4ca7d2:	mov    %rax,0x30(%rsp)
  4ca7d7:	movq   $0xb4,0x38(%rsp)
  4ca7e0:	movl   $0x46,0x40(%rsp)
  4ca7e8:	mov    %rsp,%rdi
  4ca7eb:	call   6bdae0 <ostd::log::logger::__write_log_record>
  4ca7f0:	call   6c75c0 <ostd::panic::abort>
  4ca7f5:	ud2
  4ca7f7:	endbr64
  4ca7fb:	mov    %rax,%r14
  4ca7fe:	lea    0x48(%rsp),%rdi
  4ca803:	call   4b9ca0 <core::ptr::drop_glue::<alloc::boxed::Box<dyn core::any::Any + core::marker::Send>>>
  4ca808:	jmp    4ca83c <aster_core::thread::oops::handle_oops+0x2bc>
  4ca80a:	endbr64
  4ca80e:	call   695e3b <core::panicking::panic_in_cleanup>
  4ca813:	endbr64
  4ca817:	mov    %rax,%r14
  4ca81a:	mov    %rsp,%rdi
  4ca81d:	call   4b9ca0 <core::ptr::drop_glue::<alloc::boxed::Box<dyn core::any::Any + core::marker::Send>>>
  4ca822:	jmp    4ca83c <aster_core::thread::oops::handle_oops+0x2bc>
  4ca824:	endbr64
  4ca828:	call   695e3b <core::panicking::panic_in_cleanup>
  4ca82d:	endbr64
  4ca831:	mov    %rax,%r14
  4ca834:	mov    %rbx,%rdi
  4ca837:	call   4b9d50 <core::ptr::drop_glue::<alloc::boxed::Box<aster_core::thread::oops::OopsInfo>>>
  4ca83c:	mov    %r14,%rdi
  4ca83f:	call   6e4320 <_Unwind_Resume>
  4ca844:	endbr64
  4ca848:	call   695e3b <core::panicking::panic_in_cleanup>
