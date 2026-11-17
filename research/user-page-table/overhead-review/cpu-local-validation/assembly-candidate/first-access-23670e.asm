
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

000000000023670e <__kernelet_cpu_access_start+0x364ed>:
  23670e:	48 8b 0d bb 67 80 00 	mov    0x8067bb(%rip),%rcx        # a3ced0 <KERNELET_BOOT_ARGS>
  236715:	8b b1 bc 00 00 00    	mov    0xbc(%rcx),%esi
  23671b:	65 48 8b 36          	mov    %gs:(%rsi),%rsi
  23671f:	48 c1 ee 10          	shr    $0x10,%rsi
  236723:	0f b7 f6             	movzwl %si,%esi
  236726:	48 69 f6 80 00 00 00 	imul   $0x80,%rsi,%rsi
  23672d:	48 8d 8c 31 00 10 00 00 	lea    0x1000(%rcx,%rsi,1),%rcx
  236735:	48 8b 79 68          	mov    0x68(%rcx),%rdi
  236739:	48 89 ca             	mov    %rcx,%rdx
  23673c:	e9 f9 4e 48 00       	jmp    6bb63a <first_user_task_entry+0x2a>
