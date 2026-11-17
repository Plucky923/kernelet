
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006c1f50 <ostd::arch::irq::ops::enable_local>:
  6c1f50:	f3 0f 1e fa          	endbr64
  6c1f54:	50                   	push   %rax
  6c1f55:	e9 8b 66 b7 ff       	jmp    2385e5 <__kernelet_cpu_access_start+0x383c4>
  6c1f5a:	48 85 d2             	test   %rdx,%rdx
  6c1f5d:	0f 84 a7 00 00 00    	je     6c200a <ostd::arch::irq::ops::enable_local+0xba>
  6c1f63:	e9 b3 66 b7 ff       	jmp    23861b <__kernelet_cpu_access_start+0x383fa>
  6c1f68:	8b 42 50             	mov    0x50(%rdx),%eax
  6c1f6b:	85 c0                	test   %eax,%eax
  6c1f6d:	0f 85 b2 00 00 00    	jne    6c2025 <ostd::arch::irq::ops::enable_local+0xd5>
  6c1f73:	e9 d2 66 b7 ff       	jmp    23864a <__kernelet_cpu_access_start+0x38429>
  6c1f78:	8b 42 54             	mov    0x54(%rdx),%eax
  6c1f7b:	85 c0                	test   %eax,%eax
  6c1f7d:	0f 85 a2 00 00 00    	jne    6c2025 <ostd::arch::irq::ops::enable_local+0xd5>
  6c1f83:	e8 08 59 01 00       	call   6d7890 <<ostd::irq::level::InterruptLevel>::current>
  6c1f88:	3c 02                	cmp    $0x2,%al
  6c1f8a:	0f 85 95 00 00 00    	jne    6c2025 <ostd::arch::irq::ops::enable_local+0xd5>
  6c1f90:	e8 ab 4d ff ff       	call   6b6d40 <ostd::task::virq_delivery_deferred>
  6c1f95:	84 c0                	test   %al,%al
  6c1f97:	0f 85 88 00 00 00    	jne    6c2025 <ostd::arch::irq::ops::enable_local+0xd5>
  6c1f9d:	48 8d 05 9c 86 37 00 	lea    0x37869c(%rip),%rax        # a3a640 <ostd::task::processor::CURRENT_TASK_PTR>
  6c1fa4:	48 2b 05 75 e0 33 00 	sub    0x33e075(%rip),%rax        # a00020 <_DYNAMIC+0x5fd78>
  6c1fab:	e9 c9 66 b7 ff       	jmp    238679 <__kernelet_cpu_access_start+0x38458>
  6c1fb0:	48 85 f6             	test   %rsi,%rsi
  6c1fb3:	74 70                	je     6c2025 <ostd::arch::irq::ops::enable_local+0xd5>
  6c1fb5:	48 8d 3d 1c cc 36 00 	lea    0x36cc1c(%rip),%rdi        # a2ebd8 <anon.b9a81f2eeec052eb13297414241e8ab2.33.llvm.7034704448355070909+0x18>
  6c1fbc:	e8 9f dd ff ff       	call   6bfd60 <ostd::task::scheduler::might_preempt>
  6c1fc1:	e9 e7 66 b7 ff       	jmp    2386ad <__kernelet_cpu_access_start+0x3848c>
  6c1fc6:	48 8b 02             	mov    (%rdx),%rax
  6c1fc9:	48 85 c0             	test   %rax,%rax
  6c1fcc:	74 57                	je     6c2025 <ostd::arch::irq::ops::enable_local+0xd5>
  6c1fce:	48 8b 05 3b e0 33 00 	mov    0x33e03b(%rip),%rax        # a00010 <_DYNAMIC+0x5fd68>
  6c1fd5:	48 8b 00             	mov    (%rax),%rax
  6c1fd8:	48 85 c0             	test   %rax,%rax
  6c1fdb:	74 4a                	je     6c2027 <ostd::arch::irq::ops::enable_local+0xd7>
  6c1fdd:	e9 fa 66 b7 ff       	jmp    2386dc <__kernelet_cpu_access_start+0x384bb>
  6c1fe2:	8b 4e 58             	mov    0x58(%rsi),%ecx
  6c1fe5:	8b 90 f0 08 00 00    	mov    0x8f0(%rax),%edx
  6c1feb:	0f b7 70 3a          	movzwl 0x3a(%rax),%esi
  6c1fef:	c1 e6 07             	shl    $0x7,%esi
  6c1ff2:	48 c1 e1 06          	shl    $0x6,%rcx
  6c1ff6:	48 01 c2             	add    %rax,%rdx
  6c1ff9:	48 01 f2             	add    %rsi,%rdx
  6c1ffc:	8b 44 11 10          	mov    0x10(%rcx,%rdx,1),%eax
  6c2000:	85 c0                	test   %eax,%eax
  6c2002:	75 21                	jne    6c2025 <ostd::arch::irq::ops::enable_local+0xd5>
  6c2004:	58                   	pop    %rax
  6c2005:	e9 46 f8 ff ff       	jmp    6c1850 <ostd::kernelet::entry::deliver_pending>
  6c200a:	48 8d 05 c7 86 37 00 	lea    0x3786c7(%rip),%rax        # a3a6d8 <ostd::task::preempt::cpu_local::PREEMPT_INFO>
  6c2011:	48 2b 05 08 e0 33 00 	sub    0x33e008(%rip),%rax        # a00020 <_DYNAMIC+0x5fd78>
  6c2018:	e9 ee 66 b7 ff       	jmp    23870b <__kernelet_cpu_access_start+0x384ea>
  6c201d:	85 f6                	test   %esi,%esi
  6c201f:	0f 84 3e ff ff ff    	je     6c1f63 <ostd::arch::irq::ops::enable_local+0x13>
  6c2025:	58                   	pop    %rax
  6c2026:	c3                   	ret
  6c2027:	48 8d 3d 2f 11 1a 00 	lea    0x1a112f(%rip),%rdi        # 86315d <anon.b9a81f2eeec052eb13297414241e8ab2.32.llvm.7034704448355070909>
  6c202e:	48 8d 15 8b cb 36 00 	lea    0x36cb8b(%rip),%rdx        # a2ebc0 <anon.b9a81f2eeec052eb13297414241e8ab2.33.llvm.7034704448355070909>
  6c2035:	be 4d 00 00 00       	mov    $0x4d,%esi
  6c203a:	e8 a1 77 fd ff       	call   6997e0 <core::panicking::panic_fmt>
