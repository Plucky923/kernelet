
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000241494 <__kernelet_cpu_access_start+0x41273>:
  241494:	48 8b 05 05 b9 7f 00 	mov    0x7fb905(%rip),%rax        # a3cda0 <KERNELET_BOOT_ARGS>
  24149b:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  2414a1:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  2414a5:	48 c1 e9 10          	shr    $0x10,%rcx
  2414a9:	0f b7 c9             	movzwl %cx,%ecx
  2414ac:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  2414b3:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  2414bb:	48 89 c2             	mov    %rax,%rdx
  2414be:	e9 61 ac 48 00       	jmp    6cc124 <first_user_task_entry+0x94>
