"""The racer catalogue for the character-select screen
(mutant-plan/strategy/2caves2qud-large-roster-character-select.md): hundreds of
Qud sprites organised as a small stable set of COLLECTIONS, each racer a distinct
identity with its numbered blueprint siblings folded in as VARIANTS.

Written to <store>/godot/data/racers.json by tools/export_godot_assets.py:

  {"collections": [{id, name, description, icon, racers: [ids]}...],
   "racers": {id: {id, name, unit, family, tags, variants: [{unit, name}], variant_of,
                   hp, flying, driving_class, speed, weight, kind: "monster"|"caste"}}}

Classification is editorial but data-driven: the blueprint's inheritance chain and
its Species/Class/Role tags pick the family; utility collections (Favorites,
Recent, All, Random) are the screen's own. Order inside a collection is by name
and never changes when racers are added (new ones append).
"""
import math
import re

import qud_blueprints as B
import qud_items

FAMILIES = [
    # id, display, description, test(o, chain, tags) -> bool
    ("legendary", "Legendary", "Named leaders and famous beasts of Qud.",
     lambda o, ch, tg: tg.get("Role") == "Leader"),
    ("folk", "Villagers", "The humans of Qud: farmers, pilgrims, merchants, warriors.",
     lambda o, ch, tg: "Humanoid" in ch and tg.get("Species") == "human"),
    ("mutantfolk", "Snapjaws & Kin", "Snapjaws, goatfolk, hindren, urshiib, apes and the other folk of the world.",
     lambda o, ch, tg: "Humanoid" in ch),
    ("robots", "Robots", "Chrome and clockwork: the machines the sultans left behind.",
     lambda o, ch, tg: "Robot" in ch or tg.get("Species") in ("turret", "mecha")),
    ("bugs", "Bugs & Oozes", "Things that crawl, burrow and drip.",
     lambda o, ch, tg: tg.get("Class") in ("insect", "spider", "worm", "ooze", "slime", "arachnid") or tg.get("Species") in ("spider", "ooze", "worm", "slime")),
    ("beasts", "Beasts & Birds", "Animals of the salt marsh, jungle and canyon.",
     lambda o, ch, tg: "Animal" in ch),
    ("plants", "Plants & Fungi", "Things that grow, and race anyway.",
     lambda o, ch, tg: any(c in ch for c in ("ActivePlant", "MutatedPlant", "ActiveFungus", "MutatedFungus", "Fungus", "Plant"))),
    ("divine", "Cherubim", "The sultans' holy beasts and the great nephilim.",
     lambda o, ch, tg: any(c in ch for c in ("BaseCherubimSpawn", "BaseNephal", "Godling", "Baetyl"))),
    ("crystal", "Crystals", "Chiming, crystalline and otherwise unclassifiable.",
     lambda o, ch, tg: "Crystal" in ch or "Chime" in " ".join(ch)),
]
NUMBERED = re.compile(r"^(.*?)\s+(\d+)$")


def driving(hp, flying):
    """The engine's stats_from_unit without its dice: speed/weight 1..9 and a label."""
    weight = int(round(1.0 + 2.2 * math.log(max(1.0, hp) / 5.0 + 1.0)))
    weight = max(1, min(9, weight))
    speed = max(1, min(9, 10 - weight + (2 if flying else 0)))
    if weight <= 3:
        label = "Light / nimble"
    elif weight >= 7:
        label = "Heavy / bruiser"
    else:
        label = "Middleweight"
    if flying:
        label += ", flies"
    return speed, weight, label


def _display(bp, blueprint, fallback):
    """The racer's display name: the Render DisplayName cleaned, unless it is a placeholder
    like '[Creature]'; a trailing number (a sibling index) is dropped."""
    o = bp.get(blueprint)
    d = qud_items.clean_name(o["parts"].get("Render", {}).get("DisplayName"), fallback)
    if not d or d.startswith("[") or d.startswith("*"):
        d = fallback
    m = NUMBERED.match(d)
    return m.group(1) if m else d


