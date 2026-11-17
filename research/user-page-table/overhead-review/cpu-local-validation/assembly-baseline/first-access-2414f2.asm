
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002414f2 <__kernelet_cpu_access_start+0x412d1>:
  2414f2:	48 8b 15 a7 b8 7f 00 	mov    0x7fb8a7(%rip),%rdx        # a3cda0 <KERNELET_BOOT_ARGS>
  2414f9:	8b b2 bc 00 00 00    	mov    0xbc(%rdx),%esi
  2414ff:	65 48 8b 36          	mov    %gs:(%rsi),%rsi
  241503:	48 c1 ee 10          	shr    $0x10,%rsi
  241507:	0f b7 f6             	movzwl %si,%esi
  24150a:	48 69 f6 80 00 00 00 	imul   $0x80,%rsi,%rsi
  241511:	48 8d 94 32 00 10 00 00 	lea    0x1000(%rdx,%rsi,1),%rdx
  241519:	89 4a 54             	mov    %ecx,0x54(%rdx)
  24151c:	e9 31 ac 48 00       	jmp    6cc152 <first_user_task_entry+0xc2>
