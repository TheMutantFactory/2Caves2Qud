"""The Qud surface as the racer's ground (docs/overland.md).

Three things, all pure Python so they are testable without a game or an engine:

- the OVERWORLD: Qud's static 80 x 25 parasang terrain map (QudWorldMap.rpm in the data
  copy), each parasang's terrain kind and the course tileset that stands for it;
- ZONE COORDINATES: zone ids (`JoppaWorld.wx.wy.zx.zy.z`) to and from global cells and
  world pixels (one cell = CELL_PX = 60 px, a zone = 80 x 25 cells, a parasang = 3 x 3
  zones), and `zones_within()`, the chunk-streaming policy the engine mirrors;
- the compact CHUNK format (one file per zone: a palette of distinct objects, the ground
  palette index per cell, the standing objects as [x, y, palette], Qud's light byte per cell)
  with a converter from the Raves bridge's zone snapshot, and PAVING: a course route laid
  over the chunks clears every wall / solid object under the road and its verge and records
  the road cells per zone.
"""
import json
import math
import os
import re
import xml.etree.ElementTree as ET

import qud_assets

WORLD = "JoppaWorld"
ZONE_W = 80
ZONE_H = 25
PARASANG = 3
WORLD_W = 80          # parasangs
WORLD_H = 25
SURFACE_Z = 10
CELL_PX = 60          # one Qud cell in world px: Track.TILE_PX, one voxel wall block
ZONE_PX_W = ZONE_W * CELL_PX      # 4800
ZONE_PX_H = ZONE_H * CELL_PX      # 1500

# --- the overworld ------------------------------------------------------------------------

# terrain stem -> the exporter's tileset (export_godot_assets.TILESETS). Stems come from
# terrain_stem(): the blueprint name without its variant digit and its space-suffix.
TERRAIN_TILESETS = {
    "TerrainJungle": "jungle", "TerrainDeepJungle": "jungle",
    "TerrainMountains": "stone", "TerrainMountainsSpindleShadow": "stone", "TerrainHills": "moss",
    "TerrainSaltdunes": "dune", "TerrainSaltmarsh": "salt", "TerrainDesertCanyon": "canyon",
    "TerrainMoonStair": "crystal", "TerrainFlowerfields": "leaf",
    "TerrainRuins": "ruin", "TerrainBaroqueRuins": "marble",
    "TerrainBananaGrove": "banana", "TerrainBananaGroveSpindleShadow": "banana",
    "TerrainWatervine": "watervine", "TerrainJoppa": "watervine", "TerrainJoppaTutorial": "watervine",
    "TerrainJoppaRedrockChannel": "canyon", "TerrainRedRock": "canyon",
    "TerrainFungal": "fungus", "TerrainRustWell": "rust", "TerrainRustedArchway": "rust",
    "TerrainTheSpindle": "chrome", "TerrainGritGate": "chrome", "TerrainSixDayStilt": "marble",
    "TerrainPalladiumReef": "reef", "TerrainOmonporch": "sultan", "TerrainKyakukya": "mushroom",
    "TerrainGolgotha": "bile", "TerrainEynRoj": "crystal", "TerrainBethesdaSusa": "marble",
    "TerrainAsphaltMines": "asphalt",
    "TerrainRiverYonth": "water", "TerrainRiverSvy": "water", "TerrainRiverOpal": "water",
    "TerrainMountainStream": "water", "TerrainLakeHinnom": "water", "TerrainOpalDuskwaters": "water",
}


def terrain_stem(name):
    """`TerrainRiverSvy Lake 8d` -> TerrainRiverSvy; `TerrainSaltdunes2` -> TerrainSaltdunes;
    every Fungal variant (OuterR, cG, Center, ...) -> TerrainFungal."""
    stem = name.split(" ")[0]
    stem = re.sub(r"\d+$", "", stem)
    if stem.startswith("TerrainFungal"):
        return "TerrainFungal"
    return stem


def terrain_tileset(name):
    return TERRAIN_TILESETS.get(terrain_stem(name))


