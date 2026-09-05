"""Fill the racing engine's asset contract from the Qud asset store.

The engine (godot/, from drift-wizard-3) reads everything through the QUD
autoload at res://qud/. This writes <store>/godot/ from the extracted Qud
assets and links godot/qud to it, so the project boots on Caves of Qud art
and sound without any of it entering the repo.

    units/<unit>_idle.png       creature tiles (2-bit art painted with the
                                blueprint's TileColor/DetailColor, x3 nearest),
                                plus the player castes from Subtypes.xml
    manifest.json               units -> {frame_size, idle_frames, ...}
    data/monsters.json          racers: name, unit, hp, band, flying (from the
                                blueprints' Level and Hitpoints stats) and their
                                "spells": mutations + carried weapons as abilities
                                (tools/qud_mutations.py)
    data/spells.json            Qud's grenades, guns, thrown/melee weapons and tonics
                                as the engine's action-bar records (tools/qud_items.py)
    icons/<stem>.png            their tiles, plus the six arcade pickup icons
    data/equipment.json         empty for now (artifacts later)
    tiles/track_<key>_road.png, track_<key>_ground.png   opaque tileable ground
                                per shared/tracks.json track, Qud floor tiles
                                composited on the track colours
    tiles/<ts>_wall_1..4.png    barricade textures: a wall family's front faces
    tiles/floor_<ts>.png, chasm_<x>.png, item_*.png, portal_*.png, cloud_*.png
    effects/*.png (6-frame strips), effects/proj/*.png, status/stun.png
                                procedural for now, Qud-coloured
    sfx/<engine name>.ogg       the engine's sound cues mapped onto Qud clips
    sfx/<clip>.ogg + variants.json   every take of every sound the items, mutations
                                and pickups name (their blueprints' MissileFireSound,
                                SwingSound, ThrownSound, DetonatedSound, ImpactSound
                                tags); Audio.play picks a take at random
    music/battle_1..12.ogg, lose_theme.ogg, victory_theme.ogg, title_theme.ogg
    shared/                     a copy of shared/ (tracks, tuning, overrides, maps)
    walls/                      a link to the store's voxel wall models (wall2vox.py);
                                manifest "wall_families" says which family each tileset uses

Run after tools/extract_qud.py (and again after changing shared/):

    .venv/bin/python tools/export_godot_assets.py
"""
import argparse
import json
import math
import os
import re
import shutil
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qud_assets  # noqa: E402
import qud_blueprints as B  # noqa: E402
import qud_palette  # noqa: E402

SCALE = 3                    # Qud tiles are 16x24; the engine was built around 60px wizards
FRAME_H = 24 * SCALE

