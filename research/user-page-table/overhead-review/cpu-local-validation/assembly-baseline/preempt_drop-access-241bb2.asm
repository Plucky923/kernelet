
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000241bb2 <__kernelet_cpu_access_start+0x41991>:
  241bb2:	48 8b 0d e7 b1 7f 00 	mov    0x7fb1e7(%rip),%rcx        # a3cda0 <KERNELET_BOOT_ARGS>
  241bb9:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  241bbf:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  241bc3:	48 c1 ea 10          	shr    $0x10,%rdx
  241bc7:	0f b7 d2             	movzwl %dx,%edx
  241bca:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  241bd1:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  241bd9:	89 41 54             	mov    %eax,0x54(%rcx)
  241bdc:	e9 e9 d1 48 00       	jmp    6cedca <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0x1a>
