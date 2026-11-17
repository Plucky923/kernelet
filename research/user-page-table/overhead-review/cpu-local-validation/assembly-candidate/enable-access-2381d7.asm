
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002381d7 <__kernelet_cpu_access_start+0x37fb6>:
  2381d7:	48 8b 0d f2 4c 80 00 	mov    0x804cf2(%rip),%rcx        # a3ced0 <KERNELET_BOOT_ARGS>
  2381de:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  2381e4:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  2381e8:	48 c1 ea 10          	shr    $0x10,%rdx
  2381ec:	0f b7 d2             	movzwl %dx,%edx
  2381ef:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  2381f6:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  2381fe:	48 8b 49 68          	mov    0x68(%rcx),%rcx
  238202:	8b 34 01             	mov    (%rcx,%rax,1),%esi
  238205:	e9 53 d6 48 00       	jmp    6c585d <ostd::arch::irq::ops::enable_local+0xcd>
