
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006cc090 <first_user_task_entry>:
  6cc090:	f3 0f 1e fa          	endbr64
  6cc094:	41 57                	push   %r15
  6cc096:	41 56                	push   %r14
  6cc098:	41 54                	push   %r12
  6cc09a:	53                   	push   %rbx
  6cc09b:	48 81 ec d8 00 00 00 	sub    $0xd8,%rsp
  6cc0a2:	e8 89 a6 ff ff       	call   6c6730 <ostd::task::processor::after_switching_to>
  6cc0a7:	48 8d 0d 92 e5 36 00 	lea    0x36e592(%rip),%rcx        # a3a640 <ostd::task::processor::CURRENT_TASK_PTR>
  6cc0ae:	48 2b 0d 6b 3f 33 00 	sub    0x333f6b(%rip),%rcx        # a00020 <_DYNAMIC+0x5ee40>
  6cc0b5:	e9 a6 53 b7 ff       	jmp    241460 <__kernelet_cpu_access_start+0x4123f>
  6cc0ba:	48 85 c0             	test   %rax,%rax
  6cc0bd:	0f 84 3f 01 00 00    	je     6cc202 <first_user_task_entry+0x172>
  6cc0c3:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  6cc0c8:	48 8b 58 60          	mov    0x60(%rax),%rbx
  6cc0cc:	e8 6f c4 ff ff       	call   6c8540 <ostd::kernelet::entry::user_event_record>
  6cc0d1:	4c 8b 30             	mov    (%rax),%r14
  6cc0d4:	48 c7 44 24 10 01 00 00 00 	movq   $0x1,0x10(%rsp)
  6cc0dd:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  6cc0e2:	48 c7 84 24 c0 00 00 00 ff ff ff ff 	movq   $0xffffffffffffffff,0xc0(%rsp)
  6cc0ee:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
  6cc0f3:	48 8d 54 24 10       	lea    0x10(%rsp),%rdx
  6cc0f8:	48 89 df             	mov    %rbx,%rdi
  6cc0fb:	e8 c0 3b cc ff       	call   38fcc0 <__ostd_user_init>
  6cc100:	48 8b 3b             	mov    (%rbx),%rdi
  6cc103:	48 83 c7 10          	add    $0x10,%rdi
  6cc107:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
  6cc10c:	e8 5f ed cb ff       	call   38ae70 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::should_exit>
  6cc111:	84 c0                	test   %al,%al
  6cc113:	74 0a                	je     6cc11f <first_user_task_entry+0x8f>
  6cc115:	e8 a6 a0 ff ff       	call   6c61c0 <ostd::task::exit_current_task>
  6cc11a:	e9 3e 01 00 00       	jmp    6cc25d <first_user_task_entry+0x1cd>
  6cc11f:	e9 70 53 b7 ff       	jmp    241494 <__kernelet_cpu_access_start+0x41273>
  6cc124:	8b 42 50             	mov    0x50(%rdx),%eax
  6cc127:	89 44 24 04          	mov    %eax,0x4(%rsp)
  6cc12b:	85 c0                	test   %eax,%eax
  6cc12d:	0f 85 e9 00 00 00    	jne    6cc21c <first_user_task_entry+0x18c>
  6cc133:	48 8d 3d e6 25 36 00 	lea    0x3625e6(%rip),%rdi        # a2e720 <anon.e0af733efa188d9da4104a951dd93b7e.31.llvm.15477716685929987621+0x18>
  6cc13a:	e8 d1 9b 00 00       	call   6d5d10 <ostd::task::scheduler::might_preempt>
  6cc13f:	e9 7f 53 b7 ff       	jmp    2414c3 <__kernelet_cpu_access_start+0x412a2>
  6cc144:	85 c0                	test   %eax,%eax
  6cc146:	75 0a                	jne    6cc152 <first_user_task_entry+0xc2>
  6cc148:	b9 01 00 00 00       	mov    $0x1,%ecx
  6cc14d:	e9 a0 53 b7 ff       	jmp    2414f2 <__kernelet_cpu_access_start+0x412d1>
  6cc152:	85 c0                	test   %eax,%eax
  6cc154:	0f 94 44 24 04       	sete   0x4(%rsp)
  6cc159:	80 7c 24 10 00       	cmpb   $0x0,0x10(%rsp)
  6cc15e:	75 62                	jne    6cc1c2 <first_user_task_entry+0x132>
  6cc160:	48 8d 74 24 18       	lea    0x18(%rsp),%rsi
  6cc165:	4c 8b bc 24 a8 00 00 00 	mov    0xa8(%rsp),%r15
  6cc16d:	4c 8b a4 24 b0 00 00 00 	mov    0xb0(%rsp),%r12
  6cc175:	41 81 e7 d5 0d 24 00 	and    $0x240dd5,%r15d
  6cc17c:	49 81 cf 02 02 00 00 	or     $0x202,%r15
  6cc183:	ba 88 00 00 00       	mov    $0x88,%edx
  6cc188:	4c 89 f7             	mov    %r14,%rdi
  6cc18b:	e8 f0 b3 02 00       	call   6f7580 <memcpy>
  6cc190:	49 c7 86 88 00 00 00 33 00 00 00 	movq   $0x33,0x88(%r14)
  6cc19b:	4d 89 be 90 00 00 00 	mov    %r15,0x90(%r14)
  6cc1a2:	4d 89 a6 98 00 00 00 	mov    %r12,0x98(%r14)
  6cc1a9:	49 c7 86 a0 00 00 00 2b 00 00 00 	movq   $0x2b,0xa0(%r14)
  6cc1b4:	48 c7 44 24 10 01 00 00 00 	movq   $0x1,0x10(%rsp)
  6cc1bd:	4c 89 74 24 18       	mov    %r14,0x18(%rsp)
  6cc1c2:	48 8d 74 24 08       	lea    0x8(%rsp),%rsi
  6cc1c7:	48 8d 54 24 04       	lea    0x4(%rsp),%rdx
  6cc1cc:	48 89 df             	mov    %rbx,%rdi
  6cc1cf:	e8 9c 3b cc ff       	call   38fd70 <__ostd_user_pre_user_run>
  6cc1d4:	48 8b 05 5d 3e 33 00 	mov    0x333e5d(%rip),%rax        # a00038 <_DYNAMIC+0x5ee58>
  6cc1db:	48 8b 00             	mov    (%rax),%rax
  6cc1de:	48 85 c0             	test   %rax,%rax
  6cc1e1:	74 62                	je     6cc245 <first_user_task_entry+0x1b5>
  6cc1e3:	31 ff                	xor    %edi,%edi
  6cc1e5:	ff 50 68             	call   *0x68(%rax)
  6cc1e8:	48 8d 3d 15 69 19 00 	lea    0x196915(%rip),%rdi        # 862b04 <anon.e0af733efa188d9da4104a951dd93b7e.10.llvm.15477716685929987621+0xf2>
  6cc1ef:	48 8d 15 42 25 36 00 	lea    0x362542(%rip),%rdx        # a2e738 <anon.e0af733efa188d9da4104a951dd93b7e.31.llvm.15477716685929987621+0x30>
  6cc1f6:	be b3 00 00 00       	mov    $0xb3,%esi
  6cc1fb:	e8 f0 c9 fd ff       	call   6a8bf0 <core::panicking::panic_fmt>
  6cc200:	eb 5b                	jmp    6cc25d <first_user_task_entry+0x1cd>
  6cc202:	48 8d 3d 53 6b 19 00 	lea    0x196b53(%rip),%rdi        # 862d5c <anon.e0af733efa188d9da4104a951dd93b7e.51.llvm.15477716685929987621+0x2e>
  6cc209:	48 8d 15 38 26 36 00 	lea    0x362638(%rip),%rdx        # a2e848 <anon.e0af733efa188d9da4104a951dd93b7e.54.llvm.15477716685929987621+0x38>
  6cc210:	be 2d 00 00 00       	mov    $0x2d,%esi
  6cc215:	e8 26 a6 fd ff       	call   6a6840 <core::option::expect_failed>
  6cc21a:	eb 41                	jmp    6cc25d <first_user_task_entry+0x1cd>
  6cc21c:	48 8d 15 a9 65 15 00 	lea    0x1565a9(%rip),%rdx        # 8227cc <anon.45e5aa24a1f7492fd813e4484e513d71.67.llvm.3441646032486278169>
  6cc223:	48 8d 0d 33 69 19 00 	lea    0x196933(%rip),%rcx        # 862b5d <anon.e0af733efa188d9da4104a951dd93b7e.10.llvm.15477716685929987621+0x14b>
  6cc22a:	4c 8d 0d 1f 25 36 00 	lea    0x36251f(%rip),%r9        # a2e750 <anon.e0af733efa188d9da4104a951dd93b7e.31.llvm.15477716685929987621+0x48>
  6cc231:	48 8d 74 24 04       	lea    0x4(%rsp),%rsi
  6cc236:	41 b8 67 00 00 00    	mov    $0x67,%r8d
  6cc23c:	31 ff                	xor    %edi,%edi
  6cc23e:	e8 39 be 01 00       	call   6e807c <core::panicking::assert_failed::<u32, u32>>
  6cc243:	eb 18                	jmp    6cc25d <first_user_task_entry+0x1cd>
  6cc245:	48 8d 3d dc 64 19 00 	lea    0x1964dc(%rip),%rdi        # 862728 <anon.c25f29b7a7b48a9d99b68ffd5c2b443e.31.llvm.17932337005181077852>
  6cc24c:	48 8d 15 85 22 36 00 	lea    0x362285(%rip),%rdx        # a2e4d8 <anon.c25f29b7a7b48a9d99b68ffd5c2b443e.32.llvm.17932337005181077852>
  6cc253:	be 53 00 00 00       	mov    $0x53,%esi
  6cc258:	e8 93 c9 fd ff       	call   6a8bf0 <core::panicking::panic_fmt>
  6cc25d:	0f 0b                	ud2
  6cc25f:	f3 0f 1e fa          	endbr64
  6cc263:	48 8d 7c 24 04       	lea    0x4(%rsp),%rdi
  6cc268:	e8 63 15 01 00       	call   6dd7d0 <<ostd::irq::guard::DisabledLocalIrqGuard as core::ops::drop::Drop>::drop>
  6cc26d:	e8 1d c9 fd ff       	call   6a8b8f <core::panicking::panic_cannot_unwind>
  6cc272:	f3 0f 1e fa          	endbr64
  6cc276:	e8 80 c7 fd ff       	call   6a89fb <core::panicking::panic_in_cleanup>
  6cc27b:	f3 0f 1e fa          	endbr64
  6cc27f:	e8 0b c9 fd ff       	call   6a8b8f <core::panicking::panic_cannot_unwind>
