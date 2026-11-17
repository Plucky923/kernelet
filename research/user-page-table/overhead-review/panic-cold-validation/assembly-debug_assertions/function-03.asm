
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-debug-assertions.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000003140d0 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle>:
  3140d0:	endbr64
  3140d4:	push   %rbp
  3140d5:	push   %r15
  3140d7:	push   %r14
  3140d9:	push   %r13
  3140db:	push   %r12
  3140dd:	push   %rbx
  3140de:	sub    $0xc8,%rsp
  3140e5:	mov    %dl,0x7(%rsp)
  3140e9:	mov    %rdi,0xa8(%rsp)
  3140f1:	mov    %rsi,0xa0(%rsp)
  3140f9:	mov    %rsi,0xb0(%rsp)
  314101:	lea    0x7(%rsp),%rax
  314106:	mov    %rax,0xb8(%rsp)
  31410e:	mov    %rcx,0x8(%rsp)
  314113:	mov    %rcx,0xc0(%rsp)
  31411b:	mov    0x28(%rdi),%rbp
  31411f:	mov    %rdi,0x10(%rsp)
  314124:	mov    0x30(%rdi),%rax
  314128:	mov    0x18(%rax),%r14
  31412c:	lea    0x30(%rsp),%rdi
  314131:	mov    %rbp,%rsi
  314134:	call   *%r14
  314137:	movabs $0xb6f403ec7315cb2f,%r15
  314141:	movabs $0x8eed1c0dfa03cece,%rbx
  31414b:	mov    0x38(%rsp),%rax
  314150:	xor    %r15,%rax
  314153:	mov    0x30(%rsp),%rcx
  314158:	xor    %rbx,%rcx
  31415b:	or     %rax,%rcx
  31415e:	jne    31460d <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x53d>
  314164:	lea    0x30(%rsp),%rdi
  314169:	mov    %rbp,%rsi
  31416c:	call   *%r14
  31416f:	xor    0x30(%rsp),%rbx
  314174:	xor    0x38(%rsp),%r15
  314179:	or     %rbx,%r15
  31417c:	lea    0x8f2395(%rip),%rax        # c06518 <anon.3b95ecad333729d81ec3f9963a62dbdb.26.llvm.3675744859411786911>
  314183:	mov    %rax,0x28(%rsp)
  314188:	mov    $0x20,%eax
  31418d:	mov    %rax,0x20(%rsp)
  314192:	lea    0x511d1f(%rip),%rax        # 825eb8 <anon.3b95ecad333729d81ec3f9963a62dbdb.24.llvm.3675744859411786911>
  314199:	mov    %rax,0x18(%rsp)
  31419e:	jne    3145e3 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x513>
  3141a4:	call   7aa1d0 <<ostd::irq::level::InterruptLevel>::current>
  3141a9:	cmp    $0x2,%al
  3141ab:	jne    314588 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x4b8>
  3141b1:	mov    0xa0(%rsp),%rax
  3141b9:	mov    (%rax),%r14
  3141bc:	mov    0x70(%r14),%r15
  3141c0:	mov    0x78(%r14),%rax
  3141c4:	mov    0x18(%rax),%r13
  3141c8:	lea    0x30(%rsp),%rdi
  3141cd:	mov    %r15,%rsi
  3141d0:	call   *%r13
  3141d3:	movabs $0x749e27a2a06b54a5,%rbx
  3141dd:	movabs $0xab1dbb715a95736e,%r12
  3141e7:	mov    0x38(%rsp),%rax
  3141ec:	xor    %rbx,%rax
  3141ef:	mov    0x30(%rsp),%rcx
  3141f4:	xor    %r12,%rcx
  3141f7:	or     %rax,%rcx
  3141fa:	jne    314616 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x546>
  314200:	lea    0x30(%rsp),%rdi
  314205:	mov    %r15,%rsi
  314208:	call   *%r13
  31420b:	xor    0x30(%rsp),%r12
  314210:	xor    0x38(%rsp),%rbx
  314215:	or     %r12,%rbx
  314218:	jne    3145e3 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x513>
  31421e:	mov    0x20(%r15),%rax
  314222:	movabs $0x7fffffffffffffff,%rcx
  31422c:	cmp    %rcx,%rax
  31422f:	jae    3145a7 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x4d7>
  314235:	inc    %rax
  314238:	mov    %rax,0x20(%r15)
  31423c:	cmpq   $0x0,0x28(%r15)
  314241:	je     3145b8 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x4e8>
  314247:	lea    0x28(%r15),%r13
  31424b:	mov    %r13,0x30(%rsp)
  314250:	mov    %r15,0x38(%rsp)
  314255:	mov    %rbp,0x40(%rsp)
  31425a:	mov    0x10(%rsp),%rax
  31425f:	mov    %rax,0x48(%rsp)
  314264:	mov    %r14,0x50(%rsp)
  314269:	movzbl 0x7(%rsp),%eax
  31426e:	test   %eax,%eax
  314270:	je     3142db <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x20b>
  314272:	cmp    $0x1,%eax
  314275:	mov    0x8(%rsp),%rdi
  31427a:	jne    31430b <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x23b>
  314280:	mov    0xb0(%rdi),%rax
  314287:	movq   $0xffffffffffffffff,0xb0(%rdi)
  314292:	cmp    $0xffffffffffffffff,%rax
  314296:	je     3145fc <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x52c>
  31429c:	mov    %rax,0x60(%rsp)
  3142a1:	mov    0xb8(%rdi),%rax
  3142a8:	mov    0xc0(%rdi),%rcx
  3142af:	mov    %rax,0x68(%rsp)
  3142b4:	mov    %rcx,0x70(%rsp)
  3142b9:	movq   $0x0,0xc0(%r15)
  3142c4:	mov    %rdi,%rsi
  3142c7:	lea    0x30(%rsp),%rdi
  3142cc:	lea    0x60(%rsp),%rdx
  3142d1:	call   39e830 <aster_core::thread::exception::handle_exception>
  3142d6:	jmp    314409 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x339>
  3142db:	mov    0x8(%rsp),%rax
  3142e0:	cmpl   $0x1,(%rax)
  3142e3:	jne    31432f <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x25f>
  3142e5:	mov    0x8(%rax),%rax
  3142e9:	add    $0x50,%rax
  3142ed:	test   $0x7,%al
  3142ef:	je     314333 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x263>
  3142f1:	lea    0x5495b8(%rip),%rdi        # 85d8b0 <anon.87e69e727fae8ba69621db2b34b770bd.573.llvm.9636423037488915450>
  3142f8:	lea    0x90d311(%rip),%rcx        # c21610 <anon.87e69e727fae8ba69621db2b34b770bd.605.llvm.9636423037488915450>
  3142ff:	mov    $0x1b5,%esi
  314304:	xor    %edx,%edx
  314306:	call   768920 <core::panicking::panic_nounwind_fmt>
  31430b:	movq   $0x0,0xc0(%r15)
  314316:	mov    0x10(%rsp),%rax
  31431b:	movzbl 0x80(%rax),%eax
  314322:	test   %al,%al
  314324:	jne    314438 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x368>
  31432a:	jmp    31441e <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x34e>
  31432f:	add    $0x58,%rax
  314333:	mov    (%rax),%rax
  314336:	movq   $0x1,0xc0(%r15)
  314341:	mov    %rax,0xc8(%r15)
  314348:	movzbl 0x3e0(%rbp),%eax
  31434f:	cmp    $0x2,%al
  314351:	jne    314381 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2b1>
  314353:	lea    0x258(%rbp),%rsi
  31435a:	lea    0x80(%rsp),%rdi
  314362:	lea    0x30(%rsp),%rdx
  314367:	mov    0x8(%rsp),%rcx
  31436c:	call   58c450 <<aster_core::process::posix_thread::ptrace::TraceeStatus>::ptrace_may_stop_on_syscall>
  314371:	cmpq   $0x1,0x80(%rsp)
  31437a:	jne    314399 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x2c9>
  31437c:	jmp    314409 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x339>
  314381:	movq   $0x2,0x88(%rsp)
  31438d:	movq   $0x2,0x80(%rsp)
  314399:	lea    0x30(%rsp),%rdi
  31439e:	mov    0x8(%rsp),%rsi
  3143a3:	call   4938d0 <aster_core::syscall::handle_syscall>
  3143a8:	movzbl 0x3e0(%rbp),%eax
  3143af:	cmp    $0x2,%al
  3143b1:	jne    3143f2 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x322>
  3143b3:	add    $0x258,%rbp
  3143ba:	lea    0x60(%rsp),%rdi
  3143bf:	lea    0x30(%rsp),%rdx
  3143c4:	mov    %rbp,%rsi
  3143c7:	mov    0x8(%rsp),%rcx
  3143cc:	call   58c450 <<aster_core::process::posix_thread::ptrace::TraceeStatus>::ptrace_may_stop_on_syscall>
  3143d1:	mov    0x60(%rsp),%rax
  3143d6:	test   %rax,%rax
  3143d9:	je     3143e1 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x311>
  3143db:	cmp    $0x1,%rax
  3143df:	je     3143f2 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x322>
  3143e1:	cmpl   $0x2,0x68(%rsp)
  3143e6:	je     3143f2 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x322>
  3143e8:	lea    0x68(%rsp),%rdi
  3143ed:	call   2f01e0 <core::ptr::drop_glue::<aster_core::process::signal::pending::DequeuedSignal>>
  3143f2:	cmpl   $0x2,0x88(%rsp)
  3143fa:	je     314409 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x339>
  3143fc:	lea    0x88(%rsp),%rdi
  314404:	call   2f01e0 <core::ptr::drop_glue::<aster_core::process::signal::pending::DequeuedSignal>>
  314409:	mov    0x8(%rsp),%rdi
  31440e:	mov    0x10(%rsp),%rax
  314413:	movzbl 0x80(%rax),%eax
  31441a:	test   %al,%al
  31441c:	jne    314438 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x368>
  31441e:	lea    0x30(%rsp),%rsi
  314423:	call   4cdb60 <aster_core::process::signal::handle_pending_signal>
  314428:	mov    0x10(%rsp),%rax
  31442d:	movzbl 0x80(%rax),%eax
  314434:	test   %al,%al
  314436:	je     314477 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x3a7>
  314438:	mov    0x20(%r15),%rax
  31443c:	test   %rax,%rax
  31443f:	jle    3145c1 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x4f1>
  314445:	dec    %rax
  314448:	mov    %rax,0x20(%r15)
  31444c:	movq   $0xffffffffffffffff,0xa8(%rsp)
  314458:	lea    0xa8(%rsp),%rdi
  314460:	call   2ec130 <core::ptr::drop_glue::<core::result::Result<(), aster_core::thread::oops::OopsInfo>>>
  314465:	add    $0xc8,%rsp
  31446c:	pop    %rbx
  31446d:	pop    %r12
  31446f:	pop    %r13
  314471:	pop    %r14
  314473:	pop    %r15
  314475:	pop    %rbp
  314476:	ret
  314477:	lea    0x68(%rsp),%rbx
  31447c:	lea    0x9339fd(%rip),%r12        # c47e80 <alloc::sync::STATIC_INNER_SLICE>
  314483:	lea    0x80(%rsp),%r14
  31448b:	lea    0x30(%rsp),%rbp
  314490:	jmp    3144b0 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x3e0>
  314492:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  3144a0:	mov    0x10(%rsp),%rax
  3144a5:	movzbl 0x80(%rax),%eax
  3144ac:	test   %al,%al
  3144ae:	jne    314438 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x368>
  3144b0:	mov    0x0(%r13),%rax
  3144b4:	movzbl 0x698(%rax),%eax
  3144bb:	test   %al,%al
  3144bd:	je     314438 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x368>
  3144c3:	call   7b2540 <<ostd::sync::wait::Waiter>::new_pair>
  3144c8:	mov    %rax,0x60(%rsp)
  3144cd:	mov    %rdx,0x68(%rsp)
  3144d2:	mov    %rax,0x80(%rsp)
  3144da:	lock decq (%rdx)
  3144de:	jne    3144ef <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x41f>
  3144e0:	cmp    %r12,0x68(%rsp)
  3144e5:	je     31454e <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x47e>
  3144e7:	mov    %rbx,%rdi
  3144ea:	call   79f7e0 <<alloc::sync::Arc<ostd::sync::wait::Waker>>::drop_slow>
  3144ef:	lea    0x60(%rsp),%rdi
  3144f4:	mov    %r14,%rsi
  3144f7:	mov    %r13,%rdx
  3144fa:	mov    $0x1,%ecx
  3144ff:	lea    0x8f23c2(%rip),%r8        # c068c8 <anon.3b95ecad333729d81ec3f9963a62dbdb.82.llvm.3675744859411786911+0x178>
  314506:	call   580940 <<ostd::sync::wait::Waiter as aster_core::process::signal::pause::Pause>::pause_until_by::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}::{closure#0}, ()>>
  31450b:	mov    0x8(%rsp),%rdi
  314510:	mov    %rbp,%rsi
  314513:	call   4cdb60 <aster_core::process::signal::handle_pending_signal>
  314518:	mov    0x80(%rsp),%rax
  314520:	mov    $0x1,%cl
  314522:	xchg   %cl,0x18(%rax)
  314525:	mov    0x80(%rsp),%rax
  31452d:	lock decq (%rax)
  314531:	jne    3144a0 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x3d0>
  314537:	cmp    %r12,0x80(%rsp)
  31453f:	je     31456b <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x49b>
  314541:	mov    %r14,%rdi
  314544:	call   79f7e0 <<alloc::sync::Arc<ostd::sync::wait::Waker>>::drop_slow>
  314549:	jmp    3144a0 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x3d0>
  31454e:	lea    0x524d20(%rip),%rdi        # 839275 <anon.3b95ecad333729d81ec3f9963a62dbdb.565.llvm.3675744859411786911>
  314555:	lea    0x8f373c(%rip),%rdx        # c07c98 <anon.3b95ecad333729d81ec3f9963a62dbdb.566.llvm.3675744859411786911>
  31455c:	mov    $0x10b,%esi
  314561:	call   768ac0 <core::panicking::panic_fmt>
  314566:	jmp    31468d <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x5bd>
  31456b:	lea    0x524d03(%rip),%rdi        # 839275 <anon.3b95ecad333729d81ec3f9963a62dbdb.565.llvm.3675744859411786911>
  314572:	lea    0x8f371f(%rip),%rdx        # c07c98 <anon.3b95ecad333729d81ec3f9963a62dbdb.566.llvm.3675744859411786911>
  314579:	mov    $0x10b,%esi
  31457e:	call   768ac0 <core::panicking::panic_fmt>
  314583:	jmp    31468d <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x5bd>
  314588:	lea    0x92ea81(%rip),%rax        # c43010 <anon.bf7c383cfd03a7b81434b21410e62c5a.38.llvm.3857089978811055691>
  31458f:	mov    %rax,0x28(%rsp)
  314594:	mov    $0x3d,%eax
  314599:	mov    %rax,0x20(%rsp)
  31459e:	lea    0x5909b5(%rip),%rax        # 8a4f5a <anon.bf7c383cfd03a7b81434b21410e62c5a.37.llvm.3857089978811055691>
  3145a5:	jmp    3145de <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x50e>
  3145a7:	lea    0x8f22d2(%rip),%rdi        # c06880 <anon.3b95ecad333729d81ec3f9963a62dbdb.82.llvm.3675744859411786911+0x130>
  3145ae:	call   76cb80 <core::cell::panic_already_mutably_borrowed>
  3145b3:	jmp    31468d <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x5bd>
  3145b8:	lea    0x8f22d9(%rip),%rdi        # c06898 <anon.3b95ecad333729d81ec3f9963a62dbdb.82.llvm.3675744859411786911+0x148>
  3145bf:	jmp    314603 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x533>
  3145c1:	lea    0x8f36e8(%rip),%rax        # c07cb0 <anon.3b95ecad333729d81ec3f9963a62dbdb.568.llvm.3675744859411786911>
  3145c8:	mov    %rax,0x28(%rsp)
  3145cd:	mov    $0x24,%eax
  3145d2:	mov    %rax,0x20(%rsp)
  3145d7:	lea    0x524d1c(%rip),%rax        # 8392fa <anon.3b95ecad333729d81ec3f9963a62dbdb.567.llvm.3675744859411786911>
  3145de:	mov    %rax,0x18(%rsp)
  3145e3:	mov    0x18(%rsp),%rdi
  3145e8:	mov    0x20(%rsp),%rsi
  3145ed:	mov    0x28(%rsp),%rdx
  3145f2:	call   768aa0 <core::panicking::panic>
  3145f7:	jmp    31468d <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x5bd>
  3145fc:	lea    0x8f22ad(%rip),%rdi        # c068b0 <anon.3b95ecad333729d81ec3f9963a62dbdb.82.llvm.3675744859411786911+0x160>
  314603:	call   7709b0 <core::option::unwrap_failed>
  314608:	jmp    31468d <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x5bd>
  31460d:	lea    0x8f223c(%rip),%rdi        # c06850 <anon.3b95ecad333729d81ec3f9963a62dbdb.82.llvm.3675744859411786911+0x100>
  314614:	jmp    31461d <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x54d>
  314616:	lea    0x8f224b(%rip),%rdi        # c06868 <anon.3b95ecad333729d81ec3f9963a62dbdb.82.llvm.3675744859411786911+0x118>
  31461d:	call   7709b0 <core::option::unwrap_failed>
  314622:	jmp    31468d <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x5bd>
  314624:	endbr64
  314628:	mov    %rax,%r14
  31462b:	lea    0x80(%rsp),%rdi
  314633:	call   2f06a0 <core::ptr::drop_glue::<aster_core::process::posix_thread::ptrace::util::PtraceStopResult>>
  314638:	jmp    314663 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x593>
  31463a:	endbr64
  31463e:	jmp    314660 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x590>
  314640:	endbr64
  314644:	jmp    31464a <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x57a>
  314646:	endbr64
  31464a:	mov    %rax,%r14
  31464d:	lea    0x80(%rsp),%rdi
  314655:	call   2ef390 <core::ptr::drop_glue::<ostd::sync::wait::Waiter>>
  31465a:	jmp    314663 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x593>
  31465c:	endbr64
  314660:	mov    %rax,%r14
  314663:	mov    0x20(%r15),%rax
  314667:	test   %rax,%rax
  31466a:	jle    314675 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x5a5>
  31466c:	dec    %rax
  31466f:	mov    %rax,0x20(%r15)
  314673:	jmp    31469f <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x5cf>
  314675:	lea    0x524c7e(%rip),%rdi        # 8392fa <anon.3b95ecad333729d81ec3f9963a62dbdb.567.llvm.3675744859411786911>
  31467c:	lea    0x8f362d(%rip),%rdx        # c07cb0 <anon.3b95ecad333729d81ec3f9963a62dbdb.568.llvm.3675744859411786911>
  314683:	mov    $0x24,%esi
  314688:	call   768aa0 <core::panicking::panic>
  31468d:	ud2
  31468f:	endbr64
  314693:	call   7688cb <core::panicking::panic_in_cleanup>
  314698:	endbr64
  31469c:	mov    %rax,%r14
  31469f:	lea    0xa8(%rsp),%rdi
  3146a7:	mov    %r14,%rsi
  3146aa:	call   53dc90 <unwinding::panicking::catch_unwind::do_catch::<unwinding::panic::RustPanic>>
  3146af:	mov    0xa8(%rsp),%rdi
  3146b7:	mov    0xb0(%rsp),%rsi
  3146bf:	call   7d36a0 <unwinding::panic::catch_unwind::process_panic>
  3146c4:	test   %rax,%rax
  3146c7:	je     31444c <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x37c>
  3146cd:	mov    %rax,%r15
  3146d0:	mov    %rdx,%r14
  3146d3:	call   798040 <ostd::panic::report_caught_panic>
  3146d8:	lea    0xa8(%rsp),%rdi
  3146e0:	mov    %r15,%rsi
  3146e3:	mov    %r14,%rdx
  3146e6:	call   55c900 <aster_core::thread::oops::handle_oops>
  3146eb:	cmpq   $0xffffffffffffffff,0xa8(%rsp)
  3146f4:	je     314458 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x388>
  3146fa:	mov    0xa0(%rsp),%rax
  314702:	mov    (%rax),%rsi
  314705:	mov    0x10(%rsp),%rdi
  31470a:	call   2fffc0 <aster_core::thread::task::exit_current_after_oops>
  31470f:	jmp    314458 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x388>
  314714:	endbr64
  314718:	mov    %rax,%rbx
  31471b:	lea    0xa8(%rsp),%rdi
  314723:	call   2ec130 <core::ptr::drop_glue::<core::result::Result<(), aster_core::thread::oops::OopsInfo>>>
  314728:	jmp    314745 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle+0x675>
  31472a:	endbr64
  31472e:	call   7688cb <core::panicking::panic_in_cleanup>
  314733:	endbr64
  314737:	mov    %rax,%rbx
  31473a:	mov    %r15,%rdi
  31473d:	mov    %r14,%rsi
  314740:	call   2ec080 <core::ptr::drop_glue::<core::result::Result<(), alloc::boxed::Box<dyn core::any::Any + core::marker::Send>>>>
  314745:	mov    %rbx,%rdi
  314748:	call   7d4200 <_Unwind_Resume>
  31474d:	endbr64
  314751:	call   7688cb <core::panicking::panic_in_cleanup>
