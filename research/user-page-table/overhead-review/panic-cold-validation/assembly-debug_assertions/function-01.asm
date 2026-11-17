
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-debug-assertions.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000055c900 <aster_core::thread::oops::handle_oops>:
  55c900:	endbr64
  55c904:	push   %rbp
  55c905:	push   %r15
  55c907:	push   %r14
  55c909:	push   %r13
  55c90b:	push   %r12
  55c90d:	push   %rbx
  55c90e:	sub    $0x68,%rsp
  55c912:	mov    %rdx,%r15
  55c915:	mov    %rsi,%rbx
  55c918:	mov    %rdi,%r14
  55c91b:	mov    %rsi,0x58(%rsp)
  55c920:	mov    %rdx,0x60(%rsp)
  55c925:	mov    0x18(%rdx),%r12
  55c929:	mov    %rsp,%rdi
  55c92c:	call   *%r12
  55c92f:	movabs $0x665e92791a29d7b9,%r13
  55c939:	movabs $0x14eeda07bd5a7945,%rbp
  55c943:	mov    0x8(%rsp),%rax
  55c948:	xor    %r13,%rax
  55c94b:	mov    (%rsp),%rcx
  55c94f:	xor    %rbp,%rcx
  55c952:	or     %rax,%rcx
  55c955:	jne    55cb23 <aster_core::thread::oops::handle_oops+0x223>
  55c95b:	mov    %rbx,0x48(%rsp)
  55c960:	mov    %r15,0x50(%rsp)
  55c965:	mov    %rsp,%rdi
  55c968:	mov    %rbx,%rsi
  55c96b:	call   *%r12
  55c96e:	xor    (%rsp),%rbp
  55c972:	xor    0x8(%rsp),%r13
  55c977:	or     %rbp,%r13
  55c97a:	jne    55cae9 <aster_core::thread::oops::handle_oops+0x1e9>
  55c980:	mov    0x8(%rbx),%rdi
  55c984:	mov    0x10(%rbx),%rcx
  55c988:	cmp    $0x400,%rcx
  55c98f:	mov    $0x400,%esi
  55c994:	mov    $0x400,%eax
  55c999:	cmovb  %rcx,%rax
  55c99d:	test   %rcx,%rcx
  55c9a0:	je     55c9c2 <aster_core::thread::oops::handle_oops+0xc2>
  55c9a2:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  55c9b0:	cmp    %rcx,%rax
  55c9b3:	jae    55c9c2 <aster_core::thread::oops::handle_oops+0xc2>
  55c9b5:	cmpb   $0xbf,(%rdi,%rax,1)
  55c9b9:	jg     55c9c2 <aster_core::thread::oops::handle_oops+0xc2>
  55c9bb:	dec    %rax
  55c9be:	jne    55c9b0 <aster_core::thread::oops::handle_oops+0xb0>
  55c9c0:	jmp    55c9f0 <aster_core::thread::oops::handle_oops+0xf0>
  55c9c2:	cmp    $0x400,%rax
  55c9c8:	cmovb  %rax,%rsi
  55c9cc:	test   %rax,%rax
  55c9cf:	je     55c9f2 <aster_core::thread::oops::handle_oops+0xf2>
  55c9d1:	data16 data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  55c9e0:	cmp    %rax,%rsi
  55c9e3:	jae    55c9f2 <aster_core::thread::oops::handle_oops+0xf2>
  55c9e5:	cmpb   $0xbf,(%rdi,%rsi,1)
  55c9e9:	jg     55c9f2 <aster_core::thread::oops::handle_oops+0xf2>
  55c9eb:	dec    %rsi
  55c9ee:	jne    55c9e0 <aster_core::thread::oops::handle_oops+0xe0>
  55c9f0:	xor    %esi,%esi
  55c9f2:	mov    0x6a3667(%rip),%rax        # c00060 <_DYNAMIC+0x1d09f0>
  55c9f9:	mov    (%rax),%rax
  55c9fc:	test   %rax,%rax
  55c9ff:	je     55cb06 <aster_core::thread::oops::handle_oops+0x206>
  55ca05:	call   *0x88(%rax)
  55ca0b:	movzbl 0x6f7916(%rip),%eax        # c54328 <ostd::log::logger::DYNAMIC_MAX_LEVEL>
  55ca12:	cmp    $0x3,%al
  55ca14:	jbe    55ca8d <aster_core::thread::oops::handle_oops+0x18d>
  55ca16:	mov    %rbx,0x48(%rsp)
  55ca1b:	lea    0x12e1e(%rip),%rax        # 56f840 <<alloc::string::String as core::fmt::Display>::fmt>
  55ca22:	mov    %rax,0x50(%rsp)
  55ca27:	movb   $0x3,0x44(%rsp)
  55ca2c:	movq   $0x1,(%rsp)
  55ca34:	movq   $0x0,0x8(%rsp)
  55ca3d:	lea    0x2bd713(%rip),%rax        # 81a157 <anon.abb8e1a675f3458015ed6867f151424c.577.llvm.10974897355327627597+0x134>
  55ca44:	mov    %rax,0x10(%rsp)
  55ca49:	lea    0x48(%rsp),%rax
  55ca4e:	mov    %rax,0x18(%rsp)
  55ca53:	lea    0x30aaad(%rip),%rax        # 867507 <anon.43d75920d2503c73fe3ebcdc287f539b.481.llvm.927796520225997127+0x1a>
  55ca5a:	mov    %rax,0x20(%rsp)
  55ca5f:	movq   $0x18,0x28(%rsp)
  55ca68:	lea    0x30aab0(%rip),%rax        # 86751f <anon.43d75920d2503c73fe3ebcdc287f539b.481.llvm.927796520225997127+0x32>
  55ca6f:	mov    %rax,0x30(%rsp)
  55ca74:	movq   $0xb4,0x38(%rsp)
  55ca7d:	movl   $0x41,0x40(%rsp)
  55ca85:	mov    %rsp,%rdi
  55ca88:	call   7b3270 <ostd::log::logger::__write_log_record>
  55ca8d:	mov    $0x1,%eax
  55ca92:	lock xadd %rax,0x6f5b0d(%rip)        # c525a8 <aster_core::thread::oops::OOPS_COUNT>
  55ca9b:	cmp    $0x270f,%rax
  55caa1:	ja     55cb50 <aster_core::thread::oops::handle_oops+0x250>
  55caa7:	mov    0x18(%rbx),%rax
  55caab:	mov    %rax,0x18(%r14)
  55caaf:	mov    0x10(%rbx),%rax
  55cab3:	mov    %rax,0x10(%r14)
  55cab7:	mov    (%rbx),%rax
  55caba:	mov    0x8(%rbx),%rcx
  55cabe:	mov    %rcx,0x8(%r14)
  55cac2:	mov    %rax,(%r14)
  55cac5:	mov    $0x8,%edx
  55caca:	mov    $0x20,%ecx
  55cacf:	mov    %rbx,%rsi
  55cad2:	call   7add50 <<ostd::mm::heap::AllocDispatch as core::alloc::global::GlobalAlloc>::dealloc>
  55cad7:	mov    %r14,%rax
  55cada:	add    $0x68,%rsp
  55cade:	pop    %rbx
  55cadf:	pop    %r12
  55cae1:	pop    %r13
  55cae3:	pop    %r14
  55cae5:	pop    %r15
  55cae7:	pop    %rbp
  55cae8:	ret
  55cae9:	lea    0x2c93c8(%rip),%rdi        # 825eb8 <anon.3b95ecad333729d81ec3f9963a62dbdb.24.llvm.3675744859411786911>
  55caf0:	lea    0x6c8b19(%rip),%rdx        # c25610 <anon.43d75920d2503c73fe3ebcdc287f539b.24.llvm.927796520225997127+0x90>
  55caf7:	mov    $0x20,%esi
  55cafc:	call   768aa0 <core::panicking::panic>
  55cb01:	jmp    55cbc5 <aster_core::thread::oops::handle_oops+0x2c5>
  55cb06:	lea    0x347e4b(%rip),%rdi        # 8a4958 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.60.llvm.11761605922429748139>
  55cb0d:	lea    0x6e61f4(%rip),%rdx        # c42d08 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.61.llvm.11761605922429748139>
  55cb14:	mov    $0x53,%esi
  55cb19:	call   768ac0 <core::panicking::panic_fmt>
  55cb1e:	jmp    55cbc5 <aster_core::thread::oops::handle_oops+0x2c5>
  55cb23:	mov    %rbx,(%rsp)
  55cb27:	mov    %r15,0x8(%rsp)
  55cb2c:	lea    0x308fbf(%rip),%rdi        # 865af2 <anon.43d75920d2503c73fe3ebcdc287f539b.127.llvm.927796520225997127>
  55cb33:	lea    0x6c8e36(%rip),%rcx        # c25970 <anon.43d75920d2503c73fe3ebcdc287f539b.122.llvm.927796520225997127+0x50>
  55cb3a:	lea    0x6ca4d7(%rip),%r8        # c27018 <anon.43d75920d2503c73fe3ebcdc287f539b.496.llvm.927796520225997127+0x20>
  55cb41:	mov    %rsp,%rdx
  55cb44:	mov    $0x2b,%esi
  55cb49:	call   76aab0 <core::result::unwrap_failed>
  55cb4e:	jmp    55cbc5 <aster_core::thread::oops::handle_oops+0x2c5>
  55cb50:	movzbl 0x6f77d1(%rip),%eax        # c54328 <ostd::log::logger::DYNAMIC_MAX_LEVEL>
  55cb57:	cmp    $0x3,%al
  55cb59:	jbe    55cbc0 <aster_core::thread::oops::handle_oops+0x2c0>
  55cb5b:	movb   $0x3,0x44(%rsp)
  55cb60:	movq   $0x1,(%rsp)
  55cb68:	movq   $0x0,0x8(%rsp)
  55cb71:	lea    0x30aa5b(%rip),%rax        # 8675d3 <anon.43d75920d2503c73fe3ebcdc287f539b.481.llvm.927796520225997127+0xe6>
  55cb78:	mov    %rax,0x10(%rsp)
  55cb7d:	movq   $0x43,0x18(%rsp)
  55cb86:	lea    0x30a97a(%rip),%rax        # 867507 <anon.43d75920d2503c73fe3ebcdc287f539b.481.llvm.927796520225997127+0x1a>
  55cb8d:	mov    %rax,0x20(%rsp)
  55cb92:	movq   $0x18,0x28(%rsp)
  55cb9b:	lea    0x30a97d(%rip),%rax        # 86751f <anon.43d75920d2503c73fe3ebcdc287f539b.481.llvm.927796520225997127+0x32>
  55cba2:	mov    %rax,0x30(%rsp)
  55cba7:	movq   $0xb4,0x38(%rsp)
  55cbb0:	movl   $0x46,0x40(%rsp)
  55cbb8:	mov    %rsp,%rdi
  55cbbb:	call   7b3270 <ostd::log::logger::__write_log_record>
  55cbc0:	call   798210 <ostd::panic::abort>
  55cbc5:	ud2
  55cbc7:	endbr64
  55cbcb:	mov    %rax,%r14
  55cbce:	mov    %rsp,%rdi
  55cbd1:	call   53c310 <core::ptr::drop_glue::<alloc::boxed::Box<dyn core::any::Any + core::marker::Send>>>
  55cbd6:	jmp    55cc28 <aster_core::thread::oops::handle_oops+0x328>
  55cbd8:	endbr64
  55cbdc:	call   7688cb <core::panicking::panic_in_cleanup>
  55cbe1:	endbr64
  55cbe5:	mov    %rax,%r14
  55cbe8:	lea    0x58(%rsp),%rdi
  55cbed:	call   53c310 <core::ptr::drop_glue::<alloc::boxed::Box<dyn core::any::Any + core::marker::Send>>>
  55cbf2:	jmp    55cc28 <aster_core::thread::oops::handle_oops+0x328>
  55cbf4:	endbr64
  55cbf8:	call   7688cb <core::panicking::panic_in_cleanup>
  55cbfd:	endbr64
  55cc01:	mov    %rax,%r14
  55cc04:	lea    0x48(%rsp),%rdi
  55cc09:	call   53c310 <core::ptr::drop_glue::<alloc::boxed::Box<dyn core::any::Any + core::marker::Send>>>
  55cc0e:	jmp    55cc28 <aster_core::thread::oops::handle_oops+0x328>
  55cc10:	endbr64
  55cc14:	call   7688cb <core::panicking::panic_in_cleanup>
  55cc19:	endbr64
  55cc1d:	mov    %rax,%r14
  55cc20:	mov    %rbx,%rdi
  55cc23:	call   53c3c0 <core::ptr::drop_glue::<alloc::boxed::Box<aster_core::thread::oops::OopsInfo>>>
  55cc28:	mov    %r14,%rdi
  55cc2b:	call   7d4200 <_Unwind_Resume>
  55cc30:	endbr64
  55cc34:	call   7688cb <core::panicking::panic_in_cleanup>
