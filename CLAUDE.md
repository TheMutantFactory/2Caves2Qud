# Working notes for Claude (and future humans)

**The rule that shapes everything here:** Caves of Qud's content never enters the repo. The
tools read the user's Steam install and write to the per-user store `tools/qud_assets.py`
resolves (macOS: `~/Library/Application Support/2Caves2Qud/qud`). Anything derived from the
game — tiles, sounds, data, wall voxels — lives there. `.gitignore` also blocks `extracted/`
and `godot/qud/` in case something lands in the tree by accident.

## Local paths (this machine — macOS)

| what | where |
|---|---|
| repo | `/Users/homefolder/personal-git/2Caves2Qud` |
| Python | `.venv/bin/python` (deps: `requirements-tools.txt`) |
| Qud install | `~/Library/Application Support/Steam/steamapps/common/Caves of Qud/CoQ.app` (2.0.4, Unity 6000.0.77f1) |
| Qud data | `<CoQ.app>/Contents/Resources/Data` — `resources.assets` (atlases, AudioClips), `resources.resource` (audio stream), `Managed/Assembly-CSharp.dll`, `StreamingAssets/Base` (XML) |
| asset store | `~/Library/Application Support/2Caves2Qud/qud` (`tools/qud_assets.py` prints it) |
| Godot 4.7 | `/Users/homefolder/Downloads/Godot.app/Contents/MacOS/Godot` (not on PATH) |
| engine source | `~/personal-git/drift-wizard-3` — the Godot racer is on its feature branches (`rift-type` is newest; `feature/godot-3d` is the plain 3D racer), **local `main` is an empty initial commit** |
| Qud decompile | `~/qud-decomp/full/Assembly-CSharp.decompiled.cs` (one file; `grep -n "class exTextureInfo"`) |
| raves-of-qud | `~/personal-git/raves-of-qud` — the 2.5D Qud viewer; its `docs/rendering.md` §4 and `tools/capture/voxwall.py` are the origin of the flush-and-carve wall model |

## Commands

```bash
.venv/bin/python tools/qud_locate.py        # install report (exit 1 if a check fails)
.venv/bin/python tools/extract_qud.py       # tiles + sfx + data; no-op when current; --force, --only tiles,sfx,data
.venv/bin/python tools/wall2vox.py [name]   # wall families -> walls/*.vox|json|png; exits 1 on a failed self-check
.venv/bin/python tools/qud_assets.py        # where the store is + its manifest
.venv/bin/python tools/export_godot_assets.py   # fill <store>/godot + link godot/qud (after extract; after shared/ edits)
/Users/homefolder/Downloads/Godot.app/Contents/MacOS/Godot --headless --path godot --quit-after 4 -- --mute   # script/boot check
/Users/homefolder/Downloads/Godot.app/Contents/MacOS/Godot --path godot -- --track=brick --auto --frames=240 --screenshot=/tmp/r.png --mute
```

## How Qud stores what we take (verified 2026-09-05, game 2.0.4)

- **Tiles are not files.** ~27k images are packed into 17 `Kobold_DynamicAtlas_<Folder>_1`
  Texture2Ds (Walls 2048², Tiles 2048², …). Each tile is an ex2D `exTextureInfo`
  MonoBehaviour: `m_Name` = the editor path flattened
  (`Assets_Content_Textures_Walls_wall_mud-00000000.png`), a PPtr to the atlas, and the rect.
  The build has **no MonoBehaviour type tree**, so `extract_qud.parse_texture_info` reads the
  raw bytes against the class layout from the decompile. ex2D rects are bottom-left origin;
  PIL is top-down, so the crop is `(x, H-y-h, x+w, H-y)`. No tile is rotated or diced in
  2.0.4 (the rotated path in the extractor is untested). Verified: the crop of
  `wall_crystal1-00000010` is pixel-identical to the tile the raves bridge exported from inside
  the running game.
- **Names → blueprint paths.** Strip `Assets_Content_Textures_`; the first `_` splits folder
  from file (no texture folder contains `_`, file names freely do). Blueprints say
  `Tile="Creatures/sw_glowfish.bmp"`; the store holds `tiles/Creatures/sw_glowfish.png`
  (`qud_assets.tile_file()` does the swap). `tiles/index.json` maps the blueprint path to the
  file.
