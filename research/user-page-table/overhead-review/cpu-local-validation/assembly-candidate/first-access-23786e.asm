
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000023786e <__kernelet_cpu_access_start+0x3764d>:
  23786e:	48 8b 05 1b 56 80 00 	mov    0x80561b(%rip),%rax        # a3ce90 <KERNELET_BOOT_ARGS>
  237875:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  23787b:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  23787f:	48 c1 e9 10          	shr    $0x10,%rcx
  237883:	0f b7 c9             	movzwl %cx,%ecx
  237886:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  23788d:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  237895:	48 89 c2             	mov    %rax,%rdx
  237898:	e9 7f 66 48 00       	jmp    6bdf1c <first_user_task_entry+0xdc>
