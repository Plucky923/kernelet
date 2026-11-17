
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000240fe7 <__kernelet_cpu_access_start+0x40dc6>:
  240fe7:	48 8b 0d b2 bd 7f 00 	mov    0x7fbdb2(%rip),%rcx        # a3cda0 <KERNELET_BOOT_ARGS>
  240fee:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  240ff4:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  240ff8:	48 c1 ea 10          	shr    $0x10,%rdx
  240ffc:	0f b7 d2             	movzwl %dx,%edx
  240fff:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  241006:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  24100e:	48 8b 49 68          	mov    0x68(%rcx),%rcx
  241012:	48 8b 34 01          	mov    (%rcx,%rax,1),%rsi
  241016:	e9 7f 7a 48 00       	jmp    6c8a9a <ostd::arch::irq::ops::enable_local+0x6a>
