
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002380e7 <__kernelet_cpu_access_start+0x37ec6>:
  2380e7:	48 8b 05 e2 4d 80 00 	mov    0x804de2(%rip),%rax        # a3ced0 <KERNELET_BOOT_ARGS>
  2380ee:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  2380f4:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  2380f8:	48 c1 e9 10          	shr    $0x10,%rcx
  2380fc:	0f b7 c9             	movzwl %cx,%ecx
  2380ff:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  238106:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  23810e:	48 89 c2             	mov    %rax,%rdx
  238111:	e9 92 d6 48 00       	jmp    6c57a8 <ostd::arch::irq::ops::enable_local+0x18>
