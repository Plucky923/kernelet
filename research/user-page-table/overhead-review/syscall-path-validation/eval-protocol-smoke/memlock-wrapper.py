import json
from pathlib import Path
import resource
import subprocess
import sys


root = Path.cwd()
before = resource.getrlimit(resource.RLIMIT_MEMLOCK)
resource.setrlimit(resource.RLIMIT_MEMLOCK, (0, before[1]))
after = resource.getrlimit(resource.RLIMIT_MEMLOCK)
record = {
    "memlock_before": {"soft_bytes": before[0], "hard_bytes": before[1]},
    "memlock_for_cli_and_qemu": {"soft_bytes": after[0], "hard_bytes": after[1]},
    "cli_args": sys.argv[1:],
}
(root / ".syscall-overhead-work/standards-memlock.json").write_text(
    json.dumps(record, indent=2) + "\n"
)
raise SystemExit(subprocess.call(
    [sys.executable, "-m", "host.cli", *sys.argv[1:]], cwd=root / "poc/eval",
))
