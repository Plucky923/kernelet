
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000238179 <__kernelet_cpu_access_start+0x37f58>:
  238179:	48 8b 05 50 4d 80 00 	mov    0x804d50(%rip),%rax        # a3ced0 <KERNELET_BOOT_ARGS>
  238180:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  238186:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  23818a:	48 c1 e9 10          	shr    $0x10,%rcx
  23818e:	0f b7 c9             	movzwl %cx,%ecx
  238191:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  238198:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  2381a0:	48 89 c2             	mov    %rax,%rdx
  2381a3:	e9 5e d6 48 00       	jmp    6c5806 <ostd::arch::irq::ops::enable_local+0x76>
