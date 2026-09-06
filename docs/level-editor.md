# The level editor

An overlay over a course in free drive, for devs and testers to improve a level quickly and
save what they did. Open a course with it:

```bash
cd godot && Godot -- --type=gp --track=joppa --newrun --editor
```

The wizard is in free drive (WASD, no laps, the field keeps running its route); the panel
sits on the right; **F1** hides and shows it. Everything applies live.

## What it edits

**The tree** lists the course's sprites by source (each Qud zone, the scatter, placed by
hand) and blueprint, with counts and the flags already set (`[hidden]`, `[floor]`...).
Select a blueprint to edit its kind:

| setting | what it does |
|---|---|
| hidden | none of this blueprint is placed |
| display | `billboard` (vertical, faces the camera), `floor` (flat on the ground where it stands), `road` (flat on the road layer, allowed under the road), `offroad` (flat, culled from the road), `wall` (a voxel wall block of the family its tile names, or the course's), `water` (a water cell) |
| scale | 0.25–3 × the tile's size |
| lift | px above its normal height |
| alpha, tint | translucency; one of Qud's eighteen palette letters over the tile |
| drop shadow | a dark disc under a billboard |
| animate | unit strips cycle their idle frames |
| solid | karts collide with it (four barricade segments around it) |
| density, band min/max | scatter entries of this blueprint: count multiplier and the distances from the curb it may stand at |

**Instances.** Click a sprite in the world to select it (the nearest on screen within 28 px);
HIDE removes that one, the nudge buttons move it 20 px, MOVE then a click on the ground moves
it there, PLACE (with a blueprint selected in the tree or the palette) then a click adds a
new one. The instance's own scale (multiplied over its kind's), rotation (flat sprites and
wall blocks) and horizontal flip sit under the buttons.

**The palette.** Every tiled Qud blueprint, 4000 of them, painted by the exporter: type in
the search box, pick one, PLACE, click the ground. A blueprint placed this way joins the
tree under "placed by hand" and gets kind settings like any other.

**The free-flying camera.** F2 (or FLY) leaves the wizard and flies: IJKL move, U and O rise
and sink, shift is fast, the right mouse button drags the view; F2 again returns to the
wizard's camera. Picking and placing work from the air.

**Undo and redo.** Every change snapshots the overrides first: UNDO / Ctrl+Z and REDO /
Ctrl+Shift+Z walk them, sixty deep.

**The course.** The floor mode (tiled ground or the Qud floor of dots and grasses) and, when
the course stands a Qud zone, where it stands: `at` (loop fraction), `side`, `gap` from the
curb. Sliding them re-places the zone.

## Where it goes

SAVE writes `shared/levels/<key>.json` to the repo and to the asset store's copy; RELOAD
reads it back; RESET KIND clears the selected blueprint's settings. The file is the source
of truth: `Track._build_dressing` reads it for every race, so what a tester saves is what
the game shows, and it is committed like any course data. Shape:

```json
{"kinds": {"Watervine": {"hidden": true}, "Torchpost": {"solid": true, "display": "billboard"}},
 "hidden": ["z:Joppa:12:7:Bed"], "moves": {"s:Dogthorn Tree:3": [4120.0, 2210.5]},
 "inst": {"z:Joppa:40:12:Starapple Tree": {"scale": 1.8, "rot": 90, "flip": true}},
 "extras": [{"name": "Starapple Tree", "x": 3000.0, "y": 1800.0}],
 "course": {"floor_mode": "qud", "zone": {"at": 0.97, "side": -1, "gap": 140}}}
```

## The probe

`--level_edit="Name:prop=value;@<instance id>:prop=value;+Name@x,y;undo"` applies kind and
instance settings, places an extra and undoes from the command line, and `--level_save`
saves, so a test can run without a window:

```bash
Godot --headless --quit-after 400 -- --type=gp --track=joppa --newrun --auto --noattacks --frames=300 --editor "--level_edit=Watervine:hidden=true;Torchpost:solid=true;Noisegrass:density=0.5" --level_save
```

prints an `editor:` line per setting and a `dressing:` line after each rebuild (Watervine
hidden: 412 hidden; Torchpost solid: 19 solid; Noisegrass at half density: 160 fewer items),
then `editor: saved`; a plain race afterwards prints the same `dressing:` numbers, which is
the file being read.

## Ideas not built yet

Painting the road's width and camber from inside (the road mesh is built once from the
course data; a slider would want a track rebuild), group selection, and copying a set of
instance edits from one course to another. The overrides file is plain JSON, so the last
two are a text editor away today.
