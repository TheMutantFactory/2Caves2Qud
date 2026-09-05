"""Turn Qud's autotiled wall sprites into voxel wall models.

Every wall family in Qud ships as an 8-bit-neighbourhood set of 16x24 tiles
(`<stem>-<nesw bits>.png`: bit order N NE E SE S SW W NW, 1 = a wall there).
Each tile packs two views into one image: the ROOF seen from above in the
upper rows, and the 10-pixel-tall FRONT FACE in the bottom 10 rows. The
tiles are 2-colour masks (black = main colour, white = detail colour,
transparent = background) that the game paints per object.

The model built here, per family:

  * source = the FRONT-FACING RUN tile, bits 00100010 (walls east and west,
    nothing south, so the face shows with no end posts) — the piece a track
    barrier tiles along. The isolated tile 00000000 gives a second
    "-isolated" model with the end posts for a lone block.
  * a 16 (x, east) x 16 (y, north) x 10 (z, up) voxel block, one voxel per
    art pixel, flush-and-carve like the raves-of-qud renderer: the solid sits
    flush at the cell boundary and only BACKGROUND pixels recess.
      - front face rows carve inward CARVE voxels on the south side; the same
        art, mirrored, carves the north side;
      - the roof art (the cap rows above the face, minus a transparent
        separator row when the family has one) sits centred in the 16-deep
        footprint with a solid rim, and carves the top layer down where it is
        background;
      - materials: 1 main, 2 detail, 3 recess/core (carved floors and the
        interior).

Outputs, under <store>/walls/ (a derivative of Qud's art: never committed):

  <name>.vox            MagicaVoxel, palette 1/2/3 = the family's blueprint
                        colours (main / detail / darkened main)
  <name>-isolated.vox   the lone-block variant, when the family has one
  <name>-end-west.vox / -end-east.vox   the run's end pieces (single-neighbour
                        tiles 00100000 / 00000010; one mirrored from the other
                        when a family ships only one, "mirrored": true in the JSON)
  <name>.json           dims, sources, colours, and the grid as z-layers of
                        16 strings ('.' air, '1' '2' '3' materials) — what the
                        Godot loader reads; no .vox parser needed there
  <name>.png            preview: front | top | back, x8
  index.json            every family

Self-check (fails the run): the front elevation and roof mask re-read from
the built grid must equal the source art's opacity mask.

    python tools/wall2vox.py            # every family
    python tools/wall2vox.py wall_mud   # one (substring on the family name)
"""
import json
import os
import re
import struct
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qud_assets  # noqa: E402
import qud_blueprints  # noqa: E402
import qud_palette  # noqa: E402

W, D, H = 16, 16, 10          # voxel block: width (x), depth (y), height (z)
FACE_ROWS = 10                # the front face is the bottom 10 art rows
CARVE = 2                     # face gaps recess this many voxels
CAP_CARVE = 1                 # roof gaps recess this many voxels
RUN_BITS = "00100010"
ISOLATED_BITS = "00000000"
END_WEST_BITS = "00100000"    # a wall to the EAST only: this block is the run's west end
END_EAST_BITS = "00000010"    # a wall to the WEST only: the east end
WALL_FOLDERS = ("Walls", "Walls2", "Tiles", "Tiles2")
AIR, MAIN, DETAIL, CORE = 0, 1, 2, 3
TILE_RE = re.compile(r"^(?P<stem>.+)-(?P<bits>[01]{8})\.png$")


# ---------------------------------------------------------------- art

