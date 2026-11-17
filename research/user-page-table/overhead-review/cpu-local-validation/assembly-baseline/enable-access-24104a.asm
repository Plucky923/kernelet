
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000024104a <__kernelet_cpu_access_start+0x40e29>:
  24104a:	48 8b 0d 4f bd 7f 00 	mov    0x7fbd4f(%rip),%rcx        # a3cda0 <KERNELET_BOOT_ARGS>
  241051:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  241057:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  24105b:	48 c1 ea 10          	shr    $0x10,%rdx
  24105f:	0f b7 d2             	movzwl %dx,%edx
  241062:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  241069:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  241071:	48 89 ce             	mov    %rcx,%rsi
  241074:	e9 53 7a 48 00       	jmp    6c8acc <ostd::arch::irq::ops::enable_local+0x9c>
