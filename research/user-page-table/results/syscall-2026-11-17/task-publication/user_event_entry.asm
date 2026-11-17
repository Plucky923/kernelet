
research/user-page-table/results/syscall-2026-11-17/task-publication/image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006ebdc0 <user_event_entry>:
  6ebdc0:	f3 0f 1e fa          	endbr64
  6ebdc4:	55                   	push   %rbp
  6ebdc5:	41 57                	push   %r15
  6ebdc7:	41 56                	push   %r14
  6ebdc9:	41 55                	push   %r13
  6ebdcb:	41 54                	push   %r12
  6ebdcd:	53                   	push   %rbx
  6ebdce:	48 83 ec 48          	sub    $0x48,%rsp
  6ebdd2:	48 85 ff             	test   %rdi,%rdi
  6ebdd5:	74 12                	je     6ebde9 <user_event_entry+0x29>
  6ebdd7:	48 83 ff 02          	cmp    $0x2,%rdi
  6ebddb:	0f 85 a1 01 00 00    	jne    6ebf82 <user_event_entry+0x1c2>
  6ebde1:	40 b5 02             	mov    $0x2,%bpl
  6ebde4:	45 31 ff             	xor    %r15d,%r15d
  6ebde7:	eb 05                	jmp    6ebdee <user_event_entry+0x2e>
  6ebde9:	41 b7 01             	mov    $0x1,%r15b
  6ebdec:	31 ed                	xor    %ebp,%ebp
  6ebdee:	48 8b 0d 2b 42 31 00 	mov    0x31422b(%rip),%rcx        # a00020 <_DYNAMIC+0x57970>
  6ebdf5:	48 8d 1d 34 e8 34 00 	lea    0x34e834(%rip),%rbx        # a3a630 <ostd::task::processor::CURRENT_TASK_PTR>
  6ebdfc:	48 29 cb             	sub    %rcx,%rbx
  6ebdff:	4c 8d 25 ea e9 34 00 	lea    0x34e9ea(%rip),%r12        # a3a7f0 <ostd::task::preempt::cpu_local::PREEMPT_INFO>
  6ebe06:	4c 89 e0             	mov    %r12,%rax
  6ebe09:	48 29 c8             	sub    %rcx,%rax
  6ebe0c:	e9 13 5c b5 ff       	jmp    241a24 <__kernelet_cpu_access_start+0x4183c>
  6ebe11:	48 85 db             	test   %rbx,%rbx
  6ebe14:	0f 84 75 01 00 00    	je     6ebf8f <user_event_entry+0x1cf>
  6ebe1a:	48 89 5c 24 18       	mov    %rbx,0x18(%rsp)
  6ebe1f:	48 85 c9             	test   %rcx,%rcx
  6ebe22:	0f 85 50 01 00 00    	jne    6ebf78 <user_event_entry+0x1b8>
  6ebe28:	89 c0                	mov    %eax,%eax
  6ebe2a:	48 85 c0             	test   %rax,%rax
  6ebe2d:	0f 84 45 01 00 00    	je     6ebf78 <user_event_entry+0x1b8>
  6ebe33:	4c 8b 6b 60          	mov    0x60(%rbx),%r13
  6ebe37:	4c 8b 73 70          	mov    0x70(%rbx),%r14
  6ebe3b:	48 83 eb 80          	sub    $0xffffffffffffff80,%rbx
  6ebe3f:	48 c7 44 24 20 01 00 	movq   $0x1,0x20(%rsp)
  6ebe46:	00 00 
  6ebe48:	48 89 5c 24 28       	mov    %rbx,0x28(%rsp)
  6ebe4d:	48 c7 44 24 30 ff ff 	movq   $0xffffffffffffffff,0x30(%rsp)
  6ebe54:	ff ff 
  6ebe56:	45 84 ff             	test   %r15b,%r15b
  6ebe59:	74 2c                	je     6ebe87 <user_event_entry+0xc7>
  6ebe5b:	49 8b 7d 00          	mov    0x0(%r13),%rdi
  6ebe5f:	48 83 c7 10          	add    $0x10,%rdi
  6ebe63:	40 0f b6 cd          	movzbl %bpl,%ecx
  6ebe67:	48 8d 54 24 18       	lea    0x18(%rsp),%rdx
  6ebe6c:	4c 8d 44 24 20       	lea    0x20(%rsp),%r8
  6ebe71:	4c 89 f6             	mov    %r14,%rsi
  6ebe74:	e8 17 5b df ff       	call   4e1990 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle>
  6ebe79:	84 c0                	test   %al,%al
  6ebe7b:	74 71                	je     6ebeee <user_event_entry+0x12e>
  6ebe7d:	e8 3e cb fe ff       	call   6d89c0 <ostd::task::exit_current_task>
  6ebe82:	e9 55 01 00 00       	jmp    6ebfdc <user_event_entry+0x21c>
  6ebe87:	49 8b 45 00          	mov    0x0(%r13),%rax
  6ebe8b:	4c 8b 78 38          	mov    0x38(%rax),%r15
  6ebe8f:	48 8b 40 40          	mov    0x40(%rax),%rax
  6ebe93:	48 89 e7             	mov    %rsp,%rdi
  6ebe96:	4c 89 fe             	mov    %r15,%rsi
  6ebe99:	ff 50 18             	call   *0x18(%rax)
  6ebe9c:	48 b8 b4 a5 18 b0 fd 	movabs $0xe24f38fdb018a5b4,%rax
  6ebea3:	38 4f e2 
  6ebea6:	48 33 44 24 08       	xor    0x8(%rsp),%rax
  6ebeab:	48 b9 45 f3 13 03 e6 	movabs $0xc9f482e60313f345,%rcx
  6ebeb2:	82 f4 c9 
  6ebeb5:	48 33 0c 24          	xor    (%rsp),%rcx
  6ebeb9:	48 09 c1             	or     %rax,%rcx
  6ebebc:	0f 85 00 01 00 00    	jne    6ebfc2 <user_event_entry+0x202>
  6ebec2:	49 8b 46 20          	mov    0x20(%r14),%rax
  6ebec6:	48 b9 ff ff ff ff ff 	movabs $0x7fffffffffffffff,%rcx
  6ebecd:	ff ff 7f 
  6ebed0:	48 39 c8             	cmp    %rcx,%rax
  6ebed3:	0f 83 f7 00 00 00    	jae    6ebfd0 <user_event_entry+0x210>
  6ebed9:	48 8d 48 01          	lea    0x1(%rax),%rcx
  6ebedd:	49 89 4e 20          	mov    %rcx,0x20(%r14)
  6ebee1:	49 8b 76 28          	mov    0x28(%r14),%rsi
  6ebee5:	48 85 f6             	test   %rsi,%rsi
  6ebee8:	75 71                	jne    6ebf5b <user_event_entry+0x19b>
  6ebeea:	49 89 46 20          	mov    %rax,0x20(%r14)
  6ebeee:	4c 2b 25 2b 41 31 00 	sub    0x31412b(%rip),%r12        # a00020 <_DYNAMIC+0x57970>
  6ebef5:	e9 5c 5b b5 ff       	jmp    241a56 <__kernelet_cpu_access_start+0x4186e>
  6ebefa:	45 85 e4             	test   %r12d,%r12d
  6ebefd:	0f 84 9a 00 00 00    	je     6ebf9d <user_event_entry+0x1dd>
  6ebf03:	85 c0                	test   %eax,%eax
  6ebf05:	0f 94 c0             	sete   %al
  6ebf08:	24 01                	and    $0x1,%al
  6ebf0a:	88 04 24             	mov    %al,(%rsp)
  6ebf0d:	85 d2                	test   %edx,%edx
  6ebf0f:	0f 85 92 00 00 00    	jne    6ebfa7 <user_event_entry+0x1e7>
  6ebf15:	80 7c 24 20 00       	cmpb   $0x0,0x20(%rsp)
  6ebf1a:	0f 84 90 00 00 00    	je     6ebfb0 <user_event_entry+0x1f0>
  6ebf20:	49 83 c6 60          	add    $0x60,%r14
  6ebf24:	48 89 e6             	mov    %rsp,%rsi
  6ebf27:	4c 89 f7             	mov    %r14,%rdi
  6ebf2a:	e8 e1 b1 c5 ff       	call   347110 <<aster_core::process::posix_thread::thread_local::SuppUserContext>::before_user_exec>
  6ebf2f:	48 8b 05 da 41 31 00 	mov    0x3141da(%rip),%rax        # a00110 <_DYNAMIC+0x57a60>
  6ebf36:	48 8b 00             	mov    (%rax),%rax
  6ebf39:	31 ff                	xor    %edi,%edi
  6ebf3b:	ff 50 68             	call   *0x68(%rax)
  6ebf3e:	48 8d 3d 1d ed 17 00 	lea    0x17ed1d(%rip),%rdi        # 86ac62 <anon.c2df9e03b4d6d7c0a78f4f050a2b780d.17.llvm.1328962690349044372+0x1f>
  6ebf45:	48 8d 15 dc 31 34 00 	lea    0x3431dc(%rip),%rdx        # a2f128 <anon.c2df9e03b4d6d7c0a78f4f050a2b780d.24.llvm.1328962690349044372+0x18>
  6ebf4c:	be b3 00 00 00       	mov    $0xb3,%esi
  6ebf51:	e8 ea fa fc ff       	call   6bba40 <core::panicking::panic_fmt>
  6ebf56:	e9 81 00 00 00       	jmp    6ebfdc <user_event_entry+0x21c>
  6ebf5b:	48 83 c6 10          	add    $0x10,%rsi
  6ebf5f:	4c 89 ff             	mov    %r15,%rdi
  6ebf62:	e8 d9 2e df ff       	call   4dee40 <aster_core::process::signal::pending::has_pending_signal>
  6ebf67:	49 ff 4e 20          	decq   0x20(%r14)
  6ebf6b:	84 c0                	test   %al,%al
  6ebf6d:	0f 85 e8 fe ff ff    	jne    6ebe5b <user_event_entry+0x9b>
  6ebf73:	e9 76 ff ff ff       	jmp    6ebeee <user_event_entry+0x12e>
  6ebf78:	e8 33 ef fe ff       	call   6daeb0 <ostd::arch::irq::ops::finish_enable_local_slow>
  6ebf7d:	e9 b1 fe ff ff       	jmp    6ebe33 <user_event_entry+0x73>
  6ebf82:	48 83 ff 01          	cmp    $0x1,%rdi
  6ebf86:	75 0e                	jne    6ebf96 <user_event_entry+0x1d6>
  6ebf88:	e8 d3 f3 ff ff       	call   6eb360 <ostd::user::kernelet_events::user_exception_entry>
  6ebf8d:	eb 4d                	jmp    6ebfdc <user_event_entry+0x21c>
  6ebf8f:	e8 ac f3 ff ff       	call   6eb340 <ostd::user::kernelet_events::missing_current_task>
  6ebf94:	eb 46                	jmp    6ebfdc <user_event_entry+0x21c>
  6ebf96:	e8 65 f3 ff ff       	call   6eb300 <ostd::user::kernelet_events::invalid_user_event>
  6ebf9b:	eb 3f                	jmp    6ebfdc <user_event_entry+0x21c>
  6ebf9d:	e8 ce a7 00 00       	call   6f6770 <<ostd::irq::guard::DisabledLocalIrqGuard>::preempt_and_disable_slow>
  6ebfa2:	e9 61 ff ff ff       	jmp    6ebf08 <user_event_entry+0x148>
  6ebfa7:	89 d7                	mov    %edx,%edi
  6ebfa9:	e8 a2 f6 ff ff       	call   6eb650 <ostd::user::kernelet_events::panic_active_preempt_guard>
  6ebfae:	eb 2c                	jmp    6ebfdc <user_event_entry+0x21c>
  6ebfb0:	48 8d 7c 24 20       	lea    0x20(%rsp),%rdi
  6ebfb5:	48 89 de             	mov    %rbx,%rsi
  6ebfb8:	e8 73 5a ff ff       	call   6e1a30 <<ostd::arch::cpu::context::UserContext>::sync_owned_to_frame>
  6ebfbd:	e9 5e ff ff ff       	jmp    6ebf20 <user_event_entry+0x160>
  6ebfc2:	48 8d 3d 87 b2 32 00 	lea    0x32b287(%rip),%rdi        # a17250 <anon.7e0bfdcbbaf78bb5e7c5ed7ecb0ac195.382.llvm.9549409281826994870>
  6ebfc9:	e8 02 d7 fc ff       	call   6b96d0 <core::option::unwrap_failed>
  6ebfce:	eb 0c                	jmp    6ebfdc <user_event_entry+0x21c>
  6ebfd0:	48 8d 3d 91 b2 32 00 	lea    0x32b291(%rip),%rdi        # a17268 <anon.7e0bfdcbbaf78bb5e7c5ed7ecb0ac195.383.llvm.9549409281826994870>
  6ebfd7:	e8 54 e8 fc ff       	call   6ba830 <core::cell::panic_already_mutably_borrowed>
  6ebfdc:	0f 0b                	ud2
  6ebfde:	f3 0f 1e fa          	endbr64
  6ebfe2:	e8 f8 f9 fc ff       	call   6bb9df <core::panicking::panic_cannot_unwind>
  6ebfe7:	f3 0f 1e fa          	endbr64
  6ebfeb:	e8 ef f9 fc ff       	call   6bb9df <core::panicking::panic_cannot_unwind>
  6ebff0:	f3 0f 1e fa          	endbr64
  6ebff4:	49 ff 4e 20          	decq   0x20(%r14)
  6ebff8:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
  6ebffd:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
  6ec002:	e8 19 ec ff ff       	call   6eac20 <core::ptr::drop_glue::<ostd::arch::cpu::context::UserContext>>
  6ec007:	e8 d3 f9 fc ff       	call   6bb9df <core::panicking::panic_cannot_unwind>
  6ec00c:	f3 0f 1e fa          	endbr64
  6ec010:	48 89 e7             	mov    %rsp,%rdi
  6ec013:	e8 38 aa 00 00       	call   6f6a50 <<ostd::irq::guard::DisabledLocalIrqGuard as core::ops::drop::Drop>::drop>
  6ec018:	eb de                	jmp    6ebff8 <user_event_entry+0x238>
  6ec01a:	f3 0f 1e fa          	endbr64
  6ec01e:	e8 28 f8 fc ff       	call   6bb84b <core::panicking::panic_in_cleanup>
  6ec023:	f3 0f 1e fa          	endbr64
  6ec027:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
  6ec02c:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
  6ec031:	e8 ea eb ff ff       	call   6eac20 <core::ptr::drop_glue::<ostd::arch::cpu::context::UserContext>>
  6ec036:	e8 a4 f9 fc ff       	call   6bb9df <core::panicking::panic_cannot_unwind>
