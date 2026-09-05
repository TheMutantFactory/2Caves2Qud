# The courses

The Track Design Bible (`mutant-plan/strategy/2caves2qud-tracks/`) describes twenty courses in
five cups. `tools/qud_tracks.py` carries them as engine data and writes `shared/tracks.json`;
edit the script, not the JSON. Each course is:

- a control-point loop drawn from the bible's Route paragraph (the engine drapes a Catmull-Rom
  road over rolling ground; `elevation` is the course's own amplitude, so Chavvah climbs and
  Joppa barely rolls);
- a Qud biome for the road (`tileset`), the ground (`offroad`) and the walls (`wallset`), which
  `tools/export_godot_assets.py` turns into Qud floor tiles painted in the course's palette and
  a voxel wall family (brinestalk huts in Joppa, chrome in Grit Gate, bone in the Tomb);
- the course's surface hazards as fixed patches at fractions of the loop: `ice` slides, `fire`
  and `poison` hurt, `water`, `oil` and `slime` slow, warm `static` stuns (`Race._spawn_track_hazards`);
- laps (five for the Hydropon sprint), the Qud items that appear on the road as scrolls, and
  the roster metadata the Courses page shows: cup, difficulty, format, target lap, signature
  skill, racing sentence, spoiler flag.

The Grand Prix runs the cups in order: level N is the Nth course (`Shared.track_for_level`).
Single Race and Local Multiplayer pick from the Courses page.

| # | course | cup | biome | surface |
|---|---|---|---|---|
| 01 | Joppa Waterwheel Run | Fresh Water | watervine / salt / brinestalk | pond water |
| 02 | Red Rock Ramble | Fresh Water | canyon / desert / rock | river water |
| 03 | Rust Wells Spiral | Fresh Water | rust / chrome / metal | qudzu slime |
| 04 | Six Day Stilt Pilgrimage | Fresh Water | salt / dune / marble | clean |
| 05 | Grit Gate Grand Prix | Chrome | chrome / ruin / metal | force barriers (static) |
| 06 | Asphalt Mines Slick | Chrome | asphalt / bone / rock | oil, lava fire |
| 07 | Golgotha Drop | Chrome | rust / bile / metal | gas, refuse slime |
| 08 | Bethesda Susa Deep Freeze | Chrome | marble / jungle / marble | wet stone then ice |
| 09 | Kyakukya Cap Circuit | Canopy | mushroom / jungle / mushroom | pool water |
| 10 | Rainbow Wood Soupway | Canopy | fungus / soup / mushroom | soup slime |
| 11 | Chavvah Canopy Climb | Canopy | crystal / leaf / crystal | clean, steep |
| 12 | Eyn Roj Dreamroot | Canopy | marble / crystal / crystal | psychic static |
| 13 | Lake Hinnom Causeway | Reef | esh / water / coolant | open water |
| 14 | Palladium Reef Polyp Maze | Reef | chrome / reef / coolant | plasma static, water |
| 15 | Yd Freehold Pipeworks | Reef | pipe / sponge / metal | oil, fire |
| 16 | Moon Stair Static Circuit | Reef | black marble / crystal / crystal | warm static |
| 17 | The Hydropon Bloom | Spindle | lily / water / marble | water, 5 laps |
| 18 | Omonporch Twin Gates | Spindle | sultan / banana / sultan columns | magnetic static |
| 19 | Tomb of the Eaters Bell Run | Spindle | bone / black marble / bone | crematory fire, gas |
| 20 | Thin World Crossing | Spindle | hologram / void / filigree | holographic static |

## What the bible asks for that the engine cannot build yet

Recorded per course as `gaps` in `tools/qud_tracks.py`, so nothing is lost when a design is cut
to data. The big ones:

- **Section races.** Golgotha, Bethesda Susa, Eyn Roj and the Tomb are one-way descents or
  ascents; the engine only knows loops, so they run as three-lap circuits of their shape.
- **Timed and moving hazards**: the waterwheel gate, force-barrier cycles, vent cycles, clam
  jump pads, the Bell clock, baboon throws, market traffic.
- **Vertical transfers and jumps**: branch hops, leaf ramps, the magnetic wall, shaft drops.
- **Lap-by-lap development**: growing lilies, oil ribbons, leaning trees, announced rule
  changes, the thinning road. Hazards are fixed for the race today.
- **Parallel routes**: Yd Freehold's rooms, Grit Gate's corridor vs tunnel, the Thin World's
  twin portals. Each course is one line.
- **Ghost echoes**, psychic overlays, occlusion struts.

The next engine features that would unlock the most courses are, in order: a `hazards` entry
that cycles (on/off with a period and a cue), a jump-pad patch kind, and per-lap hazard sets.
