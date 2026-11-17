# PoC Evaluation Results: SMP Asterinas on Linux (PR #3 + PR #7 + Direct PTE)

This record describes the 2026-11-16 artifacts and experiments. The [2026-11-17 syscall measurement report](results/syscall-2026-11-17/README.md) provides the current implementation, matched CPU placement, raw samples, mitigation comparison, and limits of cost attribution.

- **Date**: 2026-11-16
- **Host / Hypervisor**: AMD Ryzen 7 5800H, QEMU/KVM (`-enable-kvm -cpu host -smp 2 -m 1024M -nic none`)
- **Host Kernel**: Unmitigated Linux 6.12 baseline (`prototype/linux/patches/0001-carrier-hooks.patch`, `# CONFIG_CPU_MITIGATIONS is not set`, `CONFIG_KERNELET=y`, `bzImage` `2,323,456` bytes); PTI verification ran on temporary `CONFIG_CPU_MITIGATIONS=y` + `CONFIG_MITIGATION_PAGE_TABLE_ISOLATION=y` build (`bzImage` `2,606,080` bytes) before restoring the unmitigated baseline.

---

## 1. System & Implementation Overview

The PoC integrates PR #3 (`reduce-syscall-overhead`), PR #7 (`fpu-state-management`), and Direct PTE (`direct-page-table-updates-in-vostd`) into a single runnable SMP Asterinas-on-Linux stack:

- **Linux Host Patch (`prototype/linux/patches/0001-carrier-hooks.patch`)**: Exports `kernelet_return_to_user`, `kernelet_cpu_slot` / `kernelet_cpu_slot_gs_offset`, `kernelet_fpu_restore_carrier`, `kernelet_fpu_sched_in`, `kernelet_fpu_reset_carrier`, `mmput_async`, and `get_vm_area` / `vm_area_map_pages` / `vm_area_unmap_pages`; hooks all 11 forwarded user exceptions (`on_exception`) and unrecovered kernel faults (`on_kernel_fault`); and adds an inline `work == SYSCALL_WORK_KERNELET` fast path in `include/linux/entry-common.h` (`syscall_enter_from_user_mode_work`) before out-of-line `syscall_trace_enter`.
- **PoC Endovisor (`poc/linux/endovisor/poc_endovisor.ko`, `80,816` bytes on restored baseline)**: Implements `/dev/poc_endovisor` with 2 MiB grant grains (`alloc_pages(GFP_KERNEL_ACCOUNT | __GFP_ZERO, 9)`, up to 512 MiB; 256 MiB used in MM/safety boots), sparse `meta_base` vmalloc mapping (`poc_grant.c`), guarded 256 KiB kernelet stacks on 512 KiB strides, dual address-space modes in `poc_space.c` (`POC_PT_MODE_DIRECT = 0` empty `mm_struct` vs `POC_PT_MODE_VMA = 1` `VM_PFNMAP` VMA baseline), PR #3/`UserEventRecord` carrier dispatch (`poc_carrier.c`), PR #7 lazy-on-syscall / eager-on-switch FPU lifecycle, and `STACK_FRAME_NON_STANDARD` + `CALL_NOSPEC` annotations in `poc_switch.S` (verified with 0 compiler/`objtool`/`__warn_thunk` warnings under `CONFIG_MITIGATION_RETHUNK=y`).
- **Audited Kernelet Image (`poc/target/kernelet-unsafe-audit-cbd11506de9495a6/kernelet-image.elf`, `12,131,976` bytes)**: Built via `OSDK_KERNELET_IMAGE_ONLY=1` with `cargo-osdk` passing all static safety/FP/ABI audits (144-byte `EntryTable` with `user_event_entry`, 160-byte `ServiceTable`, 2,352-byte `BootArgs`, 0 unsafe-audit violations).
- **Runner & Benchmark Suite (`poc/linux/runner/run-poc`, `poc/linux/bench/*.c`)**: Static C binaries compiled with `-O2 -static -pthread` (`bench_syscall_fpu`, `bench_mm`, `test_mm_safety`) packed as standalone `/init` CPIO archives (`guest-syscall.cpio`, `guest-mm.cpio`, `guest-safety.cpio`) alongside `host-initramfs.cpio.gz` (`6,504,816` bytes), so Native Linux and Asterinas execute the exact same guest binaries (`MADV_NOHUGEPAGE`, `clock_gettime(CLOCK_MONOTONIC)` outside timed loops, `go_pipe`/`ready_pipe` barriers).

---

## 2. Stage 3: PR #3 (`reduce-syscall-overhead`) & PR #7 (`fpu-state-management`)

### 2.1 Five-Boot KVM Comparison (`native-syscall` vs `poc-syscall --pt-mode direct --vcpus 2`)

