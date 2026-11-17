
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000023789d <__kernelet_cpu_access_start+0x3767c>:
  23789d:	48 8b 05 ec 55 80 00 	mov    0x8055ec(%rip),%rax        # a3ce90 <KERNELET_BOOT_ARGS>
  2378a4:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  2378aa:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  2378ae:	48 c1 e9 10          	shr    $0x10,%rcx
  2378b2:	0f b7 c9             	movzwl %cx,%ecx
  2378b5:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  2378bc:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  2378c4:	8b 50 54             	mov    0x54(%rax),%edx
  2378c7:	85 d2                	test   %edx,%edx
  2378c9:	75 07                	jne    2378d2 <__kernelet_cpu_access_start+0x376b1>
  2378cb:	c7 40 54 01 00 00 00 	movl   $0x1,0x54(%rax)
  2378d2:	e9 65 66 48 00       	jmp    6bdf3c <first_user_task_entry+0xfc>
