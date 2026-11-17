
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000023870b <__kernelet_cpu_access_start+0x384ea>:
  23870b:	48 8b 0d 7e 47 80 00 	mov    0x80477e(%rip),%rcx        # a3ce90 <KERNELET_BOOT_ARGS>
  238712:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  238718:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  23871c:	48 c1 ea 10          	shr    $0x10,%rdx
  238720:	0f b7 d2             	movzwl %dx,%edx
  238723:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  23872a:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  238732:	48 8b 49 68          	mov    0x68(%rcx),%rcx
  238736:	8b 34 01             	mov    (%rcx,%rax,1),%esi
  238739:	e9 df 98 48 00       	jmp    6c201d <ostd::arch::irq::ops::enable_local+0xcd>
