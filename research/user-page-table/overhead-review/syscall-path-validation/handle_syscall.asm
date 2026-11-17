
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/syscall-path-validation/image-release.elf:     file format elf64-x86-64


Disassembly of section .text:

0000000000427740 <_RNvNtCshotNd2mSv6q_10aster_core7syscall14handle_syscall>:
  427740:	f3 0f 1e fa          	endbr64
  427744:	41 56                	push   %r14
  427746:	53                   	push   %rbx
  427747:	48 81 ec f8 04 00 00 	sub    $0x4f8,%rsp
  42774e:	48 89 f3             	mov    %rsi,%rbx
  427751:	48 89 fa             	mov    %rdi,%rdx
  427754:	48 8b 46 08          	mov    0x8(%rsi),%rax
  427758:	83 3e 01             	cmpl   $0x1,(%rsi)
  42775b:	75 03                	jne    427760 <_RNvNtCshotNd2mSv6q_10aster_core7syscall14handle_syscall+0x20>
  42775d:	48 8b 00             	mov    (%rax),%rax
  427760:	48 8b 70 50          	mov    0x50(%rax),%rsi
  427764:	48 8d 7c 24 08       	lea    0x8(%rsp),%rdi
  427769:	48 89 d9             	mov    %rbx,%rcx
  42776c:	e8 0f 8c fb ff       	call   3e0380 <_RNvNtNtCshotNd2mSv6q_10aster_core7syscall4arch16syscall_dispatch>
  427771:	83 7c 24 18 00       	cmpl   $0x0,0x18(%rsp)
  427776:	0f 84 d7 00 00 00    	je     427853 <_RNvNtCshotNd2mSv6q_10aster_core7syscall14handle_syscall+0x113>
  42777c:	48 8b 44 24 18       	mov    0x18(%rsp),%rax
  427781:	48 89 44 24 38       	mov    %rax,0x38(%rsp)
  427786:	48 8b 44 24 08       	mov    0x8(%rsp),%rax
  42778b:	48 8b 4c 24 10       	mov    0x10(%rsp),%rcx
  427790:	48 89 4c 24 30       	mov    %rcx,0x30(%rsp)
  427795:	48 89 44 24 28       	mov    %rax,0x28(%rsp)
  42779a:	0f b6 05 d7 56 61 00 	movzbl 0x6156d7(%rip),%eax        # a3ce78 <_RNvNtNtCs3BxAPKCioTh_4ostd3log6logger17DYNAMIC_MAX_LEVEL>
  4277a1:	3c 07                	cmp    $0x7,%al
  4277a3:	0f 86 f5 01 00 00    	jbe    42799e <_RNvNtCshotNd2mSv6q_10aster_core7syscall14handle_syscall+0x25e>
  4277a9:	48 8d 44 24 28       	lea    0x28(%rsp),%rax
  4277ae:	48 89 84 24 88 00 00 	mov    %rax,0x88(%rsp)
  4277b5:	00 
  4277b6:	48 8d 05 43 cf 02 00 	lea    0x2cf43(%rip),%rax        # 454700 <_RNvXsw_NtCshotNd2mSv6q_10aster_core5errorNtB5_5ErrorNtNtCs4l6QGzsNTLX_4core3fmt5Debug3fmt.llvm.1744883703703194182>
  4277bd:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  4277c4:	00 
  4277c5:	c6 84 24 84 00 00 00 	movb   $0x7,0x84(%rsp)
  4277cc:	07 
  4277cd:	48 c7 44 24 40 01 00 	movq   $0x1,0x40(%rsp)
  4277d4:	00 00 
  4277d6:	48 c7 44 24 48 00 00 	movq   $0x0,0x48(%rsp)
  4277dd:	00 00 
  4277df:	48 8d 05 e5 8b 3d 00 	lea    0x3d8be5(%rip),%rax        # 8003cb <anon.db2dde0c4cedf436d40d4d69131b20f6.386.llvm.1744883703703194182>
  4277e6:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  4277eb:	48 8d 84 24 88 00 00 	lea    0x88(%rsp),%rax
  4277f2:	00 
  4277f3:	48 89 44 24 58       	mov    %rax,0x58(%rsp)
  4277f8:	48 8d 05 86 1d 41 00 	lea    0x411d86(%rip),%rax        # 839585 <anon.db2dde0c4cedf436d40d4d69131b20f6.387.llvm.1744883703703194182>
  4277ff:	48 89 44 24 60       	mov    %rax,0x60(%rsp)
  427804:	48 c7 44 24 68 13 00 	movq   $0x13,0x68(%rsp)
  42780b:	00 00 
  42780d:	48 8d 05 84 1d 41 00 	lea    0x411d84(%rip),%rax        # 839598 <anon.db2dde0c4cedf436d40d4d69131b20f6.388.llvm.1744883703703194182>
  427814:	48 89 44 24 70       	mov    %rax,0x70(%rsp)
  427819:	48 c7 44 24 78 b4 00 	movq   $0xb4,0x78(%rsp)
  427820:	00 00 
  427822:	c7 84 24 80 00 00 00 	movl   $0x185,0x80(%rsp)
  427829:	85 01 00 00 
  42782d:	0f b6 05 3c 56 61 00 	movzbl 0x61563c(%rip),%eax        # a3ce70 <_RNvNtNtCs3BxAPKCioTh_4ostd3log6logger6LOGGER+0x10>
  427834:	3c 02                	cmp    $0x2,%al
  427836:	75 3d                	jne    427875 <_RNvNtCshotNd2mSv6q_10aster_core7syscall14handle_syscall+0x135>
  427838:	48 8b 3d 21 56 61 00 	mov    0x615621(%rip),%rdi        # a3ce60 <_RNvNtNtCs3BxAPKCioTh_4ostd3log6logger6LOGGER>
  42783f:	48 8b 05 22 56 61 00 	mov    0x615622(%rip),%rax        # a3ce68 <_RNvNtNtCs3BxAPKCioTh_4ostd3log6logger6LOGGER+0x8>
  427846:	48 8d 74 24 40       	lea    0x40(%rsp),%rsi
  42784b:	ff 50 18             	call   *0x18(%rax)
  42784e:	e9 4b 01 00 00       	jmp    42799e <_RNvNtCshotNd2mSv6q_10aster_core7syscall14handle_syscall+0x25e>
  427853:	80 7c 24 08 00       	cmpb   $0x0,0x8(%rsp)
  427858:	0f 85 58 01 00 00    	jne    4279b6 <_RNvNtCshotNd2mSv6q_10aster_core7syscall14handle_syscall+0x276>
  42785e:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
  427863:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
  427867:	83 3b 01             	cmpl   $0x1,(%rbx)
  42786a:	0f 84 3f 01 00 00    	je     4279af <_RNvNtCshotNd2mSv6q_10aster_core7syscall14handle_syscall+0x26f>
  427870:	e9 3d 01 00 00       	jmp    4279b2 <_RNvNtCshotNd2mSv6q_10aster_core7syscall14handle_syscall+0x272>
  427875:	48 8d 44 24 50       	lea    0x50(%rsp),%rax
  42787a:	0f b6 8c 24 84 00 00 	movzbl 0x84(%rsp),%ecx
  427881:	00 
  427882:	88 4c 24 07          	mov    %cl,0x7(%rsp)
  427886:	48 8b 4c 24 40       	mov    0x40(%rsp),%rcx
  42788b:	48 8b 54 24 48       	mov    0x48(%rsp),%rdx
  427890:	48 89 8c 24 98 00 00 	mov    %rcx,0x98(%rsp)
  427897:	00 
  427898:	48 89 94 24 a0 00 00 	mov    %rdx,0xa0(%rsp)
  42789f:	00 
  4278a0:	48 89 44 24 20       	mov    %rax,0x20(%rsp)
  4278a5:	48 8d 44 24 07       	lea    0x7(%rsp),%rax
  4278aa:	48 89 84 24 a8 00 00 	mov    %rax,0xa8(%rsp)
  4278b1:	00 
  4278b2:	48 8b 05 77 87 5d 00 	mov    0x5d8777(%rip),%rax        # a00030 <_DYNAMIC+0x5d9e8>
  4278b9:	48 89 84 24 b0 00 00 	mov    %rax,0xb0(%rsp)
  4278c0:	00 
  4278c1:	48 8d 84 24 98 00 00 	lea    0x98(%rsp),%rax
  4278c8:	00 
  4278c9:	48 89 84 24 b8 00 00 	mov    %rax,0xb8(%rsp)
  4278d0:	00 
  4278d1:	48 8d 05 28 2b 2f 00 	lea    0x2f2b28(%rip),%rax        # 71a400 <_RNvXs1i_NtCs4l6QGzsNTLX_4core3fmtReNtB6_7Display3fmtCs3BxAPKCioTh_4ostd>
  4278d8:	48 89 84 24 c0 00 00 	mov    %rax,0xc0(%rsp)
  4278df:	00 
  4278e0:	48 8d 44 24 20       	lea    0x20(%rsp),%rax
  4278e5:	48 89 84 24 c8 00 00 	mov    %rax,0xc8(%rsp)
  4278ec:	00 
  4278ed:	48 8d 05 ec 2a 2f 00 	lea    0x2f2aec(%rip),%rax        # 71a3e0 <_RNvXs1i_NtCs4l6QGzsNTLX_4core3fmtRNtB6_9ArgumentsNtB6_7Display3fmtCs3BxAPKCioTh_4ostd>
  4278f4:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  4278fb:	00 
  4278fc:	4c 8d b4 24 e8 00 00 	lea    0xe8(%rsp),%r14
  427903:	00 
  427904:	ba 00 04 00 00       	mov    $0x400,%edx
  427909:	4c 89 f7             	mov    %r14,%rdi
  42790c:	31 f6                	xor    %esi,%esi
  42790e:	e8 0d e6 30 00       	call   735f20 <memset>
  427913:	c7 84 24 f0 04 00 00 	movl   $0x8,0x4f0(%rsp)
  42791a:	08 00 00 00 
  42791e:	48 8d 05 2b b1 3f 00 	lea    0x3fb12b(%rip),%rax        # 822a50 <anon.31357acbf73c121db40f526e06268467.26.llvm.186973046271484012>
  427925:	48 89 84 24 d8 00 00 	mov    %rax,0xd8(%rsp)
  42792c:	00 
  42792d:	48 c7 84 24 e0 00 00 	movq   $0x4,0xe0(%rsp)
  427934:	00 04 00 00 00 
  427939:	48 c7 84 24 e8 04 00 	movq   $0x0,0x4e8(%rsp)
  427940:	00 00 00 00 00 
  427945:	48 8d 35 f4 7d 60 00 	lea    0x607df4(%rip),%rsi        # a2f740 <anon.31357acbf73c121db40f526e06268467.24.llvm.186973046271484012>
  42794c:	48 8d 15 83 36 3e 00 	lea    0x3e3683(%rip),%rdx        # 80afd6 <anon.5fe4f258ead25c2a9059fca975a76dd1.41.llvm.10329050153015054036>
  427953:	48 8d bc 24 d8 00 00 	lea    0xd8(%rsp),%rdi
  42795a:	00 
  42795b:	48 8d 8c 24 a8 00 00 	lea    0xa8(%rsp),%rcx
  427962:	00 
  427963:	e8 38 71 2b 00       	call   6deaa0 <_RNvNtCs4l6QGzsNTLX_4core3fmt5write>
  427968:	4c 8b 84 24 e8 04 00 	mov    0x4e8(%rsp),%r8
  42796f:	00 
  427970:	4d 85 c0             	test   %r8,%r8
  427973:	74 29                	je     42799e <_RNvNtCshotNd2mSv6q_10aster_core7syscall14handle_syscall+0x25e>
  427975:	48 8b 05 bc 86 5d 00 	mov    0x5d86bc(%rip),%rax        # a00038 <_DYNAMIC+0x5d9f0>
  42797c:	48 8b 00             	mov    (%rax),%rax
  42797f:	8b bc 24 f0 04 00 00 	mov    0x4f0(%rsp),%edi
  427986:	48 8b b4 24 d8 00 00 	mov    0xd8(%rsp),%rsi
  42798d:	00 
  42798e:	8b 94 24 e0 00 00 00 	mov    0xe0(%rsp),%edx
  427995:	4c 89 f1             	mov    %r14,%rcx
  427998:	ff 90 80 00 00 00    	call   *0x80(%rax)
  42799e:	48 63 44 24 38       	movslq 0x38(%rsp),%rax
  4279a3:	48 f7 d8             	neg    %rax
  4279a6:	48 8b 4b 08          	mov    0x8(%rbx),%rcx
  4279aa:	83 3b 01             	cmpl   $0x1,(%rbx)
  4279ad:	75 03                	jne    4279b2 <_RNvNtCshotNd2mSv6q_10aster_core7syscall14handle_syscall+0x272>
  4279af:	48 8b 09             	mov    (%rcx),%rcx
  4279b2:	48 89 41 50          	mov    %rax,0x50(%rcx)
  4279b6:	48 81 c4 f8 04 00 00 	add    $0x4f8,%rsp
  4279bd:	5b                   	pop    %rbx
  4279be:	41 5e                	pop    %r14
  4279c0:	c3                   	ret