# engine tileset name -> (Qud floor tile, main, detail, wall family stem)
TILESETS = {
    "brick":   ("Tiles/sw_floor_brick1.bmp",  "w", "y", "wall_brick"),
    "volcano": ("Tiles/sw_floor_chunk1.bmp",  "r", "R", "wall_rock"),
    "ice":     ("Tiles/sw_floor_diamonds.bmp", "C", "Y", "wall_crystal1"),
    "stone":   ("Tiles/sw_floor_brickb1.bmp", "y", "K", "wall_marble"),
    "moss":    ("Tiles/sw_floor_dirty1.bmp",  "g", "G", "wall_mud"),
}
CHASMS = {"lava": ("Tiles/sw_floor_dirty2.bmp", "R", "r"), "water": ("Tiles/sw_floor_dirty3.bmp", "B", "b")}
ITEM_TILES = {
    "item_mana_orb": ("Items/ms_smooth_gemstone.bmp", "B", "C"),
    "item_spell_scroll": ("Items/sw_book_1.bmp", "w", "Y"),
    "item_ruby_heart": ("Items/ms_heart.bmp", "R", "r"),
    "item_bookshelf": ("Items/sw_bookshelf1.bmp", "w", "y"),
    "item_trinket": ("Items/sw_grenade_mki.bmp", "y", "G"),
    "portal_dormant_portal": ("Walls/sw_wall_archgate-00000000.png", "c", "C"),
}
EFFECT_COLOURS = {
    "lightning_0": "W", "translocation": "M", "blood": "R", "ice": "C", "dark": "m",
    "shield_expire": "B", "fang": "Y", "physical": "y", "arcane": "M", "fire": "O",
    "heal": "G", "buff_apply": "W", "shield_apply": "B", "poison": "g", "holy": "Y",
}
# engine sound cue -> regexes tried in order over the Qud clip names
SOUNDS = {
    "learn_spell": [r"^ui_notification-001$", r"^ui_notification"],
    "menu_abort": [r"^ui_invalid$", r"^ui_popup_close"],
    "sorcery": [r"sfx_ability_mutation_.*pyrokinesis", r"sfx_ability_mutation", r"sfx_ability"],
    "teleport": [r"teleport_involuntary_in-001", r"teleport"],
    "item_pickup": [r"sfx_interact_.*pickup", r"takeItem", r"sfx_interact_generic", r"sfx_interact"],
    "death_enemy": [r"sfx_death_generic", r"_death_"],
    "victory_level": [r"^ui_achievement_unlock$", r"ui_trade_complete"],
    "start_level": [r"^ui_page_change$", r"ui_popup_open"],
    "shield_break": [r"^shatter$", r"^breakage$"],
    "hit_player": [r"hitOrganic-01", r"hitOrganic"],
    "death_player": [r"^ui_notification_death$", r"_death_"],
    "death_boss": [r"highExplosive_explode-001", r"explode"],
    "summon": [r"^svardym_plop$", r"teleport"],
    "hit_enemy": [r"hitOrganic-02", r"hitOrganic"],
    "enemy": [r"humanoid_generic_vo_attack", r"vo_attack"],
}
MUSIC = ["Overworld", "Substrate", "A New World", "Moonstair", "Complex Being", "Stoic Porridge",
         "Onward", "Pilgrims Path", "Golgotha", "Stilt", "Deep Dawn", "Lazarus"]
THEMES = {"lose_theme": "Among The Tombs of Eaters", "victory_theme": "Arrival of The Official Party",
          "title_theme": "Cave Addendum"}
FLYING_HINTS = ("bird", "bat", "moth", "hawk", "wasp", "fly", "wing", "crow", "vulture", "dragonfly", "harpy", "eagle")


def log(msg):
    print(msg, flush=True)


# ---------------------------------------------------------------- art

def paint(img, main, detail):
    """Qud's 2-bit mask -> colour: black pixels take main, white take detail.
    Polychrome tiles (the newer full-colour art) are left as drawn."""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    two_bit = True
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a >= 128 and 96 < r + g + b < 672:
                two_bit = False
                break
        if not two_bit:
            break
    if not two_bit:
        return img
    mc, dc = qud_palette.rgb(main), qud_palette.rgb(detail)
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                px[x, y] = (0, 0, 0, 0)
            elif r + g + b < 384:
                px[x, y] = mc + (255,)
            else:
                px[x, y] = dc + (255,)
    return img


def scaled(img, k=SCALE):
    return img.resize((img.width * k, img.height * k), Image.NEAREST)


def load_tile(qpath):
    f = qud_assets.tile_file(qpath) if qpath else None
    return Image.open(f) if f and os.path.exists(f) else None


