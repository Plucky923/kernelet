
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000237939 <__kernelet_cpu_access_start+0x37718>:
  237939:	48 8b 05 50 55 80 00 	mov    0x805550(%rip),%rax        # a3ce90 <KERNELET_BOOT_ARGS>
  237940:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  237946:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  23794a:	48 c1 e9 10          	shr    $0x10,%rcx
  23794e:	0f b7 c9             	movzwl %cx,%ecx
  237951:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  237958:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  237960:	8b 50 54             	mov    0x54(%rax),%edx
  237963:	85 d2                	test   %edx,%edx
  237965:	75 07                	jne    23796e <__kernelet_cpu_access_start+0x3774d>
  237967:	c7 40 54 01 00 00 00 	movl   $0x1,0x54(%rax)
  23796e:	e9 be 68 48 00       	jmp    6be231 <user_event_entry+0x181>
