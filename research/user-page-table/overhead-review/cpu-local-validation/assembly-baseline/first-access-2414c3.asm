
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/direct-handler-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000002414c3 <__kernelet_cpu_access_start+0x412a2>:
  2414c3:	48 8b 0d d6 b8 7f 00 	mov    0x7fb8d6(%rip),%rcx        # a3cda0 <KERNELET_BOOT_ARGS>
  2414ca:	8b 91 bc 00 00 00    	mov    0xbc(%rcx),%edx
  2414d0:	65 48 8b 12          	mov    %gs:(%rdx),%rdx
  2414d4:	48 c1 ea 10          	shr    $0x10,%rdx
  2414d8:	0f b7 d2             	movzwl %dx,%edx
  2414db:	48 69 d2 80 00 00 00 	imul   $0x80,%rdx,%rdx
  2414e2:	48 8d 8c 11 00 10 00 00 	lea    0x1000(%rcx,%rdx,1),%rcx
  2414ea:	8b 41 54             	mov    0x54(%rcx),%eax
  2414ed:	e9 52 ac 48 00       	jmp    6cc144 <first_user_task_entry+0xb4>
