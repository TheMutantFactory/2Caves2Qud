# Rift Wizard Gauntlet

The game's own realms, in real time. `tools/extract_levels.py` runs Rift
Wizard 3's `LevelGenerator` for realms 1 to 21 and dumps the results: the
18x18 grid of floor, wall and chasm tiles with their biome, every monster the
generator placed with its HP and spells, the spawners (the game's "monster
generators", 40 HP, summoning on a cooldown), the rift portals, memory orbs
and component pickups. The Godot mode plays those levels like Gauntlet.

## The loop

1. **A realm loads** from the dump for the campaign's current level: walls as
   blocks with the biome's wall tiles, floor with the biome's scribbles,
   chasms as sunken lava, water or swamp that walkers cannot cross and fliers
   can. You start on the generator's start tile.
2. **Monsters hunt you** along a flow field over the tiles, bite on contact,
   and fire their ranged spell when they have one. Spawners stand still and
   summon their monster every few seconds until you destroy them. Bosses are
   bigger and marked.
3. **Spells are on cooldowns.** Keys 1 to 0 cast the spells in your slots at
   the nearest monster in range; each then cools down for a time set by its
   charges in the game (more charges, shorter cooldown). Same effect mapping
   as the campaign: bolts, blasts, chain beams, familiars, shields, heals,
   hexes, blinks.
4. **Shop on Tab.** The campaign's spell shop and artifacts. Memory orbs on
   the floor and every kill pay spell points; component pickups grant an
   artifact.
5. **Clear the realm** and the rift portals open. Walk into one for the next
   realm (+2 spell points, as the game pays per realm). Twenty-one realms.
   Die and the run ends.

## Controls

WASD or arrows walk, 1 to 0 cast, Tab shop, Escape menu (on the death or win
screen). Cards and shop use mouse, arrows and Enter.

## Spell kinds (2026-09-04)

Gauntlet casts through the same spell mapping as the race, including the
hand-written overrides in shared/overrides.json: bursts around the hero,
auras that tick on the nearest monsters for a while, patches laid on the
ground ahead (ice ones freeze), empowerments (temporary artifact bonuses),
melee swipes at what is in front, multi-shot bolts, drains that heal, stuns
on hits, and beams that take a share of a monster's max HP. Unlimited
spells (max_charges 0) run on the shortest cooldown and HP-cost spells pay
per cast, refused when it would need more HP than you have.