def tile_or_blank(qpath, main, detail, size=(16, 24)):
    im = load_tile(qpath)
    if im is None:
        im = Image.new("RGBA", size, (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rectangle([2, 2, size[0] - 3, size[1] - 3], outline=qud_palette.rgb(main) + (255,))
        return im
    return paint(im, main, detail)


def tileable(img, base_rgb, size=96):
    """An opaque, tileable square: the (painted) floor tile repeated over a base colour."""
    out = Image.new("RGBA", (size, size), tuple(base_rgb) + (255,))
    t = scaled(img, 2)
    for y in range(0, size, t.height):
        for x in range(0, size, t.width):
            out.alpha_composite(t, (x, y))
    out.putalpha(255)
    return out


def effect_strip(name, letter, frames=6, size=48):
    """A 6-frame burst: an expanding ring in the effect's colour, fading."""
    col = qud_palette.rgb(letter)
    strip = Image.new("RGBA", (size * frames, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(strip)
    c = size / 2.0
    for i in range(frames):
        t = (i + 1) / frames
        r = 4 + t * (c - 4)
        a = int(255 * (1.0 - t * 0.85))
        x0 = i * size + c
        d.ellipse([x0 - r, c - r, x0 + r, c + r], outline=col + (a,), width=max(2, int(6 * (1 - t)) + 2))
        if name in ("fang", "physical", "blood"):
            for k in range(6):
                ang = k * math.pi / 3 + t * 0.7
                d.line([x0 + math.cos(ang) * r * 0.4, c + math.sin(ang) * r * 0.4,
                        x0 + math.cos(ang) * r, c + math.sin(ang) * r], fill=col + (a,), width=2)
    return strip


def stun_icon(size=24):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col = qud_palette.rgb("W") + (255,)
    for k in range(3):
        cx = 4 + k * 8
        d.polygon([(cx, 2), (cx + 2, 7), (cx + 7, 7), (cx + 3, 10), (cx + 5, 15), (cx, 12), (cx - 5, 15), (cx - 3, 10), (cx - 7, 7), (cx - 2, 7)], fill=col)
    return im


def projectile(name, letter):
    col = qud_palette.rgb(letter)
    im = Image.new("RGBA", (30, 12), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if name == "fire_ball":
        d.ellipse([4, 1, 26, 11], fill=col + (255,))
        d.ellipse([10, 3, 22, 9], fill=qud_palette.rgb("W") + (255,))
    else:
        d.line([2, 6, 28, 6], fill=col + (255,), width=4)
        d.ellipse([22, 2, 30, 10], fill=qud_palette.rgb("Y") + (255,))
    return im


# ---------------------------------------------------------------- units

def export_units(bp, out, manifest, abilities=None):
    units_dir = os.path.join(out, "units")
    os.makedirs(units_dir, exist_ok=True)
    monsters = []
    n = 0
    seen_units = set()
    for name in bp.names():
        if bp.is_abstract(name):
            continue
        r = bp.render(name)
        if not r.get("Tile"):
            continue
        o = bp.get(name)
        if "Creature" not in o["chain"] and o["parts"].get("Brain") is None:
            continue
        if o["tags"].get("Role") == "Zone" or "Zone" in name:
            continue
        img = load_tile(r["Tile"])
        if img is None or img.width != 16:
            continue
        unit = B.slug(name)
        if unit in seen_units or unit == "player":
            continue
        seen_units.add(unit)
        main = B.color_letter(r, "TileColor") or B.color_letter(r, "ColorString") or "y"
        detail = B.color_letter(r, "DetailColor") or "Y"
        scaled(paint(img, main, detail)).save(os.path.join(units_dir, unit + "_idle.png"))
        manifest["units"][unit] = {"frame_size": img.height * SCALE, "idle_frames": 1, "attack_frames": 1, "radius": 0}
        level = bp.stat_int(name, "Level", 1) or 1
        hp = bp.stat_int(name, "Hitpoints", 20) or 20
        band = max(1, min(9, 1 + (level - 1) // 4))
        lname = name.lower()
        flying = any(h in lname for h in FLYING_HINTS) or "Flying" in o["parts"] or o["tags"].get("Flying") is not None
        spells = []
        if abilities is not None:
            spells, wings = abilities.abilities(name)
            flying = flying or wings
        monsters.append({"name": name, "asset": ["char", unit], "asset_exists": True,
                         "max_hp": float(hp), "radius": 0, "flying": bool(flying), "level": level,
                         "roles": [{"role": "spawn", "difficulty_band": band, "tier": "easy" if band <= 3 else ("med" if band <= 6 else "hard")}],
                         "spells": spells, "tile": r["Tile"], "colors": [main, detail]})
        n += 1
    return n, monsters


def export_players(data_dir, out, manifest):
    """`player` and the `player_<caste>` skins the Wardrobe lists, from Subtypes.xml."""
    units_dir = os.path.join(out, "units")
    subs = []
    p = os.path.join(data_dir, "Subtypes.xml")
    if os.path.exists(p):
        for el in B.parse_xml(p).iter():
            if el.get("Tile") and el.get("Name"):
                subs.append((el.get("Name"), el.get("Tile"), el.get("DetailColor") or "Y"))
    default = None
    for name, tile, detail in subs:
        img = load_tile(tile)
        if img is None:
            continue
        unit = "player_" + B.slug(name)
        scaled(paint(img, "Y", detail)).save(os.path.join(units_dir, unit + "_idle.png"))
        manifest["units"][unit] = {"frame_size": img.height * SCALE, "idle_frames": 1, "attack_frames": 1, "radius": 0}
        if default is None or name == "Marauder":
            default = (img, detail)
    if default is None:
        img = load_tile("Creatures/sw_farmer.bmp") or Image.new("RGBA", (16, 24), (255, 255, 255, 255))
        default = (img, "Y")
    img, detail = default
    scaled(paint(img, "Y", detail)).save(os.path.join(units_dir, "player_idle.png"))
    manifest["units"]["player"] = {"frame_size": img.height * SCALE, "idle_frames": 1, "attack_frames": 1, "radius": 0}
    return len(subs)


# ---------------------------------------------------------------- items

# The arcade pickups (Items.KINDS keys) wear these Qud tiles as icons.
PICKUP_ICONS = {
    "fireball": ("Items/sw_grenade_mki.bmp", "W", "Y"),
    "lightning_bolt": ("items/sw_techrifle_1.bmp", "C", "Y"),
    "blink": ("Items/sw_recoiler.bmp", "c", "C"),
    "lightning_form": ("Items/sw_injector.bmp", "R", "Y"),
    "freeze": ("Items/sw_grenade_mki.bmp", "C", "Y"),
    "wolf": ("Creatures/sw_snapjaw.bmp", "w", "R"),
}


def write_icons(out, icons):
    icons_dir = os.path.join(out, "icons")
    os.makedirs(icons_dir, exist_ok=True)
    n = 0
    for stem, (tile, main, detail) in icons.items():
        img = load_tile(tile)
        if img is None:
            continue
        scaled(paint(img, main, detail)).save(os.path.join(icons_dir, stem + ".png"))
        n += 1
    return n


def export_items(bp, out, sounds=None):
    import qud_items
    ib = qud_items.ItemBuilder(bp, lambda t: qud_assets.tile_file(t) is not None, sounds)
    recs = ib.build()
    os.makedirs(os.path.join(out, "data"), exist_ok=True)
    with open(os.path.join(out, "data", "spells.json"), "w", encoding="utf-8") as f:
        json.dump(recs, f, indent=0)
    n = write_icons(out, ib.icons)
    for key, (tile, main, detail) in PICKUP_ICONS.items():
        scaled(tile_or_blank(tile, main, detail)).save(os.path.join(out, "icons", key + ".png"))
    return recs, n


# ---------------------------------------------------------------- tiles

def wall_faces(family, main, detail, tiles_dir):
    """Four front faces of a wall family (different neighbourhoods), x3."""
    out = []
    for folder in ("Walls", "Tiles", "Walls2", "Tiles2"):
        d = os.path.join(tiles_dir, folder)
        if not os.path.isdir(d):
            continue
        cands = sorted(f for f in os.listdir(d) if f.startswith(family + "-") and f.endswith(".png"))
        if not cands:
            continue
        pref = [c for c in cands if c.endswith(("00100010.png", "00000010.png", "00100000.png", "00000000.png"))]
        for fn in (pref + cands)[:4]:
            img = paint(Image.open(os.path.join(d, fn)), main, detail)
            out.append(scaled(img.crop((0, img.height - 10, 16, img.height))))
        break
    return out


def export_track_tiles(out, manifest, tiles_dir):
    tdir = os.path.join(out, "tiles")
    os.makedirs(tdir, exist_ok=True)
    with open(os.path.join(qud_assets.path("godot"), "shared", "tracks.json"), "r", encoding="utf-8") as f:
        tracks = json.load(f)["tracks"]
    manifest["track_tiles"] = {}
    manifest["tiles"] = []
    done_walls = set()
    for t in tracks:
        key = t["key"]
        ts = t["floor"][2] if len(t.get("floor", [])) > 2 else "brick"
        floor_q, fm, fd, fam = TILESETS.get(ts, TILESETS["brick"])
        floor = tile_or_blank(floor_q, fm, fd)
        tileable(floor, t.get("road_color", [80, 76, 70])).save(os.path.join(tdir, "track_%s_road.png" % key))
        off = t.get("offroad", [])
        if len(off) > 2 and off[1] == "chasm":
            ch = off[2].replace("chasm_", "")
            oq, om, od = CHASMS.get(ch, CHASMS["water"])
        else:
            ots = off[2] if len(off) > 2 else "moss"
            oq, om, od, _ = TILESETS.get(ots, TILESETS["moss"])
        ground = tile_or_blank(oq, om, od)
        tileable(ground, t.get("ground", [8, 12, 6])).save(os.path.join(tdir, "track_%s_ground.png" % key))
        manifest["track_tiles"][key] = {"road": "track_%s_road.png" % key, "ground": "track_%s_ground.png" % key, "tile_px": 96}
        wts = t["walls"][2] if len(t.get("walls", [])) > 2 else ts
        if wts not in done_walls:
            done_walls.add(wts)
            _, wm, wd, wfam = TILESETS.get(wts, TILESETS["brick"])
            faces = wall_faces(wfam, wm, wd, tiles_dir)
            for i, face in enumerate(faces):
                face.save(os.path.join(tdir, "%s_wall_%d.png" % (wts, i + 1)))
                manifest["tiles"].append({"file": "%s_wall_%d.png" % (wts, i + 1), "tileset": wts, "kind": "wall"})
    for ts, (q, m, d, _) in TILESETS.items():
        tileable(tile_or_blank(q, m, d), (44, 42, 48)).save(os.path.join(tdir, "floor_%s.png" % ts))
    for ch, (q, m, d) in CHASMS.items():
        tileable(tile_or_blank(q, m, d), (0, 0, 0)).save(os.path.join(tdir, "chasm_%s.png" % ch))
    for name, (q, m, d) in ITEM_TILES.items():
        scaled(tile_or_blank(q, m, d)).save(os.path.join(tdir, name + ".png"))
    for cloud, letter in (("ice", "C"), ("thunder", "W"), ("rainstorm", "B")):
        im = Image.new("RGBA", (48, 32), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        col = qud_palette.rgb(letter)
        for cx, cy, r in ((14, 18, 10), (26, 14, 12), (36, 20, 9)):
            dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (200,))
        im.save(os.path.join(tdir, "cloud_%s_cloud.png" % cloud))
    return len(tracks)


def export_effects(out):
    edir = os.path.join(out, "effects")
    os.makedirs(os.path.join(edir, "proj"), exist_ok=True)
    for name, letter in EFFECT_COLOURS.items():
        effect_strip(name, letter).save(os.path.join(edir, name + ".png"))
    projectile("fire_ball", "O").save(os.path.join(edir, "proj", "fire_ball.png"))
    projectile("arcane_bolt", "M").save(os.path.join(edir, "proj", "arcane_bolt.png"))
    os.makedirs(os.path.join(out, "status"), exist_ok=True)
    stun_icon().save(os.path.join(out, "status", "stun.png"))
    os.makedirs(os.path.join(out, "icons"), exist_ok=True)
    os.makedirs(os.path.join(out, "equipment"), exist_ok=True)
    return len(EFFECT_COLOURS)


# ---------------------------------------------------------------- sound

def link_or_copy(src, dst):
    if os.path.lexists(dst):
        os.remove(dst)
    try:
        os.symlink(src, dst)
    except (OSError, NotImplementedError, AttributeError):
        shutil.copy2(src, dst)


def export_sounds(out):
    sfx_src = qud_assets.path("sfx")
    with open(os.path.join(sfx_src, "index.json"), "r", encoding="utf-8") as f:
        clips = json.load(f)
    names = sorted(clips)
    sdir = os.path.join(out, "sfx")
    mdir = os.path.join(out, "music")
    os.makedirs(sdir, exist_ok=True)
    os.makedirs(mdir, exist_ok=True)
    mapping = {}
    for cue, pats in SOUNDS.items():
        pick = None
        for pat in pats:
            rx = re.compile(pat)
            for n in names:
                if rx.search(n):
                    pick = n
                    break
            if pick:
                break
        if pick:
            link_or_copy(os.path.join(sfx_src, clips[pick]["file"]), os.path.join(sdir, cue + ".ogg"))
            mapping[cue] = pick
    have = [m for m in MUSIC if m in clips]
    for i in range(12):
        if have:
            src = have[i % len(have)]
            link_or_copy(os.path.join(sfx_src, clips[src]["file"]), os.path.join(mdir, "battle_%d.ogg" % (i + 1)))
            mapping["battle_%d" % (i + 1)] = src
    for cue, track in THEMES.items():
        if track in clips:
            link_or_copy(os.path.join(sfx_src, clips[track]["file"]), os.path.join(mdir, cue + ".ogg"))
            mapping[cue] = track
    with open(os.path.join(sdir, "mapping.json"), "w", encoding="utf-8") as f:
        json.dump(mapping, f, indent=1, sort_keys=True)
    return mapping


# The arcade pickups' cast sounds (Items.use plays "pickup_<kind>"), first existing wins.
PICKUP_SOUNDS = {
    "fireball": ["sfx_throwing_generic_throw"], "lightning_bolt": ["sfx_missile_laserRifle_fire"],
    "blink": ["sfx_ability_mutation_phase", "sfx_ability_teleport_involuntary_in"],
    "lightning_form": ["sfx_ability_injectorTube_inject"], "freeze": ["sfx_throwing_generic_throw"],
    "wolf": ["sfx_humanoid_generic_vo_attack"],
}


def export_sound_takes(out, sounds, items, monsters):
    """Every sound the items, mutations and pickups name: link all of Qud's takes
    (sfx_x-001..-005) into sfx/ and write sfx/variants.json name -> [clip names],
    which Audio.play picks from at random. Aliases (pickup_<kind>) map the same way."""
    sdir = os.path.join(out, "sfx")
    names = {}
    for rec in items:
        for k in ("sound", "hit_sound"):
            b = rec.get("kart", {}).get(k)
            if b:
                names[b] = b
    for m in monsters:
        for rec in m.get("spells", []):
            for k in ("sound", "hit_sound"):
                b = rec.get("kart", {}).get(k)
                if b:
                    names[b] = b
    for kind, cands in PICKUP_SOUNDS.items():
        b = sounds.first(*cands)
        if b:
            names["pickup_" + kind] = b
    variants = {}
    linked = set()
    for name, base in names.items():
        takes = sounds.bases.get(base, [])
        if not takes:
            continue
        variants[name] = takes
        for clip in takes:
            if clip in linked:
                continue
            linked.add(clip)
            link_or_copy(os.path.join(qud_assets.path("sfx"), sounds.files[clip]), os.path.join(sdir, clip + ".ogg"))
    with open(os.path.join(sdir, "variants.json"), "w", encoding="utf-8") as f:
        json.dump(variants, f, indent=0, sort_keys=True)
    return len(linked), len(variants)


# ---------------------------------------------------------------- link

def link_project(repo, out):
    """godot/qud -> <store>/godot (symlink; a junction on Windows; else a copy warning)."""
    link = os.path.join(repo, "godot", "qud")
    if os.path.islink(link) or os.path.exists(link):
        if os.path.islink(link):
            os.remove(link)
        else:
            log("godot/qud exists and is not a link; leaving it alone")
            return
    try:
        os.symlink(out, link, target_is_directory=True)
    except OSError:
        if sys.platform.startswith("win"):
            import subprocess
            subprocess.check_call(["cmd", "/c", "mklink", "/J", link, out])
        else:
            raise
    log("linked godot/qud -> %s" % out)


# ---------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", help="default: <store>/godot")
    args = ap.parse_args(argv)
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    store = qud_assets.store_dir()
    if not os.path.isdir(qud_assets.path("tiles")):
        log("no asset store at %s — run tools/extract_qud.py first" % store)
        return 2
    out = args.out or os.path.join(store, "godot")
    os.makedirs(out, exist_ok=True)
    log("store:  %s\noutput: %s" % (store, out))

    # shared/ first: the track export reads it back from the output
    os.makedirs(os.path.join(out, "shared", "maps"), exist_ok=True)
    for fn in os.listdir(os.path.join(repo, "shared")):
        if fn.endswith(".json"):
            shutil.copy2(os.path.join(repo, "shared", fn), os.path.join(out, "shared", fn))
    maps = os.path.join(repo, "shared", "maps")
    if os.path.isdir(maps):
        for fn in os.listdir(maps):
            if fn.endswith(".json"):
                shutil.copy2(os.path.join(maps, fn), os.path.join(out, "shared", "maps", fn))

    manifest = {"source": store, "units": {}, "icons": [], "effects": [], "status": [], "equipment": []}
    bp = B.Blueprints(qud_assets.path("data"))
    import qud_sounds
    sounds = qud_sounds.SoundIndex(qud_assets.path("sfx"))
    items, n_icons = export_items(bp, out, sounds)
    log("items:   %d as action-bar spells, %d icons" % (len(items), n_icons))
    import qud_mutations
    ab = qud_mutations.AbilityBuilder(bp, {r["qud"]: r for r in items}, lambda t: qud_assets.tile_file(t) is not None, sounds)
    n_units, monsters = export_units(bp, out, manifest, ab)
    n_players = export_players(qud_assets.path("data"), out, manifest)
    log("units:   %d creatures + player + %d castes" % (n_units, n_players))
    with open(os.path.join(out, "data", "monsters.json"), "w", encoding="utf-8") as f:
        json.dump(monsters, f, indent=0)
    armed = sum(1 for m in monsters if any(sp["stats"].get("damage", 0) > 0 for sp in m["spells"]))
    log("abilities: %d creatures armed (%d mutations, %d weapons), %d mutation icons" % (
        armed, sum(1 for m in monsters for sp in m["spells"] if "Mutation" in sp["tags"]),
        sum(1 for m in monsters for sp in m["spells"] if "Mutation" not in sp["tags"]), write_icons(out, ab.icons)))
    with open(os.path.join(out, "data", "equipment.json"), "w", encoding="utf-8") as f:
        f.write("[]\n")
    log("tracks:  %d" % export_track_tiles(out, manifest, qud_assets.path("tiles")))
    log("effects: %d" % export_effects(out))
    mapping = export_sounds(out)
    n_takes, n_names = export_sound_takes(out, sounds, items, monsters)
    log("takes:   %d clips linked for %d named sounds (per-weapon fire/hit, mutations, pickups)" % (n_takes, n_names))
    log("sounds:  %d cues + %d music" % (sum(1 for k in mapping if not k.startswith("battle_") and k not in THEMES),
                                        sum(1 for k in mapping if k.startswith("battle_") or k in THEMES)))
    # the voxel wall models (tools/wall2vox.py) and which family each tileset uses
    walls_src = qud_assets.path("walls")
    walls_dst = os.path.join(out, "walls")
    if os.path.isdir(walls_src):
        if os.path.islink(walls_dst) or os.path.isfile(walls_dst):
            os.remove(walls_dst)
        elif os.path.isdir(walls_dst):
            shutil.rmtree(walls_dst)
        try:
            os.symlink(walls_src, walls_dst, target_is_directory=True)
        except OSError:
            shutil.copytree(walls_src, walls_dst)
        log("walls:   linked (%d models)" % len([f for f in os.listdir(walls_src) if f.endswith(".json")]))
    else:
        log("walls:   none (run tools/wall2vox.py for voxel barriers)")
    manifest["wall_families"] = {ts: v[3] for ts, v in TILESETS.items()}
    with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    with open(os.path.join(out, "README.txt"), "w") as f:
        f.write("Generated by tools/export_godot_assets.py from the Qud asset store. Not committed.\n")
    link_project(repo, out)
    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
