
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000241b83 <__kernelet_cpu_access_start+0x41962>:
  241b83:	48 8b 05 16 b2 7f 00 	mov    0x7fb216(%rip),%rax        # a3cda0 <KERNELET_BOOT_ARGS>
  241b8a:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  241b90:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  241b94:	48 c1 e9 10          	shr    $0x10,%rcx
  241b98:	0f b7 c9             	movzwl %cx,%ecx
  241b9b:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  241ba2:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  241baa:	8b 68 54             	mov    0x54(%rax),%ebp
  241bad:	e9 0a d2 48 00       	jmp    6cedbc <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0xc>
