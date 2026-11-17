
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000024101b <__kernelet_cpu_access_start+0x40dfa>:
  24101b:	48 8b 05 7e bd 7f 00 	mov    0x7fbd7e(%rip),%rax        # a3cda0 <KERNELET_BOOT_ARGS>
  241022:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  241028:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  24102c:	48 c1 e9 10          	shr    $0x10,%rcx
  241030:	0f b7 c9             	movzwl %cx,%ecx
  241033:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  24103a:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  241042:	48 89 c2             	mov    %rax,%rdx
  241045:	e9 66 7a 48 00       	jmp    6c8ab0 <ostd::arch::irq::ops::enable_local+0x80>
