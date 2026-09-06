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

Voxel walls IN GAME (2026-09-05): `godot/QudVox.gd` (static cache, one ArrayMesh per
model, `vertex_color_is_srgb`) + `Track._build_barricades` / `_build_scenery` place blocks at
`WALL_PX` (60 px) pitch, front face toward the road (`rotation.y = atan2(facing.x, facing.y)`).
The race log prints `walls: N voxel ... blocks (<family>)` — read that, not the screenshot,
to know the voxel path ran (the sprite fallback prints nothing). Verified brick + chicago_loop.

End pieces (2026-09-05): wall2vox exports `-end-west` (`00100000`, wall to the east only)
and `-end-east` (`00000010`), mirroring one from the other if a family ships only one (all 80
ship both). `QudVox.run_variant(k, count, along, facing)` picks isolated / end / run per block;
a block's east is `facing` turned a quarter clockwise, `(facing.y, -facing.x)` in world px.

Qud ITEMS as the weapons (2026-09-05): `tools/qud_items.py` → `data/spells.json` (220
records: 49 grenades, 50 missile, 12 thrown, 99 melee, 10 tonics) + `icons/` from item
tiles. Each record's `kart` dict is applied in `SpellDB.effect_for` after the rules and
before `shared/overrides.json`. Arcade pickups (`Items.KINDS`) keep their six behaviours
under Qud names/icons; summons use `tuning.items.summon_unit` (snapjaw). Verified with the
test rig: `--rig=ahead:220 --learn="Laser Rifle,..." --cast="Laser Rifle@2,..." --report=x.json`
prints `rig cast: <name> ok=true kind=<kind>` per cast and the report carries damage dealt.
Gotchas: Qud DisplayName markup NESTS (`{{crysteel|{{crysteel|crysteel}} dagger}}`), strip in a
loop; melee Physics Category is "Melee Weapons" (plural); thrown junk (corpses, husks,
injectors) needs the Tier tag filter.

MUTATIONS as abilities (2026-09-05): `tools/qud_mutations.py` (class → kind table; creature
blueprints name mutations by CLASS, Mutations.xml maps class → display name + tile; breathers
have no Mutations.xml entry) + the creature's inventory weapons that are item records →
`monsters.json[].spells`, ranged-damaging first (the engine picks the first such). 284/904
armed. `Race.gd` gained `--type=gp|campaign|single` for CLI tests. Probe: a campaign race's
`race:` tally — monster abilities land in the `bolt` (projectiles), `hazard` (patches) and
`wolf` (summons) buckets, not `ability` (that bucket is melee). Damage by band is TUNED
(docs/balance.md): `ability_damage_by_band` fitted to a per-band median hit, a 20% per-hit
cap, a 2.5 s mercy window after a monster hit. `hit:` lines under `--hazard-log` are the probe.
The engine reads tuning from the STORE copy (`godot/qud/shared/tuning.json`): copy or re-export
after editing `shared/tuning.json`, or a probe silently measures the old values.

PER-WEAPON SOUNDS (2026-09-05): there is NO Sounds.xml in Qud's data — sounds are TAGS on the
blueprints (`MissileFireSound`, `SwingSound`, `ThrownSound`, `DetonatedSound`, projectile
`ImpactSound`), path-like values whose last segment is the clip base; clips ship as five
takes `-001..-005`. `tools/qud_sounds.py` resolves; records carry `kart.sound` (cast) and
`kart.hit_sound` (impact/detonation); the exporter links every take + `sfx/variants.json`,
`Audio.play` picks a take at random and `--sfx-log` prints `sfx: <name> -> <clip>` (THE probe).
`Items.cast_spell` plays the cast sound up front (beams on the first hit), projectiles carry
`hit_sound` (Race's projectile loop plays it on impact / a grenade's end of flight), the arcade
pickups play `pickup_<kind>`. The 15 engine cues in `mapping.json` are still regex guesses.

