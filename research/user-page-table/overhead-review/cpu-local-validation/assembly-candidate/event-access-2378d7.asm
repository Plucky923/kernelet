
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002378d7 <__kernelet_cpu_access_start+0x376b6>:
  2378d7:	48 8b 0d b2 55 80 00 	mov    0x8055b2(%rip),%rcx        # a3ce90 <KERNELET_BOOT_ARGS>
  2378de:	8b b1 bc 00 00 00    	mov    0xbc(%rcx),%esi
  2378e4:	65 48 8b 36          	mov    %gs:(%rsi),%rsi
  2378e8:	48 c1 ee 10          	shr    $0x10,%rsi
  2378ec:	0f b7 f6             	movzwl %si,%esi
  2378ef:	48 69 f6 80 00 00 00 	imul   $0x80,%rsi,%rsi
  2378f6:	48 8d 8c 31 00 10 00 00 	lea    0x1000(%rcx,%rsi,1),%rcx
  2378fe:	48 8b 41 68          	mov    0x68(%rcx),%rax
  237902:	48 89 ca             	mov    %rcx,%rdx
  237905:	e9 c3 67 48 00       	jmp    6be0cd <user_event_entry+0x1d>
