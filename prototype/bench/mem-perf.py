#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Aggregates the memory costs (E6 and E9) over the boots of `make mem-perf`.

Each boot's log carries lines

    MEM-PERF <name> n=<n> median=<c> p99=<c> min=<c> max=<c>

in TSC cycles, from the mem kernel (`mem/src/lib.rs`, perf_main). For every
measurement this prints the median of the per-boot medians, the median and the
worst of the per-boot p99s, and the same in nanoseconds at the TSC frequency
the endovisor logged. It also lists the counters the kernel printed beside
them (MEM-RESULT lines), as the set of values seen across the boots. It exits
non-zero if a log is missing a measurement.
"""

import glob
import os
import re
import statistics
import sys

PERF = re.compile(r"MEM-PERF (\S+) n=(\d+) median=(\d+) p99=(\d+) min=(\d+) max=(\d+)")
RESULT = re.compile(r"MEM-RESULT (\S+) (.*)")
TSC = re.compile(r"tsc (\d+) kHz")

ORDER = [
    ("first_touch", "first touch of a mapped page (per page)"),
    ("map_single", "map, one page per call (per call)"),
    ("map_single_avg", "map, 512 pages under one cursor (per page)"),
    ("protect_2m", "protect 2 MiB read-only + flush (per 512 pages)"),
    ("read_after_protect", "read after protect (per page)"),
    ("copy_64", "copy 64 B out of tenant memory"),
    ("copy_4k", "copy 4 KiB out of tenant memory"),
    ("fork_64m", "fork, 64 MiB mapped"),
    ("child_reads_64m", "the child reads all 64 MiB"),
    ("fork_child_reads_64m", "fork + the child's reads"),
    ("parent_rereads_64m", "the parent re-reads all 64 MiB after fork"),
    ("munmap_64m", "munmap of the 64 MiB"),
]

REQUIRED = ("first_touch", "map_single", "protect_2m", "copy_64", "fork_64m", "munmap_64m")


def load(path):
    perf, results, khz = {}, [], None
    with open(path, errors="replace") as f:
        for line in f:
            line = line.rstrip("\r\n")
            m = TSC.search(line)
            if m and khz is None:
                khz = int(m.group(1))
            m = PERF.search(line)
            if m:
                perf[m.group(1)] = dict(n=int(m.group(2)), median=int(m.group(3)),
                                        p99=int(m.group(4)))
            m = RESULT.search(line)
            if m:
                results.append((m.group(1), m.group(2)))
    return perf, results, khz


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else ".build/mem"
    rc = 0
    boots = []
    khz = None
    for fpath in sorted(glob.glob(os.path.join(d, "perf-*.log"))):
        perf, results, k = load(fpath)
        khz = khz or k
        boots.append((fpath, perf, results))
    if not boots:
        print(f"no perf-*.log in {d}")
        return 1
    if khz is None:
        print("no TSC frequency in any log")
        return 1
    ns = lambda c: c * 1e6 / khz

    print(f"TSC {khz} kHz; {len(boots)} boot(s)")
    print()
    print("| measurement | boots | median (cycles) | p99 median | p99 worst | median (ns) | p99 worst (ns) |")
    print("|---|---:|---:|---:|---:|---:|---:|")
    for name, desc in ORDER:
        rows = [p[name] for _, p, _ in boots if name in p and p[name]["n"] > 0]
        if not rows:
            continue
        med = statistics.median(r["median"] for r in rows)
        p99m = statistics.median(r["p99"] for r in rows)
        p99w = max(r["p99"] for r in rows)
        print(f"| {desc} | {len(rows)} | {med:.0f} | {p99m:.0f} | {p99w:.0f} | "
              f"{ns(med):,.0f} | {ns(p99w):,.0f} |")
    print()
    # The counters beside the times.
    tot = {}
    for _, _, results in boots:
        for key, rest in results:
            for kv in rest.split():
                if "=" not in kv:
                    continue
                k, v = kv.split("=", 1)
                if v.isdigit():
                    tot.setdefault(key, {}).setdefault(k, []).append(int(v))
    for key in sorted(tot):
        parts = ", ".join(f"{k} {sorted(set(v))}" for k, v in tot[key].items())
        print(f"  {key}: {parts}")
    for fpath, perf, _ in boots:
        for name in REQUIRED:
            if name not in perf:
                print(f"  MISSING {name} in {fpath}")
                rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
