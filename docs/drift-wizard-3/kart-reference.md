# Kart mechanics reference

What the kart genre actually does under the hood, read from three open source
racers, and how those mechanics map onto Drift Wizard 3's `shared/tuning.json`.
Numbers here are quoted from the sources; the "ours" column is what we run.

## Sources and licenses

| project | what it is | license | how we use it |
| --- | --- | --- | --- |
| [Kinoko](https://github.com/vabold/Kinoko) | Clean-room C++ reimplementation of Mario Kart Wii physics, bit-accurate for ghost replay | MIT (c) 2022-2026 vabold | Formulas and constants; code may be ported with the notice kept |
| [SuperTuxKart](https://github.com/supertuxkart/stk-code) | The reference open source kart racer | GPL-3.0 | Design and numbers only, no code copied |
| [Dr. Robotnik's Ring Racers](https://github.com/KartKrewDev/RingRacers) | Sprite-based 2.5D kart racer on the Doom engine, sequel to SRB2Kart | GPL-2.0 | Design and numbers only, no code copied |
| [Hanachan](https://github.com/stblr/Hanachan) | Kinoko's Rust predecessor | GPL-2.0-or-later | Not used |

This repo is MIT. GPL sources are reference material: we reimplement the
mechanic from the description and the numbers, which are not copyrightable.
Nothing from Nintendo's own game is used; Kinoko reproduces behaviour, not
assets.

Files read (all fetched to a scratch folder, none committed):

- Kinoko `source/game/kart/KartMove.cc` (`calcTurn`, `calcRotation`,
  `calcVehicleAcceleration`, `calcAcceleration`, `calcMtCharge`,
  `startManualDrift`, `releaseMt`, `calcOffroad`), `KartBoost.cc`, `KartParam.hh`
- SuperTuxKart `data/kart_characteristics.xml`, `data/powerup.xml`,
  `data/stk_config.xml` (the `<ai>` block), `src/karts/skidding.cpp`
- Ring Racers `src/k_kart.c` (`K_GetKartSpeed`, `K_GetKartSpeedFromStat`,
  `K_GetKartAccel`, `K_GetKartTurnValue`, `K_GetKartDriftSparkValue`,
  `K_KartDrift`, `K_GetKartBoostPower`, `K_DoSneaker`), `src/k_roulette.c`,
  `src/k_bot.cpp`

## 1. Character stats: the speed / weight triangle

**Ring Racers.** Every racer has `kartspeed` and `kartweight`, each 1 to 9.
Everything else derives from them:

- Top speed: `k_speed = 148 + 4 * kartspeed` (152 to 184, so about +/-10%
  around the middle), then scaled by game speed (Easy 81%, Normal 100%, Hard
  119%, Nightmare 137%).
- Acceleration: `k_accel = 121 + 17 * (9 - kartspeed)` (121 to 257). Low speed
  stat means roughly double the acceleration. The classic trade.
- Handling: turning dampens as speed rises; the "harsh" dampening window
  starts at `(110 + 2 * (9 - weight))%` of top speed, so light karts keep sharp
  steering longer.
- Drift charge per stage: `(26*4 + speed*2 + (9 - weight)) * 8` ticks at 35
  tics/s, so a fast light kart needs about 3.4 s per stage and a slow heavy one
  about 2.6 s.
- Boost stacking "metabolism" (see section 4) is better for light karts.
- Weight decides bumps: the heavier kart pushes the lighter one.

**SuperTuxKart** uses three classes instead. Relative to base: light has
0.8x engine power, 0.95x top speed, 0.6x mass, tightest turn radius; medium
0.875x / 1.0x / 0.75x; heavy 1.0x / 1.05x / 1.0x, widest turn radius.

**Kinoko** carries the full Mario Kart Wii stat block per character/vehicle
combo: `speed`, `weight`, `handlingManualTightness`, `driftManualTightness`,
`handlingReactivity`, `driftReactivity`, `miniTurbo` (frames), and per-surface
`kclSpeed` / `kclRot` tables. The values live in the game's binary param files,
not in the source, so we take the structure and use Ring Racers' numbers.

**Ours.** Each racer gets `speed` and `weight` 1 to 9 derived from the Rift
Wizard unit that drives it: weight from `max_hp` on a log scale, speed from
the inverse plus a bonus for flying units, with a little jitter. The wizard is
5/5. Top speed is `base * (1 + 0.025 * (speed - 5))`, acceleration
`base * (1 + 0.12 * (5 - speed))`, turn rate `* (1 + 0.03 * (5 - weight))`.

## 2. Turning and steering

**Kinoko `calcRotation`.** The turn amount is a stat (`handlingManualTightness`,
or the drift tightness while drifting) times the smoothed stick, then scaled
by speed:

- below speed 20: `turn * 0.4 + (speed/20) * turn * 0.6` (ramps up from 40%)
- speed 20 to 70: `turn * 0.5 * (1 + (1 - (speed-20)/50))` (100% down to 50%)
- above 70: `turn * 0.5`
- hopping mid-drift-start: `* 1.4`; zipper boost: `* 2`

Stick smoothing (`calcTurn`): `weighted = raw * reactivity + weighted * (1 -
reactivity)`, clamped. While drifting the effective turn is
`((weighted + driftDir) / 2) * 0.8 + 0.2 * driftDir`, which is why a Mario
Kart drift always keeps turning the way you hopped: you can tighten or widen
it, never reverse it.

**SuperTuxKart.** A piecewise-linear turn *radius* by speed:
`0:2.0 10:7.5 25:15 45:30` metres (heavy class 30% wider). Steering input
takes 0.17 s to reach half lock and 0.28 s to full lock, and resets in 0.1 s.
While skidding, the [-1, 1] steer maps to [0.2, 0.8] on the skid side
(`reduce-turn-min/max`), the same "never reverse a drift" rule as Kinoko.

**Ring Racers `K_GetKartTurnValue`.** Two-stage dampening: harsh up to
`(110 + 2*(9-weight))%` of max speed, then the excess counts half, capped at
2x max speed.

**Ours.** A normalised turn curve over `speed / max_speed`, interpolated:
`[0, 0.4], [0.25, 1.0], [0.8, 0.5], [1.6, 0.45]` (Kinoko's shape). Steering is
smoothed toward the input at 9/s (about 0.2 s to full lock, STK's figure).
While drifting, steer maps to [0.2, 1.0] on the drift side.

## 3. Drifting and mini-turbos

**Kinoko `calcMtCharge` / `releaseMt`.** Drifting needs speed above 55% of
base (`MINIMUM_DRIFT_THRESHOLD`). The mini-turbo charge gains 2 per frame,
plus 3 more when the stick is held into the drift (past 0.4). Full charge at
270 (2.25 s neutral, 0.9 s held inward), then a super mini-turbo charges
another 300 on the same rule. Release fires a boost of `miniTurbo` frames
(per-vehicle stat), 3x as long for a super. Releasing while braking cancels.
An outside-drift kart also gets an extra turn bonus at drift start:
`0.5 * speedRatio * driftManualTightness`, decaying 1% per frame.

**Kinoko `KartBoost`.** Three boost types, each with a top-speed multiplier
and an acceleration override:

| type | speed | accel | notes |
| --- | --- | --- | --- |
| mini-turbo (all kinds) | +20% | 3.0 | duration from the stat |
| mushroom / trick | +40% | 7.0 | hard speed limit 115 |
| start boost | +30% | 6.0 | |

**SuperTuxKart skid.** Min speed 10 m/s. Two bonus levels at 1.0 s and 3.0 s
of skidding: `bonus-speed 4.5 / 6.5` m/s on top of the 25 m/s cap,
`bonus-time 3.0 / 4.0` s, plus engine force 250 / 350. Steering angle
multiplier climbs to 2.5x over 0.5 s of skid.

**Ring Racers `K_KartDrift`.** Four spark stages at 1x, 2x, 3x, 4x the drift
spark value (section 1). Boost on release, in tics (35/s):

| stage | sparks | driftboost |
| --- | --- | --- |
| 0 (early release) | grey | 15 |
| 1 | yellow | 20 |
| 2 | red | 50 |
| 3 | blue | 85 |
| 4 | rainbow | 125 |

then scaled by `(38 + weight + speed) / 40`, so heavy fast karts keep slightly
more of it. A drift boost is +100% top speed and +800% acceleration while
active (a "sneaker"), which is why they feel violent.

**Ours.** Drift needs 55% of top speed. Charge accrues at 1/s, 2.5/s when
steering into the drift. Three stages at 0.6, 1.4 and 2.4 s (scaled by the
stat rule from section 1), releasing boosts of 0.6, 1.2 and 2.0 s at +21%,
+26% and +30% top speed with doubled acceleration. Grip drops to a quarter
while drifting and the turn rate rises 1.4x.

## 4. Boost stacking

**Ring Racers `K_GetKartBoostPower`.** Boosts add, but each extra one is
divided by `1 + metabolism * (n - 1)`, where `metabolism = 1 - (9 - weight) *
0.5 / 8` (0.5 for the lightest, 1.0 for the heaviest). So a light kart holding
two boosts gets more than a heavy one. Handling bonuses do not stack; the
best one wins.

**Ours.** Same rule. Every boost is a named `(strength, time)` entry on the
kart; the multiplier is `1 + sum(strength_i / (1 + metabolism * i))` over
strengths sorted descending, capped at +80%. Drift boosts, Lightning Form,
slipstream and the start boost all go through it.

## 5. Slipstream / drafting

**SuperTuxKart.** A zone 8 m long and 4 m wide behind a kart doing at least
20 m/s (inner half counts double). Sit in it for 2.5 s to collect, then get
+3 m/s and 300 engine force for a duration based on time collected, fading
over 2 s. Light class 0.9x length, heavy 1.1x.

**Ours.** 360 px long, 70 px wide, target above 60% of top speed. Collect for
1.5 s, then a +18% boost for 1.6 s. The HUD shows DRAFT while charging.

## 6. Start boost

**SuperTuxKart** `startup time="0.3 0.5" boost="8 4"`: throttle within 0.3 s
of GO gives the big boost, within 0.5 s the small one. **Kinoko** treats the
start boost as its own boost type (+30%). Mario Kart also punishes holding
throttle too early with a burnout.

**Ours.** Throttle first pressed within 0.35 s before to 0.15 s after GO gives
a +35% boost for 1.0 s. Held for more than 0.9 s before GO burns out: 0.7 s
stunned. AI racers roll a reaction time so some of them get it wrong too.

## 7. Items by distance, not rank

**Ring Racers `k_roulette.c`.** Item odds are a function of *distance behind
first place*, not finishing position. Each item has a peak distance and a
duplication tolerance (`K_DynamicItemOddsRace`): sneaker 25, invincibility 60,
banana 8, orbinaut 11, jawz 16, mine 19, SPB 58, grow 60, shrink 70, in units
of 2048 map units. Distance is inflated for small lobbies
(`K_ItemOddsScale`: 2 players count as 2.5x, 16 players 0.75x) so a duel still
throws big items.

**SuperTuxKart `powerup.xml`.** Weight tables per rank, interpolated across
the field, with separate tables for 1, 5, 9, 14 and 20 karts. Global items
(switch, parachute) get rarer with more karts. In 1st place the field is
mostly bowling balls, bubblegum and plungers; last place gets zippers,
triple bowling and rubber balls.

**Ours.** Odds per item at three anchors, leading / mid / far, interpolated
by seconds behind the leader (far = 8 s, inflated by 12.5% per missing player
below eight):

| item | leading | mid | far |
| --- | --- | --- | --- |
| Fireball | 4 | 3 | 1 |
| Freeze | 4 | 2 | 0 |
| Summon Wolf | 3 | 2 | 1 |
| Blink | 0 | 2 | 4 |
| Lightning Form | 1 | 3 | 5 |
| Lightning Bolt | 0 | 2 | 4 |

## 8. AI rubber-banding

**SuperTuxKart `stk_config.xml <ai>`.** Speed caps by distance to the player
(negative = behind), e.g. hard: `first-speed-cap 50:1.0 150:0.9`,
`last-speed-cap 0:0.96 80:0.8`; karts in between average the two. Skid
probability is also distance-based (`rb-skid-probability -50:1.0 -20:0.7
20:0.2 50:0.0`), which is a subtler band than a raw speed cap. False start
probability 1% to 8% by difficulty.

**Ring Racers `k_bot.cpp`.** Bots rubber-band toward a target distance behind
1st (`K_BotRubberbandDistance`, 640 map units per position slot), with the
rival bot always chasing the front.

**Ours.** Speed scale interpolated by px ahead of the player:
`[-2000, 1.14], [-500, 1.06], [0, 1.0], [500, 0.94], [1500, 0.86]`, times a
per-racer skill factor. Drift probability by the same distance:
`[-1500, 1.0], [0, 0.6], [1500, 0.2]`.

## 9. Collisions and bumps

**Kinoko** has `bumpDeviationLevel` per vehicle and `weight` ("contrary to
popular belief, this does not affect gravity"). **Ring Racers** resolves bumps
by weight: the heavier kart pushes, the lighter one gets knocked and slowed.

**Ours.** Push and velocity exchange split by mass (`1 + 1.5 * (weight-1)/8`),
so an Ogre shoves a Bat aside and barely notices.

## 10. Off-road

**Kinoko** multiplies speed and rotation by per-surface `kclSpeed` /
`kclRot` factors (with a short "offroad invincibility" after a boost).
**Ring Racers** divides boost power by `1 + offroad`, doubled on Hard+.
**Ours** keeps the flat 45% top speed off-road with extra drag and 70% grip;
a boost now ignores off-road for its duration (Kinoko's invincibility).

## Not taken (yet)

- Hop before drift, inside vs outside drift types (Kinoko).
- Nitro, zippers, parachutes, plungers (STK).
- Sliptide / wavedash, rings, the item roulette animation (Ring Racers).
- Tricks off ramps: needs the Godot elevation to mean something first.
