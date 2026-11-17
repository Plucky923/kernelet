
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000240fb8 <__kernelet_cpu_access_start+0x40d97>:
  240fb8:	48 8b 05 e1 bd 7f 00 	mov    0x7fbde1(%rip),%rax        # a3cda0 <KERNELET_BOOT_ARGS>
  240fbf:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  240fc5:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  240fc9:	48 c1 e9 10          	shr    $0x10,%rcx
  240fcd:	0f b7 c9             	movzwl %cx,%ecx
  240fd0:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  240fd7:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  240fdf:	48 89 c2             	mov    %rax,%rdx
  240fe2:	e9 7b 7a 48 00       	jmp    6c8a62 <ostd::arch::irq::ops::enable_local+0x32>
