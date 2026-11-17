
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000023783b <__kernelet_cpu_access_start+0x3761a>:
  23783b:	48 8b 0d 4e 56 80 00 	mov    0x80564e(%rip),%rcx        # a3ce90 <KERNELET_BOOT_ARGS>
  237842:	8b b1 bc 00 00 00    	mov    0xbc(%rcx),%esi
  237848:	65 48 8b 36          	mov    %gs:(%rsi),%rsi
  23784c:	48 c1 ee 10          	shr    $0x10,%rsi
  237850:	0f b7 f6             	movzwl %si,%esi
  237853:	48 69 f6 80 00 00 00 	imul   $0x80,%rsi,%rsi
  23785a:	48 8d 8c 31 00 10 00 00 	lea    0x1000(%rcx,%rsi,1),%rcx
  237862:	48 8b 79 68          	mov    0x68(%rcx),%rdi
  237866:	48 89 ca             	mov    %rcx,%rdx
  237869:	e9 fc 65 48 00       	jmp    6bde6a <first_user_task_entry+0x2a>
