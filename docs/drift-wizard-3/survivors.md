# Rift Wizard Survivors

A second mode beside the race: the wizard on foot in the Chicago Loop, the
buildings as walls, the game's monsters pouring in from the edges of the
screen, the game's spells firing themselves. Vampire Survivors with Rift
Wizard's parts.

## The loop

1. **Realms on a timer.** Every 60 s the realm counter ticks up. The realm
   sets the difficulty band (same mapping as the campaign) and so which
   monsters spawn, from the game's own spawn tables with their real HP and
   ranged spells. At each new realm a rare monster arrives as a boss with
   triple HP. Realm 20 brings a final boss; kill it to win.
2. **Waves.** Monsters spawn just off screen at a rate that climbs with the
   realm, walk at a speed from their stats (fliers are quick, ogres are not),
   bite on contact and fire their spell at range. Buildings block everyone.
3. **Spells cast themselves.** You start with one spell of your choice. Each
   owned spell fires on a cooldown derived from its charges in the game (more
   charges, faster) using the same effect mapping as the campaign: bolts home
   on the nearest monster, blasts explode, beams chain through several, summons
   become a familiar orbiting you, hexes freeze the pack, shields and heals do
   what they say, self-buffs raise your speed.
4. **XP and levels.** Kills drop mana gems worth a share of the monster's HP;
   walk near to collect. Each level pauses the field and offers three cards: a
   new spell, an upgrade to one you own (+25% damage, faster, more targets), or
   a passive (max HP, speed, magnet, cooldowns). Ten spell slots, as in the
   game.
5. **Hearts** drop now and then. Die and you get a tally and a restart.

## Controls

WASD or arrows to walk (left stick on a pad), Tab pauses, Escape returns to
the menu. Level-up cards: click or 1 to 3.

## Numbers (shared/tuning.json, `survivors`)

Wizard 50 HP at 420 px/s on the 32 px/m Loop. Spawn rate 1.5 + 0.6 per realm
monsters per second, capped at 350 on the field. Gem magnet 220 px. Level
curve 10 + 8 per level.

## Spell kinds (2026-09-04)

Survivors casts through the same spell mapping as the race, including the
hand-written overrides in shared/overrides.json: bursts around the hero,
auras that tick on the nearest monsters for a while, patches laid on the
ground ahead (ice ones freeze), empowerments (temporary artifact bonuses),
melee swipes at what is in front, multi-shot bolts, drains that heal, stuns
on hits, and beams that take a share of a monster's max HP. Unlimited
spells (max_charges 0) run on the shortest cooldown and HP-cost spells pay
per cast, refused when it would need more HP than you have.

Monsters move at a quarter of their earlier speed (`survivors.mob_speed_base` 37.5, `mob_speed_per_stat` 6.25), the wizard too (`hero_speed` 105), and every spell cooldown is four times longer (`cooldown_scale` 4).

## Realm arenas (2026-09-04, later)

Each realm is now the game's own generated realm (the dumps from
tools/extract_levels.py) as a walkable arena: walls, floor and chasms from
the grid at `survivors.realm_tile_px` (200 px a tile, four times the
Gauntlet's area), the realm's monsters and bosses where the game put them,
its lairs as spawners that let their monster out every few turns (up to
`spawner_cap` alive each) until they are killed, its memory orbs as XP and
its components as hearts, and its rifts, which light up when every monster
and lair is dead: walk into one for the next realm. `--realm=N` starts
there, `--realm_file=` picks a layout. Monsters path through the walls with
a flow field; flyers cross chasms. `survivors.arena: "plain"` or `"city"`
bring the older arenas back with the timed waves.

A repeat pick of a spell you own is one of the game's own upgrades for it,
by name: Fireball's Ash Ball, Meteor, Shaped Blast and so on, with the
game's text on the card and a line saying what it does here. The extractor
dumps what each upgrade changes (bonuses to existing stats, new stats,
added damage types); SpellDB.apply_upgrade maps those like the base stats
(damage, range, radius, duration, targets, summons, charges, HP cost,
shields, healing) and reads the text for pure flags (stuns, freezes,
blinds, drains, extra targets, bigger areas, pulls). An upgrade of level N
costs N-1 banked picks, like a spell. When every upgrade is taken the old
numeric "+" comes back.

XP per level is `xp_base + xp_step * (level-1) + xp_quad * (level-1)^2`.
On a level-up you can bank the pick instead: each banked pick lets spells
one level higher into the next offer, and taking a level-N spell spends
N-1 banked picks.

## Arena (2026-09-04)

The arena is an open field now: a flat `survivors.arena_px` square paved
with the `survivors.arena_floor` tileset, nothing to hit, the wizard starting
in the middle and the minimap a window around it. `survivors.arena: "city"`
brings the Chicago Loop back.

Pause (Tab) offers Q to quit to the menu. The camera sits lower and further
back (`cam_height` 380, `cam_back` 560). `opening_mobs` monsters spawn
`opening_distance` px from the wizard as soon as the first spell is chosen.
