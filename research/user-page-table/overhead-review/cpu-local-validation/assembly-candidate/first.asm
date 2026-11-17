
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006bde40 <first_user_task_entry>:
  6bde40:	f3 0f 1e fa          	endbr64
  6bde44:	55                   	push   %rbp
  6bde45:	41 57                	push   %r15
  6bde47:	41 56                	push   %r14
  6bde49:	41 54                	push   %r12
  6bde4b:	53                   	push   %rbx
  6bde4c:	48 81 ec e0 00 00 00 	sub    $0xe0,%rsp
  6bde53:	e8 68 92 ff ff       	call   6b70c0 <ostd::task::processor::after_switching_to>
  6bde58:	e9 a4 99 b7 ff       	jmp    237801 <__kernelet_cpu_access_start+0x375e0>
  6bde5d:	31 db                	xor    %ebx,%ebx
  6bde5f:	85 c0                	test   %eax,%eax
  6bde61:	40 0f 94 c5          	sete   %bpl
  6bde65:	e9 d1 99 b7 ff       	jmp    23783b <__kernelet_cpu_access_start+0x3761a>
  6bde6a:	48 8d 0d cf c7 37 00 	lea    0x37c7cf(%rip),%rcx        # a3a640 <ostd::task::processor::CURRENT_TASK_PTR>
  6bde71:	48 2b 0d a8 21 34 00 	sub    0x3421a8(%rip),%rcx        # a00020 <_DYNAMIC+0x5fd78>
  6bde78:	4c 8b 34 0f          	mov    (%rdi,%rcx,1),%r14
  6bde7c:	4d 85 f6             	test   %r14,%r14
  6bde7f:	0f 84 67 01 00 00    	je     6bdfec <first_user_task_entry+0x1ac>
  6bde85:	48 8b 0d 84 21 34 00 	mov    0x342184(%rip),%rcx        # a00010 <_DYNAMIC+0x5fd68>
  6bde8c:	48 8b 09             	mov    (%rcx),%rcx
  6bde8f:	48 85 c9             	test   %rcx,%rcx
  6bde92:	0f 84 6e 01 00 00    	je     6be006 <first_user_task_entry+0x1c6>
  6bde98:	8b 52 58             	mov    0x58(%rdx),%edx
  6bde9b:	8b b1 f0 08 00 00    	mov    0x8f0(%rcx),%esi
  6bdea1:	0f b7 79 3a          	movzwl 0x3a(%rcx),%edi
  6bdea5:	48 8d 3c 7f          	lea    (%rdi,%rdi,2),%rdi
  6bdea9:	c1 e7 06             	shl    $0x6,%edi
  6bdeac:	48 c1 e2 06          	shl    $0x6,%rdx
  6bdeb0:	48 01 ce             	add    %rcx,%rsi
  6bdeb3:	48 01 fe             	add    %rdi,%rsi
  6bdeb6:	48 8b 1c 32          	mov    (%rdx,%rsi,1),%rbx
  6bdeba:	85 c0                	test   %eax,%eax
  6bdebc:	75 05                	jne    6bdec3 <first_user_task_entry+0x83>
  6bdebe:	e8 8d 40 00 00       	call   6c1f50 <ostd::arch::irq::ops::enable_local>
  6bdec3:	4c 89 74 24 10       	mov    %r14,0x10(%rsp)
  6bdec8:	4d 8b 76 60          	mov    0x60(%r14),%r14
  6bdecc:	48 c7 44 24 18 01 00 00 00 	movq   $0x1,0x18(%rsp)
  6bded5:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
  6bdeda:	48 c7 84 24 c8 00 00 00 ff ff ff ff 	movq   $0xffffffffffffffff,0xc8(%rsp)
  6bdee6:	48 8d 74 24 10       	lea    0x10(%rsp),%rsi
  6bdeeb:	48 8d 54 24 18       	lea    0x18(%rsp),%rdx
  6bdef0:	4c 89 f7             	mov    %r14,%rdi
  6bdef3:	e8 b8 a4 de ff       	call   4a83b0 <__ostd_user_init>
  6bdef8:	49 8b 3e             	mov    (%r14),%rdi
  6bdefb:	48 83 c7 10          	add    $0x10,%rdi
  6bdeff:	48 8d 74 24 10       	lea    0x10(%rsp),%rsi
  6bdf04:	e8 f7 4f de ff       	call   4a2f00 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::should_exit>
  6bdf09:	84 c0                	test   %al,%al
  6bdf0b:	74 0a                	je     6bdf17 <first_user_task_entry+0xd7>
  6bdf0d:	e8 6e 8d ff ff       	call   6b6c80 <ostd::task::exit_current_task>
  6bdf12:	e9 4a 01 00 00       	jmp    6be061 <first_user_task_entry+0x221>
  6bdf17:	e9 52 99 b7 ff       	jmp    23786e <__kernelet_cpu_access_start+0x3764d>
  6bdf1c:	8b 42 50             	mov    0x50(%rdx),%eax
  6bdf1f:	89 44 24 0c          	mov    %eax,0xc(%rsp)
  6bdf23:	85 c0                	test   %eax,%eax
  6bdf25:	0f 85 f5 00 00 00    	jne    6be020 <first_user_task_entry+0x1e0>
  6bdf2b:	48 8d 3d 06 08 37 00 	lea    0x370806(%rip),%rdi        # a2e738 <anon.2556e6359d291468c09e00eda78c61db.22.llvm.15615756070059268768+0x48>
  6bdf32:	e8 29 1e 00 00       	call   6bfd60 <ostd::task::scheduler::might_preempt>
  6bdf37:	e9 61 99 b7 ff       	jmp    23789d <__kernelet_cpu_access_start+0x3767c>
  6bdf3c:	85 d2                	test   %edx,%edx
  6bdf3e:	0f 94 44 24 0c       	sete   0xc(%rsp)
  6bdf43:	80 7c 24 18 00       	cmpb   $0x0,0x18(%rsp)
  6bdf48:	75 62                	jne    6bdfac <first_user_task_entry+0x16c>
  6bdf4a:	48 8d 74 24 20       	lea    0x20(%rsp),%rsi
  6bdf4f:	4c 8b bc 24 b0 00 00 00 	mov    0xb0(%rsp),%r15
  6bdf57:	4c 8b a4 24 b8 00 00 00 	mov    0xb8(%rsp),%r12
  6bdf5f:	41 81 e7 d5 0d 24 00 	and    $0x240dd5,%r15d
  6bdf66:	49 81 cf 02 02 00 00 	or     $0x202,%r15
  6bdf6d:	ba 88 00 00 00       	mov    $0x88,%edx
  6bdf72:	48 89 df             	mov    %rbx,%rdi
  6bdf75:	e8 e6 a1 02 00       	call   6e8160 <memcpy>
  6bdf7a:	48 c7 83 88 00 00 00 33 00 00 00 	movq   $0x33,0x88(%rbx)
  6bdf85:	4c 89 bb 90 00 00 00 	mov    %r15,0x90(%rbx)
  6bdf8c:	4c 89 a3 98 00 00 00 	mov    %r12,0x98(%rbx)
  6bdf93:	48 c7 83 a0 00 00 00 2b 00 00 00 	movq   $0x2b,0xa0(%rbx)
  6bdf9e:	48 c7 44 24 18 01 00 00 00 	movq   $0x1,0x18(%rsp)
  6bdfa7:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
  6bdfac:	48 8d 74 24 10       	lea    0x10(%rsp),%rsi
  6bdfb1:	48 8d 54 24 0c       	lea    0xc(%rsp),%rdx
  6bdfb6:	4c 89 f7             	mov    %r14,%rdi
  6bdfb9:	e8 a2 a4 de ff       	call   4a8460 <__ostd_user_pre_user_run>
  6bdfbe:	48 8b 05 73 20 34 00 	mov    0x342073(%rip),%rax        # a00038 <_DYNAMIC+0x5fd90>
  6bdfc5:	48 8b 00             	mov    (%rax),%rax
  6bdfc8:	48 85 c0             	test   %rax,%rax
  6bdfcb:	74 7c                	je     6be049 <first_user_task_entry+0x209>
  6bdfcd:	31 ff                	xor    %edi,%edi
  6bdfcf:	ff 50 68             	call   *0x68(%rax)
  6bdfd2:	48 8d 3d 25 4b 1a 00 	lea    0x1a4b25(%rip),%rdi        # 862afe <anon.2556e6359d291468c09e00eda78c61db.26.llvm.15615756070059268768+0x17>
  6bdfd9:	48 8d 15 70 07 37 00 	lea    0x370770(%rip),%rdx        # a2e750 <anon.2556e6359d291468c09e00eda78c61db.22.llvm.15615756070059268768+0x60>
  6bdfe0:	be b3 00 00 00       	mov    $0xb3,%esi
  6bdfe5:	e8 f6 b7 fd ff       	call   6997e0 <core::panicking::panic_fmt>
  6bdfea:	eb 75                	jmp    6be061 <first_user_task_entry+0x221>
  6bdfec:	48 8d 3d 63 4d 1a 00 	lea    0x1a4d63(%rip),%rdi        # 862d56 <anon.2556e6359d291468c09e00eda78c61db.46.llvm.15615756070059268768+0x2e>
  6bdff3:	48 8d 15 66 08 37 00 	lea    0x370866(%rip),%rdx        # a2e860 <anon.2556e6359d291468c09e00eda78c61db.49.llvm.15615756070059268768+0x38>
  6bdffa:	be 2d 00 00 00       	mov    $0x2d,%esi
  6bdfff:	e8 2c 94 fd ff       	call   697430 <core::option::expect_failed>
  6be004:	eb 5b                	jmp    6be061 <first_user_task_entry+0x221>
  6be006:	48 8d 3d 50 51 1a 00 	lea    0x1a5150(%rip),%rdi        # 86315d <anon.b9a81f2eeec052eb13297414241e8ab2.32.llvm.7034704448355070909>
  6be00d:	48 8d 15 ac 0b 37 00 	lea    0x370bac(%rip),%rdx        # a2ebc0 <anon.b9a81f2eeec052eb13297414241e8ab2.33.llvm.7034704448355070909>
  6be014:	be 4d 00 00 00       	mov    $0x4d,%esi
  6be019:	e8 c2 b7 fd ff       	call   6997e0 <core::panicking::panic_fmt>
  6be01e:	eb 41                	jmp    6be061 <first_user_task_entry+0x221>
  6be020:	48 8d 15 a9 47 16 00 	lea    0x1647a9(%rip),%rdx        # 8227d0 <anon.6bbc1879cbe514377c4321431c5b6ee0.67.llvm.11246372459317742168>
  6be027:	48 8d 0d 29 4b 1a 00 	lea    0x1a4b29(%rip),%rcx        # 862b57 <anon.2556e6359d291468c09e00eda78c61db.26.llvm.15615756070059268768+0x70>
  6be02e:	4c 8d 0d 33 07 37 00 	lea    0x370733(%rip),%r9        # a2e768 <anon.2556e6359d291468c09e00eda78c61db.22.llvm.15615756070059268768+0x78>
  6be035:	48 8d 74 24 0c       	lea    0xc(%rsp),%rsi
  6be03a:	41 b8 67 00 00 00    	mov    $0x67,%r8d
  6be040:	31 ff                	xor    %edi,%edi
  6be042:	e8 0d 3c 01 00       	call   6d1c54 <core::panicking::assert_failed::<u32, u32>>
  6be047:	eb 18                	jmp    6be061 <first_user_task_entry+0x221>
  6be049:	48 8d 3d e4 50 1a 00 	lea    0x1a50e4(%rip),%rdi        # 863134 <anon.b9a81f2eeec052eb13297414241e8ab2.30.llvm.7034704448355070909>
  6be050:	48 8d 15 51 0b 37 00 	lea    0x370b51(%rip),%rdx        # a2eba8 <anon.b9a81f2eeec052eb13297414241e8ab2.31.llvm.7034704448355070909>
  6be057:	be 53 00 00 00       	mov    $0x53,%esi
  6be05c:	e8 7f b7 fd ff       	call   6997e0 <core::panicking::panic_fmt>
  6be061:	0f 0b                	ud2
  6be063:	f3 0f 1e fa          	endbr64
  6be067:	40 88 eb             	mov    %bpl,%bl
  6be06a:	89 df                	mov    %ebx,%edi
  6be06c:	e8 8f e0 ff ff       	call   6bc100 <core::ptr::drop_glue::<ostd::irq::guard::DisabledLocalIrqGuard>>
  6be071:	eb 17                	jmp    6be08a <first_user_task_entry+0x24a>
  6be073:	f3 0f 1e fa          	endbr64
  6be077:	e8 6f b5 fd ff       	call   6995eb <core::panicking::panic_in_cleanup>
  6be07c:	f3 0f 1e fa          	endbr64
  6be080:	48 8d 7c 24 0c       	lea    0xc(%rsp),%rdi
  6be085:	e8 c6 42 01 00       	call   6d2350 <<ostd::irq::guard::DisabledLocalIrqGuard as core::ops::drop::Drop>::drop>
  6be08a:	e8 f0 b6 fd ff       	call   69977f <core::panicking::panic_cannot_unwind>
  6be08f:	f3 0f 1e fa          	endbr64
  6be093:	e8 53 b5 fd ff       	call   6995eb <core::panicking::panic_in_cleanup>
  6be098:	f3 0f 1e fa          	endbr64
  6be09c:	e8 de b6 fd ff       	call   69977f <core::panicking::panic_cannot_unwind>
  6be0a1:	f3 0f 1e fa          	endbr64
  6be0a5:	e8 d5 b6 fd ff       	call   69977f <core::panicking::panic_cannot_unwind>
