
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002366d4 <__kernelet_cpu_access_start+0x364b3>:
  2366d4:	48 8b 0d f5 67 80 00 	mov    0x8067f5(%rip),%rcx        # a3ced0 <KERNELET_BOOT_ARGS>
  2366db:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  2366e1:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  2366e5:	48 c1 ea 10          	shr    $0x10,%rdx
  2366e9:	0f b7 d2             	movzwl %dx,%edx
  2366ec:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  2366f3:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  2366fb:	8b 41 54             	mov    0x54(%rcx),%eax
  2366fe:	85 c0                	test   %eax,%eax
  236700:	75 07                	jne    236709 <__kernelet_cpu_access_start+0x364e8>
  236702:	c7 41 54 01 00 00 00 	movl   $0x1,0x54(%rcx)
  236709:	e9 1f 4f 48 00       	jmp    6bb62d <first_user_task_entry+0x1d>