def overworld(path=None):
    """{w, h, cells: [[terrain name] * 80] * 25} from QudWorldMap.rpm (row-major, y down)."""
    path = path or qud_assets.path("data", "QudWorldMap.rpm")
    root = ET.parse(path).getroot()
    w, h = int(root.get("Width", WORLD_W)), int(root.get("Height", WORLD_H))
    cells = [["" for _ in range(w)] for _ in range(h)]
    for cell in root.iter("cell"):
        x, y = int(cell.get("X")), int(cell.get("Y"))
        obj = cell.find("object")
        cells[y][x] = obj.get("Name") if obj is not None else ""
    return {"w": w, "h": h, "cells": cells}


def terrain_at(ow, wx, wy):
    return ow["cells"][wy][wx]


# --- zone ids, cells and pixels -----------------------------------------------------------

def zone_id(wx, wy, zx, zy, z=SURFACE_Z, world=WORLD):
    return "%s.%d.%d.%d.%d.%d" % (world, wx, wy, zx, zy, z)


def parse_zone_id(zid):
    parts = zid.split(".")
    return (".".join(parts[:-5]),) + tuple(int(p) for p in parts[-5:])


def zone_origin_cell(zid):
    _, wx, wy, zx, zy, _ = parse_zone_id(zid)
    return ((wx * PARASANG + zx) * ZONE_W, (wy * PARASANG + zy) * ZONE_H)


def zone_origin_px(zid):
    gx, gy = zone_origin_cell(zid)
    return (gx * CELL_PX, gy * CELL_PX)