- **Audio** is 3020 `AudioClip`s, FMOD Vorbis streamed from `resources.resource`, 4.6 h total.
  UnityPy decodes through pyfmodex; as WAV that is 2.7 GB, so the store keeps OGG Vorbis via
  `soundfile` (libsndfile, cross-platform wheel). `--sfx-format wav` if you need raw PCM.
- **Wall tiles** are 16×24, 2-bit (black = TileColor main, white = DetailColor detail,
  transparent = background). Bottom 10 rows = the front face; the rows above = the roof;
  some families (metal) separate the two with a fully transparent row.
  Neighbourhood bits are `N NE E SE S SW W NW`. `00100010` is the E-W run (the face shows,
  no end posts), `00000000` the isolated block. Colours per family come from the blueprints
  tagged `PaintedWall`, resolving `Inherits` for the Render part.
- **Validity of the install** = the Steam `appmanifest_333640.acf` build id + the sizes of
  the files we read (`qud_locate.install_fingerprint`); the store's `manifest.json` carries the
  fingerprint it was built from, and the extractor is a no-op while they match.

## Rules

- A check must be able to fail: `wall2vox.py` re-reads the elevation off the built grid and
  compares it to the art; keep that kind of probe in every generator.
- Commit and push after each unit of work once the tools run clean (Daniel's standing
  cadence). Git identity: DazzlingDukeOfLazers <daniel.dee@gmail.com>.
- When a tool path or command is needed twice, put it in this file, not the session.

## The engine (imported 2026-09-05 from drift-wizard-3 `rift-type`, see docs/drift-wizard-3/ENGINE_BASE)

`godot/` + `shared/` + `docs/drift-wizard-3/` came over whole with `git archive` — no shared
history, so sync by diffing against the recorded commit. Three deliberate deltas from upstream:
`RW3.gd` → `QUD.gd` (autoload `QUD`, root `res://qud/`); `Audio._stream` loads OGG/WAV from
the file at runtime (the store is outside the project, nothing is imported);
`net/SteamNet.gd` reaches the GodotSteam singleton through `Engine.get_singleton` so the
autoload chain boots without the extension. Keep those three when pulling upstream changes.

- `godot/qud` is a SYMLINK to `<store>/godot`, made by `tools/export_godot_assets.py`
  (junction on Windows). Godot follows it; `.godot/` is the only import cache and it is ignored.
- The engine's asset contract (what `QUD.texture()` etc. expect) is documented at the top of
  `tools/export_godot_assets.py`. Racers = `data/monsters.json` + `units/<unit>_idle.png`
  (16×24 tiles ×3, `frame_size` 72) — the engine positions sprites by `frame_size` as height.
- Grand Prix races the `player_*` wardrobe skins (Qud castes); Monster Campaign / realms race
  `monsters.json` by difficulty band = 1 + (Level-1)//4. A creature with no `Level` is band 1.
- Headless boot check + a windowed AI race with `--frames=N --screenshot=path` (quits itself)
  are the two verifications; both in README. The race prints a `race: state=...` line at the end.
- Editor rescan: after ADDING a `class_name`, `--headless --editor --quit` once, else the
  headless check reports `Identifier "X" not declared` for every class_name script.

## Status (2026-09-05) and what's next

Done: install locate/validate, the one-time extractor (27,462 tiles + 3,020 sounds + data),
`wall2vox.py` (80 wall families; 56 get blueprint colours, the other 24 — coolant, nephilim,
skull, resheph, spindle… — fall back to grey/white), and the ENGINE: imported and booting on
Qud assets (menu, AI race on brick/ice, 904 creature racers + 24 castes, Qud floor/wall tiles,
Qud sound cues + soundtrack). Verified by screenshot.

Next, in order:
1. A GDScript loader for `walls/<family>.json` (layers → one ArrayMesh per family) and a
   track-side barrier that tiles the run model, replacing the flat `<ts>_wall_N.png` quads.
2. Qud items as the pickups/weapons: `Items.xml` blueprints (grenades, guns, tonics) in place
   of the RW3 spell list — `data/spells.json` is `[]` today, so item boxes give nothing.
3. Mutations as monster abilities (`Mutations.xml`), `Sounds.xml` event→clip mapping for the
   cues that are still regex guesses (see `<store>/godot/sfx/mapping.json`).
4. Placeholder art to Qud art: effects strips, projectiles, stun icon, portal, clouds.
5. The tracks: Qud biomes (salt marsh, jungle, desert canyon, ruins) as tilesets; realm dumps
   (`Shared.realms`) could come from Qud zone `.rpm` maps in `data/`.
