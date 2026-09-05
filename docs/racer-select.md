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

**Not built yet.** Text search, filters and sort, the racer-and-vehicle 3D preview (portraits
are the idle sprite), duplicate-selection rules (duplicates are allowed), unlocks in the
select (the Monster Campaign's unlock list still lives in `Campaign.unlocked`), spoken names,
reduced-motion settings. `--mode=racers --party=N --select_demo=browse,variant,ready` renders
the screen with seeded seats for screenshots; `--select_autostart` proceeds to the Courses page.
