"""Regression tests for spells, artifacts and the archetype NPCs, run through the
Godot test rig (docs/test-rig.md).

    .venv/Scripts/python tools/rig_test.py                 # the default suite
    .venv/Scripts/python tools/rig_test.py --only Fire     # cases whose name contains "Fire"
    .venv/Scripts/python tools/rig_test.py --all-spells    # every spell in the game (slow)
    .venv/Scripts/python tools/rig_test.py --json out.json # keep every rig report

Each case launches a headless race with --rig (archetype NPCs holding set gaps
around an auto-driven wizard), grants spells or artifacts, schedules casts, and
reads back the JSON report the scene prints. Runs are deterministic: fixed
physics step, seeded RNG, casts scheduled on simulation time.
"""
import argparse
import concurrent.futures
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT_DEFAULT = r"C:\Users\danie\Downloads\gofo\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"

RIG = "ahead:220,behind:220,swerve:420,beside:-90,parked:600"
CAST_AT = 4.0
SECONDS = 12.0

# One spell per effect kind, plus a few that exercise the mapping edges.
SPELL_CASES = [
    "Magic Missile", "Lightning Bolt", "Fireball", "Wolf", "Arcane Warding", "Healing Light",
    "Invoke Savagery", "Blink", "Petrify", "Freeze", "Chain Lightning", "Iceball", "Death Bolt",
    "Giant Bear", "Lightning Form", "Void Beam", "Poison Sting", "Summon Blade", "Touch of Death",
    "Dragon Claw", "Blood Bullet", "Vampiricism", "Flame Burst", "Dragon Roar", "Lightning Halo", "Wall of Flame",
    "Mystic Power", "Shatter", "Dread Lash", "Chaos Barrage", "Lifedrain", "Regeneration Aura", "Wheel of Death",
]

# What a cast of each effect kind must do to count as working.
KIND_CHECKS = {
    "bolt": "damage", "beam": "damage", "blast": "damage", "melee": "damage", "burst": "damage", "aura": "damage",
    "patch": "damage", "summon": "summon", "shield": "shield", "heal": "heal", "buff": "buff", "blink": "blink",
    "hex": "hex", "empower": "empower",
}

# Spells that need a set-up cast first (cast one second earlier).
PRE_CASTS = {"Shatter": "Freeze"}

# Melee spells need a kart within arm's reach; these get a close "ahead" NPC.
MELEE_RIG = "ahead:70,behind:220,swerve:420,parked:600"
_SPELL_INFO = {}


def godot_path(arg):
    return arg or os.environ.get("DRIFT_GODOT") or GODOT_DEFAULT


def run_rig(godot, args, timeout=180):
    """Launch one headless rig run; return (report dict or None, stdout text)."""
    cmd = [godot, "--headless", "--path", os.path.join(ROOT, "godot"), "--"] + args
    t0 = time.time()
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace")
        out = p.stdout + p.stderr
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or "") + "\nTIMEOUT after %ds" % timeout
        if isinstance(out, bytes):
            out = out.decode("utf-8", "replace")
    report = None
    for line in out.splitlines():
        if line.startswith("rig: "):
            try:
                report = json.loads(line[5:])
            except json.JSONDecodeError:
                pass
    if report is not None:
        report["_seconds_wall"] = round(time.time() - t0, 1)
    return report, out


def base_args(seed=1, track="brick", seconds=SECONDS):
    return ["--rig=" + RIG, "--auto", "--newrun", "--map=%s" % track, "--seed=%d" % seed,
            "--seconds=%g" % seconds, "--timescale=4", "--hp=20"]


def npc(snap, archetype):
    for n in snap["npcs"]:
        if n["archetype"] == archetype:
            return n
    return None


def total_damage(snap):
    return sum(n["damage_taken"] for n in snap["npcs"])


def slain_hp(before, end):
    """HP of NPCs present in `before` but gone by `end`: they were killed, which counts as damage."""
    left = {n["name"] for n in end["npcs"]}
    return sum(n["hp"] for n in before["npcs"] if n["name"] not in left)


