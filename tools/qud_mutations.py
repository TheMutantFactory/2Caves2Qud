"""Caves of Qud's mutations as the abilities of its creatures (and of the player
racing as one), plus the weapons a creature carries.

The engine gives every monster racer a "spells" list and picks its ability from
it (Race._ability_spell_from: the first damaging record with range > 2 tiles,
else the first damaging one, else a bite). Records are the same spell shape the
items use (tools/qud_items.py), with a `kart` hint for the effect kind.

Creature blueprints name mutations by CLASS (`<mutation Name="FlamingRay"
Level="3"/>`); Mutations.xml maps class -> display name + tile. Breath
weapons (FireBreather, IceBreather, ...) and a few natural attacks have no
Mutations.xml entry, so the table below carries their names and borrows icons.
Passive mutations (Wings, Gills, Night Vision, Carapace...) make no ability;
Wings and Astral do mark the creature as flying.
"""
import qud_blueprints as B

# class -> (display name, icon tile, spec). spec: kind, dtype, dmg (at level 1), per_level, range (tiles), extras
MUTATIONS = {
    "FlamingRay": ("Flaming Ray", "Mutations/flaming_ray.bmp", {"kind": "beam", "dtype": "Fire", "dmg": 9, "per_level": 2.5, "range": 8}),
    "FreezingRay": ("Freezing Ray", "Mutations/freezing_ray.bmp", {"kind": "beam", "dtype": "Ice", "dmg": 7, "per_level": 2.0, "range": 8, "stun": 1.0}),
    "ElectricalGeneration": ("Electrical Generation", "Mutations/electrical_generation.bmp", {"kind": "beam", "dtype": "Lightning", "dmg": 8, "per_level": 2.5, "range": 6, "count": 2}),
    "LightManipulation": ("Light Manipulation", "Mutations/light_manipulation.bmp", {"kind": "beam", "dtype": "Holy", "dmg": 6, "per_level": 2.0, "range": 9}),
    "Disintegration": ("Disintegration", "Mutations/disintergration.bmp", {"kind": "blast", "dtype": "Arcane", "dmg": 12, "per_level": 3.0, "range": 1, "radius": 240}),
    "Pyrokinesis": ("Pyrokinesis", "Mutations/pyrokinesis.bmp", {"kind": "patch", "dtype": "Fire", "dmg": 5, "per_level": 1.5, "range": 8, "radius": 170, "tick": 0.4, "duration": 5.0}),
    "Cryokinesis": ("Cryokinesis", "Mutations/cryokinesis.bmp", {"kind": "patch", "dtype": "Ice", "dmg": 4, "per_level": 1.2, "range": 8, "radius": 170, "tick": 0.4, "duration": 5.0, "stun": 0.5}),
    "SunderMind": ("Sunder Mind", "Mutations/sunder_mind.bmp", {"kind": "bolt", "dtype": "Arcane", "dmg": 8, "per_level": 2.5, "range": 9, "stun": 0.4}),
    "Confusion": ("Confusion", "Mutations/confusion.bmp", {"kind": "hex", "dtype": "Arcane", "dmg": 2, "per_level": 0.5, "range": 6, "stun": 1.2, "radius": 200}),
    "StunningForce": ("Stunning Force", "Mutations/stunning_force.bmp", {"kind": "burst", "dtype": "Arcane", "dmg": 5, "per_level": 1.5, "range": 1, "radius": 260, "shove": 560, "stun": 0.6}),
    "TimeDilation": ("Time Dilation", "Mutations/time_dilation.bmp", {"kind": "hex", "dtype": "Arcane", "dmg": 1, "per_level": 0.3, "range": 1, "stun": 1.5, "radius": 300}),
    "LifeDrain": ("Syphon Vim", "Mutations/syphon_vim.bmp", {"kind": "bolt", "dtype": "Blood", "dmg": 6, "per_level": 2.0, "range": 5, "heal_frac": 0.6}),
    "Teleportation": ("Teleportation", "Mutations/teleportation.bmp", {"kind": "blink", "dtype": "Arcane", "dmg": 0, "per_level": 0, "range": 0, "distance": 420}),
    "TemporalFugue": ("Temporal Fugue", "Mutations/temporal_fugue.bmp", {"kind": "summon", "dtype": "Arcane", "dmg": 4, "per_level": 1.0, "range": 1, "count": 2, "duration": 8.0}),
    "ForceBubble": ("Force Bubble", "Mutations/force_bubble.bmp", {"kind": "shield", "dtype": "Arcane", "dmg": 0, "per_level": 0, "range": 0, "shields": 2}),
    "ForceWall": ("Force Wall", "Mutations/force_wall.bmp", {"kind": "shield", "dtype": "Arcane", "dmg": 0, "per_level": 0, "range": 0, "shields": 1}),
    "Regeneration": ("Regeneration", "Mutations/regeneration.bmp", {"kind": "heal", "dtype": "Nature", "dmg": 0, "per_level": 0, "range": 0, "amount": 12}),
    "HeightenedSpeed": ("Heightened Quickness", "Mutations/heightened_quickness.bmp", {"kind": "buff", "dtype": "Nature", "dmg": 0, "per_level": 0, "range": 0, "strength": 0.3, "duration": 4.0}),
    "AdrenalControl2": ("Adrenal Control", "Mutations/adrenal_control.bmp", {"kind": "buff", "dtype": "Nature", "dmg": 0, "per_level": 0, "range": 0, "strength": 0.25, "duration": 5.0}),
    "Quills": ("Quills", "Mutations/quills.bmp", {"kind": "burst", "dtype": "Physical", "dmg": 8, "per_level": 1.5, "range": 1, "radius": 180}),
    "BurrowingClaws": ("Burrowing Claws", "Mutations/burrowing_claws.bmp", {"kind": "melee", "dtype": "Physical", "dmg": 7, "per_level": 1.5, "range": 1}),
    "Horns": ("Horns", "Mutations/horns.bmp", {"kind": "melee", "dtype": "Physical", "dmg": 8, "per_level": 1.5, "range": 1, "shove": 300}),
    "Beak": ("Beak", "Mutations/beak.bmp", {"kind": "melee", "dtype": "Physical", "dmg": 5, "per_level": 1.0, "range": 1}),
    "Stinger": ("Stinger", "Mutations/stinger.bmp", {"kind": "melee", "dtype": "Poison", "dmg": 7, "per_level": 1.5, "range": 1, "stun": 0.8}),
    "SlimeGlands": ("Slime Glands", "Mutations/slime_glands.bmp", {"kind": "patch", "dtype": "Nature", "dmg": 1, "per_level": 0.2, "range": 5, "radius": 160, "tick": 0.6, "duration": 6.0, "stun": 0.3}),
    "CorrosiveGasGeneration": ("Corrosive Gas Generation", "Mutations/gas_generation.bmp", {"kind": "patch", "dtype": "Poison", "dmg": 6, "per_level": 1.5, "range": 1, "radius": 200, "tick": 0.5, "duration": 7.0}),
    "SleepGasGeneration": ("Sleep Gas Generation", "Mutations/gas_generation.bmp", {"kind": "hex", "dtype": "Dark", "dmg": 1, "per_level": 0.2, "range": 1, "radius": 200, "stun": 1.6}),
    "Spinnerets": ("Spinnerets", "Mutations/spinnerets.bmp", {"kind": "patch", "dtype": "Nature", "dmg": 1, "per_level": 0.2, "range": 1, "radius": 140, "tick": 0.5, "duration": 8.0, "stun": 0.5}),
    "SpiderWebs": ("Webs", "Mutations/spinnerets.bmp", {"kind": "patch", "dtype": "Nature", "dmg": 1, "per_level": 0.2, "range": 4, "radius": 160, "tick": 0.5, "duration": 8.0, "stun": 0.5}),
    "StickyTongue": ("Sticky Tongue", "Mutations/beak.bmp", {"kind": "beam", "dtype": "Nature", "dmg": 4, "per_level": 1.0, "range": 5, "shove": -520}),
    "Burgeoning": ("Burgeoning", "Mutations/burgeoning.bmp", {"kind": "summon", "dtype": "Nature", "dmg": 3, "per_level": 1.0, "range": 3, "count": 2, "duration": 9.0}),
    "SporePuffer": ("Spore Puff", "Mutations/gas_generation.bmp", {"kind": "patch", "dtype": "Poison", "dmg": 4, "per_level": 1.0, "range": 1, "radius": 180, "tick": 0.5, "duration": 6.0}),
    "FireBreather": ("Fire Breath", "Mutations/flaming_ray.bmp", {"kind": "blast", "dtype": "Fire", "dmg": 9, "per_level": 2.5, "range": 5, "radius": 180}),
    "IceBreather": ("Frost Breath", "Mutations/freezing_ray.bmp", {"kind": "blast", "dtype": "Ice", "dmg": 7, "per_level": 2.0, "range": 5, "radius": 180, "stun": 0.8}),
    "PoisonBreather": ("Poison Breath", "Mutations/gas_generation.bmp", {"kind": "patch", "dtype": "Poison", "dmg": 5, "per_level": 1.5, "range": 5, "radius": 180, "tick": 0.5, "duration": 6.0}),
    "CorrosiveBreather": ("Acid Breath", "Mutations/gas_generation.bmp", {"kind": "patch", "dtype": "Poison", "dmg": 7, "per_level": 1.5, "range": 5, "radius": 160, "tick": 0.5, "duration": 5.0}),
    "SleepBreather": ("Sleep Breath", "Mutations/gas_generation.bmp", {"kind": "hex", "dtype": "Dark", "dmg": 1, "per_level": 0.2, "range": 5, "radius": 180, "stun": 1.6}),
    "StunBreather": ("Stun Breath", "Mutations/stunning_force.bmp", {"kind": "hex", "dtype": "Lightning", "dmg": 2, "per_level": 0.5, "range": 5, "radius": 180, "stun": 1.2}),
    "ConfusionBreather": ("Confusion Breath", "Mutations/confusion.bmp", {"kind": "hex", "dtype": "Arcane", "dmg": 1, "per_level": 0.3, "range": 5, "radius": 180, "stun": 1.0}),
    "NormalityBreather": ("Normality Breath", "Mutations/gas_generation.bmp", {"kind": "hex", "dtype": "Arcane", "dmg": 1, "per_level": 0.3, "range": 5, "radius": 180, "stun": 0.6}),
    "ElectromagneticPulse": ("Electromagnetic Pulse", "Mutations/electromagnetic_pulse.bmp", {"kind": "burst", "dtype": "Lightning", "dmg": 4, "per_level": 1.0, "range": 1, "radius": 260, "stun": 0.8}),
    "Kindle": ("Kindle", "Mutations/kindle.bmp", {"kind": "bolt", "dtype": "Fire", "dmg": 4, "per_level": 1.0, "range": 6}),
    "SpacetimeVortex": ("Spacetime Vortex", "Mutations/spacetime_vortex.bmp", {"kind": "burst", "dtype": "Arcane", "dmg": 10, "per_level": 2.0, "range": 1, "radius": 240, "shove": -500}),
    "Phasing": ("Phasing", "Mutations/phasing.bmp", {"kind": "blink", "dtype": "Arcane", "dmg": 0, "per_level": 0, "range": 0, "distance": 300}),
    "Astral": ("Astral", "Mutations/phasing.bmp", {"kind": "blink", "dtype": "Arcane", "dmg": 0, "per_level": 0, "range": 0, "distance": 300}),
}
FLYING_CLASSES = ("Wings", "Astral")

