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

## Camber and the leaning tree

A course's `camber` banks its corners: the road's outer edge rises by the camber scaled by
the local curvature (smoothed over the corner), the inner edge drops, and the banking fades
out just past the curbs so the ground meets it. The kart gets a little more grip on a
banked stretch, so a good line through Joppa's sweeper or Omonporch's court is held rather
than fought. Ten courses have camber, Omonporch the most.

Chavvah's `lean` tilts the whole course by lap: level on lap 1, toward the branch transfer
on lap 2, back toward the terrace on lap 3. The tilt animates over three seconds so the
sway is the preview, the built course rotates about its centre as one piece, and karts,
hazards and pickups follow because every height comes from the same function. The grade
under the kart includes the lean, so the fast line really does change with it.

## Steps and shafts

A profile keypoint marked `step` is a ledge: the height holds until that point and jumps
there, the road is cut so no strip hangs down the face, and the ground shelf forms the shaft
wall. A kart carries its absolute height from step to step, so when the road under it drops
away it keeps its height and falls under gravity with a third of its steering (the bible's
"controlled shaft drop with an aerial steering choice"), landing with a thud and a puff.
A small riser works the other way: the kart pops up it, which is a stair. Golgotha's two
shaft drops are real drops now (its jump pads there are gone), Eyn Roj dives through the
hole between the mirrored leaves, Red Rock drops through the cracked opening, and the Thin
World's unsupported stair climbs three risers. `--hazard-log` prints `drop: <kart> fell N px`.

## Map-cutting movers and the void

A mover with `cuts_walls` bores through a run of wall blocks laid along its path from the
curb outward (the rock is authored, random scenery rarely sits on a path), freeing each
block with a puff as its first pass reaches it, and one with `opens` unseals the branch it
bores toward when it reaches the end: the Asphalt Mines' drillbot works its way through the wall and opens the
drill cut, an expert shortcut that did not exist when the race began (the HUD says so).

