
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002386dc <__kernelet_cpu_access_start+0x384bb>:
  2386dc:	48 8b 0d ad 47 80 00 	mov    0x8047ad(%rip),%rcx        # a3ce90 <KERNELET_BOOT_ARGS>
  2386e3:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  2386e9:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  2386ed:	48 c1 ea 10          	shr    $0x10,%rdx
  2386f1:	0f b7 d2             	movzwl %dx,%edx
  2386f4:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  2386fb:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  238703:	48 89 ce             	mov    %rcx,%rsi
  238706:	e9 d7 98 48 00       	jmp    6c1fe2 <ostd::arch::irq::ops::enable_local+0x92>