All 5+5 paired boots passed `smp_pthreads_cpus=2`, `smp_fork_cpus=2`, `smp_check=1`, `reg_preserve_getpid=1`, `reg_preserve_nanosleep=1`, `fpu_sse_getpid_ok=1`, `fpu_avx_getpid_ok=1`, `fpu_switch_sse_aba_ns_ok=1`, `fpu_switch_avx_aba_ns_ok=1`, `rt_sigreturn_valid=1`, `rt_sigreturn_bad_mxcsr=1`, `rt_sigreturn_bad_xcomp_bv=1`, and `suite_done=1` with 0 host kernel `BUG`/`WARNING`/`Oops`/`lockdep` splats and clean `poc_endovisor: unloaded`.

#### Summary Medians & Means (ns)

| Metric | Native Median [Mean] (ns) | Asterinas Direct 2-vCPU Median [Mean] (ns) | Ratio (`Ast / Nat`) or Delta |
|---|---:|---:|---:|
| `getpid_ns` (`1M` calls) | 38.95 [38.97] | 122.91 [123.24] | 3.16x |
| `fpu_sse_getpid_ns` (x87+SSE live) | 39.26 [39.32] | 124.21 [124.22] | 3.16x (+1.30 ns vs `getpid_ns`) |
| `fpu_avx_getpid_ns` (x87+AVX live) | 39.27 [39.38] | 124.61 [124.01] | 3.17x (+1.70 ns vs `getpid_ns`) |
| `fpu_switch_sse_aba_ns` (`50k` CPU0 trips) | 1023.80 [1020.95] | 1505.06 [1511.17] | 1.47x |
| `fpu_switch_avx_aba_ns` (`50k` CPU0 trips) | 1066.22 [1067.21] | 1522.05 [1531.05] | 1.43x |

#### Raw Per-Boot Numbers (ns) and Asterinas Counters

- **Native Linux (`poc_mode=native-syscall`, `-smp 2`)**:
  - B1: `getpid=38.76`, `sse_getpid=39.13`, `avx_getpid=39.27`, `sse_aba=1014.20`, `avx_aba=1066.22`
  - B2: `getpid=38.78`, `sse_getpid=39.32`, `avx_getpid=38.90`, `sse_aba=1023.80`, `avx_aba=1073.49`
  - B3: `getpid=38.95`, `sse_getpid=39.26`, `avx_getpid=39.42`, `sse_aba=1018.44`, `avx_aba=1075.10`
  - B4: `getpid=39.16`, `sse_getpid=39.92`, `avx_getpid=40.08`, `sse_aba=1023.83`, `avx_aba=1060.22`
  - B5: `getpid=39.20`, `sse_getpid=38.98`, `avx_getpid=39.25`, `sse_aba=1024.47`, `avx_aba=1061.01`
- **Asterinas-on-Linux (`poc_mode=poc-syscall poc_pt_mode=direct poc_vcpus=2`)**:
  - B1: `getpid=122.59`, `sse_getpid=123.54`, `avx_getpid=124.61`, `sse_aba=1499.84`, `avx_aba=1522.05` (`fpu_saves=674`, `fpu_restores=676`, `virqs=116`, `vm_creates=6`, `vm_destroys=6`, `exceptions=103`)
  - B2: `getpid=122.65`, `sse_getpid=124.32`, `avx_getpid=123.83`, `sse_aba=1509.73`, `avx_aba=1518.68` (`fpu_saves=665`, `fpu_restores=667`, `virqs=115`, `vm_creates=6`, `vm_destroys=6`, `exceptions=103`)
  - B3: `getpid=124.30`, `sse_getpid=124.99`, `avx_getpid=124.85`, `sse_aba=1565.26`, `avx_aba=1551.21` (`fpu_saves=732`, `fpu_restores=734`, `virqs=107`, `vm_creates=6`, `vm_destroys=6`, `exceptions=103`)
  - B4: `getpid=123.74`, `sse_getpid=124.02`, `avx_getpid=121.65`, `sse_aba=1475.94`, `avx_aba=1508.40` (`fpu_saves=846`, `fpu_restores=848`, `virqs=109`, `vm_creates=6`, `vm_destroys=6`, `exceptions=103`)
  - B5: `getpid=122.91`, `sse_getpid=124.21`, `avx_getpid=125.09`, `sse_aba=1505.06`, `avx_aba=1554.90` (`fpu_saves=905`, `fpu_restores=907`, `virqs=112`, `vm_creates=6`, `vm_destroys=6`, `exceptions=103`)
- **Isolated `poc_suite=syscall`** (`1,050,000` `getpid` calls): `getpid_ns=123.05 ns`, `fpu_saves=223`, `fpu_restores=225`, `virqs=33` — confirming **0** per-syscall FPU saves or restores (counters reflect host preemption ticks only).