# ---------------------------------------------------------------- checks

def check_archetypes(report):
    """The NPCs hold their gaps: mean error under a quarter of the gap, everyone alive."""
    fails = []
    detail = []
    for g in report["gaps"]:
        tol = max(60.0, abs(g["dist"]) * 0.25)
        detail.append("%s mean %.0f max %.0f" % (g["name"], g["mean_err"], g["max_err"]))
        if g["archetype"] in ("ahead", "behind", "swerve"):
            if g["samples"] == 0:
                fails.append("%s: no samples" % g["name"])
            elif g["mean_err"] > tol:
                fails.append("%s: mean gap error %.0f px > %.0f" % (g["name"], g["mean_err"], tol))
        if not g["alive"]:
            fails.append("%s: died" % g["name"])
    end = report["end"]
    if end["speed"] < 100:
        fails.append("wizard not driving (speed %.0f)" % end["speed"])
    return fails, "; ".join(detail)


def check_spell(report, name):
    casts = [c for c in report["casts"] if c["name"] == name]
    if not casts:
        return ["cast never scheduled"], ""
    c = casts[0]
    kind = c.get("kind", "")
    if c["slot"] < 0:
        return ["spell not on the action bar (unknown name?)"], ""
    hp0 = c["before"]["hp"]
    if c.get("hp_cost", 0) >= hp0:
        # the game refuses these too until shrines raise max HP (the wizard starts at 50)
        if c.get("ready", True):
            return ["HP cost %d >= HP %.0f but the cast was allowed" % (c["hp_cost"], hp0)], kind
        return [], "kind=%s hp_cost=%d unaffordable at %.0f HP, refused (as in the game)" % (kind, c["hp_cost"], hp0)
    if not c["ok"]:
        return ["cast returned false (kind %s)" % (kind or "unmapped")], kind
    before, after, end = c["before"], c["after"], report["end"]
    what = KIND_CHECKS.get(kind)
    fails = []
    detail = "kind=%s" % kind
    # costs: the game's HP cost comes off the wizard, a charge comes off the bar, an
    # unlimited spell (max_charges 0) spends nothing and can go again after its cooldown
    hp_cost = c.get("hp_cost", 0)
    if hp_cost > 0:
        paid = before["hp"] - after["hp"]
        detail += " hp_cost=%d paid=%.0f" % (hp_cost, paid)
        if abs(paid - hp_cost) > 0.5:
            fails.append("HP cost %d but HP went %.0f->%.0f" % (hp_cost, before["hp"], after["hp"]))
    if c.get("unlimited"):
        detail += " unlimited"
        if c.get("charges_after", 0) != 0 or c.get("cd_after", 0) <= 0:
            fails.append("unlimited spell should start a cooldown, not spend charges")
        if len(casts) > 1 and 2 * hp_cost < hp0 and not casts[1]["ok"]:
            fails.append("second cast of an unlimited spell failed")
    elif c.get("charges_after", 0) != c.get("charges_before", 1) - 1:
        fails.append("charges %s -> %s after a cast" % (c.get("charges_before"), c.get("charges_after")))
    if kind == "melee":
        far = [n["name"] for n in after["npcs"] if abs(n["gap_px"]) > 150 and n["damage_taken"] > 0]
        if far:
            fails.append("melee reached NPCs far away: %s" % ",".join(far))
    if what == "damage":
        dealt = total_damage(end) - total_damage(before) + slain_hp(before, end)
        detail += " dealt=%.0f" % dealt
        if report["slain"]:
            detail += " slain=%s" % ",".join(report["slain"])
        eff = c.get("effect", {})
        if dealt <= 0 and float(eff.get("damage", 1)) <= 0 and (eff.get("shove") or eff.get("stun") or eff.get("slip") or eff.get("heal")):
            detail += " (no damage by design)"
        elif dealt <= 0:
            fails.append("no damage to any NPC by the end of the run")
    elif what == "summon":
        detail += " wolves_peak=%d dealt=%.0f" % (report["wolves_peak"], total_damage(end) - total_damage(before))
        if report["wolves_peak"] <= 0:
            fails.append("no summon appeared")
    elif what == "shield":
        detail += " shields=%d" % after["shields"]
        if after["shields"] <= before["shields"]:
            fails.append("no shield gained")
    elif what == "heal":
        detail += " hp %.0f->%.0f" % (before["hp"], after["hp"])
        if after["hp"] <= before["hp"]:
            fails.append("no HP gained")
    elif what == "buff":
        detail += " boost_t=%.2f" % after["boost_t"]
        if after["boost_t"] <= 0:
            fails.append("no boost applied")
    elif what == "blink":
        jump = after["progress_px"] - before["progress_px"]
        detail += " jump=%.0f" % jump
        if jump < 150:
            fails.append("blink moved the wizard only %.0f px" % jump)
    elif what == "hex":
        stunned = [n["name"] for n in after["npcs"] if n["stun_t"] > 0]
        detail += " stunned=%s" % ",".join(stunned)
        if not stunned:
            fails.append("no NPC stunned")
    elif what == "empower":
        detail += " bonuses=%s" % json.dumps(after.get("bonuses", {}), sort_keys=True)
        if not after.get("bonuses") or after.get("bonuses") == before.get("bonuses"):
            fails.append("no temporary bonus in force after the cast")
    else:
        fails.append("unknown effect kind %r" % kind)
    if what == "damage" and kind in ("aura", "burst") and c.get("effect", {}).get("heal", 0) and not c.get("effect", {}).get("damage"):
        # a pure heal-over-time aura: judge it by HP instead
        fails = [f for f in fails if not f.startswith("no damage")]
        detail += " hp %.0f->%.0f" % (before["hp"], end["hp"])
        if end["hp"] <= before["hp"]:
            fails.append("heal aura did not raise HP")
    return fails, detail


