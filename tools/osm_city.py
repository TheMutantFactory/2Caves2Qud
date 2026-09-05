"""Fetch a city street grid and building footprints from OpenStreetMap and
write a compact map both builds can load.

    .venv/Scripts/python tools/osm_city.py chicago_loop
    .venv/Scripts/python tools/osm_city.py chicago_loop --preview   # also extracted/gis/<key>.png

Data: (c) OpenStreetMap contributors, ODbL 1.0 (https://www.openstreetmap.org/copyright).
The raw Overpass response is cached under extracted/gis/ (gitignored); the
processed shared/maps/<key>.json is committed with attribution.

Output units: world px, y down, origin at the bounding box's north-west
corner, px_per_m from the city definition (32 px per metre: a 15 m street is
480 px wide against a 60 px kart; too big for the Mode-7 surface, Godot only).
"""
import argparse
import json
import math
import os
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import rw3_locate  # noqa: E402

CITIES = {
    "chicago_loop": {
        "name": "Chicago Loop",
        "bbox": (41.8720, -87.6450, 41.8920, -87.6180),  # south, west, north, east
        "px_per_m": 32.0,
    },
}

OVERPASS = "https://overpass-api.de/api/interpreter"
HIGHWAYS = "primary|secondary|tertiary|residential|unclassified|living_street|primary_link|secondary_link|tertiary_link"
WIDTH_M = {"primary": 24, "secondary": 20, "tertiary": 18, "residential": 15, "unclassified": 15,
           "living_street": 12, "primary_link": 14, "secondary_link": 12, "tertiary_link": 12}


def fetch(city, cache):
    if os.path.exists(cache):
        with open(cache, "r", encoding="utf-8") as f:
            return json.load(f)
    s, w, n, e = city["bbox"]
    query = f"""[out:json][timeout:90];
(
  way["highway"~"^({HIGHWAYS})$"]({s},{w},{n},{e});
  way["building"]({s},{w},{n},{e});
);
(._;>;);
out body;"""
    req = urllib.request.Request(OVERPASS, data=("data=" + urllib.parse.quote(query)).encode(),
                                 headers={"User-Agent": "drift-wizard-3/0.1 (hobby kart game; contact via github)"})
    with urllib.request.urlopen(req, timeout=180) as r:
        data = json.load(r)
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    with open(cache, "w", encoding="utf-8") as f:
        json.dump(data, f)
    return data


def build(city, raw):
    s, w, n, e = city["bbox"]
    ppm = city["px_per_m"]
    lat0 = (s + n) / 2
    m_per_deg_lat = 111320.0
    m_per_deg_lon = 111320.0 * math.cos(math.radians(lat0))

    def to_px(lat, lon):
        return [round((lon - w) * m_per_deg_lon * ppm, 1), round((n - lat) * m_per_deg_lat * ppm, 1)]

    nodes = {}
    for el in raw["elements"]:
        if el["type"] == "node":
            nodes[el["id"]] = to_px(el["lat"], el["lon"])

    size = [int((e - w) * m_per_deg_lon * ppm), int((n - s) * m_per_deg_lat * ppm)]
    ways = [el for el in raw["elements"] if el["type"] == "way"]

    # count how many highway ways touch each node: >1 (or way ends) = intersection
    use = {}
    for el in ways:
        if "highway" in el.get("tags", {}):
            for nid in el["nodes"]:
                use[nid] = use.get(nid, 0) + 1

    streets = []
    buildings = []
    for el in ways:
        tags = el.get("tags", {})
        pts = [nodes[nid] for nid in el["nodes"] if nid in nodes]
        if len(pts) < 2:
            continue
        if "highway" in tags:
            kind = tags["highway"]
            # split the way at intersections so each street segment runs between two junctions
            seg_nodes = [el["nodes"][0]]
            for nid in el["nodes"][1:]:
                seg_nodes.append(nid)
                if use.get(nid, 0) > 1 or nid == el["nodes"][-1]:
                    p = [nodes[x] for x in seg_nodes if x in nodes]
                    if len(p) >= 2:
                        streets.append({
                            "name": tags.get("name", ""),
                            "kind": kind,
                            "oneway": tags.get("oneway", "no") == "yes",
                            "width": WIDTH_M.get(kind, 15) * ppm,
                            "from": seg_nodes[0],
                            "to": seg_nodes[-1],
                            "points": p,
                        })
                    seg_nodes = [nid]
        elif "building" in tags:
            levels = tags.get("building:levels")
            height_m = None
            if tags.get("height"):
                try:
                    height_m = float(str(tags["height"]).split()[0])
                except ValueError:
                    height_m = None
            if height_m is None:
                try:
                    height_m = float(levels) * 3.6 if levels else 12.0
                except ValueError:
                    height_m = 12.0
            if pts[0] == pts[-1]:
                pts = pts[:-1]
            if len(pts) >= 3:
                buildings.append({"name": tags.get("name", ""), "height": round(height_m * ppm, 1), "points": pts})

    streets = merge_pass_through(streets)
    buildings = drop_buildings_over_streets(buildings, streets)

    junctions = {}
    for st in streets:
        for nid in (st["from"], st["to"]):
            junctions.setdefault(nid, {"id": nid, "pos": nodes[nid], "streets": []})
    for i, st in enumerate(streets):
        junctions[st["from"]]["streets"].append(i)
        junctions[st["to"]]["streets"].append(i)

    return {
        "meta": {
            "name": city["name"],
            "source": "OpenStreetMap via Overpass API",
            "license": "ODbL 1.0, (c) OpenStreetMap contributors, https://www.openstreetmap.org/copyright",
            "bbox": [s, w, n, e],
            "px_per_m": ppm,
            "size": size,
        },
        "streets": streets,
        "junctions": list(junctions.values()),
        "buildings": buildings,
    }


