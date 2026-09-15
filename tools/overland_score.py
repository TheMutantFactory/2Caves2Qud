"""The overland scoreboard (docs/overland.md): every goal's check, run, graded, reported.

    .venv\\Scripts\\python.exe tools\\overland_score.py            # the headless goals
    .venv\\Scripts\\python.exe tools\\overland_score.py --screen   # plus the windowed, on-screen goals
    .venv\\Scripts\\python.exe tools\\overland_score.py --only G5  # one goal (comma list)

Writes reports/overland-score.md and prints the total. A goal scores only when its check
runs green here; a check that cannot run (no Godot, nothing baked) scores nothing and says
why. The numbers in docs/overland.md's table are the ones enforced below.
"""
import argparse
import datetime
import glob
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qud_assets
import qud_overland

GODOT_DEFAULT = r"C:\Users\danie\Downloads\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
REPORT = os.path.join(ROOT, "reports", "overland-score.md")
GOLDEN = os.path.join(ROOT, "reports", "overland", "golden")
SHOTS = os.path.join(ROOT, "reports", "overland", "shots")
PY = sys.executable

GOALS = [
    ("G1", "Overworld parsed", 5), ("G2", "Zone bake", 15), ("G3", "Chunk to art", 10),
    ("G4", "Paving", 10), ("G5", "Chunk streaming", 15), ("G6", "A race on the surface", 15),
    ("G7", "Free drive across zones", 10), ("G8", "Light bake", 10), ("G9", "On-screen regression", 10),
]


def godot_bin():
    g = os.environ.get("CAVES2_GODOT") or GODOT_DEFAULT
    return g if os.path.exists(g) else None


def run_godot(args, timeout=900, headless=True, quit_after=None):
    g = godot_bin()
    if g is None:
        return None, "no Godot (set CAVES2_GODOT)"
    cmd = [g] + (["--headless"] if headless else []) + ["--path", os.path.join(ROOT, "godot")]
    if quit_after:
        cmd += ["--quit-after", str(quit_after)]
    cmd += ["--"] + args
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace")
    except subprocess.TimeoutExpired as e:
        return (e.stdout or "") + (e.stderr or ""), "timeout after %ds" % timeout
    return (p.stdout or "") + (p.stderr or ""), None


def pytest_run(expr):
    p = subprocess.run([PY, "-m", "pytest", os.path.join(ROOT, "tools", "tests"), "-q", "-k", expr],
                       capture_output=True, text=True, cwd=ROOT, encoding="utf-8", errors="replace")
    tail = (p.stdout.strip().splitlines() or [""])[-1]
    return p.returncode == 0, tail


# --- the checks ------------------------------------------------------------------------

def g1():
    ok, tail = pytest_run("overworld or terrain_stem")
    return ok, tail


def g4():
    ok, tail = pytest_run("pave or seg_dist or course_route or course_anchors")
    return ok, tail


