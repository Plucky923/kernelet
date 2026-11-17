
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000236770 <__kernelet_cpu_access_start+0x3654f>:
  236770:	48 8b 05 59 67 80 00 	mov    0x806759(%rip),%rax        # a3ced0 <KERNELET_BOOT_ARGS>
  236777:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  23677d:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  236781:	48 c1 e9 10          	shr    $0x10,%rcx
  236785:	0f b7 c9             	movzwl %cx,%ecx
  236788:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  23678f:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  236797:	8b 50 54             	mov    0x54(%rax),%edx
  23679a:	85 d2                	test   %edx,%edx
  23679c:	75 07                	jne    2367a5 <__kernelet_cpu_access_start+0x36584>
  23679e:	c7 40 54 01 00 00 00 	movl   $0x1,0x54(%rax)
  2367a5:	e9 62 4f 48 00       	jmp    6bb70c <first_user_task_entry+0xfc>