### 2.2 Verification of PR #7 FPU Targets & Attribution of `getpid_ns` vs PR #3

- **PR #7 FPU Overhead Targets Met**: Preloading x87+SSE or x87+AVX registers across 1,000,000 `getpid` calls preserves all registers bit-for-bit with only `+1.30 ns` (SSE) and `+1.70 ns` (AVX) median difference over plain `getpid_ns` (`124.21 ns` and `124.61 ns` vs `122.91 ns`), meeting/exceeding PR #7's `+3–4 ns` per-syscall ceiling. Intra-carrier CPU 0 A↔B switching (`50,000` `sched_yield()` round trips = `100,000` switches) runs in `1505.06 ns` (SSE) and `1522.05 ns` (AVX) per round trip (`1.47x` and `1.43x` native) with 0 cross-thread corruption. `rt_sigreturn` checked XSAVE import (`valid=1`, `bad_mxcsr=1`, `bad_xcomp_bv=1`) safely forces `SIGSEGV` on corrupted frames without leaking `#GP` to the host.
- **Workload and attribution limits**: PR #3's `63.7 ns` vs `57.5 ns` (`1.11x`) figure measures a minimal constant-return handler. The `122.91 ns` result above measures full `aster-core` POSIX execution against an unmitigated Linux 6.12 baseline (`38.95 ns`). These workloads and builds do not establish a component-by-component cost difference. A separate instrumented run (`383.34 ns`) observed `non_sysret=0`, `cx_ne=0`, `r11_ne=0`, and `rflags_bad=0` across `1,049,921` calls. Those counters check return-frame eligibility before Linux exit work; they do not observe the final `SYSRET` or `IRET` instruction. Instrumented latency is excluded from the performance table. No unmeasured sub-component nanosecond costs are assigned.

---

## 3. Stage 4: Direct Page-Table Updates (`direct-page-table-updates-in-vostd`)

### 3.1 Five-Boot Shuffled KVM MM Comparison (`native-mm` vs `poc-mm --pt-mode vma` vs `poc-mm --pt-mode direct`)

Execution orders across the 5 rounds (5 internal iterations per boot, 64 MiB = `16,384` unique 4 KiB pages except `mprotect_ro_2m` = `512` pages and `exit_empty` = `0` pages, `MADV_NOHUGEPAGE`, `poc_grant_mb=256`, `poc_vcpus=2`): `R1: native direct vma`, `R2: direct vma native`, `R3: native direct vma`, `R4: direct vma native`, `R5: vma native direct`. All 15 boots exited `0` with `MM_RESULT suite_done 1 1.00`, 0 host kernel splats, and clean `poc_endovisor: unloaded`.

#### Summary Table (`ns_total`, 5-Boot Median, Per-Page Cost, `[min, max]`, Mean, `Direct/Native`, `VMA/Direct`)

