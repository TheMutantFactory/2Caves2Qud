"""Qud's sound names, resolved against the extracted clips.

Blueprints name sounds by a path-like tag value ("Sounds/Missile/Fires/Rifles/
sfx_missile_laserRifle_fire"); the clips in the store are the last segment plus
a variant suffix (sfx_missile_laserRifle_fire-001 .. -005). `SoundIndex` maps a
tag value or bare base name to its variants, and `first()` walks a fallback list.
"""
import json
import os
import re

VARIANT = re.compile(r"-\d+$")


class SoundIndex:
    def __init__(self, sfx_dir):
        self.dir = sfx_dir
        self.files = {}          # clip name -> relative file
        self.bases = {}          # base -> [clip names]
        try:
            with open(os.path.join(sfx_dir, "index.json"), "r", encoding="utf-8") as f:
                idx = json.load(f)
        except (OSError, ValueError):
            idx = {}
        for name in sorted(idx):
            self.files[name] = idx[name]["file"]
            self.bases.setdefault(VARIANT.sub("", name), []).append(name)

    @staticmethod
    def base_of(value):
        """'Sounds/Melee/cudgels/sfx_melee_cudgel_wood_swing' -> the base name."""
        if not value:
            return None
        v = value.replace("\\", "/").split("/")[-1].strip()
        return v or None

    def has(self, base):
        return base in self.bases

    def resolve(self, value):
        b = self.base_of(value)
        return b if b and b in self.bases else None

    def first(self, *candidates):
        for c in candidates:
            if not c:
                continue
            b = self.resolve(c)
            if b:
                return b
        return None

    def prefix(self, p):
        for b in sorted(self.bases):
            if b.startswith(p):
                return b
        return None
