
/mnt/data/projects/kernelet/.cpu-local-validation-work/candidate.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000238116 <__kernelet_cpu_access_start+0x37ef5>:
  238116:	48 8b 05 b3 4d 80 00 	mov    0x804db3(%rip),%rax        # a3ced0 <KERNELET_BOOT_ARGS>
  23811d:	8b 88 bc 00 00 00    	mov    0xbc(%rax),%ecx
  238123:	65 48 8b 09          	mov    %gs:(%rcx),%rcx
  238127:	48 c1 e9 10          	shr    $0x10,%rcx
  23812b:	0f b7 c9             	movzwl %cx,%ecx
  23812e:	48 69 c9 80 00 00 00 	imul   $0x80,%rcx,%rcx
  238135:	48 8d 84 08 00 10 00 00 	lea    0x1000(%rax,%rcx,1),%rax
  23813d:	48 89 c2             	mov    %rax,%rdx
  238140:	e9 73 d6 48 00       	jmp    6c57b8 <ostd::arch::irq::ops::enable_local+0x28>