| Workload | Native Median (ns/p) `[min, max]` (Mean) | VMA Baseline Median (ns/p) `[min, max]` (Mean) | Direct PTE Median (ns/p) `[min, max]` (Mean) | `Direct / Native` | `VMA / Direct` |
|---|---:|---:|---:|---:|---:|
| `anon_pf_1page` | 5,297,448 (323.33) `[5093807, 5622917]` (5,337,620.8) | 20,324,757 (1240.52) `[19725847, 20915865]` (20,302,088.4) | 13,731,741 (838.12) `[13525327, 15045862]` (14,058,958.2) | 2.59x | **1.48x** |
| `memfd_faultaround_16p` | 1,561,813 (95.33) `[1343508, 1724016]` (1,512,046.8) | 3,723,592 (227.27) `[3562299, 3796141]` (3,699,827.8) | 2,058,510 (125.64) `[1905124, 2213732]` (2,063,191.4) | 1.32x | **1.81x** |
| `mmap_populate_64m` | 5,473,874 (334.10) `[5279573, 5607976]` (5,452,118.6) | 2,745 (0.17) `[1563, 3476]` (2,510.4) | 1,854 (0.11) `[1472, 2996]` (2,200.0) | 0.00x* | **1.48x** |
| `mmap_populate_read_64m` | 265,570 (16.21) `[222272, 279495]` (261,230.2) | 20,339,314 (1241.41) `[20238792, 21208220]` (20,533,460.2) | 14,067,718 (858.63) `[13289531, 14712919]` (14,064,114.2) | 52.97x* | **1.45x** |
| `fork_64m` | 24,253 (1.48) `[24033, 24595]` (24,263.6) | 3,797,373 (231.77) `[3420603, 4254550]` (3,838,720.2) | 2,009,598 (122.66) `[1793355, 2213359]` (2,000,433.0) | 82.86x | **1.89x** |
| `child_read_64m` | 84,843 (5.18) `[83521, 89893]` (85,450.6) | 132,209 (8.07) `[131358, 133161]` (132,339.4) | 130,446 (7.96) `[123914, 156042]` (134,793.6) | 1.54x | 1.01x |
| `parent_read_64m` | 87,298 (5.33) `[86787, 90774]` (88,466.0) | 116,390 (7.10) `[98699, 123173]` (115,072.4) | 118,064 (7.21) `[110300, 122421]` (116,250.2) | 1.35x | 0.99x |
| `mprotect_ro_2m` | 1,162 (2.27) `[1001, 2144]` (1,354.4) | 77,741 (151.84) `[71379, 83961]` (77,962.8) | 21,209 (41.42) `[21048, 21830]` (21,297.0) | 18.25x | **3.67x** |
| `mprotect_ro_64m` | 2,504 (0.15) `[2455, 2565]` (2,498.8) | 2,511,059 (153.26) `[2364554, 2572941]` (2,488,617.8) | 658,350 (40.18) `[649073, 673086]` (659,017.0) | 262.92x | **3.81x** |
| `cow_write_1ref` | 230,016 (14.04) `[225718, 248820]` (232,973.4) | 26,275,704 (1603.74) `[25466601, 26734894]` (26,128,223.0) | 20,544,457 (1253.93) `[20331599, 21206852]` (20,757,644.4) | 89.32x | **1.28x** |
| `cow_write_2ref` | 16,307,484 (995.33) `[15220500, 16739874]` (16,198,623.0) | 34,260,175 (2091.08) `[33244531, 34852799]` (34,060,158.2) | 24,544,189 (1498.06) `[24374497, 25327610]` (24,692,222.2) | 1.51x | **1.40x** |
| `munmap_64m` | 68,765 (4.20) `[61271, 89522]` (72,741.6) | 1,783,784 (108.87) `[756728, 1784475]` (1,578,180.4) | 681,393 (41.59) `[641540, 1701665]` (1,065,750.4) | 9.91x | **2.62x** |
| `exit_empty` | 12,222 `[12052, 12663]` (12,330.4) | 124,597 `[122964, 128053]` (125,394.6) | 114,345 `[111667, 117341]` (114,393.0) | 9.36x | 1.09x |
| `exit_64m` | 111,812 (6.82) `[73693, 113545]` (96,983.4) | 1,969,293 (120.20) `[1936001, 2042856]` (1,980,816.6) | 1,884,451 (115.02) `[1837151, 1917425]` (1,883,920.6) | 16.85x | 1.05x |

\*Note on `mmap_populate_64m` / `mmap_populate_read_64m`: On Native Linux, `mmap(..., MAP_POPULATE)` eagerly faults/maps all 16,384 pages during the `mmap` syscall (`5.47 ms`), leaving `mmap_populate_read_64m` with 0 page faults (`0.27 ms`). In Asterinas (`poc/kernel/core/src/syscall/mmap.rs`), `do_sys_mmap` parses `MMapFlags::MAP_POPULATE` without eager pre-faulting, so `mmap_populate_64m` only registers the VMAR (`1.85 us` Direct / `2.75 us` VMA) and defers the 16,384 page faults into `mmap_populate_read_64m` (`14.07 ms` Direct vs `20.34 ms` VMA, `1.45x` speedup; combined `mmap + read` is `14.07 ms` Direct vs `20.34 ms` VMA vs `5.74 ms` Native).

#### Raw Per-Boot `ns_total` Values (`R1..R5`)

