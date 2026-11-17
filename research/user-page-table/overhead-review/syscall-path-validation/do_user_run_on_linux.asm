
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/syscall-path-validation/endovisor-release.ko:     file format elf64-x86-64


Disassembly of section .text:

0000000000009130 <do_user_run_on_linux>:
    9130:	4c 8b 4f 28          	mov    0x28(%rdi),%r9
    9134:	48 89 f8             	mov    %rdi,%rax
    9137:	41 0f b6 b1 55 10 00 	movzbl 0x1055(%r9),%esi
    913e:	00 
    913f:	40 84 f6             	test   %sil,%sil
    9142:	0f 85 52 01 00 00    	jne    929a <do_user_run_on_linux+0x16a>
    9148:	65 48 8b 0d 00 00 00 	mov    %gs:0x0(%rip),%rcx        # 9150 <do_user_run_on_linux+0x20>
    914f:	00 
			914c: R_X86_64_PC32	const_pcpu_hot-0x4
    9150:	48 f7 01 04 00 00 00 	testq  $0x4,(%rcx)
    9157:	0f 85 30 01 00 00    	jne    928d <do_user_run_on_linux+0x15d>
    915d:	49 ba ff ef ff ff ff 	movabs $0x7fffffffefff,%r10
    9164:	7f 00 00 
    9167:	48 8b 78 68          	mov    0x68(%rax),%rdi
    916b:	48 8b 97 90 00 00 00 	mov    0x90(%rdi),%rdx
    9172:	81 e2 d5 0d 24 00    	and    $0x240dd5,%edx
    9178:	48 81 ca 02 02 00 00 	or     $0x202,%rdx
    917f:	4c 3b 97 80 00 00 00 	cmp    0x80(%rdi),%r10
    9186:	73 5e                	jae    91e6 <do_user_run_on_linux+0xb6>
    9188:	48 89 97 90 00 00 00 	mov    %rdx,0x90(%rdi)
    918f:	31 d2                	xor    %edx,%edx
    9191:	66 c7 87 88 00 00 00 	movw   $0x33,0x88(%rdi)
    9198:	33 00 
    919a:	66 c7 87 a0 00 00 00 	movw   $0x2b,0xa0(%rdi)
    91a1:	2b 00 
    91a3:	48 c7 47 78 ff ff ff 	movq   $0xffffffffffffffff,0x78(%rdi)
    91aa:	ff 
    91ab:	48 c7 80 c0 00 00 00 	movq   $0xd,0xc0(%rax)
    91b2:	0d 00 00 00 
    91b6:	48 89 90 c8 00 00 00 	mov    %rdx,0xc8(%rax)
    91bd:	48 89 90 d0 00 00 00 	mov    %rdx,0xd0(%rax)
    91c4:	c6 80 b8 00 00 00 01 	movb   $0x1,0xb8(%rax)
    91cb:	f0 80 09 02          	lock orb $0x2,(%rcx)
    91cf:	c7 40 38 02 00 00 00 	movl   $0x2,0x38(%rax)
    91d6:	48 8b 40 40          	mov    0x40(%rax),%rax
    91da:	31 c9                	xor    %ecx,%ecx
    91dc:	89 48 54             	mov    %ecx,0x54(%rax)
    91df:	e8 00 00 00 00       	call   91e4 <do_user_run_on_linux+0xb4>
			91e0: R_X86_64_PLT32	return_to_user-0x4
    91e4:	0f 0b                	ud2
    91e6:	4c 8b 87 98 00 00 00 	mov    0x98(%rdi),%r8
    91ed:	49 c1 f8 2f          	sar    $0x2f,%r8
    91f1:	49 83 c0 01          	add    $0x1,%r8
    91f5:	49 83 f8 01          	cmp    $0x1,%r8
    91f9:	77 8d                	ja     9188 <do_user_run_on_linux+0x58>
    91fb:	41 b8 33 00 00 00    	mov    $0x33,%r8d
    9201:	41 bb 2b 00 00 00    	mov    $0x2b,%r11d
    9207:	0f b6 70 70          	movzbl 0x70(%rax),%esi
    920b:	48 89 97 90 00 00 00 	mov    %rdx,0x90(%rdi)
    9212:	66 44 89 87 88 00 00 	mov    %r8w,0x88(%rdi)
    9219:	00 
    921a:	66 44 89 9f a0 00 00 	mov    %r11w,0xa0(%rdi)
    9221:	00 
    9222:	48 c7 47 78 ff ff ff 	movq   $0xffffffffffffffff,0x78(%rdi)
    9229:	ff 
    922a:	c7 40 38 02 00 00 00 	movl   $0x2,0x38(%rax)
    9231:	48 8b 40 40          	mov    0x40(%rax),%rax
    9235:	c7 40 54 00 00 00 00 	movl   $0x0,0x54(%rax)
    923c:	40 84 f6             	test   %sil,%sil
    923f:	74 9e                	je     91df <do_user_run_on_linux+0xaf>
    9241:	48 8b 87 80 00 00 00 	mov    0x80(%rdi),%rax
    9248:	48 3b 47 58          	cmp    0x58(%rdi),%rax
    924c:	75 32                	jne    9280 <do_user_run_on_linux+0x150>
    924e:	48 8b 97 90 00 00 00 	mov    0x90(%rdi),%rdx
    9255:	48 39 57 30          	cmp    %rdx,0x30(%rdi)
    9259:	75 25                	jne    9280 <do_user_run_on_linux+0x150>
    925b:	66 83 bf 88 00 00 00 	cmpw   $0x33,0x88(%rdi)
    9262:	33 
    9263:	75 1b                	jne    9280 <do_user_run_on_linux+0x150>
    9265:	66 83 bf a0 00 00 00 	cmpw   $0x2b,0xa0(%rdi)
    926c:	2b 
    926d:	75 11                	jne    9280 <do_user_run_on_linux+0x150>
    926f:	f7 c2 00 01 01 00    	test   $0x10100,%edx
    9275:	75 09                	jne    9280 <do_user_run_on_linux+0x150>
    9277:	49 39 c2             	cmp    %rax,%r10
    927a:	0f 83 5f ff ff ff    	jae    91df <do_user_run_on_linux+0xaf>
    9280:	f0 49 ff 81 28 16 00 	lock incq 0x1628(%r9)
    9287:	00 
    9288:	e9 52 ff ff ff       	jmp    91df <do_user_run_on_linux+0xaf>
    928d:	f6 81 59 07 00 00 01 	testb  $0x1,0x759(%rcx)
    9294:	0f 84 c3 fe ff ff    	je     915d <do_user_run_on_linux+0x2d>
    929a:	48 89 c7             	mov    %rax,%rdi
    929d:	e8 00 00 00 00       	call   92a2 <do_user_run_on_linux+0x172>
			929e: R_X86_64_PLT32	carrier_die-0x4

Disassembly of section .init.text:

Disassembly of section .exit.text:

Disassembly of section .text.unlikely:

Disassembly of section .altinstr_replacement:
