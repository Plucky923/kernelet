
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002367aa <__kernelet_cpu_access_start+0x36589>:
  2367aa:	48 8b 0d 1f 67 80 00 	mov    0x80671f(%rip),%rcx        # a3ced0 <KERNELET_BOOT_ARGS>
  2367b1:	8b b1 bc 00 00 00    	mov    0xbc(%rcx),%esi
  2367b7:	65 48 8b 36          	mov    %gs:(%rsi),%rsi
  2367bb:	48 c1 ee 10          	shr    $0x10,%rsi
  2367bf:	0f b7 f6             	movzwl %si,%esi
  2367c2:	48 69 f6 80 00 00 00 	imul   $0x80,%rsi,%rsi
  2367c9:	48 8d 8c 31 00 10 00 00 	lea    0x1000(%rcx,%rsi,1),%rcx
  2367d1:	48 8b 41 68          	mov    0x68(%rcx),%rax
  2367d5:	48 89 ca             	mov    %rcx,%rdx
  2367d8:	e9 c0 50 48 00       	jmp    6bb89d <user_event_entry+0x1d>