def _variants(bp, ms, display):
    """Siblings become variants; when their display names coincide they are numbered
    ('Snapjaw Scavenger 1 / 2 / 3') so the variant strip reads."""
    names = [_display(bp, x.get("qud", x["name"]), x.get("qud", x["name"])) for x in ms]
    out = []
    for i, x in enumerate(ms):
        n = names[i]
        if names.count(n) > 1:
            n = "%s %d" % (n, names[:i + 1].count(n))
        out.append({"unit": x["asset"][1], "name": n})
    return out


def build(bp, monsters, castes):
    """monsters: the exporter's monsters.json records; castes: [(unit, name)]."""
    racers = {}
    by_family = {f[0]: [] for f in FAMILIES}
    by_family["castes"] = []
    # fold numbered siblings ("Snapjaw Scavenger 0/1/2") into one racer with variants
    groups = {}
    for m in monsters:
        name = m.get("qud", m["name"])          # the blueprint name; "name" is the display name
        mm = NUMBERED.match(name)
        base = mm.group(1) if mm else name
        groups.setdefault(base, []).append(m)
    for base, ms in groups.items():
        ms.sort(key=lambda x: x.get("qud", x["name"]))
        lead = ms[0]
        o = bp.get(lead.get("qud", lead["name"]))
        ch, tg = o["chain"], o["tags"]
        fam = "beasts"
        for fid, _, _, test in FAMILIES:
            try:
                if test(o, ch, tg):
                    fam = fid
                    break
            except Exception:
                continue
        unit = lead["asset"][1]
        speed, weight, label = driving(float(lead.get("max_hp", 20)), bool(lead.get("flying")))
        display = _display(bp, lead.get("qud", lead["name"]), base)
        rec = {
            "id": unit, "name": display, "unit": unit, "kind": "monster", "family": fam,
            "tags": [t for t in (tg.get("Species"), tg.get("Class"), tg.get("Role")) if t],
            "variants": _variants(bp, ms, display),
            "hp": float(lead.get("max_hp", 20)), "flying": bool(lead.get("flying")),
            "speed": speed, "weight": weight, "driving_class": label,
            "level": int(lead.get("level", 1)), "qud": lead.get("qud", lead["name"]),
        }
        racers[unit] = rec
        by_family[fam].append(unit)
    for unit, name in castes:
        rec = {"id": unit, "name": name, "unit": unit, "kind": "caste", "family": "castes", "tags": ["caste", "human"],
               "variants": [{"unit": unit, "name": name}], "hp": 50.0, "flying": False,
               "speed": 5, "weight": 5, "driving_class": "Middleweight, casts from the action bar", "level": 1, "qud": name}
        racers[unit] = rec
        by_family["castes"].append(unit)
    for k in by_family:
        by_family[k].sort(key=lambda u: racers[u]["name"].lower())
    collections = [
        {"id": "favorites", "name": "Favorites", "description": "Racers you starred. Press Y on any racer.", "utility": "favorites", "icon": "", "racers": []},
        {"id": "recent", "name": "Recently Used", "description": "Your last picks, newest first.", "utility": "recent", "icon": "", "racers": []},
        {"id": "all", "name": "All Racers", "description": "Every racer in the game, A to Z.", "utility": "all", "icon": "",
         "racers": sorted(racers, key=lambda u: racers[u]["name"].lower())},
        {"id": "random", "name": "Random", "description": "Any racer. Reroll with left or right.", "utility": "random", "icon": "", "racers": []},
        {"id": "castes", "name": "Castes", "description": "The callings and castes a player character is born to; they cast from the action bar.", "icon": by_family["castes"][0] if by_family["castes"] else "", "racers": by_family["castes"]},
    ]
    for fid, disp, desc, _ in FAMILIES:
        ids = by_family[fid]
        if not ids:
            continue
        collections.append({"id": fid, "name": disp, "description": desc, "icon": ids[len(ids) // 3], "racers": ids})
    return {"collections": collections, "racers": racers}
