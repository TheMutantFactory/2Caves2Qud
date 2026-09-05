# Rift-Type

A side-scrolling shooter, R-Type by way of Rift Wizard, built from the game's
realms. Pick **4 RIFT-TYPE** on the title screen (or `--mode=rifttype`).

## The realm as a corridor

Each level is the realm's own generated map turned sideways. A twelve-row band
of the grid scrolls past: its wall cells become the ceiling and floor
formations (in the middle of the corridor only the odd pillar survives, so it
reads as a tunnel with obstacles rather than a maze), its chasm cells are the
backdrop, its floor tiles the ground, and its props (portals, shrines, orbs)
are scenery where the game put them. The three dumps of the realm are laid end
to end, then mirrored, for seven segments before the boss arena.

Walls block: a wall ahead stops the wizard and the scroll carries it left; a
wall above or below stops the climb. Being crushed against the screen's edge
costs HP and blinks the wizard to the nearest open spot.

## Monsters

The realm's monsters are the waves, and what they are picks the formation:

| monster | formation |
| --- | --- |
| flyers | sine weave, V, divers from above, or an orbiting ring |
| walkers | sweeping column, V, sine, or a swarm that homes on you |
| stationary things | turrets on the ceiling or floor |
| lairs | hives drawn the game's way (the monster inside the lair frame) that hatch their own monster until destroyed |
| big sprites | slow walls with lots of HP |

**Every monster uses every one of its Rift Wizard abilities.** Each spell in
its list is classified from its name and shape and fired on its own cooldown
while the monster is on screen:

| the spell | what it does here |
| --- | --- |
| melee, pounce, charge, ambush | a lunge at you when within reach |
| heal, restore, regenerate, blessing | heals nearby monsters |
| shield, ward, armor, binding | shields nearby monsters |
| drain, siphon, leech, vampiric | a beam that heals the caster when it lands |
| summon, spawn, hatch, call, raise, gather, forge, deploy | **summons what the game says it summons** (see below) |
| storm, rain, hail, barrage, salvo | bullets from the ceiling over your head |
| nova, burst, wave, pulse, quake, blast | a ring of bullets |
| beam, lightning, ray, flamethrower, breath | a telegraphed beam |
| gaze, cloud, poison, miasma, curse, hex, aura, spit | a drifting cloud that hurts while you stand in it |
| teleport, blink, shift, phase | the monster blinks to a new spot near you |
| anything with no damage type | a self buff: faster for a few seconds, tinted |
| anything else ranged | an aimed bolt in its damage type |

Summons are read off the game's own spell text ("Summon 3 Ash Imps", "Summon
a Fenris", "Summon 2 Blood Hounds") and matched to the monster list, so a
goblin king brings goblins and a bone wizard raises bone knights; a spell
whose text names nothing the sprites know falls back to a small monster of
the realm. The same reader drives the boss's summon phase. A timed run
reports which ability kinds fired and how many things were summoned.

**Their passives are the game's passives too.** `tools/extract_data.py`
now records every monster buff's tooltip and, for the spawning ones, what
they spawn and how many. The shooter reproduces the families a player sees:

