# Overland — racing on the real Qud surface

The courses so far are drawn from scratch on a blank canvas. Overland is the other way round:
Caves of Qud generates its world from a seed, we take the surface as it comes, and pave the
courses into it. One zone of Qud is one chunk of ours; the whole 80 x 25 parasang map is one
continuous ground, and eventually you drive from one race to the next across it.

This page is the plan, the scoreboard that grades it, and the decisions it rests on. The
status line at the top is the only part that changes often.

**Status (2026-09-15, evening): everything in the table is built; the full run
(`tools/overland_score.py --screen`) scores 100 / 100, see `reports/overland-score.md`.
Next: step 7, the drive to the next race.**

## What was learned before the plan (2026-09-15)

- **Raves of Qud does not generate the world. Qud does.** Raves is a viewer on a running,
  modded game: its C# bridge mod publishes the active zone each turn and Godot draws it. So
  "generate the entire world from a seed" means asking the running game to build zones, which
  its `ZoneManager.GetZone(id)` does on demand and deterministically for a world seed.
- **The overworld is static.** `StreamingAssets/Base/QudWorldMap.rpm` is the 80 x 25 parasang
  terrain map (jungle 554, mountains 183, salt dunes 245, canyon 138, moon stair 69, ...). The
  seed varies what stands in a zone, not the biome of the parasang. Roads between race sites can
  be designed on that map with no game running.
- Raves already has the pieces the render side needs: `World.gd` (zone id <-> global cell
  maths: 80 x 25 cells per zone, 3 x 3 zones per parasang), `WorldStore.gd` (zones persisted to
  `<RavesOfQud>/world/<gameId>/<zoneId>.json`), `ZoneSnapshot.cs` (the per-cell sweep with
  tile, colours, wall / solid / liquid flags and Qud's own per-cell `light` byte), and the
  `zonetp` bridge command that moves the player to any zone id (builds it). Its stored zone
  record is 800 KB per zone, so a bake needs a compact format.
- 2Caves2Qud already stands a Qud zone template beside a course (`Track._collect_dressing`:
  walls to voxel runs, liquids to water cells, creatures to unit strips, else billboards) and
  paints every tiled blueprint into `dressing/`. The overland chunk builder is that code fed
  by baked zones instead of `.rpm` templates.
- The racer's world unit is the pixel (`Track.U` = 0.05 m/px, `TILE_PX` 60, one voxel wall
  block = 60 px). **One Qud cell = 60 px**, so a zone is 4800 x 1500 px and a course canvas
  (about 3600 x 2400 px after `STRETCH`) covers one to two zones. The whole map is
  1.15 M x 112 k px = 57 km x 5.6 km; float32 keeps ~4 mm at that range, fine for one region,
  a floating origin later (see Deferred).
- On this PC the deployed Raves mod is OLDER than `origin/main` (it lacks `zonetp`, `loadout`,
  `identifyall`); the bake command goes on a branch off `origin/main` and is deployed with it.

## What was learned building it (2026-09-15)

- **The bake is fast.** `ZoneManager.GetZone` builds a marsh zone in ~1 s and Joppa's own in
  17 ms; the 5 x 5 parasang region (225 zones) took 52 s and 2.5 MB. The whole surface
  (18,000 zones) is an hour or two, not a night. Raves branch `dd/pc-world-bake`:
  `mod/BakeExporter.cs`, `tools/capture/bake.py` (and `qud.py load <save>` through the bridge).
