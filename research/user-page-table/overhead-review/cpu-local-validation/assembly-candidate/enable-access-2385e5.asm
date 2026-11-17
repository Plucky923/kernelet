
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002385e5 <__kernelet_cpu_access_start+0x383c4>:
  2385e5:	48 8b 05 a4 48 80 00 	mov    0x8048a4(%rip),%rax        # a3ce90 <KERNELET_BOOT_ARGS>
  2385ec:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  2385f2:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  2385f6:	48 c1 e9 10          	shr    $0x10,%rcx
  2385fa:	0f b7 c9             	movzwl %cx,%ecx
  2385fd:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  238604:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  23860c:	c7 40 54 00 00 00 00 	movl   $0x0,0x54(%rax)
  238613:	48 8b 10             	mov    (%rax),%rdx
  238616:	e9 3f 99 48 00       	jmp    6c1f5a <ostd::arch::irq::ops::enable_local+0xa>
