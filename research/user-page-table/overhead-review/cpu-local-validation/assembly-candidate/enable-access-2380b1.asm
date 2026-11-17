
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002380b1 <__kernelet_cpu_access_start+0x37e90>:
  2380b1:	48 8b 05 18 4e 80 00 	mov    0x804e18(%rip),%rax        # a3ced0 <KERNELET_BOOT_ARGS>
  2380b8:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  2380be:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  2380c2:	48 c1 e9 10          	shr    $0x10,%rcx
  2380c6:	0f b7 c9             	movzwl %cx,%ecx
  2380c9:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  2380d0:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  2380d8:	c7 40 54 00 00 00 00 	movl   $0x0,0x54(%rax)
  2380df:	48 8b 10             	mov    (%rax),%rdx
  2380e2:	e9 b3 d6 48 00       	jmp    6c579a <ostd::arch::irq::ops::enable_local+0xa>
