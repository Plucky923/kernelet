
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000241557 <__kernelet_cpu_access_start+0x41336>:
  241557:	48 8b 05 42 b8 7f 00 	mov    0x7fb842(%rip),%rax        # a3cda0 <KERNELET_BOOT_ARGS>
  24155e:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  241564:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  241568:	48 c1 e9 10          	shr    $0x10,%rcx
  24156c:	0f b7 c9             	movzwl %cx,%ecx
  24156f:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  241576:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  24157e:	48 89 c2             	mov    %rax,%rdx
  241581:	e9 33 ae 48 00       	jmp    6cc3b9 <user_event_entry+0x129>
