"""Summarise the damage tally printed by Godot balance runs.

    .venv/Scripts/python tools/godot_tally.py extracted/godot_bal_*.log

Each run ends with a line like
    race: state=racing realm=1 ... hp=31 ... tally={"ability":12,...}
"""
import json
import re
import sys

ROW = re.compile(r"race: state=(\w+) realm=(\d+) lap=(\d+) rank=(\d+) karts=(\d+) hp=(-?\d+) sp=(\d+) spells=(\d+) slain=(\d+) fps=(\d+) tally=(\{.*\})")


def main(paths):
    rows = []
    for p in paths:
        try:
            text = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        m = None
        for m in ROW.finditer(text):
            pass
        if not m:
            print("%-32s no tally line" % p)
            continue
        state, realm, lap, rank, karts, hp, sp, spells, slain, fps, tally = m.groups()
        t = json.loads(tally)
        taken = sum(float(t.get(k, 0)) for k in ("ability", "lap", "mob", "bolt", "wolf"))
        rows.append((p, state, int(lap), int(rank), int(hp), int(slain), t, taken))
        print("%-32s %-8s lap %s rank %s hp %3s slain %s | took %3d = spells %3d laps %3d bumps %3d bolts %3d wolves %3d | dealt %3d casts %2d sp +%d" % (
            p.split("/")[-1], state, lap, rank, hp, slain, taken, t.get("ability", 0), t.get("lap", 0), t.get("mob", 0),
            t.get("bolt", 0), t.get("wolf", 0), t.get("dealt", 0), t.get("casts", 0), int(sp) - int(t.get("sp_start", 0))))
    if rows:
        n = len(rows)
        print("avg took %.0f (spells %.0f, laps %.0f, bumps %.0f, bolts %.0f, wolves %.0f), avg hp left %.0f, avg slain %.1f" % (
            sum(r[7] for r in rows) / n,
            sum(float(r[6].get("ability", 0)) for r in rows) / n, sum(float(r[6].get("lap", 0)) for r in rows) / n,
            sum(float(r[6].get("mob", 0)) for r in rows) / n, sum(float(r[6].get("bolt", 0)) for r in rows) / n,
            sum(float(r[6].get("wolf", 0)) for r in rows) / n, sum(r[4] for r in rows) / n, sum(r[5] for r in rows) / n))


if __name__ == "__main__":
    main(sys.argv[1:])