# class -> cast sound candidates (first that exists in the store wins), then a kind fallback
SOUNDS = {
    "FlamingRay": ["sfx_ability_mutation_flamingRay_attack"], "FreezingRay": ["sfx_ability_mutation_freezingRay_attack"],
    "LightManipulation": ["sfx_ability_mutation_lightManipulation_laser_fire"], "Quills": ["sfx_ability_mutation_quills_expel"],
    "Disintegration": ["sfx_ability_mutation_disintegration_disintegrate"], "BurrowingClaws": ["sfx_ability_mutation_burrowingClaws_burrow"],
    "Beak": ["sfx_ability_mutation_beak_peck"], "Stinger": ["sfx_ability_mutation_stinger_tailWhip"],
    "Spinnerets": ["sfx_ability_mutation_spinnerets_webDrop"], "SpiderWebs": ["sfx_ability_mutation_spinnerets_webDrop"],
    "Burgeoning": ["sfx_ability_mutation_burgeoning_plantGrow"], "TemporalFugue": ["sfx_ability_mutation_temporalFugue_copy"],
    "StunningForce": ["sfx_ability_mutation_stunning_force"], "TimeDilation": ["sfx_ability_mutation_timeDilation_activate"],
    "ElectromagneticPulse": ["sfx_ability_mutation_emp_activate", "sfx_ability_electromagnetic_pulse"],
    "Confusion": ["sfx_ability_confusion"], "Cryokinesis": ["sfx_ability_cryokinesis_active"],
    "Pyrokinesis": ["sfx_ability_pyrokinesis_active", "sfx_ability_mutation_flamingRay_attack"],
    "Regeneration": ["sfx_ability_mutation_regeneration_limbRegrowth"],
    "ForceBubble": ["sfx_ability_forcefield_create"], "ForceWall": ["sfx_ability_forcefield_create"],
    "Teleportation": ["sfx_ability_mutation_phase"], "Phasing": ["sfx_ability_mutation_phase"], "Astral": ["sfx_ability_mutation_phase"],
    "SpacetimeVortex": ["sfx_ability_mutation_phase"], "StickyTongue": ["sfx_ability_creature_liquid_spit"],
    "SlimeGlands": ["sfx_ability_creature_liquid_spit"], "Horns": ["sfx_ability_charge"],
    "CorrosiveGasGeneration": ["sfx_ability_gasMutation_activeRelease"], "SleepGasGeneration": ["sfx_ability_gasMutation_activeRelease"],
    "SporePuffer": ["sfx_ability_gasMutation_activeRelease"],
}
BREATH_SOUND = ["sfx_ability_gas_breathe"]
KIND_SOUND = {"beam": "sfx_ability_mutation_physical_generic_activate", "bolt": "sfx_ability_mutation_mental_generic_activate",
              "blast": "sfx_ability_mutation_physical_generic_activate", "patch": "sfx_ability_gasMutation_activeRelease",
              "hex": "sfx_ability_mutation_mental_generic_activate", "burst": "sfx_ability_mutation_physical_generic_activate",
              "summon": "sfx_ability_mutation_mental_generic_activate", "shield": "sfx_ability_forcefield_create",
              "heal": "sfx_ability_mutation_physical_generic_activate", "buff": "sfx_ability_mutation_physical_generic_activate",
              "blink": "sfx_ability_mutation_phase", "melee": "sfx_ability_mutation_physical_generic_activate"}
