
research/user-page-table/results/syscall-2026-11-17/final/image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000406b70 <aster_core::syscall::getpid::sys_getpid>:
  406b70:	f3 0f 1e fa          	endbr64
  406b74:	53                   	push   %rbx
  406b75:	48 83 ec 60          	sub    $0x60,%rsp
  406b79:	48 89 f8             	mov    %rdi,%rax
  406b7c:	48 8b 0e             	mov    (%rsi),%rcx
  406b7f:	48 8b 09             	mov    (%rcx),%rcx
  406b82:	8b 89 a0 06 00 00    	mov    0x6a0(%rcx),%ecx
  406b88:	89 4c 24 04          	mov    %ecx,0x4(%rsp)
  406b8c:	0f b6 15 85 63 63 00 	movzbl 0x636385(%rip),%edx        # a3cf18 <ostd::log::logger::DYNAMIC_MAX_LEVEL>
  406b93:	80 fa 07             	cmp    $0x7,%dl
  406b96:	77 1a                	ja     406bb2 <aster_core::syscall::getpid::sys_getpid+0x42>
  406b98:	89 c9                	mov    %ecx,%ecx
  406b9a:	48 c7 00 00 00 00 00 	movq   $0x0,(%rax)
  406ba1:	48 89 48 08          	mov    %rcx,0x8(%rax)
  406ba5:	c7 40 10 00 00 00 00 	movl   $0x0,0x10(%rax)
  406bac:	48 83 c4 60          	add    $0x60,%rsp
  406bb0:	5b                   	pop    %rbx
  406bb1:	c3                   	ret
