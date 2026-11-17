
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000241be1 <__kernelet_cpu_access_start+0x419c0>:
  241be1:	48 8b 15 b8 b1 7f 00 	mov    0x7fb1b8(%rip),%rdx        # a3cda0 <KERNELET_BOOT_ARGS>
  241be8:	8b b2 bc 00 00 00    	mov    0xbc(%rdx),%esi
  241bee:	65 48 8b 36          	mov    %gs:(%rsi),%rsi
  241bf2:	48 c1 ee 10          	shr    $0x10,%rsi
  241bf6:	0f b7 f6             	movzwl %si,%esi
  241bf9:	48 69 f6 80 00 00 00 	imul   $0x80,%rsi,%rsi
  241c00:	48 8d 94 32 00 10 00 00 	lea    0x1000(%rdx,%rsi,1),%rdx
  241c08:	48 8b 52 68          	mov    0x68(%rdx),%rdx
  241c0c:	29 0c 02             	sub    %ecx,(%rdx,%rax,1)
  241c0f:	e9 ce d1 48 00       	jmp    6cede2 <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0x32>
