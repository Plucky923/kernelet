
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002386ad <__kernelet_cpu_access_start+0x3848c>:
  2386ad:	48 8b 05 dc 47 80 00 	mov    0x8047dc(%rip),%rax        # a3ce90 <KERNELET_BOOT_ARGS>
  2386b4:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  2386ba:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  2386be:	48 c1 e9 10          	shr    $0x10,%rcx
  2386c2:	0f b7 c9             	movzwl %cx,%ecx
  2386c5:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  2386cc:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  2386d4:	48 89 c2             	mov    %rax,%rdx
  2386d7:	e9 ea 98 48 00       	jmp    6c1fc6 <ostd::arch::irq::ops::enable_local+0x76>
