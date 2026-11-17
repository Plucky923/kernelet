
research/user-page-table/results/syscall-2026-11-17/baseline/endovisor.ko:     file format elf64-x86-64


Disassembly of section .text:

0000000000009850 <do_user_run_on_linux>:
    9850:	4c 8b 4f 28          	mov    0x28(%rdi),%r9
    9854:	48 89 f8             	mov    %rdi,%rax
    9857:	41 0f b6 b1 55 10 00 	movzbl 0x1055(%r9),%esi
    985e:	00 
    985f:	40 84 f6             	test   %sil,%sil
    9862:	0f 85 52 01 00 00    	jne    99ba <do_user_run_on_linux+0x16a>
    9868:	65 48 8b 0d 00 00 00 	mov    %gs:0x0(%rip),%rcx        # 9870 <do_user_run_on_linux+0x20>
    986f:	00 
    9870:	48 f7 01 04 00 00 00 	testq  $0x4,(%rcx)
    9877:	0f 85 30 01 00 00    	jne    99ad <do_user_run_on_linux+0x15d>
    987d:	49 ba ff ef ff ff ff 	movabs $0x7fffffffefff,%r10
    9884:	7f 00 00 
    9887:	48 8b 78 68          	mov    0x68(%rax),%rdi
    988b:	48 8b 97 90 00 00 00 	mov    0x90(%rdi),%rdx
    9892:	81 e2 d5 0d 24 00    	and    $0x240dd5,%edx
    9898:	48 81 ca 02 02 00 00 	or     $0x202,%rdx
    989f:	4c 3b 97 80 00 00 00 	cmp    0x80(%rdi),%r10
    98a6:	73 5e                	jae    9906 <do_user_run_on_linux+0xb6>
    98a8:	48 89 97 90 00 00 00 	mov    %rdx,0x90(%rdi)
    98af:	31 d2                	xor    %edx,%edx
    98b1:	66 c7 87 88 00 00 00 	movw   $0x33,0x88(%rdi)
    98b8:	33 00 
    98ba:	66 c7 87 a0 00 00 00 	movw   $0x2b,0xa0(%rdi)
    98c1:	2b 00 
    98c3:	48 c7 47 78 ff ff ff 	movq   $0xffffffffffffffff,0x78(%rdi)
    98ca:	ff 
    98cb:	48 c7 80 d8 00 00 00 	movq   $0xd,0xd8(%rax)
    98d2:	0d 00 00 00 
    98d6:	48 89 90 e0 00 00 00 	mov    %rdx,0xe0(%rax)
    98dd:	48 89 90 e8 00 00 00 	mov    %rdx,0xe8(%rax)
    98e4:	c6 80 d0 00 00 00 01 	movb   $0x1,0xd0(%rax)
    98eb:	f0 80 09 02          	lock orb $0x2,(%rcx)
    98ef:	c7 40 38 02 00 00 00 	movl   $0x2,0x38(%rax)
    98f6:	48 8b 40 40          	mov    0x40(%rax),%rax
    98fa:	31 c9                	xor    %ecx,%ecx
    98fc:	89 48 54             	mov    %ecx,0x54(%rax)
    98ff:	e8 00 00 00 00       	call   9904 <do_user_run_on_linux+0xb4>
    9904:	0f 0b                	ud2
    9906:	4c 8b 87 98 00 00 00 	mov    0x98(%rdi),%r8
    990d:	49 c1 f8 2f          	sar    $0x2f,%r8
    9911:	49 83 c0 01          	add    $0x1,%r8
    9915:	49 83 f8 01          	cmp    $0x1,%r8
    9919:	77 8d                	ja     98a8 <do_user_run_on_linux+0x58>
    991b:	41 b8 33 00 00 00    	mov    $0x33,%r8d
    9921:	41 bb 2b 00 00 00    	mov    $0x2b,%r11d
    9927:	0f b6 70 70          	movzbl 0x70(%rax),%esi
    992b:	48 89 97 90 00 00 00 	mov    %rdx,0x90(%rdi)
    9932:	66 44 89 87 88 00 00 	mov    %r8w,0x88(%rdi)
    9939:	00 
    993a:	66 44 89 9f a0 00 00 	mov    %r11w,0xa0(%rdi)
    9941:	00 
    9942:	48 c7 47 78 ff ff ff 	movq   $0xffffffffffffffff,0x78(%rdi)
    9949:	ff 
    994a:	c7 40 38 02 00 00 00 	movl   $0x2,0x38(%rax)
    9951:	48 8b 40 40          	mov    0x40(%rax),%rax
    9955:	c7 40 54 00 00 00 00 	movl   $0x0,0x54(%rax)
    995c:	40 84 f6             	test   %sil,%sil
    995f:	74 9e                	je     98ff <do_user_run_on_linux+0xaf>
    9961:	48 8b 87 80 00 00 00 	mov    0x80(%rdi),%rax
    9968:	48 3b 47 58          	cmp    0x58(%rdi),%rax
    996c:	75 32                	jne    99a0 <do_user_run_on_linux+0x150>
    996e:	48 8b 97 90 00 00 00 	mov    0x90(%rdi),%rdx
    9975:	48 39 57 30          	cmp    %rdx,0x30(%rdi)
    9979:	75 25                	jne    99a0 <do_user_run_on_linux+0x150>
    997b:	66 83 bf 88 00 00 00 	cmpw   $0x33,0x88(%rdi)
    9982:	33 
    9983:	75 1b                	jne    99a0 <do_user_run_on_linux+0x150>
    9985:	66 83 bf a0 00 00 00 	cmpw   $0x2b,0xa0(%rdi)
    998c:	2b 
    998d:	75 11                	jne    99a0 <do_user_run_on_linux+0x150>
    998f:	f7 c2 00 01 01 00    	test   $0x10100,%edx
    9995:	75 09                	jne    99a0 <do_user_run_on_linux+0x150>
    9997:	49 39 c2             	cmp    %rax,%r10
    999a:	0f 83 5f ff ff ff    	jae    98ff <do_user_run_on_linux+0xaf>
    99a0:	f0 49 ff 81 28 16 00 	lock incq 0x1628(%r9)
    99a7:	00 
    99a8:	e9 52 ff ff ff       	jmp    98ff <do_user_run_on_linux+0xaf>
    99ad:	f6 81 59 07 00 00 01 	testb  $0x1,0x759(%rcx)
    99b4:	0f 84 c3 fe ff ff    	je     987d <do_user_run_on_linux+0x2d>
    99ba:	48 89 c7             	mov    %rax,%rdi
    99bd:	e8 00 00 00 00       	call   99c2 <do_user_run_on_linux+0x172>

Disassembly of section .exit.text:

Disassembly of section .text.unlikely:

Disassembly of section .init.text:

Disassembly of section .altinstr_replacement:
