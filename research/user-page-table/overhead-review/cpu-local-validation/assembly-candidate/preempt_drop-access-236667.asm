
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000236667 <__kernelet_cpu_access_start+0x36446>:
  236667:	48 8b 05 62 68 80 00 	mov    0x806862(%rip),%rax        # a3ced0 <KERNELET_BOOT_ARGS>
  23666e:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  236674:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  236678:	48 c1 e9 10          	shr    $0x10,%rcx
  23667c:	0f b7 c9             	movzwl %cx,%ecx
  23667f:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  236686:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  23668e:	8b 68 54             	mov    0x54(%rax),%ebp
  236691:	85 ed                	test   %ebp,%ebp
  236693:	75 07                	jne    23669c <__kernelet_cpu_access_start+0x3647b>
  236695:	c7 40 54 01 00 00 00 	movl   $0x1,0x54(%rax)
  23669c:	e9 1b 4e 48 00       	jmp    6bb4bc <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0xc>
