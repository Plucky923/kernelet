
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006ba8d0 <user_event_entry>:
  6ba8d0:	endbr64
  6ba8d4:	push   %rbp
  6ba8d5:	push   %r15
  6ba8d7:	push   %r14
  6ba8d9:	push   %r12
  6ba8db:	push   %rbx
  6ba8dc:	sub    $0xe0,%rsp
  6ba8e3:	mov    %rdi,0x10(%rsp)
  6ba8e8:	jmp    23774d <__kernelet_cpu_access_start+0x3752c>
  6ba8ed:	mov    0x34571c(%rip),%rcx        # a00010 <_DYNAMIC+0x601e8>
  6ba8f4:	mov    (%rcx),%rcx
  6ba8f7:	test   %rcx,%rcx
  6ba8fa:	je     6babe2 <user_event_entry+0x312>
  6ba900:	mov    0x58(%rdx),%esi
  6ba903:	mov    0x8f0(%rcx),%edi
  6ba909:	movzwl 0x3a(%rcx),%edx
  6ba90d:	lea    (%rdx,%rdx,2),%rdx
  6ba911:	shl    $0x6,%edx
  6ba914:	shl    $0x6,%rsi
  6ba918:	add    %rcx,%rdi
  6ba91b:	add    %rdx,%rdi
  6ba91e:	mov    (%rsi,%rdi,1),%rbx
  6ba922:	mov    $0xffffffffffffffff,%rcx
  6ba929:	mov    0x10(%rsp),%rdx
  6ba92e:	test   %rdx,%rdx
  6ba931:	je     6ba989 <user_event_entry+0xb9>
  6ba933:	cmp    $0x1,%rdx
  6ba937:	je     6ba94b <user_event_entry+0x7b>
  6ba939:	cmp    $0x2,%rdx
  6ba93d:	jne    6bac19 <user_event_entry+0x349>
  6ba943:	mov    $0x2,%bpl
  6ba946:	mov    $0x1,%r15b
  6ba949:	jmp    6ba98e <user_event_entry+0xbe>
  6ba94b:	mov    0x18(%rdi,%rsi,1),%rcx
  6ba950:	mov    0x20(%rdi,%rsi,1),%rdx
  6ba955:	mov    0x28(%rdi,%rsi,1),%rdi
  6ba95a:	mov    $0x1,%bpl
  6ba95d:	cmp    $0x1f,%rcx
  6ba961:	ja     6babaa <user_event_entry+0x2da>
  6ba967:	xor    %r15d,%r15d
  6ba96a:	lea    0x1a7ec7(%rip),%rsi        # 862838 <anon.d87aee44940f3bb572abe9e9cb01d6a2.8.llvm.2394514988628529432+0x302>
  6ba971:	movslq (%rsi,%rcx,4),%r8
  6ba975:	add    %rsi,%r8
  6ba978:	mov    %rdx,%rsi
  6ba97b:	notrack jmp *%r8
  6ba97f:	mov    $0x18,%ecx
  6ba984:	xor    %r15d,%r15d
  6ba987:	jmp    6ba949 <user_event_entry+0x79>
  6ba989:	xor    %r15d,%r15d
  6ba98c:	xor    %ebp,%ebp
  6ba98e:	lea    0x37fcab(%rip),%rdi        # a3a640 <ostd::task::processor::CURRENT_TASK_PTR>
  6ba995:	sub    0x345684(%rip),%rdi        # a00020 <_DYNAMIC+0x601f8>
  6ba99c:	mov    (%rax,%rdi,1),%rax
  6ba9a0:	test   %rax,%rax
  6ba9a3:	je     6babff <user_event_entry+0x32f>
  6ba9a9:	mov    0x60(%rax),%r14
  6ba9ad:	mov    %rax,0x8(%rsp)
  6ba9b2:	movq   $0x1,0x18(%rsp)
  6ba9bb:	mov    %rbx,0x20(%rsp)
  6ba9c0:	mov    %rcx,0xc8(%rsp)
  6ba9c8:	mov    %rsi,0xd0(%rsp)
  6ba9d0:	mov    %rdx,0xd8(%rsp)
  6ba9d8:	call   6be7c0 <ostd::arch::irq::ops::enable_local>
  6ba9dd:	test   %r15b,%r15b
  6ba9e0:	je     6ba9f7 <user_event_entry+0x127>
  6ba9e2:	mov    (%r14),%rdi
  6ba9e5:	add    $0x10,%rdi
  6ba9e9:	lea    0x8(%rsp),%rsi
  6ba9ee:	call   54ac40 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::has_kernel_event>
  6ba9f3:	test   %al,%al
  6ba9f5:	je     6baa11 <user_event_entry+0x141>
  6ba9f7:	mov    (%r14),%rdi
  6ba9fa:	add    $0x10,%rdi
  6ba9fe:	movzbl %bpl,%edx
  6baa02:	lea    0x8(%rsp),%rsi
  6baa07:	lea    0x18(%rsp),%rcx
  6baa0c:	call   54b2a0 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle>
  6baa11:	mov    (%r14),%rdi
  6baa14:	add    $0x10,%rdi
  6baa18:	lea    0x8(%rsp),%rsi
  6baa1d:	call   54ab60 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::should_exit>
  6baa22:	test   %al,%al
  6baa24:	je     6baa30 <user_event_entry+0x160>
  6baa26:	call   6b34a0 <ostd::task::exit_current_task>
  6baa2b:	jmp    6bac98 <user_event_entry+0x3c8>
  6baa30:	jmp    237780 <__kernelet_cpu_access_start+0x3755f>
  6baa35:	mov    0x50(%rdx),%eax
  6baa38:	mov    %eax,0x4(%rsp)
  6baa3c:	test   %eax,%eax
  6baa3e:	jne    6bac49 <user_event_entry+0x379>
  6baa44:	lea    0x373cf5(%rip),%rdi        # a2e740 <anon.4e67789babc3ff0b30a8506a73b6620c.22.llvm.8985484055589539988+0x48>
  6baa4b:	call   6bc580 <ostd::task::scheduler::might_preempt>
  6baa50:	jmp    2377af <__kernelet_cpu_access_start+0x3758e>
  6baa55:	test   %edx,%edx
  6baa57:	sete   0x4(%rsp)
  6baa5c:	cmpb   $0x0,0x18(%rsp)
  6baa61:	jne    6baac5 <user_event_entry+0x1f5>
  6baa63:	lea    0x20(%rsp),%rsi
  6baa68:	mov    0xb0(%rsp),%r15
  6baa70:	mov    0xb8(%rsp),%r12
  6baa78:	and    $0x240dd5,%r15d
  6baa7f:	or     $0x202,%r15
  6baa86:	mov    $0x88,%edx
  6baa8b:	mov    %rbx,%rdi
  6baa8e:	call   6e4a80 <memcpy>
  6baa93:	movq   $0x33,0x88(%rbx)
  6baa9e:	mov    %r15,0x90(%rbx)
  6baaa5:	mov    %r12,0x98(%rbx)
  6baaac:	movq   $0x2b,0xa0(%rbx)
  6baab7:	movq   $0x1,0x18(%rsp)
  6baac0:	mov    %rbx,0x20(%rsp)
  6baac5:	lea    0x8(%rsp),%rsi
  6baaca:	lea    0x4(%rsp),%rdx
  6baacf:	mov    %r14,%rdi
  6baad2:	call   550ec0 <__ostd_user_pre_user_run>
  6baad7:	mov    0x34555a(%rip),%rax        # a00038 <_DYNAMIC+0x60210>
  6baade:	mov    (%rax),%rax
  6baae1:	test   %rax,%rax
  6baae4:	je     6bac72 <user_event_entry+0x3a2>
  6baaea:	xor    %edi,%edi
  6baaec:	call   *0x68(%rax)
  6baaef:	lea    0x1a7f08(%rip),%rdi        # 8629fe <anon.4e67789babc3ff0b30a8506a73b6620c.26.llvm.8985484055589539988+0x17>
  6baaf6:	lea    0x373c5b(%rip),%rdx        # a2e758 <anon.4e67789babc3ff0b30a8506a73b6620c.22.llvm.8985484055589539988+0x60>
  6baafd:	mov    $0xb3,%esi
  6bab02:	call   696030 <core::panicking::panic_fmt>
  6bab07:	jmp    6bac98 <user_event_entry+0x3c8>
  6bab0c:	mov    $0x10,%ecx
  6bab11:	xor    %r15d,%r15d
  6bab14:	jmp    6ba949 <user_event_entry+0x79>
  6bab19:	mov    $0x13,%ecx
  6bab1e:	xor    %r15d,%r15d
  6bab21:	jmp    6ba949 <user_event_entry+0x79>
  6bab26:	mov    $0x17,%ecx
  6bab2b:	xor    %r15d,%r15d
  6bab2e:	jmp    6ba949 <user_event_entry+0x79>
  6bab33:	mov    $0x15,%ecx
  6bab38:	xor    %r15d,%r15d
  6bab3b:	jmp    6ba949 <user_event_entry+0x79>
  6bab40:	mov    $0x14,%ecx
  6bab45:	xor    %r15d,%r15d
  6bab48:	jmp    6ba949 <user_event_entry+0x79>
  6bab4d:	mov    $0x11,%ecx
  6bab52:	xor    %r15d,%r15d
  6bab55:	jmp    6ba949 <user_event_entry+0x79>
  6bab5a:	mov    $0x16,%ecx
  6bab5f:	xor    %r15d,%r15d
  6bab62:	jmp    6ba949 <user_event_entry+0x79>
  6bab67:	xor    %esi,%esi
  6bab69:	test   %rdx,%rdx
  6bab6c:	setne  %sil
  6bab70:	mov    $0xd,%ecx
  6bab75:	xor    %r15d,%r15d
  6bab78:	jmp    6ba98e <user_event_entry+0xbe>
  6bab7d:	mov    $0xf,%ecx
  6bab82:	xor    %r15d,%r15d
  6bab85:	jmp    6ba949 <user_event_entry+0x79>
  6bab8a:	test   $0xffffffffffff7f00,%rdx
  6bab91:	jne    6bac8c <user_event_entry+0x3bc>
  6bab97:	mov    $0xe,%ecx
  6bab9c:	xor    %r15d,%r15d
  6bab9f:	mov    %rdx,%rsi
  6baba2:	mov    %rdi,%rdx
  6baba5:	jmp    6ba98e <user_event_entry+0xbe>
  6babaa:	add    $0xffffffffffffffea,%rcx
  6babae:	cmp    $0x6,%rcx
  6babb2:	jb     6ba97f <user_event_entry+0xaf>
  6babb8:	lea    0x1a7dc7(%rip),%rdi        # 862986 <anon.4e67789babc3ff0b30a8506a73b6620c.10.llvm.8985484055589539988+0x4c>
  6babbf:	lea    0x373afa(%rip),%rdx        # a2e6c0 <anon.4e67789babc3ff0b30a8506a73b6620c.11.llvm.8985484055589539988+0x18>
  6babc6:	mov    $0x36,%esi
  6babcb:	call   693c80 <core::option::expect_failed>
  6babd0:	jmp    6bac98 <user_event_entry+0x3c8>
  6babd5:	mov    $0x12,%ecx
  6babda:	xor    %r15d,%r15d
  6babdd:	jmp    6ba949 <user_event_entry+0x79>
  6babe2:	lea    0x1a8474(%rip),%rdi        # 86305d <anon.640ee05cbc79ee72d993a22be3c2086a.32.llvm.10029247957258186659>
  6babe9:	lea    0x373fd8(%rip),%rdx        # a2ebc8 <anon.640ee05cbc79ee72d993a22be3c2086a.33.llvm.10029247957258186659>
  6babf0:	mov    $0x4d,%esi
  6babf5:	call   696030 <core::panicking::panic_fmt>
  6babfa:	jmp    6bac98 <user_event_entry+0x3c8>
  6babff:	lea    0x1a807d(%rip),%rdi        # 862c83 <anon.4e67789babc3ff0b30a8506a73b6620c.46.llvm.8985484055589539988+0x5b>
  6bac06:	lea    0x373c73(%rip),%rdx        # a2e880 <anon.4e67789babc3ff0b30a8506a73b6620c.49.llvm.8985484055589539988+0x50>
  6bac0d:	mov    $0x28,%esi
  6bac12:	call   693c80 <core::option::expect_failed>
  6bac17:	jmp    6bac98 <user_event_entry+0x3c8>
  6bac19:	lea    0x10(%rsp),%rax
  6bac1e:	mov    %rax,0x18(%rsp)
  6bac23:	mov    0x345436(%rip),%rax        # a00060 <_DYNAMIC+0x60238>
  6bac2a:	mov    %rax,0x20(%rsp)
  6bac2f:	lea    0x1477bb(%rip),%rdi        # 8023f1 <anon.a6f7c60b6370fba0a14341d270c3bcdd.24.llvm.4110714919376948433+0x1c2>
  6bac36:	lea    0x373c5b(%rip),%rdx        # a2e898 <anon.4e67789babc3ff0b30a8506a73b6620c.49.llvm.8985484055589539988+0x68>
  6bac3d:	lea    0x18(%rsp),%rsi
  6bac42:	call   696030 <core::panicking::panic_fmt>
  6bac47:	jmp    6bac98 <user_event_entry+0x3c8>
  6bac49:	lea    0x167b7c(%rip),%rdx        # 8227cc <anon.150ac8731568b04a4890e94e4f771633.67.llvm.17063130079879217559>
  6bac50:	lea    0x1a7e00(%rip),%rcx        # 862a57 <anon.4e67789babc3ff0b30a8506a73b6620c.26.llvm.8985484055589539988+0x70>
  6bac57:	lea    0x373b12(%rip),%r9        # a2e770 <anon.4e67789babc3ff0b30a8506a73b6620c.22.llvm.8985484055589539988+0x78>
  6bac5e:	lea    0x4(%rsp),%rsi
  6bac63:	mov    $0x67,%r8d
  6bac69:	xor    %edi,%edi
  6bac6b:	call   6d07cd <core::panicking::assert_failed::<u32, u32>>
  6bac70:	jmp    6bac98 <user_event_entry+0x3c8>
  6bac72:	lea    0x1a83bb(%rip),%rdi        # 863034 <anon.640ee05cbc79ee72d993a22be3c2086a.30.llvm.10029247957258186659>
  6bac79:	lea    0x373f30(%rip),%rdx        # a2ebb0 <anon.640ee05cbc79ee72d993a22be3c2086a.31.llvm.10029247957258186659>
  6bac80:	mov    $0x53,%esi
  6bac85:	call   696030 <core::panicking::panic_fmt>
  6bac8a:	jmp    6bac98 <user_event_entry+0x3c8>
  6bac8c:	lea    0x3742b5(%rip),%rdi        # a2ef48 <anon.943e0da6b7cc193d71c9d7a687b5b7dd.15.llvm.1248439088975708565>
  6bac93:	call   693cc0 <core::option::unwrap_failed>
  6bac98:	ud2
  6bac9a:	endbr64
  6bac9e:	xor    %edi,%edi
  6baca0:	call   6b8920 <core::ptr::drop_glue::<ostd::irq::guard::DisabledLocalIrqGuard>>
  6baca5:	jmp    6bacbe <user_event_entry+0x3ee>
  6baca7:	endbr64
  6bacab:	call   695e3b <core::panicking::panic_in_cleanup>
  6bacb0:	endbr64
  6bacb4:	lea    0x4(%rsp),%rdi
  6bacb9:	call   6d4ed0 <<ostd::irq::guard::DisabledLocalIrqGuard as core::ops::drop::Drop>::drop>
  6bacbe:	call   695fcf <core::panicking::panic_cannot_unwind>
  6bacc3:	endbr64
  6bacc7:	call   695e3b <core::panicking::panic_in_cleanup>
  6baccc:	endbr64
  6bacd0:	call   695fcf <core::panicking::panic_cannot_unwind>