The void is where falling cannot end the race but costs the line: a kart in a gap or void
stretch, or off a floating course past its margin (`void_offroad`: the Thin World floats
over the void, Chavvah's deep sky catches a fall on a lower leaf), sinks for a second and is
returned to the road just past where it fell, slow and facing forward, with a translocation.
Rust Wells' collapsed bridge is a fall now, not a drive across the ground.

## The psychic overlays and the ghost echoes

Eyn Roj's perception course, from its Route: three authored forms that alter what is seen
and never what is driven, arriving by section and vanishing at the chiming rock. The spec
is `psychic` on the course: forms per section, an `envelope` in px and a `beat` in Hz.

- **Doubled edges** (section 1 on): a second, translucent magenta edge beyond the real curb,
  built in short chunks so each fades on its own.
- **False silhouettes** (section 2 on): racers that are not there, Qud creatures standing
  well off the road in magenta, breathing through their idle frames.
- **Ghost echoes** (section 3): each racer's delayed image, its own sprite in magenta drawn
  where it was a second ago (a ring of positions in `Race._psychic_step`).
- **Nothing inside the envelope.** Every overlay fades to nothing within five kart lengths
  of a kart, and a ghost is never drawn inside a human's envelope.
- **Rhythm rocks.** Studs along the true edge (one multimesh) pulse on the beat and sit
  brighter where a real turn is ahead: the one thing that is always trustworthy.

- **Rhythm-rock haptics** (`Race._haptics`). On each beat of the course a human whose road
  turns by more than 25° over the next 1200 px (about 1.4 s at pace, `Track.bend_ahead`)
  gets a short rumble on the pad that drives that seat, harder for a sharper bend (the solo
  wizard: the first pad connected). Nothing on a straight, nothing on another course;
  `race.haptics` turns it off. The studs' emphasis uses the same rule, so the pad and the
  bright studs ahead agree: a first cut measured six waypoints ahead, which on the
  stretched loop is a few hundred px, and rumbled twice in a whole run.

`--psychic-log` prints `psychic: section=N forms=[...] edges=k/K faded=F sils=s/S ghosts=G
pulse=` every five seconds and on each section change; `psychic: none on <key>` on a course
without overlays. `--haptics-log` prints `haptic: <kart> pad=N bend=deg strength=x wp=`
per rumble (`pad=-1` in a headless run, which has no pads: the intent is logged, the call
skipped) and `haptic: none on <key>` elsewhere.

- **The echo roots** (the skill route: follow a briefly solidified echo across two root
  gaps). Two expert branches across the helix carry `echo` (period, duty, phase): the
  branch is road only while solid, half of every four seconds on the beat, its landing
  flashing gold in time with the rhythm rock; faded, it is drawn as a magenta echo, seen
  and not road, and a kart on it falls (`Track.void_here`) and is returned to the main
  helix below rather than reset. The main road is solid whatever the echo does: the mouth
  and the landing overlap it, so a kart is only falling once it has left the road
  (`_main_dist`). The AI commits at the fork only while the echo is solid and may still be
  caught by the fade. `--hazard-log` prints `echo: <root> solid|fades` on each transition,
  `branch: <kart> takes echo root N`, `echo: <kart> missed <root>` before its `void:` fall
  and return. In the check: 37 takes, 8 misses, every miss returned to the helix.
  Eyn Roj's course file is complete.

## The occlusion struts

Palladium's sightline course, from its Route: struts that occlude vision without blocking
movement, authored so the apex behind each is hidden only after the edge has announced the
turn. The spec is `struts` (each `at`, `side` in half-widths, `span`, `angle`, `height`) and
`strut_strips` (loop ranges with a colour).

- **Struts** (`Track._build_struts`): tall translucent silver panels standing across part of
  the road, six through the trellis a little before each bend and three widely spaced cover
  struts on the final deck. A kart drives through them. Within a couple of kart lengths of
  a human a strut goes nearly clear, so the road is always locally readable.
- **Luminous edge strips**: emissive lines along both curbs through the occluded sectors,
  silver outbound and gold on the return, drawn with no depth test so they show through
  the struts and establish every turn before the strut hides it.

`--strut-log` prints the build (`struts: 9 panels, 4 edge strips`) and, every five
seconds, `struts: total=N clear=k clear_frames=F`: the clear-frame count grows as the
field passes through the trellis (0 → 349 over the first lap in the check), `struts: none
on <key>` on a course without them. Screenshots at 16 s and 24 s show a panel across the
road ahead with the field half-seen behind it and the silver strip along the curb.
What is left of the course file: the plasma jellies' venting and the sunslag polyps.

## The plasma jellies

Palladium's lane hazard, from its file: plasma jellies charge with a bright swelling
animation before venting across one lane. A course hazard of kind `jelly` (`at`, `side`
beyond ±1 so it sits just off a curb, `radius`, `period`, `duty`, `phase`) expands in
`Track.hazard_spots` into the emitter and three `plasma` patches from that curb to the
road's centre that share its cycle, so the far lane is always open. `Race._update_jelly`
is the telegraph: for the two seconds before a vent the Plasma Jelly sprite (Qud's own)
swells to 1.6× and brightens to plasma blue with a sound; while venting it throbs and the
patches are live (3 damage, a 0.6 s stun, Lightning); then it subsides. Palladium carries
two, at 0.30 on the left and 0.55 on the right, on a six-second cycle offset by three, in
place of the sweeping static patches they replace.

Probe: `--hazard-log` prints `jelly: N charging t=` two seconds before each `jelly: N
vents t=` (and the three `hazard: plasma on/off` lines of its patches), and over three laps
the wizard takes `hit: hazard 3.0` from a vent. Screenshots around the first jelly show
the trellis strut before it hiding the lane, which is the course working as designed, so
the log is the proof here. What is left of the course file: the sunslag polyps.

## The sunslag polyps

Palladium's skill route, from its file: pluck three soft polyps on a tight inside
sequence; one reveals a fixed sunslag boost each lap, the others ordinary boost charge,
and lap 3 lights the correct one with a faint golden pulse on approach. The spec is
`polyps` (`at`, `side`) and `sunslag` (which of them hides the bulb, fixed for competitive
play). `Race._spawn_polyps` grows a coral polyp (Qud's coral ball, exported as the `polyp`
icon) at each; driving within a kart's reach plucks it with a burst of green: the sunslag
one gives a 0.6 boost for 2.5 s and pops Qud's sunslag bulb up out of the spot for a
moment (the reveal), the others give two coins of boost charge. Plucked polyps stay gone
until the leader's next lap regrows them, and from lap 3 the sunslag polyp pulses gold.
Palladium's three sit on the inside of the market shelf's bend at 0.44–0.48, the second
the sunslag.

Probe: `--hazard-log` prints `polyp: 3 grown, sunslag is 1`, `polyp: <kart> plucks N
charge|sunslag`, `polyp: regrow lap L` and `regrow lap 3  sunslag glows gold`. Over three
laps the first kart through plucked all three each lap (the same racer twice), the sunslag
among them. Palladium's course file is complete.

## The Bell and the checker sanctuaries

The Tomb of the Eaters' timed-route system, from its file: the Bell rings on an authored
sector clock shown by a large circular HUD ring and escalating chimes; a racer exposed at
zero is displaced sideways into the recovery corridor, losing about 1.25 s and never moved
backward; checker sanctuaries pulse and confer clear tethered feedback. The spec is `bell`
(`period`, `displace`, `radius`, `sanctuaries` as loop fractions).

- **Sanctuaries** (`Track._build_bell`): a road-wide gold-and-black checker pad at each
  fraction, eighteen of them about ten seconds of road apart so the main line meets one
  before every pulse, and one in the middle of every branch: the crypts, where a racer
  tethers early for the price of a few bends. They pulse, faster over the last three
  seconds before the ring.
- **The tether** (`Race._update_bell`): touching a pad tethers the racer until the next
  ring, with a gold burst and, for the wizard, a chime and `TETHERED` on the HUD.
- **The ring**: every `period` seconds, after three escalating chimes. Every tethered racer
  is released; every exposed one is stunned for `displace` seconds and shoved sideways
  toward the nearer edge, never backward, with `THE BELL: EXPOSED` for the wizard.
- **The HUD ring**: a circular sector clock top-centre, gold while tethered, ember while
  exposed and whitening as the ring nears, with `EXPOSED`, `THE BELL IN N` or `TETHERED`
  under it.

Probe: `--hazard-log` prints `bell: 19 sanctuaries, period 12 s` (18 on the route, one in the recovery corridor), `bell: <kart> tethers at
<idx>`, and `bell: rings N t= tethered=k displaced=[...]` on every ring. In the check the
Bell rang every twelve seconds; most of the field was tethered at each ring and the
exposed were displaced (the start pack at the first ring, and racers caught between pads
later). What is left of the course file: the crematory sequence and the stairwell
teleporter.

## The crematory sector and the stairwell teleporter

The last of the Tomb's file. **The stairwell teleporter** (hazard kind `teleport` with a
`target` fraction): a cyan pad on the main line at 0.30 that sends every kart crossing it
to the access corridor at 0.34, facing forward at its speed, with a translocation at both
ends and a two-second cooldown; the exit is marked by a second pad. **The crematory
sector** teaches each hazard alone and then all at once, with a lane always open:

- **The press** (kind `press`): a stone block hanging above one lane that slams down on its
  cycle, stunning and hurting what is under it; its cue is its shadow, which darkens on the
  lane over the second before the slam as the block descends.
- **The arm** (mover kind `arm`): the crematory arm sweeping across the road, a barrier on
  the move; its cue is the dark sweep mark along its path.
- **The vent** (kind `vent`): a flare of fire on one lane; its cue is the amber glow every
  cycling patch shows the second before it goes live.
- **The fan** (mover kind `fan`): sweeping across the road, it blows a kart sideways along
  its motion rather than hurting it; its cue is the pale streamers along its path, which
  wave while it blows.

Taught alone at 0.38, 0.43, 0.48 and 0.53, then combined at 0.58–0.63 with press and vent
on opposite lanes out of phase and the arm and fan sweeping from opposite ends. The old
stand-ins (barrier patches and a giant bell patch) are gone.

Probe: `--hazard-log` prints `teleport: <kart> -> <exit>`, `fan: blows <kart>`, the
`hazard: press|vent on/off` cycles and the wizard's `hit: hazard` lines. In the check all
eight karts teleported, all eight were blown, the presses and vents cycled through the run
and the wizard was pressed once. The Tomb's course file is complete, and with it every
course file in the bible.

## What the bible asks for that the engine cannot build yet

Nothing on the bible's list is left as a rule the engine cannot express. The graybox pass
(docs/graybox.md) measured the AI field on every course and stretched the loops to the
bible's lap times; the AI field's damage and the lap rule are balanced (docs/balance.md).
The section races were re-routed as three regions each and run to their targets, and Eyn
Roj has its psychic overlays and ghost echoes, Palladium its occlusion struts, its venting
plasma jellies and its sunslag polyps, the rhythm rocks reach the pad, and the Tomb has its
Bell and sanctuaries, its crematory sector and its stairwell teleporter. Every course file
in the bible is built; what remains is playing it.
