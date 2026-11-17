
/mnt/data/projects/kernelet/research/user-page-table/overhead-review/panic-cold-validation/kernelet-image.elf:     file format elf64-x86-64


Disassembly of section .text:

00000000006c73d0 <ostd::panic::report_caught_panic>:
  6c73d0:	endbr64
  6c73d4:	push   %rbp
  6c73d5:	push   %rbx
  6c73d6:	sub    $0xc18,%rsp
  6c73dd:	jmp    238a3a <__kernelet_cpu_access_start+0x38819>
  6c73e2:	mov    $0x1,%bl
  6c73e4:	data16 data16 cs nopw 0x0(%rax,%rax,1)
  6c73f0:	xor    %eax,%eax
  6c73f2:	lock cmpxchg %bl,0x375b8e(%rip)        # a3cf88 <ostd::panic::PANIC_MESSAGE>
  6c73fa:	je     6c7405 <ostd::panic::report_caught_panic+0x35>
  6c73fc:	pause
  6c73fe:	call   6be6b0 <ostd::kernelet::entry::on_spin>
  6c7403:	jmp    6c73f0 <ostd::panic::report_caught_panic+0x20>
  6c7405:	cmpl   $0x1,0x375b84(%rip)        # a3cf90 <ostd::panic::PANIC_MESSAGE+0x8>
  6c740c:	jne    6c7472 <ostd::panic::report_caught_panic+0xa2>
  6c740e:	lea    0x375b83(%rip),%rsi        # a3cf98 <ostd::panic::PANIC_MESSAGE+0x10>
  6c7415:	lea    0x8(%rsp),%rdi
  6c741a:	mov    $0x408,%edx
  6c741f:	call   6e4a80 <memcpy>
  6c7424:	movb   $0x0,0x375b5d(%rip)        # a3cf88 <ostd::panic::PANIC_MESSAGE>
  6c742b:	test   %ebp,%ebp
  6c742d:	jne    6c7434 <ostd::panic::report_caught_panic+0x64>
  6c742f:	call   6be7c0 <ostd::arch::irq::ops::enable_local>
  6c7434:	lea    0x810(%rsp),%rdi
  6c743c:	lea    0x8(%rsp),%rsi
  6c7441:	mov    $0x408,%edx
  6c7446:	call   6e4a80 <memcpy>
  6c744b:	mov    0xc10(%rsp),%rdx
  6c7453:	cmp    $0x401,%rdx
  6c745a:	jb     6c74d4 <ostd::panic::report_caught_panic+0x104>
  6c745c:	lea    0x367ca5(%rip),%rcx        # a2f108 <anon.3b07fa90b168bf09adaaf9843382d095.27.llvm.2036654910146418673>
  6c7463:	mov    %rdx,%rsi
  6c7466:	mov    $0x400,%edx
  6c746b:	xor    %edi,%edi
  6c746d:	call   691ce0 <core::slice::index::slice_index_fail>
  6c7472:	movb   $0x0,0x375b0f(%rip)        # a3cf88 <ostd::panic::PANIC_MESSAGE>
  6c7479:	test   %ebp,%ebp
  6c747b:	jne    6c7482 <ostd::panic::report_caught_panic+0xb2>
  6c747d:	call   6be7c0 <ostd::arch::irq::ops::enable_local>
  6c7482:	lea    0x415(%rsp),%rdi
  6c748a:	mov    $0x3fb,%edx
  6c748f:	xor    %esi,%esi
  6c7491:	call   6e4a90 <memset>
  6c7496:	movl   $0x726f6261,0x410(%rsp)
  6c74a1:	movb   $0x74,0x414(%rsp)
  6c74a9:	lea    0x810(%rsp),%rdi
  6c74b1:	lea    0x410(%rsp),%rsi
  6c74b9:	mov    $0x400,%edx
  6c74be:	call   6e4a80 <memcpy>
  6c74c3:	movq   $0x5,0xc10(%rsp)
  6c74cf:	mov    $0x5,%edx
  6c74d4:	lea    0x8(%rsp),%rdi
  6c74d9:	lea    0x810(%rsp),%rsi
  6c74e1:	call   693780 <core::str::converts::from_utf8>
  6c74e6:	cmpl   $0x1,0x8(%rsp)
  6c74eb:	je     6c7541 <ostd::panic::report_caught_panic+0x171>
  6c74ed:	mov    0x10(%rsp),%rdi
  6c74f2:	mov    0x18(%rsp),%rax
  6c74f7:	cmp    $0x400,%rax
  6c74fd:	mov    $0x400,%esi
  6c7502:	cmovb  %rax,%rsi
  6c7506:	test   %rax,%rax
  6c7509:	je     6c7522 <ostd::panic::report_caught_panic+0x152>
  6c750b:	nopl   0x0(%rax,%rax,1)
  6c7510:	cmp    %rax,%rsi
  6c7513:	jae    6c7522 <ostd::panic::report_caught_panic+0x152>
  6c7515:	cmpb   $0xbf,(%rdi,%rsi,1)
  6c7519:	jg     6c7522 <ostd::panic::report_caught_panic+0x152>
  6c751b:	dec    %rsi
  6c751e:	jne    6c7510 <ostd::panic::report_caught_panic+0x140>
  6c7520:	xor    %esi,%esi
  6c7522:	mov    0x338b0f(%rip),%rax        # a00038 <_DYNAMIC+0x60210>
  6c7529:	mov    (%rax),%rax
  6c752c:	test   %rax,%rax
  6c752f:	je     6c7582 <ostd::panic::report_caught_panic+0x1b2>
  6c7531:	call   *0x88(%rax)
  6c7537:	add    $0xc18,%rsp
  6c753e:	pop    %rbx
  6c753f:	pop    %rbp
  6c7540:	ret
  6c7541:	mov    0x10(%rsp),%rax
  6c7546:	mov    0x18(%rsp),%rcx
  6c754b:	mov    %rcx,0x418(%rsp)
  6c7553:	mov    %rax,0x410(%rsp)
  6c755b:	lea    0x19c4c0(%rip),%rdi        # 863a22 <anon.3b07fa90b168bf09adaaf9843382d095.22.llvm.2036654910146418673>
  6c7562:	lea    0x367b67(%rip),%rcx        # a2f0d0 <anon.3b07fa90b168bf09adaaf9843382d095.24.llvm.2036654910146418673>
  6c7569:	lea    0x367b80(%rip),%r8        # a2f0f0 <anon.3b07fa90b168bf09adaaf9843382d095.26.llvm.2036654910146418673>
  6c7570:	lea    0x410(%rsp),%rdx
  6c7578:	mov    $0x2b,%esi
  6c757d:	call   6953f0 <core::result::unwrap_failed>
  6c7582:	lea    0x19baab(%rip),%rdi        # 863034 <anon.640ee05cbc79ee72d993a22be3c2086a.30.llvm.10029247957258186659>
  6c7589:	lea    0x367620(%rip),%rdx        # a2ebb0 <anon.640ee05cbc79ee72d993a22be3c2086a.31.llvm.10029247957258186659>
  6c7590:	mov    $0x53,%esi
  6c7595:	call   696030 <core::panicking::panic_fmt>
  6c759a:	endbr64
  6c759e:	mov    %rax,%rbx
  6c75a1:	test   %ebp,%ebp
  6c75a3:	jne    6c75aa <ostd::panic::report_caught_panic+0x1da>
  6c75a5:	call   6be7c0 <ostd::arch::irq::ops::enable_local>
  6c75aa:	mov    %rbx,%rdi
  6c75ad:	call   6e4320 <_Unwind_Resume>
  6c75b2:	endbr64
  6c75b6:	call   695e3b <core::panicking::panic_in_cleanup>