def classify(img):
    """RGBA image -> rows of material classes (0 bg, 1 main=black, 2 detail=white).
    Also returns how many opaque pixels were neither black nor white."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    rows = []
    odd = 0
    for y in range(h):
        row = []
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                row.append(AIR)
            elif r + g + b < 384:
                row.append(MAIN)
                if r + g + b > 96:
                    odd += 1
            else:
                row.append(DETAIL)
                if r + g + b < 672:
                    odd += 1
        rows.append(row)
    return rows, odd


def split_bands(rows):
    """-> (cap_rows, face_rows): the face is the last FACE_ROWS rows; the cap is
    everything above, less trailing fully-transparent separator rows."""
    face = rows[-FACE_ROWS:]
    cap = rows[:-FACE_ROWS]
    while cap and all(c == AIR for c in cap[-1]):
        cap.pop()
    return cap, face


# ---------------------------------------------------------------- build

def build(cap, face):
    """-> grid[z][y][x] of materials for one wall block."""
    grid = [[[CORE] * W for _ in range(D)] for _ in range(H)]
    # roof: cap rows centred in the depth, row 0 = north (y = D-1); rim stays main
    top = H - 1
    pad = (D - len(cap)) // 2
    for y in range(D):
        for x in range(W):
            grid[top][y][x] = MAIN
    for r, row in enumerate(cap):
        y = D - 1 - pad - r
        if not 0 <= y < D:
            continue
        for x in range(W):
            c = row[x]
            if c == AIR:
                for dz in range(CAP_CARVE):
                    grid[top - dz][y][x] = AIR
            else:
                grid[top][y][x] = c
    # front face (south, y = 0..CARVE-1) and its mirror on the back (north)
    for r, row in enumerate(face):
        z = H - 1 - r
        for x in range(W):
            c = row[x]
            for dy in range(CARVE):
                for xx, y in ((x, dy), (W - 1 - x, D - 1 - dy)):
                    grid[z][y][xx] = AIR if c == AIR else c
    # end columns wear the main colour where nothing else claimed them
    for z in range(H):
        for y in range(D):
            for x in (0, W - 1):
                if grid[z][y][x] == CORE:
                    grid[z][y][x] = MAIN
    return grid


def check(grid, cap, face):
    """Re-read the elevation and roof masks off the grid; -> list of mismatches."""
    bad = []
    for r, row in enumerate(face):
        z = H - 1 - r
        for x in range(W):
            want = row[x] != AIR
            got = grid[z][0][x] != AIR
            if want != got:
                bad.append(("front", x, r, want, got))
            got_b = grid[z][D - 1][W - 1 - x] != AIR
            if want != got_b:
                bad.append(("back", x, r, want, got_b))
    pad = (D - len(cap)) // 2
    for r, row in enumerate(cap):
        y = D - 1 - pad - r
        if y < CARVE or y >= D - CARVE:
            continue                      # the face shell wins there, by design
        for x in range(W):
            want = row[x] != AIR
            got = grid[H - 1][y][x] != AIR
            if want != got:
                bad.append(("top", x, r, want, got))
    return bad


# ---------------------------------------------------------------- output

def write_vox(path, grid, palette):
    voxels = []
    for z in range(H):
        for y in range(D):
            for x in range(W):
                m = grid[z][y][x]
                if m != AIR:
                    voxels.append(struct.pack("<4B", x, y, z, m))
    size = struct.pack("<3i", W, D, H)
    xyzi = struct.pack("<i", len(voxels)) + b"".join(voxels)
    rgba = bytearray()
    for i in range(256):
        c = palette.get(i + 1, (0, 0, 0))
        rgba += struct.pack("<4B", c[0], c[1], c[2], 255)

    def chunk(cid, content, children=b""):
        return cid + struct.pack("<ii", len(content), len(children)) + content + children

    body = chunk(b"SIZE", size) + chunk(b"XYZI", xyzi) + chunk(b"RGBA", bytes(rgba))
    with open(path, "wb") as f:
        f.write(b"VOX " + struct.pack("<i", 150) + chunk(b"MAIN", b"", body))
    return len(voxels)


def layers(grid):
    return [["".join(".123"[m] for m in grid[z][y]) for y in range(D)] for z in range(H)]


def preview(path, grid, palette, scale=8):
    def col(m):
        return palette[m] + (255,) if m else (0, 0, 0, 0)
    front = Image.new("RGBA", (W, H))
    back = Image.new("RGBA", (W, H))
    top = Image.new("RGBA", (W, D))
    for z in range(H):
        for x in range(W):
            for y in range(D):
                if grid[z][y][x] != AIR:
                    front.putpixel((x, H - 1 - z), col(grid[z][y][x]))
                    break
            for y in range(D - 1, -1, -1):
                if grid[z][y][x] != AIR:
                    back.putpixel((W - 1 - x, H - 1 - z), col(grid[z][y][x]))
                    break
    for y in range(D):
        for x in range(W):
            for z in range(H - 1, -1, -1):
                if grid[z][y][x] != AIR:
                    top.putpixel((x, D - 1 - y), col(grid[z][y][x]))
                    break
    gap = 2
    sheet = Image.new("RGBA", (W * 3 + gap * 2, D), (20, 20, 20, 255))
    sheet.paste(front, (0, 0))
    sheet.paste(top, (W + gap, 0))
    sheet.paste(back, (2 * (W + gap), 0))
    sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST).save(path)


# ---------------------------------------------------------------- blueprints

def family_colours(data_dir):
    """PaintedWall family stem -> {'main': letter, 'detail': letter, 'blueprints': [...]}
    from the blueprint XML, honouring Inherits for the Render part and the tag."""
    objs = {}
    bp_dir = os.path.join(data_dir, "ObjectBlueprints")
    if not os.path.isdir(bp_dir):
        return {}
    for fn in sorted(os.listdir(bp_dir)):
        if not fn.endswith(".xml"):
            continue
        try:
            root = qud_blueprints.parse_xml(os.path.join(bp_dir, fn))
        except ET.ParseError:
            continue
        for ob in root.iter("object"):
            name = ob.get("Name")
            if not name:
                continue
            o = objs.setdefault(name, {"inherits": ob.get("Inherits"), "render": {}, "tags": {}})
            for part in ob.findall("part"):
                if part.get("Name") == "Render":
                    o["render"].update({k: v for k, v in part.attrib.items() if k != "Name"})
            for tag in ob.findall("tag"):
                o["tags"][tag.get("Name")] = tag.get("Value")

    def lookup(name, kind, key, depth=0):
        o = objs.get(name)
        if o is None or depth > 20:
            return None
        v = o[kind].get(key)
        if v is not None:
            return v
        return lookup(o["inherits"], kind, key, depth + 1) if o["inherits"] else None

    out = {}
    for name in objs:
        fam = lookup(name, "tags", "PaintedWall")
        if not fam:
            continue
        main = qud_palette.fg_letter(lookup(name, "render", "TileColor")) or \
            qud_palette.fg_letter(lookup(name, "render", "ColorString"))
        detail = lookup(name, "render", "DetailColor")
        if not main:
            continue
        e = out.setdefault(fam, {"votes": {}, "blueprints": []})
        e["blueprints"].append(name)
        k = (main, (detail or "Y")[:1])
        e["votes"][k] = e["votes"].get(k, 0) + 1
    for fam, e in out.items():
        (main, detail), _ = max(e["votes"].items(), key=lambda kv: kv[1])
        e["main"], e["detail"] = main, detail
        del e["votes"]
    return out


# ---------------------------------------------------------------- main

def find_families(tiles_dir):
    fams = {}
    for folder in WALL_FOLDERS:
        d = os.path.join(tiles_dir, folder)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            m = TILE_RE.match(fn)
            if not m:
                continue
            key = folder + "/" + m.group("stem")
            fams.setdefault(key, {})[m.group("bits")] = os.path.join(d, fn)
    return fams


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    only = argv[0] if argv else None
    tiles_dir = qud_assets.path("tiles")
    if not os.path.isdir(tiles_dir):
        print("no tile store at %s — run tools/extract_qud.py first" % tiles_dir)
        return 2
    out_dir = qud_assets.path("walls")
    os.makedirs(out_dir, exist_ok=True)
    colours = family_colours(qud_assets.path("data"))
    fams = find_families(tiles_dir)
    stems = {}
    for key in fams:
        stems.setdefault(key.split("/", 1)[1], []).append(key)

    index = {}
    failures = 0
    skipped = []
    for key, variants in sorted(fams.items()):
        if only and only not in key:
            continue
        folder, stem = key.split("/", 1)
        name = stem if len(stems[stem]) == 1 else "%s_%s" % (folder, stem)
        sources = {}
        if RUN_BITS in variants:
            sources[""] = (RUN_BITS, variants[RUN_BITS])
        else:
            south_free = [b for b in sorted(variants) if b[4] == "0"]
            if south_free:
                sources[""] = (south_free[0], variants[south_free[0]])
        if ISOLATED_BITS in variants and sources.get("", (None,))[0] != ISOLATED_BITS:
            sources["-isolated"] = (ISOLATED_BITS, variants[ISOLATED_BITS])
        # END PIECES: the single-neighbour tiles. A family that ships only one of the
        # two gets the other by MIRRORING the art on x (a west end is an east end seen
        # from behind), flagged so the record says which is real.
        ends = {"-end-west": END_WEST_BITS, "-end-east": END_EAST_BITS}
        have = {suf: bits for suf, bits in ends.items() if bits in variants}
        for suf, bits in ends.items():
            if bits in variants:
                sources[suf] = (bits, variants[bits])
            elif have:
                other = next(iter(have.values()))
                sources[suf] = (bits, ("mirror", variants[other]))
        if not sources:
            skipped.append((key, "no south-facing tile among %d variants" % len(variants)))
            continue
        col = colours.get(stem, {"main": "y", "detail": "Y", "blueprints": []})
        main_rgb = qud_palette.rgb(col["main"])
        detail_rgb = qud_palette.rgb(col["detail"])
        palette = {MAIN: main_rgb, DETAIL: detail_rgb,
                   CORE: tuple(int(c * 0.55) for c in main_rgb)}
        entry = {"family": key, "name": name, "variants": len(variants),
                 "colours": {"main": col["main"], "detail": col["detail"],
                             "main_rgb": main_rgb, "detail_rgb": detail_rgb},
                 "blueprints": col["blueprints"][:12], "models": {}}
        for suffix, (bits, path) in sources.items():
            mirrored = isinstance(path, tuple)
            if mirrored:
                path = path[1]
            img = Image.open(path)
            if mirrored:
                img = ImageOps.mirror(img.convert("RGBA"))
            if img.width != W:
                skipped.append((key, "tile is %dx%d, not %d wide" % (img.width, img.height, W)))
                continue
            rows, odd = classify(img)
            cap, face = split_bands(rows)
            grid = build(cap, face)
            bad = check(grid, cap, face)
            if bad:
                failures += 1
                print("CHECK FAILED %s%s: %d mismatches, e.g. %s" % (name, suffix, len(bad), bad[:3]))
            base = os.path.join(out_dir, name + suffix)
            n = write_vox(base + ".vox", grid, palette)
            preview(base + ".png", grid, palette)
            model = {"source": os.path.relpath(path, tiles_dir), "bits": bits, "mirrored": mirrored,
                     "tile_size": [img.width, img.height], "cap_rows": len(cap),
                     "face_rows": len(face), "odd_pixels": odd, "voxels": n,
                     "size": [W, D, H], "layers": layers(grid)}
            with open(base + ".json", "w", encoding="utf-8") as f:
                json.dump({"family": key, "colours": entry["colours"], "materials":
                           {"1": "main", "2": "detail", "3": "core"}, **model}, f, indent=0)
            entry["models"][suffix or "run"] = {k: v for k, v in model.items() if k != "layers"}
            entry["models"][suffix or "run"]["files"] = [name + suffix + ext for ext in (".vox", ".json", ".png")]
        index[name] = entry
    with open(os.path.join(out_dir, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, indent=1, sort_keys=True)
    print("walls: %d families -> %s" % (len(index), out_dir))
    for key, why in skipped:
        print("  skipped %s: %s" % (key, why))
    if failures:
        print("%d model(s) FAILED the elevation check" % failures)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
