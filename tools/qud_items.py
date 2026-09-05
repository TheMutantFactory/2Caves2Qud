"""Caves of Qud's items as the racing engine's "spells": the things a kart casts
from its action bar, learns from scrolls on the road and buys in the shop.

The engine (SpellDB.gd) reads records shaped like Rift Wizard 3 spells and maps
them onto kart effect kinds by rules over their stats and tags: damage + radius
-> blast, "bolt/beam/ray" in the name -> beam, heal -> heal, self_target ->
buff, a duration and no damage -> hex, else bolt; a record's own "kart" dict is
applied over that (kinds the rules cannot reach: patch, burst, shield, empower,
summon, stun, shove, count). This module builds those records from the
blueprints in Items.xml:

  grenades   HE -> blast (Fire); heat -> blast (Fire); cold -> blast (Ice) that
             stuns; poison/acid gas -> a patch (Poison); sleep/stun gas and
             flashbang -> hex that stuns; EMP/normality -> hex; gravity ->
             burst that pulls; time dilation -> hex slow; phase -> blink.
             Mark I/II/III and the Tier tag set the level; three per bundle.
  missile    pistols, rifles, bows, dart guns: bolt (Physical) with the
  weapons    magazine as charges; lasers, rails, eigen/spaser, arc, freeze ray:
             beam by damage type; chain weapons multi-shot; shotguns 3-shot
             short range; flamethrowers lay a fire patch; launchers blast.
  thrown     javelins, axes, daggers: bolt (Physical), four per bundle.
  melee      swords, axes, cudgels...: melee, unlimited.
  tonics     salve/ubernostrum heal; blaze/sphynx salt/skulk/love boost;
             hulk honey empowers; rubbergum/shade oil shield; nectar heals.

Damage is the mean of the blueprint's dice, scaled to the kart game's numbers
(a wizard has 50 HP; RW3 spells did 5-40). Names are the game's display names
with its colour markup stripped. Sounds come from the blueprints' own tags
(MissileFireSound, SwingSound, ThrownSound, DetonatedSound, the projectile's
ImpactSound) resolved against the extracted clips (tools/qud_sounds.py), into
the record's kart hint as "sound" (cast) and "hit_sound" (impact/detonation).
"""
import re

import qud_blueprints as B

TIER_LEVEL = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 7}
MARKUP = re.compile(r"\{\{[^|}]*\|([^}]*)\}\}")
DICE = re.compile(r"^\s*(\d+)d(\d+)\s*([+-]\s*\d+)?\s*$")

