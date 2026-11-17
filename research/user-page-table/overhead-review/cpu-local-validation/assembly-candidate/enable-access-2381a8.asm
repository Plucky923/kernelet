
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002381a8 <__kernelet_cpu_access_start+0x37f87>:
  2381a8:	48 8b 0d 21 4d 80 00 	mov    0x804d21(%rip),%rcx        # a3ced0 <KERNELET_BOOT_ARGS>
  2381af:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  2381b5:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  2381b9:	48 c1 ea 10          	shr    $0x10,%rdx
  2381bd:	0f b7 d2             	movzwl %dx,%edx
  2381c0:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  2381c7:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  2381cf:	48 89 ce             	mov    %rcx,%rsi
  2381d2:	e9 4b d6 48 00       	jmp    6c5822 <ostd::arch::irq::ops::enable_local+0x92>