| passive (game name) | who, for example | here |
| --- | --- | --- |
| Summon On Death, Box of Woe | Animated Knight, Bone Colossus, Chimeras, Bag of Bugs, Kobold Camp | dies into the named things (up to three each) |
| Splitting | Bone Shamblers, Worm Balls | splits into two half-size children, which split again |
| Respawn As | Vampires, Werewolf, Gargoyle, Spriggans | comes back as its other form (vampire to bat) |
| Reincarnation | Phoenixes, Chronos, Odin, the Cats | returns from death as many times as the game says |
| Death Explosion, Suicide Explosion, Phoenix | Goatia, Fire/Ice/Void Bombers, Phoenix | a burst in its damage type that hurts you and your party |
| Mushboom Burst, Spiked Wheel | Mushbooms, Bone Wheel | a poison cloud; eight bone spears |
| Generator | Spider Queens, Flame and Ice Rifts, Night Hag, Bag of Bugs | a chance every second to spawn its brood (up to five alive) |
| Mature Into, Chance To Become | baby spiders, eggs, bushes, bats, Trollets | grows into the adult form after a while, keeping its path |
| Slime Growth | every slime | heals, grows, and splits into two at double HP |
| Reinforcements | Gaia, Skull Hornet Hive, Yggdrasil | calls help once HP drops below its threshold |
| Summon On Kill | Crackler | another Crackler when it lands a hit |
| Retaliation, Sparking Soul | Animated Armor, The Body Electric | shoots back when hurt |
| Thorns, Curse Retaliation | Blood Knight, Bone Wheel and ten more | hurts whoever strikes it in melee: touching it, a party lunge or a skeleton's bite, or shooting it from within two tiles |
| Soul Eater, Blood Amalgam, Death Eater | Amaru, Blood Knight, Fenris, Bone King | grows when things die near it |
| Regeneration, Troll Regeneration, Shield Regeneration | many | heals or reshields over time |
| Healing Aura, Damage Aura, Toxic Aura | Fae Queen, Annihilation Goo, Goo Spitter | heals monsters near it; hurts you when you stand near |
| Passive Teleportation, Quickstep | Aether Spiders, Bad Balloon | blinks about; moves faster |

The report line counts each of these under `abilities` (death_spawn, split,
respawn_as, reincarnate, explode, generator, mature, slime_split, reinforce,
retaliate, regen, shield_regen, heal_aura, damage_aura, teleporty, grow,
summon_on_kill). The feedback showcase acts them out and quotes the tooltip.

The realm's boss (its own boss unit, else one of the game's rare monsters for
that realm, else its biggest monster) waits at the end with a fat HP bar. Its
phases come from its spell list (see Boss patterns). Clearing it moves on to
the next realm.

## The tavern and the party

Every level has a tavern about halfway along, in an open cell. Fly into it
and three of the game's thirteen adventurers (the Tavern companions:
Necromancer, Vampire Hunter, Paladin, Dragon Knight, Ranger, Berserker,
Assassin, Witch Doctor, Cleric, Engineer, Bard, Alchemist, Valkyrie, pulled
from Equipment.py by `tools/extract_companions.py`) offer to join; 1, 2 or 3
recruits one, 4 drinks alone. Up to three fly with you in formation, with
their own HP and shields shown top right, and use their own spells against
the monsters: lunges, bolts and beams at the nearest thing, the Ranger's bear
as a familiar, the Cleric's and Bard's heals on you and each other, the
Paladin's shields, the Alchemist's brews. Bullets and contact hurt them and
they can fall; the survivors carry into the next realm.

**Their passives are the game's passives**, read from the buff tooltips
`tools/extract_companions.py` pulls out and shown on the tavern card:

| companion | passive here |
| --- | --- |
| Necromancer | every Living monster that dies while it flies with you rises as a skeleton (flying or stationary as the original was) that hunts monsters for 25 seconds |
| Paladin | shields grow back every six seconds; a healing aura for you and the party |
| Cleric | a holy aura: damage to monsters nearby every second, you healed |
| Witch Doctor | a withering aura: monsters nearby corrode and take a quarter more damage |
| Vampire Hunter | Quickstep dodges half of what comes at it; silvered weapons burn Blood, Dark and Undead monsters for extra holy damage |
| Dragon Knight | adaptive armour halves the damage type that hurt it last; it teleports about on its own |
| Berserker | rage: every wound adds damage and resistance; below half HP it goes berserk for ten seconds, faster and twice as hard |
| Assassin | evasion: after a hit it teleports away and gains a shield |
| Bard | a good cast earns an encore, a life back when it falls |
| Valkyrie | when a Living ally falls she takes their place at once and her spells are ready again |

`--recruit=Necromancer,Paladin` seats companions at the start for testing, and
the report line counts skeletons raised and every passive that fired.

## The wizard

Arrows or WASD fly. Hold Enter, E, Ctrl, X or Shift to fire bolts; hold past a
second and let go for the wave cannon, a screen-wide beam. Kills drop XP orbs
that pull toward you.

