"""The overland export (docs/overland.md, G3): baked chunks -> what Godot draws.

The Raves bridge's `bake` writes one compact chunk per zone under
<RavesOfQud>/chunks/<gameId>/ (tools/capture/bake.py over there). Each palette entry is a
Qud object as the game rendered it: blueprint name, tile, colour strings, wall / solid /
liquid / creature flags, a light radius. This module resolves every entry to something the
engine can stand up, the way the course dressing does (tools/qud_zones.py):

    ground   -> a cell of the GROUND ATLAS: every distinct (tile, main, detail) painted once
    wall     -> a voxel wall family (walls/<family>.vox) — a fence is a prop, it is thin
    floor    -> a painted tile laid flat (Qud's dirt paths, floors, rugs)
    water    -> a water cell in the liquid's colour
    creature -> a unit idle strip when the extractor made one, else a prop
    prop     -> a painted billboard (world/<gameId>/art/<key>.png, by the INSTANCE colours)
    skip     -> no tile at all (nothing Qud draws either)

Output, under <store>/godot/world/<gameId>/:
    index.json            gameId, the zone list with bounds, the atlas geometry, the stats
    ground.png            the ground atlas (48 x 72 cells, 16 per row)
    art/<key>.png         the painted prop / floor tiles
    <zoneId>.json         the resolved chunk: ground (atlas indices), objs [[x, y, p]],
                          palette [{name, kind, art, fam, color, radius}], and the raw flags
"""
import hashlib
import json
import os
import sys

from PIL import Image

import qud_assets
import qud_palette
import qud_world as qw
from qud_blueprints import slug

ATLAS_COLS = 16
TILE_W, TILE_H = 16, 24


def chunks_root():
    """Where the Raves bake writes: <RavesOfQud support dir>/chunks. CAVES2_CHUNKS overrides."""
    env = os.environ.get("CAVES2_CHUNKS")
    if env:
        return env
    if sys.platform == "darwin" or sys.platform.startswith("win"):
        base = os.path.expanduser("~/Library/Application Support/RavesOfQud")
    else:
        base = os.path.expanduser("~/.local/share/RavesOfQud")
    return os.path.join(base, "chunks")


def latest_world(root=None):
    """The gameId dir with the newest world.json (or CAVES2_WORLD), None if none baked."""
    root = root or chunks_root()
    env = os.environ.get("CAVES2_WORLD")
    if env and os.path.isdir(os.path.join(root, env)):
        return env
    best, best_t = None, -1
    if not os.path.isdir(root):
        return None
    for gid in os.listdir(root):
        wj = os.path.join(root, gid, "world.json")
        if os.path.isfile(wj) and os.path.getmtime(wj) > best_t:
            best, best_t = gid, os.path.getmtime(wj)
    return best


def norm_tile(tile):
    """A tile path as the blueprints write it. The bake sometimes carries the atlas-flattened
    name (`Assets_Content_Textures_Tiles_fence_ew.bmp`): strip the prefix, the first `_`
    splits folder from file (no texture folder contains `_`)."""
    t = tile.replace("\\", "/")
    low = t.lower()
    prefix = "assets_content_textures_"
    if low.startswith(prefix):
        rest = t[len(prefix):]
        i = rest.find("_")
        if i > 0:
            folder = rest[:i]
            folder = folder[:1].upper() + folder[1:]
            return folder + "/" + rest[i + 1:]
    return t


def main_letter(color):
    """`&w^k` -> w: the foreground letter of a Qud colour string (default y)."""
    if not color:
        return "y"
    i = color.rfind("&")
    if i >= 0 and i + 1 < len(color):
        return color[i + 1]
    return color[0] if len(color) == 1 else "y"


def detail_letter(detail):
    return detail[:1] if detail else "Y"


def rgb_hex(color):
    r, g, b = qud_palette.rgb(main_letter(color))
    return "%02x%02x%02x" % (r, g, b)


def kind_of(bp, p):
    """The display kind of a palette entry (see the module doc)."""
    if p.get("ground"):
        return "ground"
    if not p.get("tile"):
        return "skip"
    if p.get("liquid"):
        return "water"
    name = p.get("name", "")
    if p.get("wall") and "Fence" not in name:
        return "wall"
    if p.get("creature"):
        return "creature"
    try:
        chain = [c["name"] for c in bp.chain(name)]
    except Exception:
        chain = []
    if "Floor" in chain and not p.get("wall"):
        return "floor"
    return "prop"


