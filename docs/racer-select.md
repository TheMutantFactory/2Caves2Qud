# Racer select

`godot/RacerSelect.gd` implements the large-roster design
(`mutant-plan/strategy/2caves2qud-large-roster-character-select.md`): 908 racers is far too
many for one shared grid, so the shared centre shows a small stable set of collections and
each seat browses privately in its own quadrant.

**Catalogue.** `tools/qud_racers.py` writes `data/racers.json`: every creature the exporter
made a racer of, its numbered blueprint siblings folded in as variants (Snapjaw Scavenger 1 /
2 / 3), the 24 castes as their own collection, families from the blueprint's inheritance
chain and Species/Class/Role tags, and the engine's speed/weight reading of its hit points and
flight as a one-line driving class. Order inside a collection is alphabetical and stable.

| collection | racers | rule |
|---|---|---|
| Favorites, Recently Used, All Racers, Random | utility | the screen's own; per seat, saved to `user://racers.cfg` |
| Castes | 24 | the player callings; cast from the action bar |
| Legendary | 16 | blueprint Role = Leader |
| Villagers | 192 | humanoid, species human |
| Snapjaws & Kin | 136 | other humanoids |
| Robots | 88 | the Robot chain, turrets, mecha |
| Bugs & Oozes | 101 | insect, spider, worm, ooze classes |
| Beasts & Birds | 205 | the Animal chain |
| Plants & Fungi | 106 | the plant and fungus chains |
| Cherubim | 33 | cherubim, nephilim, godlings, baetyls |
| Crystals | 7 | crystal chimes and golems |

**Flow per seat.** `PRESS A TO JOIN` → `CHOOSING` (a marker on the shared grid; several seats
may sit on one tile) → a private 2×5 browser with page and position counters, bumpers
paging, the focused racer's name and driving class → `CHOOSE A VARIANT` (or `CONFIRM`, or
reroll for Random) → `READY – B TO CHANGE`. One seat's paging never moves another's. When
every joined seat is ready the heading becomes `START RACE` and the first seat's A opens the
Courses page; more than one seat makes it a split-screen party race. Y stars a favorite; a
returning seat opens on Recently Used.

**Identity.** Colour, a large P-number badge and a different badge corner shape per seat, on
both the quadrant and the grid marker. Text sizes are 22 px and up for state and prompts.

**Input.** The local-multiplayer stack (`Players` frames): d-pad or stick moves, drift/cast is
A, item is B, bumpers page, slot 0 is Y. Keyboard players join on the WASD or arrows side.

**The extras** (all in `RacerSelect.gd`, knobs under `select` in `shared/tuning.json`):

- **Locks.** A monster of band `lock_band` (6, level 21) or above is locked until one has
  been slain in the Monster Campaign (`Campaign.unlocked`, filled by `Campaign.unlock` on a
  kill). Castes and the lower bands are always open. Locked portraits are dimmed, the name
  reads `[LOCKED]`, choosing one says `LOCKED: SLAY ONE IN THE MONSTER CAMPAIGN` and stays in
  the browser. Random never picks a locked racer.
- **Duplicates.** Twins are allowed and the rule is stated on the prompt line before any
  collision. The later seat is moved to the first variant no other seat holds and told
  `TWIN OF P1: VARIANT 2`; when every variant is taken it reads `SAME LOOK AS P1`.
- **Filters and sort.** Per seat, never shared: the 9 key cycles `all / unlocked / flying /
  light / middleweight / heavy`, the 8 key cycles `collection / name / speed / weight`, in
  the collection tiles or the browser; the browser re-lists around the racer under the
  cursor and the state line shows the active filter and sort. Gamepads have no spare button
  for these; the bible calls them secondary.
- **Search.** Keyboard seats only: `/` starts typing on the first keyboard seat that is
  browsing (from the collection tiles it opens All Racers), letters filter as they land
  against name, id, family, tags and the Qud blueprint, Backspace deletes, Enter or Esc
  stops typing and keeps the search, B clears it. While a seat is typing its drive keys do
  not move the cursor. The state line reads `SEARCH: gol_`, then `"gol"  1 / 69`.
- **The racer-and-vehicle preview.** In the variant and ready states the quadrant shows
  the racer in its own little 3D world: the idle sprite on a pedestal in the seat's colour,
  under a light, the pedestal turning and the sprite swaying (a flat sprite is never shown
  edge-on). In this engine the vehicle is the sprite: a kart is a Qud creature on the road,
  and the preview shows exactly what races, in the exact variant.
- **Spoken names.** `select.spoken_names` or `--spoken`: the OS voice (Godot's text to
  speech) says the racer under the cursor as it moves and the racer chosen. Off by default.
- **Reduced motion.** `select.reduced_motion` or `--reduced_motion`: the preview stops
  turning and swaying.

**Probes.** `--select_log` prints a `select:` line per browse, choose, lock, twin, ready,
filter/sort/search change, preview build and spoken name (`say "..." (no voice)` in a
headless run). `--select_keys=seat:action,...` drives the real handler with one frame per
action (`a b left right up down next prev fav filter sort all random type:<text>`), before
the Menu seats the `--party` players, so a script starts with `0:a` to join. The two checks:

```bash
Godot --headless --quit-after 90 -- --mode=racers --party=1 --select_log --spoken "--select_keys=0:a,0:all,0:a,0:right,0:type:adiyy,0:a,0:type:gol,0:filter,0:filter,0:sort,0:b"
Godot --headless --quit-after 90 -- --mode=racers --party=2 --select_log "--select_keys=0:a,0:all,0:a,0:type:snapjaw scavenger,0:a,0:a,1:a,1:all,1:a,1:type:snapjaw scavenger,1:a,1:a"
```

The first prints the lock (`locked adiyy (band 7)`), the search (`"gol" list=69`), the
filters (`unlocked` 65, `flying` 4), the sort and the cleared search (`flying` 45); the
second prints seat 1 as a twin moved to variant 1 and two previews with different units.
`--mode=racers --party=N --select_demo=browse,variant,ready` still renders the screen for
screenshots; `--select_autostart` proceeds to the Courses page.
