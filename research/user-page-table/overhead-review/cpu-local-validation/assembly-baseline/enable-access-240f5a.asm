
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000240f5a <__kernelet_cpu_access_start+0x40d39>:
  240f5a:	48 8b 05 3f be 7f 00 	mov    0x7fbe3f(%rip),%rax        # a3cda0 <KERNELET_BOOT_ARGS>
  240f61:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  240f67:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  240f6b:	48 c1 e9 10          	shr    $0x10,%rcx
  240f6f:	0f b7 c9             	movzwl %cx,%ecx
  240f72:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  240f79:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  240f81:	48 89 c2             	mov    %rax,%rdx
  240f84:	e9 b8 7a 48 00       	jmp    6c8a41 <ostd::arch::irq::ops::enable_local+0x11>