QUD ART for effects (2026-09-05): `EFFECTS_QUD` / `PROJ_QUD` tables in the exporter build the
strips from tiles with per-frame ops (scale/flip/rot/alpha); records carry `kart.projectile`
(a tile stem in `effects/proj/`), `Items.proj_texture` resolves it. GOTCHA: Godot IMPORTS the
PNGs under the `godot/qud` symlink (`.import` sidecars land in the store) and serves the CACHED
texture from `.godot/imported` after a re-export — the exporter now ends with a headless
`--import` (`CAVES2_GODOT` names the binary, `CAVES2_NO_IMPORT=1` skips). If art looks stale,
that is why. Effect strips are 48×72 frames (Qud tiles ×3); projectiles ×1.5.

COURSES + RACER SELECT (2026-09-05): `tools/qud_tracks.py` GENERATES `shared/tracks.json` (edit
the script; 20 courses + the city guest); `docs/tracks.md` has the table and the `gaps`.
Exporter `TILESETS` are Qud biomes (35) and `wall_families` is keyed by the course's `wallset`.
Track: `spec.elevation`, `hazard_spots()`; Race: `_spawn_track_hazards` (fixed `Items.Hazard`
patches, `HAZARD_KINDS`), `laps` from the spec, GP fallback `Shared.track_for_level`. Menu
`levels` page = COURSES (cups); `racers` page = `RacerSelect.gd` (design doc in mutant-plan);
`tools/qud_racers.py` → `data/racers.json`. Probes: `hazards: N course patches (<key>)` in the
race log; `--mode=racers --party=N --select_demo=...` + `--select_autostart` → `menu: page=levels
players=N`. GOTCHA: a bad python splice duplicated a block of the exporter once — after editing
by index, `grep -c "^def name"` for duplicates.

CYCLING HAZARDS + JUMP PADS (2026-09-05): hazard entries carry `period/duty/phase` (Track
`hazard_spots` must pass them — it dropped them once and every course reported "0 cycling");
`Race._update_course_hazards` sets `Hazard.active/cue`, kinds `barrier/wheel/cart/bell/jump`
in `HAZARD_KINDS` (`stun` per kind), pads call `Kart.launch` (air_t: no off-road drag, arc
lift in `update_visual`). `tools/qud_tracks.py` `TIMED` table adds them per course. Probe:
`--hazard-log` prints `hazard: <kind> on|off t=` and `jump: <kart> t=`.

PER-LAP HAZARD SETS (2026-09-05): hazard `laps` + `per_lap` overrides; `Race._apply_lap_sets`
runs on the LEADER's lap (`_leader_lap`), dormant-by-lap hazards draw faint (preview), course
`lap_notes` go through `say()`. `tools/qud_tracks.py` LAPPED / LAPPED_REPLACES / LAP_NOTES.
Probe: `--hazard-log` → `lap N: hazard set k / n live`; `--timescale=3` gets a race to lap 3
in ~35 s wall. monsters.json `name` is now the cleaned DISPLAY name; `qud` is the blueprint
name (racers.json and abilities key on `qud`).

PARALLEL ROUTES (2026-09-05): spec `branches` → `Track.branches` (`_build_branches`, open
Catmull-Rom, `_ribbon_of` generalises the road strip); `nearest()` returns `branch/bidx` and the
branch sample's EQUIVALENT loop index (`branch_equiv`) so `advance` keeps laps; `Track.aim` +
`choose_branch` steer the AI (`Kart.branch*` fields); hazards/items on branches; minimap draws
them. GDScript gotcha: `var x := <expr over an untyped param>` fails to infer — type it.
Probe: `branches: N parallel routes` + `branch: <kart> takes <name>` under `--hazard-log`.

SECTION RACES (2026-09-05): spec `sections` > 0 → `Track.open` (open Catmull-Rom with a
500 px lead-in, `start_i`, `start_wp()`, `direction_at` clamps, `nearest` no wrap, `advance`
finishes at the far end by setting `kart.lap = 99`, a FinishLine mesh); Race sets every
kart's `next_wp = track.start_wp()`, skips the lap rule on open roads, and the HUD /
`_leader_lap` use `stage_of` / `stage_name` / `stage_count`. Probe: `section N: hazard set`
lines and `race: state=gates|finished lap=99`. The rig's arc-length helpers still assume a loop.