def check_artifact(report, name, baseline_damage):
    fails = []
    if name not in report["artifacts"]:
        return ["artifact not granted (unknown name?)"], ""
    bon = report["bonuses"]
    detail = "bonuses=%s" % json.dumps(bon, sort_keys=True)
    if not bon:
        fails.append("artifact has no bonuses")
    casts = [c for c in report["casts"] if c["name"] == "Magic Missile"]
    if casts and casts[0]["ok"]:
        dealt = total_damage(report["end"]) - total_damage(casts[0]["before"])
        detail += " dealt=%.0f (baseline %.0f)" % (dealt, baseline_damage)
        if bon.get("spell_damage", 0) > 0 and dealt <= baseline_damage:
            fails.append("+spell_damage but dealt %.0f <= baseline %.0f" % (dealt, baseline_damage))
    return fails, detail


# ---------------------------------------------------------------- suites

def spell_info(name):
    if not _SPELL_INFO:
        path = os.path.join(ROOT, "godot", "rw3", "data", "spells.json")
        with open(path, encoding="utf-8") as f:
            for s in json.load(f):
                if "error" not in s:
                    _SPELL_INFO[s["name"]] = s
    return _SPELL_INFO.get(name, {})


def spell_case(name, track="brick"):
    info = spell_info(name)
    args = base_args(track=track)
    ov = {}
    try:
        with open(os.path.join(ROOT, "shared", "overrides.json"), encoding="utf-8") as f:
            ov = json.load(f).get("spells", {}).get(name, {})
    except (OSError, json.JSONDecodeError):
        pass
    if info.get("melee") or ov.get("kind") == "melee":
        args = [a if not a.startswith("--rig=") else "--rig=" + MELEE_RIG for a in args]
    if int(info.get("hp_cost", 0)) > 0:
        args = [a if not a.startswith("--hp=") else "--hp=50" for a in args]   # room to pay twice
    casts = "%s@%g" % (name, CAST_AT)
    learn = name
    if name in PRE_CASTS:
        casts = "%s@%g," % (PRE_CASTS[name], CAST_AT - 1.0) + casts
        learn = "%s,%s" % (PRE_CASTS[name], name)
    if int(info.get("max_charges", 1)) <= 0:
        casts += ",%s@%g" % (name, CAST_AT + 1.5)     # unlimited: prove it goes again
    return {"suite": "spell", "name": name,
            "args": args + ["--learn=%s" % learn, "--cast=%s" % casts],
            "check": lambda r: check_spell(r, name)}


