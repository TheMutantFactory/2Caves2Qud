# Balance: the AI field's damage by band

The campaign's monster racers cast their first damaging Qud ability (or bite) at the wizard.
This page records how that damage is tuned, the numbers it was tuned against, and the probe
that reproduces them. Knobs live in `shared/tuning.json` under `campaign`.

## The problem, measured

Baseline (commit 13cb1c9): the auto-driven wizard, a weak driver who trails the pack, raced
six realms with three seeds each, 200 race seconds per run. From realm 8 up it died on lap 1
in eleven of twelve runs. The per-hit log (`hit:` lines under `--hazard-log`) showed why: the
start-pack volley. Every monster's first cooldown expires between 6 and 12 s, all seven are
within reach, and the wizard took five hits in five seconds and a second volley ten seconds
later. At realm 1 those are bites of 2.4 HP; at realm 8 the same volley is 6.3 HP a hit and
two volleys are the whole 50 HP. On top of that, band 9 carried one-shots (Spacetime Vortex,
77 raw damage at a 1.3 scale) and a patch ability ticked 10 HP every half second (Elder
Gallbeard: three ticks in 1.2 s).

## The three knobs

- `ability_damage_by_band` — a per-band scale on the ability's damage, fitted so the band's
  MEAN capped hit (bites included: most monsters are unarmed and bite for 3 + band) lands at
  2.5 HP at band 1 rising to 5.3 HP at band 9, 5% to 11% of the wizard's 50 HP. The fitted
  values were smoothed to 0.46, 0.40, 0.40, 0.37, 0.34, 0.33, 0.34, 0.40, 0.41: the curve
  dips through the middle bands because their raw means rise faster than the target (band 7
  has the breath weapons) and climbs again where the roster is mostly biters. Refit after
  the roster changes.
- `ability_damage_cap_pct` (0.2) — no single ability hit or patch tick takes more than a
  fifth of max HP. Summons are exempt (their damage is per bite over a duration).
- `ability_hit_mercy` (2.5 s) — a monster ability or patch tick that lands starts a mercy
  window; further monster hits inside it flash but do no damage. The volley becomes one hit,
  a patch ticks at most every 2.5 s. Mercy does not cover lap damage, mobs, wolves or the
  course's own hazards, and never applies to monsters.

Fitting the curve, per band b: effective damage of each monster's pick = max(stats.damage,
5 x level), the record's `kart.damage` hint over it, 3 + b for a biter; scale(b) solves
mean(min(damage x scale, cap)) = 2.5 + 0.35 (b - 1) by bisection over the band's roster. A
first fit against the band MEDIAN left realm 16 twice as hot as its neighbours, because the
median is the bite and the armed monsters all hit the cap.

## After

| realm | band | deaths before | deaths after | field damage before | field damage after | HP left after |
|---|---|---|---|---|---|---|
| 1 | 1 | 0/3 | 0/3 | 41/18/4 | 11/21/3 | 45/28/50 |
| 4 | 2 | 0/3 | 0/3 | 43/21/35 | 25/15/19 | 47/34/50 |
| 8 | 4 | 3/3 | 0/3 | 50/54/75 | 21/10/25 | 44/39/24 |
| 12 | 6 | 2/3 | 0/3 | 52/19/62 | 19/5/21 | 30/44/28 |
| 16 | 7 | 3/3 | 0/3 | 62/83/81 | 63/46/57 | 28/25/35 |
| 20 | 9 | 2/3 | 0/3 | 55/67/101 | 18/12/34 | 48/44/45 |

Field damage is the `bolt` + `hazard` + `wolf` buckets of the `race:` tally; HP left is at
the end of the 200 s run (lap 2 or 3, or the realm's gates). Realm 16 (band 7, the breath
weapons) is the hottest band and the one to watch if the curve is refit.

## The probe

```bash
cd godot && Godot --headless --quit-after 4200 -- --type=campaign --realm=16 --newrun --seed=1 --auto --timescale=3 --frames=4000 --hazard-log 2>&1 | grep -E "^hit:|^race:"
```

`hit: <cause> <damage> from <source> hp=<after> t=` per hit on the wizard, `hit: mercy` for
a hit the window absorbed, and the `race:` line with the tally at the end. The tuning is
read from the asset store's copy (`godot/qud/shared/tuning.json`): copy `shared/tuning.json`
over or rerun the exporter after editing it, or the probe measures the old values.
