
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000238145 <__kernelet_cpu_access_start+0x37f24>:
  238145:	48 8b 0d 84 4d 80 00 	mov    0x804d84(%rip),%rcx        # a3ced0 <KERNELET_BOOT_ARGS>
  23814c:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  238152:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  238156:	48 c1 ea 10          	shr    $0x10,%rdx
  23815a:	0f b7 d2             	movzwl %dx,%edx
  23815d:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  238164:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  23816c:	48 8b 49 68          	mov    0x68(%rcx),%rcx
  238170:	48 8b 34 01          	mov    (%rcx,%rax,1),%rsi
  238174:	e9 77 d6 48 00       	jmp    6c57f0 <ostd::arch::irq::ops::enable_local+0x60>
