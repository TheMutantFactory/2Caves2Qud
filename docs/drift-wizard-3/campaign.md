# Campaign mode

The wizard versus the game: twenty realms, each a race against that realm's
monsters. You keep your hit points, spell points and spells between realms.
Die and the run is over.

## The loop

1. **Realm.** A track is picked for the realm; the seven racers are monsters
   from the game's spawn tables for that realm's difficulty band (band = 1 +
   (level-1) * 8 / 19, so realm 1 is bats and goblins, realm 20 is arbiters).
   Every monster carries its real HP and its first ranged spell as an ability.
2. **Laps are turns.** Each lap crossing refills one charge on every spell you
   own. When *you* cross the line: in 1st, every monster takes lap damage; in
   any other position you take damage per rank behind. Position matters twice
   a lap for the whole field: a monster crossing ahead of you hurts.
3. **Shinies** on the track: mana orbs (a random one-shot spell, as before),
   ruby hearts (heal), spell scrolls (+1 spell point), trinkets (artifacts,
   later). Killing a monster drops a heart and pays a spell point.
4. **Shop.** Tab, P or Escape pauses and opens the full spell shop (mouse,
   or arrows/stick and Enter/A). Spells cost their level in spell points and
   fill one of ten action-bar slots (keys 1 to 0). A bought spell arrives
   fully charged. **Real-time:** hold Q (Y on a pad) during the race for the
   quick shop: time slows to 15% and four affordable offers appear; press 1-4
   to buy one straight into the next slot, release Q to race on. Offers
   reroll every lap.
5. **Artifacts.** Trinkets on the track and some rift gates grant one of the
   game's 350 equipment items as a passive artifact. Items with stat bonuses
   map directly (+damage, +range, +radius, +charges, +duration, summons);
   the rest map by their first tag: Fire speed, Lightning boost, Ice drift
   charge, Nature max HP, Holy heal per lap, Dark lap damage, Arcane charges,
   Blood heal per kill, Metallic shield per lap, Conjuration summon damage,
   Sorcery spell damage, Enchantment duration, Translocation blink.
   Summons use the unit named in the spell, or a sprite for the spell's tag.
6. **Rift gates.** Finish the race alive and three gates appear as cards:
   each names the next realm's track, its reward (spell points, healing, a
   full recharge, an artifact) and a preview of the monsters. Pick one, the
   next realm loads.

## Spells as kart effects

`SpellDB.gd` turns every entry in the game's spell dump into one of a few
kart-shaped effects, from its stats and tags:

| data | effect |
| --- | --- |
| `minion_health` | **summon**: a chaser that bites the next racer it meets (minion damage, minion duration) |
| `damage` + `radius` | **blast**: a projectile that explodes for radius damage |
| `damage`, Lightning / bolt / beam | **beam**: instant hit on the nearest racer ahead within range |
| `damage` | **bolt**: a projectile |
| `shields` | **shield**: absorb that many hits |
| `heal` | **heal** |
| self-target enchantment | **buff**: a speed boost for the duration |
| Translocation with range | **blink** forward |
| enchantment with duration and range | **hex**: freeze the nearest racer ahead |

Range is tiles times 90 px, radius tiles times 70 px, duration turns times
0.8 s, damage as-is against monster HP.

## Numbers (shared/tuning.json, `campaign`)

Wizard 50 HP, 3 starting spell points, +2 per gate. Lap damage to every
monster when leading (20% of its max HP, at least 2), 2 per rank behind you otherwise, capped at 8. Hearts
heal 15. Monster abilities fire every 6 to 12 s when you are in range, at 60% damage in realm 1 rising to 130% by realm 20.

Balance runs: `godot --path godot -- --auto --newrun --mute --seed=N
--frames=5400 --screenshot=x.png` prints a damage tally by cause;
`tools/godot_tally.py extracted/*.log` summarises several. The auto driver is
a weak racer, so its numbers are a floor for a human.

## Bosses

`campaign.boss_realms` (10, 15, 20) replace the first AI racer with a boss: a
rare monster whose tier fits the realm's difficulty band, or at realm 20 one
of the game's final bosses (their 5x5 sprite is drawn at full size). Bosses run
a 6/9 stat line and carry `boss_hp_base + boss_hp_per_realm * realm` HP, so
they are worth killing on the lap rule but will not fall to one orb.

## Effect kinds

Every spell maps to one effect dict. The kinds the race can express:

