
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000241521 <__kernelet_cpu_access_start+0x41300>:
  241521:	4c 8b 05 78 b8 7f 00 	mov    0x7fb878(%rip),%r8        # a3cda0 <KERNELET_BOOT_ARGS>
  241528:	45 8b 88 bc 00 00 00 	mov    0xbc(%r8),%r9d
  24152f:	65 4d 8b 09          	mov    %gs:(%r9),%r9
  241533:	49 c1 e9 10          	shr    $0x10,%r9
  241537:	45 0f b7 c9          	movzwl %r9w,%r9d
  24153b:	4d 69 c9 80 00 00 00 	imul   $0x80,%r9,%r9
  241542:	4f 8d 84 08 00 10 00 00 	lea    0x1000(%r8,%r9,1),%r8
  24154a:	4d 8b 40 68          	mov    0x68(%r8),%r8
  24154e:	49 8b 34 38          	mov    (%r8,%rdi,1),%rsi
  241552:	e9 d1 ad 48 00       	jmp    6cc328 <user_event_entry+0x98>
