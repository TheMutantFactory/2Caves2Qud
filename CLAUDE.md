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

## Status (2026-09-05) and what's next

Done: install locate/validate, the one-time extractor (27,462 tiles + 3,020 sounds + data),
and `wall2vox.py` (80 wall families, all 16×24, face 10 rows, cap 12–14 rows; 56 families get
blueprint colours, the other 24 — coolant, nephilim, skull, resheph, spindle… — are painted by
other mechanisms and fall back to grey/white).

Next, in order:
1. **Bring in the engine.** Decide which drift-wizard-3 branch to start from (`rift-type` has
   everything incl. multiplayer; `feature/godot-3d` is the lean 3D racer) and copy `godot/` +
   `shared/` here, then swap its `rw3/` asset root for the Qud store (`godot/qud/` symlink or
   an `export_godot_assets.py` step that copies just what the game uses).
2. A GDScript loader for `walls/<family>.json` (layers → one ArrayMesh per family, greedy
   faces are optional at 2.5k voxels) and a track-side barrier that tiles the run model.
3. Sprites for karts/items: creature and item tiles are 2-bit too; the recolour rule is in
   `tools/qud_palette.py` (black→TileColor, white→DetailColor), blueprints in `data/`.
4. `Sounds.xml` in `data/` maps game events to clip names in `sfx/index.json`.