- **Native**: `anon_pf_1page=[5240582, 5297448, 5433350, 5622917, 5093807]`, `memfd_faultaround_16p=[1343508, 1724016, 1361571, 1561813, 1569326]`, `mmap_populate_64m=[5473874, 5607976, 5393218, 5505952, 5279573]`, `mmap_populate_read_64m=[261643, 279495, 222272, 265570, 277171]`, `fork_64m=[24595, 24033, 24253, 24304, 24133]`, `child_read_64m=[84843, 83521, 89893, 85244, 83752]`, `parent_read_64m=[90774, 87298, 86787, 90533, 86938]`, `mprotect_ro_2m=[1162, 1022, 2144, 1001, 1443]`, `mprotect_ro_64m=[2504, 2465, 2455, 2505, 2565]`, `cow_write_1ref=[248820, 225718, 232541, 227772, 230016]`, `cow_write_2ref=[16549951, 15220500, 16175306, 16739874, 16307484]`, `munmap_64m=[89522, 61902, 61271, 82248, 68765]`, `exit_empty=[12613, 12663, 12052, 12222, 12102]`, `exit_64m=[111812, 73693, 74044, 111823, 113545]`.
- **VMA Baseline (`pt_mode=1`)**: `anon_pf_1page=[20058837, 20324757, 20915865, 20485136, 19725847]`, `memfd_faultaround_16p=[3656890, 3562299, 3760217, 3723592, 3796141]`, `mmap_populate_64m=[2965, 3476, 2745, 1803, 1563]`, `mmap_populate_read_64m=[20238792, 20578739, 20302236, 21208220, 20339314]`, `fork_64m=[3797373, 3420603, 3932909, 4254550, 3788166]`, `child_read_64m=[133161, 132209, 133000, 131969, 131358]`, `parent_read_64m=[122933, 98699, 114167, 123173, 116390]`, `mprotect_ro_2m=[77059, 79674, 83961, 71379, 77741]`, `mprotect_ro_64m=[2364554, 2540744, 2511059, 2453791, 2572941]`, `cow_write_1ref=[26275704, 25466601, 26734894, 25567393, 26596523]`, `cow_write_2ref=[34260175, 34852799, 33605117, 34338169, 33244531]`, `munmap_64m=[1781931, 1783984, 756728, 1783784, 1784475]`, `exit_empty=[123549, 122964, 127810, 128053, 124597]`, `exit_64m=[1936001, 1969293, 1945452, 2042856, 2010481]`, `grant_create_us=[64113, 77407, 78292, 92991, 73102]` (median `77,407 us`, mean `77,181.0 us`).
- **Direct PTE (`pt_mode=0`)**: `anon_pf_1page=[15045862, 14399006, 13592855, 13731741, 13525327]`, `memfd_faultaround_16p=[2213732, 1905124, 2058510, 2052971, 2085620]`, `mmap_populate_64m=[1793, 2996, 1472, 1854, 2885]`, `mmap_populate_read_64m=[14067718, 13920692, 14329711, 13289531, 14712919]`, `fork_64m=[2009598, 1802678, 2183175, 1793355, 2213359]`, `child_read_64m=[156042, 123914, 130185, 133381, 130446]`, `parent_read_64m=[111361, 122421, 118064, 119105, 110300]`, `mprotect_ro_2m=[21259, 21209, 21139, 21830, 21048]`, `mprotect_ro_64m=[658350, 649073, 651207, 673086, 663369]`, `cow_write_1ref=[21206852, 20331599, 20523957, 21181357, 20544457]`, `cow_write_2ref=[25327610, 24374497, 24703381, 24544189, 24511434]`, `munmap_64m=[681393, 641540, 1662174, 1701665, 641980]`, `exit_empty=[117341, 114345, 115865, 112747, 111667]`, `exit_64m=[1917425, 1837151, 1866162, 1914414, 1884451]`, `grant_create_us=[145767, 50211, 119496, 52393, 61347]` (median `61,347 us`, mean `85,842.8 us`).

### 3.2 `POC_STATS_JSON` Service-Call Elimination (`R1..R5`)

| Counter | VMA Baseline (`pt_mode=1`, `R1..R5`) | Direct PTE (`pt_mode=0`, `R1..R5`) |
|---|---|---|
| `vm_creates` / `vm_destroys` | 26 / 26 on all 5 boots | 26 / 26 on all 5 boots |
| `exceptions` / `page_faults` | 777,898 / 777,898 on all 5 boots | 777,898 / 777,898 on all 5 boots |
| `vm_maps` | `[991235, 998094, 1004218, 988701, 1007123]` | **0** on all 5 boots |
| `vm_protects` | `[379409, 372550, 366426, 381943, 363521]` | **0** on all 5 boots |
| `vm_unmaps` | `[117534, 124393, 130517, 115000, 133422]` | **0** on all 5 boots |
| `vm_flushes` | `[114678, 107819, 101695, 117212, 98790]` | `232,212` on all 5 boots |
| `fpu_saves` | `[1404, 1439, 1405, 1518, 1388]` | `[1071, 1044, 1062, 1047, 1044]` |
| `virqs` | `[65, 79, 90, 83, 63]` | `[73, 62, 75, 52, 71]` |

Direct PTE completely eliminates all ~1.49M `OP_VM_MAP` / `OP_VM_PROTECT` / `OP_VM_UNMAP` host transitions (`vm_maps = vm_protects = vm_unmaps = 0`), yielding **3.81x** speedup on `mprotect_ro_64m`, **3.67x** on `mprotect_ro_2m`, **2.62x** on `munmap_64m`, **1.89x** on `fork_64m`, **1.81x** on `memfd_faultaround_16p`, **1.48x** on `anon_pf_1page` and `mmap_populate_64m`, **1.45x** on `mmap_populate_read_64m`, **1.40x** on `cow_write_2ref`, and **1.28x** on `cow_write_1ref`.

### 3.3 `poc_async_destroy` Ablation (6 KVM Boots, Direct PTE)

