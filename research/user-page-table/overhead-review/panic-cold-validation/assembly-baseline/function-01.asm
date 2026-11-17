
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-baseline.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000047dc90 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>>:
  47dc90:	endbr64
  47dc94:	push   %rbp
  47dc95:	push   %r15
  47dc97:	push   %r14
  47dc99:	push   %rbx
  47dc9a:	sub    $0xc18,%rsp
  47dca1:	call   522e90 <unwinding::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>>
  47dca6:	mov    %rax,%r14
  47dca9:	mov    %rdx,%rbx
  47dcac:	test   %rax,%rax
  47dcaf:	je     47de17 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x187>
  47dcb5:	jmp    21cd26 <__kernelet_cpu_access_start+0x1cb05>
  47dcba:	mov    $0x1,%r15b
  47dcbd:	nopl   (%rax)
  47dcc0:	xor    %eax,%eax
  47dcc2:	lock cmpxchg %r15b,0x5bf355(%rip)        # a3d020 <ostd::panic::PANIC_MESSAGE>
  47dccb:	je     47dcd6 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x46>
  47dccd:	pause
  47dccf:	call   6c1770 <ostd::kernelet::entry::on_spin>
  47dcd4:	jmp    47dcc0 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x30>
  47dcd6:	cmpl   $0x1,0x5bf34b(%rip)        # a3d028 <ostd::panic::PANIC_MESSAGE+0x8>
  47dcdd:	jne    47dd4c <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xbc>
  47dcdf:	lea    0x5bf34a(%rip),%rsi        # a3d030 <ostd::panic::PANIC_MESSAGE+0x10>
  47dce6:	lea    0x8(%rsp),%rdi
  47dceb:	mov    $0x408,%edx
  47dcf0:	call   6e77d0 <memcpy>
  47dcf5:	movb   $0x0,0x5bf324(%rip)        # a3d020 <ostd::panic::PANIC_MESSAGE>
  47dcfc:	test   %ebp,%ebp
  47dcfe:	jne    47dd05 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x75>
  47dd00:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  47dd05:	lea    0x810(%rsp),%rdi
  47dd0d:	lea    0x8(%rsp),%rsi
  47dd12:	mov    $0x408,%edx
  47dd17:	call   6e77d0 <memcpy>
  47dd1c:	mov    0xc10(%rsp),%rdx
  47dd24:	cmp    $0x401,%rdx
  47dd2b:	jb     47ddb6 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x126>
  47dd31:	lea    0x5b1730(%rip),%rcx        # a2f468 <anon.55b2096fce70f764b67d5f98016630b8.27.llvm.15975230346321710139>
  47dd38:	mov    %rdx,%rsi
  47dd3b:	mov    $0x400,%edx
  47dd40:	xor    %edi,%edi
  47dd42:	call   695060 <core::slice::index::slice_index_fail>
  47dd47:	jmp    47de86 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x1f6>
  47dd4c:	movb   $0x0,0x5bf2cd(%rip)        # a3d020 <ostd::panic::PANIC_MESSAGE>
  47dd53:	test   %ebp,%ebp
  47dd55:	jne    47dd5c <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0xcc>
  47dd57:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  47dd5c:	lea    0x415(%rsp),%rdi
  47dd64:	mov    $0x3fb,%edx
  47dd69:	xor    %esi,%esi
  47dd6b:	call   6e77e0 <memset>
  47dd70:	mov    0x3e5d4d(%rip),%eax        # 863ac3 <anon.55b2096fce70f764b67d5f98016630b8.38.llvm.15975230346321710139>
  47dd76:	mov    %eax,0x410(%rsp)
  47dd7d:	movzbl 0x3e5d43(%rip),%eax        # 863ac7 <anon.55b2096fce70f764b67d5f98016630b8.38.llvm.15975230346321710139+0x4>
  47dd84:	mov    %al,0x414(%rsp)
  47dd8b:	lea    0x810(%rsp),%rdi
  47dd93:	lea    0x410(%rsp),%rsi
  47dd9b:	mov    $0x400,%edx
  47dda0:	call   6e77d0 <memcpy>
  47dda5:	movq   $0x5,0xc10(%rsp)
  47ddb1:	mov    $0x5,%edx
  47ddb6:	lea    0x8(%rsp),%rdi
  47ddbb:	lea    0x810(%rsp),%rsi
  47ddc3:	call   696b00 <core::str::converts::from_utf8>
  47ddc8:	cmpl   $0x1,0x8(%rsp)
  47ddcd:	je     47de2b <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x19b>
  47ddcf:	mov    0x10(%rsp),%rdi
  47ddd4:	mov    0x18(%rsp),%rax
  47ddd9:	cmp    $0x400,%rax
  47dddf:	mov    $0x400,%esi
  47dde4:	cmovb  %rax,%rsi
  47dde8:	test   %rax,%rax
  47ddeb:	je     47de02 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x172>
  47dded:	nopl   (%rax)
  47ddf0:	cmp    %rax,%rsi
  47ddf3:	jae    47de02 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x172>
  47ddf5:	cmpb   $0xbf,(%rdi,%rsi,1)
  47ddf9:	jg     47de02 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x172>
  47ddfb:	dec    %rsi
  47ddfe:	jne    47ddf0 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x160>
  47de00:	xor    %esi,%esi
  47de02:	mov    0x58222f(%rip),%rax        # a00038 <_DYNAMIC+0x5fe50>
  47de09:	mov    (%rax),%rax
  47de0c:	test   %rax,%rax
  47de0f:	je     47de6e <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x1de>
  47de11:	call   *0x88(%rax)
  47de17:	mov    %r14,%rax
  47de1a:	mov    %rbx,%rdx
  47de1d:	add    $0xc18,%rsp
  47de24:	pop    %rbx
  47de25:	pop    %r14
  47de27:	pop    %r15
  47de29:	pop    %rbp
  47de2a:	ret
  47de2b:	mov    0x10(%rsp),%rax
  47de30:	mov    0x18(%rsp),%rcx
  47de35:	mov    %rcx,0x418(%rsp)
  47de3d:	mov    %rax,0x410(%rsp)
  47de45:	lea    0x3e5bc3(%rip),%rdi        # 863a0f <anon.55b2096fce70f764b67d5f98016630b8.22.llvm.15975230346321710139>
  47de4c:	lea    0x5b15dd(%rip),%rcx        # a2f430 <anon.55b2096fce70f764b67d5f98016630b8.24.llvm.15975230346321710139>
  47de53:	lea    0x5b15f6(%rip),%r8        # a2f450 <anon.55b2096fce70f764b67d5f98016630b8.26.llvm.15975230346321710139>
  47de5a:	lea    0x410(%rsp),%rdx
  47de62:	mov    $0x2b,%esi
  47de67:	call   698770 <core::result::unwrap_failed>
  47de6c:	jmp    47de86 <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x1f6>
  47de6e:	lea    0x3e52b7(%rip),%rdi        # 86312c <anon.afbcb67d570395342e5c7b93cc9f14b2.30.llvm.5541347225946096535>
  47de75:	lea    0x5b0d2c(%rip),%rdx        # a2eba8 <anon.afbcb67d570395342e5c7b93cc9f14b2.31.llvm.5541347225946096535>
  47de7c:	mov    $0x53,%esi
  47de81:	call   6993b0 <core::panicking::panic_fmt>
  47de86:	ud2
  47de88:	endbr64
  47de8c:	mov    %rax,%r15
  47de8f:	test   %ebp,%ebp
  47de91:	jne    47deaa <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x21a>
  47de93:	call   6c1880 <ostd::arch::irq::ops::enable_local>
  47de98:	jmp    47deaa <ostd::panic::catch_unwind::<(), <aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}>+0x21a>
  47de9a:	endbr64
  47de9e:	call   6991bb <core::panicking::panic_in_cleanup>
  47dea3:	endbr64
  47dea7:	mov    %rax,%r15
  47deaa:	mov    %r14,%rdi
  47dead:	mov    %rbx,%rsi
  47deb0:	call   47a590 <core::ptr::drop_glue::<core::result::Result<(), alloc::boxed::Box<dyn core::any::Any + core::marker::Send>>>>
  47deb5:	mov    %r15,%rdi
  47deb8:	call   6e7070 <_Unwind_Resume>
  47debd:	endbr64
  47dec1:	call   6991bb <core::panicking::panic_in_cleanup>
