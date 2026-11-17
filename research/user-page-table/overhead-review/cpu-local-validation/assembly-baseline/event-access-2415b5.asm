
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002415b5 <__kernelet_cpu_access_start+0x41394>:
  2415b5:	48 8b 15 e4 b7 7f 00 	mov    0x7fb7e4(%rip),%rdx        # a3cda0 <KERNELET_BOOT_ARGS>
  2415bc:	8b b2 bc 00 00 00    	mov    0xbc(%rdx),%esi
  2415c2:	65 48 8b 36          	mov    %gs:(%rsi),%rsi
  2415c6:	48 c1 ee 10          	shr    $0x10,%rsi
  2415ca:	0f b7 f6             	movzwl %si,%esi
  2415cd:	48 69 f6 80 00 00 00 	imul   $0x80,%rsi,%rsi
  2415d4:	48 8d 94 32 00 10 00 00 	lea    0x1000(%rdx,%rsi,1),%rdx
  2415dc:	89 4a 54             	mov    %ecx,0x54(%rdx)
  2415df:	e9 03 ae 48 00       	jmp    6cc3e7 <user_event_entry+0x157>