| Mode | `exit_empty` (ns) [Med] | `exit_64m` (ns) [Med] | Total QEMU Wall (ms) [Med] | `grant_create_us` | `fpu_saves` / `virqs` |
|---|---|---|---|---|---|
| `poc_async_destroy=0` (sync RCU) | `[114109, 112521, 109031]` **112,521** | `[1899821, 1921954, 1828476]` **1,899,821** (115.96 ns/p) | `[2195, 2188, 2212]` **2,195** | `[75148, 54587, 54350]` | `[1041, 1050, 1052]` / `[58, 49, 51]` |
| `poc_async_destroy=1` (`call_rcu`) | `[83303, 97680, 73022]` **83,303** (**1.35x**) | `[745896, 1866866, 768816]` **768,816** (46.92 ns/p, **2.47x**) | `[1979, 1993, 1966]` **1,979** (-216 ms) | `[80635, 60521, 66230]` | `[948, 969, 974]` / `[51, 49, 51]` |

All 6 ablation boots exited `0` with 0 host splats and clean `poc_endovisor: unloaded`. Note on ordering trade-off (`poc/linux/endovisor/poc_space.c:305-312`): when `poc_async_destroy=1`, `poc_space_teardown` defers `mmput_async(mm)` via `call_rcu` without calling `synchronize_rcu()` before returning to `VmSpace::drop`, which immediately frees Asterinas-owned lower page-table frames back to the grant allocator. Thus `poc_async_destroy=0` (`synchronize_rcu()`) remains the safe default against lockless host `perf`/NMI walkers until page-table reclamation itself is RCU-deferred.

---

## 4. Safety, Isolation & PTI Verification Matrix

| Check | Configuration | Outcome | Key Evidence |
|---|---|---|---|
| KVM Direct-PTE Safety (`test_mm_safety`) | `-enable-kvm -cpu host -smp 2`, `poc_mode=poc-safety poc_pt_mode=direct poc_vcpus=2` | **PASS** | All 11 forwarded exceptions (`#DE,#DB,#BP,#OF,#UD,#SS,#GP,#PF,#MF,#XM,#AC`) `ok=1`; `pf_rcx_r11_preserve=1`; `prot_none_softw2=1`; `pt_alloc_race_2vcpu errors=0 ok=1` (`1,000` rounds); `kernel_efault=1`; `SAFETY suite_done 1`; `exit_code=0`, 0 splats, clean `rmmod`. |
| QEMU TCG `-cpu SapphireRapids` | `-accel tcg -cpu SapphireRapids -smp 2`, `poc_mode=poc-safety` vs `native-safety` | **TCG limitation** | TCG 11.1.3 warns `CPUID[0xD,1].EAX.xfd [bit 4]` unsupported; `de/db/bp/of/ud/gp/pf/mf`, `pf_rcx_r11_preserve`, `prot_none_softw2`, `pt_alloc_race_2vcpu`, `kernel_efault` all passed (`1`), while `exc_ss`/`exc_xm`/`exc_ac` failed identically on both `poc-safety` and `native-safety` under TCG (`0` host splats). |
| Sandbox Kill / Eviction (`poc_kill_ms=50`) | KVM `poc-syscall` and `poc-mm` (`poc_grant_mb=256`, `poc_vcpus=2`) | **PASS** | Both printed `RUN_POC exit_kind=killed exit_code=9 ... exit_msg="killed by holder"` (`INIT: /bin/run-poc exited 131`), 0 splats, clean `poc_endovisor: unloaded`. |
| `pti=on` Safety + MM (after `poc_switch.S` `objtool` fix) | KVM `CONFIG_CPU_MITIGATIONS=y` + `CONFIG_MITIGATION_PAGE_TABLE_ISOLATION=y` + `pti=on` | **PASS** | Host logged `Kernel/User page tables isolation: enabled`; after an initial `WARN_ONCE` (`__warn_thunk`) prior to fixing `poc_switch.S` (`CALL_NOSPEC` + `STACK_FRAME_NON_STANDARD`, removing `OBJECT_FILES_NON_STANDARD_poc_switch.o := y`), re-running both `pti=on` boots produced **0** `__warn_thunk` / `WARNING` / `BUG` / `Oops` splats. `SAFETY suite_done 1` (`11/11` exceptions + all checks) and `MM_RESULT suite_done 1` (`anon_pf_1page=29,659,225 ns`, `memfd_faultaround_16p=2,588,187 ns`, `fork_64m=1,796,851 ns`, `mprotect_ro_64m=666,344 ns`, `cow_write_1ref=33,929,416 ns`, `cow_write_2ref=43,054,847 ns`, `munmap_64m=1,694,102 ns`, `exit_64m=764,518 ns`, `grant_create_us=451,025`). |
| Restored Unmitigated Baseline Sanity | KVM `Linux 6.12.0 #5` (`# CONFIG_CPU_MITIGATIONS is not set`), `poc_endovisor.ko` (`80,816` B) | **PASS** | `SAFETY suite_done 1` (11/11 exceptions + `pf_rcx_r11_preserve=1` + `prot_none_softw2=1` + `pt_alloc_race_2vcpu errors=0 ok=1` + `kernel_efault=1`), `exit_code=0`, 0 splats, clean `poc_endovisor: unloaded`. |

