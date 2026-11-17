
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002372ad <__kernelet_cpu_access_start+0x3708c>:
  2372ad:	48 8b 05 dc 5b 80 00 	mov    0x805bdc(%rip),%rax        # a3ce90 <KERNELET_BOOT_ARGS>
  2372b4:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  2372ba:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  2372be:	48 c1 e9 10          	shr    $0x10,%rcx
  2372c2:	0f b7 c9             	movzwl %cx,%ecx
  2372c5:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  2372cc:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  2372d4:	8b 68 54             	mov    0x54(%rax),%ebp
  2372d7:	85 ed                	test   %ebp,%ebp
  2372d9:	75 07                	jne    2372e2 <__kernelet_cpu_access_start+0x370c1>
  2372db:	c7 40 54 01 00 00 00 	movl   $0x1,0x54(%rax)
  2372e2:	e9 d5 02 48 00       	jmp    6b75bc <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0xc>
