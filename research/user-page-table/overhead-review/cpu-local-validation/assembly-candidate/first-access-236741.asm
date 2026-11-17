
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000236741 <__kernelet_cpu_access_start+0x36520>:
  236741:	48 8b 05 88 67 80 00 	mov    0x806788(%rip),%rax        # a3ced0 <KERNELET_BOOT_ARGS>
  236748:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  23674e:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  236752:	48 c1 e9 10          	shr    $0x10,%rcx
  236756:	0f b7 c9             	movzwl %cx,%ecx
  236759:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  236760:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  236768:	48 89 c2             	mov    %rax,%rdx
  23676b:	e9 7c 4f 48 00       	jmp    6bb6ec <first_user_task_entry+0xdc>
