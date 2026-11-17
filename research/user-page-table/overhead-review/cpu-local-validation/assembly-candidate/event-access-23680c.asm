
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000023680c <__kernelet_cpu_access_start+0x365eb>:
  23680c:	48 8b 05 bd 66 80 00 	mov    0x8066bd(%rip),%rax        # a3ced0 <KERNELET_BOOT_ARGS>
  236813:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  236819:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  23681d:	48 c1 e9 10          	shr    $0x10,%rcx
  236821:	0f b7 c9             	movzwl %cx,%ecx
  236824:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  23682b:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  236833:	8b 50 54             	mov    0x54(%rax),%edx
  236836:	85 d2                	test   %edx,%edx
  236838:	75 07                	jne    236841 <__kernelet_cpu_access_start+0x36620>
  23683a:	c7 40 54 01 00 00 00 	movl   $0x1,0x54(%rax)
  236841:	e9 bb 51 48 00       	jmp    6bba01 <user_event_entry+0x181>