def _point_in_poly(p, poly):
    x, y = p
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if x < xi:
                inside = not inside
    return inside


def drop_buildings_over_streets(buildings, streets):
    """Stations, platforms and multi-level road decks are tagged as buildings
    but sit on top of streets; a kart cannot drive through a box, so drop them."""
    boxes = []
    for b in buildings:
        xs = [x for x, _ in b["points"]]
        ys = [y for _, y in b["points"]]
        boxes.append((min(xs), min(ys), max(xs), max(ys)))
    bad = set()
    for st in streets:
        pts = st["points"]
        for i in range(len(pts) - 1):
            a, c = pts[i], pts[i + 1]
            length = math.dist(a, c)
            k = max(1, int(length / 40))
            for j in range(k + 1):
                t = j / k
                p = (a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t)
                for bi, (x0, y0, x1, y1) in enumerate(boxes):
                    if bi in bad or not (x0 <= p[0] <= x1 and y0 <= p[1] <= y1):
                        continue
                    if _point_in_poly(p, buildings[bi]["points"]):
                        bad.add(bi)
    kept = [b for i, b in enumerate(buildings) if i not in bad]
    print("dropped %d buildings that sit over streets" % len(bad))
    return kept


def merge_pass_through(streets):
    """Join street segments that meet end-to-end at a node no other street
    uses (OSM splits ways at address changes, bridges, etc.)."""
    changed = True
    while changed:
        changed = False
        ends = {}
        for i, st in enumerate(streets):
            ends.setdefault(st["from"], []).append(i)
            ends.setdefault(st["to"], []).append(i)
        for nid, idx in ends.items():
            if len(idx) != 2 or idx[0] == idx[1]:
                continue
            a, b = streets[idx[0]], streets[idx[1]]
            if a is None or b is None or a["oneway"] != b["oneway"] or a["kind"] != b["kind"]:
                continue
            # orient so a ends at nid and b starts at nid
            if a["from"] == nid:
                a = {**a, "from": a["to"], "to": a["from"], "points": list(reversed(a["points"]))}
            if b["to"] == nid:
                b = {**b, "from": b["to"], "to": b["from"], "points": list(reversed(b["points"]))}
            if a["to"] != nid or b["from"] != nid or a["from"] == b["to"]:
                continue
            merged = {**a, "to": b["to"], "points": a["points"] + b["points"][1:],
                      "name": a["name"] or b["name"], "width": max(a["width"], b["width"])}
            streets[idx[0]] = merged
            streets[idx[1]] = None
            streets = [x for x in streets if x is not None]
            changed = True
            break
    return streets


def preview(city_map, path):
    from PIL import Image, ImageDraw
    w, h = city_map["meta"]["size"]
    scale = 1600.0 / max(w, h)
    img = Image.new("RGB", (int(w * scale) + 1, int(h * scale) + 1), (14, 12, 18))
    d = ImageDraw.Draw(img)
    for b in city_map["buildings"]:
        pts = [(x * scale, y * scale) for x, y in b["points"]]
        shade = min(200, 40 + int(b["height"] / 8 / 4))
        d.polygon(pts, fill=(shade, shade - 6, shade + 8))
    for st in city_map["streets"]:
        pts = [(x * scale, y * scale) for x, y in st["points"]]
        d.line(pts, fill=(200, 190, 170), width=max(1, int(st["width"] * scale)))
    for j in city_map["junctions"]:
        x, y = j["pos"]
        if len(j["streets"]) >= 3:
            d.ellipse((x * scale - 3, y * scale - 3, x * scale + 3, y * scale + 3), fill=(229, 28, 35))
    img.save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("city", choices=sorted(CITIES))
    ap.add_argument("--preview", action="store_true")
    args = ap.parse_args()
    city = CITIES[args.city]
    repo = rw3_locate.repo_root()
    cache = os.path.join(repo, "extracted", "gis", args.city + ".overpass.json")
    raw = fetch(city, cache)
    city_map = build(city, raw)
    out_dir = os.path.join(repo, "shared", "maps")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, args.city + ".json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(city_map, f, separators=(",", ":"))
    m = city_map["meta"]
    print("%s: %d streets, %d junctions, %d buildings, world %dx%d px (%d m x %d m), %s -> %d KB" % (
        m["name"], len(city_map["streets"]), len(city_map["junctions"]), len(city_map["buildings"]),
        m["size"][0], m["size"][1], m["size"][0] / m["px_per_m"], m["size"][1] / m["px_per_m"],
        os.path.relpath(out, repo), os.path.getsize(out) // 1024))
    if args.preview:
        p = os.path.join(repo, "extracted", "gis", args.city + ".png")
        preview(city_map, p)
        print("preview", p)


if __name__ == "__main__":
    main()