- **A course is bigger than a parasang.** `race.track_scale` is 4 in tuning.json (on top of the
  generator's STRETCH already in tracks.json), so Joppa's canvas is 26,064 x 17,376 px: about
  two parasangs wide and four tall. `qud_world.COURSE_ANCHORS` puts each course's canvas
  origin on a zone; Joppa's at `JoppaWorld.10.21.2.0.10` lands the village inside the loop.
- **Painted ground is a Cell field** (`PaintTile` and kin), readable under an occupied cell;
  the snapshot path (`Cell.Render`) only answers on an empty one. A Joppa zone: 222 distinct
  objects, 989 standing, 227 wall cells, 21 torchposts (light radius 6).
- **Every object in the region resolves** (261,131 of 261,131): 1,044 painted billboard /
  floor tiles, a 46-cell ground atlas. Qud's colour letters are case-sensitive (`y` / `Y`)
  and Windows file names are not; the art names spell the case out.
- **The Store Python virtualises AppData.** The extract "succeeded" into a sandbox Godot
  could not see. `CAVES2_ASSETS` names a store outside AppData (CLAUDE.md, PC paths).
- **Paving clears more than solids.** The first race had watervine standing on the road:
  the road takes everything but floors and water, the verge takes walls and solids.
- The streaming self-check (`--stream_test`) walks the route: 9 chunks max of cap 9, and an
  AI race on Joppa's marsh renders at the 60 fps cap with chunks loading one a frame.
- **The crossing is slow because the marsh is off-road.** The player alone, steered three
  zones east and back (`--free_test=3`): a leg takes ~50 s of wall time at timescale 3,
  static memory sits at 65 MB the whole way (39 loads, 30 unloads, delta 0). With the AI
  field still racing the loop the loaded set is the UNION of every kart's window (20 chunks
  seen), so the crossing runs the player alone and the cap is one window.
- **A dusk race re-bakes every 12 s.** At an hour of Qud a minute (`seg_per_s` 8.33) and a
  0.1 daylight step, a race started at 19:24 has keys at 0, 12 and 24 s; a noon race has
  one. Each bake is one MIX-black mesh per chunk plus the billboard instance colours; walls
  keep their own vertex colours for now (Deferred).
- **The second lap's fixes (09-16).** Qud's painted grass is vegetation, not floor: it stands
  up as billboards by Raves' `UPRIGHT_GROUND` rule (a vegetation word in the tile name, or a
  tile under Creatures/), so the floor atlas is four dirt tiles and the grass is ~500 sprites a
  zone. Qud's light-occluders (`Render Occluding="true"`: trees, brinestalk, sunflowers,
  statues) stand at 2x. Standing sprites use `overland_billboard.gdshader` (fixed-Y billboard,
  the bake's instance tint, darker with distance: tuning `dark_near_m` / `dark_far_m` /
  `dark_min`). The ambient fauna is the region's own: the export counts the creatures the
  bake found (828 giant dragonflies, 355 snapjaw scavengers round Joppa) and the race spawns
  the commonest flyer and the commonest roaming walker (rooted and aquatic things excluded).
- **A chunk load must not cost a frame.** With the grass standing, a chunk's build (floor
  mesh, walls, ~1,000 sprites, the dark mesh at night) plus a route scan per sprite for the
  paving dropped the free-drive crossing to 43-47 fps. Two fixes: the paved cells are computed
  once at setup (a disc per route sample into two dictionaries, road and verge) so paving is
  a lookup; and a chunk builds in four steps, one a frame (`_run_steps`), all at once only at
  setup. Steady 60 fps in every G9 scene since.
- **GDScript infers nothing from an untyped value** (`var d := nearest(c, -1).dist`, or a
  field of an untyped loop variable): the script fails to compile and Race.gd with it, so the
  run never quits and every probe times out. Type such locals; the score's "timeout" is
  the symptom.

## The shape

```
Qud (running, Raves bridge mod)          2Caves2Qud tools (Python)              2Caves2Qud (Godot)
  bake: ZoneManager.GetZone(id)  --->  chunks/<seed>/<zone>.json  --->  qud_world.py: resolve art,  --->  QudWorld.gd: stream chunks
  compact per-cell record               (~30 KB, one per zone)          pave the course, write         around the karts, build floor /
                                                                        <store>/godot/world/<seed>/    walls / billboards / water,
  QudWorldMap.rpm (static)  --->  overworld.json (biome per parasang)   the road ribbon on top, bake light
```

