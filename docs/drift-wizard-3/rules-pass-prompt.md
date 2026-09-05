# Prompt: a rules pass on Drift Wizard 3's spell and artifact mapping

Paste everything below the line into the model, and attach these files from
`extracted/rules/` (generate them with `tools/export_rules.py`):
`rulebook.md` (the digest; enough on its own), and optionally `spells.json`,
`artifacts.json`, `kart.json` for exact numbers. Put the answer's
`overrides.json` block into `shared/overrides.json`, copy it to
`godot/rw3/shared/`, and run `tools/rig_test.py --all-spells`.

---

You are helping design the spell and artifact rules for **Drift Wizard 3**,
a kart racer built from the roguelike **Rift Wizard 3**. Every spell,
artifact and monster in the racer is the game's own, with its own sprite and
text; your job is to decide what each one *does in a race* so that it keeps
the identity it has in the roguelike.

## The racer in one page

- **A run is 20 realms.** Each realm is one race of 3 laps against 7
  monsters drawn from the game's spawn tables for that difficulty band
  (realms 10 and 15 add a rare boss, realm 20 a final boss). The player is
  the Wizard, 50 HP, in a kart. Karts have speed and weight stats derived
  from the monster's HP and flying flag.
- **Kart mechanics** (Mario-Kart-like): accelerate, brake, drift with three
  charge stages that release a boost, slipstream behind another kart for a
  boost, bumps between karts push by mass. A lap takes roughly 40 to 70
  seconds; the whole race 2 to 3 minutes. Top speed is about 780 px/s; the
  road is 210 to 230 px wide; one Rift Wizard tile is treated as 90 px.