LAP-CHANGING GEOMETRY (2026-09-05): branch `laps` (dormant = translucent ghost, not road,
skipped by `nearest`/`choose_branch`, hazards sleep via `spot.branch`) + spec `road_states`
(the loop road is built in PIECES at stretch boundaries — `road_pieces` — so a piece can be
hologram / cracked / gap; `on_road` is false in a gap; a `bypass` branch is taken 0.9 while
its stretch is a gap). `Track.apply_lap(lap)` runs from `Race._apply_lap_sets` and returns
the change strings the log prints. `_ribbon_of` returns its MeshInstance3D now.

MOVERS + THROWERS (2026-09-05): spec `movers` ([at, side] paths, pingpong/loop, period; drawn
as amber MoverMark ribbons; `Track.mover_paths`, static `mover_pos`) ride in `course_hazards`
with a `mover` dict and are re-placed every frame; `throwers` are `course_hazards` entries
with a `thrower` dict and no node until a stone flies (`_update_thrower`: shadow Hazard from
`pad_shadow`, cue seconds, then hit_kart + effect + stone sounds). Probe: `stone: ... lands
hits=N`, the `hazard` tally bucket, `hazards: ... N moving, M throwers`.

AUTHORED ELEVATION (2026-09-05): spec `profile` → `Track._build_profile` (cosine between
keypoints into `profile_h` per route point, then a 160 px `hgrid` of the nearest route point's
height faded by distance: full to 1.5 widths, gone by 4); `height_px` = noise + `authored_height`
(bilinear); `grade(p, fwd)`; Kart caps top speed by grade (0.72..1.22) and adds a slope push.
Build prints `elevation: <key> authored lo..hi px`. The probe line has `h=` / `grade=`.

CAMBER + LEAN (2026-09-05): spec `camber` → `Track._build_camber` (signed curvature smoothed
±6 samples, `bank[i]`), `camber_at(p)` via `_route_lateral` (stride-2 nearest scan — cheap
enough per to3 call; the ground build pays ~5M ops once), `banking(p)` → +20% grip in Kart.
spec `lean` {lap: [dx, dy]} → `apply_lap` sets `lean_target`, `Track._process` animates
`lean` over 3 s AND rotates the Track node about the map centre so built meshes tilt; `to3`
adds `lean_h` so Race-owned things (karts, hazards, boxes) match. `height_px` = noise +
authored + camber + lean. Build prints `camber: <key> N px, steepest bank M px`; the log
prints `lap N: lean dx,dy`.

STEPS + SHAFTS (2026-09-06): profile keypoint `[at, h, "step"]` → `Track.steps` (route
indices = ceil(at*n), the first sample with the new height — floor was off by one and lerped
across the cliff), the road pieces cut there WITHOUT sharing the point (no vertical strip),
the shelf grid makes the shaft wall. Near the road `authored_height` is the EXACT route
height interpolated along the segment (`_route_lateral.along`), never across a step; the
grid (160 px cells) only serves the far field — a grid-smoothed ledge was a ramp and karts
fell in pieces. Camber's `bank` is interpolated the same way. Kart: `alt`/`vz`/`abs_h` — when `abs_h - height_px(pos) > 12` the
kart falls (GRAVITY 1400 px/s², grip ×0.35 in the air), `landed_from` for one step, Race plays
the thud + effect and logs `drop: <kart> fell N px`. Build prints `... N steps`.

CUTTERS + VOID (2026-09-06): mover `cuts_walls`/`opens` → `Race._update_cutter` (blocks along
the path from `Track.blocks_along`; `Track._build_cut_walls` lays the rock run along the path first, freed as the mover's first-pass distance passes them;
`unseal_branch` at the end); branch `sealed` (never live until unsealed). Void: `Track.void_here`
(gap/void stretch within the road, or `void_offroad` past `void_margin`), `Race._void_check`
sinks the kart 1 s (`Kart.void_t`) then `return_point` (past the stretch, +3 samples). Probe:
`cut: <mover> cut N wall blocks, opens <branch>`, `void: <kart> falls / returns at`.