**Level-ups** offer three cards, chosen with 1, 2 or 3, drawn from the
upgrades and from the game's own level 1 and 2 spells (about a third of the
draw). Upgrades: Twin Bolt, Spread, Arcane Edge, Rapid Fire, Familiar (a wolf
or bat orbits and shoots), Force Shield, Wave Cannon, Vitality, Swift, Seeking
Bolts, Piercing, Rear Guard, Force Pod.

**Spells** sit on the number keys, each on a cooldown that grows with its
level. The spell's effect record (the same one the karts read) decides what a
cast does here: bolts and hexes fire seeking shots in the spell's damage type,
beams cross the screen, blasts burst on the nearest monster ahead, auras pulse
around you for a while, summons fly as familiars for their duration, shields,
heals, buffs (a damage multiplier for a while) and blinks do what they say.

**The Force.** The Force Pod upgrade summons a floating eye that rides your
front and fires with your bolts (piercing from level 2). F or Q sends it
ahead: it holds about a screen-third in front of you, eats every bullet it
touches, rams what it meets, and fires on its own (three ways at level 3).
Press again to call it back. It cannot be hurt.

**Across realms.** Clearing a boss carries score, level, upgrades, spells, max
HP and shields into the next realm (with a small heal). Dying ends the run.

## After the boss: chest, rifts, a breather

The boss drops a **chest** (so do the big crawling minibosses). Fly into it
for one of the game's artifacts, shown with its text; its bonuses read into
the shooter: damage, HP, speed, shield charges, heal on kill, wider blasts
and beams, shorter spell cooldowns, stronger familiars. Artifacts show as an
icon row under the stats and carry across realms.

Then **three rifts** open in the arena, one per dump of the next realm, each
ringed by the monsters that wait behind it and labelled with its tileset. Fly
into one to choose which version of the next realm you get.

Between realms a **transition screen** is drawn at random from five: the
realm summary (time, kills, summons, score, what hurt you), a bestiary card
for one monster you slew (portrait, count, its abilities), the party roll
call, what you carry (spells, artifacts, upgrades), or a preview of the
realm ahead with the monsters behind the rift you chose. Enter flies on.

## Realm select, wizard select and scores

The title's **4 RIFT-TYPE** opens a realm grid (arrows move, Enter flies, or
click FLY): every realm the dumps know, its tileset, and your best score on
it. Below it is **your wizard**: the outfit you fly as, with `[` and `]`
cycling the game's outfits and W opening the wardrobe; it is the same saved
outfit the other modes use. Scores live in `user://rifttype.cfg`: best score
per realm, best run (with the realms it spanned), farthest realm cleared,
flights. The demo pilot's runs are never recorded.

## Boss patterns

The boss's own spell list becomes its phases, one per spell on a 4.5 second
cycle, announced under its HP bar:

| spell | phase |
| --- | --- |
| melee | a wind-up, then a committed dash at where you were |
| beam, lightning, ray | three telegraphed beams fanned at you |
| summon, spawn, hatch, call, raise | three of the thing it names (matched against the realm's monsters), else small ones |
| storm, rain, hail, barrage | bullets raining from the ceiling across the screen |
| nova, burst, wave, pulse, quake, blast, shatter | two staggered rings of fourteen |
| gaze, cloud, poison, miasma, curse, hex, aura, breath | drifting clouds that hurt while you stand in them |
| anything else ranged | five-way aimed spreads, three volleys |

A boss with no spells gets the stock set: spread, charge, ring, summon.

## Testing

```bash
"<godot.exe>" --headless --path godot -- --mode=rifttype --realm=3 --seed=6 --auto --seconds=160 --timescale=3
"<godot.exe>" --path godot -- --mode=rifttype --realm=3 --seed=6 --auto --mute --frames=900 --screenshot=out.png
```

Screenshot hooks: `--screen=levelup|tavern|chest|rifts|intermission` stage
that moment at frame 30 and hold it. `--auto` flies a demo pilot (lines up on monsters, flees bullets, picks the
open row through the next five columns, fires in bursts and lets a charge go
every few seconds, takes the first upgrade). A timed run prints a
`rifttype:` line: state, HP, level, score, kills, waves, whether the boss came,
the upgrades, bolts fired, when the wizard died and what did it.
