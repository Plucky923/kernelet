from dataclasses import asdict
import json
from pathlib import Path
import re
import resource
import sys

root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(root / "poc/eval"))
from host.qemu_driver import run_qemu_with_pinning

results = root / "research/user-page-table/results/syscall-2026-11-17"
output = results / "validation"
output.mkdir(exist_ok=True)
resource.setrlimit(resource.RLIMIT_MEMLOCK, (0, resource.getrlimit(resource.RLIMIT_MEMLOCK)[1]))
cases = [
    ("direct-smp-fpu", "kernelet-syscall", "direct", "", "RESULT suite_done 1 bool"),
    ("direct-events", "kernelet-events", "direct", "", "RESULT suite_done 1 bool"),
    ("vma-events", "kernelet-events", "vma", "", "RESULT suite_done 1 bool"),
    ("direct-safety", "kernelet-safety", "direct", "", "SAFETY suite_done 1"),
    ("vma-safety", "kernelet-safety", "vma", "", "SAFETY suite_done 1"),
    ("lifecycle", "native-lifecycle", "direct", "", "RESULT suite_done 1 bool"),
    ("audit", "kernelet-syscall", "direct", "kernelet_mod_args=audit=1", "RESULT suite_done 1 bool"),
    ("kill", "kernelet-syscall", "direct", "kernelet_kill_ms=500", None),
]
for label, mode, pt_mode, extra, required in cases:
    if len(sys.argv) > 1 and label not in sys.argv[1:]:
        continue
    cmdline = (
        "console=ttyS0 panic=-1 nokaslr mitigations=off "
        f"kernelet_mode={mode} kernelet_pt_mode={pt_mode} "
        f"kernelet_vcpus=2 kernelet_grant_mb=256 kernelet_attach=exec {extra}"
    )
    result = run_qemu_with_pinning(
        kernel_path=results / "baseline/bzImage",
        initrd_path=results / "aligned-handoff/initrd.cpio.gz",
        cmdline=cmdline, vcpus=2, mem_mb=1024, timeout_sec=90,
        temp_root=root / "research/user-page-table/.syscall-cost-work/q",
        log_dir=output, log_prefix=label,
    )
    serial = result.serial_log
    expected_result = 137 if label == "kill" else 0
    assert f"INIT: result={expected_result}" in serial, label
    assert not re.search(r"BUG:|WARNING:|Oops:|Kernel panic", serial), label
    if required is not None:
        assert required in serial, label
    records = [json.loads(line.removeprefix("STATS_JSON "))
               for line in serial.splitlines() if line.startswith("STATS_JSON ")]
    for stats in records:
        assert stats["vm_creates"] == stats["vm_destroys"], (label, stats)
        assert stats["grant_grains_allocated"] == stats["grant_grains_freed"], (label, stats)
        if label == "audit":
            assert stats["syscalls"] >= 9_000_000, stats
            assert "non_sysret_precheck" in stats, stats
        else:
            assert "syscalls" not in stats and "non_sysret_precheck" not in stats, stats
        if label == "kill":
            assert stats["exit_kind_name"] == "killed", stats
    record = {key: value for key, value in asdict(result).items()
              if key not in ("serial_log", "stderr_log")}
    record.update(label=label, stats=records)
    (output / f"{label}.json").write_text(json.dumps(record, indent=2) + "\n")
    print(f"{label}: passed", flush=True)
