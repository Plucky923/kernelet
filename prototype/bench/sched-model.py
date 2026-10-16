#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""The reference model of the sched kernel's scheduling policy.

It reads a serial log, takes the scenario from the kernel's own `SCHED-TASK` and
`SCHED-EV` lines and the trace from its `SCHED: sw` lines, and asks whether the
trace is a *legal* schedule of the policy — not whether it is one particular
interleaving, because two virtual CPUs interleave as they please.

The policy, in the five rules this checks:

  1. pinning        a task only ever runs on the virtual CPU it is pinned to;
  2. strict priority  a task never runs on a virtual CPU while a more urgent task
                    is runnable there;
  3. round robin    inside a priority level, a task never runs twice in a row on a
                    virtual CPU while another runnable task of that level waits;
  4. the slice      a tick never leaves a task running longer than the slice plus
                    one tick — counted in the virtual CPU's *own* ticks, because a
                    virtual CPU the host has descheduled receives none and five
                    ticks of slice can be seven milliseconds of wall clock;
  5. wake-up        a task woken into a level more urgent than the one running gets
                    the processor within one tick plus slack.

Usage: sched-model.py <serial.log>
"""

import re
import sys

SLICE_TICKS = 5
TICK_MS = 1
WAKE_SLACK_MS = 3

re_task = re.compile(
    r"SCHED-TASK t(\d+) prio=(\d+) pin=(-?\d+) kind=(\w+)")
re_sw = re.compile(
    r"SCHED: sw (\d+) v(\d+) (\d+)->(\d+) p(\d+) r(\w+) @(\d+) c(\d+) k(\d+)")
re_ev = re.compile(r"SCHED-EV (\w+) t(\d+) v(\d+) @(\d+)")
re_conf = re.compile(r"SCHED-CONF mode=(\S+) dur=(\d+) vcpus=(\d+)")


def main(path):
    tasks = {}
    switches = []
    events = []
    conf = None

    with open(path, "rb") as f:
        text = f.read().decode("utf-8", "replace").replace("\r", "")

    for line in text.split("\n"):
        m = re_conf.search(line)
        if m:
            conf = (m.group(1), int(m.group(2)), int(m.group(3)))
        m = re_task.search(line)
        if m:
            tid = int(m.group(1))
            tasks[tid] = {
                "prio": int(m.group(2)),
                "pin": int(m.group(3)),
                "kind": m.group(4),
            }
        m = re_sw.search(line)
        if m:
            switches.append({
                "seq": int(m.group(1)), "vcpu": int(m.group(2)),
                "prev": int(m.group(3)), "next": int(m.group(4)),
                "level": int(m.group(5)), "reason": m.group(6),
                "ms": int(m.group(7)), "tsc": int(m.group(8)),
                "ticks": int(m.group(9)),
            })
        m = re_ev.search(line)
        if m:
            events.append({"kind": m.group(1), "task": int(m.group(2)),
                           "vcpu": int(m.group(3)), "ms": int(m.group(4))})

    if conf is None or not tasks or not switches:
        print("  BAD     no trace in %s (conf=%s, %d task(s), %d switch(es))"
              % (path, conf, len(tasks), len(switches)))
        return 1

    switches.sort(key=lambda s: s["seq"])
    print("  info    scenario %s: %d task(s), %d switch(es), %d event(s)"
          % (conf[0], len(tasks), len(switches), len(events)))

    bad = []

    def fail(rule, msg):
        if len(bad) < 40:
            bad.append("%s: %s" % (rule, msg))

    # --- 1. pinning -------------------------------------------------------
    for s in switches:
        t = tasks.get(s["next"])
        if t is None:
            fail("unknown task", "switch %d runs t%d, never announced"
                 % (s["seq"], s["next"]))
            continue
        if t["pin"] >= 0 and t["pin"] != s["vcpu"]:
            fail("pinning", "t%d is pinned to v%d but ran on v%d at switch %d"
                 % (s["next"], t["pin"], s["vcpu"], s["seq"]))

    # --- runnability, reconstructed from the trace ------------------------
    # A task stops being runnable when it is switched away from with reason
    # `wait` or `exit`, and becomes runnable again the next time it is run.
    # Everything announced is runnable from the start.
    sleeping = set()
    exited = set()
    current = {}     # vcpu -> (task, since_ms)
    last_at_level = {}   # (vcpu, level) -> task that ran last there

    def runnable_on(vcpu, exclude):
        out = []
        for tid, t in tasks.items():
            if tid in exited or tid in sleeping or tid == exclude:
                continue
            if t["pin"] >= 0 and t["pin"] != vcpu:
                continue
            if current.get(vcpu, (None, 0, 0))[0] == tid:
                continue
            out.append(tid)
        return out

    for s in switches:
        v, nxt, prev, level = s["vcpu"], s["next"], s["prev"], s["level"]

        # --- 4. the slice -------------------------------------------------
        if s["reason"] == "tick" and prev in tasks:
            since = current.get(v, (None, None, None))
            if since[0] == prev and since[2] is not None:
                held = s["ticks"] - since[2]
                if held > SLICE_TICKS + 1:
                    fail("slice", "t%d held v%d for %d of its tick(s) (slice %d "
                                  "+ one) before switch %d"
                         % (prev, v, held, SLICE_TICKS, s["seq"]))

        # --- 2. strict priority -------------------------------------------
        my_prio = tasks[nxt]["prio"] if nxt in tasks else level
        for other in runnable_on(v, nxt):
            if tasks[other]["prio"] < my_prio:
                fail("priority", "switch %d ran t%d (p%d) on v%d while t%d (p%d) "
                                 "was runnable there"
                     % (s["seq"], nxt, my_prio, v, other, tasks[other]["prio"]))
                break

        # --- 3. round robin inside the level ------------------------------
        peers = [t for t in runnable_on(v, nxt)
                 if tasks[t]["prio"] == my_prio]
        if last_at_level.get((v, my_prio)) == nxt and peers:
            fail("round robin", "t%d ran twice in a row at p%d on v%d (switch %d) "
                                "while t%s waited"
                 % (nxt, my_prio, v, s["seq"], peers[0]))
        last_at_level[(v, my_prio)] = nxt

        # --- bookkeeping --------------------------------------------------
        if s["reason"] == "wait" and prev in tasks:
            sleeping.add(prev)
        if s["reason"] == "exit" and prev in tasks:
            exited.add(prev)
        sleeping.discard(nxt)
        current[v] = (nxt, s["ms"], s["ticks"])

    # --- 5. a wake into a more urgent level preempts within a tick --------
    woken_late = 0
    for e in events:
        if e["kind"] != "wake":
            continue
        tid = e["task"]
        t = tasks.get(tid)
        if t is None:
            continue
        v = t["pin"] if t["pin"] >= 0 else e["vcpu"]
        ran = [s for s in switches
               if s["next"] == tid and s["vcpu"] == v and s["ms"] >= e["ms"]]
        if not ran:
            continue     # the run may be past the end of the trace
        if ran[0]["ms"] - e["ms"] > TICK_MS + WAKE_SLACK_MS:
            woken_late += 1
    if woken_late:
        fail("wake-up", "%d wake-up(s) of a more urgent task took longer than "
                        "one tick plus %d ms" % (woken_late, WAKE_SLACK_MS))

    levels = sorted({s["level"] for s in switches})
    print("  info    levels exercised: %s; reasons: %s"
          % (levels, sorted({s["reason"] for s in switches})))

    if bad:
        for b in bad:
            print("  BAD     %s" % b)
        print("  BAD     the trace is not a legal schedule of the policy "
              "(%d violation(s))" % len(bad))
        return 1

    print("  ok      the trace is a legal schedule of the policy: pinning, "
          "strict priority, round robin, the slice and wake-up preemption")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else ".build/serial.log"))
