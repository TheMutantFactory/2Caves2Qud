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

## Cycling hazards and jump pads

A hazard entry with `period` cycles: live for `duty` of every `period` seconds, offset by
`phase`, faint while dormant and pulsing amber for the second before it goes live (the
bible's "amber tells the player to prepare"). A `barrier` stuns and hurts (Grit Gate's force
barriers, Yd Freehold's workshop arms, the Tomb's crematory), a `wheel` spins the kart
(Joppa's waterwheel gate), a `cart` slows and jolts (Stilt market lanes), a `bell` is a wide
stun pulse (the Tomb), and the surface kinds cycle too (Golgotha's vents, Bethesda's cryo
chambers, Rainbow Wood's sludges, the Asphalt Mines' fire snouts, Palladium's plasma jellies).

A `jump` pad lofts any kart that crosses it while live: a hop of under a second with a boost,
drawn on an arc with the shadow shrinking, during which nothing below slows the kart, so a pad
carries over water or a gap. Chavvah's leaf ramps, Red Rock's arch, Golgotha's shaft drops,
Eyn Roj's boost roots and the Moon Stair's pads are always live; Kyakukya's caps beat on a
two-second cycle, Lake Hinnom's clams and the Hydropon's foam pads cycle, and Omonporch's
magnetic wall pulses. `--hazard-log` prints every switch and every jump.

## Lap development

A hazard's `laps` list says which laps it is live on, and `per_lap` overrides its period,
duty or phase on a given lap. The lap is the race leader's, so the course changes for
everyone at once, and a hazard that is not yet live is drawn faint from the start: the
bible's "persistent changes are visibly previewed". Each course's `lap_notes` show on the
HUD as the leader starts the lap ("the waterwheel turns faster", "the middle cap falls off
the beat", "a sunslag polyp glows gold"). Joppa's wheel speeds up and opens a gap on lap 3,
Red Rock's baboons aim outside, then at the lane, then alternate, the Stilt's carts fill one
aisle then the other, Grit Gate's third gate comes online on lap 2 and its cycle inverts on
lap 3, the Asphalt Mines leak one oil ribbon then two, Rainbow Wood adds a weep per lap,
Lake Hinnom's current reverses, the Moon Stair's pads exist only from lap 2 (Stable, then
Elastic), the Hydropon's centre leaves span on lap 3, and the Thin World's void shows through
more each lap. `--hazard-log` prints `lap N: hazard set k / n live` at every change.

## Parallel routes

A course's `branches` are second roads: each leaves the loop at one fraction and rejoins at
another through control points placed on the chord between those two points, pushed toward
the loop's centroid for an inside cut or away for an outer detour (`tools/qud_tracks.py`
`branch()` / `place_branch()`). The bible's route language is on the curbs: a `safe` route is
wider with grey curbs, an `expert` route narrower with luminous cyan curbs. A branch carries
its own hazards at fractions of its length (with cycles and lap gates like the loop's) and a
double set of items halfway along, the premium pickups the bible puts on the slower line.

In the engine a branch counts as road, a kart on it keeps its loop progress through the
branch sample's equivalent loop index (so laps and positions stay right), and AI karts
decide at the fork with the branch's `ai_take` chance and aim along it (`Track.aim`,
`choose_branch`). The minimap draws branches in their route colour. `--hazard-log` prints
`branch: <kart> takes <route>`.

| course | route | kind | what it is |
|---|---|---|---|
| Joppa | pond cut | expert | shorter, through two water patches |
| Red Rock | cavern bridge | safe | the wide outer bridge |
| Rust Wells | wire bridge | expert | a jump across the gap |
| Six Day Stilt | left aisle, right aisle | safe | the three bazaar aisles; carts fill one per lap |
| Grit Gate | service tunnel | safe | around the force barriers |
| Asphalt Mines | dry outer bend | safe | around the oil |
| Golgotha | second chute | expert | a vent of its own |
| Bethesda Susa | chrome elevator | expert | a jump past the switchbacks |
| Kyakukya | root ramp | safe | around the pool |
| Chavvah | slender branches | expert | two hops between limbs |
| Lake Hinnom | water line | expert | shorter, slower |
| Palladium Reef | inner chute | expert | its jump opens on lap 2 |
| Yd Freehold | red workshop, violet salon | expert, safe | two of the three rooms; the loop is the market |
| Moon Stair | shortcut crystals | expert | warm static on the way |
| Hydropon | centre leaves | expert | water until lap 3, then a pad |
| Omonporch | high line | expert | the magnetic release |
| Tomb | recovery corridor | safe | around the crematory |
| Thin World | Recoming portal | safe | the twin of the Crossing |

## Section races

A course with `sections` is one way: an open road from the grid to a finish line at its far
end, with a lead-in behind the first point so the grid stands on road. There are no laps;
the HUD counts sections, the far end finishes the kart, and the development machinery
(`laps=[2]`, `per_lap`, the notes) runs per section, so "Section 2 rides the belts"
and "Section 3 enters the cryobarrios" are data. Golgotha Drop, Bethesda Susa Deep Freeze,
Eyn Roj Dreamroot and the Tomb of the Eaters Bell Run are section races; their branches
and hazards sit at fractions of the path like everywhere else.

## Lap-changing geometry

Two things change the road itself between laps. A **branch with `laps`** exists only on those
laps: before, it is drawn as a translucent ghost road with no curbs (the preview), it is not
road, its hazards sleep and the AI ignores it; on its lap it becomes a route. The Hydropon's
centre leaves grow in on lap 3, Palladium's inner chute opens on lap 2, Yd Freehold's
surface bypass lights on lap 3, and Rust Wells' outer bypass appears when the bridge goes.
A **road stretch with `road_states`** is built as its own piece of road so it can change
state on a lap: `hologram` is translucent cyan and still road (the Thin World thins on lap 2
and more on lap 3; a Moon Stair platform), `cracked` is the amber preview of a break (Rust
Wells lap 1), and `gap` is no road at all (Rust Wells laps 2 and 3: a bridge panel is gone,
the curbs remain as the edge). AI karts take a `bypass` branch nine times in ten while its
stretch is a gap; a jump pad on lap 3 launches the brave across. `--hazard-log` prints
`lap N: road a-b <state>` and `lap N: branch <name> live|dormant`.

## Moving hazards and throwers

A course's `movers` are patches that travel a path authored as loop-fraction and lateral
pairs, back and forth or around, in a set period; the path is drawn on the road as an amber
sweep marking, the bible's cue. The Stilt's pack animals and handcarts cross one aisle on lap
2 and the other on lap 3, Rainbow Wood's three sludges sway across their river crossings (one
per lap joining), Palladium's plasma jellies vent across a lane, the Tomb's crematory arm and
fan sweep the road, a drillbot works the Asphalt Mines' wall, a reef current crosses Lake
Hinnom's causeway, and small fauna cross Golgotha's chute. A mover takes any hazard kind, so
it stuns, slows or hurts like the patch it is.

`throwers` land a stone on the road every period: a dark shadow marks the target for a
second first (the bible's "circular shadows for a full second"), a throw sound warns, then
the stone hits everyone in its radius with damage and a stun. Red Rock's baboons aim outside
on lap 1, at the racing lane on lap 2 and alternate on lap 3; a mushroom cap falls on
Kyakukya's last straight. `--hazard-log` prints `stone: <name> throws, lands t=` and
`stone: <name> lands t= hits=N`.

## Authored elevation

A course's `profile` is a list of height keypoints along the route: the road follows them
(smoothly, wrapping on a loop, open on a section race), and the ground shelves with it, full
height within one and a half road widths and fading to the terrain noise by four. Red Rock
drops 320 px into its canyon and climbs the switchbacks out, the Asphalt Mines descend to
the lava gallery and climb home, Golgotha and Bethesda Susa fall all the way to their
finishes, the Tomb rises 600 px to the Spindle opening, Chavvah climbs twice around the trunk
and dives, the Moon Stair climbs its switchback and Omonporch's magnetic wall rises 340 px in
a tenth of a lap. Slopes matter: the kart's top speed and acceleration follow the grade
under it, so a descent runs away and a climb is earned. `--hazard-log`'s player line carries
`h=` and `grade=`.

## What the bible asks for that the engine cannot build yet

Recorded per course as `gaps` in `tools/qud_tracks.py`, so nothing is lost when a design is cut
to data. The big ones:

- **Steps and shafts.** Elevation is a smooth profile; Golgotha's shaft drops and the
  Tomb's stairwell are slopes, not falls.
- **Movers that change the map**: the drillbot's holes in the wall, a collapsing conveyor;
  a mover sweeps, it does not cut.
- **Vertical transfers with real height**: a jump is a hop with a boost, not a change of
  level; the branch-to-branch transfers and the shaft drops stay on one road.
- **Camber and lean** (Chavvah's tilting tree, Moon Stair's rule changes beyond the pads):
  the road's shape never changes, only whether a stretch or a branch is road.
- **A third room** (Yd Freehold has two branches and the loop; the bible has three rooms
  plus a lap-3 bypass) and routes that split more than once.
- **Ghost echoes**, psychic overlays, occlusion struts.

The next engine features that would unlock the most courses are, in order: camber, the
leaning tree, and steps.
