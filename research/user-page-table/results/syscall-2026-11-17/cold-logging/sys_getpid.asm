
research/user-page-table/results/syscall-2026-11-17/cold-logging/image.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000034ca00 <aster_core::syscall::getpid::sys_getpid>:
  34ca00:	f3 0f 1e fa          	endbr64
  34ca04:	53                   	push   %rbx
  34ca05:	48 83 ec 60          	sub    $0x60,%rsp
  34ca09:	48 89 f8             	mov    %rdi,%rax
  34ca0c:	48 8b 0e             	mov    (%rsi),%rcx
  34ca0f:	48 8b 09             	mov    (%rcx),%rcx
  34ca12:	8b 89 a0 06 00 00    	mov    0x6a0(%rcx),%ecx
  34ca18:	89 4c 24 04          	mov    %ecx,0x4(%rsp)
  34ca1c:	0f b6 15 0d 05 6f 00 	movzbl 0x6f050d(%rip),%edx        # a3cf30 <ostd::log::logger::DYNAMIC_MAX_LEVEL>
  34ca23:	80 fa 07             	cmp    $0x7,%dl
  34ca26:	77 1a                	ja     34ca42 <aster_core::syscall::getpid::sys_getpid+0x42>
  34ca28:	89 c9                	mov    %ecx,%ecx
  34ca2a:	48 c7 00 00 00 00 00 	movq   $0x0,(%rax)
  34ca31:	48 89 48 08          	mov    %rcx,0x8(%rax)
  34ca35:	c7 40 10 00 00 00 00 	movl   $0x0,0x10(%rax)
  34ca3c:	48 83 c4 60          	add    $0x60,%rsp
  34ca40:	5b                   	pop    %rbx
  34ca41:	c3                   	ret
  34ca42:	48 8d 4c 24 04       	lea    0x4(%rsp),%rcx
  34ca47:	48 89 4c 24 08       	mov    %rcx,0x8(%rsp)
  34ca4c:	48 8d 0d 2d eb 36 00 	lea    0x36eb2d(%rip),%rcx        # 6bb580 <<u32 as core::fmt::Display>::fmt>
  34ca53:	48 89 4c 24 10       	mov    %rcx,0x10(%rsp)
  34ca58:	c6 44 24 5c 07       	movb   $0x7,0x5c(%rsp)
  34ca5d:	48 c7 44 24 18 01 00 	movq   $0x1,0x18(%rsp)
  34ca64:	00 00 
  34ca66:	48 c7 44 24 20 00 00 	movq   $0x0,0x20(%rsp)
  34ca6d:	00 00 
  34ca6f:	48 8d 0d 50 e8 4b 00 	lea    0x4be850(%rip),%rcx        # 80b2c6 <anon.51d947cc6456ba95acc74ef1934ee9ef.570.llvm.5443261001715077015>
  34ca76:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
  34ca7b:	48 8d 4c 24 08       	lea    0x8(%rsp),%rcx
  34ca80:	48 89 4c 24 30       	mov    %rcx,0x30(%rsp)
  34ca85:	48 8d 0d 47 ac 4e 00 	lea    0x4eac47(%rip),%rcx        # 8376d3 <anon.51d947cc6456ba95acc74ef1934ee9ef.571.llvm.5443261001715077015>
  34ca8c:	48 89 4c 24 38       	mov    %rcx,0x38(%rsp)
  34ca91:	48 c7 44 24 40 1b 00 	movq   $0x1b,0x40(%rsp)
  34ca98:	00 00 
  34ca9a:	48 8d 0d 4d ac 4e 00 	lea    0x4eac4d(%rip),%rcx        # 8376ee <anon.51d947cc6456ba95acc74ef1934ee9ef.572.llvm.5443261001715077015>
  34caa1:	48 89 4c 24 48       	mov    %rcx,0x48(%rsp)
  34caa6:	48 c7 44 24 50 b7 00 	movq   $0xb7,0x50(%rsp)
  34caad:	00 00 
  34caaf:	c7 44 24 58 08 00 00 	movl   $0x8,0x58(%rsp)
  34cab6:	00 
  34cab7:	48 8d 7c 24 18       	lea    0x18(%rsp),%rdi
  34cabc:	48 89 c3             	mov    %rax,%rbx
  34cabf:	e8 dc 20 39 00       	call   6deba0 <ostd::log::logger::__write_log_record>
  34cac4:	48 89 d8             	mov    %rbx,%rax
  34cac7:	8b 4c 24 04          	mov    0x4(%rsp),%ecx
  34cacb:	e9 58 ff ff ff       	jmp    34ca28 <aster_core::syscall::getpid::sys_getpid+0x28>