---

## 5. Pass-2 Syscall Hot-Path Optimization & Single-`cfg` Cleanup

Following the initial Stage 3/4 measurements above, dead Asterinas-on-Asterinas host code and diagnostic `cfg`s were purged across `poc/{ostd,kernel,osdk,linux/endovisor}` (retaining only `feature = "kernelet"`), and two optimization passes reduced `getpid_ns` median latency on Asterinas-on-Linux from `122.91` ns (`126.47` ns immediately post-purge) to **`94.15` ns** while keeping `SAFETY` and both `direct` and `vma` `MM` suites green.

### 5.1 Four-Way KVM Syscall + FPU Comparison (`5`-Boot Medians & Means, `-enable-kvm -cpu host -smp 2 -m 1024M`)

| Metric | Native Linux Median [Mean] (ns) | Native Bare-Metal Asterinas Median [Mean] (ns) | Pre-Opt Asterinas-on-Linux (§2.1) (ns) | Pass-2 Optimized Asterinas-on-Linux Median [Mean] (ns) | `Pass-2 / Native Linux` | `Pass-2 / Bare-Metal Ast` |
|---|---:|---:|---:|---:|---:|---:|
| `getpid_ns` (`1M` calls) | 38.30 [38.31] | 50.35 [50.55] | 122.91 [123.24] | **94.15 [94.10]** | **2.46x** | **1.87x** |
| `fpu_sse_getpid_ns` (x87+SSE live) | 37.97 [37.86] | 55.86 [56.27] | 124.21 [124.22] | **101.77 [100.30]** | **2.68x** | **1.82x** |
| `fpu_avx_getpid_ns` (x87+AVX live) | 38.56 [38.60] | 51.52 [51.35] | 124.61 [124.01] | **95.34 [95.20]** | **2.47x** | **1.85x** |
| `fpu_switch_sse_aba_ns` (`50k` CPU0 trips) | 1015.76 [1017.56] | 752.02 [769.66] | 1505.06 [1511.17] | **1376.76 [1373.43]** | **1.36x** | **1.83x** |
| `fpu_switch_avx_aba_ns` (`50k` CPU0 trips) | 1066.94 [1068.23] | 824.17 [815.03] | 1522.05 [1531.05] | **1411.25 [1409.22]** | **1.32x** | **1.71x** |

- **Pass-2 Raw Per-Boot Numbers (ns)**:
  - **Native Linux (`kernelet_mode=native-syscall`, 5 interleaved boots)**: `getpid_ns=[39.17, 38.13, 38.30, 37.55, 38.42]`, `fpu_sse_getpid_ns=[37.97, 37.74, 38.08, 38.09, 37.40]`, `fpu_avx_getpid_ns=[38.56, 38.63, 37.87, 38.32, 39.64]`, `fpu_switch_sse_aba_ns=[1008.65, 1028.85, 1019.66, 1015.76, 1014.86]`, `fpu_switch_avx_aba_ns=[1057.61, 1065.67, 1076.89, 1074.04, 1066.94]`; all boolean checks and `suite_done=1` on all 5 boots.
  - **Native Bare-Metal Asterinas (`asterinas-osdk-bin.elf`, `8,314,568` B, `-machine q35,kernel-irqchip=split -device isa-debug-exit,iobase=0xf4,iosize=0x04`, 5 boots)**: `getpid_ns=[50.28, 50.25, 50.49, 51.37, 50.35]`, `fpu_sse_getpid_ns=[61.81, 50.90, 60.57, 55.86, 52.20]`, `fpu_avx_getpid_ns=[50.76, 51.52, 51.05, 51.84, 51.59]`, `fpu_switch_sse_aba_ns=[760.85, 740.91, 843.43, 752.02, 751.11]`, `fpu_switch_avx_aba_ns=[770.62, 826.69, 872.11, 781.56, 824.17]`; `reg_preserve_*`, `fpu_*_getpid_ok`, and `rt_sigreturn_*` all passed (`1`), while `smp_check` and `fpu_switch_*_ok` reported `0` solely because glibc `sched_getcpu()` via the prebuilt Linux vDSO returns `123` (`0x7b`) on both bare-metal CPUs instead of `0`/`1`.
  - **Pass-2 Optimized Asterinas-on-Linux (`kernelet_mode=kernelet-syscall kernelet_pt_mode=direct kernelet_vcpus=2`, 5 interleaved boots)**: `getpid_ns=[93.65, 94.49, 94.71, 94.15, 93.49]`, `fpu_sse_getpid_ns=[95.08, 102.57, 101.77, 102.27, 99.82]`, `fpu_avx_getpid_ns=[94.19, 95.34, 96.02, 95.47, 94.96]`, `fpu_switch_sse_aba_ns=[1403.52, 1349.10, 1359.92, 1377.87, 1376.76]`, `fpu_switch_avx_aba_ns=[1432.61, 1390.24, 1411.25, 1420.06, 1391.94]`; all boolean checks and `suite_done=1` on all 5 boots, `grant_create_us=[27354, 26616, 27587, 26497, 26960]`, `fpu_saves=[872, 879, 809, 888, 869]`, `fpu_restores=[874, 881, 811, 890, 871]`, `non_sysret=[9, 9, 9, 12, 12]`, `virqs=[60, 54, 67, 60, 69]`.