The bible's engine list is COMPLETE. BALANCE (2026-09-06): the AI field's damage by band is
tuned (docs/balance.md; 0 deaths in 18 auto-player races, was 11), and the LAP RULE for a
trailing wizard is capped at 5 with a 20% HP floor (`Race._lap_penalty`, probe `lap: floor`).
GRAYBOX PASS (2026-09-06, docs/graybox.md): `--graybox` prints one `graybox:` line per race
(lap best/med vs target, offroad %, stuck s, drops, voids, item sets + gap, tightest bend).
Every loop lapped SHORT (~0.5 of the bible's lap; sections ~0.16 of the run) → per-course
`STRETCH` in qud_tracks.py scales control + size (widths stay in kart widths, mover periods
scale). Item sets are spaced by road length at 850 px/s (race.item_set_seconds/item_pace_px).
`--frames` is PHYSICS frames (60/s) regardless of --timescale: 20000 = 333 s. Batch 20
courses with xargs -P 6 (~12 min). GOTCHA: waypoint samples per control segment must scale
with stretch (Track.advance needs the next point within width x 0.7) — the first stretched
batch read 47-82% off-road on the sections for that reason. Circuits now lap 0.90-1.14 of
target; the section races were RE-ROUTED (three regions each, 4800x3200 canvas, ~2x road)
and run 0.88-0.93 of the bible's run. The race ENDS when the wizard finishes: a graybox
`finished=k/n` counts only the karts ahead of it. RACER SELECT EXTRAS (2026-09-06, docs/racer-select.md): locks by band (`select.lock_band`
6 + Campaign.unlocked), twin rule (next free variant, told), per-seat filters (key 9) / sort
(key 8) / keyboard search (/), 3D pedestal preview (SubViewport per quad; the vehicle IS the
sprite), spoken names (OS TTS, `--spoken`), reduced motion. Probes: `--select_log` +
`--select_keys=seat:action,...` (runs BEFORE the Menu seats --party players: start with 0:a).
PSYCHIC OVERLAYS (2026-09-06): spec `psychic` (forms per section, envelope, beat) →
`Track._build_psychic` (edge chunks, silhouettes, stud multimesh) + `psychic_update`;
`Race._psychic_step/_psychic_visual` draw the ghost echoes (1 s ring per kart). Probe
`--psychic-log`. A windowed `--frames=N` counts RENDER frames: pair with --timescale to reach
a late section for a screenshot.
OCCLUSION STRUTS (2026-09-06): spec `struts` + `strut_strips` → `Track._build_struts`
(panels via `_fence_of`, strips via `_ribbon_of` with no_depth_test) + `struts_update`
(near a human → alpha 0.14). Probe `--strut-log` (`clear_frames` must GROW). A "none" line
in `_process` needs its own once-flag (physics frame 1 never lines up with a render frame).
PLASMA JELLIES (2026-09-06): hazard kind `jelly` → `Track.hazard_spots` expands to an emitter
+ three `plasma` patches across one lane sharing the cycle; `Race._update_jelly` swells the
sprite for JELLY_CHARGE s before the vent. Probe `jelly: N charging / vents` under
--hazard-log. GOTCHA: a key set on a hazard SPOT must be copied into the course_hazards
ENTRY (the spawner rebuilds the dict) — the first probe cycled the patches with no jelly.
SUNSLAG POLYPS (2026-09-06): spec `polyps` + `sunslag` → `Track.polyp_spots`, `Race._spawn_polyps
/_update_polyps/_regrow_polyps` (regrow in `_apply_lap_sets`); icons `polyp`/`sunslag` from
Qud's coral ball / sunslag bulb via PICKUP_ICONS in the exporter. Probe `polyp:` lines under
--hazard-log. GOTCHA: inserting a call "at the end of a function" by text — check the
function really ends there (a trailing comment + var block bit twice).
HAPTICS (2026-09-06): `Race._haptics` rumbles a human's pad on the psychic beat before a
bend (`Track.bend_ahead`: >25 deg over 1200 px of road — never count waypoints for distance,
their spacing changes with stretch; the studs' emphasis shares the rule); `_pad_of` maps a seat to its GamepadAdapter.device, the solo
wizard to the first connected pad. `race.haptics` switch; probe `--haptics-log` (pad=-1
headless). THE BIBLE'S LISTS ARE CLOSED.
ECHO ROOTS (2026-09-06): branch `echo` {period,duty,phase} → `Track.echo_update` (solid on the
beat, magenta echo when faded), `void_here` falls a kart on a faded echo only past the main
road (`_main_dist`: a branch's mouth overlaps the road — the first cut dropped the whole
field at the fork), `choose_branch` skips a faded echo. Probe `echo:` lines under --hazard-log.
THE BELL (2026-09-06): spec `bell` → `Track._build_bell` (checker pads on the route + one per
branch, a generated ImageTexture) + `Race._update_bell` (sector clock, tether per window,
displace = stun + sideways shove, chimes, HUD `BellRing` inner Control drawing an arc).
Probe `bell:` lines under --hazard-log (rings/tethered/displaced). CREMATORY + TELEPORTER (2026-09-06): hazard kinds press (block + shadow cue), arm (mover),
vent, fan (mover; pushes along its motion, FAN_PUSH), teleport (`target` fraction → exit
waypoint; sets pos/vel/heading/next_wp, 2 s cooldown). Mover marks are coloured by kind.
EVERY COURSE FILE IN THE BIBLE IS BUILT.
TOUR (2026-09-06, docs/tour.md): `--tour` → `Tour.gd` drives every course in Shared.track_order
(Campaign.tour_index survives scene reloads; Race takes the key from Tour.key_for); SPACE pauses
(race.paused) + note box; Enter saves to reports/tour-feedback.md + reports/tour/<key>-<stamp>.png
(shot taken BEFORE the panel shows); N/B/T/A. Race's own pause key is off under the tour.
Probe `--tour_test` (pause at 3 s, note, advance, quit), `--tour_hold` for a screenshot.
LEVEL EDITOR (2026-09-06, docs/level-editor.md): `--editor` → `LevelEditor.gd` over free drive;
`Track` dressing is now COLLECTED (`dressing_items`, stable ids z:/s:/x:) then PLACED through
`level_overrides` (shared/levels/<key>.json: kinds / hidden / moves / extras / course) by
`rebuild_dressing()`; `_place_item` does the display modes; solid = barricade segments.
Probe `--level_edit=Name:prop=value;@id:prop=value;+Name@x,y;undo` + `--level_save`. Per-instance
`inst` overrides (scale/rot/flip), full palette (exporter paints EVERY tiled blueprint into
dressing/), fly camera (F2, IJKL/U/O, right-drag), undo/redo (snapshots, 60 deep). GOTCHA: never name a method `_set`
(Object._set) — the parser rejects the signature. SAVE writes the repo AND the store copy.
SPRITE BROWSER (2026-09-06): `tools/sprite_browser.py --build` paints every tiled blueprint
(4031) into <store>/browser/thumbs + index.json (category = inheritance chain, kind, which
Qud .rpm zones hold it and how many, which courses use it); `--serve 8765` serves
tools/browser/index.html (tree / search / kind / zone filters, detail with "how displayed",
a placement helper that writes `dressing` entries and a per-course plan in localStorage).
Launch config "sprites" in ~/.claude/launch.json (preview pane reads the HOME launch.json).
QUD FLOOR (2026-09-06): spec `floor_mode: "qud"` / `race.floor_mode` → `Track._build_qud_floor`
(60x90 cells, per-cell UV into `tiles/track_<key>_floor.png`, weights from
manifest.track_tiles[key].floor_weights); exporter `FLOOR_SETS` per offroad biome, atlas
composited over 0.3 x the course ground colour (a transparent atlas rendered BLACK ground).
SET DRESSING (2026-09-06): `tools/qud_zones.py` reads Qud's .rpm zone templates (80x25 grid
of blueprint names); the exporter's dressing step (after the walls export — it needs
manifest.wall_families) writes data/zones.json, data/dressing.json and dressing/<slug>.png
(painted tiles); `Track._build_dressing` stands a zone beside the road (walls → voxel runs by
neighbour scan, ponds → water cells, creatures → unit idle strips, else billboards) and
scatters blueprints. Course spec `dressing` (see the generator's docstring). Probe: the
`dressing:` build line. Joppa done; the other courses' zones are listed in docs/tracks.md.
Next: play it — the graybox and select passes are numeric; a human lap and a human select
session will find what the probes cannot.
2. Racer select: unlocks, duplicate rule, 3D racer-and-kart preview, search (docs/racer-select.md).
3. The tracks: Qud biomes (salt marsh, jungle, desert canyon, ruins) as tilesets; realm dumps
   (`Shared.realms`) could come from Qud zone `.rpm` maps in `data/`.
