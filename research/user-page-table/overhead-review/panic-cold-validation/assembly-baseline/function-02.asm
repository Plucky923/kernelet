
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-baseline.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000044e530 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>>:
  44e530:	endbr64
  44e534:	push   %r15
  44e536:	push   %r14
  44e538:	push   %r12
  44e53a:	push   %rbx
  44e53b:	sub    $0x58,%rsp
  44e53f:	mov    %rdi,%r14
  44e542:	mov    %rsi,%rdi
  44e545:	call   47dc90 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>>
  44e54a:	test   %rax,%rax
  44e54d:	je     44e6e9 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0x1b9>
  44e553:	mov    %rax,%r15
  44e556:	mov    %rdx,%r12
  44e559:	mov    %rax,0x48(%rsp)
  44e55e:	mov    %rdx,0x50(%rsp)
  44e563:	mov    %rsp,%rdi
  44e566:	mov    %rax,%rsi
  44e569:	call   *0x18(%rdx)
  44e56c:	movabs $0x73be6c8310941a54,%rax
  44e576:	xor    0x8(%rsp),%rax
  44e57b:	movabs $0x292c2ec78f41bf60,%rcx
  44e585:	xor    (%rsp),%rcx
  44e589:	or     %rax,%rcx
  44e58c:	mov    %r15,%rbx
  44e58f:	cmovne %r12,%rbx
  44e593:	jne    44e6ff <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0x1cf>
  44e599:	mov    0x8(%r15),%rdi
  44e59d:	mov    0x10(%r15),%rcx
  44e5a1:	cmp    $0x400,%rcx
  44e5a8:	mov    $0x400,%esi
  44e5ad:	mov    $0x400,%eax
  44e5b2:	cmovb  %rcx,%rax
  44e5b6:	test   %rcx,%rcx
  44e5b9:	je     44e5d2 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0xa2>
  44e5bb:	nopl   0x0(%rax,%rax,1)
  44e5c0:	cmp    %rcx,%rax
  44e5c3:	jae    44e5d2 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0xa2>
  44e5c5:	cmpb   $0xbf,(%rdi,%rax,1)
  44e5c9:	jg     44e5d2 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0xa2>
  44e5cb:	dec    %rax
  44e5ce:	jne    44e5c0 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0x90>
  44e5d0:	jmp    44e600 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0xd0>
  44e5d2:	cmp    $0x400,%rax
  44e5d8:	cmovb  %rax,%rsi
  44e5dc:	test   %rax,%rax
  44e5df:	je     44e602 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0xd2>
  44e5e1:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  44e5f0:	cmp    %rax,%rsi
  44e5f3:	jae    44e602 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0xd2>
  44e5f5:	cmpb   $0xbf,(%rdi,%rsi,1)
  44e5f9:	jg     44e602 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0xd2>
  44e5fb:	dec    %rsi
  44e5fe:	jne    44e5f0 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0xc0>
  44e600:	xor    %esi,%esi
  44e602:	mov    0x5b1a2f(%rip),%rax        # a00038 <_DYNAMIC+0x5fe50>
  44e609:	mov    (%rax),%rax
  44e60c:	test   %rax,%rax
  44e60f:	je     44e72f <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0x1ff>
  44e615:	call   *0x88(%rax)
  44e61b:	movzbl 0x5ee866(%rip),%eax        # a3ce88 <ostd::log::logger::DYNAMIC_MAX_LEVEL>
  44e622:	cmp    $0x3,%al
  44e624:	jbe    44e69d <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0x16d>
  44e626:	mov    %rbx,0x48(%rsp)
  44e62b:	lea    0x2824e(%rip),%rax        # 476880 <<alloc::string::String as core::fmt::Display>::fmt>
  44e632:	mov    %rax,0x50(%rsp)
  44e637:	movb   $0x3,0x44(%rsp)
  44e63c:	movq   $0x1,(%rsp)
  44e644:	movq   $0x0,0x8(%rsp)
  44e64d:	lea    0x3c8767(%rip),%rax        # 816dbb <anon.aecc9a89757d91c4e8263f5e59c0c8b5.61.llvm.1405205997946210488+0x203>
  44e654:	mov    %rax,0x10(%rsp)
  44e659:	lea    0x48(%rsp),%rax
  44e65e:	mov    %rax,0x18(%rsp)
  44e663:	lea    0x3f184a(%rip),%rax        # 83feb4 <anon.aecc9a89757d91c4e8263f5e59c0c8b5.516.llvm.1405205997946210488+0x2f7>
  44e66a:	mov    %rax,0x20(%rsp)
  44e66f:	movq   $0x18,0x28(%rsp)
  44e678:	lea    0x3f184d(%rip),%rax        # 83fecc <anon.aecc9a89757d91c4e8263f5e59c0c8b5.516.llvm.1405205997946210488+0x30f>
  44e67f:	mov    %rax,0x30(%rsp)
  44e684:	movq   $0xb4,0x38(%rsp)
  44e68d:	movl   $0x40,0x40(%rsp)
  44e695:	mov    %rsp,%rdi
  44e698:	call   6c0ba0 <ostd::log::logger::__write_log_record>
  44e69d:	mov    $0x1,%eax
  44e6a2:	lock xadd %rax,0x5ec895(%rip)        # a3af40 <aster_core::thread::oops::OOPS_COUNT>
  44e6ab:	cmp    $0x270f,%rax
  44e6b1:	ja     44e749 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0x219>
  44e6b7:	mov    0x18(%rbx),%rax
  44e6bb:	mov    %rax,0x18(%r14)
  44e6bf:	mov    0x10(%rbx),%rax
  44e6c3:	mov    %rax,0x10(%r14)
  44e6c7:	mov    (%rbx),%rax
  44e6ca:	mov    0x8(%rbx),%rcx
  44e6ce:	mov    %rcx,0x8(%r14)
  44e6d2:	mov    %rax,(%r14)
  44e6d5:	mov    $0x8,%edx
  44e6da:	mov    $0x20,%ecx
  44e6df:	mov    %rbx,%rsi
  44e6e2:	call   6cf1e0 <<ostd::mm::heap::AllocDispatch as core::alloc::global::GlobalAlloc>::dealloc>
  44e6e7:	jmp    44e6f0 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0x1c0>
  44e6e9:	movq   $0xffffffffffffffff,(%r14)
  44e6f0:	mov    %r14,%rax
  44e6f3:	add    $0x58,%rsp
  44e6f7:	pop    %rbx
  44e6f8:	pop    %r12
  44e6fa:	pop    %r14
  44e6fc:	pop    %r15
  44e6fe:	ret
  44e6ff:	mov    %r15,(%rsp)
  44e703:	mov    %r12,0x8(%rsp)
  44e708:	lea    0x3f189f(%rip),%rdi        # 83ffae <anon.7200fa5fe448993de6c8e4f60a327c2f.53.llvm.12614982092476800003>
  44e70f:	lea    0x5c6222(%rip),%rcx        # a14938 <anon.7200fa5fe448993de6c8e4f60a327c2f.47.llvm.12614982092476800003+0x50>
  44e716:	lea    0x5c619b(%rip),%r8        # a148b8 <anon.7200fa5fe448993de6c8e4f60a327c2f.34.llvm.12614982092476800003+0x18>
  44e71d:	mov    %rsp,%rdx
  44e720:	mov    $0x2b,%esi
  44e725:	call   698770 <core::result::unwrap_failed>
  44e72a:	jmp    44e7be <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0x28e>
  44e72f:	lea    0x4149f6(%rip),%rdi        # 86312c <anon.afbcb67d570395342e5c7b93cc9f14b2.30.llvm.5541347225946096535>
  44e736:	lea    0x5e046b(%rip),%rdx        # a2eba8 <anon.afbcb67d570395342e5c7b93cc9f14b2.31.llvm.5541347225946096535>
  44e73d:	mov    $0x53,%esi
  44e742:	call   6993b0 <core::panicking::panic_fmt>
  44e747:	jmp    44e7be <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0x28e>
  44e749:	movzbl 0x5ee738(%rip),%eax        # a3ce88 <ostd::log::logger::DYNAMIC_MAX_LEVEL>
  44e750:	cmp    $0x3,%al
  44e752:	jbe    44e7b9 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0x289>
  44e754:	movb   $0x3,0x44(%rsp)
  44e759:	movq   $0x1,(%rsp)
  44e761:	movq   $0x0,0x8(%rsp)
  44e76a:	lea    0x3f180f(%rip),%rax        # 83ff80 <anon.aecc9a89757d91c4e8263f5e59c0c8b5.516.llvm.1405205997946210488+0x3c3>
  44e771:	mov    %rax,0x10(%rsp)
  44e776:	movq   $0x43,0x18(%rsp)
  44e77f:	lea    0x3f172e(%rip),%rax        # 83feb4 <anon.aecc9a89757d91c4e8263f5e59c0c8b5.516.llvm.1405205997946210488+0x2f7>
  44e786:	mov    %rax,0x20(%rsp)
  44e78b:	movq   $0x18,0x28(%rsp)
  44e794:	lea    0x3f1731(%rip),%rax        # 83fecc <anon.aecc9a89757d91c4e8263f5e59c0c8b5.516.llvm.1405205997946210488+0x30f>
  44e79b:	mov    %rax,0x30(%rsp)
  44e7a0:	movq   $0xb4,0x38(%rsp)
  44e7a9:	movl   $0x45,0x40(%rsp)
  44e7b1:	mov    %rsp,%rdi
  44e7b4:	call   6c0ba0 <ostd::log::logger::__write_log_record>
  44e7b9:	call   6ce560 <ostd::panic::abort>
  44e7be:	ud2
  44e7c0:	endbr64
  44e7c4:	mov    %rax,%r14
  44e7c7:	lea    0x48(%rsp),%rdi
  44e7cc:	call   44cba0 <core::ptr::drop_glue::<alloc::boxed::Box<dyn core::any::Any + core::marker::Send>>>
  44e7d1:	jmp    44e805 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0x2d5>
  44e7d3:	endbr64
  44e7d7:	call   6991bb <core::panicking::panic_in_cleanup>
  44e7dc:	endbr64
  44e7e0:	mov    %rax,%r14
  44e7e3:	mov    %rsp,%rdi
  44e7e6:	call   44cba0 <core::ptr::drop_glue::<alloc::boxed::Box<dyn core::any::Any + core::marker::Send>>>
  44e7eb:	jmp    44e805 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>+0x2d5>
  44e7ed:	endbr64
  44e7f1:	call   6991bb <core::panicking::panic_in_cleanup>
  44e7f6:	endbr64
  44e7fa:	mov    %rax,%r14
  44e7fd:	mov    %rbx,%rdi
  44e800:	call   44cc50 <core::ptr::drop_glue::<alloc::boxed::Box<aster_core::thread::oops::OopsInfo>>>
  44e805:	mov    %r14,%rdi
  44e808:	call   6e7070 <_Unwind_Resume>
  44e80d:	endbr64
  44e811:	call   6991bb <core::panicking::panic_in_cleanup>