### 5.2 Key Optimizations, SMP Fix & Hygiene Verification

- **Endovisor (`poc/linux/endovisor/endovisor.ko`, `94,760` B)**: Added `ccflags-y += -O2` in `poc/linux/endovisor/Makefile` (inlining `fatal_signal_pending` on syscall entry/exit); cached `event_rsp` stack validation in `enter_user_event` (`carrier->cached_event_rsp`, invalidated under `stack_mutex` via `sandbox->kstack_free_gen` before clearing `live_stacks_bitmap` in `poc/linux/endovisor/grant.c`) and replaced `/` and `%` in `stack_pool_contains` with power-of-two shifts/masks; replaced `smp_mb()` in `do_user_run_on_linux` with `barrier()` paired with unconditional `set_notify_resume` on `virq_raise`; and added `jump_user_run` in `poc/linux/endovisor/switch.S` (`STACK_FRAME_NON_STANDARD`) to switch `%rsp` and directly `call do_user_run_on_linux`.
- **vOSTD (`poc/ostd`) & Cross-vCPU `active_pt_regs` Fix**: Added the zero-initialized `.bss` `KERNELET_FAST_CPU` (`FastCpuTable`) lookup table populated once in `_kernelet_entry` (`poc/ostd/src/kernelet/entry.rs`, `poc/ostd/src/arch/x86/cpu/kernelet_local.rs`) so `record_asm!`/`cpu_local_asm!` resolve `vrec`/`local_base`/`urec` in 3 loads without `imul`; boxed `LinuxPtRegs` in `UserContextRepr::Owned` to shrink `UserContext` to `<= 40` bytes; fused `.text.kernelet_cpu_access` entry (`fast_enter_user_event`) and exit (`try_disable_with_guards_if_no_preempt`) blocks, shrinking `user_event_entry`'s frame in `kernelet-image.elf` (`14,730,448` B) to `72` bytes (`sub $0x48,%rsp`, down from `1,072` bytes); passed `&Self::LocalData` directly in `UserEventHandler` (verified once by `TypeId` in `build_user_with_stack`); and fixed cross-vCPU `pt_regs` tracking by storing `active_pt_regs: AtomicPtr<LinuxPtRegs>` on `Task` (`poc/ostd/src/task/mod.rs`, updated on `after_switching_to` and `user_event_entry`) instead of a stale per-vCPU pointer.
- **`aster-core` (`poc/kernel`)**: Extracted `#[cold] #[inline(never)]` error/stop helpers (`handle_caught_oops`, `exit_current_after_oops`, `wait_while_stopped`); switched `syscall_dispatch` in `poc/kernel/core/src/syscall/mod.rs` to 3 register args `(syscall_number, ctx, user_ctx)` with 0-argument fast arms (zero `rdi..r9` stack spills on `SYS_GETPID`); and routed `LinuxAbi::syscall_args` (`poc/kernel/core/src/arch/x86/cpu.rs`) to `UserContext::syscall_args::<N>` under `feature = "kernelet"`.
- **Regression, Build & Single-`cfg` Hygiene**: Pass-2 `kernelet-safety` (`direct`, `SAFETY suite_done=1`, `exit_code=0`), `kernelet-mm` (`direct` and `vma`, `MM_RESULT suite_done=1 1.00`, `exit_code=0`), and `kernelet-mm` (`direct`, `kernelet_kill_ms=50`, `exit_kind=killed exit_code=9`, `INIT: result=131`) all passed with `0` host kernel splats and clean `endovisor: unloaded`. Repo-wide `cfg` audit across `poc/{ostd,kernel,osdk}` confirmed only `feature = "kernelet"` remains (`0` dead-code matches), and `cargo-osdk` built both `--release --kernelet` (0 unsafe-audit violations) and native bare-metal `--release --boot-method vmm-direct` with 0 code warnings.
