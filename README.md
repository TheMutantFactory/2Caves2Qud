# 2Caves2Qud

A kart racer made of [Caves of Qud](https://store.steampowered.com/app/333640/Caves_of_Qud/):
its sprites, weapons, artwork, sounds and a few of its rules, on a track, going far too fast.
The engine is the Godot 4.7 kart racer from
[drift-wizard-3](https://github.com/TheMutantFactory/drift-wizard-3).

**This repo never ships any Caves of Qud content.** You need your own copy of the game
installed through Steam. The extractor reads that install once and writes everything the
game needs to a per-user directory *outside* this repo; nothing derived from the game is
committed.

## Layout

```
tools/            read the Qud install, write the asset store, build wall voxels, fill the engine's asset contract
godot/            the game (Godot 4.7): the drift-wizard-3 kart racer, its asset root re-pointed
                  at res://qud/ — a gitignored link into the asset store
shared/           the engine's data contract: tracks.json, tuning.json, overrides.json, maps/
docs/             design notes; docs/drift-wizard-3/ is the engine's own documentation as imported
```

## One-time setup: extract the Qud assets

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements-tools.txt
.venv/bin/python tools/qud_locate.py      # finds + validates the install, prints a report
.venv/bin/python tools/extract_qud.py     # ~2 min: tiles, sounds, data -> the asset store
.venv/bin/python tools/wall2vox.py        # wall sprites -> voxel wall models
```

The asset store lives at

| OS | path |
|---|---|
| macOS | `~/Library/Application Support/2Caves2Qud/qud` |
| Windows | `%LOCALAPPDATA%\2Caves2Qud\qud` |
| Linux | `~/.local/share/2Caves2Qud/qud` |

(`CAVES2_ASSETS` overrides it; `QUD_DIR` points at a non-Steam install.) A second run is a
no-op while the install's Steam build id and data-file sizes match the store's
`manifest.json`; a game update changes those and the next run re-extracts.

What goes in the store, and where it comes from:

| store | contents | source |
|---|---|---|
| `tiles/<Folder>/<name>.png` + `index.json` | every one of Qud's ~27k tile images, at the path the blueprints use (`Creatures/sw_glowfish.bmp` → `tiles/Creatures/sw_glowfish.png`) | the `Kobold_DynamicAtlas_*` textures in `resources.assets`, sliced by the game's own `exTextureInfo` atlas records |
| `sfx/<name>.ogg` + `index.json` | every sound effect and music clip | the `AudioClip`s streamed from `resources.resource`, decoded (FMOD Vorbis) and re-encoded as OGG Vorbis |
| `data/` | blueprints, `Colors.xml`, `Sounds.xml`, maps, text | a verbatim copy of `StreamingAssets/Base` |
| `walls/<family>.vox` / `.json` / `.png` + `index.json` | a voxel wall block per autotiled wall family | `tools/wall2vox.py`, from the tiles above |

## Run the game

```bash
.venv/bin/python tools/export_godot_assets.py   # fill godot/qud from the store (again after editing shared/)
"<godot>" --path godot                          # the menu
"<godot>" --path godot -- --track=brick --auto --frames=400 --screenshot=out.png   # an AI race, one frame, quit
"<godot>" --headless --path godot --quit-after 5                                   # script-error check
```

The engine is the Godot build of [drift-wizard-3](https://github.com/TheMutantFactory/drift-wizard-3)
at the commit recorded in `docs/drift-wizard-3/ENGINE_BASE`, imported whole (race, campaign,
local split-screen and Steam multiplayer, survivors, gauntlet and rift-type modes) with three
changes: the `RW3` autoload is `QUD` and reads `res://qud/`, sounds load straight from the
store's OGG files instead of being imported, and the Steam layer compiles without the
GodotSteam extension (online stays off until `tools/get_godotsteam.py` fetches it).
`tools/export_godot_assets.py` fills the engine's asset contract from Qud: every creature
blueprint with a tile becomes a racer (its `Level` sets the difficulty band, `Hitpoints` the
weight), the player castes from `Subtypes.xml` are the wardrobe skins, track road and ground
are Qud floor tiles over the track colours, barricades are wall-family faces, the engine's
sound cues map onto Qud clips and its twelve battle themes onto Qud's soundtrack. Equipment is an
empty list until Qud's artifacts come in.

### Effects and projectiles are Qud drawings

Qud draws its explosions as glyph particles, so there are no explosion sprites to take; the
engine's effect strips are instead Qud's own tiles animated frame by frame: its fire tiles
flicker for a burn, its four gas frames roll for poison and the hazard clouds, the force
bubble grows and fades for shields, the phase-change swirl turns for a teleport, the liquid
tiles pool for blood, the freezing ray, sunder mind, light circle and heart pulse for ice,
arcane, holy and healing. Projectiles are the thing itself: the grenade you threw, the dagger,
a slug, an arrow or a rocket, named per record by `kart.projectile`, and a mutation's bolt is
its own glyph. The stun icon is Stunning Force, the portal a teleport gate.

## Qud items as the weapons

The engine's action bar, road scrolls and shop were built around Rift Wizard's spells:
records with a level, tags, damage type, range, charges and stats that `SpellDB.gd` maps
onto kart effect kinds (bolt, beam, blast, patch, burst, hex, heal, buff, shield, summon…).
`tools/qud_items.py` builds those records from Qud's `Items.xml` instead, so what you pick
up and fire is Qud's arsenal: 49 grenades (HE and thermal blast, cryo blasts that freeze,
poison and acid gas lay a field, sleep and stun gas and flashbangs stun, gravity pulls),
50 missile weapons (pistols, rifles, bows and dart guns as bolts with the magazine as
charges; lasers, rails, eigen and spaser weapons and the freeze ray as beams; chain weapons
multi-shot, shotguns three short bolts, the flamethrower and gas pumps lay patches,
launchers and cannons blast), 12 thrown daggers, 99 melee weapons (unlimited swings) and
10 tonics (salve and ubernostrum heal, blaze and sphynx salt boost, hulk honey empowers,
rubbergum and shade oil shield). Damage is the mean of the blueprint's dice scaled to the
kart game's numbers, the level comes from Qud's tier and mark, icons are the items' own
tiles, and each record carries a `kart` hint for the kinds the automatic rules cannot
reach; `shared/overrides.json` still has the last word by name. The six arcade item-box
pickups are the same engine behaviours wearing Qud items: HE grenade, laser rifle,
recoiler, blaze injector, cryo grenade and a snapjaw pack.

### Every weapon sounds like itself

Qud's blueprints name their sounds: a gun's `MissileFireSound`, a blade's `SwingSound`, a
grenade's `DetonatedSound`, the `ImpactSound` of the projectile a gun fires. The item and
mutation generators resolve those names (and a table for the mutations: flaming ray attack,
quills expel, gas breath, injector tube…) against the extracted clips through
`tools/qud_sounds.py`, and the exporter links every take Qud ships of each one (five for
most) with a `variants.json` the engine's `Audio.play` picks from at random. So a laser
rifle fires with its own crack and lands with the direct-energy hit, a grenade plays the
throw and then its detonation where it falls, a long sword swings with steel, a snapjaw's
musket sounds like a musket. `--sfx-log` prints every cue played, which is how this is
tested.

## The courses and the racer select

The twenty courses of the Track Design Bible (`mutant-plan/strategy/2caves2qud-tracks`) are
engine data in `tools/qud_tracks.py`: a loop drawn from each Route, a Qud biome for road,
ground and walls, the surface hazards the course is about (pond water in Joppa, oil and lava
in the Asphalt Mines, ice in Bethesda Susa, warm static on the Moon Stair), laps, items and
the roster line the Courses page shows. Five cups, easiest first; the Grand Prix runs them in
order. What the bible asks for that the engine cannot build yet (section races, timed gates,
jumps, lap-by-lap change, parallel rooms) is recorded per course as `gaps`. See
[docs/tracks.md](docs/tracks.md).

Racer select follows the large-roster design: a shared grid of fourteen collections in the
centre (Favorites, Recent, All, Random, then Castes, Legendary, Villagers, Snapjaws & Kin,
Robots, Bugs & Oozes, Beasts & Birds, Plants & Fungi, Cherubim, Crystals), and four seat
quadrants that browse privately: join, choose a collection, page a 2×5 browser, pick a
variant, ready. 908 racers, numbered siblings folded into variants, favorites and recent per
seat, and a start that goes to the Courses page as a split-screen party when more than one
seat is in. See [docs/racer-select.md](docs/racer-select.md).

## Mutations as the monsters' abilities

In the Monster Campaign the field is Qud's creatures, and each one attacks with what its
blueprint gives it. `tools/qud_mutations.py` turns a creature's `<mutation>` entries into
ability records in the same shape as the items (flaming and freezing rays and light
manipulation as beams, pyro- and cryokinesis, gas generation, webs and spore puffs as
patches, disintegration and breath weapons as blasts, confusion, stunning force and sleep
gas as stuns, syphon vim drains, temporal fugue and burgeoning summon, quills and horns and
stingers strike, regeneration heals, force bubble shields, teleportation blinks), scaled by
the mutation's level, with Qud's mutation tiles as icons; wings mark the creature as flying.
The weapons in a creature's inventory that are item records come along too, so a snapjaw
hunter fires its short bow and a chrome pyramid its swarm rack. The engine picks the first
ranged damaging record as the creature's ability and casts it at you on a cooldown; a
creature with nothing bites. 284 of the 904 creatures are armed this way. The same list
arms you when you race as an unlocked monster.

## Wall voxels

Qud's wall families (`wall_mud`, `wall_rock`, `wall_crystal1`, `wall_brinestalk`, …) are
autotiled sets of 16×24 sprites keyed by the 8-bit neighbourhood (`-00100010` = walls east
and west). Each sprite packs a top-down roof in its upper rows and a **10-pixel-tall front
face** in its bottom 10 rows, as a 2-colour mask the game paints per object (black = main
colour, white = detail colour).

`wall2vox.py` takes the **front-facing run tile** (`00100010`: nothing to the south, so the
face shows; walls east and west, so no end posts) and builds a 16×16×10 voxel block: the
face carves the south side (and, mirrored, the north), the roof carves the top, background
pixels recess and everything else stays flush — the raves-of-qud "flush-and-carve" model. The
isolated tile (`00000000`) gives a `-isolated` variant with the end posts for a lone block,
and the single-neighbour tiles (`00100000`, `00000010`) give `-end-west` / `-end-east` pieces
with a post on the open side, so a run of blocks in the game reads as one wall with proper
ends.
Colours come from the blueprints that paint with that family (`PaintedWall` tag → `TileColor`
/ `DetailColor`). Each model is also written as JSON layers so the Godot side needs no `.vox`
parser, plus a front/top/back preview PNG. A self-check re-reads the elevation off the
finished grid and fails the run if it differs from the art.

In the game, `godot/QudVox.gd` turns those layers into one shared `ArrayMesh` per family
(only solid-to-air faces, vertex-coloured per material) and `Track.gd` places the blocks
where the engine used to stand flat wall sprites: runs of blocks across the sealed side
streets of a city track (the barricades a kart bounces off), and short ruined runs of wall
scattered beside a loop track, turned to face the road. One block spans the old 60-px sprite
pitch, so the tracks' spacing and collisions are unchanged. The tileset → wall family mapping
is the `wall_families` table in the exported manifest; a tileset without a voxel model falls
back to the sprites.

## Licence

MIT for everything in this repo. Caves of Qud and its assets are © Freehold Games and are not
included; the tools only ever read the copy you own.

## Sprite browser

```bash
.venv/bin/python tools/sprite_browser.py --build        # once (and after an extract)
.venv/bin/python tools/sprite_browser.py --serve 8765   # http://localhost:8765/
```

Every tiled Qud blueprint painted in its colours, in a category tree drawn from the
blueprints' inheritance, with which of Qud's zone templates hold it and which courses dress
with it, how the engine would display it (billboard, voxel wall, water cell, unit strip),
and a placement helper that writes `dressing` entries for `tools/qud_tracks.py`. Its output
lives in the asset store, outside the repo.

## Level editor

```bash
cd godot && Godot -- --type=gp --track=joppa --newrun --editor
```

An overlay over a course in free drive: the course's sprites in a tree, per-blueprint hide /
display mode / scale / tint / solid / density, per-instance hide, nudge, move and place, the
floor mode and the zone's position, saved to `shared/levels/<key>.json` and read by every
race. See docs/level-editor.md.

## The tour

```bash
cd godot && Godot -- --type=gp --tour
```

The game drives you through every course in real time. SPACE pauses and opens a note box;
Enter saves the note with a screenshot to `reports/tour-feedback.md`; N and B skip, T takes
the wheel. See docs/tour.md.