class GroundAtlas:
    def __init__(self):
        self.entries = []          # (tile, main letter, detail letter)
        self._index = {}

    def index(self, tile, color, detail):
        key = (norm_tile(tile), main_letter(color), detail_letter(detail))
        i = self._index.get(key)
        if i is None:
            i = len(self.entries)
            self.entries.append(key)
            self._index[key] = i
        return i

    def render(self, load_tile, paint, scaled, path):
        n = max(1, len(self.entries))
        cols = ATLAS_COLS
        rows = (n + cols - 1) // cols
        cw, ch = TILE_W * 3, TILE_H * 3
        img = Image.new("RGBA", (cols * cw, rows * ch), (0, 0, 0, 0))
        missing = 0
        for i, (tile, main, detail) in enumerate(self.entries):
            src = load_tile(tile)
            if src is None:
                missing += 1
                cell = Image.new("RGBA", (cw, ch), qud_palette.rgb(main) + (255,))
            else:
                cell = scaled(paint(src, main, detail))
            img.paste(cell, ((i % cols) * cw, (i // cols) * ch))
        img.save(path)
        return {"cols": cols, "rows": rows, "cell_w": cw, "cell_h": ch, "count": len(self.entries), "missing": missing}


class WorldExporter:
    def __init__(self, bp, out, families, unit_slugs, paint, scaled, load_tile):
        self.bp, self.out, self.families, self.unit_slugs = bp, out, families, unit_slugs
        self.paint, self.scaled, self.load_tile = paint, scaled, load_tile
        self.atlas = GroundAtlas()
        self.art = {}              # art key -> relative path
        self.skipped = {}          # name -> count
        os.makedirs(os.path.join(out, "art"), exist_ok=True)

    def _wall_family(self, name):
        import qud_zones
        return qud_zones.wall_family(self.bp, name, self.families)

    def _paint_art(self, name, tile, color, detail):
        """A billboard / floor tile painted in the instance's own colours, written once."""
        t = norm_tile(tile)
        m, d = main_letter(color), detail_letter(detail)
        # Qud's colour letters are case-sensitive (y dark, Y bright) and Windows file names
        # are not: spell the case out ("dy" / "bY") or two paints overwrite one file.
        code = lambda l: ("b" if l.isupper() else "d") + l
        key = "%s_%s%s_%s" % (slug(name).lower(), code(m), code(d), hashlib.md5(t.encode("utf-8")).hexdigest()[:6])
        if key in self.art:
            return self.art[key]
        img = self.load_tile(t)
        if img is None:
            self.art[key] = ""
            return ""
        rel = "art/" + key + ".png"
        self.scaled(self.paint(img, m, d)).save(os.path.join(self.out, rel))
        self.art[key] = rel
        return rel

    def resolve_entry(self, p):
        kind = kind_of(self.bp, p)
        name = p.get("name", "")
        e = {"name": name, "kind": kind, "art": "", "fam": "", "color": rgb_hex(p.get("color", "")),
             "wall": bool(p.get("wall")), "solid": bool(p.get("solid")), "radius": int(p.get("lightRadius", 0) or 0)}
        if kind == "wall":
            e["fam"] = self._wall_family(name)
            if not e["fam"]:
                kind = "prop"
        if kind == "creature":
            u = self.unit_slugs.get(name)
            if u:
                e["art"] = "unit:" + u
            else:
                kind = "prop"
        if kind in ("prop", "floor"):
            e["art"] = self._paint_art(name, p.get("tile", ""), p.get("color", ""), p.get("detail", ""))
            if not e["art"]:
                kind = "skip"
        if kind == "water":
            e["color"] = rgb_hex(p.get("color", "&b"))
        e["kind"] = kind
        return e

    def resolve_chunk(self, ch):
        palette = [self.resolve_entry(p) for p in ch.palette]
        ground = []
        for g in ch.ground:
            if g < 0:
                ground.append(-1)
            else:
                p = ch.palette[g]
                ground.append(self.atlas.index(p["tile"], p["color"], p["detail"]))
        for (x, y, i) in ch.objs:
            if palette[i]["kind"] == "skip":
                self.skipped[palette[i]["name"]] = self.skipped.get(palette[i]["name"], 0) + 1
        return {"id": ch.id, "wx": ch.wx, "wy": ch.wy, "zx": ch.zx, "zy": ch.zy, "z": ch.z, "w": ch.w, "h": ch.h,
                "ground": ground, "objs": [list(o) for o in ch.objs], "palette": palette}

    def export(self, gid, src_dir):
        zones = []
        total = resolved = 0
        for fn in sorted(os.listdir(src_dir)):
            if not fn.startswith("JoppaWorld.") or not fn.endswith(".json"):
                continue
            ch = qw.load_chunk(os.path.join(src_dir, fn))
            res = self.resolve_chunk(ch)
            kinds = [p["kind"] for p in res["palette"]]
            total += len(ch.objs)
            resolved += sum(1 for (x, y, i) in ch.objs if kinds[i] != "skip")
            with open(os.path.join(self.out, ch.id + ".json"), "w", encoding="utf-8") as f:
                json.dump(res, f, separators=(",", ":"))
            ox, oy = qw.zone_origin_px(ch.id)
            zones.append({"id": ch.id, "wx": ch.wx, "wy": ch.wy, "zx": ch.zx, "zy": ch.zy, "z": ch.z,
                          "px": [ox, oy], "objs": len(ch.objs)})
        atlas = self.atlas.render(self.load_tile, self.paint, self.scaled, os.path.join(self.out, "ground.png"))
        manifest = {}
        try:
            with open(os.path.join(src_dir, "world.json"), encoding="utf-8") as f:
                manifest = json.load(f)
        except (OSError, ValueError):
            pass
        index = {"gameId": gid, "world": manifest, "cell_px": qw.CELL_PX, "zone_w": qw.ZONE_W, "zone_h": qw.ZONE_H,
                 "parasang": qw.PARASANG, "atlas": atlas, "zones": zones, "anchors": qw.COURSE_ANCHORS,
                 "stats": {"objects": total, "resolved": resolved, "art": len([a for a in self.art.values() if a]),
                           "skipped": dict(sorted(self.skipped.items(), key=lambda kv: -kv[1]))}}
        with open(os.path.join(self.out, "index.json"), "w", encoding="utf-8") as f:
            json.dump(index, f, indent=0)
        return index


def export_world(bp, out, families, unit_slugs, paint, scaled, load_tile, gid=None):
    """The exporter's world step. Returns the index (None when nothing is baked)."""
    root = chunks_root()
    gid = gid or latest_world(root)
    if gid is None:
        return None
    dst = os.path.join(out, "world", gid)
    os.makedirs(dst, exist_ok=True)
    wx = WorldExporter(bp, dst, families, unit_slugs, paint, scaled, load_tile)
    index = wx.export(gid, os.path.join(root, gid))
    with open(os.path.join(out, "world", "index.json"), "w", encoding="utf-8") as f:
        json.dump({"latest": gid, "worlds": [gid]}, f)
    return index