def zone_at_px(x, y, z=SURFACE_Z):
    """The surface zone id under a world pixel, None off the map."""
    if x < 0 or y < 0:
        return None
    col = int(x // ZONE_PX_W)
    row = int(y // ZONE_PX_H)
    if col >= WORLD_W * PARASANG or row >= WORLD_H * PARASANG:
        return None
    return zone_id(col // PARASANG, row // PARASANG, col % PARASANG, row % PARASANG, z)


def cell_at_px(x, y, z=SURFACE_Z):
    """(zone id, x, y) of the cell under a world pixel; None off the map."""
    zid = zone_at_px(x, y, z)
    if zid is None:
        return None
    ox, oy = zone_origin_px(zid)
    return (zid, int((x - ox) // CELL_PX), int((y - oy) // CELL_PX))


def cell_px(zid, x, y):
    """World px of the cell's top-left corner."""
    ox, oy = zone_origin_px(zid)
    return (ox + x * CELL_PX, oy + y * CELL_PX)


def zones_within(px, radius, z=SURFACE_Z):
    """The streaming policy: every zone within `radius` zones (Chebyshev) of the zone
    under `px`, clipped to the map. The engine's QudWorld mirrors this exactly."""
    zid = zone_at_px(px[0], px[1], z)
    if zid is None:
        return set()
    _, wx, wy, zx, zy, _ = parse_zone_id(zid)
    col, row = wx * PARASANG + zx, wy * PARASANG + zy
    out = set()
    for c in range(col - radius, col + radius + 1):
        for r in range(row - radius, row + radius + 1):
            if 0 <= c < WORLD_W * PARASANG and 0 <= r < WORLD_H * PARASANG:
                out.add(zone_id(c // PARASANG, r // PARASANG, c % PARASANG, r % PARASANG, z))
    return out


# --- the compact chunk --------------------------------------------------------------------

PALETTE_KEYS = ("name", "tile", "color", "detail", "tilecolor", "wall", "solid", "liquid", "ground",
                "creature", "lightRadius", "layer")


def _palette_entry(o):
    return {
        "name": str(o.get("name", "")),
        "tile": str(o.get("tile", "")),
        "color": str(o.get("color", "")),
        "detail": str(o.get("detail", "")),
        "tilecolor": str(o.get("tilecolor", "")),
        "wall": bool(o.get("wall", False)),
        "solid": bool(o.get("solid", False)),
        "liquid": bool(o.get("liquid", False)),
        "ground": bool(o.get("ground", False)),
        "creature": bool(o.get("creature", False)),
        "lightRadius": int(o.get("lightRadius", 0) or 0),
        "layer": int(o.get("layer", 0) or 0),
    }


class Chunk:
    """One zone. ground[i] / light[i] index cells by y * w + x; objs are (x, y, palette)
    for every non-ground object, in the snapshot's draw order."""

    def __init__(self, zid, w=ZONE_W, h=ZONE_H):
        self.id = zid
        self.w, self.h = w, h
        _, self.wx, self.wy, self.zx, self.zy, self.z = parse_zone_id(zid)
        self.palette = []
        self._pal_index = {}
        self.ground = [-1] * (w * h)
        self.light = [0] * (w * h)
        self.objs = []

    def cell_index(self, x, y):
        return y * self.w + x

    def palette_index(self, o):
        e = _palette_entry(o)
        key = tuple(e[k] for k in PALETTE_KEYS)
        i = self._pal_index.get(key)
        if i is None:
            i = len(self.palette)
            self.palette.append(e)
            self._pal_index[key] = i
        return i

    def objects_at(self, x, y):
        return [self.palette[i] for (ox, oy, i) in self.objs if ox == x and oy == y]

    def is_wall(self, x, y):
        return any(p["wall"] for p in self.objects_at(x, y))

    def is_solid(self, x, y):
        return any(p["wall"] or p["solid"] for p in self.objects_at(x, y))

    def is_liquid(self, x, y):
        return any(p["liquid"] for p in self.objects_at(x, y))

    def copy(self):
        c = Chunk(self.id, self.w, self.h)
        c.palette = [dict(p) for p in self.palette]
        c._pal_index = dict(self._pal_index)
        c.ground = list(self.ground)
        c.light = list(self.light)
        c.objs = list(self.objs)
        return c

    def to_dict(self):
        return {"id": self.id, "wx": self.wx, "wy": self.wy, "zx": self.zx, "zy": self.zy, "z": self.z,
                "w": self.w, "h": self.h, "palette": self.palette, "ground": self.ground,
                "objs": [list(o) for o in self.objs], "light": self.light}

    @classmethod
    def from_dict(cls, d):
        c = cls(d["id"], int(d.get("w", ZONE_W)), int(d.get("h", ZONE_H)))
        c.palette = [_palette_entry(p) for p in d["palette"]]
        c._pal_index = {tuple(p[k] for k in PALETTE_KEYS): i for i, p in enumerate(c.palette)}
        c.ground = [int(g) for g in d["ground"]]
        c.light = [int(l) for l in d["light"]]
        c.objs = [(int(o[0]), int(o[1]), int(o[2])) for o in d["objs"]]
        return c


def chunk_from_snapshot(snap):
    """A Chunk from a Raves bridge zone snapshot (the wire format, or the trimmed record
    WorldStore saves): {zone: {id, ...}, cells: [{x, y, light, objs: [...]}]}."""
    zone = snap["zone"]
    zid = zone.get("id") or zone_id(int(zone["wx"]), int(zone["wy"]), int(zone["zx"]), int(zone["zy"]), int(zone.get("z", SURFACE_Z)))
    ch = Chunk(zid, int(zone.get("width", ZONE_W)), int(zone.get("height", ZONE_H)))
    for cell in snap.get("cells", []):
        x, y = int(cell["x"]), int(cell["y"])
        if not (0 <= x < ch.w and 0 <= y < ch.h):
            continue
        i = ch.cell_index(x, y)
        ch.light[i] = int(cell.get("light", 0))
        for o in cell.get("objs", []):
            if o.get("ground"):
                ch.ground[i] = ch.palette_index(o)
            else:
                ch.objs.append((x, y, ch.palette_index(o)))
    return ch


def save_chunk(ch, path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(ch.to_dict(), f, separators=(",", ":"))


def load_chunk(path):
    with open(path, encoding="utf-8") as f:
        return Chunk.from_dict(json.load(f))


# --- paving -------------------------------------------------------------------------------

def seg_dist(p, a, b):
    """Distance from point p to segment ab."""
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    if l2 == 0:
        return math.hypot(p[0] - ax, p[1] - ay)
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / l2))
    return math.hypot(p[0] - (ax + t * dx), p[1] - (ay + t * dy))


def route_dist(p, route, closed, bbox=None):
    if bbox is not None and (p[0] < bbox[0] or p[0] > bbox[2] or p[1] < bbox[1] or p[1] > bbox[3]):
        return float("inf")
    n = len(route)
    best = float("inf")
    for i in range(n if closed else n - 1):
        d = seg_dist(p, route[i], route[(i + 1) % n])
        if d < best:
            best = d
    return best


class Paving:
    """The result of pave(): the chunks with the road's solids removed, the road cells per
    zone and what was cleared per zone (so the overlay is a diff, not a copy)."""

    def __init__(self):
        self.chunks = {}
        self.road_cells = {}     # zone id -> [(x, y)]
        self.cleared = {}        # zone id -> [(x, y, palette)]

    def to_dict(self):
        return {"road": {z: [list(c) for c in cells] for z, cells in self.road_cells.items()},
                "cleared": {z: [list(c) for c in cells] for z, cells in self.cleared.items()}}


def pave(chunks, route, width_px, verge_px=CELL_PX, closed=True):
    """Lay a road (a polyline in world px) over the chunks. A cell is ROAD when its centre is
    within width/2 of the route: everything standing on it goes except floors and liquids
    (the road is drawn over them). Within the VERGE beyond that, walls and solids go too, so
    nothing hard stands at the curb. Input chunks are not mutated."""
    half = width_px * 0.5
    reach = half + verge_px
    xs = [p[0] for p in route]
    ys = [p[1] for p in route]
    bbox = (min(xs) - reach, min(ys) - reach, max(xs) + reach, max(ys) + reach)
    out = Paving()
    for zid in sorted(chunks):
        ch = chunks[zid]
        ox, oy = zone_origin_px(zid)
        if ox + ch.w * CELL_PX < bbox[0] or ox > bbox[2] or oy + ch.h * CELL_PX < bbox[1] or oy > bbox[3]:
            out.chunks[zid] = ch
            continue
        dist = {}
        road = []
        for y in range(ch.h):
            for x in range(ch.w):
                c = (ox + (x + 0.5) * CELL_PX, oy + (y + 0.5) * CELL_PX)
                d = route_dist(c, route, closed, bbox)
                dist[(x, y)] = d
                if d <= half:
                    road.append((x, y))
        new = ch.copy()
        cleared = []
        kept = []
        for (x, y, i) in ch.objs:
            p = ch.palette[i]
            d = dist[(x, y)]
            hard = p["wall"] or p["solid"]
            on_road = d <= half and not p["liquid"] and not p.get("floor", False)
            if on_road or (hard and d <= reach):
                cleared.append((x, y, i))
            else:
                kept.append((x, y, i))
        new.objs = kept
        out.chunks[zid] = new
        if road:
            out.road_cells[zid] = road
        if cleared:
            out.cleared[zid] = cleared
    return out


# Where each course lands on the world: the anchor zone whose origin is the canvas origin.
# Joppa's loop, at track_scale 4, spans about 26k x 17k px; anchored at parasang 10.21's
# last column the village (11.22.1.1) sits inside the loop, within the 5x5 region baked
# round it (wx 9..13, wy 20..24).
COURSE_ANCHORS = {"joppa": "JoppaWorld.10.21.2.0.10"}


def track_scale():
    """The engine's px multiplier on every course (shared/tuning.json race.track_scale,
    Track._build_loop): the generator's STRETCH is already in tracks.json's control points."""
    p = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "shared", "tuning.json")
    try:
        with open(p, encoding="utf-8") as f:
            return float(json.load(f).get("race", {}).get("track_scale", 2.0))
    except (OSError, ValueError):
        return 2.0


def course_spec(key):
    """The engine's copy of a course (shared/tracks.json), which is what Godot builds."""
    p = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "shared", "tracks.json")
    with open(p, encoding="utf-8") as f:
        tj = json.load(f)
    for t in (tj["tracks"] if isinstance(tj, dict) else tj):
        if t["key"] == key:
            return t
    raise KeyError(key)


def course_bounds_px(spec, anchor_zone):
    """(x0, y0, x1, y1): where the course canvas lands in world px."""
    k = track_scale()
    ox, oy = zone_origin_px(anchor_zone)
    return (ox, oy, ox + spec["size"][0] * k, oy + spec["size"][1] * k)


def course_route(spec, anchor_zone, samples=16):
    """A course's loop as world px, the way the engine lays it: tracks.json control points
    (STRETCH already applied) times race.track_scale, the canvas origin on the anchor zone's
    origin. With track_scale 4 a course is ~26k x 17k px: two parasangs wide, four tall."""
    import qud_tracks
    k = track_scale()
    ox, oy = zone_origin_px(anchor_zone)
    control = [(ox + x * k, oy + y * k) for (x, y) in spec["control"]]
    return qud_tracks._loop_points(control, samples)