GRENADES = [
    (r"^HEGrenade", {"kind": "blast", "dtype": "Fire", "radius": 200, "dmg_mul": 2.4}),
    (r"^HeatGrenade", {"kind": "blast", "dtype": "Fire", "radius": 180, "dmg": 18}),
    (r"^ColdGrenade", {"kind": "blast", "dtype": "Ice", "radius": 180, "dmg": 12, "stun": 1.0}),
    (r"^PoisonGasGrenade", {"kind": "patch", "dtype": "Poison", "radius": 160, "dmg": 6, "tick": 0.5, "duration": 8.0}),
    (r"^AcidGasGrenade", {"kind": "patch", "dtype": "Poison", "radius": 140, "dmg": 9, "tick": 0.5, "duration": 6.0}),
    (r"^SleepGasGrenade", {"kind": "hex", "dtype": "Dark", "stun": 1.8, "radius": 160}),
    (r"^StunGasGrenade", {"kind": "hex", "dtype": "Lightning", "stun": 1.4, "radius": 160}),
    (r"^FlashbangGrenade", {"kind": "hex", "dtype": "Holy", "stun": 1.0, "radius": 220}),
    (r"^EMPGrenade", {"kind": "hex", "dtype": "Lightning", "stun": 0.8, "radius": 200}),
    (r"^NormalityGasGrenade", {"kind": "hex", "dtype": "Arcane", "stun": 0.6, "radius": 160}),
    (r"^GravityGrenade", {"kind": "burst", "dtype": "Arcane", "dmg": 8, "radius": 300, "shove": -520}),
    (r"^TimeDilationGrenade", {"kind": "hex", "dtype": "Arcane", "stun": 1.2, "radius": 240}),
    (r"^PhaseGrenade", {"kind": "blink", "dtype": "Arcane", "distance": 420}),
    (r"^ThermalGrenade", {"kind": "blast", "dtype": "Fire", "radius": 180, "dmg": 18}),
    (r"^PlasmaGrenade", {"kind": "blast", "dtype": "Fire", "radius": 240, "dmg": 30}),
    (r"^SunderGrenade", {"kind": "blast", "dtype": "Physical", "radius": 160, "dmg": 22}),
    (r"^FireSupportGrenade", {"kind": "blast", "dtype": "Fire", "radius": 260, "dmg": 26}),
    (r"^StasisGrenade", {"kind": "hex", "dtype": "Arcane", "stun": 2.2, "radius": 140}),
]
TONICS = {
    "SalveTonic": {"heal": 16, "level": 1},
    "UbernostrumTonic": {"heal": 40, "level": 4},
    "NectarTonic": {"heal": 25, "level": 5},
    "BlazeTonic": {"buff": 0.45, "level": 2, "notes": "speed"},
    "SphynxSaltTonic": {"buff": 0.3, "level": 3},
    "SkulkTonic": {"buff": 0.25, "level": 2},
    "LoveTonic": {"buff": 0.2, "level": 2},
    "HulkHoneyTonic": {"empower": 0.5, "level": 3},
    "RubbergumTonic": {"shields": 1, "level": 2},
    "ShadeOilTonic": {"shields": 2, "level": 3},
}
BEAM_WORDS = ("laser", "eigen", "spaser", "rail", "arc winder", "freeze ray", "nullray", "di-thermo", "hypertractor",
              "space inverter", "psychal", "blood-gradient", "beam")
DTYPE_BY_WORD = [
    ("freeze", "Ice"), ("arc", "Lightning"), ("eigen", "Lightning"), ("laser", "Fire"), ("thermo", "Fire"),
    ("flame", "Fire"), ("spaser", "Arcane"), ("nullray", "Arcane"), ("psychal", "Arcane"), ("space inverter", "Arcane"),
    ("blood", "Blood"), ("rail", "Metallic"), ("hypertractor", "Arcane"),
]


