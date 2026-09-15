"""Overland (docs/overland.md): the overworld, zone coordinates, the compact chunk
format and paving. Pure Python; the only external input is the Qud data copy in the
asset store (skipped when it is not extracted on this machine)."""
import glob
import json
import os

import pytest

import qud_assets
import qud_world as qw

HAVE_STORE = os.path.exists(qud_assets.path("data", "QudWorldMap.rpm"))
needs_store = pytest.mark.skipif(not HAVE_STORE, reason="asset store not extracted")

RAVES_WORLD = os.path.expanduser(r"~\Library\Application Support\RavesOfQud\world")
RAVES_ZONES = sorted(glob.glob(os.path.join(RAVES_WORLD, "*", "JoppaWorld.*.10.json")))


# --- G1: the overworld ---------------------------------------------------------

@needs_store
def test_overworld_is_the_full_parasang_grid():
    ow = qw.overworld()
    assert ow["w"] == 80 and ow["h"] == 25
    assert len(ow["cells"]) == 25 and all(len(r) == 80 for r in ow["cells"])
    assert qw.terrain_at(ow, 11, 22) in ("TerrainJoppa", "TerrainJoppaTutorial", "TerrainWatervine")


@needs_store
def test_every_terrain_kind_in_the_map_has_a_tileset():
    from export_godot_assets import TILESETS
    ow = qw.overworld()
    kinds = {name for row in ow["cells"] for name in row}
    assert len(kinds) > 40
    unmapped = sorted(k for k in kinds if qw.terrain_tileset(k) is None)
    assert unmapped == [], "terrain kinds with no tileset: %s" % unmapped
    bad = sorted({qw.terrain_tileset(k) for k in kinds} - set(TILESETS))
    assert bad == [], "tilesets the exporter does not know: %s" % bad


def test_terrain_stem_drops_variants_and_suffixes():
    assert qw.terrain_stem("TerrainSaltdunes2") == "TerrainSaltdunes"
    assert qw.terrain_stem("TerrainRiverSvy Lake 8d") == "TerrainRiverSvy"
    assert qw.terrain_stem("TerrainLakeHinnom blank") == "TerrainLakeHinnom"
    assert qw.terrain_stem("TerrainFungalOuterGw") == "TerrainFungal"
    assert qw.terrain_tileset("TerrainRiverYonth NSE") == "water"
    assert qw.terrain_tileset("NotATerrain") is None


# --- zone ids and pixels ------------------------------------------------------

def test_zone_id_round_trip():
    zid = qw.zone_id(11, 22, 1, 1)
    assert zid == "JoppaWorld.11.22.1.1.10"
    assert qw.parse_zone_id(zid) == ("JoppaWorld", 11, 22, 1, 1, 10)
    assert qw.parse_zone_id("JoppaWorld.11.22.1.1.11")[5] == 11


def test_zone_origin_is_the_global_cell_times_cell_px():
    # Joppa's zone: parasang 11,22, zone 1,1 -> global cell (34*80, 67*25)
    assert qw.zone_origin_px("JoppaWorld.11.22.1.1.10") == (34 * 80 * 60, 67 * 25 * 60)
    assert qw.zone_origin_px("JoppaWorld.0.0.0.0.10") == (0, 0)


def test_zone_at_px_inverts_the_origin():
    for zid in ["JoppaWorld.11.22.1.1.10", "JoppaWorld.0.0.0.0.10", "JoppaWorld.79.24.2.2.10"]:
        ox, oy = qw.zone_origin_px(zid)
        assert qw.zone_at_px(ox, oy) == zid
        assert qw.zone_at_px(ox + 4799, oy + 1499) == zid
        assert qw.zone_at_px(ox + 4800, oy) != zid
    assert qw.zone_at_px(-1, 0) is None
    assert qw.zone_at_px(80 * 3 * 4800, 0) is None


def test_cell_at_px_and_back():
    zid, x, y = qw.cell_at_px(34 * 4800 + 61, 67 * 1500 + 1499)
    assert (zid, x, y) == ("JoppaWorld.11.22.1.1.10", 1, 24)
    assert qw.cell_px(zid, 1, 24) == (34 * 4800 + 60, 67 * 1500 + 24 * 60)


def test_zones_within_is_the_streaming_policy():
    # radius 1 round Joppa's zone: the 3x3 of neighbouring zones, straddling parasangs
    got = qw.zones_within(qw.zone_origin_px("JoppaWorld.11.22.1.1.10"), 1)
    assert len(got) == 9
    assert "JoppaWorld.11.22.0.0.10" in got and "JoppaWorld.11.22.2.2.10" in got
    # the zone west of parasang 11's first column is parasang 10's last column
    got = qw.zones_within(qw.zone_origin_px("JoppaWorld.11.22.0.1.10"), 1)
    assert "JoppaWorld.10.22.2.1.10" in got
    # the map edge clips the set
    got = qw.zones_within((0, 0), 1)
    assert len(got) == 4


# --- the compact chunk ---------------------------------------------------------