HIT_SOUND = {"Fire": "sfx_missile_directEnergy_hit", "Ice": "sfx_missile_directEnergy_hit", "Lightning": "sfx_missile_directEnergy_hit",
             "Arcane": "sfx_missile_directEnergy_hit", "Holy": "sfx_missile_directEnergy_hit"}
DAMAGE_SCALE = 1.6      # Qud dice means -> the kart's numbers (a wizard has 50 HP)


def icon_stem(tile):
    import qud_items
    return qud_items.icon_stem(tile)


class AbilityBuilder:
    def __init__(self, bp, items_by_blueprint, has_tile, sounds=None):
        self.bp = bp
        self.items = items_by_blueprint      # blueprint name -> item record (tools/qud_items.py)
        self.has_tile = has_tile
        self.sounds = sounds                 # qud_sounds.SoundIndex or None
        self.icons = {}                      # stem -> (tile, main, detail)
        self.used = {}                       # class -> count, for the report

    def record(self, cls, level):
        if cls not in MUTATIONS:
            return None
        display, tile, spec = MUTATIONS[cls]
        try:
            lv = max(1, int(str(level).split("-")[0]))
        except ValueError:
            lv = 1
        dmg = round((spec["dmg"] + spec["per_level"] * (lv - 1)) * DAMAGE_SCALE, 1)
        stem = icon_stem(tile) if self.has_tile(tile) else ""
        if stem:
            self.icons.setdefault(stem, (tile, "y", "W"))
        kart = {k: v for k, v in spec.items() if k not in ("dmg", "per_level", "range")}
        if dmg > 0:
            kart["damage"] = dmg
        if spec["kind"] in ("bolt", "blast") and stem:
            kart["projectile"] = stem
        if "radius" in kart and lv > 1:
            kart["radius"] = round(kart["radius"] * (1.0 + 0.06 * (lv - 1)))
        rec = {
            "name": display, "qud": cls, "level": max(1, min(7, lv)), "tags": ["Mutation", spec["dtype"]],
            "damage_type": [spec["dtype"]], "range": spec["range"], "max_charges": 0, "hp_cost": 0,
            "melee": spec["kind"] == "melee", "self_target": spec["kind"] in ("buff", "shield", "heal"),
            "stats": {"damage": dmg} if dmg > 0 else {}, "description": {"text": ""},
            "asset": ["mutations", stem] if stem else [], "upgrades": [], "kart": kart,
        }
        if spec["kind"] == "heal":
            rec["stats"]["heal"] = spec["amount"]
        if self.sounds is not None:
            cands = list(SOUNDS.get(cls, [])) + (BREATH_SOUND if cls.endswith("Breather") else []) + [KIND_SOUND.get(spec["kind"])]
            snd = self.sounds.first(*cands)
            if snd:
                kart["sound"] = snd
            hit = self.sounds.first(HIT_SOUND.get(spec["dtype"]), "sfx_throwing_generic_hitOrganic")
            if hit and spec["kind"] in ("bolt", "blast", "beam", "melee"):
                kart["hit_sound"] = hit
        self.used[cls] = self.used.get(cls, 0) + 1
        return rec

    def abilities(self, name):
        """-> (spells, flying) for a creature blueprint: its mutations, then the
        weapons in its inventory that are item records."""
        o = self.bp.get(name)
        out = []
        seen = set()
        flying = False
        for m in o["mutations"]:
            cls = m["class"]
            if cls in FLYING_CLASSES:
                flying = True
            if cls in seen:
                continue
            seen.add(cls)
            rec = self.record(cls, m.get("level", "1"))
            if rec:
                out.append(rec)
        for inv in o["inventory"]:
            key = inv.lstrip("@").strip()
            item = self.items.get(key)
            if item and item["name"] not in seen:
                seen.add(item["name"])
                out.append(item)
        # ranged first: the engine picks the first damaging record with range > 2
        out.sort(key=lambda r: (0 if (r["stats"].get("damage", 0) > 0 and r["range"] > 2) else
                                1 if r["stats"].get("damage", 0) > 0 else 2))
        return out, flying
