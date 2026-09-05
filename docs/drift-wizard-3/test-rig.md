# Test rig

A race scene with no opponents, no lap rule and no monster abilities: the
wizard drives (or auto-drives) and archetype NPCs hold set gaps around it, so
every spell and artifact can be tried by hand or checked by a script under
the same conditions every time.

## Driving it

Menu: `T` (or `--rig=...` on the command line). The track's own spell list
is put on the action bar with 30 SP in the bank, so `1`..`0` cast, `Tab`
opens the shop for more, `Q` the quick shop. `F` still toggles free drive.

`L` opens the spell picker: type part of a name or tag, press a digit to
choose the slot (the label says what it replaces), then click a spell or
press Enter for the first match. It goes straight onto the bar with full
charges, no spell points. `N` opens the enemy picker: the left side lists the NPCs on the track with
a remove button each (and "remove all"), the right side adds one: choose an
archetype, type the gap in px and the lane (-1..1, the swerve amplitude for
swerve, ignored for beside where the gap is the side offset), then click a
monster from the searchable list. It appears at its spot with `rig.npc_hp`
HP and holds its gap like the rest. `Z` cycles slow motion (1x, 0.3x, 0.1x, from
`rig.slow_steps`) so a projectile or a summon can be watched frame by frame;
the HUD shows the current factor.

```bash
& "C:\Users\danie\Downloads\gofo\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe" --path godot -- --rig=ahead:250,behind:250,swerve:420,beside:-90 --map=volcano
```

## Archetypes

`--rig=` takes a comma list of `kind:dist[:lat[:unit]]` (unit is a sprite
name such as `yaldabaoth`; the default cycles through a few small monsters). `dist` is px along the
route relative to the wizard (about 90 px per game tile), `lat` a fraction of
half the road width (+ is the wizard's right).

| kind | behaviour |
| --- | --- |
| `ahead:D` | stays D px ahead, whatever the wizard does; slows down if the wizard stops |
| `behind:D` | stays D px behind; allowed to go faster than the wizard to catch up |
| `swerve:D[:A]` | D px ahead, weaving across the road with amplitude A (default `rig.swerve_amplitude`, 0.55) every `rig.swerve_period` s |
| `beside:X` | level with the wizard, X px to the side (negative = left) |
| `parked:D` | sits still D px up the road |

They start at their target spots with `rig.npc_hp` HP (200). By default they
are kinematic: they slide along the route at the wizard's speed plus a
bounded catch-up (`rig.catchup_gain` px/s per px of gap error, at most
`rig.catchup_max`), so the gap is exact and repeatable; a stun freezes them
in place and they close the gap again afterwards. They still collide, take
damage, block projectiles and give slipstream. `--drive` (or
`rig.kinematic: false`) makes them drive the real kart physics instead, at
up to `rig.speed_scale` of a normal kart, which feels more like racing but
loses ground in corners. The numbers live in the `rig` block of
[shared/tuning.json](../shared/tuning.json); after editing it, copy it into
`godot/rw3/shared/` (the exporter does this too).

## Regression runs

Extra flags on the race scene make a run scriptable:

| flag | effect |
| --- | --- |
| `--learn=Name,Name` | put spells on the bar for free |
| `--artifacts=Name,Name` | grant artifacts |
| `--hp=N` | start HP (for heal tests) |
| `--cast=Name@sec,...` | cast from the bar at those simulation times |
| `--seconds=N` | stop after N simulated seconds |
| `--timescale=X` | run the simulation X times faster (physics step stays 1/60 s) |
| `--report=path.json` | write the report; it is also printed as one `rig: {...}` line |
| `--shinies` | keep item boxes and scrolls on the track (off by default in the rig) |

The report has a snapshot before and after every cast (wizard HP, shields,
boost, progress; each NPC's HP, damage taken, stun, gap) plus the end state,
per-NPC gap error statistics after `rig.settle_time`, the peak number of
summons, and the artifact bonuses in force.

`tools/rig_test.py` runs a suite of such cases in parallel and checks each
spell by its effect kind: bolts, beams and blasts must damage an NPC, summons
must appear, shields/heals/buffs must show on the wizard immediately, blinks
must move it, hexes must stun. Artifacts must grant bonuses and a
`+spell_damage` artifact must beat the baseline Magic Missile damage. The
archetype cases check that the NPCs hold their gaps. Costs are checked on
every spell case: an HP-cost spell must take exactly that much HP, a charged
spell must lose one charge, an unlimited spell must start a cooldown instead
and go again on a second cast; melee spells get a close "ahead" NPC and must
not reach anyone far away. A spell whose HP cost is at or above the wizard's
HP must be refused, as the game does (the wizard starts at 50 HP in both).

```bash
.venv/Scripts/python tools/rig_test.py
```

```bash
.venv/Scripts/python tools/rig_test.py --all-spells --json extracted/rig/all.json
```

A spell whose cast returns false is reported as failing with its effect
kind; that is the list of spells the kart mapping in SpellDB does not cover
yet. As of 2026-09-04 the full sweep passes all 186 spells in about three
minutes (five workers); the default suite of 26 cases takes 30 seconds.
Kills count as damage: a 200-damage spell removes the 200 HP NPC from the
end snapshot, so the check adds the HP of any NPC that disappeared.

## Spell scrolls

Each track lists its `spells` in [shared/tracks.json](../shared/tracks.json).
Scrolls on the track (a scroll with the spell's icon floating above it) cycle
through that list; driving over one adds the spell to the action bar for
free, or gives it a charge if you already have it. A full bar leaves the
scroll where it is.
