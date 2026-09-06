"""The sprite browser: every tiled Qud blueprint, painted in its colours, in a category tree
drawn from the blueprints' own inheritance, with where Qud puts it (which zone templates
hold it) and where we put it (which courses dress with it), and a placement helper that
writes the `dressing` entries for tools/qud_tracks.py.

  .venv/bin/python tools/sprite_browser.py --build      # thumbs + index into <store>/browser
  .venv/bin/python tools/sprite_browser.py --serve 8765 # then open http://localhost:8765/

Everything it writes lives in the asset store outside the repo (Qud's art is never shipped);
only tools/browser/index.html is ours.
"""
import argparse
import http.server
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qud_assets
import qud_blueprints as B
import qud_zones
from export_godot_assets import load_tile, paint, scaled  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def build():
    out = qud_assets.path("browser", mkdir=True)
    thumbs = os.path.join(out, "thumbs")
    os.makedirs(thumbs, exist_ok=True)
    bp = B.Blueprints(qud_assets.path("data"))
    # where Qud puts things: every zone template's object counts
    zones = {}
    data_dir = qud_assets.path("data")
    for fn in sorted(os.listdir(data_dir)):
        if fn.endswith(".rpm"):
            z = qud_zones.parse_zone(os.path.join(data_dir, fn))
            counts = {}
            for _x, _y, name in z["cells"]:
                counts[name] = counts.get(name, 0) + 1
            zones[fn[:-4]] = counts
    # where we put things: the courses' dressing
    courses, used = [], {}
    tj_path = os.path.join(REPO, "shared", "tracks.json")
    if os.path.exists(tj_path):
        with open(tj_path, encoding="utf-8") as f:
            tj = json.load(f)
        for t in (tj["tracks"] if isinstance(tj, dict) else tj):
            courses.append({"key": t["key"], "name": t.get("name", t["key"])})
            for d in t.get("dressing", []):
                if d.get("scatter"):
                    used.setdefault(d["scatter"], set()).add(t["key"])
                if d.get("zone"):
                    for name in zones.get(d["zone"], {}):
                        used.setdefault(name, set()).add(t["key"])
    unit_dir = qud_assets.path("godot", "units")
    items = []
    painted = 0
    for name in sorted(bp.names()):
        if bp.is_abstract(name):
            continue
        r = bp.render(name) or {}
        tile = r.get("Tile")
        if not tile:
            continue
        img = load_tile(tile)
        if img is None:
            continue
        main = B.color_letter(r, "TileColor") or B.color_letter(r, "ColorString") or "y"
        detail = B.color_letter(r, "DetailColor") or "Y"
        sl = B.slug(name)
        dest = os.path.join(thumbs, sl + ".png")
        if not os.path.exists(dest):
            scaled(paint(img, main, detail)).save(dest)
            painted += 1
        chain = [c["name"] for c in bp.chain(name)][1:]
        chain.reverse()                      # Object ... Parent
        kind = qud_zones.classify(bp, name)
        unit = sl if os.path.exists(os.path.join(unit_dir, sl + "_idle.png")) else ""
        zc = {z: c[name] for z, c in zones.items() if name in c}
        items.append({"name": name, "slug": sl, "chain": chain, "tile": tile, "main": main, "detail": detail,
                      "kind": kind, "w": img.width, "h": img.height, "unit": unit, "zones": zc,
                      "courses": sorted(used.get(name, [])), "display": r.get("DisplayName", "")})
    index = {"items": items, "zones": sorted(zones), "courses": courses}
    with open(os.path.join(out, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f)
    shutil.copy2(os.path.join(REPO, "tools", "browser", "index.html"), os.path.join(out, "index.html"))
    print("browser: %d sprites (%d painted now), %d zones, %d courses -> %s" % (len(items), painted, len(zones), len(courses), out))


def serve(port):
    root = qud_assets.path("browser")
    if not os.path.exists(os.path.join(root, "index.json")):
        build()
    else:
        shutil.copy2(os.path.join(REPO, "tools", "browser", "index.html"), os.path.join(root, "index.html"))
    os.chdir(root)
    handler = http.server.SimpleHTTPRequestHandler
    handler.log_message = lambda *a, **k: None
    print("sprite browser at http://localhost:%d/  (%s)" % (port, root), flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--serve", nargs="?", const=8765, type=int)
    a = ap.parse_args(argv)
    if a.build:
        build()
    if a.serve:
        serve(a.serve)
    if not a.build and not a.serve:
        ap.print_help()


if __name__ == "__main__":
    main()
