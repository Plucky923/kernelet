
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-debug-assertions.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002fffc0 <aster_core::thread::task::exit_current_after_oops>:
  2fffc0:	push   %rbp
  2fffc1:	push   %r15
  2fffc3:	push   %r14
  2fffc5:	push   %r13
  2fffc7:	push   %r12
  2fffc9:	push   %rbx
  2fffca:	sub    $0x48,%rsp
  2fffce:	mov    %rsi,%r14
  2fffd1:	mov    %rdi,%r15
  2fffd4:	movabs $0xb6f403ec7315cb2f,%rbx
  2fffde:	movabs $0x8eed1c0dfa03cece,%r13
  2fffe8:	mov    0x28(%rdi),%r12
  2fffec:	mov    0x30(%rdi),%rax
  2ffff0:	mov    0x18(%rax),%rbp
  2ffff4:	lea    0x10(%rsp),%rdi
  2ffff9:	mov    %r12,%rsi
  2ffffc:	call   *%rbp
  2ffffe:	mov    0x18(%rsp),%rax
  300003:	xor    %rbx,%rax
  300006:	mov    0x10(%rsp),%rcx
  30000b:	xor    %r13,%rcx
  30000e:	or     %rax,%rcx
  300011:	jne    30027f <aster_core::thread::task::exit_current_after_oops+0x2bf>
  300017:	lea    0x10(%rsp),%rdi
  30001c:	mov    %r12,%rsi
  30001f:	call   *%rbp
  300021:	xor    0x18(%rsp),%rbx
  300026:	xor    0x10(%rsp),%r13
  30002b:	or     %rbx,%r13
  30002e:	jne    3001e3 <aster_core::thread::task::exit_current_after_oops+0x223>
  300034:	call   7aa1d0 <<ostd::irq::level::InterruptLevel>::current>
  300039:	cmp    $0x2,%al
  30003b:	jne    3001fb <aster_core::thread::task::exit_current_after_oops+0x23b>
  300041:	mov    %r15,0x40(%rsp)
  300046:	movabs $0x749e27a2a06b54a5,%r13
  300050:	movabs $0xab1dbb715a95736e,%rbp
  30005a:	mov    0x70(%r14),%rbx
  30005e:	mov    %r14,%r15
  300061:	mov    0x78(%r14),%rax
  300065:	mov    0x18(%rax),%r14
  300069:	lea    0x10(%rsp),%rdi
  30006e:	mov    %rbx,%rsi
  300071:	call   *%r14
  300074:	mov    0x18(%rsp),%rax
  300079:	xor    %r13,%rax
  30007c:	mov    0x10(%rsp),%rcx
  300081:	xor    %rbp,%rcx
  300084:	or     %rax,%rcx
  300087:	jne    30028b <aster_core::thread::task::exit_current_after_oops+0x2cb>
  30008d:	lea    0x10(%rsp),%rdi
  300092:	mov    %rbx,%rsi
  300095:	call   *%r14
  300098:	xor    0x18(%rsp),%r13
  30009d:	xor    0x10(%rsp),%rbp
  3000a2:	or     %r13,%rbp
  3000a5:	jne    3001e3 <aster_core::thread::task::exit_current_after_oops+0x223>
  3000ab:	mov    (%r12),%rcx
  3000af:	cmp    $0xffffffffffffffff,%rcx
  3000b3:	je     300273 <aster_core::thread::task::exit_current_after_oops+0x2b3>
  3000b9:	mov    (%rcx),%rax
  3000bc:	nopl   0x0(%rax)
  3000c0:	test   %rax,%rax
  3000c3:	je     300273 <aster_core::thread::task::exit_current_after_oops+0x2b3>
  3000c9:	js     3001b3 <aster_core::thread::task::exit_current_after_oops+0x1f3>
  3000cf:	lea    0x1(%rax),%rdx
  3000d3:	lock cmpxchg %rdx,(%rcx)
  3000d8:	jne    3000c0 <aster_core::thread::task::exit_current_after_oops+0x100>
  3000da:	mov    %rcx,0x8(%rsp)
  3000df:	lea    0x8(%rsp),%rax
  3000e4:	mov    %rax,0x10(%rsp)
  3000e9:	mov    %rbx,0x18(%rsp)
  3000ee:	mov    %r12,0x20(%rsp)
  3000f3:	mov    0x40(%rsp),%rax
  3000f8:	mov    %rax,0x28(%rsp)
  3000fd:	mov    %r15,0x30(%rsp)
  300102:	lea    0x10(%rsp),%rcx
  300107:	mov    $0x1,%edi
  30010c:	mov    $0x9,%esi
  300111:	mov    $0x1,%edx
  300116:	xor    %r8d,%r8d
  300119:	call   4daf90 <aster_core::process::posix_thread::exit::exit_internal>
  30011e:	cmpq   $0x0,0x20(%rbx)
  300123:	jne    300213 <aster_core::thread::task::exit_current_after_oops+0x253>
  300129:	movq   $0xffffffffffffffff,0x20(%rbx)
  300131:	mov    0x28(%rbx),%rax
  300135:	mov    %rax,0x38(%rsp)
  30013a:	movq   $0x0,0x28(%rbx)
  300142:	test   %rax,%rax
  300145:	je     300169 <aster_core::thread::task::exit_current_after_oops+0x1a9>
  300147:	lock decq (%rax)
  30014b:	jne    300169 <aster_core::thread::task::exit_current_after_oops+0x1a9>
  30014d:	lea    0x947d2c(%rip),%rax        # c47e80 <alloc::sync::STATIC_INNER_SLICE>
  300154:	cmp    %rax,0x38(%rsp)
  300159:	je     300259 <aster_core::thread::task::exit_current_after_oops+0x299>
  30015f:	lea    0x38(%rsp),%rdi
  300164:	call   3f0330 <<alloc::sync::Arc<aster_core::process::process::Process>>::drop_slow>
  300169:	mov    0x20(%rbx),%rax
  30016d:	test   %rax,%rax
  300170:	jns    300224 <aster_core::thread::task::exit_current_after_oops+0x264>
  300176:	inc    %rax
  300179:	mov    %rax,0x20(%rbx)
  30017d:	mov    0x8(%rsp),%rax
  300182:	lock decq (%rax)
  300186:	jne    3001a4 <aster_core::thread::task::exit_current_after_oops+0x1e4>
  300188:	lea    0x947cf1(%rip),%rax        # c47e80 <alloc::sync::STATIC_INNER_SLICE>
  30018f:	cmp    %rax,0x8(%rsp)
  300194:	je     300241 <aster_core::thread::task::exit_current_after_oops+0x281>
  30019a:	lea    0x8(%rsp),%rdi
  30019f:	call   3f0330 <<alloc::sync::Arc<aster_core::process::process::Process>>::drop_slow>
  3001a4:	add    $0x48,%rsp
  3001a8:	pop    %rbx
  3001a9:	pop    %r12
  3001ab:	pop    %r13
  3001ad:	pop    %r14
  3001af:	pop    %r15
  3001b1:	pop    %rbp
  3001b2:	ret
  3001b3:	lea    0x913506(%rip),%rax        # c136c0 <anon.19d55e948ab5c9cf675718faebdbae94.294.llvm.11391517053439275543>
  3001ba:	mov    %rax,0x10(%rsp)
  3001bf:	lea    0x232f0a(%rip),%rax        # 5330d0 <<&str as core::fmt::Display>::fmt>
  3001c6:	mov    %rax,0x18(%rsp)
  3001cb:	lea    0x50cbfa(%rip),%rdi        # 80cdcc <anon.055378037c1e9cc1a0f00573dcf9c1be.36.llvm.2361150307424502331>
  3001d2:	lea    0x913a37(%rip),%rdx        # c13c10 <anon.19d55e948ab5c9cf675718faebdbae94.388.llvm.11391517053439275543>
  3001d9:	lea    0x10(%rsp),%rsi
  3001de:	call   768ac0 <core::panicking::panic_fmt>
  3001e3:	lea    0x525cce(%rip),%rdi        # 825eb8 <anon.3b95ecad333729d81ec3f9963a62dbdb.24.llvm.3675744859411786911>
  3001ea:	lea    0x906327(%rip),%rdx        # c06518 <anon.3b95ecad333729d81ec3f9963a62dbdb.26.llvm.3675744859411786911>
  3001f1:	mov    $0x20,%esi
  3001f6:	call   768aa0 <core::panicking::panic>
  3001fb:	lea    0x5a4d58(%rip),%rdi        # 8a4f5a <anon.bf7c383cfd03a7b81434b21410e62c5a.37.llvm.3857089978811055691>
  300202:	lea    0x942e07(%rip),%rdx        # c43010 <anon.bf7c383cfd03a7b81434b21410e62c5a.38.llvm.3857089978811055691>
  300209:	mov    $0x3d,%esi
  30020e:	call   768aa0 <core::panicking::panic>
  300213:	lea    0x9071b6(%rip),%rdi        # c073d0 <anon.3b95ecad333729d81ec3f9963a62dbdb.254.llvm.3675744859411786911+0x90>
  30021a:	call   76cb40 <core::cell::panic_already_borrowed>
  30021f:	jmp    3002c8 <aster_core::thread::task::exit_current_after_oops+0x308>
  300224:	lea    0x5391f6(%rip),%rdi        # 839421 <anon.3b95ecad333729d81ec3f9963a62dbdb.567.llvm.3675744859411786911+0x127>
  30022b:	lea    0x907a96(%rip),%rdx        # c07cc8 <anon.3b95ecad333729d81ec3f9963a62dbdb.568.llvm.3675744859411786911+0x18>
  300232:	mov    $0x24,%esi
  300237:	call   768aa0 <core::panicking::panic>
  30023c:	jmp    3002c8 <aster_core::thread::task::exit_current_after_oops+0x308>
  300241:	lea    0x53902d(%rip),%rdi        # 839275 <anon.3b95ecad333729d81ec3f9963a62dbdb.565.llvm.3675744859411786911>
  300248:	lea    0x907a49(%rip),%rdx        # c07c98 <anon.3b95ecad333729d81ec3f9963a62dbdb.566.llvm.3675744859411786911>
  30024f:	mov    $0x10b,%esi
  300254:	call   768ac0 <core::panicking::panic_fmt>
  300259:	lea    0x539015(%rip),%rdi        # 839275 <anon.3b95ecad333729d81ec3f9963a62dbdb.565.llvm.3675744859411786911>
  300260:	lea    0x907a31(%rip),%rdx        # c07c98 <anon.3b95ecad333729d81ec3f9963a62dbdb.566.llvm.3675744859411786911>
  300267:	mov    $0x10b,%esi
  30026c:	call   768ac0 <core::panicking::panic_fmt>
  300271:	jmp    3002c8 <aster_core::thread::task::exit_current_after_oops+0x308>
  300273:	lea    0x9257d6(%rip),%rdi        # c25a50 <anon.43d75920d2503c73fe3ebcdc287f539b.143.llvm.927796520225997127>
  30027a:	call   7709b0 <core::option::unwrap_failed>
  30027f:	lea    0x90711a(%rip),%rdi        # c073a0 <anon.3b95ecad333729d81ec3f9963a62dbdb.254.llvm.3675744859411786911+0x60>
  300286:	call   7709b0 <core::option::unwrap_failed>
  30028b:	lea    0x907126(%rip),%rdi        # c073b8 <anon.3b95ecad333729d81ec3f9963a62dbdb.254.llvm.3675744859411786911+0x78>
  300292:	call   7709b0 <core::option::unwrap_failed>
  300297:	endbr64
  30029b:	mov    %rax,%r14
  30029e:	mov    0x20(%rbx),%rax
  3002a2:	test   %rax,%rax
  3002a5:	jns    3002b0 <aster_core::thread::task::exit_current_after_oops+0x2f0>
  3002a7:	inc    %rax
  3002aa:	mov    %rax,0x20(%rbx)
  3002ae:	jmp    3002d1 <aster_core::thread::task::exit_current_after_oops+0x311>
  3002b0:	lea    0x53916a(%rip),%rdi        # 839421 <anon.3b95ecad333729d81ec3f9963a62dbdb.567.llvm.3675744859411786911+0x127>
  3002b7:	lea    0x907a0a(%rip),%rdx        # c07cc8 <anon.3b95ecad333729d81ec3f9963a62dbdb.568.llvm.3675744859411786911+0x18>
  3002be:	mov    $0x24,%esi
  3002c3:	call   768aa0 <core::panicking::panic>
  3002c8:	ud2
  3002ca:	endbr64
  3002ce:	mov    %rax,%r14
  3002d1:	lea    0x8(%rsp),%rdi
  3002d6:	call   2ec7e0 <core::ptr::drop_glue::<alloc::sync::Arc<aster_core::process::process::Process>>>
  3002db:	mov    %r14,%rdi
  3002de:	call   7d4200 <_Unwind_Resume>
  3002e3:	endbr64
  3002e7:	call   7688cb <core::panicking::panic_in_cleanup>