- **Casting.** The wizard has an action bar of up to 10 spells on keys 1-0.
  Each spell has charges (the game's `max_charges`, capped at 12); one lap
  refills one charge on every spell. A spell with `max_charges` 0 is
  unlimited on a 1.2 s cooldown. `hp_cost` is paid per cast and the cast is
  refused if it would need more HP than the wizard has. Spells are learned
  from scrolls on the track, bought with spell points (SP) at a pause shop
  or a slow-motion quick shop, and SP come from kills, pickups and rift
  gates. Cost in SP equals the spell's level.
- **Monsters** race with a kart each, and use their first ranged damaging
  spell as an ability against the wizard on a 6 to 12 s cooldown when in
  range; otherwise a melee bite. Bosses have 60 + 8 x realm HP. Ordinary
  monsters keep their game HP (a realm-1 goblin has 7; a band-9 monster
  several hundred), so damage numbers matter against both.
- **The lap rule.** Cross the line in 1st and every monster loses 20% of
  its max HP; cross it behind and the wizard loses 2 HP per rank behind,
  capped at 8. Killing a monster gives 1 SP and drops a heart.
- **Artifacts** (the game's equipment) are passive bonuses picked up from
  trinket shinies or rift gates; the wizard can hold ten.
- Other modes reuse the same mapping: **Survivors** (top-down, the wizard on
  foot, spells auto-cast on cooldown) and **Gauntlet** (the game's generated
  realms in real time, spells on cooldown, spawners to destroy). Anything you
  design should still read sensibly there.

## What the code can express today (effect kinds)

Each spell is mapped to one effect dict `{"kind": ..., numbers...}`:

| kind | what happens | numbers used |
| --- | --- | --- |
| `bolt` | a homing projectile at the kart ahead | damage, range (px), targets |
| `beam` | instant hits on the nearest karts ahead within range | damage, range, targets |
| `blast` | a slow fireball that detonates near a kart, hurting everyone in the radius | damage, range, radius (px) |
| `melee` | a swipe at karts within range in front: damage, 0.3 s stun, a shove | damage, range, targets |
| `summon` | karts that ride in formation with the wizard (beside, a fixed ring, or a road grid when many) and bite enemy karts within reach | damage, duration (s), count |
| `shield` | hits absorbed | shields |
| `heal` | HP restored | amount |
| `buff` | a speed boost | strength (0.2 = +20% top speed), duration |
| `blink` | teleport forward along the track | distance (px) |
| `hex` | stun the kart ahead and make it slide | duration (s, capped 3.5) |
| `burst` | damage everyone around the caster, optional shove outward | damage, radius, stun, shove, heal_frac, only_stunned |
| `aura` | for a while, every tick hit the nearest N karts in radius and/or heal the caster | damage, radius, tick, duration, targets (0 = all), heal, heal_frac |
| `patch` | a hazard laid up the road that damages karts inside it every tick | damage, radius, range (where), tick, duration, slip |
| `empower` | a temporary artifact-style bonus set on the wizard | bonuses (dict of artifact keys), duration |

Extras on any damaging kind: `count` (bolt/blast: several in a spread),
`stun` (s), `shove` (px/s along the hit; negative pulls the victim back),
`heal_frac` (the caster heals that share of the damage).

Numbers a spell dict may carry: `damage`, `range`, `radius`, `duration`,
`targets`, `count`, `shields`, `amount`, `strength`, `distance`, `dtype`
(damage type, for colour and effects). Damage types have no resistances in
the racer yet.

Artifacts map to a bonus set from this list: `spell_damage`, `spell_range`,
`spell_radius`, `charges`, `spell_duration`, `summon_damage`,
`summon_count`, `beam_targets`, `speed` (fraction), `boost` (fraction),
`drift_charge` (fraction), `max_hp`, `lap_heal`, `lap_damage`, `kill_heal`,
`lap_shield`, `blink`.

The current automatic mapping (what the code does when nothing overrides it)
is written out in the rulebook's "Drift Wizard's current mapping rules"
section, and every spell line ends with `-> kart: ...` showing its result.

## What I want from you

1. **Review the mapping spell by spell.** Where the automatic result
   misrepresents the spell (a self-targeted burst fired forward as a bolt, a
   drain with no drain, a wall that does nothing, a summon with the wrong
   feel), propose a better mapping *within the kinds above*, with numbers.
   Keep the game's identity: level, tags, damage type, whether it is
   unlimited or costs HP, how many targets, how big an area.
2. **Propose new effect kinds only where several spells need one**, each
   with a one-paragraph spec (what it does on the track, which numbers it
   takes, how it should look using the game's existing effect sprites and
   the kinds above as building blocks). Bursts, auras, road hazards,
   empowerments, drains, shoves and multi-shot already exist (table above);
   candidates still missing: a curse that damages over time on one kart, a
   chain between karts, a decoy/wall summon that blocks, a delayed hit.
3. **Balance against the numbers above**: a 50 HP wizard, monsters from 7
   HP to several hundred, a 3-lap race, one charge back per lap, unlimited
   spells every 1.2 s. Level 1 spells should feel worth a slot in realm 1
   and level 7+ spells should feel like events. Say when a number in the
   tuning block should change instead of a per-spell override.
4. **Artifacts**: the automatic mapping only reads `global_bonuses` and
   otherwise falls back to the item's first tag. Propose bonus sets for the
   artifacts whose description clearly means something in a race (speed,
   shields, healing, extra charges, summons) and say which should stay on
   the tag fallback.
5. **Prioritise**: a top-20 list of changes that improve the racer most,
   then the long tail.

## Output format

First the reasoning as prose, grouped by spell tag or effect kind, short.
Then one JSON block that I will save as `shared/overrides.json`:

```json
{
  "spells": {
    "Wheel of Death": {"kind": "blast", "damage": 60, "radius": 200, "range": 1, "notes": "a burst around the caster: fire the blast at range 1 so it detonates on the wizard's own spot"},
    "Lifedrain": {"kind": "bolt", "damage": 6, "range": 400, "notes": "needs a drain kind: heal the caster for damage dealt"}
  },
  "artifacts": {
    "Boots of the Bear": {"max_hp": 15, "notes": "the description says HP and Nature"}
  },
  "new_kinds": {
    "drain": "spec ...",
    "patch": "spec ..."
  },
  "tuning": {
    "campaign.melee_range": 180,
    "notes": "..."
  }
}
```

Rules for the block: spell entries only list the fields that change; unknown
kinds are allowed only if they appear in `new_kinds`; artifact entries replace
the whole bonus set; `notes` are free text. Keep spell and artifact names
exactly as in the rulebook.