def clean_name(display, fallback):
    if not display:
        return fallback
    s = display
    while True:                      # {{crysteel|{{crysteel|crysteel}} dagger}}: nested markup
        t = MARKUP.sub(r"\1", s)
        if t == s:
            break
        s = t
    s = re.sub(r"&[a-zA-Z]|\^[a-zA-Z]", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    words = []
    for w in s.split(" "):
        if w.lower() in ("mk", "mki", "mkii", "mkiii"):
            words.append(w.capitalize())
        elif w.upper() in ("I", "II", "III", "IV", "V", "HE", "EMP"):
            words.append(w.upper())
        else:
            words.append(w[:1].upper() + w[1:])
    return " ".join(words)


def dice_mean(s, default=0.0):
    if not s:
        return default
    m = DICE.match(str(s))
    if not m:
        try:
            return float(s)
        except ValueError:
            return default
    n, d = int(m.group(1)), int(m.group(2))
    bonus = int(m.group(3).replace(" ", "")) if m.group(3) else 0
    return n * (d + 1) / 2.0 + bonus


def icon_stem(tile):
    return re.sub(r"[^a-z0-9]+", "_", (tile or "").split("/")[-1].split("\\")[-1].rsplit(".", 1)[0].lower()).strip("_")


class ItemBuilder:
    def __init__(self, bp, has_tile, sounds=None):
        self.bp = bp
        self.has_tile = has_tile      # tile path -> bool (the store has that image)
        self.sounds = sounds          # qud_sounds.SoundIndex, or None for silent records
        self.records = []
        self.icons = {}               # stem -> (tile, main, detail)
        self.seen_names = set()

    def _base(self, name, o, r, level, tags, dtype, kind_hint=None):
        display = clean_name(r.get("DisplayName"), name)
        if display in self.seen_names:
            return None
        tile = r.get("Tile")
        if not tile or not self.has_tile(tile):
            return None
        self.seen_names.add(display)
        stem = icon_stem(tile)
        main = B.color_letter(r, "TileColor") or B.color_letter(r, "ColorString") or "y"
        detail = B.color_letter(r, "DetailColor") or "Y"
        self.icons.setdefault(stem, (tile, main, detail))
        desc = o["parts"].get("Description", {}).get("Short", "")
        return {
            "name": display, "qud": name, "level": max(1, min(7, level)), "tags": tags,
            "damage_type": [dtype], "range": 6, "max_charges": 3, "hp_cost": 0,
            "melee": False, "self_target": False, "stats": {}, "description": {"text": MARKUP.sub(r"\1", desc)},
            "asset": ["items", stem], "upgrades": [], "kart": {},
        }

    def sound(self, rec, o, tag, *fallbacks):
        """The record's cast sound: the blueprint's tag, else the first fallback that exists."""
        if self.sounds is None:
            return
        b = self.sounds.first(o["tags"].get(tag), *fallbacks)
        if b:
            rec["kart"]["sound"] = b

    def hit_sound(self, rec, *candidates):
        if self.sounds is None:
            return
        b = self.sounds.first(*candidates)
        if b:
            rec["kart"]["hit_sound"] = b

    def projectile_impact(self, o):
        """The ImpactSound of the projectile a weapon fires, via its ammo loader."""
        for part in ("EnergyAmmoLoader", "MagazineAmmoLoader", "LiquidAmmoLoader"):
            proj = o["parts"].get(part, {}).get("ProjectileObject")
            if proj and proj in self.bp.raw:
                v = self.bp.get(proj)["tags"].get("ImpactSound")
                if v:
                    return v
        return None

    def tier_level(self, o, default=1):
        t = o["tags"].get("Tier")
        try:
            return TIER_LEVEL.get(int(t), default) if t else default
        except ValueError:
            return default

    def build(self):
        bp = self.bp
        for name in bp.names():
            if bp.is_abstract(name):
                continue
            o = bp.get(name)
            chain = o["chain"]
            r = o["parts"].get("Render", {})
            if not r.get("Tile"):
                continue
            if "Grenade" in chain or name.endswith("Grenade1") or name.endswith("Grenade2") or name.endswith("Grenade3"):
                self.grenade(name, o, r)
            elif "Tonic" in chain and name in TONICS:
                self.tonic(name, o, r)
            elif "MissileWeapon" in o["parts"] and ("BaseMissileWeapon" in chain or "BaseHeavyWeapon" in chain):
                self.missile(name, o, r)
            elif "ThrownWeapon" in o["parts"] and o["parts"]["ThrownWeapon"].get("Damage") and o["tags"].get("Tier") \
                    and "njector" not in (r.get("DisplayName") or "") and not name.startswith("Clue_"):
                self.thrown(name, o, r)
            elif "MeleeWeapon" in o["parts"] and o["parts"]["MeleeWeapon"].get("BaseDamage") \
                    and str(o["parts"].get("Physics", {}).get("Category", "")).startswith("Melee Weapon") and o["tags"].get("Tier"):
                self.melee(name, o, r)
        self.records.sort(key=lambda x: (x["level"], x["name"]))
        return self.records

    def grenade(self, name, o, r):
        spec = None
        for rx, sp in GRENADES:
            if re.match(rx, name):
                spec = sp
                break
        if spec is None:
            return
        mark = int(o["tags"].get("Mark", "1") or 1) if str(o["tags"].get("Mark", "1")).isdigit() else 1
        level = max(self.tier_level(o, mark), mark)
        rec = self._base(name, o, r, level, ["Grenade", spec["dtype"]], spec["dtype"])
        if rec is None:
            return
        dmg = spec.get("dmg", 0.0)
        he = o["parts"].get("HEGrenade", {})
        if he.get("Damage"):
            dmg = dice_mean(he["Damage"]) * spec.get("dmg_mul", 1.0)
        dmg = dmg * (1.0 + 0.25 * (mark - 1))
        rec["stats"] = {"damage": round(dmg, 1)} if dmg > 0 else {}
        if spec["kind"] in ("blast", "burst") or "radius" in spec:
            rec["stats"]["radius"] = round(spec["radius"] / 70.0, 2)   # RADIUS_PX units for the rules
        kart = {"kind": spec["kind"], "dtype": spec["dtype"]}
        for k in ("radius", "stun", "shove", "tick", "duration", "distance"):
            if k in spec:
                kart[k] = spec[k] * (1.0 + 0.15 * (mark - 1)) if k in ("radius", "stun", "duration") else spec[k]
        if dmg > 0:
            kart["damage"] = round(dmg, 1)
        rec["kart"] = kart
        rec["range"] = 7
        rec["max_charges"] = 3
        self.sound(rec, o, "ThrownSound", "sfx_throwing_generic_throw", "sfx_throwing_stone_medium_throw")
        self.hit_sound(rec, o["tags"].get("DetonatedSound"),
                       "sfx_grenade_gas_explode" if spec["kind"] in ("patch", "hex") else "sfx_grenade_highExplosive_explode")
        self.records.append(rec)

    def missile(self, name, o, r):
        lname = name.lower()
        mw = o["parts"]["MissileWeapon"]
        level = self.tier_level(o, 2)
        dtype = "Physical"
        for word, dt in DTYPE_BY_WORD:
            if word in lname:
                dtype = dt
                break
        beam = any(w in lname for w in BEAM_WORDS)
        rec = self._base(name, o, r, level, ["Missile", dtype], dtype)
        if rec is None:
            return
        shots = int(mw.get("ShotsPerAction", "1") or 1)
        mag = o["parts"].get("MagazineAmmoLoader", {}).get("MaxAmmo")
        charges = int(mag) if mag and str(mag).isdigit() else (6 if "Pistol" in o["chain"] or "BasePistol" in o["chain"] else 4)
        dmg = 5.0 + 3.0 * level
        if "BaseBow" in o["chain"] or "dart" in lname:
            dmg *= 0.8
        if "BaseRifle" in o["chain"] or "BaseMagazineRifle" in o["chain"]:
            dmg *= 1.2
        rec["stats"] = {"damage": round(dmg, 1)}
        rec["range"] = 9 if ("Rifle" in " ".join(o["chain"]) or "BaseBow" in o["chain"]) else 6
        rec["max_charges"] = max(1, min(12, charges))
        kart = {"dtype": dtype}
        if "booster" in lname:
            return
        if "flame" in lname:
            kart.update({"kind": "patch", "radius": 150, "tick": 0.4, "damage": round(dmg * 0.6, 1), "duration": 6.0})
        elif "pump" in lname:
            kart.update({"kind": "patch", "dtype": "Poison", "radius": 170, "tick": 0.5, "damage": round(dmg * 0.4, 1), "duration": 7.0})
        elif "grappling" in lname:
            kart.update({"kind": "beam", "shove": -520, "damage": round(dmg * 0.4, 1)})
        elif "launcher" in lname or "rocket" in lname or "mortar" in lname or "cannon" in lname:
            kart.update({"kind": "blast", "radius": 200, "damage": round(dmg * 1.6, 1)})
            rec["max_charges"] = 2
        elif beam:
            kart["kind"] = "beam"
            if dtype == "Ice":
                kart["stun"] = 1.2
            if "hypertractor" in lname or "space inverter" in lname:
                kart["shove"] = -480
        else:
            kart["kind"] = "bolt"
        if "chain" in lname or shots >= 3:
            kart["count"] = max(3, min(6, shots if shots >= 3 else 4))
            kart["damage"] = round(dmg * 0.6, 1)
        if "shotgun" in lname:
            kart.update({"kind": "bolt", "count": 3, "damage": round(dmg * 0.8, 1)})
            rec["range"] = 4
        rec["kart"] = kart
        self.sound(rec, o, "MissileFireSound",
                   "sfx_missile_bow_fire" if "BaseBow" in o["chain"] else None,
                   "sfx_missile_rifle_fire" if rec["range"] >= 9 else "sfx_missile_smallGun_fire")
        self.hit_sound(rec, self.projectile_impact(o),
                       "sfx_missile_directEnergy_hit" if beam else "sfx_throwing_generic_hitOrganic")
        self.records.append(rec)

    def thrown(self, name, o, r):
        tw = o["parts"]["ThrownWeapon"]
        level = self.tier_level(o, 1)
        rec = self._base(name, o, r, level, ["Thrown", "Physical"], "Physical")
        if rec is None:
            return
        dmg = dice_mean(tw.get("Damage"), 2.0) * 3.0 + 2.0 * level
        rec["stats"] = {"damage": round(dmg, 1)}
        rec["range"] = 5
        rec["max_charges"] = 4
        rec["kart"] = {"kind": "bolt", "dtype": "Physical"}
        self.sound(rec, o, "ThrownSound", "sfx_throwing_generic_throw")
        self.hit_sound(rec, "sfx_throwing_generic_hitOrganic")
        self.records.append(rec)

    def melee(self, name, o, r):
        mw = o["parts"]["MeleeWeapon"]
        level = self.tier_level(o, 1)
        rec = self._base(name, o, r, level, ["Melee", "Physical", mw.get("Skill", "")], "Physical")
        if rec is None:
            return
        dmg = dice_mean(mw.get("BaseDamage"), 2.0) * 3.0 + 1.5 * level
        rec["stats"] = {"damage": round(dmg, 1), "num_targets": 1}
        rec["melee"] = True
        rec["range"] = 1
        rec["max_charges"] = 0
        rec["kart"] = {"kind": "melee", "dtype": "Physical"}
        skill = mw.get("Skill", "")
        self.sound(rec, o, "SwingSound",
                   {"LongBlades": "sfx_melee_longBlade_metal_swing", "ShortBlades": "sfx_melee_shortSword_metal_swing",
                    "Axe": "sfx_melee_axe_metal_swing", "Cudgel": "sfx_melee_cudgel_oneHanded_metal_swing"}.get(skill),
                   "sfx_melee_cudgel_wood_swing")
        self.hit_sound(rec, o["tags"].get("HitSound"), "sfx_throwing_generic_hitOrganic")
        self.records.append(rec)

    def tonic(self, name, o, r):
        spec = TONICS[name]
        rec = self._base(name, o, r, spec["level"], ["Tonic", "Nature"], "Nature")
        if rec is None:
            return
        rec["self_target"] = True
        rec["range"] = 0
        rec["max_charges"] = 2
        if "heal" in spec:
            rec["stats"] = {"heal": spec["heal"]}
            rec["kart"] = {"kind": "heal", "amount": spec["heal"]}
        elif "buff" in spec:
            rec["kart"] = {"kind": "buff", "strength": spec["buff"], "duration": 4.0}
        elif "empower" in spec:
            rec["kart"] = {"kind": "empower", "bonuses": {"damage": spec["empower"]}, "duration": 8.0}
        elif "shields" in spec:
            rec["stats"] = {"shields": spec["shields"]}
            rec["kart"] = {"kind": "shield", "shields": spec["shields"]}
        self.sound(rec, o, "", "sfx_ability_injectorTube_inject")
        self.records.append(rec)