Chunk = zone. A chunk file is the compact bake: the zone id, a palette of distinct objects
(name, tile, colours, wall / solid / liquid flags), the 2000 ground palette indices, the standing
objects as `[x, y, palette]`, and the 2000 light bytes. The exporter turns that into what Godot
draws (the palette resolved to `dressing/` art, wall families, unit strips), so Godot never
reads a blueprint.

A course is paved by anchoring its control loop at a parasang: the canvas origin lands on the
parasang's first zone, the road ribbon is built exactly as today, and the cells under the road
(plus a verge) are cleared of walls and props in the chunk overlay. Flat first: `elevation` is
0 and the profile / camber / steps stay off until terrain (Deferred).

Lighting: Qud's per-cell `light` is a static map per zone (torches, glowpads) plus daylight
that is a pure function of the clock. So darkness = f(chunk light map, clock), a vertex-colour
mesh per chunk exactly as Raves does it. **Race mode bakes once at the start** for the race
clock (and again only at keyframes if the race crosses dusk), **free drive rebakes on a slow
cadence**. The answer to "not for 4-8 players?": the bake is cheap (2000 quads per chunk, well
under a millisecond), and what multiplayer actually needs is that everyone computes the same
light, which holds because the inputs are the static map and the shared race clock. Sun
shadows stay real-time (a `DirectionalLight3D` whose angle is the same clock function on every
machine, no sync). What must not go live is per-kart light that rebuilds meshes; headlights are
additive billboards, as Raves draws torches.

## The scoreboard

`tools/overland_score.py` runs every check below and writes `reports/overland-score.md`.
Each goal is Specific (the check), Measurable (the number), Achievable (built on existing
code), Relevant (the demo: a race on the real Joppa surface, then a drive to the next race),
Time-bound (the date column). Points only land when the check runs green from a clean
checkout; a check that cannot fail earns nothing.

