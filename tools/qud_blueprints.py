"""Caves of Qud's object blueprints (data/ObjectBlueprints/*.xml in the asset
store), with inheritance resolved.

A blueprint is `<object Name=.. Inherits=..>` holding `<part Name=..>` elements
(attributes), `<stat Name=.. Value=..>`, `<tag Name=.. Value=..>`. Children
inherit and override per part-attribute, per stat, per tag. `Blueprints.get()`
returns the RESOLVED view; `.render()` the Render part; `.tile()` the tile path
as the game writes it (case and separators vary wildly across the XML).
"""
import os
import re
import xml.etree.ElementTree as ET

_BAD_CHARREF = re.compile(r"&#(x[0-9a-fA-F]+|[0-9]+);")


def parse_xml(path):
    """ElementTree root of a Qud XML file. The game's XML carries numeric
    character references to control characters (its own colour/glyph codes)
    that a strict parser rejects; strip those before parsing."""
    with open(path, "r", encoding="utf-8-sig", errors="replace") as f:
        text = f.read()

    def fix(m):
        v = m.group(1)
        n = int(v[1:], 16) if v.startswith("x") else int(v)
        if n < 32 and n not in (9, 10, 13) or 0xD800 <= n <= 0xDFFF or n > 0x10FFFF:
            return ""
        return m.group(0)

    return ET.fromstring(_BAD_CHARREF.sub(fix, text))


class Blueprints:
    def __init__(self, data_dir):
        self.raw = {}
        bp_dir = os.path.join(data_dir, "ObjectBlueprints")
        for fn in sorted(os.listdir(bp_dir)):
            if not fn.endswith(".xml"):
                continue
            try:
                root = parse_xml(os.path.join(bp_dir, fn))
            except ET.ParseError as e:
                raise RuntimeError("%s: %s" % (fn, e))
            for ob in root.iter("object"):
                name = ob.get("Name")
                if not name:
                    continue
                o = self.raw.setdefault(name, {"name": name, "inherits": ob.get("Inherits"),
                                                "parts": {}, "stats": {}, "tags": {}, "file": fn,
                                                "removed_parts": set()})
                if ob.get("Inherits"):
                    o["inherits"] = ob.get("Inherits")
                for el in ob:
                    if el.tag == "part":
                        pn = el.get("Name")
                        if pn:
                            o["parts"].setdefault(pn, {}).update({k: v for k, v in el.attrib.items() if k != "Name"})
                    elif el.tag == "removepart":
                        o["removed_parts"].add(el.get("Name"))
                    elif el.tag == "stat":
                        sn = el.get("Name")
                        if sn:
                            o["stats"][sn] = dict(el.attrib)
                    elif el.tag in ("tag", "intproperty", "stringproperty", "property"):
                        tn = el.get("Name")
                        if tn:
                            o["tags"][tn] = el.get("Value", "")
        self._resolved = {}

    def names(self):
        return list(self.raw.keys())

    def chain(self, name):
        out = []
        seen = set()
        while name and name in self.raw and name not in seen:
            seen.add(name)
            out.append(self.raw[name])
            name = self.raw[name]["inherits"]
        return out

    def get(self, name):
        """Resolved blueprint: parts/stats/tags merged root-first so the child wins."""
        if name in self._resolved:
            return self._resolved[name]
        r = {"name": name, "parts": {}, "stats": {}, "tags": {}, "chain": [], "inherits": None}
        ch = self.chain(name)
        r["chain"] = [o["name"] for o in ch]
        r["inherits"] = ch[0]["inherits"] if ch else None
        for o in reversed(ch):
            for pn, attrs in o["parts"].items():
                r["parts"].setdefault(pn, {}).update(attrs)
            for pn in o["removed_parts"]:
                r["parts"].pop(pn, None)
            for sn, attrs in o["stats"].items():
                r["stats"].setdefault(sn, {}).update(attrs)
            for tn, tv in o["tags"].items():
                # Value="*noinherit" marks a tag that applies to THIS object only
                # (BaseObject on a template whose children are the real spawns)
                if tv == "*noinherit" and o is not ch[0]:
                    continue
                r["tags"][tn] = tv
        self._resolved[name] = r
        return r

    def render(self, name):
        return self.get(name)["parts"].get("Render", {})

    def tile(self, name):
        return self.render(name).get("Tile")

    def is_abstract(self, name):
        """Base/template objects the game never spawns as-is."""
        o = self.get(name)
        if name.startswith("Base") or name.startswith("_") or " Base" in name:
            return True
        if o["tags"].get("BaseObject") is not None:
            return True
        return False

    def stat_int(self, name, stat, default=None):
        s = self.get(name)["stats"].get(stat)
        if not s:
            return default
        for key in ("Value", "sValue"):
            v = s.get(key)
            if v:
                m = re.match(r"-?\d+", v)
                if m:
                    return int(m.group(0))
        return default


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def color_letter(render, key):
    """The one-letter colour code for TileColor/DetailColor/ColorString ('&r^w' -> 'r')."""
    v = render.get(key)
    if not v:
        return None
    if key == "DetailColor":
        return v[:1]
    i = v.rfind("&")
    if i >= 0 and i + 1 < len(v):
        return v[i + 1]
    return v[:1] if len(v) == 1 else None
