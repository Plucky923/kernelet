
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000054b2a0 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle>:
  54b2a0:	endbr64
  54b2a4:	push   %rbp
  54b2a5:	push   %r15
  54b2a7:	push   %r14
  54b2a9:	push   %r13
  54b2ab:	push   %r12
  54b2ad:	push   %rbx
  54b2ae:	sub    $0xa8,%rsp
  54b2b5:	mov    %rcx,%r12
  54b2b8:	mov    %rdi,%rbx
  54b2bb:	mov    %dl,0xf(%rsp)
  54b2bf:	mov    %rdi,0x40(%rsp)
  54b2c4:	mov    %rsi,0x80(%rsp)
  54b2cc:	mov    %rsi,0x48(%rsp)
  54b2d1:	lea    0xf(%rsp),%rax
  54b2d6:	mov    %rax,0x50(%rsp)
  54b2db:	mov    %rcx,0x58(%rsp)
  54b2e0:	mov    0x28(%rdi),%rbp
  54b2e4:	mov    0x30(%rdi),%rax
  54b2e8:	lea    0x10(%rsp),%rdi
  54b2ed:	mov    %rbp,%rsi
  54b2f0:	call   *0x18(%rax)
  54b2f3:	movabs $0x3055e825b63270e2,%rax
  54b2fd:	xor    0x18(%rsp),%rax
  54b302:	movabs $0x914bd2fe7b2ae461,%rcx
  54b30c:	xor    0x10(%rsp),%rcx
  54b311:	or     %rax,%rcx
  54b314:	jne    54b607 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x367>
  54b31a:	call   6cc4e0 <<ostd::irq::level::InterruptLevel>::current>
  54b31f:	cmp    $0x2,%al
  54b321:	jne    54b610 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x370>
  54b327:	mov    0x80(%rsp),%rax
  54b32f:	mov    (%rax),%r14
  54b332:	mov    0x70(%r14),%r15
  54b336:	mov    0x78(%r14),%rax
  54b33a:	lea    0x10(%rsp),%rdi
  54b33f:	mov    %r15,%rsi
  54b342:	call   *0x18(%rax)
  54b345:	movabs $0x4d7292a1cf721c3f,%rax
  54b34f:	xor    0x18(%rsp),%rax
  54b354:	movabs $0xa3c1baf054c8d07a,%rcx
  54b35e:	xor    0x10(%rsp),%rcx
  54b363:	or     %rax,%rcx
  54b366:	jne    54b62a <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x38a>
  54b36c:	mov    0x20(%r15),%rax
  54b370:	movabs $0x7fffffffffffffff,%rcx
  54b37a:	cmp    %rcx,%rax
  54b37d:	jae    54b638 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x398>
  54b383:	inc    %rax
  54b386:	mov    %rax,0x20(%r15)
  54b38a:	cmpq   $0x0,0x28(%r15)
  54b38f:	je     54b646 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x3a6>
  54b395:	lea    0x28(%r15),%r13
  54b399:	mov    %r13,0x10(%rsp)
  54b39e:	mov    %r15,0x18(%rsp)
  54b3a3:	mov    %rbp,0x20(%rsp)
  54b3a8:	mov    %rbx,0x28(%rsp)
  54b3ad:	mov    %r14,0x30(%rsp)
  54b3b2:	movzbl 0xf(%rsp),%eax
  54b3b7:	test   %eax,%eax
  54b3b9:	je     54b42f <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x18f>
  54b3bb:	cmp    $0x1,%eax
  54b3be:	jne    54b48c <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x1ec>
  54b3c4:	mov    0xb0(%r12),%rax
  54b3cc:	movq   $0xffffffffffffffff,0xb0(%r12)
  54b3d8:	cmp    $0xffffffffffffffff,%rax
  54b3dc:	je     54b64f <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x3af>
  54b3e2:	mov    %rax,0x88(%rsp)
  54b3ea:	mov    0xb8(%r12),%rax
  54b3f2:	mov    0xc0(%r12),%rcx
  54b3fa:	mov    %rax,0x90(%rsp)
  54b402:	mov    %rcx,0x98(%rsp)
  54b40a:	movq   $0x0,0xc0(%r15)
  54b415:	lea    0x10(%rsp),%rdi
  54b41a:	lea    0x88(%rsp),%rdx
  54b422:	mov    %r12,%rsi
  54b425:	call   594090 <aster_core::thread::exception::handle_exception>
  54b42a:	jmp    54b525 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x285>
  54b42f:	mov    0x8(%r12),%rax
  54b434:	add    $0x50,%rax
  54b438:	cmpb   $0x0,(%r12)
  54b43d:	lea    0x58(%r12),%rcx
  54b442:	cmovne %rax,%rcx
  54b446:	mov    (%rcx),%rax
  54b449:	movq   $0x1,0xc0(%r15)
  54b454:	mov    %rax,0xc8(%r15)
  54b45b:	movzbl 0x3e0(%rbp),%eax
  54b462:	cmp    $0x2,%al
  54b464:	jne    54b4ab <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x20b>
  54b466:	lea    0x258(%rbp),%rsi
  54b46d:	lea    0x60(%rsp),%rdi
  54b472:	lea    0x10(%rsp),%rdx
  54b477:	mov    %r12,%rcx
  54b47a:	call   569590 <<aster_core::process::posix_thread::ptrace::TraceeStatus>::ptrace_may_stop_on_syscall>
  54b47f:	cmpq   $0x1,0x60(%rsp)
  54b485:	jne    54b4bd <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x21d>
  54b487:	jmp    54b51b <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x27b>
  54b48c:	movq   $0x0,0xc0(%r15)
  54b497:	movzbl 0x80(%rbx),%eax
  54b49e:	test   %al,%al
  54b4a0:	jne    54b548 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2a8>
  54b4a6:	jmp    54b530 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x290>
  54b4ab:	movq   $0x2,0x68(%rsp)
  54b4b4:	movq   $0x2,0x60(%rsp)
  54b4bd:	lea    0x10(%rsp),%rdi
  54b4c2:	mov    %r12,%rsi
  54b4c5:	call   592d50 <aster_core::syscall::handle_syscall>
  54b4ca:	movzbl 0x3e0(%rbp),%eax
  54b4d1:	cmp    $0x2,%al
  54b4d3:	jne    54b4f6 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x256>
  54b4d5:	add    $0x258,%rbp
  54b4dc:	lea    0x88(%rsp),%rdi
  54b4e4:	lea    0x10(%rsp),%rdx
  54b4e9:	mov    %rbp,%rsi
  54b4ec:	mov    %r12,%rcx
  54b4ef:	call   569590 <<aster_core::process::posix_thread::ptrace::TraceeStatus>::ptrace_may_stop_on_syscall>
  54b4f4:	jmp    54b50e <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x26e>
  54b4f6:	movq   $0x2,0x90(%rsp)
  54b502:	movq   $0x2,0x88(%rsp)
  54b50e:	lea    0x88(%rsp),%rdi
  54b516:	call   525ed0 <core::ptr::drop_glue::<aster_core::process::posix_thread::ptrace::util::PtraceStopResult>>
  54b51b:	lea    0x60(%rsp),%rdi
  54b520:	call   525ed0 <core::ptr::drop_glue::<aster_core::process::posix_thread::ptrace::util::PtraceStopResult>>
  54b525:	movzbl 0x80(%rbx),%eax
  54b52c:	test   %al,%al
  54b52e:	jne    54b548 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2a8>
  54b530:	lea    0x10(%rsp),%rsi
  54b535:	mov    %r12,%rdi
  54b538:	call   594820 <aster_core::process::signal::handle_pending_signal>
  54b53d:	movzbl 0x80(%rbx),%eax
  54b544:	test   %al,%al
  54b546:	je     54b55e <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2be>
  54b548:	decq   0x20(%r15)
  54b54c:	add    $0xa8,%rsp
  54b553:	pop    %rbx
  54b554:	pop    %r12
  54b556:	pop    %r13
  54b558:	pop    %r14
  54b55a:	pop    %r15
  54b55c:	pop    %rbp
  54b55d:	ret
  54b55e:	lea    0x60(%rsp),%rbp
  54b563:	lea    0x10(%rsp),%r14
  54b568:	jmp    54b57b <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2db>
  54b56a:	nopw   0x0(%rax,%rax,1)
  54b570:	movzbl 0x80(%rbx),%eax
  54b577:	test   %al,%al
  54b579:	jne    54b548 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2a8>
  54b57b:	mov    0x0(%r13),%rax
  54b57f:	movzbl 0x698(%rax),%eax
  54b586:	test   %al,%al
  54b588:	je     54b548 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2a8>
  54b58a:	call   6d6cc0 <<ostd::sync::wait::Waiter>::new_pair>
  54b58f:	mov    %rax,0x88(%rsp)
  54b597:	mov    %rdx,0x90(%rsp)
  54b59f:	mov    %rax,0x60(%rsp)
  54b5a4:	lock decq (%rdx)
  54b5a8:	jne    54b5b7 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x317>
  54b5aa:	lea    0x90(%rsp),%rdi
  54b5b2:	call   6bc160 <<alloc::sync::Arc<ostd::sync::wait::Waker>>::drop_slow>
  54b5b7:	lea    0x88(%rsp),%rdi
  54b5bf:	mov    %rbp,%rsi
  54b5c2:	mov    %r13,%rdx
  54b5c5:	mov    $0x1,%ecx
  54b5ca:	lea    0x4d0a97(%rip),%r8        # a1c068 <anon.b67fb28ca0c888ac7fce900d751e1979.12.llvm.8086507298010013112+0x288>
  54b5d1:	call   5616b0 <<ostd::sync::wait::Waiter as aster_core::process::signal::pause::Pause>::pause_until_by::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}::{closure#0}, ()>>
  54b5d6:	mov    %r12,%rdi
  54b5d9:	mov    %r14,%rsi
  54b5dc:	call   594820 <aster_core::process::signal::handle_pending_signal>
  54b5e1:	mov    0x60(%rsp),%rax
  54b5e6:	mov    $0x1,%cl
  54b5e8:	xchg   %cl,0x18(%rax)
  54b5eb:	mov    0x60(%rsp),%rax
  54b5f0:	lock decq (%rax)
  54b5f4:	jne    54b570 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2d0>
  54b5fa:	mov    %rbp,%rdi
  54b5fd:	call   6bc160 <<alloc::sync::Arc<ostd::sync::wait::Waker>>::drop_slow>
  54b602:	jmp    54b570 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2d0>
  54b607:	lea    0x4d09e2(%rip),%rdi        # a1bff0 <anon.b67fb28ca0c888ac7fce900d751e1979.12.llvm.8086507298010013112+0x210>
  54b60e:	jmp    54b631 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x391>
  54b610:	lea    0x316a8c(%rip),%rdi        # 8620a3 <anon.49bf9ad671d8bfc407d32ba9fbfd84b8.5.llvm.15122895417035496165>
  54b617:	lea    0x4e29ba(%rip),%rdx        # a2dfd8 <anon.49bf9ad671d8bfc407d32ba9fbfd84b8.6.llvm.15122895417035496165>
  54b61e:	mov    $0x3d,%esi
  54b623:	call   696010 <core::panicking::panic>
  54b628:	jmp    54b65b <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x3bb>
  54b62a:	lea    0x4d09d7(%rip),%rdi        # a1c008 <anon.b67fb28ca0c888ac7fce900d751e1979.12.llvm.8086507298010013112+0x228>
  54b631:	call   693cc0 <core::option::unwrap_failed>
  54b636:	jmp    54b65b <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x3bb>
  54b638:	lea    0x4d09e1(%rip),%rdi        # a1c020 <anon.b67fb28ca0c888ac7fce900d751e1979.12.llvm.8086507298010013112+0x240>
  54b63f:	call   694e20 <core::cell::panic_already_mutably_borrowed>
  54b644:	jmp    54b65b <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x3bb>
  54b646:	lea    0x4d09eb(%rip),%rdi        # a1c038 <anon.b67fb28ca0c888ac7fce900d751e1979.12.llvm.8086507298010013112+0x258>
  54b64d:	jmp    54b656 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x3b6>
  54b64f:	lea    0x4d09fa(%rip),%rdi        # a1c050 <anon.b67fb28ca0c888ac7fce900d751e1979.12.llvm.8086507298010013112+0x270>
  54b656:	call   693cc0 <core::option::unwrap_failed>
  54b65b:	ud2
  54b65d:	endbr64
  54b661:	mov    %rax,%r14
  54b664:	lea    0x60(%rsp),%rdi
  54b669:	call   525ed0 <core::ptr::drop_glue::<aster_core::process::posix_thread::ptrace::util::PtraceStopResult>>
  54b66e:	jmp    54b6a1 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x401>
  54b670:	endbr64
  54b674:	jmp    54b6b7 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x417>
  54b676:	endbr64
  54b67a:	mov    %rax,%r14
  54b67d:	mov    0x60(%rsp),%rax
  54b682:	mov    $0x1,%cl
  54b684:	xchg   %cl,0x18(%rax)
  54b687:	mov    0x60(%rsp),%rax
  54b68c:	lock decq (%rax)
  54b690:	jne    54b6a1 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x401>
  54b692:	lea    0x60(%rsp),%rdi
  54b697:	call   6bc160 <<alloc::sync::Arc<ostd::sync::wait::Waker>>::drop_slow>
  54b69c:	mov    %r14,%rsi
  54b69f:	jmp    54b6ba <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x41a>
  54b6a1:	mov    %r14,%rsi
  54b6a4:	decq   0x20(%r15)
  54b6a8:	jmp    54b6c7 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x427>
  54b6aa:	endbr64
  54b6ae:	call   695e3b <core::panicking::panic_in_cleanup>
  54b6b3:	endbr64
  54b6b7:	mov    %rax,%rsi
  54b6ba:	decq   0x20(%r15)
  54b6be:	jmp    54b6c7 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x427>
  54b6c0:	endbr64
  54b6c4:	mov    %rax,%rsi
  54b6c7:	lea    0x40(%rsp),%rdi
  54b6cc:	call   387d00 <unwinding::panicking::catch_unwind::do_catch::<unwinding::panic::RustPanic>>
  54b6d1:	mov    0x40(%rsp),%rdi
  54b6d6:	mov    0x48(%rsp),%rsi
  54b6db:	call   6e3e40 <unwinding::panic::catch_unwind::process_panic>
  54b6e0:	test   %rax,%rax
  54b6e3:	je     54b54c <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2ac>
  54b6e9:	mov    %rax,%r15
  54b6ec:	mov    %rdx,%r14
  54b6ef:	call   6c73d0 <ostd::panic::report_caught_panic>
  54b6f4:	lea    0x40(%rsp),%rdi
  54b6f9:	mov    %r15,%rsi
  54b6fc:	mov    %r14,%rdx
  54b6ff:	call   4ca580 <aster_core::thread::oops::handle_oops>
  54b704:	mov    0x40(%rsp),%r14
  54b709:	cmp    $0xffffffffffffffff,%r14
  54b70d:	je     54b54c <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2ac>
  54b713:	mov    0x80(%rsp),%rax
  54b71b:	mov    (%rax),%rsi
  54b71e:	mov    %rbx,%rdi
  54b721:	call   535470 <aster_core::thread::task::exit_current_after_oops>
  54b726:	test   %r14,%r14
  54b729:	je     54b73d <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x49d>
  54b72b:	mov    0x48(%rsp),%rsi
  54b730:	mov    $0x1,%edx
  54b735:	mov    %r14,%rcx
  54b738:	call   6c82a0 <<ostd::mm::heap::AllocDispatch as core::alloc::global::GlobalAlloc>::dealloc>
  54b73d:	mov    0x58(%rsp),%rax
  54b742:	lock decq (%rax)
  54b746:	jne    54b54c <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2ac>
  54b74c:	lea    0x58(%rsp),%rdi
  54b751:	call   438930 <<alloc::sync::Arc<aster_core::thread::Thread>>::drop_slow>
  54b756:	jmp    54b54c <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2ac>
  54b75b:	endbr64
  54b75f:	mov    %rax,%rbx
  54b762:	lea    0x40(%rsp),%rdi
  54b767:	call   522db0 <core::ptr::drop_glue::<core::result::Result<(), aster_core::thread::oops::OopsInfo>>>
  54b76c:	jmp    54b789 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x4e9>
  54b76e:	endbr64
  54b772:	call   695e3b <core::panicking::panic_in_cleanup>
  54b777:	endbr64
  54b77b:	mov    %rax,%rbx
  54b77e:	mov    %r15,%rdi
  54b781:	mov    %r14,%rsi
  54b784:	call   522d50 <core::ptr::drop_glue::<core::result::Result<(), alloc::boxed::Box<dyn core::any::Any + core::marker::Send>>>>
  54b789:	mov    %rbx,%rdi
  54b78c:	call   6e4320 <_Unwind_Resume>
  54b791:	endbr64
  54b795:	call   695e3b <core::panicking::panic_in_cleanup>
