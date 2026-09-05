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
sound cues map onto Qud clips and its twelve battle themes onto Qud's soundtrack. Effects,
projectiles and item pickups are procedural placeholders in Qud colours until Qud's own
items and mutations take their place; spells and equipment are empty lists for now.

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
isolated tile (`00000000`) gives a `-isolated` variant with the end posts for a lone block.
Colours come from the blueprints that paint with that family (`PaintedWall` tag → `TileColor`
/ `DetailColor`). Each model is also written as JSON layers so the Godot side needs no `.vox`
parser, plus a front/top/back preview PNG. A self-check re-reads the elevation off the
finished grid and fails the run if it differs from the art.

## Licence

MIT for everything in this repo. Caves of Qud and its assets are © Freehold Games and are not
included; the tools only ever read the copy you own.
