
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006ba660 <first_user_task_entry>:
  6ba660:	endbr64
  6ba664:	push   %rbp
  6ba665:	push   %r15
  6ba667:	push   %r14
  6ba669:	push   %r12
  6ba66b:	push   %rbx
  6ba66c:	sub    $0xe0,%rsp
  6ba673:	call   6b38e0 <ostd::task::processor::after_switching_to>
  6ba678:	jmp    237677 <__kernelet_cpu_access_start+0x37456>
  6ba67d:	xor    %ebx,%ebx
  6ba67f:	test   %eax,%eax
  6ba681:	sete   %bpl
  6ba685:	jmp    2376b1 <__kernelet_cpu_access_start+0x37490>
  6ba68a:	lea    0x37ffaf(%rip),%rcx        # a3a640 <ostd::task::processor::CURRENT_TASK_PTR>
  6ba691:	sub    0x345988(%rip),%rcx        # a00020 <_DYNAMIC+0x601f8>
  6ba698:	mov    (%rdi,%rcx,1),%r14
  6ba69c:	test   %r14,%r14
  6ba69f:	je     6ba810 <first_user_task_entry+0x1b0>
  6ba6a5:	mov    0x345964(%rip),%rcx        # a00010 <_DYNAMIC+0x601e8>
  6ba6ac:	mov    (%rcx),%rcx
  6ba6af:	test   %rcx,%rcx
  6ba6b2:	je     6ba82a <first_user_task_entry+0x1ca>
  6ba6b8:	mov    0x58(%rdx),%edx
  6ba6bb:	mov    0x8f0(%rcx),%esi
  6ba6c1:	movzwl 0x3a(%rcx),%edi
  6ba6c5:	lea    (%rdi,%rdi,2),%rdi
  6ba6c9:	shl    $0x6,%edi
  6ba6cc:	shl    $0x6,%rdx
  6ba6d0:	add    %rcx,%rsi
  6ba6d3:	add    %rdi,%rsi
  6ba6d6:	mov    (%rdx,%rsi,1),%rbx
  6ba6da:	test   %eax,%eax
  6ba6dc:	jne    6ba6e3 <first_user_task_entry+0x83>
  6ba6de:	call   6be7c0 <ostd::arch::irq::ops::enable_local>
  6ba6e3:	mov    %r14,0x10(%rsp)
  6ba6e8:	mov    0x60(%r14),%r14
  6ba6ec:	movq   $0x1,0x18(%rsp)
  6ba6f5:	mov    %rbx,0x20(%rsp)
  6ba6fa:	movq   $0xffffffffffffffff,0xc8(%rsp)
  6ba706:	mov    (%r14),%rdi
  6ba709:	add    $0x10,%rdi
  6ba70d:	lea    0x10(%rsp),%rsi
  6ba712:	lea    0x18(%rsp),%rdx
  6ba717:	call   54ad60 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::init>
  6ba71c:	mov    (%r14),%rdi
  6ba71f:	add    $0x10,%rdi
  6ba723:	lea    0x10(%rsp),%rsi
  6ba728:	call   54ab60 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::should_exit>
  6ba72d:	test   %al,%al
  6ba72f:	je     6ba73b <first_user_task_entry+0xdb>
  6ba731:	call   6b34a0 <ostd::task::exit_current_task>
  6ba736:	jmp    6ba885 <first_user_task_entry+0x225>
  6ba73b:	jmp    2376e4 <__kernelet_cpu_access_start+0x374c3>
  6ba740:	mov    0x50(%rdx),%eax
  6ba743:	mov    %eax,0xc(%rsp)
  6ba747:	test   %eax,%eax
  6ba749:	jne    6ba844 <first_user_task_entry+0x1e4>
  6ba74f:	lea    0x373fea(%rip),%rdi        # a2e740 <anon.4e67789babc3ff0b30a8506a73b6620c.22.llvm.8985484055589539988+0x48>
  6ba756:	call   6bc580 <ostd::task::scheduler::might_preempt>
  6ba75b:	jmp    237713 <__kernelet_cpu_access_start+0x374f2>
  6ba760:	test   %edx,%edx
  6ba762:	sete   0xc(%rsp)
  6ba767:	cmpb   $0x0,0x18(%rsp)
  6ba76c:	jne    6ba7d0 <first_user_task_entry+0x170>
  6ba76e:	lea    0x20(%rsp),%rsi
  6ba773:	mov    0xb0(%rsp),%r15
  6ba77b:	mov    0xb8(%rsp),%r12
  6ba783:	and    $0x240dd5,%r15d
  6ba78a:	or     $0x202,%r15
  6ba791:	mov    $0x88,%edx
  6ba796:	mov    %rbx,%rdi
  6ba799:	call   6e4a80 <memcpy>
  6ba79e:	movq   $0x33,0x88(%rbx)
  6ba7a9:	mov    %r15,0x90(%rbx)
  6ba7b0:	mov    %r12,0x98(%rbx)
  6ba7b7:	movq   $0x2b,0xa0(%rbx)
  6ba7c2:	movq   $0x1,0x18(%rsp)
  6ba7cb:	mov    %rbx,0x20(%rsp)
  6ba7d0:	lea    0x10(%rsp),%rsi
  6ba7d5:	lea    0xc(%rsp),%rdx
  6ba7da:	mov    %r14,%rdi
  6ba7dd:	call   550ec0 <__ostd_user_pre_user_run>
  6ba7e2:	mov    0x34584f(%rip),%rax        # a00038 <_DYNAMIC+0x60210>
  6ba7e9:	mov    (%rax),%rax
  6ba7ec:	test   %rax,%rax
  6ba7ef:	je     6ba86d <first_user_task_entry+0x20d>
  6ba7f1:	xor    %edi,%edi
  6ba7f3:	call   *0x68(%rax)
  6ba7f6:	lea    0x1a8201(%rip),%rdi        # 8629fe <anon.4e67789babc3ff0b30a8506a73b6620c.26.llvm.8985484055589539988+0x17>
  6ba7fd:	lea    0x373f54(%rip),%rdx        # a2e758 <anon.4e67789babc3ff0b30a8506a73b6620c.22.llvm.8985484055589539988+0x60>
  6ba804:	mov    $0xb3,%esi
  6ba809:	call   696030 <core::panicking::panic_fmt>
  6ba80e:	jmp    6ba885 <first_user_task_entry+0x225>
  6ba810:	lea    0x1a843f(%rip),%rdi        # 862c56 <anon.4e67789babc3ff0b30a8506a73b6620c.46.llvm.8985484055589539988+0x2e>
  6ba817:	lea    0x37404a(%rip),%rdx        # a2e868 <anon.4e67789babc3ff0b30a8506a73b6620c.49.llvm.8985484055589539988+0x38>
  6ba81e:	mov    $0x2d,%esi
  6ba823:	call   693c80 <core::option::expect_failed>
  6ba828:	jmp    6ba885 <first_user_task_entry+0x225>
  6ba82a:	lea    0x1a882c(%rip),%rdi        # 86305d <anon.640ee05cbc79ee72d993a22be3c2086a.32.llvm.10029247957258186659>
  6ba831:	lea    0x374390(%rip),%rdx        # a2ebc8 <anon.640ee05cbc79ee72d993a22be3c2086a.33.llvm.10029247957258186659>
  6ba838:	mov    $0x4d,%esi
  6ba83d:	call   696030 <core::panicking::panic_fmt>
  6ba842:	jmp    6ba885 <first_user_task_entry+0x225>
  6ba844:	lea    0x167f81(%rip),%rdx        # 8227cc <anon.150ac8731568b04a4890e94e4f771633.67.llvm.17063130079879217559>
  6ba84b:	lea    0x1a8205(%rip),%rcx        # 862a57 <anon.4e67789babc3ff0b30a8506a73b6620c.26.llvm.8985484055589539988+0x70>
  6ba852:	lea    0x373f17(%rip),%r9        # a2e770 <anon.4e67789babc3ff0b30a8506a73b6620c.22.llvm.8985484055589539988+0x78>
  6ba859:	lea    0xc(%rsp),%rsi
  6ba85e:	mov    $0x67,%r8d
  6ba864:	xor    %edi,%edi
  6ba866:	call   6d07cd <core::panicking::assert_failed::<u32, u32>>
  6ba86b:	jmp    6ba885 <first_user_task_entry+0x225>
  6ba86d:	lea    0x1a87c0(%rip),%rdi        # 863034 <anon.640ee05cbc79ee72d993a22be3c2086a.30.llvm.10029247957258186659>
  6ba874:	lea    0x374335(%rip),%rdx        # a2ebb0 <anon.640ee05cbc79ee72d993a22be3c2086a.31.llvm.10029247957258186659>
  6ba87b:	mov    $0x53,%esi
  6ba880:	call   696030 <core::panicking::panic_fmt>
  6ba885:	ud2
  6ba887:	endbr64
  6ba88b:	mov    %bpl,%bl
  6ba88e:	mov    %ebx,%edi
  6ba890:	call   6b8920 <core::ptr::drop_glue::<ostd::irq::guard::DisabledLocalIrqGuard>>
  6ba895:	jmp    6ba8ae <first_user_task_entry+0x24e>
  6ba897:	endbr64
  6ba89b:	call   695e3b <core::panicking::panic_in_cleanup>
  6ba8a0:	endbr64
  6ba8a4:	lea    0xc(%rsp),%rdi
  6ba8a9:	call   6d4ed0 <<ostd::irq::guard::DisabledLocalIrqGuard as core::ops::drop::Drop>::drop>
  6ba8ae:	call   695fcf <core::panicking::panic_cannot_unwind>
  6ba8b3:	endbr64
  6ba8b7:	call   695e3b <core::panicking::panic_in_cleanup>
  6ba8bc:	endbr64
  6ba8c0:	call   695fcf <core::panicking::panic_cannot_unwind>
  6ba8c5:	endbr64
  6ba8c9:	call   695fcf <core::panicking::panic_cannot_unwind>
