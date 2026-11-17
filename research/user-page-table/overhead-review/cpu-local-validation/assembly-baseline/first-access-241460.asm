
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000241460 <__kernelet_cpu_access_start+0x4123f>:
  241460:	48 8b 15 39 b9 7f 00 	mov    0x7fb939(%rip),%rdx        # a3cda0 <KERNELET_BOOT_ARGS>
  241467:	8b b2 bc 00 00 00    	mov    0xbc(%rdx),%esi
  24146d:	65 48 8b 36          	mov    %gs:(%rsi),%rsi
  241471:	48 c1 ee 10          	shr    $0x10,%rsi
  241475:	0f b7 f6             	movzwl %si,%esi
  241478:	48 69 f6 80 00 00 00 	imul   $0x80,%rsi,%rsi
  24147f:	48 8d 94 32 00 10 00 00 	lea    0x1000(%rdx,%rsi,1),%rdx
  241487:	48 8b 52 68          	mov    0x68(%rdx),%rdx
  24148b:	48 8b 04 0a          	mov    (%rdx,%rcx,1),%rax
  24148f:	e9 26 ac 48 00       	jmp    6cc0ba <first_user_task_entry+0x2a>
