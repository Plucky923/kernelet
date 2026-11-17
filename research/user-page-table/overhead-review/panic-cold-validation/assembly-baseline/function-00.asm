
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-baseline.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000522e90 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>>:
  522e90:	endbr64
  522e94:	push   %rbp
  522e95:	push   %r15
  522e97:	push   %r14
  522e99:	push   %r13
  522e9b:	push   %r12
  522e9d:	push   %rbx
  522e9e:	sub    $0xe8,%rsp
  522ea5:	mov    0x18(%rdi),%rax
  522ea9:	mov    %rax,0x80(%rsp)
  522eb1:	mov    %rax,0xe0(%rsp)
  522eb9:	mov    0x10(%rdi),%r14
  522ebd:	mov    %r14,0xd8(%rsp)
  522ec5:	mov    (%rdi),%rax
  522ec8:	mov    0x8(%rdi),%r15
  522ecc:	mov    %r15,0xd0(%rsp)
  522ed4:	mov    %rax,0xc8(%rsp)
  522edc:	mov    0x28(%rax),%rbx
  522ee0:	mov    %rax,0x68(%rsp)
  522ee5:	mov    0x30(%rax),%rax
  522ee9:	lea    0x90(%rsp),%rdi
  522ef1:	mov    %rbx,%rsi
  522ef4:	call   *0x18(%rax)
  522ef7:	movabs $0x24381668dbddccd4,%rcx
  522f01:	movabs $0xd5bc020f4457557d,%rdx
  522f0b:	mov    0x98(%rsp),%rax
  522f13:	xor    %rcx,%rax
  522f16:	mov    0x90(%rsp),%rcx
  522f1e:	xor    %rdx,%rcx
  522f21:	or     %rax,%rcx
  522f24:	jne    5237fb <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x96b>
  522f2a:	call   6d6e30 <<ostd::irq::level::InterruptLevel>::current>
  522f2f:	cmp    $0x2,%al
  522f31:	jne    523804 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x974>
  522f37:	mov    (%r15),%rax
  522f3a:	mov    0x70(%rax),%rsi
  522f3e:	mov    0x78(%rax),%rax
  522f42:	lea    0x90(%rsp),%rdi
  522f4a:	mov    %rsi,(%rsp)
  522f4e:	call   *0x18(%rax)
  522f51:	movabs $0x4403bae9dd1ea411,%rax
  522f5b:	xor    0x98(%rsp),%rax
  522f63:	movabs $0xdb07d43de26bc392,%rcx
  522f6d:	xor    0x90(%rsp),%rcx
  522f75:	or     %rax,%rcx
  522f78:	jne    523821 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x991>
  522f7e:	mov    (%rsp),%rdx
  522f82:	mov    0x20(%rdx),%rax
  522f86:	movabs $0x7fffffffffffffff,%rcx
  522f90:	cmp    %rcx,%rax
  522f93:	jae    523832 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x9a2>
  522f99:	inc    %rax
  522f9c:	mov    %rax,0x20(%rdx)
  522fa0:	cmpq   $0x0,0x28(%rdx)
  522fa5:	je     523843 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x9b3>
  522fab:	lea    0x28(%rdx),%rcx
  522faf:	mov    (%r15),%rax
  522fb2:	mov    %rcx,0xc0(%rsp)
  522fba:	mov    %rcx,0x90(%rsp)
  522fc2:	mov    %rdx,0x98(%rsp)
  522fca:	mov    %rbx,0xa0(%rsp)
  522fd2:	mov    0x68(%rsp),%rcx
  522fd7:	mov    %rcx,0xa8(%rsp)
  522fdf:	mov    %rax,0xb0(%rsp)
  522fe7:	movzbl (%r14),%eax
  522feb:	test   %eax,%eax
  522fed:	je     523062 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x1d2>
  522fef:	cmp    $0x1,%eax
  522ff2:	mov    0x80(%rsp),%r14
  522ffa:	jne    5230cb <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x23b>
  523000:	mov    0xb0(%r14),%rax
  523007:	movq   $0xffffffffffffffff,0xb0(%r14)
  523012:	cmp    $0xffffffffffffffff,%rax
  523016:	mov    (%rsp),%rdx
  52301a:	je     52384c <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x9bc>
  523020:	mov    %rax,0x20(%rsp)
  523025:	mov    0xb8(%r14),%rax
  52302c:	mov    0xc0(%r14),%rcx
  523033:	mov    %rax,0x28(%rsp)
  523038:	mov    %rcx,0x30(%rsp)
  52303d:	movq   $0x0,0xc0(%rdx)
  523048:	lea    0x90(%rsp),%rdi
  523050:	lea    0x20(%rsp),%rdx
  523055:	mov    %r14,%rsi
  523058:	call   4f2ac0 <aster_core::thread::exception::handle_exception>
  52305d:	jmp    523167 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x2d7>
  523062:	mov    0x80(%rsp),%r14
  52306a:	mov    0x8(%r14),%rax
  52306e:	add    $0x50,%rax
  523072:	cmpb   $0x0,(%r14)
  523076:	lea    0x58(%r14),%rcx
  52307a:	cmovne %rax,%rcx
  52307e:	mov    (%rcx),%rax
  523081:	mov    (%rsp),%rcx
  523085:	movq   $0x1,0xc0(%rcx)
  523090:	mov    %rax,0xc8(%rcx)
  523097:	movzbl 0x3e0(%rbx),%eax
  52309e:	cmp    $0x2,%al
  5230a0:	jne    5230f3 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x263>
  5230a2:	lea    0x258(%rbx),%rsi
  5230a9:	lea    0x48(%rsp),%rdi
  5230ae:	lea    0x90(%rsp),%rdx
  5230b6:	mov    %r14,%rcx
  5230b9:	call   531b70 <<aster_core::process::posix_thread::ptrace::TraceeStatus>::ptrace_may_stop_on_syscall>
  5230be:	cmpq   $0x1,0x48(%rsp)
  5230c4:	jne    523105 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x275>
  5230c6:	jmp    52315d <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x2cd>
  5230cb:	mov    (%rsp),%rbx
  5230cf:	movq   $0x0,0xc0(%rbx)
  5230da:	mov    0x68(%rsp),%rax
  5230df:	movzbl 0x80(%rax),%eax
  5230e6:	test   %al,%al
  5230e8:	jne    52319f <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x30f>
  5230ee:	jmp    52317b <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x2eb>
  5230f3:	movq   $0x2,0x50(%rsp)
  5230fc:	movq   $0x2,0x48(%rsp)
  523105:	lea    0x90(%rsp),%rdi
  52310d:	mov    %r14,%rsi
  523110:	call   4f1780 <aster_core::syscall::handle_syscall>
  523115:	movzbl 0x3e0(%rbx),%eax
  52311c:	cmp    $0x2,%al
  52311e:	jne    523141 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x2b1>
  523120:	add    $0x258,%rbx
  523127:	lea    0x20(%rsp),%rdi
  52312c:	lea    0x90(%rsp),%rdx
  523134:	mov    %rbx,%rsi
  523137:	mov    %r14,%rcx
  52313a:	call   531b70 <<aster_core::process::posix_thread::ptrace::TraceeStatus>::ptrace_may_stop_on_syscall>
  52313f:	jmp    523153 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x2c3>
  523141:	movq   $0x2,0x28(%rsp)
  52314a:	movq   $0x2,0x20(%rsp)
  523153:	lea    0x20(%rsp),%rdi
  523158:	call   522930 <core::ptr::drop_glue::<aster_core::process::posix_thread::ptrace::util::PtraceStopResult>>
  52315d:	lea    0x48(%rsp),%rdi
  523162:	call   522930 <core::ptr::drop_glue::<aster_core::process::posix_thread::ptrace::util::PtraceStopResult>>
  523167:	mov    (%rsp),%rbx
  52316b:	mov    0x68(%rsp),%rax
  523170:	movzbl 0x80(%rax),%eax
  523177:	test   %al,%al
  523179:	jne    52319f <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x30f>
  52317b:	lea    0x90(%rsp),%rsi
  523183:	mov    %r14,%rdi
  523186:	call   4f3250 <aster_core::process::signal::handle_pending_signal>
  52318b:	mov    0x68(%rsp),%rax
  523190:	movzbl 0x80(%rax),%eax
  523197:	test   %al,%al
  523199:	mov    (%rsp),%rbx
  52319d:	je     5231b7 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x327>
  52319f:	decq   0x20(%rbx)
  5231a3:	xor    %eax,%eax
  5231a5:	add    $0xe8,%rsp
  5231ac:	pop    %rbx
  5231ad:	pop    %r12
  5231af:	pop    %r13
  5231b1:	pop    %r14
  5231b3:	pop    %r15
  5231b5:	pop    %rbp
  5231b6:	ret
  5231b7:	mov    $0x1,%r12b
  5231ba:	lea    0x4fcbff(%rip),%rbp        # a1fdc0 <anon.0fd7751ddbb964514b2ed2bfec276595.119.llvm.13163086016827432529+0x120>
  5231c1:	jmp    5231e0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x350>
  5231c3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  5231d0:	mov    0x68(%rsp),%rax
  5231d5:	movzbl 0x80(%rax),%eax
  5231dc:	test   %al,%al
  5231de:	jne    52319f <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x30f>
  5231e0:	mov    0xc0(%rsp),%rax
  5231e8:	mov    (%rax),%rax
  5231eb:	movzbl 0x698(%rax),%eax
  5231f2:	test   %al,%al
  5231f4:	je     52319f <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x30f>
  5231f6:	call   6d9a30 <<ostd::sync::wait::Waiter>::new_pair>
  5231fb:	mov    %rax,0x20(%rsp)
  523200:	mov    %rdx,0x28(%rsp)
  523205:	mov    %rax,0x10(%rsp)
  52320a:	lock decq (%rdx)
  52320e:	jne    52321a <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x38a>
  523210:	lea    0x28(%rsp),%rdi
  523215:	call   6bf350 <<alloc::sync::Arc<ostd::sync::wait::Waker>>::drop_slow>
  52321a:	mov    0xc0(%rsp),%rax
  523222:	mov    (%rax),%r13
  523225:	movb   $0x1,0xf(%rsp)
  52322a:	mov    0x10(%rsp),%rax
  52322f:	mov    %rax,0x78(%rsp)
  523234:	mov    0x10(%rax),%rax
  523238:	mov    0x70(%rax),%r15
  52323c:	mov    0x78(%rax),%rax
  523240:	lea    0x20(%rsp),%rdi
  523245:	mov    %r15,%rsi
  523248:	call   *0x18(%rax)
  52324b:	mov    0x28(%rsp),%rax
  523250:	movabs $0xdbb2c6048829d888,%rcx
  52325a:	xor    %rcx,%rax
  52325d:	mov    0x20(%rsp),%rcx
  523262:	movabs $0xd795ec3689c4cb1b,%rdx
  52326c:	xor    %rdx,%rcx
  52326f:	or     %rax,%rcx
  523272:	jne    523430 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x5a0>
  523278:	mov    (%r15),%rax
  52327b:	mov    0x38(%rax),%rsi
  52327f:	mov    0x40(%rax),%rax
  523283:	lea    0x20(%rsp),%rdi
  523288:	mov    %rsi,0x70(%rsp)
  52328d:	call   *0x18(%rax)
  523290:	mov    0x20(%rsp),%rax
  523295:	movabs $0xd5bc020f4457557d,%rcx
  52329f:	xor    %rcx,%rax
  5232a2:	mov    0x28(%rsp),%rcx
  5232a7:	movabs $0x24381668dbddccd4,%rdx
  5232b1:	xor    %rdx,%rcx
  5232b4:	or     %rax,%rcx
  5232b7:	jne    523430 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x5a0>
  5232bd:	mov    0x78(%rsp),%rsi
  5232c2:	lock incq (%rsi)
  5232c6:	jle    523b51 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xcc1>
  5232cc:	mov    0x70(%rsp),%rdi
  5232d1:	mov    $0x1,%edx
  5232d6:	call   451020 <<aster_core::process::posix_thread::PosixThread>::set_signalled_waker>
  5232db:	movq   $0x0,0x88(%rsp)
  5232e7:	movq   $0x0,0x58(%rsp)
  5232f0:	lea    0xf(%rsp),%rax
  5232f5:	mov    %rax,0x48(%rsp)
  5232fa:	mov    0x70(%rsp),%rax
  5232ff:	mov    %rax,0x50(%rsp)
  523304:	data16 data16 cs nopw 0x0(%rax,%rax,1)
  523310:	movzbl 0x698(%r13),%eax
  523318:	test   %al,%al
  52331a:	je     523650 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x7c0>
  523320:	mov    0x58(%rsp),%rcx
  523325:	test   %rcx,%rcx
  523328:	je     5233bb <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x52b>
  52332e:	lea    0x28(%rcx),%r15
  523332:	jmp    22aef3 <__kernelet_cpu_access_start+0x2acd2>
  523337:	xor    %eax,%eax
  523339:	lock cmpxchg %r12b,0x28(%rcx)
  52333f:	je     523360 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x4d0>
  523341:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  523350:	pause
  523352:	call   6c1770 <ostd::kernelet::entry::on_spin>
  523357:	xor    %eax,%eax
  523359:	lock cmpxchg %r12b,(%r15)
  52335e:	jne    523350 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x4c0>
  523360:	test   %r14d,%r14d
  523363:	mov    %r15,0x28(%rsp)
  523368:	sete   0x30(%rsp)
  52336d:	lea    0x58(%rsp),%rax
  523372:	mov    %rax,0x20(%rsp)
  523377:	lea    0x20(%rsp),%rdi
  52337c:	call   52ded0 <<aster_core::time::core::timer::TimerGuard>::remain>
  523381:	test   %rax,%rax
  523384:	je     5233a0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x510>
  523386:	xor    %ebx,%ebx
  523388:	movb   $0x0,(%r15)
  52338c:	test   %r14d,%r14d
  52338f:	jne    5233b3 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x523>
  523391:	jmp    5233ae <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x51e>
  523393:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  5233a0:	test   %edx,%edx
  5233a2:	sete   %bl
  5233a5:	movb   $0x0,(%r15)
  5233a9:	test   %r14d,%r14d
  5233ac:	jne    5233b3 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x523>
  5233ae:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  5233b3:	test   %bl,%bl
  5233b5:	jne    523663 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x7d3>
  5233bb:	mov    0x48(%rsp),%rax
  5233c0:	mov    0x50(%rsp),%rdi
  5233c5:	cmpb   $0x2,(%rax)
  5233c8:	jne    5233e0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x550>
  5233ca:	call   469c10 <<aster_core::process::posix_thread::PosixThread as aster_core::process::signal::pending::HandlePendingSignal>::has_pending_sigkill>
  5233cf:	test   %al,%al
  5233d1:	je     5233ed <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x55d>
  5233d3:	jmp    52365f <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x7cf>
  5233d8:	nopl   0x0(%rax,%rax,1)
  5233e0:	call   469910 <<aster_core::process::posix_thread::PosixThread as aster_core::process::signal::pending::HandlePendingSignal>::has_pending>
  5233e5:	test   %al,%al
  5233e7:	jne    52365f <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x7cf>
  5233ed:	mov    0x10(%rsp),%r15
  5233f2:	xor    %eax,%eax
  5233f4:	xchg   %al,0x18(%r15)
  5233f8:	test   %al,%al
  5233fa:	jne    523310 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x480>
  523400:	lea    0x10(%r15),%r14
  523404:	data16 data16 cs nopw 0x0(%rax,%rax,1)
  523410:	mov    %r14,%rdi
  523413:	mov    %rbp,%rsi
  523416:	call   6be3e0 <ostd::task::scheduler::park_current::<<ostd::sync::wait::Waker>::do_wait::{closure#0}>>
  52341b:	xor    %eax,%eax
  52341d:	xchg   %al,0x18(%r15)
  523421:	test   %al,%al
  523423:	je     523410 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x580>
  523425:	jmp    523310 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x480>
  52342a:	nopw   0x0(%rax,%rax,1)
  523430:	movq   $0x0,0x18(%rsp)
  523439:	movq   $0x0,0x48(%rsp)
  523442:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  523450:	movzbl 0x698(%r13),%eax
  523458:	test   %al,%al
  52345a:	je     523540 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x6b0>
  523460:	mov    0x48(%rsp),%rcx
  523465:	test   %rcx,%rcx
  523468:	je     5234fb <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x66b>
  52346e:	lea    0x28(%rcx),%r14
  523472:	jmp    22af2f <__kernelet_cpu_access_start+0x2ad0e>
  523477:	xor    %eax,%eax
  523479:	lock cmpxchg %r12b,0x28(%rcx)
  52347f:	je     5234a0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x610>
  523481:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  523490:	pause
  523492:	call   6c1770 <ostd::kernelet::entry::on_spin>
  523497:	xor    %eax,%eax
  523499:	lock cmpxchg %r12b,(%r14)
  52349e:	jne    523490 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x600>
  5234a0:	test   %r15d,%r15d
  5234a3:	mov    %r14,0x28(%rsp)
  5234a8:	sete   0x30(%rsp)
  5234ad:	lea    0x48(%rsp),%rax
  5234b2:	mov    %rax,0x20(%rsp)
  5234b7:	lea    0x20(%rsp),%rdi
  5234bc:	call   52ded0 <<aster_core::time::core::timer::TimerGuard>::remain>
  5234c1:	test   %rax,%rax
  5234c4:	je     5234e0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x650>
  5234c6:	xor    %ebx,%ebx
  5234c8:	movb   $0x0,(%r14)
  5234cc:	test   %r15d,%r15d
  5234cf:	jne    5234f3 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x663>
  5234d1:	jmp    5234ee <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x65e>
  5234d3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  5234e0:	test   %edx,%edx
  5234e2:	sete   %bl
  5234e5:	movb   $0x0,(%r14)
  5234e9:	test   %r15d,%r15d
  5234ec:	jne    5234f3 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x663>
  5234ee:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  5234f3:	test   %bl,%bl
  5234f5:	mov    (%rsp),%rbx
  5234f9:	jne    52354f <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x6bf>
  5234fb:	mov    0x10(%rsp),%r14
  523500:	xor    %eax,%eax
  523502:	xchg   %al,0x18(%r14)
  523506:	test   %al,%al
  523508:	jne    523450 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x5c0>
  52350e:	lea    0x10(%r14),%r15
  523512:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  523520:	mov    %r15,%rdi
  523523:	mov    %rbp,%rsi
  523526:	call   6be3e0 <ostd::task::scheduler::park_current::<<ostd::sync::wait::Waker>::do_wait::{closure#0}>>
  52352b:	xor    %eax,%eax
  52352d:	xchg   %al,0x18(%r14)
  523531:	test   %al,%al
  523533:	je     523520 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x690>
  523535:	jmp    523450 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x5c0>
  52353a:	nopw   0x0(%rax,%rax,1)
  523540:	xor    %r14d,%r14d
  523543:	mov    0x48(%rsp),%rax
  523548:	test   %rax,%rax
  52354b:	jne    523571 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x6e1>
  52354d:	jmp    523581 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x6f1>
  52354f:	mov    $0x1,%al
  523551:	mov    0x78(%rsp),%rcx
  523556:	xchg   %al,0x18(%rcx)
  523559:	movzbl 0x698(%r13),%eax
  523561:	test   %al,%al
  523563:	setne  %r14b
  523567:	mov    0x48(%rsp),%rax
  52356c:	test   %rax,%rax
  52356f:	je     523581 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x6f1>
  523571:	lock decq (%rax)
  523575:	jne    523581 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x6f1>
  523577:	lea    0x48(%rsp),%rdi
  52357c:	call   4cdab0 <<alloc::sync::Arc<aster_core::time::core::timer::Timer>>::drop_slow>
  523581:	mov    0x18(%rsp),%rbx
  523586:	test   %rbx,%rbx
  523589:	je     523647 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x7b7>
  52358f:	mov    %rbx,0x48(%rsp)
  523594:	test   %r14b,%r14b
  523597:	je     5235b0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x720>
  523599:	lock decq (%rbx)
  52359d:	mov    (%rsp),%rbx
  5235a1:	je     52363d <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x7ad>
  5235a7:	jmp    523647 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x7b7>
  5235ac:	nopl   0x0(%rax)
  5235b0:	jmp    22af6b <__kernelet_cpu_access_start+0x2ad4a>
  5235b5:	data16 cs nopw 0x0(%rax,%rax,1)
  5235c0:	xor    %eax,%eax
  5235c2:	lock cmpxchg %r12b,0x28(%rbx)
  5235c8:	je     5235e0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x750>
  5235ca:	pause
  5235cc:	call   6c1770 <ostd::kernelet::entry::on_spin>
  5235d1:	jmp    5235c0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x730>
  5235d3:	data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  5235e0:	mov    0x30(%rbx),%rcx
  5235e4:	cmp    $0xffffffffffffffff,%rcx
  5235e8:	je     523620 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x790>
  5235ea:	mov    (%rcx),%rax
  5235ed:	nopl   (%rax)
  5235f0:	test   %rax,%rax
  5235f3:	je     523620 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x790>
  5235f5:	js     523791 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x901>
  5235fb:	lea    0x1(%rax),%rdx
  5235ff:	lock cmpxchg %rdx,(%rcx)
  523604:	jne    5235f0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x760>
  523606:	mov    %rcx,0x20(%rsp)
  52360b:	movb   $0x1,0x28(%rcx)
  52360f:	lock decq (%rcx)
  523613:	jne    523620 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x790>
  523615:	lea    0x20(%rsp),%rdi
  52361a:	call   4cda60 <<alloc::sync::Arc<aster_core::time::core::timer::TimerCallback>>::drop_slow>
  52361f:	nop
  523620:	movb   $0x0,0x28(%rbx)
  523624:	test   %r15d,%r15d
  523627:	jne    52362e <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x79e>
  523629:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  52362e:	mov    0x48(%rsp),%rax
  523633:	lock decq (%rax)
  523637:	mov    (%rsp),%rbx
  52363b:	jne    523647 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x7b7>
  52363d:	lea    0x48(%rsp),%rdi
  523642:	call   4cdab0 <<alloc::sync::Arc<aster_core::time::core::timer::Timer>>::drop_slow>
  523647:	mov    (%rsp),%rbx
  52364b:	jmp    523754 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x8c4>
  523650:	xor    %r14d,%r14d
  523653:	mov    0x58(%rsp),%rax
  523658:	test   %rax,%rax
  52365b:	jne    52368a <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x7fa>
  52365d:	jmp    52369a <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x80a>
  52365f:	xor    %eax,%eax
  523661:	jmp    523665 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x7d5>
  523663:	mov    $0x1,%al
  523665:	mov    $0x1,%cl
  523667:	mov    0x78(%rsp),%rdx
  52366c:	xchg   %cl,0x18(%rdx)
  52366f:	movzbl 0x698(%r13),%ecx
  523677:	test   %cl,%cl
  523679:	setne  %r14b
  52367d:	and    %al,%r14b
  523680:	mov    0x58(%rsp),%rax
  523685:	test   %rax,%rax
  523688:	je     52369a <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x80a>
  52368a:	lock decq (%rax)
  52368e:	jne    52369a <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x80a>
  523690:	lea    0x58(%rsp),%rdi
  523695:	call   4cdab0 <<alloc::sync::Arc<aster_core::time::core::timer::Timer>>::drop_slow>
  52369a:	mov    0x88(%rsp),%rbx
  5236a2:	test   %rbx,%rbx
  5236a5:	je     523746 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x8b6>
  5236ab:	mov    %rbx,0x18(%rsp)
  5236b0:	test   %r14b,%r14b
  5236b3:	je     5236c4 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x834>
  5236b5:	lock decq (%rbx)
  5236b9:	mov    (%rsp),%rbx
  5236bd:	je     52373c <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x8ac>
  5236bf:	jmp    523746 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x8b6>
  5236c4:	jmp    22afa7 <__kernelet_cpu_access_start+0x2ad86>
  5236c9:	nopl   0x0(%rax)
  5236d0:	xor    %eax,%eax
  5236d2:	lock cmpxchg %r12b,0x28(%rbx)
  5236d8:	je     5236e3 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x853>
  5236da:	pause
  5236dc:	call   6c1770 <ostd::kernelet::entry::on_spin>
  5236e1:	jmp    5236d0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x840>
  5236e3:	mov    0x30(%rbx),%rcx
  5236e7:	cmp    $0xffffffffffffffff,%rcx
  5236eb:	je     52371f <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x88f>
  5236ed:	mov    (%rcx),%rax
  5236f0:	test   %rax,%rax
  5236f3:	je     52371f <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x88f>
  5236f5:	js     5237c6 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x936>
  5236fb:	lea    0x1(%rax),%rdx
  5236ff:	lock cmpxchg %rdx,(%rcx)
  523704:	jne    5236f0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x860>
  523706:	mov    %rcx,0x20(%rsp)
  52370b:	movb   $0x1,0x28(%rcx)
  52370f:	lock decq (%rcx)
  523713:	jne    52371f <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x88f>
  523715:	lea    0x20(%rsp),%rdi
  52371a:	call   4cda60 <<alloc::sync::Arc<aster_core::time::core::timer::TimerCallback>>::drop_slow>
  52371f:	movb   $0x0,0x28(%rbx)
  523723:	test   %r13d,%r13d
  523726:	jne    52372d <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x89d>
  523728:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  52372d:	mov    0x18(%rsp),%rax
  523732:	lock decq (%rax)
  523736:	mov    (%rsp),%rbx
  52373a:	jne    523746 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x8b6>
  52373c:	lea    0x18(%rsp),%rdi
  523741:	call   4cdab0 <<alloc::sync::Arc<aster_core::time::core::timer::Timer>>::drop_slow>
  523746:	mov    0x70(%rsp),%rdi
  52374b:	mov    (%rsp),%rbx
  52374f:	call   4511f0 <<aster_core::process::posix_thread::PosixThread>::clear_signalled_waker>
  523754:	mov    0x80(%rsp),%rdi
  52375c:	lea    0x90(%rsp),%rsi
  523764:	call   4f3250 <aster_core::process::signal::handle_pending_signal>
  523769:	mov    0x10(%rsp),%rax
  52376e:	mov    $0x1,%cl
  523770:	xchg   %cl,0x18(%rax)
  523773:	mov    0x10(%rsp),%rax
  523778:	lock decq (%rax)
  52377c:	jne    5231d0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x340>
  523782:	lea    0x10(%rsp),%rdi
  523787:	call   6bf350 <<alloc::sync::Arc<ostd::sync::wait::Waker>>::drop_slow>
  52378c:	jmp    5231d0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x340>
  523791:	lea    0x4f55b0(%rip),%rax        # a18d48 <anon.cfac5cc4358780d9e0f789c5cd6dc1c3.211.llvm.17080032327367914158>
  523798:	mov    %rax,0x20(%rsp)
  52379d:	lea    0x5344c(%rip),%rax        # 576bf0 <<&str as core::fmt::Display>::fmt>
  5237a4:	mov    %rax,0x28(%rsp)
  5237a9:	lea    0x2e8e93(%rip),%rdi        # 80c643 <anon.021f6bd551db92d9d6c9f53b265611f8.15.llvm.34896216114674485>
  5237b0:	lea    0x4f5c89(%rip),%rdx        # a19440 <anon.cfac5cc4358780d9e0f789c5cd6dc1c3.276.llvm.17080032327367914158>
  5237b7:	lea    0x20(%rsp),%rsi
  5237bc:	call   6993b0 <core::panicking::panic_fmt>
  5237c1:	jmp    523b51 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xcc1>
  5237c6:	lea    0x4f557b(%rip),%rax        # a18d48 <anon.cfac5cc4358780d9e0f789c5cd6dc1c3.211.llvm.17080032327367914158>
  5237cd:	mov    %rax,0x20(%rsp)
  5237d2:	lea    0x53417(%rip),%rax        # 576bf0 <<&str as core::fmt::Display>::fmt>
  5237d9:	mov    %rax,0x28(%rsp)
  5237de:	lea    0x2e8e5e(%rip),%rdi        # 80c643 <anon.021f6bd551db92d9d6c9f53b265611f8.15.llvm.34896216114674485>
  5237e5:	lea    0x4f5c54(%rip),%rdx        # a19440 <anon.cfac5cc4358780d9e0f789c5cd6dc1c3.276.llvm.17080032327367914158>
  5237ec:	lea    0x20(%rsp),%rsi
  5237f1:	call   6993b0 <core::panicking::panic_fmt>
  5237f6:	jmp    523b51 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xcc1>
  5237fb:	lea    0x4fc546(%rip),%rdi        # a1fd48 <anon.0fd7751ddbb964514b2ed2bfec276595.119.llvm.13163086016827432529+0xa8>
  523802:	jmp    523828 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x998>
  523804:	lea    0x33e990(%rip),%rdi        # 86219b <anon.15e4b86be320fe459a17ca9fb0b8e1cc.5.llvm.13975411090267346181>
  52380b:	lea    0x50a7be(%rip),%rdx        # a2dfd0 <anon.15e4b86be320fe459a17ca9fb0b8e1cc.6.llvm.13975411090267346181>
  523812:	mov    $0x3d,%esi
  523817:	call   699390 <core::panicking::panic>
  52381c:	jmp    523b51 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xcc1>
  523821:	lea    0x4fc538(%rip),%rdi        # a1fd60 <anon.0fd7751ddbb964514b2ed2bfec276595.119.llvm.13163086016827432529+0xc0>
  523828:	call   697040 <core::option::unwrap_failed>
  52382d:	jmp    523b51 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xcc1>
  523832:	lea    0x4fc53f(%rip),%rdi        # a1fd78 <anon.0fd7751ddbb964514b2ed2bfec276595.119.llvm.13163086016827432529+0xd8>
  523839:	call   6981a0 <core::cell::panic_already_mutably_borrowed>
  52383e:	jmp    523b51 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xcc1>
  523843:	lea    0x4fc546(%rip),%rdi        # a1fd90 <anon.0fd7751ddbb964514b2ed2bfec276595.119.llvm.13163086016827432529+0xf0>
  52384a:	jmp    523853 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x9c3>
  52384c:	lea    0x4fc555(%rip),%rdi        # a1fda8 <anon.0fd7751ddbb964514b2ed2bfec276595.119.llvm.13163086016827432529+0x108>
  523853:	call   697040 <core::option::unwrap_failed>
  523858:	jmp    523b51 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xcc1>
  52385d:	endbr64
  523861:	jmp    523a8c <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xbfc>
  523866:	endbr64
  52386a:	mov    %rax,%r12
  52386d:	jmp    523aa3 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc13>
  523872:	endbr64
  523876:	jmp    523ad4 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc44>
  52387b:	endbr64
  52387f:	mov    %rax,%r12
  523882:	jmp    5239d0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb40>
  523887:	endbr64
  52388b:	mov    %rax,%r12
  52388e:	jmp    523aeb <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc5b>
  523893:	endbr64
  523897:	mov    %rax,%r12
  52389a:	mov    (%rsp),%rbx
  52389e:	jmp    523a48 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xbb8>
  5238a3:	endbr64
  5238a7:	mov    %rax,%r12
  5238aa:	lea    0x48(%rsp),%rdi
  5238af:	call   522930 <core::ptr::drop_glue::<aster_core::process::posix_thread::ptrace::util::PtraceStopResult>>
  5238b4:	mov    (%rsp),%rbx
  5238b8:	jmp    523b23 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc93>
  5238bd:	endbr64
  5238c1:	mov    %rax,%r12
  5238c4:	movb   $0x0,(%r15)
  5238c8:	test   %r14d,%r14d
  5238cb:	jne    5239b6 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb26>
  5238d1:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  5238d6:	jmp    5239b6 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb26>
  5238db:	endbr64
  5238df:	call   6991bb <core::panicking::panic_in_cleanup>
  5238e4:	endbr64
  5238e8:	mov    %rax,%r12
  5238eb:	test   %r13d,%r13d
  5238ee:	jne    523aa3 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc13>
  5238f4:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  5238f9:	mov    (%rsp),%rbx
  5238fd:	jmp    523aa7 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc17>
  523902:	endbr64
  523906:	call   6991bb <core::panicking::panic_in_cleanup>
  52390b:	endbr64
  52390f:	mov    %rax,%r12
  523912:	jmp    523b23 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc93>
  523917:	endbr64
  52391b:	mov    %rax,%r12
  52391e:	mov    (%rsp),%rbx
  523922:	jmp    523a2e <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb9e>
  523927:	endbr64
  52392b:	jmp    5239b3 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb23>
  523930:	endbr64
  523934:	mov    %rax,%r12
  523937:	test   %r15d,%r15d
  52393a:	jne    523aeb <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc5b>
  523940:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  523945:	mov    (%rsp),%rbx
  523949:	jmp    523aef <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc5f>
  52394e:	endbr64
  523952:	call   6991bb <core::panicking::panic_in_cleanup>
  523957:	endbr64
  52395b:	mov    %rax,%r12
  52395e:	jmp    523b04 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc74>
  523963:	endbr64
  523967:	mov    %rax,%r12
  52396a:	movb   $0x0,(%r14)
  52396e:	test   %r15d,%r15d
  523971:	jne    523981 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xaf1>
  523973:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  523978:	mov    (%rsp),%rbx
  52397c:	jmp    523a2e <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb9e>
  523981:	mov    (%rsp),%rbx
  523985:	jmp    523a2e <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb9e>
  52398a:	endbr64
  52398e:	call   6991bb <core::panicking::panic_in_cleanup>
  523993:	endbr64
  523997:	mov    %rax,%r12
  52399a:	test   %r14d,%r14d
  52399d:	jne    5239b6 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb26>
  52399f:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  5239a4:	jmp    5239b6 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb26>
  5239a6:	endbr64
  5239aa:	call   6991bb <core::panicking::panic_in_cleanup>
  5239af:	endbr64
  5239b3:	mov    %rax,%r12
  5239b6:	mov    0x58(%rsp),%rax
  5239bb:	test   %rax,%rax
  5239be:	je     5239d0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb40>
  5239c0:	lock decq (%rax)
  5239c4:	jne    5239d0 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb40>
  5239c6:	lea    0x58(%rsp),%rdi
  5239cb:	call   4cdab0 <<alloc::sync::Arc<aster_core::time::core::timer::Timer>>::drop_slow>
  5239d0:	mov    0x88(%rsp),%rax
  5239d8:	test   %rax,%rax
  5239db:	je     5239f9 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb69>
  5239dd:	lock decq (%rax)
  5239e1:	jne    5239f9 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb69>
  5239e3:	lea    0x88(%rsp),%rdi
  5239eb:	call   4cdab0 <<alloc::sync::Arc<aster_core::time::core::timer::Timer>>::drop_slow>
  5239f0:	mov    (%rsp),%rbx
  5239f4:	jmp    523b04 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc74>
  5239f9:	mov    (%rsp),%rbx
  5239fd:	jmp    523b04 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc74>
  523a02:	endbr64
  523a06:	call   6991bb <core::panicking::panic_in_cleanup>
  523a0b:	endbr64
  523a0f:	mov    %rax,%r12
  523a12:	test   %r15d,%r15d
  523a15:	jne    523a2e <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb9e>
  523a17:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  523a1c:	jmp    523a2e <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xb9e>
  523a1e:	endbr64
  523a22:	call   6991bb <core::panicking::panic_in_cleanup>
  523a27:	endbr64
  523a2b:	mov    %rax,%r12
  523a2e:	mov    0x48(%rsp),%rax
  523a33:	test   %rax,%rax
  523a36:	je     523a48 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xbb8>
  523a38:	lock decq (%rax)
  523a3c:	jne    523a48 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xbb8>
  523a3e:	lea    0x48(%rsp),%rdi
  523a43:	call   4cdab0 <<alloc::sync::Arc<aster_core::time::core::timer::Timer>>::drop_slow>
  523a48:	mov    0x18(%rsp),%rax
  523a4d:	test   %rax,%rax
  523a50:	je     523b04 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc74>
  523a56:	lock decq (%rax)
  523a5a:	jne    523b04 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc74>
  523a60:	lea    0x18(%rsp),%rdi
  523a65:	call   4cdab0 <<alloc::sync::Arc<aster_core::time::core::timer::Timer>>::drop_slow>
  523a6a:	jmp    523b04 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc74>
  523a6f:	endbr64
  523a73:	call   6991bb <core::panicking::panic_in_cleanup>
  523a78:	endbr64
  523a7c:	mov    %rax,%r12
  523a7f:	mov    (%rsp),%rbx
  523a83:	jmp    523b23 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc93>
  523a88:	endbr64
  523a8c:	mov    %rax,%r12
  523a8f:	movb   $0x0,0x28(%rbx)
  523a93:	test   %r13d,%r13d
  523a96:	jne    523aa3 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc13>
  523a98:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  523a9d:	mov    (%rsp),%rbx
  523aa1:	jmp    523aa7 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc17>
  523aa3:	mov    (%rsp),%rbx
  523aa7:	mov    0x18(%rsp),%rax
  523aac:	lock decq (%rax)
  523ab0:	jne    523b04 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc74>
  523ab2:	lea    0x18(%rsp),%rdi
  523ab7:	call   4cdab0 <<alloc::sync::Arc<aster_core::time::core::timer::Timer>>::drop_slow>
  523abc:	jmp    523b04 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc74>
  523abe:	endbr64
  523ac2:	call   6991bb <core::panicking::panic_in_cleanup>
  523ac7:	endbr64
  523acb:	mov    %rax,%r12
  523ace:	jmp    523b27 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc97>
  523ad0:	endbr64
  523ad4:	mov    %rax,%r12
  523ad7:	movb   $0x0,0x28(%rbx)
  523adb:	test   %r15d,%r15d
  523ade:	jne    523aeb <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc5b>
  523ae0:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  523ae5:	mov    (%rsp),%rbx
  523ae9:	jmp    523aef <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc5f>
  523aeb:	mov    (%rsp),%rbx
  523aef:	mov    0x48(%rsp),%rax
  523af4:	lock decq (%rax)
  523af8:	jne    523b04 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc74>
  523afa:	lea    0x48(%rsp),%rdi
  523aff:	call   4cdab0 <<alloc::sync::Arc<aster_core::time::core::timer::Timer>>::drop_slow>
  523b04:	mov    0x10(%rsp),%rax
  523b09:	mov    $0x1,%cl
  523b0b:	xchg   %cl,0x18(%rax)
  523b0e:	mov    0x10(%rsp),%rax
  523b13:	lock decq (%rax)
  523b17:	jne    523b23 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xc93>
  523b19:	lea    0x10(%rsp),%rdi
  523b1e:	call   6bf350 <<alloc::sync::Arc<ostd::sync::wait::Waker>>::drop_slow>
  523b23:	decq   0x20(%rbx)
  523b27:	lea    0xc8(%rsp),%rdi
  523b2f:	mov    %r12,%rsi
  523b32:	call   4e22e0 <unwinding::panicking::catch_unwind::do_catch::<unwinding::panic::RustPanic>>
  523b37:	mov    0xc8(%rsp),%rax
  523b3f:	test   %rax,%rax
  523b42:	je     523b51 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xcc1>
  523b44:	mov    0xd0(%rsp),%rdx
  523b4c:	jmp    5231a5 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x315>
  523b51:	ud2
  523b53:	endbr64
  523b57:	call   6991bb <core::panicking::panic_in_cleanup>
  523b5c:	endbr64
  523b60:	call   6991bb <core::panicking::panic_in_cleanup>