def g2():
    root = qud_overland.chunks_root()
    gid = qud_overland.latest_world(root)
    if gid is None:
        return False, "nothing baked under %s (raves-of-qud tools/capture/bake.py)" % root
    files = glob.glob(os.path.join(root, gid, "JoppaWorld.*.json"))
    if len(files) < 81:
        return False, "%d zones baked, the region check wants 81" % len(files)
    big = [f for f in files if os.path.getsize(f) > 80 * 1024]
    bad = []
    for f in files:
        try:
            with open(f, encoding="utf-8") as fh:
                d = json.load(fh)
            if len(d.get("ground", [])) != d.get("w", 80) * d.get("h", 25):
                bad.append(os.path.basename(f))
        except (OSError, ValueError):
            bad.append(os.path.basename(f))
    if big or bad:
        return False, "%d over 80 KB, %d malformed" % (len(big), len(bad))
    # the bake's own report, when the raves checkout is beside this one
    reports = sorted(glob.glob(os.path.join(os.path.dirname(ROOT), "raves-of-qud", "reports", "bake-20*.md")))
    note = ""
    if reports:
        with open(reports[-1], encoding="utf-8") as fh:
            m = re.search(r"wall time ([\d.]+) s for (\d+) zones = ([\d.]+) s/zone", fh.read())
        if m:
            note = "; last bake %s zones in %s s (%s s/zone)" % (m.group(2), m.group(1), m.group(3))
            if float(m.group(1)) > 600:
                return False, "the region bake took %s s, over the 10 min bound" % m.group(1)
    return True, "%d zones, max %d KB%s" % (len(files), max(os.path.getsize(f) for f in files) // 1024, note)


def g3():
    p = os.path.join(qud_assets.store_dir(), "godot", "world", "index.json")
    if not os.path.exists(p):
        return False, "no world export (tools/export_godot_assets.py)"
    with open(p, encoding="utf-8") as fh:
        gid = json.load(fh).get("latest", "")
    with open(os.path.join(qud_assets.store_dir(), "godot", "world", gid, "index.json"), encoding="utf-8") as fh:
        idx = json.load(fh)
    st = idx["stats"]
    frac = st["resolved"] / max(1, st["objects"])
    skipped = ", ".join("%s %d" % kv for kv in list(st.get("skipped", {}).items())[:8]) or "none"
    return frac >= 0.97, "%d zones, %.1f%% of %d objects resolved, %d art, skipped: %s" % (
        len(idx["zones"]), 100 * frac, st["objects"], st["art"], skipped)


def g5():
    out, err = run_godot(["--track=joppa", "--overland", "--stream_test", "--auto", "--mute"], timeout=600)
    if out is None:
        return False, err
    m = re.search(r"overland_test: ok=(true|false) steps=(\d+) max_chunks=(\d+) cap=(\d+) loads=(\d+) unloads=(\d+)", out)
    if not m:
        return False, "no overland_test line" + (" (%s)" % err if err else "")
    return m.group(1) == "true", "steps %s, max %s chunks of cap %s, %s loads, %s unloads" % m.group(2, 3, 4, 5, 6)


GRAYBOX = re.compile(r"graybox: track=(\S+) .*?lap_best=([\d.]+) lap_med=([\d.]+) nlaps=(\d+) finished=(\d+)/(\d+) offroad=([\d.]+)% stuck=([\d.]+)s drops=(\d+) voids=(\d+)")


def _race(extra):
    args = ["--type=single", "--track=joppa", "--newrun", "--seed=1", "--auto", "--noattacks", "--timescale=3",
            "--frames=20000", "--graybox", "--mute"] + extra
    out, err = run_godot(args, timeout=900, quit_after=20200)
    if out is None:
        return None, err
    m = GRAYBOX.search(out)
    if not m:
        return None, "no graybox line" + (" (%s)" % err if err else "")
    return {"lap_best": float(m.group(2)), "lap_med": float(m.group(3)), "nlaps": int(m.group(4)),
            "finished": int(m.group(5)), "field": int(m.group(6)), "offroad": float(m.group(7)),
            "stuck": float(m.group(8)), "drops": int(m.group(9)), "voids": int(m.group(10)),
            "state": (re.search(r"race: state=(\w+)", out) or [None, "?"])[1]}, None


def g6():
    canvas, err = _race([])
    if canvas is None:
        return False, "canvas race: " + err
    over, err = _race(["--overland"])
    if over is None:
        return False, "overland race: " + err
    ok = over["nlaps"] >= 3 and over["drops"] == 0 and over["voids"] == 0 and abs(over["offroad"] - canvas["offroad"]) <= 5.0
    return ok, "overland laps %d (med %.1f s) offroad %.1f%% vs canvas %.1f%%, drops %d, voids %d, state %s" % (
        over["nlaps"], over["lap_med"], over["offroad"], canvas["offroad"], over["drops"], over["voids"], over["state"])


FREE = re.compile(r"overland_free: ok=(true|false) legs=(\d+) max_chunks=(\d+) cap=(\d+) delta_last_min=(-?\d+) MB samples=(\d+) loads=(\d+) unloads=(\d+)")


def g7():
    """Free drive three zones east and back, repeating, for 150 s of wall time (the marsh is
    off-road: a crossing takes ~50 s at timescale 3). The player alone, so the chunk cap is
    one kart's window."""
    out, err = run_godot(["--track=joppa", "--overland", "--free_test=3", "--frames=9000", "--timescale=3", "--mute"], timeout=900)
    if out is None:
        return False, err
    m = FREE.search(out)
    if not m:
        return False, "no overland_free verdict" + (" (%s)" % err if err else "")
    return m.group(1) == "true", "legs %s, max %s chunks of cap %s, memory delta over the last minute %s MB, %s loads, %s unloads" % m.group(2, 3, 4, 5, 7, 8)


LIGHT = re.compile(r"light: bakes=(\d+) keys=(\d+) last_seg=(\d+)")


def g8():
    """Race mode: a noon race bakes once; a dusk race bakes at its keyframes and no more.
    Free drive: rebakes on the cadence (60 s) — 80 s of wall time gives two bakes."""
    notes = []
    ok = True
    for name, args, want in [
        ("noon race", ["--auto", "--frames=1800", "--clock=6000"], lambda b, k: b == 1 and k == 1),
        ("dusk race", ["--auto", "--frames=1800", "--clock=9700"], lambda b, k: b == k and k >= 2),
        ("free drive", ["--free_test=1", "--frames=4800", "--clock=6000"], lambda b, k: b == 2),
    ]:
        out, err = run_godot(["--track=joppa", "--overland", "--mute"] + args, timeout=600)
        m = LIGHT.search(out or "")
        if not m:
            notes.append("%s: no light summary (%s)" % (name, err or "?"))
            ok = False
            continue
        b, k = int(m.group(1)), int(m.group(2))
        good = want(b, k)
        ok = ok and good
        notes.append("%s: %d bakes, %d keys%s" % (name, b, k, "" if good else " (WRONG)"))
    return ok, "; ".join(notes)


def _ahash(path):
    from PIL import Image
    im = Image.open(path).convert("L").resize((8, 8), Image.LANCZOS)
    px = list(im.getdata())
    mean = sum(px) / 64.0
    return [1 if v > mean else 0 for v in px], mean / 255.0


def g9():
    """Windowed shots for {race, free drive}; compared with goldens by average hash."""
    os.makedirs(SHOTS, exist_ok=True)
    scenes = {
        "race_noon": ["--track=joppa", "--overland", "--auto", "--frames=240", "--clock=6000", "--mute"],
        "race_night": ["--track=joppa", "--overland", "--auto", "--frames=240", "--clock=0", "--mute"],
        "free_noon": ["--track=joppa", "--overland", "--free_test=1", "--frames=240", "--clock=6000", "--mute"],
        "free_night": ["--track=joppa", "--overland", "--free_test=1", "--frames=240", "--clock=0", "--mute"],
    }
    results = []
    all_ok = True
    lums = {}
    for name, args in scenes.items():
        shot = os.path.join(SHOTS, name + ".png")
        if os.path.exists(shot):
            os.remove(shot)
        out, err = run_godot(args + ["--screenshot=" + shot], timeout=600, headless=False)
        if out is None or not os.path.exists(shot):
            results.append("%s: no screenshot (%s)" % (name, err or "run ended without one"))
            all_ok = False
            continue
        fps = re.search(r"race: state=\w+ .*?fps=(\d+)", out)
        h, lum = _ahash(shot)
        lums[name] = lum
        gold = os.path.join(GOLDEN, name + ".png")
        if not os.path.exists(gold):
            results.append("%s: no golden at %s (copy the shot there once it looks right)" % (name, gold))
            all_ok = False
            continue
        gh, glum = _ahash(gold)
        dist = sum(1 for a, b in zip(h, gh) if a != b)
        fps_ok = fps is None or int(fps.group(1)) >= 55
        results.append("%s: hash distance %d, luminance %.2f vs golden %.2f, fps %s" % (name, dist, lum, glum, fps.group(1) if fps else "?"))
        if dist > 6 or not fps_ok:
            all_ok = False
    # G8's on-screen half: night is darker than noon by a margin
    if "race_noon" in lums and "race_night" in lums:
        d = lums["race_noon"] - lums["race_night"]
        results.append("noon minus night luminance %.2f%s" % (d, "" if d > 0.15 else " (WRONG: needs > 0.15)"))
        if d <= 0.15:
            all_ok = False
    return all_ok, "; ".join(results)


CHECKS = {"G1": g1, "G2": g2, "G3": g3, "G4": g4, "G5": g5, "G6": g6, "G7": g7, "G8": g8, "G9": g9}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--screen", action="store_true", help="also run the windowed goals (G9)")
    ap.add_argument("--only", help="comma list of goal ids")
    args = ap.parse_args(argv)
    only = set(args.only.split(",")) if args.only else None
    rows = []
    total = 0
    t_all = time.time()
    for gid, title, pts in GOALS:
        if only and gid not in only:
            continue
        if gid == "G9" and not args.screen and not only:
            rows.append((gid, title, pts, None, "skipped: needs --screen (a window)"))
            continue
        t0 = time.time()
        try:
            ok, note = CHECKS[gid]()
        except Exception as e:   # a check that crashes scores nothing, and says so
            ok, note = False, "check crashed: %s: %s" % (type(e).__name__, e)
        rows.append((gid, title, pts, ok, "%s (%.0f s)" % (note, time.time() - t0)))
        if ok:
            total += pts
        print("%s %-26s %3s/%-3d %s" % (gid, title, pts if ok else 0, pts, note))
    possible = sum(pts for gid, _, pts in GOALS if not only or gid in only)
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w", encoding="utf-8") as f:
        f.write("# Overland score: %d / %d\n\n" % (total, possible))
        f.write("%s, %.0f s%s\n\n" % (datetime.datetime.now().strftime("%Y-%m-%d %H:%M"), time.time() - t_all,
                                    "" if args.screen else " (headless goals only; --screen adds G9)"))
        f.write("| goal | title | points | check |\n|---|---|---|---|\n")
        for gid, title, pts, ok, note in rows:
            f.write("| %s | %s | %s | %s |\n" % (gid, title, ("%d/%d" % (pts if ok else 0, pts)) if ok is not None else "-/%d" % pts, note))
    print("score: %d / %d -> %s" % (total, possible, os.path.relpath(REPORT, ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