def _synthetic_chunk(walls=(), props=(), liquids=()):
    """A flat zone of dirt with walls / props / puddles at the given cells."""
    snapshot = {"zone": {"id": "JoppaWorld.11.22.1.1.10", "wx": 11, "wy": 22, "zx": 1, "zy": 1, "z": 10,
                         "width": 80, "height": 25}, "cells": []}
    for y in range(25):
        for x in range(80):
            objs = [{"name": "[painted ground]", "tile": "Tiles/tile-dirt1.png", "color": "&w", "detail": "k",
                     "ground": True, "wall": False, "solid": False}]
            if (x, y) in walls:
                objs.append({"name": "BrinestalkWall", "tile": "Walls/wall_brinestalk-00000000.png",
                             "color": "&w", "detail": "W", "wall": True, "solid": True})
            if (x, y) in props:
                objs.append({"name": "Watervine", "tile": "Terrain/sw_watervine.bmp", "color": "&g",
                             "detail": "G", "wall": False, "solid": False})
            if (x, y) in liquids:
                objs.append({"name": "SaltyWaterPuddle", "tile": "Liquids/Water/deep-00000000.png",
                             "color": "&b", "detail": "B", "wall": False, "solid": False, "liquid": True})
            snapshot["cells"].append({"x": x, "y": y, "light": 200 if y < 20 else 1, "objs": objs})
    return qw.chunk_from_snapshot(snapshot)


def test_chunk_from_snapshot_builds_the_palette_and_grids():
    ch = _synthetic_chunk(walls={(5, 5), (6, 5)}, props={(10, 10)}, liquids={(70, 20)})
    assert ch.id == "JoppaWorld.11.22.1.1.10" and (ch.w, ch.h) == (80, 25)
    assert len(ch.ground) == 2000 and len(ch.light) == 2000
    names = [p["name"] for p in ch.palette]
    assert names.count("BrinestalkWall") == 1, "one palette entry per distinct object"
    assert all(ch.ground[i] >= 0 for i in range(2000))
    assert sorted(ch.objs) == sorted([(5, 5, names.index("BrinestalkWall")), (6, 5, names.index("BrinestalkWall")),
                                      (10, 10, names.index("Watervine")), (70, 20, names.index("SaltyWaterPuddle"))])
    assert ch.light[0] == 200 and ch.light[24 * 80] == 1
    assert ch.palette[names.index("BrinestalkWall")]["wall"] is True
    assert ch.palette[names.index("SaltyWaterPuddle")]["liquid"] is True


def test_chunk_json_round_trip_is_small_and_exact(tmp_path):
    ch = _synthetic_chunk(walls={(x, 3) for x in range(80)}, props={(x, y) for x in range(0, 80, 3) for y in range(5, 25, 2)})
    p = tmp_path / "z.json"
    qw.save_chunk(ch, str(p))
    assert p.stat().st_size < 80 * 1024
    back = qw.load_chunk(str(p))
    assert back.to_dict() == ch.to_dict()


def test_chunk_queries():
    ch = _synthetic_chunk(walls={(5, 5)}, props={(10, 10)}, liquids={(70, 20)})
    assert ch.is_wall(5, 5) and not ch.is_wall(6, 5)
    assert ch.is_liquid(70, 20)
    assert [o["name"] for o in ch.objects_at(10, 10)] == ["Watervine"]
    assert ch.cell_index(79, 24) == 1999


@pytest.mark.skipif(not RAVES_ZONES, reason="no Raves-saved zones on this machine")
def test_raves_saved_zones_convert():
    for path in RAVES_ZONES:
        with open(path, encoding="utf-8") as f:
            snap = json.load(f)
        ch = qw.chunk_from_snapshot(snap)
        assert (ch.w, ch.h) == (80, 25)
        assert len(ch.ground) == 2000
        # Qud paints ground only on a cell with nothing drawable on it; a marsh zone is mostly
        # puddles and vines (12.22.1.1: 332 painted, 2000 covered). Unpainted = the biome floor.
        painted = sum(1 for g in ch.ground if g >= 0)
        covered = len({i for i, g in enumerate(ch.ground) if g >= 0} | {y * ch.w + x for (x, y, _) in ch.objs})
        assert painted >= 300 and covered >= 1990, "%s: %d painted, %d covered" % (path, painted, covered)
        assert all(0 <= l <= 255 for l in ch.light)
        d = json.dumps(ch.to_dict(), separators=(",", ":"))
        assert len(d) < 80 * 1024, "%s compacts to %d bytes" % (os.path.basename(path), len(d))


# --- G4: paving ----------------------------------------------------------------

def _dist_to_polyline(p, pts):
    best = float("inf")
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        best = min(best, qw.seg_dist(p, a, b))
    return best


def test_seg_dist():
    assert qw.seg_dist((0, 1), (0, 0), (10, 0)) == 1.0
    assert qw.seg_dist((15, 0), (0, 0), (10, 0)) == 5.0
    assert qw.seg_dist((5, 0), (5, 0), (5, 0)) == 0.0


