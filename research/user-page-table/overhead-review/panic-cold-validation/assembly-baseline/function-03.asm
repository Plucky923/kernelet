
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-baseline.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000048bfb0 <aster_core::thread::task::exit_current_after_oops>:
  48bfb0:	endbr64
  48bfb4:	push   %r15
  48bfb6:	push   %r14
  48bfb8:	push   %r12
  48bfba:	push   %rbx
  48bfbb:	sub    $0x48,%rsp
  48bfbf:	mov    %rsi,%rbx
  48bfc2:	mov    %rdi,%r14
  48bfc5:	mov    0x28(%rdi),%r15
  48bfc9:	mov    0x30(%rdi),%rax
  48bfcd:	lea    0x10(%rsp),%rdi
  48bfd2:	mov    %r15,%rsi
  48bfd5:	call   *0x18(%rax)
  48bfd8:	movabs $0x24381668dbddccd4,%rax
  48bfe2:	xor    0x18(%rsp),%rax
  48bfe7:	movabs $0xd5bc020f4457557d,%rcx
  48bff1:	xor    0x10(%rsp),%rcx
  48bff6:	or     %rax,%rcx
  48bff9:	jne    48c147 <aster_core::thread::task::exit_current_after_oops+0x197>
  48bfff:	call   6d6e30 <<ostd::irq::level::InterruptLevel>::current>
  48c004:	cmp    $0x2,%al
  48c006:	jne    48c153 <aster_core::thread::task::exit_current_after_oops+0x1a3>
  48c00c:	mov    (%rbx),%r12
  48c00f:	mov    0x70(%r12),%rbx
  48c014:	mov    0x78(%r12),%rax
  48c019:	lea    0x10(%rsp),%rdi
  48c01e:	mov    %rbx,%rsi
  48c021:	call   *0x18(%rax)
  48c024:	movabs $0x4403bae9dd1ea411,%rax
  48c02e:	xor    0x18(%rsp),%rax
  48c033:	movabs $0xdb07d43de26bc392,%rcx
  48c03d:	xor    0x10(%rsp),%rcx
  48c042:	or     %rax,%rcx
  48c045:	jne    48c16b <aster_core::thread::task::exit_current_after_oops+0x1bb>
  48c04b:	mov    (%r15),%rcx
  48c04e:	cmp    $0xffffffffffffffff,%rcx
  48c052:	je     48c185 <aster_core::thread::task::exit_current_after_oops+0x1d5>
  48c058:	mov    (%rcx),%rax
  48c05b:	nopl   0x0(%rax,%rax,1)
  48c060:	test   %rax,%rax
  48c063:	je     48c185 <aster_core::thread::task::exit_current_after_oops+0x1d5>
  48c069:	js     48c117 <aster_core::thread::task::exit_current_after_oops+0x167>
  48c06f:	lea    0x1(%rax),%rdx
  48c073:	lock cmpxchg %rdx,(%rcx)
  48c078:	jne    48c060 <aster_core::thread::task::exit_current_after_oops+0xb0>
  48c07a:	mov    %rcx,0x8(%rsp)
  48c07f:	lea    0x8(%rsp),%rax
  48c084:	mov    %rax,0x10(%rsp)
  48c089:	mov    %rbx,0x18(%rsp)
  48c08e:	mov    %r15,0x20(%rsp)
  48c093:	mov    %r14,0x28(%rsp)
  48c098:	mov    %r12,0x30(%rsp)
  48c09d:	lea    0x10(%rsp),%rcx
  48c0a2:	mov    $0x1,%edi
  48c0a7:	mov    $0x9,%esi
  48c0ac:	mov    $0x1,%edx
  48c0b1:	xor    %r8d,%r8d
  48c0b4:	call   4fe860 <aster_core::process::posix_thread::exit::exit_internal>
  48c0b9:	cmpq   $0x0,0x20(%rbx)
  48c0be:	jne    48c177 <aster_core::thread::task::exit_current_after_oops+0x1c7>
  48c0c4:	movq   $0xffffffffffffffff,0x20(%rbx)
  48c0cc:	mov    0x28(%rbx),%rax
  48c0d0:	mov    %rax,0x40(%rsp)
  48c0d5:	movq   $0x0,0x28(%rbx)
  48c0dd:	test   %rax,%rax
  48c0e0:	je     48c0f2 <aster_core::thread::task::exit_current_after_oops+0x142>
  48c0e2:	lock decq (%rax)
  48c0e6:	jne    48c0f2 <aster_core::thread::task::exit_current_after_oops+0x142>
  48c0e8:	lea    0x40(%rsp),%rdi
  48c0ed:	call   4cbf40 <<alloc::sync::Arc<aster_core::process::process::Process>>::drop_slow>
  48c0f2:	incq   0x20(%rbx)
  48c0f6:	mov    0x8(%rsp),%rax
  48c0fb:	lock decq (%rax)
  48c0ff:	jne    48c10b <aster_core::thread::task::exit_current_after_oops+0x15b>
  48c101:	lea    0x8(%rsp),%rdi
  48c106:	call   4cbf40 <<alloc::sync::Arc<aster_core::process::process::Process>>::drop_slow>
  48c10b:	add    $0x48,%rsp
  48c10f:	pop    %rbx
  48c110:	pop    %r12
  48c112:	pop    %r14
  48c114:	pop    %r15
  48c116:	ret
  48c117:	lea    0x58cc2a(%rip),%rax        # a18d48 <anon.cfac5cc4358780d9e0f789c5cd6dc1c3.211.llvm.17080032327367914158>
  48c11e:	mov    %rax,0x10(%rsp)
  48c123:	lea    0xeaac6(%rip),%rax        # 576bf0 <<&str as core::fmt::Display>::fmt>
  48c12a:	mov    %rax,0x18(%rsp)
  48c12f:	lea    0x38050d(%rip),%rdi        # 80c643 <anon.021f6bd551db92d9d6c9f53b265611f8.15.llvm.34896216114674485>
  48c136:	lea    0x58d303(%rip),%rdx        # a19440 <anon.cfac5cc4358780d9e0f789c5cd6dc1c3.276.llvm.17080032327367914158>
  48c13d:	lea    0x10(%rsp),%rsi
  48c142:	call   6993b0 <core::panicking::panic_fmt>
  48c147:	lea    0x58b532(%rip),%rdi        # a17680 <anon.f33a4f5cee034cd6bd08af439f8252b2.118.llvm.8031750790851227478+0xa8>
  48c14e:	call   697040 <core::option::unwrap_failed>
  48c153:	lea    0x3d6041(%rip),%rdi        # 86219b <anon.15e4b86be320fe459a17ca9fb0b8e1cc.5.llvm.13975411090267346181>
  48c15a:	lea    0x5a1e6f(%rip),%rdx        # a2dfd0 <anon.15e4b86be320fe459a17ca9fb0b8e1cc.6.llvm.13975411090267346181>
  48c161:	mov    $0x3d,%esi
  48c166:	call   699390 <core::panicking::panic>
  48c16b:	lea    0x58b526(%rip),%rdi        # a17698 <anon.f33a4f5cee034cd6bd08af439f8252b2.118.llvm.8031750790851227478+0xc0>
  48c172:	call   697040 <core::option::unwrap_failed>
  48c177:	lea    0x58b532(%rip),%rdi        # a176b0 <anon.f33a4f5cee034cd6bd08af439f8252b2.118.llvm.8031750790851227478+0xd8>
  48c17e:	call   698160 <core::cell::panic_already_borrowed>
  48c183:	ud2
  48c185:	lea    0x58886c(%rip),%rdi        # a149f8 <anon.7200fa5fe448993de6c8e4f60a327c2f.64.llvm.12614982092476800003>
  48c18c:	call   697040 <core::option::unwrap_failed>
  48c191:	endbr64
  48c195:	mov    %rax,%r14
  48c198:	incq   0x20(%rbx)
  48c19c:	jmp    48c1a5 <aster_core::thread::task::exit_current_after_oops+0x1f5>
  48c19e:	endbr64
  48c1a2:	mov    %rax,%r14
  48c1a5:	mov    0x8(%rsp),%rax
  48c1aa:	lock decq (%rax)
  48c1ae:	jne    48c1ba <aster_core::thread::task::exit_current_after_oops+0x20a>
  48c1b0:	lea    0x8(%rsp),%rdi
  48c1b5:	call   4cbf40 <<alloc::sync::Arc<aster_core::process::process::Process>>::drop_slow>
  48c1ba:	mov    %r14,%rdi
  48c1bd:	call   6e7070 <_Unwind_Resume>
  48c1c2:	endbr64
  48c1c6:	call   6991bb <core::panicking::panic_in_cleanup>
