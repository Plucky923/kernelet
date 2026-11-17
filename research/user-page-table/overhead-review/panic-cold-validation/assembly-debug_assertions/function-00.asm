
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-debug-assertions.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000798040 <ostd::panic::report_caught_panic>:
  798040:	endbr64
  798044:	push   %r14
  798046:	push   %rbx
  798047:	sub    $0x828,%rsp
  79804e:	lea    0x4bbc73(%rip),%rdi        # c53cc8 <ostd::panic::PANIC_MESSAGE>
  798055:	call   79aa70 <<ostd::sync::spin::SpinLock<core::option::Option<alloc::collections::btree::map::BTreeMap<usize, ostd::util::range_alloc::FreeRange>>>>::lock>
  79805a:	mov    %edx,%ebx
  79805c:	cmpl   $0x1,0x8(%rax)
  798060:	jne    79808b <ostd::panic::report_caught_panic+0x4b>
  798062:	mov    %rax,%rsi
  798065:	add    $0x10,%rsi
  798069:	lea    0x18(%rsp),%rdi
  79806e:	mov    $0x408,%edx
  798073:	mov    %rax,%r14
  798076:	call   7d4fd0 <memcpy>
  79807b:	movb   $0x0,(%r14)
  79807f:	test   $0x1,%bl
  798082:	je     7980e3 <ostd::panic::report_caught_panic+0xa3>
  798084:	call   79c0d0 <ostd::arch::irq::ops::enable_local>
  798089:	jmp    7980e3 <ostd::panic::report_caught_panic+0xa3>
  79808b:	movb   $0x0,(%rax)
  79808e:	test   $0x1,%bl
  798091:	je     798098 <ostd::panic::report_caught_panic+0x58>
  798093:	call   79c0d0 <ostd::arch::irq::ops::enable_local>
  798098:	lea    0x18(%rsp),%rbx
  79809d:	mov    $0x408,%edx
  7980a2:	mov    %rbx,%rdi
  7980a5:	xor    %esi,%esi
  7980a7:	call   7d4fe0 <memset>
  7980ac:	lea    0x10bd19(%rip),%rax        # 8a3dcc <anon.e07f08680952a81bdd214844bdef2536.46.llvm.4295080565535924109>
  7980b3:	mov    %rbx,%rcx
  7980b6:	sub    %rax,%rcx
  7980b9:	sub    %rbx,%rax
  7980bc:	cmovb  %rcx,%rax
  7980c0:	cmp    $0x4,%rax
  7980c4:	jbe    7981e8 <ostd::panic::report_caught_panic+0x1a8>
  7980ca:	movb   $0x74,0x1c(%rsp)
  7980cf:	movl   $0x726f6261,0x18(%rsp)
  7980d7:	movq   $0x5,0x418(%rsp)
  7980e3:	lea    0x420(%rsp),%rdi
  7980eb:	lea    0x18(%rsp),%rsi
  7980f0:	mov    $0x408,%edx
  7980f5:	call   7d4fd0 <memcpy>
  7980fa:	mov    0x820(%rsp),%rdx
  798102:	cmp    $0x401,%rdx
  798109:	jae    798182 <ostd::panic::report_caught_panic+0x142>
  79810b:	lea    0x18(%rsp),%rdi
  798110:	lea    0x420(%rsp),%rsi
  798118:	call   771270 <core::str::converts::from_utf8>
  79811d:	cmpl   $0x1,0x18(%rsp)
  798122:	je     798198 <ostd::panic::report_caught_panic+0x158>
  798124:	mov    0x20(%rsp),%rdi
  798129:	mov    0x28(%rsp),%rax
  79812e:	cmp    $0x400,%rax
  798134:	mov    $0x400,%esi
  798139:	cmovb  %rax,%rsi
  79813d:	test   %rax,%rax
  798140:	je     798162 <ostd::panic::report_caught_panic+0x122>
  798142:	data16 data16 data16 data16 cs nopw 0x0(%rax,%rax,1)
  798150:	cmp    %rax,%rsi
  798153:	jae    798162 <ostd::panic::report_caught_panic+0x122>
  798155:	cmpb   $0xbf,(%rdi,%rsi,1)
  798159:	jg     798162 <ostd::panic::report_caught_panic+0x122>
  79815b:	dec    %rsi
  79815e:	jne    798150 <ostd::panic::report_caught_panic+0x110>
  798160:	xor    %esi,%esi
  798162:	mov    0x467ef7(%rip),%rax        # c00060 <_DYNAMIC+0x1d09f0>
  798169:	mov    (%rax),%rax
  79816c:	test   %rax,%rax
  79816f:	je     7981d0 <ostd::panic::report_caught_panic+0x190>
  798171:	call   *0x88(%rax)
  798177:	add    $0x828,%rsp
  79817e:	pop    %rbx
  79817f:	pop    %r14
  798181:	ret
  798182:	lea    0x4aa4c7(%rip),%rcx        # c42650 <anon.e07f08680952a81bdd214844bdef2536.22.llvm.4295080565535924109>
  798189:	mov    %rdx,%rsi
  79818c:	mov    $0x400,%edx
  798191:	xor    %edi,%edi
  798193:	call   770350 <core::slice::index::slice_index_fail>
  798198:	mov    0x20(%rsp),%rax
  79819d:	mov    0x28(%rsp),%rcx
  7981a2:	mov    %rcx,0x10(%rsp)
  7981a7:	mov    %rax,0x8(%rsp)
  7981ac:	lea    0x10bb0a(%rip),%rdi        # 8a3cbd <anon.e07f08680952a81bdd214844bdef2536.19.llvm.4295080565535924109>
  7981b3:	lea    0x4aa45e(%rip),%rcx        # c42618 <anon.e07f08680952a81bdd214844bdef2536.18.llvm.4295080565535924109>
  7981ba:	lea    0x4aa477(%rip),%r8        # c42638 <anon.e07f08680952a81bdd214844bdef2536.21.llvm.4295080565535924109>
  7981c1:	lea    0x8(%rsp),%rdx
  7981c6:	mov    $0x2b,%esi
  7981cb:	call   76aab0 <core::result::unwrap_failed>
  7981d0:	lea    0x10c781(%rip),%rdi        # 8a4958 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.60.llvm.11761605922429748139>
  7981d7:	lea    0x4aab2a(%rip),%rdx        # c42d08 <anon.0e74a12f2ac2a7330ad456ad1b8e14c7.61.llvm.11761605922429748139>
  7981de:	mov    $0x53,%esi
  7981e3:	call   768ac0 <core::panicking::panic_fmt>
  7981e8:	lea    0x10f8b4(%rip),%rdi        # 8a7aa3 <anon.f40d34db087d2d84d82875049dee6790.69.llvm.11209988631381524334>
  7981ef:	lea    0x4abe8a(%rip),%rcx        # c44080 <anon.f40d34db087d2d84d82875049dee6790.6.llvm.11209988631381524334>
  7981f6:	mov    $0x237,%esi
  7981fb:	xor    %edx,%edx
  7981fd:	call   768920 <core::panicking::panic_nounwind_fmt>