def load_spell_names():
    path = os.path.join(ROOT, "godot", "rw3", "data", "spells.json")
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return [s["name"] for s in data if "error" not in s and int(s.get("level", 0)) > 0]


def load_artifact_names(limit):
    path = os.path.join(ROOT, "godot", "rw3", "data", "equipment.json")
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    names = [a["name"] for a in data if "error" not in a and a.get("asset_exists")]
    # spread across the list so different tags are covered
    step = max(1, len(names) // limit)
    return names[::step][:limit]


def build_cases(args):
    cases = [{"suite": "archetypes", "name": "brick 20s", "args": base_args(seconds=20.0), "check": check_archetypes},
             {"suite": "archetypes", "name": "ice 20s", "args": base_args(seed=2, track="ice", seconds=20.0), "check": check_archetypes}]
    spells = load_spell_names() if args.all_spells else SPELL_CASES
    cases += [spell_case(n) for n in spells]
    for n in load_artifact_names(args.artifacts):
        cases.append({"suite": "artifact", "name": n,
                      "args": base_args() + ["--learn=Magic Missile", "--cast=Magic Missile@%g" % CAST_AT, "--artifacts=%s" % n],
                      "check": None})  # needs the baseline; filled in run_all
    if args.only:
        cases = [c for c in cases if args.only.lower() in c["name"].lower() or args.only.lower() == c["suite"]]
    return cases


def run_all(args):
    godot = godot_path(args.godot)
    cases = build_cases(args)
    if not cases:
        print("no cases match", args.only)
        return 1
    # baseline for artifact damage comparisons
    baseline = None
    if any(c["suite"] == "artifact" for c in cases):
        rep, _ = run_rig(godot, base_args() + ["--learn=Magic Missile", "--cast=Magic Missile@%g" % CAST_AT])
        if rep and rep["casts"]:
            baseline = total_damage(rep["end"]) - total_damage(rep["casts"][0]["before"])
        for c in cases:
            if c["suite"] == "artifact":
                c["check"] = (lambda n: (lambda r: check_artifact(r, n, baseline or 0.0)))(c["name"])

    results = []
    reports = {}

    def work(case):
        rep, out = run_rig(godot, case["args"])
        if rep is None:
            tail = "\n".join(l for l in out.splitlines() if "error" in l.lower() or "TIMEOUT" in l)[-600:]
            return case, ["no report from Godot: " + (tail or "(no error text)")], ""
        fails, detail = case["check"](rep)
        reports["%s/%s" % (case["suite"], case["name"])] = rep
        return case, fails, detail

    t0 = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
        for case, fails, detail in ex.map(work, cases):
            status = "PASS" if not fails else "FAIL"
            results.append((status, case["suite"], case["name"], detail, fails))
            print("%s  %-10s %-24s %s" % (status, case["suite"], case["name"][:24], detail if not fails else "; ".join(fails)), flush=True)

    n_fail = sum(1 for r in results if r[0] == "FAIL")
    print("\n%d cases, %d failed, %.0fs" % (len(results), n_fail, time.time() - t0))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump({"results": [{"status": s, "suite": su, "name": n, "detail": d, "fails": fl} for s, su, n, d, fl in results],
                       "reports": reports}, f, indent=1)
        print("reports:", args.json)
    return 1 if n_fail else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot", help="Godot binary (default: DRIFT_GODOT env or the known install)")
    ap.add_argument("--only", help="run cases whose name contains this, or a suite name (archetypes, spell, artifact)")
    ap.add_argument("--all-spells", action="store_true", help="every spell in the game instead of the curated list")
    ap.add_argument("--artifacts", type=int, default=6, help="how many artifacts to sample (default 6)")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--json", help="write all results and rig reports here")
    sys.exit(run_all(ap.parse_args()))


if __name__ == "__main__":
    main()
