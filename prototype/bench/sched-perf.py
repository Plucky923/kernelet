#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Aggregates the switch and wake-up costs across the boots of `make sched-perf`.

Each boot reports, from inside the kernelet, the median and p99 of several
thousand samples of each measurement, and from user space the same measurements
made on native Linux threads and processes on the same two CPUs in the same
control group. This takes the median of the per-boot medians and the worst p99,
and says plainly which comparisons are apples to apples and which are not.

Usage: sched-perf.py <logs...>
"""

import re
import sys

re_k = re.compile(r"SCHED-PERF (\S+) n=(\d+) median=(\d+) p99=(\d+) min=(\d+)")
re_n = re.compile(r"NATIVE-PERF (\S+) n=(\d+) median=(\d+) p99=(\d+) min=(\d+)")
re_tsc = re.compile(r"tsc (\d+) kHz")

# What each measurement is, and what it may honestly be set beside.
NOTES = {
    "kernelet_yield_roundtrip_cycles":
        "two kernelet kernel tasks yielding to each other on one vCPU; "
        "two OSTD context switches, no system call, no address-space change",
    "kernelet_wake_same_vcpu_cycles":
        "a blocked level-0 kernelet task woken by a level-2 one on the same vCPU",
    "kernelet_wake_other_vcpu_cycles":
        "the same, woken from the other vCPU: the endovisor's kick and upcall",
    "kernelet_user_switch_other_mm_cycles":
        "two tenant threads of two different tenant processes alternating on one "
        "vCPU through a yield system call: two gate entries, one OSTD switch, one "
        "kernelet_switch_mm and one floating-point swap",
    "linux_process_yield_roundtrip_cycles":
        "two Linux processes on one CPU calling sched_yield(): the same plus an "
        "address-space switch",
    "linux_pipe_wake_same_cpu_cycles":
        "a pipe write that wakes a process on the same CPU, timed from the write "
        "to the woken side running",
    "linux_pipe_wake_other_cpu_cycles":
        "the same, across processors",
}

FAIR = [
    ("kernelet_user_switch_other_mm_cycles", "linux_process_yield_roundtrip_cycles",
     "apples to apples: both are user thread -> kernel -> other user thread in "
     "another address space, both counted from the same point in user mode"),
    ("kernelet_wake_other_vcpu_cycles", "linux_pipe_wake_other_cpu_cycles",
     "roughly apples to apples: a cross-processor wake-up timed from the waker's "
     "stamp to the woken side running. The Linux side also pays for a pipe write "
     "and read, which the kernelet side does not"),
    ("kernelet_yield_roundtrip_cycles", "linux_process_yield_roundtrip_cycles",
     "NOT apples to apples, and the most important number to read carefully: the "
     "kernelet pair never leaves kernel mode and makes no system call, the Linux "
     "pair makes two and changes address space"),
]


def main(paths):
    med = {}
    p99 = {}
    ns_per_cycle = None

    for path in paths:
        with open(path, "rb") as f:
            text = f.read().decode("utf-8", "replace").replace("\r", "")
        m = re_tsc.search(text)
        if m and not ns_per_cycle:
            khz = int(m.group(1))
            if khz:
                ns_per_cycle = 1.0e6 / khz
        for rx in (re_k, re_n):
            for m in rx.finditer(text):
                name, n = m.group(1), int(m.group(2))
                if n == 0:
                    continue
                med.setdefault(name, []).append(int(m.group(3)))
                p99.setdefault(name, []).append(int(m.group(4)))

    if not med:
        print("  BAD     no measurements in %s" % " ".join(paths))
        return 1

    def summarise(name):
        ms = sorted(med.get(name, []))
        ps = sorted(p99.get(name, []))
        if not ms:
            return None
        return ms[len(ms) // 2], ps[-1], len(ms)

    print("  info    %d boot(s); cycle counter %s"
          % (len(paths),
             ("%.4f ns per cycle" % ns_per_cycle) if ns_per_cycle else "unknown"))
    print("  %-46s %10s %10s %8s %8s" % ("measurement", "median", "p99", "med ns",
                                         "p99 ns"))
    rc = 0
    for name in sorted(med):
        s = summarise(name)
        if not s:
            continue
        m, p, runs = s
        if ns_per_cycle:
            print("  %-46s %10d %10d %8.0f %8.0f   (%d runs)"
                  % (name, m, p, m * ns_per_cycle, p * ns_per_cycle, runs))
        else:
            print("  %-46s %10d %10d %8s %8s   (%d runs)"
                  % (name, m, p, "-", "-", runs))

    print("  --- what may honestly be compared with what ---")
    for a, b, why in FAIR:
        sa, sb = summarise(a), summarise(b)
        if not sa or not sb:
            print("  info    %s vs %s: one of the two is missing" % (a, b))
            continue
        ratio = sa[0] / sb[0] if sb[0] else 0
        print("  info    %s median %d vs %s median %d (%.2fx)"
              % (a, sa[0], b, sb[0], ratio))
        print("          %s" % why)

    required = ["kernelet_yield_roundtrip_cycles",
                "kernelet_wake_same_vcpu_cycles",
                "linux_process_yield_roundtrip_cycles"]
    for name in NOTES:
        if name in med:
            continue
        if name in required:
            print("  BAD     %s was not measured" % name)
            rc = 1
        else:
            print("  info    %s was not measured in these boots" % name)

    # Not an assertion. The two are not the same work, and saying so is the
    # honest thing; what is asserted is only that the measurements happened and
    # that nothing in the runs went wrong.
    sk = summarise("kernelet_yield_roundtrip_cycles")
    sl = summarise("linux_process_yield_roundtrip_cycles")
    if sk and sl:
        print("  info    a kernelet task-switch round trip is %d cycles and a "
              "Linux process yield round trip %d on the same machine; the first "
              "does strictly less work, so read it as an upper bound on what the "
              "kernelet's own scheduler costs, not as a speed-up" % (sk[0], sl[0]))
    print("  ok      the measurements were taken over %d boot(s)" % len(paths))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
