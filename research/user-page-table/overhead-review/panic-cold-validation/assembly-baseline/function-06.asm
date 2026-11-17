
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-baseline.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006bdb90 <user_event_entry>:
  6bdb90:	endbr64
  6bdb94:	push   %rbp
  6bdb95:	push   %r15
  6bdb97:	push   %r14
  6bdb99:	push   %r12
  6bdb9b:	push   %rbx
  6bdb9c:	sub    $0xe0,%rsp
  6bdba3:	mov    %rdi,0x10(%rsp)
  6bdba8:	jmp    2376e6 <__kernelet_cpu_access_start+0x374c5>
  6bdbad:	mov    0x34245c(%rip),%rcx        # a00010 <_DYNAMIC+0x5fe28>
  6bdbb4:	mov    (%rcx),%rcx
  6bdbb7:	test   %rcx,%rcx
  6bdbba:	je     6bde9e <user_event_entry+0x30e>
  6bdbc0:	mov    0x58(%rdx),%esi
  6bdbc3:	mov    0x8f0(%rcx),%edi
  6bdbc9:	movzwl 0x3a(%rcx),%edx
  6bdbcd:	lea    (%rdx,%rdx,2),%rdx
  6bdbd1:	shl    $0x6,%edx
  6bdbd4:	shl    $0x6,%rsi
  6bdbd8:	add    %rcx,%rdi
  6bdbdb:	add    %rdx,%rdi
  6bdbde:	mov    (%rsi,%rdi,1),%rbx
  6bdbe2:	mov    $0xffffffffffffffff,%rcx
  6bdbe9:	mov    0x10(%rsp),%rdx
  6bdbee:	test   %rdx,%rdx
  6bdbf1:	je     6bdc49 <user_event_entry+0xb9>
  6bdbf3:	cmp    $0x1,%rdx
  6bdbf7:	je     6bdc0b <user_event_entry+0x7b>
  6bdbf9:	cmp    $0x2,%rdx
  6bdbfd:	jne    6bded5 <user_event_entry+0x345>
  6bdc03:	mov    $0x2,%bpl
  6bdc06:	mov    $0x1,%r15b
  6bdc09:	jmp    6bdc4e <user_event_entry+0xbe>
  6bdc0b:	mov    0x18(%rdi,%rsi,1),%rcx
  6bdc10:	mov    0x20(%rdi,%rsi,1),%rdx
  6bdc15:	mov    0x28(%rdi,%rsi,1),%rdi
  6bdc1a:	mov    $0x1,%bpl
  6bdc1d:	cmp    $0x1f,%rcx
  6bdc21:	ja     6bde66 <user_event_entry+0x2d6>
  6bdc27:	xor    %r15d,%r15d
  6bdc2a:	lea    0x1a4cff(%rip),%rsi        # 862930 <anon.3ce79d8b73e4aac7fbd5c148d6020a01.8.llvm.13348157067858502311+0x302>
  6bdc31:	movslq (%rsi,%rcx,4),%r8
  6bdc35:	add    %rsi,%r8
  6bdc38:	mov    %rdx,%rsi
  6bdc3b:	notrack jmp *%r8
  6bdc3f:	mov    $0x18,%ecx
  6bdc44:	xor    %r15d,%r15d
  6bdc47:	jmp    6bdc09 <user_event_entry+0x79>
  6bdc49:	xor    %r15d,%r15d
  6bdc4c:	xor    %ebp,%ebp
  6bdc4e:	lea    0x37c9eb(%rip),%rdi        # a3a640 <ostd::task::processor::CURRENT_TASK_PTR>
  6bdc55:	sub    0x3423c4(%rip),%rdi        # a00020 <_DYNAMIC+0x5fe38>
  6bdc5c:	mov    (%rax,%rdi,1),%rax
  6bdc60:	test   %rax,%rax
  6bdc63:	je     6bdebb <user_event_entry+0x32b>
  6bdc69:	mov    0x60(%rax),%r14
  6bdc6d:	mov    %rax,0x8(%rsp)
  6bdc72:	movq   $0x1,0x18(%rsp)
  6bdc7b:	mov    %rbx,0x20(%rsp)
  6bdc80:	mov    %rcx,0xc8(%rsp)
  6bdc88:	mov    %rsi,0xd0(%rsp)
  6bdc90:	mov    %rdx,0xd8(%rsp)
  6bdc98:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  6bdc9d:	test   %r15b,%r15b
  6bdca0:	je     6bdcb7 <user_event_entry+0x127>
  6bdca2:	mov    (%r14),%rdi
  6bdca5:	add    $0x10,%rdi
  6bdca9:	lea    0x8(%rsp),%rsi
  6bdcae:	call   4a2a20 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::has_kernel_event>
  6bdcb3:	test   %al,%al
  6bdcb5:	je     6bdccd <user_event_entry+0x13d>
  6bdcb7:	movzbl %bpl,%edx
  6bdcbb:	lea    0x8(%rsp),%rsi
  6bdcc0:	lea    0x18(%rsp),%rcx
  6bdcc5:	mov    %r14,%rdi
  6bdcc8:	call   4a7c90 <__ostd_user_handle>
  6bdccd:	mov    (%r14),%rdi
  6bdcd0:	add    $0x10,%rdi
  6bdcd4:	lea    0x8(%rsp),%rsi
  6bdcd9:	call   4a2940 <<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::should_exit>
  6bdcde:	test   %al,%al
  6bdce0:	je     6bdcec <user_event_entry+0x15c>
  6bdce2:	call   6b6860 <ostd::task::exit_current_task>
  6bdce7:	jmp    6bdf54 <user_event_entry+0x3c4>
  6bdcec:	jmp    237719 <__kernelet_cpu_access_start+0x374f8>
  6bdcf1:	mov    0x50(%rdx),%eax
  6bdcf4:	mov    %eax,0x4(%rsp)
  6bdcf8:	test   %eax,%eax
  6bdcfa:	jne    6bdf05 <user_event_entry+0x375>
  6bdd00:	lea    0x370a31(%rip),%rdi        # a2e738 <anon.c1331c03898317998489fbaca113e814.22.llvm.15286295260971784537+0x48>
  6bdd07:	call   6bf700 <ostd::task::scheduler::might_preempt>
  6bdd0c:	jmp    237748 <__kernelet_cpu_access_start+0x37527>
  6bdd11:	test   %edx,%edx
  6bdd13:	sete   0x4(%rsp)
  6bdd18:	cmpb   $0x0,0x18(%rsp)
  6bdd1d:	jne    6bdd81 <user_event_entry+0x1f1>
  6bdd1f:	lea    0x20(%rsp),%rsi
  6bdd24:	mov    0xb0(%rsp),%r15
  6bdd2c:	mov    0xb8(%rsp),%r12
  6bdd34:	and    $0x240dd5,%r15d
  6bdd3b:	or     $0x202,%r15
  6bdd42:	mov    $0x88,%edx
  6bdd47:	mov    %rbx,%rdi
  6bdd4a:	call   6e77d0 <memcpy>
  6bdd4f:	movq   $0x33,0x88(%rbx)
  6bdd5a:	mov    %r15,0x90(%rbx)
  6bdd61:	mov    %r12,0x98(%rbx)
  6bdd68:	movq   $0x2b,0xa0(%rbx)
  6bdd73:	movq   $0x1,0x18(%rsp)
  6bdd7c:	mov    %rbx,0x20(%rsp)
  6bdd81:	lea    0x8(%rsp),%rsi
  6bdd86:	lea    0x4(%rsp),%rdx
  6bdd8b:	mov    %r14,%rdi
  6bdd8e:	call   4a7e00 <__ostd_user_pre_user_run>
  6bdd93:	mov    0x34229e(%rip),%rax        # a00038 <_DYNAMIC+0x5fe50>
  6bdd9a:	mov    (%rax),%rax
  6bdd9d:	test   %rax,%rax
  6bdda0:	je     6bdf2e <user_event_entry+0x39e>
  6bdda6:	xor    %edi,%edi
  6bdda8:	call   *0x68(%rax)
  6bddab:	lea    0x1a4d44(%rip),%rdi        # 862af6 <anon.c1331c03898317998489fbaca113e814.26.llvm.15286295260971784537+0x17>
  6bddb2:	lea    0x370997(%rip),%rdx        # a2e750 <anon.c1331c03898317998489fbaca113e814.22.llvm.15286295260971784537+0x60>
  6bddb9:	mov    $0xb3,%esi
  6bddbe:	call   6993b0 <core::panicking::panic_fmt>
  6bddc3:	jmp    6bdf54 <user_event_entry+0x3c4>
  6bddc8:	mov    $0x10,%ecx
  6bddcd:	xor    %r15d,%r15d
  6bddd0:	jmp    6bdc09 <user_event_entry+0x79>
  6bddd5:	mov    $0x13,%ecx
  6bddda:	xor    %r15d,%r15d
  6bdddd:	jmp    6bdc09 <user_event_entry+0x79>
  6bdde2:	mov    $0x17,%ecx
  6bdde7:	xor    %r15d,%r15d
  6bddea:	jmp    6bdc09 <user_event_entry+0x79>
  6bddef:	mov    $0x15,%ecx
  6bddf4:	xor    %r15d,%r15d
  6bddf7:	jmp    6bdc09 <user_event_entry+0x79>
  6bddfc:	mov    $0x14,%ecx
  6bde01:	xor    %r15d,%r15d
  6bde04:	jmp    6bdc09 <user_event_entry+0x79>
  6bde09:	mov    $0x11,%ecx
  6bde0e:	xor    %r15d,%r15d
  6bde11:	jmp    6bdc09 <user_event_entry+0x79>
  6bde16:	mov    $0x16,%ecx
  6bde1b:	xor    %r15d,%r15d
  6bde1e:	jmp    6bdc09 <user_event_entry+0x79>
  6bde23:	xor    %esi,%esi
  6bde25:	test   %rdx,%rdx
  6bde28:	setne  %sil
  6bde2c:	mov    $0xd,%ecx
  6bde31:	xor    %r15d,%r15d
  6bde34:	jmp    6bdc4e <user_event_entry+0xbe>
  6bde39:	mov    $0xf,%ecx
  6bde3e:	xor    %r15d,%r15d
  6bde41:	jmp    6bdc09 <user_event_entry+0x79>
  6bde46:	test   $0xffffffffffff7f00,%rdx
  6bde4d:	jne    6bdf48 <user_event_entry+0x3b8>
  6bde53:	mov    $0xe,%ecx
  6bde58:	xor    %r15d,%r15d
  6bde5b:	mov    %rdx,%rsi
  6bde5e:	mov    %rdi,%rdx
  6bde61:	jmp    6bdc4e <user_event_entry+0xbe>
  6bde66:	add    $0xffffffffffffffea,%rcx
  6bde6a:	cmp    $0x6,%rcx
  6bde6e:	jb     6bdc3f <user_event_entry+0xaf>
  6bde74:	lea    0x1a4c03(%rip),%rdi        # 862a7e <anon.c1331c03898317998489fbaca113e814.10.llvm.15286295260971784537+0x4c>
  6bde7b:	lea    0x370836(%rip),%rdx        # a2e6b8 <anon.c1331c03898317998489fbaca113e814.11.llvm.15286295260971784537+0x18>
  6bde82:	mov    $0x36,%esi
  6bde87:	call   697000 <core::option::expect_failed>
  6bde8c:	jmp    6bdf54 <user_event_entry+0x3c4>
  6bde91:	mov    $0x12,%ecx
  6bde96:	xor    %r15d,%r15d
  6bde99:	jmp    6bdc09 <user_event_entry+0x79>
  6bde9e:	lea    0x1a52b0(%rip),%rdi        # 863155 <anon.afbcb67d570395342e5c7b93cc9f14b2.32.llvm.5541347225946096535>
  6bdea5:	lea    0x370d14(%rip),%rdx        # a2ebc0 <anon.afbcb67d570395342e5c7b93cc9f14b2.33.llvm.5541347225946096535>
  6bdeac:	mov    $0x4d,%esi
  6bdeb1:	call   6993b0 <core::panicking::panic_fmt>
  6bdeb6:	jmp    6bdf54 <user_event_entry+0x3c4>
  6bdebb:	lea    0x1a4eb9(%rip),%rdi        # 862d7b <anon.c1331c03898317998489fbaca113e814.46.llvm.15286295260971784537+0x5b>
  6bdec2:	lea    0x3709af(%rip),%rdx        # a2e878 <anon.c1331c03898317998489fbaca113e814.49.llvm.15286295260971784537+0x50>
  6bdec9:	mov    $0x28,%esi
  6bdece:	call   697000 <core::option::expect_failed>
  6bded3:	jmp    6bdf54 <user_event_entry+0x3c4>
  6bded5:	lea    0x10(%rsp),%rax
  6bdeda:	mov    %rax,0x18(%rsp)
  6bdedf:	mov    0x34217a(%rip),%rax        # a00060 <_DYNAMIC+0x5fe78>
  6bdee6:	mov    %rax,0x20(%rsp)
  6bdeeb:	lea    0x14401f(%rip),%rdi        # 801f11 <anon.b67bcd52593e827c5eed2f0ccac7063f.4.llvm.12867154467337277043+0x15b>
  6bdef2:	lea    0x370997(%rip),%rdx        # a2e890 <anon.c1331c03898317998489fbaca113e814.49.llvm.15286295260971784537+0x68>
  6bdef9:	lea    0x18(%rsp),%rsi
  6bdefe:	call   6993b0 <core::panicking::panic_fmt>
  6bdf03:	jmp    6bdf54 <user_event_entry+0x3c4>
  6bdf05:	lea    0x1648c4(%rip),%rdx        # 8227d0 <anon.2503ed91df35c83fb86cc1a1f9db1e4e.67.llvm.15712373746005169545>
  6bdf0c:	lea    0x1a4c3c(%rip),%rcx        # 862b4f <anon.c1331c03898317998489fbaca113e814.26.llvm.15286295260971784537+0x70>
  6bdf13:	lea    0x37084e(%rip),%r9        # a2e768 <anon.c1331c03898317998489fbaca113e814.22.llvm.15286295260971784537+0x78>
  6bdf1a:	lea    0x4(%rsp),%rsi
  6bdf1f:	mov    $0x67,%r8d
  6bdf25:	xor    %edi,%edi
  6bdf27:	call   6d137a <core::panicking::assert_failed::<u32, u32>>
  6bdf2c:	jmp    6bdf54 <user_event_entry+0x3c4>
  6bdf2e:	lea    0x1a51f7(%rip),%rdi        # 86312c <anon.afbcb67d570395342e5c7b93cc9f14b2.30.llvm.5541347225946096535>
  6bdf35:	lea    0x370c6c(%rip),%rdx        # a2eba8 <anon.afbcb67d570395342e5c7b93cc9f14b2.31.llvm.5541347225946096535>
  6bdf3c:	mov    $0x53,%esi
  6bdf41:	call   6993b0 <core::panicking::panic_fmt>
  6bdf46:	jmp    6bdf54 <user_event_entry+0x3c4>
  6bdf48:	lea    0x3718a1(%rip),%rdi        # a2f7f0 <anon.550227be48ebb7ee8e2a1469a6e102b6.18.llvm.10212314987042294363>
  6bdf4f:	call   697040 <core::option::unwrap_failed>
  6bdf54:	ud2
  6bdf56:	endbr64
  6bdf5a:	xor    %edi,%edi
  6bdf5c:	call   6bbc60 <core::ptr::drop_glue::<ostd::irq::guard::DisabledLocalIrqGuard>>
  6bdf61:	jmp    6bdf7a <user_event_entry+0x3ea>
  6bdf63:	endbr64
  6bdf67:	call   6991bb <core::panicking::panic_in_cleanup>
  6bdf6c:	endbr64
  6bdf70:	lea    0x4(%rsp),%rdi
  6bdf75:	call   6cfd70 <<ostd::irq::guard::DisabledLocalIrqGuard as core::ops::drop::Drop>::drop>
  6bdf7a:	call   69934f <core::panicking::panic_cannot_unwind>
  6bdf7f:	endbr64
  6bdf83:	call   6991bb <core::panicking::panic_in_cleanup>
  6bdf88:	endbr64
  6bdf8c:	call   69934f <core::panicking::panic_cannot_unwind>
