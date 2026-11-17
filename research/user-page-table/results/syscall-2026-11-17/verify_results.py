import importlib.util
import json
from pathlib import Path
import statistics


root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "measurement", root / "sources/poc/linux/bench/measure_syscall.py"
)
measurement = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measurement)
verified = {}
manifests = {}
benchmark_hashes = set()

for name in ("final-ab", "mitigations-off", "mitigations-auto", "tool-validation"):
    directory = root / name
    manifest = json.loads((directory / "manifest.json").read_text())
    manifests[name] = manifest
    records = [json.loads(line) for line in (directory / "records.jsonl").read_text().splitlines()]
    summary = json.loads((directory / "summary.json").read_text())
    assert len(records) == manifest["boots"] * len(manifest["variants"])
    assert measurement.sha256(directory / "driver.py") == manifest["driver_sha256"]
    assert measurement.sha256(directory / "qemu_driver.py") == manifest["qemu_driver_sha256"]
    kernel_dir = root / ("mitigation-kernel" if name.startswith("mitigations-") else "baseline")
    assert measurement.sha256(kernel_dir / "bzImage") == manifest["kernel_sha256"]
    assert measurement.sha256(kernel_dir / "linux.config") == manifest["config_sha256"]
    for variant in manifest["variants"]:
        actual = measurement.inputs(Path(variant["initrd"]))
        for key in ("initrd_sha256", "benchmark_sha256", "image_sha256", "module_sha256"):
            assert actual[key] == variant[key], (name, variant["label"], key)
        benchmark_hashes.add(actual["benchmark_sha256"])
    frequencies = []
    for record in records:
        assert record["valid"] is True and record["qemu_rc"] == 0
        assert record["pinned_vcpu_map"] == {"0": 10, "1": 12}
        assert record["pinned_io_cpu"] == 14
        serial = directory / f"r{record['round']}-{record['label']}.serial.log"
        samples = measurement.parse_samples(serial.read_text())
        assert samples == record["samples"]
        assert statistics.median(s["elapsed_ns"] / s["iterations"] for s in samples) == record["median_ns"]
        frequencies.extend(s["tsc_ticks"] / s["elapsed_ns"] for s in samples)
    for item in summary:
        values = [r["median_ns"] for r in records if r["label"] == item["label"]]
        assert values == item["boots"] and len(values) == manifest["boots"]
        assert statistics.median(values) == item["median_ns"]
        assert min(values) == item["min_ns"] and max(values) == item["max_ns"]
    verified[name] = {
        "valid_boots": len(records), "valid_windows": len(records) * 9,
        "tsc_monotonic_ghz_range": [min(frequencies), max(frequencies)],
        "summary": summary,
    }

assert len(benchmark_hashes) == 1
rejected = root / "tool-rejected-boot"
failures = [json.loads(line) for line in (rejected / "records.jsonl").read_text().splitlines()]
assert len(failures) == 1 and failures[0]["valid"] is False
assert failures[0]["error"] and failures[0]["qemu_rc"] != 0
assert "median_ns" not in failures[0] and not (rejected / "summary.json").exists()
verified["rejected_boot_recorded"] = True
for key in ("kernel_sha256", "config_sha256", "variants", "suite", "machine", "order"):
    assert manifests["mitigations-off"][key] == manifests["mitigations-auto"][key], key

primary = {s["label"]: s["median_ns"] for s in verified["final-ab"]["summary"]}
verified["primary_comparison"] = {
    "median_reduction_ns": primary["K0"] - primary["K4"],
    "median_reduction_percent": 100 * (primary["K0"] - primary["K4"]) / primary["K0"],
    "final_minus_linux_ns": primary["K4"] - primary["L"],
    "final_over_linux_ratio": primary["K4"] / primary["L"],
}
off = {s["label"]: s["median_ns"] for s in verified["mitigations-off"]["summary"]}
auto = {s["label"]: s["median_ns"] for s in verified["mitigations-auto"]["summary"]}
verified["mitigation_comparison"] = {
    "linux_auto_minus_off_ns": auto["L"] - off["L"],
    "kernelet_auto_minus_off_ns": auto["K"] - off["K"],
    "off_kernelet_minus_linux_ns": off["K"] - off["L"],
    "auto_kernelet_minus_linux_ns": auto["K"] - auto["L"],
}

for path in sorted((root / "validation").glob("*.json")):
    result = json.loads(path.read_text())
    assert result["qemu_rc"] == 0, path
    for stat in result.get("stats", []):
        assert stat["vm_creates"] == stat["vm_destroys"], path
        assert stat["grant_grains_allocated"] == stat["grant_grains_freed"], path
    verified.setdefault("functional_cases", []).append(path.stem)

(root / "verification.json").write_text(json.dumps(verified, indent=2) + "\n")
print(json.dumps({key: verified[key] for key in ("primary_comparison", "mitigation_comparison", "functional_cases")}, indent=2))
