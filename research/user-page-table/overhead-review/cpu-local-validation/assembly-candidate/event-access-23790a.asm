
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000023790a <__kernelet_cpu_access_start+0x376e9>:
  23790a:	48 8b 05 7f 55 80 00 	mov    0x80557f(%rip),%rax        # a3ce90 <KERNELET_BOOT_ARGS>
  237911:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  237917:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  23791b:	48 c1 e9 10          	shr    $0x10,%rcx
  23791f:	0f b7 c9             	movzwl %cx,%ecx
  237922:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  237929:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  237931:	48 89 c2             	mov    %rax,%rdx
  237934:	e9 d8 68 48 00       	jmp    6be211 <user_event_entry+0x161>
