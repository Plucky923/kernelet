
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/syscall-path-validation/endovisor-release.ko:     file format elf64-x86-64


Disassembly of section .text:

0000000000007720 <on_syscall>:
    7720:	65 48 8b 15 00 00 00 	mov    %gs:0x0(%rip),%rdx        # 7728 <on_syscall+0x8>
    7727:	00 
			7724: R_X86_64_PC32	const_pcpu_hot-0x4
    7728:	48 89 f8             	mov    %rdi,%rax
    772b:	48 8b ba b0 07 00 00 	mov    0x7b0(%rdx),%rdi
    7732:	48 85 ff             	test   %rdi,%rdi
    7735:	74 41                	je     7778 <on_syscall+0x58>
    7737:	83 7f 38 02          	cmpl   $0x2,0x38(%rdi)
    773b:	75 3b                	jne    7778 <on_syscall+0x58>
    773d:	66 83 b8 88 00 00 00 	cmpw   $0x33,0x88(%rax)
    7744:	33 
    7745:	75 42                	jne    7789 <on_syscall+0x69>
    7747:	48 8b 4f 28          	mov    0x28(%rdi),%rcx
    774b:	80 b9 55 10 00 00 00 	cmpb   $0x0,0x1055(%rcx)
    7752:	75 30                	jne    7784 <on_syscall+0x64>
    7754:	48 f7 02 04 00 00 00 	testq  $0x4,(%rdx)
    775b:	75 1e                	jne    777b <on_syscall+0x5b>
    775d:	48 8b 50 78          	mov    0x78(%rax),%rdx
    7761:	48 c7 40 78 ff ff ff 	movq   $0xffffffffffffffff,0x78(%rax)
    7768:	ff 
    7769:	31 f6                	xor    %esi,%esi
    776b:	48 89 50 50          	mov    %rdx,0x50(%rax)
    776f:	c6 47 70 01          	movb   $0x1,0x70(%rdi)
    7773:	e8 a8 fe ff ff       	call   7620 <enter_user_event>
    7778:	31 c0                	xor    %eax,%eax
    777a:	c3                   	ret
    777b:	f6 82 59 07 00 00 01 	testb  $0x1,0x759(%rdx)
    7782:	74 d9                	je     775d <on_syscall+0x3d>
    7784:	e8 00 00 00 00       	call   7789 <on_syscall+0x69>
			7785: R_X86_64_PLT32	carrier_die-0x4
    7789:	48 c7 87 c0 00 00 00 	movq   $0xd,0xc0(%rdi)
    7790:	0d 00 00 00 
    7794:	48 c7 87 c8 00 00 00 	movq   $0x0,0xc8(%rdi)
    779b:	00 00 00 00 
    779f:	48 c7 87 d0 00 00 00 	movq   $0x0,0xd0(%rdi)
    77a6:	00 00 00 00 
    77aa:	c6 87 b8 00 00 00 01 	movb   $0x1,0xb8(%rdi)
    77b1:	f0 80 0a 02          	lock orb $0x2,(%rdx)
    77b5:	b8 01 00 00 00       	mov    $0x1,%eax
    77ba:	c3                   	ret

Disassembly of section .init.text:

Disassembly of section .exit.text:

Disassembly of section .text.unlikely:

Disassembly of section .altinstr_replacement:
