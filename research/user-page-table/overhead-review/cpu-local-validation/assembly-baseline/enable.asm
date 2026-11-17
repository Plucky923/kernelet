
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006c8a30 <ostd::arch::irq::ops::enable_local>:
  6c8a30:	f3 0f 1e fa          	endbr64
  6c8a34:	50                   	push   %rax
  6c8a35:	31 c0                	xor    %eax,%eax
  6c8a37:	e9 ef 84 b7 ff       	jmp    240f2b <__kernelet_cpu_access_start+0x40d0a>
  6c8a3c:	e9 19 85 b7 ff       	jmp    240f5a <__kernelet_cpu_access_start+0x40d39>
  6c8a41:	48 8b 02             	mov    (%rdx),%rax
  6c8a44:	48 85 c0             	test   %rax,%rax
  6c8a47:	0f 84 a7 00 00 00    	je     6c8af4 <ostd::arch::irq::ops::enable_local+0xc4>
  6c8a4d:	e9 37 85 b7 ff       	jmp    240f89 <__kernelet_cpu_access_start+0x40d68>
  6c8a52:	8b 42 50             	mov    0x50(%rdx),%eax
  6c8a55:	85 c0                	test   %eax,%eax
  6c8a57:	0f 85 b2 00 00 00    	jne    6c8b0f <ostd::arch::irq::ops::enable_local+0xdf>
  6c8a5d:	e9 56 85 b7 ff       	jmp    240fb8 <__kernelet_cpu_access_start+0x40d97>
  6c8a62:	8b 42 54             	mov    0x54(%rdx),%eax
  6c8a65:	85 c0                	test   %eax,%eax
  6c8a67:	0f 85 a2 00 00 00    	jne    6c8b0f <ostd::arch::irq::ops::enable_local+0xdf>
  6c8a6d:	e8 4e 03 01 00       	call   6d8dc0 <<ostd::irq::level::InterruptLevel>::current>
  6c8a72:	3c 02                	cmp    $0x2,%al
  6c8a74:	0f 85 95 00 00 00    	jne    6c8b0f <ostd::arch::irq::ops::enable_local+0xdf>
  6c8a7a:	e8 11 d8 ff ff       	call   6c6290 <ostd::task::virq_delivery_deferred>
  6c8a7f:	84 c0                	test   %al,%al
  6c8a81:	0f 85 88 00 00 00    	jne    6c8b0f <ostd::arch::irq::ops::enable_local+0xdf>
  6c8a87:	48 8d 05 b2 1b 37 00 	lea    0x371bb2(%rip),%rax        # a3a640 <ostd::task::processor::CURRENT_TASK_PTR>
  6c8a8e:	48 2b 05 8b 75 33 00 	sub    0x33758b(%rip),%rax        # a00020 <_DYNAMIC+0x5ee40>
  6c8a95:	e9 4d 85 b7 ff       	jmp    240fe7 <__kernelet_cpu_access_start+0x40dc6>
  6c8a9a:	48 85 f6             	test   %rsi,%rsi
  6c8a9d:	74 70                	je     6c8b0f <ostd::arch::irq::ops::enable_local+0xdf>
  6c8a9f:	48 8d 3d 7a 5a 36 00 	lea    0x365a7a(%rip),%rdi        # a2e520 <anon.c25f29b7a7b48a9d99b68ffd5c2b443e.36.llvm.17932337005181077852+0x18>
  6c8aa6:	e8 65 d2 00 00       	call   6d5d10 <ostd::task::scheduler::might_preempt>
  6c8aab:	e9 6b 85 b7 ff       	jmp    24101b <__kernelet_cpu_access_start+0x40dfa>
  6c8ab0:	48 8b 02             	mov    (%rdx),%rax
  6c8ab3:	48 85 c0             	test   %rax,%rax
  6c8ab6:	74 57                	je     6c8b0f <ostd::arch::irq::ops::enable_local+0xdf>
  6c8ab8:	48 8b 05 51 75 33 00 	mov    0x337551(%rip),%rax        # a00010 <_DYNAMIC+0x5ee30>
  6c8abf:	48 8b 00             	mov    (%rax),%rax
  6c8ac2:	48 85 c0             	test   %rax,%rax
  6c8ac5:	74 4a                	je     6c8b11 <ostd::arch::irq::ops::enable_local+0xe1>
  6c8ac7:	e9 7e 85 b7 ff       	jmp    24104a <__kernelet_cpu_access_start+0x40e29>
  6c8acc:	8b 4e 58             	mov    0x58(%rsi),%ecx
  6c8acf:	8b 90 f0 08 00 00    	mov    0x8f0(%rax),%edx
  6c8ad5:	0f b7 70 3a          	movzwl 0x3a(%rax),%esi
  6c8ad9:	c1 e6 07             	shl    $0x7,%esi
  6c8adc:	48 c1 e1 06          	shl    $0x6,%rcx
  6c8ae0:	48 01 c2             	add    %rax,%rdx
  6c8ae3:	48 01 f2             	add    %rsi,%rdx
  6c8ae6:	8b 44 11 10          	mov    0x10(%rcx,%rdx,1),%eax
  6c8aea:	85 c0                	test   %eax,%eax
  6c8aec:	75 21                	jne    6c8b0f <ostd::arch::irq::ops::enable_local+0xdf>
  6c8aee:	58                   	pop    %rax
  6c8aef:	e9 bc f5 ff ff       	jmp    6c80b0 <ostd::kernelet::entry::deliver_pending>
  6c8af4:	48 8d 05 59 1b 37 00 	lea    0x371b59(%rip),%rax        # a3a654 <ostd::task::preempt::cpu_local::PREEMPT_INFO>
  6c8afb:	48 2b 05 1e 75 33 00 	sub    0x33751e(%rip),%rax        # a00020 <_DYNAMIC+0x5ee40>
  6c8b02:	e9 72 85 b7 ff       	jmp    241079 <__kernelet_cpu_access_start+0x40e58>
  6c8b07:	85 f6                	test   %esi,%esi
  6c8b09:	0f 84 3e ff ff ff    	je     6c8a4d <ostd::arch::irq::ops::enable_local+0x1d>
  6c8b0f:	58                   	pop    %rax
  6c8b10:	c3                   	ret
  6c8b11:	48 8d 3d 39 9c 19 00 	lea    0x199c39(%rip),%rdi        # 862751 <anon.c25f29b7a7b48a9d99b68ffd5c2b443e.33.llvm.17932337005181077852>
  6c8b18:	48 8d 15 d1 59 36 00 	lea    0x3659d1(%rip),%rdx        # a2e4f0 <anon.c25f29b7a7b48a9d99b68ffd5c2b443e.34.llvm.17932337005181077852>
  6c8b1f:	be 4d 00 00 00       	mov    $0x4d,%esi
  6c8b24:	e8 c7 00 fe ff       	call   6a8bf0 <core::panicking::panic_fmt>