| # | goal | check | pts | by |
|---|------|-------|-----|----|
| G1 | Overworld parsed | `qud_world.overworld()` maps all 2000 parasang cells to a terrain name and a course tileset; the unit test enumerates every terrain kind in the map and asserts none is unmapped | 5 | 09-15 |
| G2 | Zone bake | Raves mod `bake` command builds zones by id on the main thread and writes compact chunks; `tools/capture/bake.py` paces a 3 x 3 parasang region round Joppa (81 zones) by confirmation, not timers; chunk <= 80 KB, 2000 cells each, region in <= 10 min, a report with per-zone seconds | 15 | 09-16 |
| G3 | Chunk to art | `qud_world.resolve()` on the Joppa region: >= 97 % of palette entries resolve to a wall family, dressing PNG, unit strip or water; the remainder listed by name in the report | 10 | 09-16 |
| G4 | Paving | `qud_world.pave(course, anchor)`: road cells lie within half-width of the route, no wall or solid object remains within width/2 + verge of the road, output is byte-identical across runs | 10 | 09-15 |
| G5 | Chunk streaming | `QudWorld.gd` headless test: for kart positions along a path, every chunk within radius R is loaded, none beyond R + 1, loads and unloads counted in the `overland:` probe line | 15 | 09-17 |
| G6 | A race on the surface | `--overland=11.22 --track=joppa --auto` finishes 3 laps; graybox offroad % within 5 points of the canvas course, 0 drops, 0 voids; render >= 55 fps windowed | 15 | 09-18 |
| G7 | Free drive across zones | `--free_test=3`: the player alone, steered 3 zones east and back, repeating, for 150 s; at least two legs done, loaded chunks never exceed (2R+1)^2, static memory delta over the last minute < 50 MB (`overland_free:` verdict) | 10 | 09-18 |
| G8 | Light bake | `light:` summary: a noon race bakes once (1 key); a race started at 19:24 bakes at every keyframe and no more; free drive rebakes on the 60 s cadence (2 bakes in 80 s); on screen (G9's run) noon minus night luminance > 0.15 | 10 | 09-19 |
| G9 | On-screen regression | windowed screenshots for {noon, night} x {race, free drive} compared with goldens in `reports/overland/golden/` (average-hash distance <= 6), fps >= 55 in the `race:` line; runs from `tools/overland_score.py --screen` | 10 | 09-19 |

70 is demo-able (a race on the real surface); 100 closes the milestone. Anything scored is
re-run by the score script, so a goal cannot silently regress to "done".

Test discipline (Daniel's): TDD, Python first for every algorithm (pytest under
`tools/tests/`), Godot logic under `godot/tests/` as headless `SceneTree` scripts (the Raves
convention), and the final round on screen: windowed runs with screenshots, compared with
goldens. Headless catches logic; only a window catches an escape.

## Plan of work

1. **G1 + G4 in Python** (no game needed): `tools/qud_world.py` with the overworld parser, the
   chunk model, and `pave()`. Tests first. The chunk model is tested on synthetic chunks and on
   the three surface zones Raves already saved on this PC (converted to the compact format).
2. **G2, the bake**: branch `dd/pc-world-bake` off `origin/main` in raves-of-qud, `BakeExporter.cs`
   (the `bake` command, main thread, `ZoneManager.GetZone`, the compact writer, the zone
   released after writing), `tools/capture/bake.py` (confirmation-paced, report). Deploy, restart
   Qud, bake the Joppa region. World seed is the game's; the region is `--center 11.22 --radius 1`.
3. **G3 export**: `tools/export_godot_assets.py` gains a `world` step: chunks resolved to art
   and written to `<store>/godot/world/<seed>/`.
4. **G5 + G6 in Godot**: `QudWorld.gd` (extends Track: flat ground, chunk streaming, the road
   built from the anchored course, `resolve()` against wall cells), Race `--overland=`, the
   probe lines, the headless streaming test, then the AI race.
5. **G7 + G8** (built 09-15): `--free_test` in Race, `godot/OverlandLight.gd` + the bake in
   QudWorld, `--clock=<segment>` to start a race at any hour.
6. **G9**: goldens, the on-screen regression run, the score script's `--screen` pass.
7. Then: drive to the next race (a second course anchored two parasangs away and a paved road
   between them on the overworld), which is the start of the next milestone, not this one.

## Decisions

- **Chunk = zone (80 x 25 cells, 60 px per cell).** One file per zone, zone ids as Qud names
  them, so a chunk is the same thing in Raves, the bake and the racer. Alternative: square
  chunks re-tiled from zones; rejected, it costs a re-index for nothing yet.
- **The bake runs inside Qud, through the Raves bridge.** Alternative: re-implement Qud's
  worldgen; rejected outright. Alternative: warp the player zone by zone (`zonetp`); rejected
  for the bake since it autosaves and moves the player, but kept as the fallback if
  `GetZone` on an unvisited zone misbehaves.
- **Compact chunk format, not the WorldStore record.** 800 KB x 18,000 zones is 14 GB; the
  palette form is ~30 KB. Raves can still read it back later (a converter is trivial).
- **Flat first.** Elevation, camber, steps and the ground noise are off in overland until the
  bake carries height (Qud has none on the surface; terrain will be ours, from the overworld
  terrain kind).
- **Light is baked from Qud's own map plus a clock, in both modes.** See the shape section.

## Deferred

- The light bake dims the ground, the road, the billboards and the sky; voxel walls, creature
  sprites and the racers keep their colours, and creature sprites do not darken with distance. Qud's real dawn/dusk curve (read `time` off the
  bridge) in place of the two-hour ramps.
- Floating origin for the full 57 km map (needed before "drive anywhere"; not for one region).
- Terrain from the overworld kind (hills, mountains, canyon walls).
- Strata (underground races), the world map view, the race-to-race road network.
- The whole-surface bake (18,000 zones, hours): run overnight once the region bake is proven.
