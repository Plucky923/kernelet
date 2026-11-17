
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002372e7 <__kernelet_cpu_access_start+0x370c6>:
  2372e7:	48 8b 15 a2 5b 80 00 	mov    0x805ba2(%rip),%rdx        # a3ce90 <KERNELET_BOOT_ARGS>
  2372ee:	8b b2 bc 00 00 00    	mov    0xbc(%rdx),%esi
  2372f4:	65 48 8b 36          	mov    %gs:(%rsi),%rsi
  2372f8:	48 c1 ee 10          	shr    $0x10,%rsi
  2372fc:	0f b7 f6             	movzwl %si,%esi
  2372ff:	48 69 f6 80 00 00 00 	imul   $0x80,%rsi,%rsi
  237306:	48 8d 94 32 00 10 00 00 	lea    0x1000(%rdx,%rsi,1),%rdx
  23730e:	48 8b 7a 68          	mov    0x68(%rdx),%rdi
  237312:	48 89 d0             	mov    %rdx,%rax
  237315:	e9 b5 02 48 00       	jmp    6b75cf <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0x1f>
