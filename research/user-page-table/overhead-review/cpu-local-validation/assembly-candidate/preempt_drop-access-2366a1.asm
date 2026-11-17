
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002366a1 <__kernelet_cpu_access_start+0x36480>:
  2366a1:	48 8b 15 28 68 80 00 	mov    0x806828(%rip),%rdx        # a3ced0 <KERNELET_BOOT_ARGS>
  2366a8:	8b b2 bc 00 00 00    	mov    0xbc(%rdx),%esi
  2366ae:	65 48 8b 36          	mov    %gs:(%rsi),%rsi
  2366b2:	48 c1 ee 10          	shr    $0x10,%rsi
  2366b6:	0f b7 f6             	movzwl %si,%esi
  2366b9:	48 69 f6 80 00 00 00 	imul   $0x80,%rsi,%rsi
  2366c0:	48 8d 94 32 00 10 00 00 	lea    0x1000(%rdx,%rsi,1),%rdx
  2366c8:	48 8b 7a 68          	mov    0x68(%rdx),%rdi
  2366cc:	48 89 d0             	mov    %rdx,%rax
  2366cf:	e9 fb 4d 48 00       	jmp    6bb4cf <<ostd::task::preempt::guard::DisabledPreemptGuard as core::ops::drop::Drop>::drop+0x1f>
