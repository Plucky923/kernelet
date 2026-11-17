
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002367dd <__kernelet_cpu_access_start+0x365bc>:
  2367dd:	48 8b 05 ec 66 80 00 	mov    0x8066ec(%rip),%rax        # a3ced0 <KERNELET_BOOT_ARGS>
  2367e4:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  2367ea:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  2367ee:	48 c1 e9 10          	shr    $0x10,%rcx
  2367f2:	0f b7 c9             	movzwl %cx,%ecx
  2367f5:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  2367fc:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  236804:	48 89 c2             	mov    %rax,%rdx
  236807:	e9 d5 51 48 00       	jmp    6bb9e1 <user_event_entry+0x161>