def test_pave_clears_solids_under_the_road_and_keeps_the_rest():
    walls = {(x, 12) for x in range(80)} | {(40, y) for y in range(25)}
    props = {(x, y) for x in range(0, 80, 4) for y in range(0, 25, 4)}
    ch = _synthetic_chunk(walls=walls, props=props)
    ox, oy = qw.zone_origin_px(ch.id)
    # a straight road along row 12, west to east, 5 cells wide (300 px) + a 1-cell verge
    route = [(ox, oy + 12 * 60 + 30), (ox + 80 * 60, oy + 12 * 60 + 30)]
    paved = qw.pave({ch.id: ch}, route, width_px=300, verge_px=60, closed=False)
    out = paved.chunks[ch.id]
    road = paved.road_cells[ch.id]
    assert road, "the road crosses this chunk"
    for (x, y) in road:
        c = (ox + x * 60 + 30, oy + y * 60 + 30)
        assert _dist_to_polyline(c, route) <= 150 + 1e-6
    for (x, y, idx) in out.objs:
        c = (ox + x * 60 + 30, oy + y * 60 + 30)
        if out.palette[idx]["wall"] or out.palette[idx]["solid"]:
            assert _dist_to_polyline(c, route) > 150 + 60 - 1e-6, "a solid survived at %d,%d" % (x, y)
    # far cells are untouched: the north-south wall keeps its far ends, props off the road stay
    assert out.is_wall(40, 0) and out.is_wall(40, 24)
    assert not out.is_wall(40, 12) and not out.is_wall(0, 12)
    assert [o["name"] for o in out.objects_at(0, 0)] == ["Watervine"]
    # a plant ON the road goes too (row 12 is road; the props at rows 8 and 16 sit 4 cells
    # off the centre line = 240 px, outside the 150 px half-width, and stay)
    assert out.objects_at(40, 12) == [] and out.objects_at(0, 12) == []
    assert [o["name"] for o in out.objects_at(0, 8)] == ["Watervine"]
    assert len(paved.cleared[ch.id]) == 80 + 6 + 20   # the wall row, the crossing wall's 6 verge cells, the 20 props on row 12
    assert ch.is_wall(40, 12), "the input chunk is not mutated"


def test_pave_is_deterministic_and_stays_in_touched_chunks():
    ch = _synthetic_chunk(walls={(x, 12) for x in range(80)})
    other = qw.chunk_from_snapshot({"zone": {"id": "JoppaWorld.11.22.2.1.10", "wx": 11, "wy": 22, "zx": 2, "zy": 1,
                                             "z": 10, "width": 80, "height": 25}, "cells": []})
    ox, oy = qw.zone_origin_px(ch.id)
    route = [(ox + 100, oy + 700), (ox + 2000, oy + 800), (ox + 3000, oy + 300)]
    a = qw.pave({ch.id: ch, other.id: other}, route, 250, 60, closed=True)
    b = qw.pave({ch.id: ch, other.id: other}, route, 250, 60, closed=True)
    assert json.dumps(a.to_dict(), sort_keys=True) == json.dumps(b.to_dict(), sort_keys=True)
    assert other.id not in a.road_cells, "a chunk the road never crosses is not in the overlay"


def test_course_route_lands_on_the_anchor_at_the_engine_scale():
    spec = qw.course_spec("joppa")
    anchor = "JoppaWorld.10.21.0.0.10"
    route = qw.course_route(spec, anchor)
    assert len(route) >= 16 * len(spec["control"])
    x0, y0, x1, y1 = qw.course_bounds_px(spec, anchor)
    assert (x0, y0) == qw.zone_origin_px(anchor)
    k = qw.track_scale()
    assert k >= 1.0 and (x1 - x0) == spec["size"][0] * k
    xs = [p[0] for p in route]
    ys = [p[1] for p in route]
    assert min(xs) >= x0 - 1 and min(ys) >= y0 - 1 and max(xs) <= x1 + 1 and max(ys) <= y1 + 1
    zones = {qw.zone_at_px(*p) for p in route}
    assert None not in zones and len(zones) >= 4, "a course spans many zones"


def test_course_anchors_keep_the_canvas_in_the_baked_region():
    # the 5x5 parasang region baked round Joppa (wx 9..13, wy 20..24)
    rx0, ry0 = qw.zone_origin_px("JoppaWorld.9.20.0.0.10")
    rx1, ry1 = qw.zone_origin_px("JoppaWorld.13.24.2.2.10")
    for key, anchor in qw.COURSE_ANCHORS.items():
        x0, y0, x1, y1 = qw.course_bounds_px(qw.course_spec(key), anchor)
        assert x0 >= rx0 and y0 >= ry0 and x1 <= rx1 + 4800 and y1 <= ry1 + 1500, key
    # Joppa's village zone lies inside its course canvas
    x0, y0, x1, y1 = qw.course_bounds_px(qw.course_spec("joppa"), qw.COURSE_ANCHORS["joppa"])
    vx, vy = qw.zone_origin_px("JoppaWorld.11.22.1.1.10")
    assert x0 <= vx and vx + 4800 <= x1 and y0 <= vy and vy + 1500 <= y1