| kind | what happens |
| --- | --- |
| `bolt` | homing projectile (`count` for a spread of several) |
| `beam` | instant hits on the nearest `targets` karts ahead |
| `blast` | slow fireball that detonates near a kart, hurting the `radius` |
| `melee` | swipe at karts right in front: damage, stun, shove |
| `burst` | damage everyone within `radius` of the caster; `shove` pushes them away, `only_stunned` limits it to frozen karts |
| `aura` | for `duration`, every `tick` s hit the nearest `targets` karts (0 = all) within `radius`, and/or `heal` the caster |
| `patch` | a hazard laid `range` px up the road: `damage` every `tick` for `duration`, `slip` makes it ice |
| `empower` | a temporary artifact-style bonus set (`bonuses`) for `duration` |
| `summon` | karts that ride in formation with you for `duration`: one beside you, two to eight in a fixed ring around you, more in a road-following grid behind; they bite enemy karts within reach (`summons` block in tuning) |
| `shield`, `heal`, `buff`, `blink`, `hex` | hits absorbed, HP, a speed boost, a jump forward, a stun on the kart ahead |

Extras any damaging kind accepts: `stun` (s), `shove` (px/s along the hit,
negative pulls the victim back), `heal_frac` (the caster heals that share of
the damage); beams take `hp_frac` (a share of the victim's max HP); auras
take `stun`, `slip` and `shove` too and may have no damage at all.

Artifacts without numeric bonuses get a bonus set from their own text
(shield, summon, heal, charge, radius, range, duration, teleport, HP,
speed, damage, in that order, two at most) before the tag fallback. The automatic mapping is in SpellDB.effect_for; hand-written
results live in `shared/overrides.json` (see docs/rulebook.md).

## Charges, HP costs and melee

Rift Wizard casts a spell with `max_charges` 0 as often as you like (Level.py
only checks charges when the maximum is nonzero). Those nine spells, Dragon
Claw and eight Blood spells, are unlimited here too, on a short real-time
cooldown (`campaign.unlimited_cooldown`, 1.2 s) shown in the slot as a
countdown instead of a number. A spell's `hp_cost` is paid per cast (red in
the slot) and a cast that would leave you at zero is refused. Melee spells
(`melee` in the game data: Dragon Claw, Touch of Death, Vampiricism,
Lumbriogenesis, Devour Flesh) become a swipe at karts within
`campaign.melee_range` px in front, with a stun and a shove
(`campaign.melee_shove`), so Dragon Claw is the reusable "ram the kart ahead"
button.

## The flow

Title screen (Enter) -> race type -> the race. `R` on the title opens the
racer select, `W` the wardrobe.

- **Grand Prix**: you against seven other wizards, each in a different
  outfit with one spell from the track's list as its attack, over the
  twenty realms with rift gates between them.
- **Monster Campaign**: the realms' own monsters race you. Every monster
  you slay is unlocked as a racer (saved in the user config).
- **Single Race**: pick a realm and one of its three layouts.
- **Test Rig**: see docs/test-rig.md.

Racing as a wizard gives the action bar; racing as an unlocked monster
gives only that monster's own attack on `E` or `1`, on a
`campaign.monster_racer_cooldown`, and no shop.

## Realms as tracks

By default each realm's race is built from one of the game's own generated
realms (the dumps from tools/extract_levels.py, three per difficulty): the
realm's tileset paves the road, its chasm is the ground, its walls are the
scenery, its monsters are the racers (one of each kind, plus the boss rule),
its lairs stand by the road as generators that let their monster wander
onto the track every few seconds (`campaign.generator_cap` at a time), its
memory orbs and crafting components lie on the road as spell points and
artifacts, and a dormant rift marks the line. The loop itself is a seeded
oval for now. Scroll lists come from `realm_spells` in the tuning by
tileset. The three rift gates after a realm are the three dumps of the next
one. `--map=brick|volcano|ice|chicago_loop` still gives the hand-made
tracks; `--realm=N --realm_file=NN_seed.json` picks a dump.

## Speed coins

Short lines of gold coins lie along the road (`campaign.coin_lines` lines of
`coins_per_line`). Every coin a kart carries adds `kart.coin_speed_pct` to
its top speed, up to `coin_max`, until the kart takes damage: then
`coin_spill` of them scatter onto the road behind it for anyone to grab.
The HUD counts yours.

## Monster attacks

Each monster's first damaging spell is mapped like a player spell and cast
at the wizard through the same code path (bolts, beams, blasts, bursts,
auras, summons in formation around the monster). Monsters only ever target
the wizard, get no artifact bonuses, and never run out of charges; their
cooldown is `campaign.ability_cooldown`. A monster without a damaging spell
bites. In debug mode (`--debug`, or the rig) `K` turns monster attacks off
and on, `]` and `[` jump to the next or previous realm.

## Spell upgrades

The pause shop lists the game's named upgrades under every spell. Once you
own the spell each upgrade can be bought for its level in spell points; the
card shows the game's text and what it does here (SpellDB.apply_upgrade,
the same mapping Survivors uses on a repeat pick). Bought upgrades change
the owned spell for the rest of the run.

## Spell scrolls

Each track carries its own spell list (`spells` in shared/tracks.json). Scroll
shinies cycle through it and show the spell's icon; running one over adds the
spell to the action bar for free, or gives it a charge if you already own it.
The mana orb still gives a random pickup item and the book a spell point.
