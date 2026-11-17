
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/syscall-path-validation/image-release.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000071ea20 <user_event_entry>:
  71ea20:	f3 0f 1e fa          	endbr64
  71ea24:	55                   	push   %rbp
  71ea25:	41 57                	push   %r15
  71ea27:	41 56                	push   %r14
  71ea29:	41 55                	push   %r13
  71ea2b:	41 54                	push   %r12
  71ea2d:	53                   	push   %rbx
  71ea2e:	48 83 ec 48          	sub    $0x48,%rsp
  71ea32:	48 85 ff             	test   %rdi,%rdi
  71ea35:	74 12                	je     71ea49 <user_event_entry+0x29>
  71ea37:	48 83 ff 02          	cmp    $0x2,%rdi
  71ea3b:	0f 85 a1 01 00 00    	jne    71ebe2 <user_event_entry+0x1c2>
  71ea41:	40 b5 02             	mov    $0x2,%bpl
  71ea44:	45 31 ff             	xor    %r15d,%r15d
  71ea47:	eb 05                	jmp    71ea4e <user_event_entry+0x2e>
  71ea49:	41 b7 01             	mov    $0x1,%r15b
  71ea4c:	31 ed                	xor    %ebp,%ebp
  71ea4e:	48 8b 0d cb 15 2e 00 	mov    0x2e15cb(%rip),%rcx        # a00020 <_DYNAMIC+0x5d9d8>
  71ea55:	48 8d 1d e4 bb 31 00 	lea    0x31bbe4(%rip),%rbx        # a3a640 <_RNvNtNtCs3BxAPKCioTh_4ostd4task9processor16CURRENT_TASK_PTR>
  71ea5c:	48 29 cb             	sub    %rcx,%rbx
  71ea5f:	4c 8d 25 9a bd 31 00 	lea    0x31bd9a(%rip),%r12        # a3a800 <_RNvNtNtNtCs3BxAPKCioTh_4ostd4task7preempt9cpu_local12PREEMPT_INFO>
  71ea66:	4c 89 e0             	mov    %r12,%rax
  71ea69:	48 29 c8             	sub    %rcx,%rax
  71ea6c:	e9 75 34 b2 ff       	jmp    241ee6 <__kernelet_cpu_access_start+0x41cfe>
  71ea71:	48 85 db             	test   %rbx,%rbx
  71ea74:	0f 84 75 01 00 00    	je     71ebef <user_event_entry+0x1cf>
  71ea7a:	48 89 5c 24 18       	mov    %rbx,0x18(%rsp)
  71ea7f:	48 85 c9             	test   %rcx,%rcx
  71ea82:	0f 85 50 01 00 00    	jne    71ebd8 <user_event_entry+0x1b8>
  71ea88:	89 c0                	mov    %eax,%eax
  71ea8a:	48 85 c0             	test   %rax,%rax
  71ea8d:	0f 84 45 01 00 00    	je     71ebd8 <user_event_entry+0x1b8>
  71ea93:	4c 8b 6b 60          	mov    0x60(%rbx),%r13
  71ea97:	4c 8b 73 70          	mov    0x70(%rbx),%r14
  71ea9b:	48 83 eb 80          	sub    $0xffffffffffffff80,%rbx
  71ea9f:	48 c7 44 24 20 01 00 	movq   $0x1,0x20(%rsp)
  71eaa6:	00 00 
  71eaa8:	48 89 5c 24 28       	mov    %rbx,0x28(%rsp)
  71eaad:	48 c7 44 24 30 ff ff 	movq   $0xffffffffffffffff,0x30(%rsp)
  71eab4:	ff ff 
  71eab6:	45 84 ff             	test   %r15b,%r15b
  71eab9:	74 2c                	je     71eae7 <user_event_entry+0xc7>
  71eabb:	49 8b 7d 00          	mov    0x0(%r13),%rdi
  71eabf:	48 83 c7 10          	add    $0x10,%rdi
  71eac3:	40 0f b6 cd          	movzbl %bpl,%ecx
  71eac7:	48 8d 54 24 18       	lea    0x18(%rsp),%rdx
  71eacc:	4c 8d 44 24 20       	lea    0x20(%rsp),%r8
  71ead1:	4c 89 f6             	mov    %r14,%rsi
  71ead4:	e8 f7 32 d6 ff       	call   481dd0 <_RNvXNtNtCshotNd2mSv6q_10aster_core6thread4taskNtB4_6ThreadNtNtNtCs3BxAPKCioTh_4ostd4user15kernelet_events16UserEventHandler6handle>
  71ead9:	84 c0                	test   %al,%al
  71eadb:	74 71                	je     71eb4e <user_event_entry+0x12e>
  71eadd:	e8 3e 36 fe ff       	call   702120 <_RNvNtCs3BxAPKCioTh_4ostd4task17exit_current_task>
  71eae2:	e9 55 01 00 00       	jmp    71ec3c <user_event_entry+0x21c>
  71eae7:	49 8b 45 00          	mov    0x0(%r13),%rax
  71eaeb:	4c 8b 78 38          	mov    0x38(%rax),%r15
  71eaef:	48 8b 40 40          	mov    0x40(%rax),%rax
  71eaf3:	48 89 e7             	mov    %rsp,%rdi
  71eaf6:	4c 89 fe             	mov    %r15,%rsi
  71eaf9:	ff 50 18             	call   *0x18(%rax)
  71eafc:	48 b8 6d 22 34 d7 92 	movabs $0x3344392d734226d,%rax
  71eb03:	43 34 03 
  71eb06:	48 33 44 24 08       	xor    0x8(%rsp),%rax
  71eb0b:	48 b9 d7 0b 84 d2 f3 	movabs $0x124f89f3d2840bd7,%rcx
  71eb12:	89 4f 12 
  71eb15:	48 33 0c 24          	xor    (%rsp),%rcx
  71eb19:	48 09 c1             	or     %rax,%rcx
  71eb1c:	0f 85 00 01 00 00    	jne    71ec22 <user_event_entry+0x202>
  71eb22:	49 8b 46 20          	mov    0x20(%r14),%rax
  71eb26:	48 b9 ff ff ff ff ff 	movabs $0x7fffffffffffffff,%rcx
  71eb2d:	ff ff 7f 
  71eb30:	48 39 c8             	cmp    %rcx,%rax
  71eb33:	0f 83 f7 00 00 00    	jae    71ec30 <user_event_entry+0x210>
  71eb39:	48 8d 48 01          	lea    0x1(%rax),%rcx
  71eb3d:	49 89 4e 20          	mov    %rcx,0x20(%r14)
  71eb41:	49 8b 76 28          	mov    0x28(%r14),%rsi
  71eb45:	48 85 f6             	test   %rsi,%rsi
  71eb48:	75 71                	jne    71ebbb <user_event_entry+0x19b>
  71eb4a:	49 89 46 20          	mov    %rax,0x20(%r14)
  71eb4e:	4c 2b 25 cb 14 2e 00 	sub    0x2e14cb(%rip),%r12        # a00020 <_DYNAMIC+0x5d9d8>
  71eb55:	e9 d5 33 b2 ff       	jmp    241f2f <__kernelet_cpu_access_start+0x41d47>
  71eb5a:	45 85 e4             	test   %r12d,%r12d
  71eb5d:	0f 84 9a 00 00 00    	je     71ebfd <user_event_entry+0x1dd>
  71eb63:	85 c0                	test   %eax,%eax
  71eb65:	0f 94 c0             	sete   %al
  71eb68:	24 01                	and    $0x1,%al
  71eb6a:	88 04 24             	mov    %al,(%rsp)
  71eb6d:	85 d2                	test   %edx,%edx
  71eb6f:	0f 85 92 00 00 00    	jne    71ec07 <user_event_entry+0x1e7>
  71eb75:	80 7c 24 20 00       	cmpb   $0x0,0x20(%rsp)
  71eb7a:	0f 84 90 00 00 00    	je     71ec10 <user_event_entry+0x1f0>
  71eb80:	49 83 c6 60          	add    $0x60,%r14
  71eb84:	48 89 e6             	mov    %rsp,%rsi
  71eb87:	4c 89 f7             	mov    %r14,%rdi
  71eb8a:	e8 c1 3a bb ff       	call   2d2650 <_RNvMs_NtNtNtCshotNd2mSv6q_10aster_core7process12posix_thread12thread_localNtB4_15SuppUserContext16before_user_exec>
  71eb8f:	48 8b 05 a2 14 2e 00 	mov    0x2e14a2(%rip),%rax        # a00038 <_DYNAMIC+0x5d9f0>
  71eb96:	48 8b 00             	mov    (%rax),%rax
  71eb99:	31 ff                	xor    %edi,%edi
  71eb9b:	ff 50 68             	call   *0x68(%rax)
  71eb9e:	48 8d 3d ae 4d 14 00 	lea    0x144dae(%rip),%rdi        # 863953 <anon.31357acbf73c121db40f526e06268467.4.llvm.186973046271484012+0x2b>
  71eba5:	48 8d 15 04 0b 31 00 	lea    0x310b04(%rip),%rdx        # a2f6b0 <anon.31357acbf73c121db40f526e06268467.11.llvm.186973046271484012+0x18>
  71ebac:	be b3 00 00 00       	mov    $0xb3,%esi
  71ebb1:	e8 da 51 fc ff       	call   6e3d90 <_RNvNtCs4l6QGzsNTLX_4core9panicking9panic_fmt>
  71ebb6:	e9 81 00 00 00       	jmp    71ec3c <user_event_entry+0x21c>
  71ebbb:	48 83 c6 10          	add    $0x10,%rsi
  71ebbf:	4c 89 ff             	mov    %r15,%rdi
  71ebc2:	e8 29 01 d6 ff       	call   47ecf0 <_RNvNtNtNtCshotNd2mSv6q_10aster_core7process6signal7pending18has_pending_signal>
  71ebc7:	49 ff 4e 20          	decq   0x20(%r14)
  71ebcb:	84 c0                	test   %al,%al
  71ebcd:	0f 85 e8 fe ff ff    	jne    71eabb <user_event_entry+0x9b>
  71ebd3:	e9 76 ff ff ff       	jmp    71eb4e <user_event_entry+0x12e>
  71ebd8:	e8 83 f6 ff ff       	call   71e260 <_RNvNtNtNtCs3BxAPKCioTh_4ostd4arch3irq3ops24finish_enable_local_slow.llvm.186973046271484012>
  71ebdd:	e9 b1 fe ff ff       	jmp    71ea93 <user_event_entry+0x73>
  71ebe2:	48 83 ff 01          	cmp    $0x1,%rdi
  71ebe6:	75 0e                	jne    71ebf6 <user_event_entry+0x1d6>
  71ebe8:	e8 03 f3 ff ff       	call   71def0 <_RNvNtNtCs3BxAPKCioTh_4ostd4user15kernelet_events20user_exception_entry>
  71ebed:	eb 4d                	jmp    71ec3c <user_event_entry+0x21c>
  71ebef:	e8 dc f2 ff ff       	call   71ded0 <_RNvNtNtCs3BxAPKCioTh_4ostd4user15kernelet_events20missing_current_task>
  71ebf4:	eb 46                	jmp    71ec3c <user_event_entry+0x21c>
  71ebf6:	e8 95 f2 ff ff       	call   71de90 <_RNvNtNtCs3BxAPKCioTh_4ostd4user15kernelet_events18invalid_user_event>
  71ebfb:	eb 3f                	jmp    71ec3c <user_event_entry+0x21c>
  71ebfd:	e8 1e a5 00 00       	call   729120 <_RNvMs1_NtNtCs3BxAPKCioTh_4ostd3irq5guardNtB5_21DisabledLocalIrqGuard24preempt_and_disable_slow>
  71ec02:	e9 61 ff ff ff       	jmp    71eb68 <user_event_entry+0x148>
  71ec07:	89 d7                	mov    %edx,%edi
  71ec09:	e8 e2 f5 ff ff       	call   71e1f0 <_RNvNtNtCs3BxAPKCioTh_4ostd4user15kernelet_events26panic_active_preempt_guard>
  71ec0e:	eb 2c                	jmp    71ec3c <user_event_entry+0x21c>
  71ec10:	48 8d 7c 24 20       	lea    0x20(%rsp),%rdi
  71ec15:	48 89 de             	mov    %rbx,%rsi
  71ec18:	e8 53 08 00 00       	call   71f470 <_RNvMsf_NtNtNtCs3BxAPKCioTh_4ostd4arch3cpu7contextNtB5_11UserContext19sync_owned_to_frame>
  71ec1d:	e9 5e ff ff ff       	jmp    71eb80 <user_event_entry+0x160>
  71ec22:	48 8d 3d 1f 49 2f 00 	lea    0x2f491f(%rip),%rdi        # a13548 <anon.cab62059654a38090c1badc12653714e.349.llvm.4467322877837864737>
  71ec29:	e8 f2 2d fc ff       	call   6e1a20 <_RNvNtCs4l6QGzsNTLX_4core6option13unwrap_failed>
  71ec2e:	eb 0c                	jmp    71ec3c <user_event_entry+0x21c>
  71ec30:	48 8d 3d 29 49 2f 00 	lea    0x2f4929(%rip),%rdi        # a13560 <anon.cab62059654a38090c1badc12653714e.350.llvm.4467322877837864737>
  71ec37:	e8 44 3f fc ff       	call   6e2b80 <_RNvNtCs4l6QGzsNTLX_4core4cell30panic_already_mutably_borrowed>
  71ec3c:	0f 0b                	ud2
  71ec3e:	f3 0f 1e fa          	endbr64
  71ec42:	e8 e8 50 fc ff       	call   6e3d2f <_RNvNtCs4l6QGzsNTLX_4core9panicking19panic_cannot_unwind>
  71ec47:	f3 0f 1e fa          	endbr64
  71ec4b:	e8 df 50 fc ff       	call   6e3d2f <_RNvNtCs4l6QGzsNTLX_4core9panicking19panic_cannot_unwind>
  71ec50:	f3 0f 1e fa          	endbr64
  71ec54:	49 ff 4e 20          	decq   0x20(%r14)
  71ec58:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
  71ec5d:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
  71ec62:	e8 b9 ed ff ff       	call   71da20 <_RINvNtCs4l6QGzsNTLX_4core3ptr9drop_glueNtNtNtNtCs3BxAPKCioTh_4ostd4arch3cpu7context11UserContextEBJ_>
  71ec67:	e8 c3 50 fc ff       	call   6e3d2f <_RNvNtCs4l6QGzsNTLX_4core9panicking19panic_cannot_unwind>
  71ec6c:	f3 0f 1e fa          	endbr64
  71ec70:	48 89 e7             	mov    %rsp,%rdi
  71ec73:	e8 d8 ab 00 00       	call   729850 <_RNvXs3_NtNtCs3BxAPKCioTh_4ostd3irq5guardNtB5_21DisabledLocalIrqGuardNtNtNtCs4l6QGzsNTLX_4core3ops4drop4Drop4drop>
  71ec78:	eb de                	jmp    71ec58 <user_event_entry+0x238>
  71ec7a:	f3 0f 1e fa          	endbr64
  71ec7e:	e8 18 4f fc ff       	call   6e3b9b <_RNvNtCs4l6QGzsNTLX_4core9panicking16panic_in_cleanup>
  71ec83:	f3 0f 1e fa          	endbr64
  71ec87:	48 8b 7c 24 20       	mov    0x20(%rsp),%rdi
  71ec8c:	48 8b 74 24 28       	mov    0x28(%rsp),%rsi
  71ec91:	e8 8a ed ff ff       	call   71da20 <_RINvNtCs4l6QGzsNTLX_4core3ptr9drop_glueNtNtNtNtCs3BxAPKCioTh_4ostd4arch3cpu7context11UserContextEBJ_>
  71ec96:	e8 94 50 fc ff       	call   6e3d2f <_RNvNtCs4l6QGzsNTLX_4core9panicking19panic_cannot_unwind>
