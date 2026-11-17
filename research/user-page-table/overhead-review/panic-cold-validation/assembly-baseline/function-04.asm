
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image-baseline.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000004a7c90 <__ostd_user_handle>:
  4a7c90:	endbr64
  4a7c94:	push   %r15
  4a7c96:	push   %r14
  4a7c98:	push   %rbx
  4a7c99:	sub    $0x50,%rsp
  4a7c9d:	mov    %rsi,%rbx
  4a7ca0:	mov    (%rdi),%r14
  4a7ca3:	add    $0x10,%r14
  4a7ca7:	mov    %dl,0xf(%rsp)
  4a7cab:	mov    %r14,0x30(%rsp)
  4a7cb0:	mov    %rsi,0x38(%rsp)
  4a7cb5:	lea    0xf(%rsp),%rax
  4a7cba:	mov    %rax,0x40(%rsp)
  4a7cbf:	mov    %rcx,0x48(%rsp)
  4a7cc4:	lea    0x10(%rsp),%rdi
  4a7cc9:	lea    0x30(%rsp),%rsi
  4a7cce:	call   44e530 <aster_core::thread::oops::catch_panics_as_oops::<<aster_core::thread::Thread as ostd::user::kernelet_events::UserEventHandler>::handle::{closure#0}, ()>>
  4a7cd3:	mov    0x10(%rsp),%r15
  4a7cd8:	cmp    $0xffffffffffffffff,%r15
  4a7cdc:	je     4a7d15 <__ostd_user_handle+0x85>
  4a7cde:	mov    %r14,%rdi
  4a7ce1:	mov    %rbx,%rsi
  4a7ce4:	call   48bfb0 <aster_core::thread::task::exit_current_after_oops>
  4a7ce9:	test   %r15,%r15
  4a7cec:	je     4a7d00 <__ostd_user_handle+0x70>
  4a7cee:	mov    0x18(%rsp),%rsi
  4a7cf3:	mov    $0x1,%edx
  4a7cf8:	mov    %r15,%rcx
  4a7cfb:	call   6cf1e0 <<ostd::mm::heap::AllocDispatch as core::alloc::global::GlobalAlloc>::dealloc>
  4a7d00:	mov    0x28(%rsp),%rax
  4a7d05:	lock decq (%rax)
  4a7d09:	jne    4a7d15 <__ostd_user_handle+0x85>
  4a7d0b:	lea    0x28(%rsp),%rdi
  4a7d10:	call   4cb380 <<alloc::sync::Arc<aster_core::thread::Thread>>::drop_slow>
  4a7d15:	add    $0x50,%rsp
  4a7d19:	pop    %rbx
  4a7d1a:	pop    %r14
  4a7d1c:	pop    %r15
  4a7d1e:	ret
  4a7d1f:	endbr64
  4a7d23:	mov    %rax,%rbx
  4a7d26:	lea    0x10(%rsp),%rdi
  4a7d2b:	call   47a600 <core::ptr::drop_glue::<core::result::Result<(), aster_core::thread::oops::OopsInfo>>>
  4a7d30:	mov    %rbx,%rdi
  4a7d33:	call   6e7070 <_Unwind_Resume>
  4a7d38:	endbr64
  4a7d3c:	call   6991bb <core::panicking::panic_in_cleanup>
