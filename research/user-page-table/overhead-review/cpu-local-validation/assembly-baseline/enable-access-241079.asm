
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000241079 <__kernelet_cpu_access_start+0x40e58>:
  241079:	48 8b 0d 20 bd 7f 00 	mov    0x7fbd20(%rip),%rcx        # a3cda0 <KERNELET_BOOT_ARGS>
  241080:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  241086:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  24108a:	48 c1 ea 10          	shr    $0x10,%rdx
  24108e:	0f b7 d2             	movzwl %dx,%edx
  241091:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  241098:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  2410a0:	48 8b 49 68          	mov    0x68(%rcx),%rcx
  2410a4:	8b 34 01             	mov    (%rcx,%rax,1),%esi
  2410a7:	e9 5b 7a 48 00       	jmp    6c8b07 <ostd::arch::irq::ops::enable_local+0xd7>
