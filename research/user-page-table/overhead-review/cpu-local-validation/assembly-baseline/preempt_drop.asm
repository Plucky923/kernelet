
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006cedb0 <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop>:
  6cedb0:	f3 0f 1e fa          	endbr64
  6cedb4:	55                   	push   %rbp
  6cedb5:	53                   	push   %rbx
  6cedb6:	50                   	push   %rax
  6cedb7:	e9 c7 2d b7 ff       	jmp    241b83 <__kernelet_cpu_access_start+0x41962>
  6cedbc:	85 ed                	test   %ebp,%ebp
  6cedbe:	75 0a                	jne    6cedca <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0x1a>
  6cedc0:	b8 01 00 00 00       	mov    $0x1,%eax
  6cedc5:	e9 e8 2d b7 ff       	jmp    241bb2 <__kernelet_cpu_access_start+0x41991>
  6cedca:	48 8d 05 83 b8 36 00 	lea    0x36b883(%rip),%rax        # a3a654 <ostd::task::preempt::cpu_local::PREEMPT_INFO>
  6cedd1:	48 2b 05 48 12 33 00 	sub    0x331248(%rip),%rax        # a00020 <_DYNAMIC+0x5ee40>
  6cedd8:	b9 01 00 00 00       	mov    $0x1,%ecx
  6ceddd:	e9 ff 2d b7 ff       	jmp    241be1 <__kernelet_cpu_access_start+0x419c0>
  6cede2:	e8 e9 97 ff ff       	call   6c85d0 <ostd::kernelet::entry::leave_preempt_guard>
  6cede7:	48 83 c4 08          	add    $0x8,%rsp
  6cedeb:	85 ed                	test   %ebp,%ebp
  6ceded:	74 03                	je     6cedf2 <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0x42>
  6cedef:	5b                   	pop    %rbx
  6cedf0:	5d                   	pop    %rbp
  6cedf1:	c3                   	ret
  6cedf2:	5b                   	pop    %rbx
  6cedf3:	5d                   	pop    %rbp
  6cedf4:	e9 37 9c ff ff       	jmp    6c8a30 <ostd::arch::irq::ops::enable_local>
  6cedf9:	f3 0f 1e fa          	endbr64
  6cedfd:	48 89 c3             	mov    %rax,%rbx
  6cee00:	85 ed                	test   %ebp,%ebp
  6cee02:	75 05                	jne    6cee09 <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0x59>
  6cee04:	e8 27 9c ff ff       	call   6c8a30 <ostd::arch::irq::ops::enable_local>
  6cee09:	48 89 df             	mov    %rbx,%rdi
  6cee0c:	e8 0f 80 02 00       	call   6f6e20 <_Unwind_Resume>
  6cee11:	f3 0f 1e fa          	endbr64
  6cee15:	e8 e1 9b fd ff       	call   6a89fb <core::panicking::panic_in_cleanup>
