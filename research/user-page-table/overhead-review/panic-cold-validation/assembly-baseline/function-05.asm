
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-baseline.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006bd920 <first_user_task_entry>:
  6bd920:	endbr64
  6bd924:	push   %rbp
  6bd925:	push   %r15
  6bd927:	push   %r14
  6bd929:	push   %r12
  6bd92b:	push   %rbx
  6bd92c:	sub    $0xe0,%rsp
  6bd933:	call   6b6c20 <ostd::task::processor::after_switching_to>
  6bd938:	jmp    237610 <__kernelet_cpu_access_start+0x373ef>
  6bd93d:	xor    %ebx,%ebx
  6bd93f:	test   %eax,%eax
  6bd941:	sete   %bpl
  6bd945:	jmp    23764a <__kernelet_cpu_access_start+0x37429>
  6bd94a:	lea    0x37ccef(%rip),%rcx        # a3a640 <ostd::task::processor::CURRENT_TASK_PTR>
  6bd951:	sub    0x3426c8(%rip),%rcx        # a00020 <_DYNAMIC+0x5fe38>
  6bd958:	mov    (%rdi,%rcx,1),%r14
  6bd95c:	test   %r14,%r14
  6bd95f:	je     6bdacc <first_user_task_entry+0x1ac>
  6bd965:	mov    0x3426a4(%rip),%rcx        # a00010 <_DYNAMIC+0x5fe28>
  6bd96c:	mov    (%rcx),%rcx
  6bd96f:	test   %rcx,%rcx
  6bd972:	je     6bdae6 <first_user_task_entry+0x1c6>
  6bd978:	mov    0x58(%rdx),%edx
  6bd97b:	mov    0x8f0(%rcx),%esi
  6bd981:	movzwl 0x3a(%rcx),%edi
  6bd985:	lea    (%rdi,%rdi,2),%rdi
  6bd989:	shl    $0x6,%edi
  6bd98c:	shl    $0x6,%rdx
  6bd990:	add    %rcx,%rsi
  6bd993:	add    %rdi,%rsi
  6bd996:	mov    (%rdx,%rsi,1),%rbx
  6bd99a:	test   %eax,%eax
  6bd99c:	jne    6bd9a3 <first_user_task_entry+0x83>
  6bd99e:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  6bd9a3:	mov    %r14,0x10(%rsp)
  6bd9a8:	mov    0x60(%r14),%r14
  6bd9ac:	movq   $0x1,0x18(%rsp)
  6bd9b5:	mov    %rbx,0x20(%rsp)
  6bd9ba:	movq   $0xffffffffffffffff,0xc8(%rsp)
  6bd9c6:	lea    0x10(%rsp),%rsi
  6bd9cb:	lea    0x18(%rsp),%rdx
  6bd9d0:	mov    %r14,%rdi
  6bd9d3:	call   4a7d50 <__ostd_user_init>
  6bd9d8:	mov    (%r14),%rdi
  6bd9db:	add    $0x10,%rdi
  6bd9df:	lea    0x10(%rsp),%rsi
  6bd9e4:	call   4a2940 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::should_exit>
  6bd9e9:	test   %al,%al
  6bd9eb:	je     6bd9f7 <first_user_task_entry+0xd7>
  6bd9ed:	call   6b6860 <ostd::task::exit_current_task>
  6bd9f2:	jmp    6bdb41 <first_user_task_entry+0x221>
  6bd9f7:	jmp    23767d <__kernelet_cpu_access_start+0x3745c>
  6bd9fc:	mov    0x50(%rdx),%eax
  6bd9ff:	mov    %eax,0xc(%rsp)
  6bda03:	test   %eax,%eax
  6bda05:	jne    6bdb00 <first_user_task_entry+0x1e0>
  6bda0b:	lea    0x370d26(%rip),%rdi        # a2e738 <anon.c1331c03898317998489fbaca113e814.22.llvm.15286295260971784537+0x48>
  6bda12:	call   6bf700 <ostd::task::scheduler::might_preempt>
  6bda17:	jmp    2376ac <__kernelet_cpu_access_start+0x3748b>
  6bda1c:	test   %edx,%edx
  6bda1e:	sete   0xc(%rsp)
  6bda23:	cmpb   $0x0,0x18(%rsp)
  6bda28:	jne    6bda8c <first_user_task_entry+0x16c>
  6bda2a:	lea    0x20(%rsp),%rsi
  6bda2f:	mov    0xb0(%rsp),%r15
  6bda37:	mov    0xb8(%rsp),%r12
  6bda3f:	and    $0x240dd5,%r15d
  6bda46:	or     $0x202,%r15
  6bda4d:	mov    $0x88,%edx
  6bda52:	mov    %rbx,%rdi
  6bda55:	call   6e77d0 <memcpy>
  6bda5a:	movq   $0x33,0x88(%rbx)
  6bda65:	mov    %r15,0x90(%rbx)
  6bda6c:	mov    %r12,0x98(%rbx)
  6bda73:	movq   $0x2b,0xa0(%rbx)
  6bda7e:	movq   $0x1,0x18(%rsp)
  6bda87:	mov    %rbx,0x20(%rsp)
  6bda8c:	lea    0x10(%rsp),%rsi
  6bda91:	lea    0xc(%rsp),%rdx
  6bda96:	mov    %r14,%rdi
  6bda99:	call   4a7e00 <__ostd_user_pre_user_run>
  6bda9e:	mov    0x342593(%rip),%rax        # a00038 <_DYNAMIC+0x5fe50>
  6bdaa5:	mov    (%rax),%rax
  6bdaa8:	test   %rax,%rax
  6bdaab:	je     6bdb29 <first_user_task_entry+0x209>
  6bdaad:	xor    %edi,%edi
  6bdaaf:	call   *0x68(%rax)
  6bdab2:	lea    0x1a503d(%rip),%rdi        # 862af6 <anon.c1331c03898317998489fbaca113e814.26.llvm.15286295260971784537+0x17>
  6bdab9:	lea    0x370c90(%rip),%rdx        # a2e750 <anon.c1331c03898317998489fbaca113e814.22.llvm.15286295260971784537+0x60>
  6bdac0:	mov    $0xb3,%esi
  6bdac5:	call   6993b0 <core::panicking::panic_fmt>
  6bdaca:	jmp    6bdb41 <first_user_task_entry+0x221>
  6bdacc:	lea    0x1a527b(%rip),%rdi        # 862d4e <anon.c1331c03898317998489fbaca113e814.46.llvm.15286295260971784537+0x2e>
  6bdad3:	lea    0x370d86(%rip),%rdx        # a2e860 <anon.c1331c03898317998489fbaca113e814.49.llvm.15286295260971784537+0x38>
  6bdada:	mov    $0x2d,%esi
  6bdadf:	call   697000 <core::option::expect_failed>
  6bdae4:	jmp    6bdb41 <first_user_task_entry+0x221>
  6bdae6:	lea    0x1a5668(%rip),%rdi        # 863155 <anon.afbcb67d570395342e5c7b93cc9f14b2.32.llvm.5541347225946096535>
  6bdaed:	lea    0x3710cc(%rip),%rdx        # a2ebc0 <anon.afbcb67d570395342e5c7b93cc9f14b2.33.llvm.5541347225946096535>
  6bdaf4:	mov    $0x4d,%esi
  6bdaf9:	call   6993b0 <core::panicking::panic_fmt>
  6bdafe:	jmp    6bdb41 <first_user_task_entry+0x221>
  6bdb00:	lea    0x164cc9(%rip),%rdx        # 8227d0 <anon.2503ed91df35c83fb86cc1a1f9db1e4e.67.llvm.15712373746005169545>
  6bdb07:	lea    0x1a5041(%rip),%rcx        # 862b4f <anon.c1331c03898317998489fbaca113e814.26.llvm.15286295260971784537+0x70>
  6bdb0e:	lea    0x370c53(%rip),%r9        # a2e768 <anon.c1331c03898317998489fbaca113e814.22.llvm.15286295260971784537+0x78>
  6bdb15:	lea    0xc(%rsp),%rsi
  6bdb1a:	mov    $0x67,%r8d
  6bdb20:	xor    %edi,%edi
  6bdb22:	call   6d137a <core::panicking::assert_failed::<u32, u32>>
  6bdb27:	jmp    6bdb41 <first_user_task_entry+0x221>
  6bdb29:	lea    0x1a55fc(%rip),%rdi        # 86312c <anon.afbcb67d570395342e5c7b93cc9f14b2.30.llvm.5541347225946096535>
  6bdb30:	lea    0x371071(%rip),%rdx        # a2eba8 <anon.afbcb67d570395342e5c7b93cc9f14b2.31.llvm.5541347225946096535>
  6bdb37:	mov    $0x53,%esi
  6bdb3c:	call   6993b0 <core::panicking::panic_fmt>
  6bdb41:	ud2
  6bdb43:	endbr64
  6bdb47:	mov    %bpl,%bl
  6bdb4a:	mov    %ebx,%edi
  6bdb4c:	call   6bbc60 <core::ptr::drop_glue::<ostd::irq::guard::DisabledLocalIrqGuard>>
  6bdb51:	jmp    6bdb6a <first_user_task_entry+0x24a>
  6bdb53:	endbr64
  6bdb57:	call   6991bb <core::panicking::panic_in_cleanup>
  6bdb5c:	endbr64
  6bdb60:	lea    0xc(%rsp),%rdi
  6bdb65:	call   6cfd70 <<ostd::irq::guard::DisabledLocalIrqGuard as core::ops::drop::Drop>::drop>
  6bdb6a:	call   69934f <core::panicking::panic_cannot_unwind>
  6bdb6f:	endbr64
  6bdb73:	call   6991bb <core::panicking::panic_in_cleanup>
  6bdb78:	endbr64
  6bdb7c:	call   69934f <core::panicking::panic_cannot_unwind>
  6bdb81:	endbr64
  6bdb85:	call   69934f <core::panicking::panic_cannot_unwind>
