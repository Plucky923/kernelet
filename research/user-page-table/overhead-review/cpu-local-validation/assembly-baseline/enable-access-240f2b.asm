
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000240f2b <__kernelet_cpu_access_start+0x40d0a>:
  240f2b:	48 8b 0d 6e be 7f 00 	mov    0x7fbe6e(%rip),%rcx        # a3cda0 <KERNELET_BOOT_ARGS>
  240f32:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  240f38:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  240f3c:	48 c1 ea 10          	shr    $0x10,%rdx
  240f40:	0f b7 d2             	movzwl %dx,%edx
  240f43:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  240f4a:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  240f52:	89 41 54             	mov    %eax,0x54(%rcx)
  240f55:	e9 e2 7a 48 00       	jmp    6c8a3c <ostd::arch::irq::ops::enable_local+0xc>
