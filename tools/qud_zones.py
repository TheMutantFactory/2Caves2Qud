"""Qud's authored zones as set dressing for the courses.

Qud ships its hand-built places as ZONE TEMPLATES (StreamingAssets/Base/<Zone>.rpm): an
80 x 25 grid of cells, each holding the blueprint names standing there. Joppa's has its
brinestalk huts, the watervine farms, the pond, the torchposts, the villagers. This module
reads a template and turns it into what the engine can stand beside a course:

- walls  -> voxel wall blocks (the family the blueprint's tile names, e.g. wall_brinestalk)
- liquids (ponds, puddles) -> flat water cells
- creatures -> the unit sprites the extractor already made (units/<slug>_idle.png)
- everything else with a tile (plants, trees, furniture, doors, signs) -> a painted
  billboard tile written to dressing/<slug>.png
- floors, paths and widgets are skipped (the course draws its own ground)

Output: data/zones.json ({zone: {w, h, objects: [{x, y, name, kind, art, fam}]}}) and
data/dressing.json ({blueprint: {kind, art, fam}}) for the courses' scatter entries.
"""
import os
import xml.etree.ElementTree as ET

import qud_assets
from qud_blueprints import slug, color_letter

SKIP_CHAIN = ("Floor", "CosmeticObject", "Widget")
SKIP_NAMES = ("Dirty", "DaylightWidget")


def parse_zone(path):
    root = ET.parse(path).getroot()
    w, h = int(root.get("Width", 80)), int(root.get("Height", 25))
    cells = []
    for cell in root.iter("cell"):
        x, y = int(cell.get("X")), int(cell.get("Y"))
        for o in cell.findall("object"):
            cells.append((x, y, o.get("Name")))
    return {"w": w, "h": h, "cells": cells}


def classify(bp, name):
    """wall | liquid | creature | prop | skip, by the blueprint's inheritance."""
    if name in SKIP_NAMES or name.startswith("Landmark"):
        return "skip"
    try:
        chain = [c["name"] for c in bp.chain(name)]
    except Exception:
        return "skip"
    if any(c in SKIP_CHAIN for c in chain):
        return "skip"
    if "Wall" in chain and "Fence" not in name:
        return "wall"
    if any(c in ("Water", "Liquid", "LiquidVolume", "BaseLiquid") for c in chain) or name in ("Pond", "PondDown"):
        return "liquid"
    if "Creature" in chain:
        return "creature"
    r = bp.render(name) or {}
    return "prop" if r.get("Tile") else "skip"


def wall_family(bp, name, families):
    """The voxel family for a wall blueprint: its tile's stem when it is one of ours
    (Walls/wall_brinestalk-00000000.png -> wall_brinestalk), else by its kind."""
    r = bp.render(name) or {}
    tile = (r.get("Tile") or "").replace("\\", "/")
    stem = os.path.basename(tile).split("-")[0].split(".")[0].lower()
    if stem in families.values():
        return stem
    chain = [c["name"] for c in bp.chain(name)]
    if any("Metal" in c for c in chain):
        return families.get("metal", "")
    if any("Wood" in c for c in chain):
        return families.get("brinestalk", "")
    if any(c in ("BaseWallStone", "StoneWall") or "Marble" in c for c in chain):
        return families.get("marble", "")
    return ""


class DressingExporter:
    def __init__(self, bp, out, families, unit_slugs, paint, scaled, load_tile):
        self.bp, self.out, self.families = bp, out, families
        self.unit_slugs = unit_slugs        # blueprint name -> unit slug with an idle strip
        self.paint, self.scaled, self.load_tile = paint, scaled, load_tile
        self.arts = {}                      # blueprint -> {kind, art, fam}
        os.makedirs(os.path.join(out, "dressing"), exist_ok=True)

    def art_for(self, name):
        if name in self.arts:
            return self.arts[name]
        kind = classify(self.bp, name)
        entry = {"kind": kind, "art": "", "fam": ""}
        if kind == "wall":
            entry["fam"] = wall_family(self.bp, name, self.families)
            if not entry["fam"]:
                kind = "prop"           # no voxel family: stand its tile up instead
                entry["kind"] = kind
        if kind == "creature":
            u = self.unit_slugs.get(name)
            if u:
                entry["art"] = "unit:" + u
            else:
                kind = "prop"
                entry["kind"] = kind
        if kind == "prop":
            r = self.bp.render(name) or {}
            img = self.load_tile(r.get("Tile"))
            if img is None:
                entry["kind"] = "skip"
            else:
                main = color_letter(r, "TileColor") or color_letter(r, "ColorString") or "y"
                detail = color_letter(r, "DetailColor") or "Y"
                fn = slug(name) + ".png"
                self.scaled(self.paint(img, main, detail)).save(os.path.join(self.out, "dressing", fn))
                entry["art"] = "dressing/" + fn
        self.arts[name] = entry
        return entry

    def zone(self, zone_name):
        z = parse_zone(qud_assets.path("data", zone_name + ".rpm"))
        objects = []
        for x, y, name in z["cells"]:
            e = self.art_for(name)
            if e["kind"] == "skip":
                continue
            objects.append({"x": x, "y": y, "name": name, "kind": e["kind"], "art": e["art"], "fam": e["fam"]})
        return {"w": z["w"], "h": z["h"], "objects": objects}
