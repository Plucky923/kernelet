
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000023864a <__kernelet_cpu_access_start+0x38429>:
  23864a:	48 8b 05 3f 48 80 00 	mov    0x80483f(%rip),%rax        # a3ce90 <KERNELET_BOOT_ARGS>
  238651:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  238657:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  23865b:	48 c1 e9 10          	shr    $0x10,%rcx
  23865f:	0f b7 c9             	movzwl %cx,%ecx
  238662:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  238669:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  238671:	48 89 c2             	mov    %rax,%rdx
  238674:	e9 ff 98 48 00       	jmp    6c1f78 <ostd::arch::irq::ops::enable_local+0x28>
