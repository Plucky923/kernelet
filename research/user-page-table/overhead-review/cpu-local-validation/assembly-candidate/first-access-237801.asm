
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000237801 <__kernelet_cpu_access_start+0x375e0>:
  237801:	48 8b 0d 88 56 80 00 	mov    0x805688(%rip),%rcx        # a3ce90 <KERNELET_BOOT_ARGS>
  237808:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  23780e:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  237812:	48 c1 ea 10          	shr    $0x10,%rdx
  237816:	0f b7 d2             	movzwl %dx,%edx
  237819:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  237820:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  237828:	8b 41 54             	mov    0x54(%rcx),%eax
  23782b:	85 c0                	test   %eax,%eax
  23782d:	75 07                	jne    237836 <__kernelet_cpu_access_start+0x37615>
  23782f:	c7 41 54 01 00 00 00 	movl   $0x1,0x54(%rcx)
  237836:	e9 22 66 48 00       	jmp    6bde5d <first_user_task_entry+0x1d>
