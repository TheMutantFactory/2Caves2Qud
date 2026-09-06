# The graybox pass over the authored loops

The bible's last roster-level check: "validate all widths, lap times, sightlines, and
respawns in graybox playtests". Without eyes on the track the pass is a measurement of the
AI field driving each course, made with the `--graybox` probe and acted on in the course
data (`tools/qud_tracks.py`). This page records the probe, the first measurement, what was
changed and the measurement after.

## The probe

```bash
cd godot && Godot --headless --quit-after 20200 -- --type=gp --track=joppa --newrun --seed=1 --auto --noattacks --timescale=3 --frames=20000 --graybox --hazard-log 2>&1 | grep -E "^graybox"
```

One `graybox:` line per race (`Race._graybox_report`), one field per checklist item:

- `lap_best` / `lap_med` — the field's best and median lap in seconds against `target`
  (the bible's lap, or `target_run` for a section race, whose single "lap" is the run).
- `offroad` — the share of racing time the field spends off the road: the width check.
- `stuck` — seconds any kart sat under 15 px/s after the start: soft locks and pins.
- `drops` / `voids` — ledge falls over 60 px and void returns: the respawn check.
- `items` / `item_gap` — distinct item sets on the loop and the seconds between them at
  the median lap, against the bible's 12–18 s rhythm.
- `tight` / `at` — the sharpest bend in degrees of heading per 100 px of road and where on
  the loop it sits: the only sightline proxy a headless run has.

`--frames` counts physics frames at 60 per second whatever `--timescale` says, so a 20000
frame run is 333 s of race, enough for three laps at the bible's pace. `--type=gp` fields
eight wizards; a realm-1 campaign field is two to six monsters and its numbers are thin.

## First measurement

Every course lapped short: circuits in 0.38–0.67 of the target lap, section runs in
0.14–0.18 of the target run, with Rust Wells (0.91) the one loop drawn long enough. The
field runs about 850 px/s at racing pace and the loops were drawn to fit one screen of
control points. Item sets came every 2–11 s instead of 12–18. Off-road time was over 10% on
Bethesda (ice), Golgotha, Hydropon (200 wide), the Tomb and Rainbowwood. Moonstair pinned
karts for 14 s. Thin World dropped the field into the void sixteen times in three laps.
The sharpest bends were the ellipse joins on Rainbowwood (69°/100 px) and Rust Wells (52).

## What changed

- **Stretch.** Each course carries a `stretch` factor (`STRETCH` in the generator) that
  scales its control points and size by target / measured lap, capped at 2.2 for a circuit
  and 3.0 for a section race. Widths stay in kart widths, hazards and movers sit at loop
  fractions, mover periods scale with the path. The section races stay short of the
  bible's three-minute runs even at 3.0: a three-section course wants three times the
  road of a circuit lap, which is authoring, not a cap.
- **Item rhythm.** `Track.item_positions` spaces sets by road length at racing pace
  (`race.item_set_seconds` 15 × `race.item_pace_px` 850) instead of a fixed count per loop.
- **Thin World's margin.** `void_margin` 40 → 80 px: the course still floats over the void,
  the AI line stops falling off it every lap (16 void falls in three laps became 4).
- **Waypoint density.** The second measurement found the section races 47–82% off-road and
  nobody finishing the Tomb: a stretched loop kept the same number of samples per control
  segment, the waypoints spread to the width of the road, and a kart cutting a corner
  missed the next one and never advanced (`Track.advance` wants it within width × 0.7).
  `_build_loop` now scales the samples with the stretch. Off-road fell to under 13%
  everywhere and under 10% on the sections.
- **Cusps.** `smooth_cusps` in the generator chamfers any control point turning more than
  120° into two: Rainbowwood's join fell from 69°/100 px to 12, Rust Wells' from 52 to 23.
- **Stretch bumps.** A second round for the circuits that still lapped short after the
  first fit (Hinnom, Omonporch, Rainbowwood, Redrock, Stilt, Palladium, Chavvah, Moonstair,
  Ydfreehold, Asphalt).
- **More route for the section races.** At the 3.0 cap the four one-way courses still ran
  in 0.54–0.67 of the bible's three-minute runs: their paths were nine points drawn like a
  circuit. Each is now drawn on a 4800 × 3200 canvas as three regions, one per section,
  from the Route paragraph — Golgotha's jungle chutes, two conveyor floors swept east then
  west with a shaft drop between, and the wide Cloaca; Bethesda's ruins, wharf and three
  pool lobes, the ward switchbacks, the cryobarrios to the Temple; Eyn Roj's glade circle
  and dive, the helix as three chambers tightening inward, the trunk ascent; the Tomb's
  bone channels down from the Death Gate, the conveyors west to the Columbarium, the climb
  through two gardens and a U-shaped hall to the Spindle. About twice the road, with the
  stretch fitted to the run target (2.3–2.9) rather than capped.

## After

| course | stretch | target | lap before | lap after | ratio | off-road | stuck | drops / voids | item gap | tightest bend |
|---|---|---|---|---|---|---|---|---|---|---|
| joppa | 1.81 | 65-75 | 39 s | 63 s | 0.90 | 0.4% | 4.4s | 0 / 0 | 15.8s | 7°/100 px at 0.33 |
| redrock | 2.1 | 70-80 | 43 s | 75 s | 1.00 | 0.1% | 0.1s | 15 / 0 | 9.4s | 6°/100 px at 0.30 |
| rustwells | 1.1 | 72-82 | 70 s | 78 s | 1.02 | 12.8% | 0.1s | 124 / 15 | 15.7s | 23°/100 px at 0.87 |
| stilt | 2.6 | 78-88 | 34 s | 83 s | 1.00 | 0.3% | 1.1s | 0 / 0 | 11.9s | 3°/100 px at 0.55 |
| gritgate | 1.79 | 75-85 | 45 s | 79 s | 0.98 | 1.0% | 15.2s | 0 / 0 | 13.1s | 9°/100 px at 0.41 |
| asphalt | 2.05 | 80-90 | 46 s | 88 s | 1.04 | 0.0% | 1.8s | 1 / 0 | 9.8s | 8°/100 px at 0.08 |
| golgotha | 2.33 | 160-180 | 30 s | 157 s | 0.93 | 6.3% | 0.0s | 41 / 0 | 15.7s | 10°/100 px at 0.94 |
| bethesda | 2.51 | 170-190 | 32 s | 158 s | 0.88 | 4.1% | 0.0s | 12 / 0 | 12.2s | 9°/100 px at 0.10 |
| kyakukya | 2.2 | 68-78 | 33 s | 72 s | 0.98 | 0.0% | 0.9s | 0 / 0 | 11.9s | 5°/100 px at 1.00 |
| rainbowwood | 1.8 | 82-92 | 58 s | 87 s | 1.00 | 2.9% | 0.0s | 0 / 0 | 17.4s | 12°/100 px at 0.25 |
| chavvah | 2.6 | 80-90 | 32 s | 84 s | 0.98 | 0.1% | 0.0s | 1 / 0 | 10.4s | 4°/100 px at 0.50 |
| eynroj | 2.49 | 165-185 | 25 s | 155 s | 0.88 | 0.9% | 6.3s | 8 / 0 | 17.2s | 11°/100 px at 0.10 |
| hinnom | 2.7 | 82-92 | 35 s | 93 s | 1.07 | 0.2% | 0.7s | 0 / 0 | 13.3s | 3°/100 px at 0.60 |
| palladium | 1.9 | 84-94 | 54 s | 87 s | 0.97 | 2.2% | 38.1s | 0 / 0 | 14.4s | 8°/100 px at 0.21 |
| ydfreehold | 2.15 | 78-88 | 46 s | 89 s | 1.07 | 0.8% | 4.4s | 0 / 0 | 11.1s | 5°/100 px at 0.84 |
| moonstair | 2.1 | 86-96 | 55 s | 103 s | 1.14 | 0.0% | 33.3s | 0 / 0 | 12.9s | 5°/100 px at 0.22 |
| hydropon | 1.54 | 38-45 | 27 s | 38 s | 0.91 | 6.7% | 1.6s | 0 / 0 | 9.5s | 7°/100 px at 0.44 |
| omonporch | 2.7 | 88-98 | 38 s | 94 s | 1.01 | 0.0% | 1.6s | 0 / 0 | 15.7s | 5°/100 px at 0.99 |
| tomb | 2.9 | 190-215 | 35 s | 185 s | 0.91 | 1.5% | 1.1s | 2 / 0 | 14.2s | 10°/100 px at 1.00 |
| thinworld | 2.17 | 92-102 | 45 s | 93 s | 0.96 | 0.7% | 19.3s | 0 / 4 | 15.5s | 9°/100 px at 0.66 |

Lap medians are the eight-wizard field's, before is the first measurement (a realm-1
campaign field), after is the final one. Every circuit laps within 0.90–1.14 of its target
and every section race runs within 0.88–0.93 of its run. A field that is half unfinished
in the table is the results screen: the race ends when the wizard finishes and the rest of
the field stops there, so only the karts ahead of it record a run. The stuck seconds
are the courses' own stun hazards doing their job (Moonstair's warm static, Gritgate's force
barriers, Palladium's strip), not pins: they scale with the field and vanish under
`--noattacks` only for monster abilities, not course hazards. Rust Wells' drops are its
spiral's steps (six a lap by design) and its voids the collapsed bridge on laps 2 and 3.

