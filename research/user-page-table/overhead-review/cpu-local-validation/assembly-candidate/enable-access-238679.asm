
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000238679 <__kernelet_cpu_access_start+0x38458>:
  238679:	48 8b 0d 10 48 80 00 	mov    0x804810(%rip),%rcx        # a3ce90 <KERNELET_BOOT_ARGS>
  238680:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  238686:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  23868a:	48 c1 ea 10          	shr    $0x10,%rdx
  23868e:	0f b7 d2             	movzwl %dx,%edx
  238691:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  238698:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  2386a0:	48 8b 49 68          	mov    0x68(%rcx),%rcx
  2386a4:	48 8b 34 01          	mov    (%rcx,%rax,1),%rsi
  2386a8:	e9 03 99 48 00       	jmp    6c1fb0 <ostd::arch::irq::ops::enable_local+0x60>
