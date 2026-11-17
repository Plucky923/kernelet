
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000241586 <__kernelet_cpu_access_start+0x41365>:
  241586:	48 8b 0d 13 b8 7f 00 	mov    0x7fb813(%rip),%rcx        # a3cda0 <KERNELET_BOOT_ARGS>
  24158d:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  241593:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  241597:	48 c1 ea 10          	shr    $0x10,%rdx
  24159b:	0f b7 d2             	movzwl %dx,%edx
  24159e:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  2415a5:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  2415ad:	8b 41 54             	mov    0x54(%rcx),%eax
  2415b0:	e9 24 ae 48 00       	jmp    6cc3d9 <user_event_entry+0x149>
