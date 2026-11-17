import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


sys.dont_write_bytecode = True
ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / "poc/eval"))

from host.invariants import validate_case_record
from host.qemu_driver import parse_serial_records
from host.schema import load_cases_toml


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", nargs=2, action="append", required=True, metavar=("TARGET", "PATH"))
    parser.add_argument("--case", action="append", required=True)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--payload", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    source_paths = [ROOT / "poc/eval/host" / name for name in (
        "schema.py", "qemu_driver.py", "invariants.py", "parsers.py",
    )]
    before = {str(path.relative_to(ROOT)): file_sha256(path) for path in source_paths}
    suite = load_cases_toml(ROOT / "poc/eval/configs/cases.toml")
    specs = {case_id: suite.cases[case_id] for case_id in args.case}
    report = {"sources_before": before, "logs": []}
    passed = True

    for target, log_path in args.log:
        path = Path(log_path)
        raw = path.read_bytes()
        serial = raw.decode("utf-8", errors="replace")
        lines = [line.strip() for line in serial.splitlines()]
        observed = {
            "target": target,
            "path": str(path),
            "sha256": hashlib.sha256(raw).hexdigest(),
            "case_frames": sum(line.startswith("EVAL_CASE_JSON ") for line in lines),
            "stats_frames": sum(line.startswith("STATS_JSON ") for line in lines),
        }
        try:
            records = parse_serial_records(serial, round_idx=1, target=target, specs=specs)
            noop = next((record.sandbox_stats for record in records
                         if record.case_id == "selfcheck.noop"), None)
            results = []
            for record in records:
                ok, reasons = validate_case_record(
                    specs[record.case_id], record, kernel_log=serial,
                    noop_stats=None if record.case_id == "selfcheck.noop" else noop,
                )
                results.append({"case_id": record.case_id, "valid": ok, "reasons": reasons})
                passed = passed and ok
            observed["records"] = results
            observed["accepted"] = all(result["valid"] for result in results)
        except (ValueError, KeyError, TypeError) as error:
            observed["accepted"] = False
            observed["error"] = str(error)
            passed = False
        observed["changed_while_reading"] = file_sha256(path) != observed["sha256"]
        passed = passed and not observed["changed_while_reading"]
        report["logs"].append(observed)

    archive_hash = file_sha256(args.archive)
    payload_hash = file_sha256(args.payload)
    # GNU cpio reads the archive; this script does not decode archive headers.
    extracted = subprocess.run(
        ["bash", "-o", "pipefail", "-c",
         'gzip -dc -- "$1" | cpio --extract --to-stdout --quiet -- "$2"',
         "read-existing-archive", str(args.archive), "payload/eval-payload.cpio"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    ).stdout
    embedded_hash = hashlib.sha256(extracted).hexdigest()
    archive_stable = archive_hash == file_sha256(args.archive)
    payload_stable = payload_hash == file_sha256(args.payload)
    matches = bool(extracted) and payload_hash == embedded_hash
    report["archive"] = {
        "path": str(args.archive), "sha256": archive_hash,
        "payload_path": str(args.payload), "payload_sha256": payload_hash,
        "embedded_payload_sha256": embedded_hash, "embedded_bytes": len(extracted),
        "payload_matches": matches, "archive_stable": archive_stable,
        "payload_stable": payload_stable,
    }
    passed = passed and matches and archive_stable and payload_stable
    after = {str(path.relative_to(ROOT)): file_sha256(path) for path in source_paths}
    report["sources_after"] = after
    report["sources_stable"] = before == after
    passed = passed and before == after
    report["passed"] = passed
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
