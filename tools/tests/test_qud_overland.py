"""The overland export (docs/overland.md G3): baked chunks resolved to what Godot draws."""
import glob
import os

import pytest

import qud_assets
import qud_overland as ov
import qud_world as qw

HAVE_STORE = os.path.exists(qud_assets.path("data", "ObjectBlueprints.xml")) or os.path.isdir(qud_assets.path("data"))
needs_store = pytest.mark.skipif(not HAVE_STORE, reason="asset store not extracted")
BAKED = sorted(glob.glob(os.path.join(ov.chunks_root(), "*", "JoppaWorld.11.22.1.1.10.json")))


def test_norm_tile_unflattens_atlas_names():
    assert ov.norm_tile("Assets_Content_Textures_Tiles_fence_ew.bmp") == "Tiles/fence_ew.bmp"
    assert ov.norm_tile("assets_content_textures_tiles_tile-grass1.png") == "Tiles/tile-grass1.png"
    assert ov.norm_tile("Terrain/sw_grass2.bmp") == "Terrain/sw_grass2.bmp"
    assert ov.norm_tile("Creatures/sw_glowfish.bmp") == "Creatures/sw_glowfish.bmp"


def test_color_letters_from_qud_strings():
    assert ov.main_letter("&w^k") == "w"
    assert ov.main_letter("&G") == "G"
    assert ov.main_letter("") == "y"
    assert ov.detail_letter("k") == "k"
    assert ov.detail_letter("") == "Y"
    assert ov.rgb_hex("&r") == "a64a2e"


def test_ground_atlas_dedups_and_indexes():
    atlas = ov.GroundAtlas()
    a = atlas.index("Tiles/tile-dirt1.png", "&w", "k")
    b = atlas.index("Tiles/tile-dirt1.png", "&w", "k")
    c = atlas.index("Tiles/tile-dirt1.png", "&y", "k")
    assert a == b and c == a + 1
    assert atlas.entries[a] == ("Tiles/tile-dirt1.png", "w", "k")
    assert atlas.entries[c] == ("Tiles/tile-dirt1.png", "y", "k")


class FakeBP:
    def chain(self, name):
        chains = {"BrinestalkWall": ["Wall", "Object"], "DirtPath": ["Floor", "Object"],
                  "Watervine": ["Plant", "Object"], "Glowfish": ["Creature", "Object"],
                  "BrinestalkFence": ["Wall", "Fence", "Object"]}
        return [{"name": c} for c in chains.get(name, ["Object"])]

    def render(self, name):
        return {"Tile": "x.bmp"}


def test_kind_of_palette_entry():
    e = lambda **k: dict({"name": "", "tile": "t.bmp", "wall": False, "solid": False, "liquid": False,
                          "creature": False, "ground": False}, **k)
    bp = FakeBP()
    assert ov.kind_of(bp, e(name="[painted ground]", ground=True)) == "ground"
    assert ov.kind_of(bp, e(name="Pond", liquid=True)) == "water"
    assert ov.kind_of(bp, e(name="BrinestalkWall", wall=True, solid=True)) == "wall"
    assert ov.kind_of(bp, e(name="BrinestalkFence", wall=True, solid=True)) == "prop"
    assert ov.kind_of(bp, e(name="DirtPath")) == "floor"
    assert ov.kind_of(bp, e(name="Glowfish", creature=True)) == "creature"
    assert ov.kind_of(bp, e(name="Watervine")) == "prop"
    assert ov.kind_of(bp, e(name="Nothing", tile="")) == "skip"


@needs_store
@pytest.mark.skipif(not BAKED, reason="no baked Joppa chunk on this machine")
def test_joppa_chunk_resolves(tmp_path):
    import export_godot_assets as X
    import qud_blueprints as B
    bp = B.Blueprints(qud_assets.path("data"))
    families = {f[:-5]: f[:-5] for f in os.listdir(qud_assets.path("walls")) if f.endswith(".json")} if os.path.isdir(qud_assets.path("walls")) else {}
    wx = ov.WorldExporter(bp, str(tmp_path), families, {}, X.paint, X.scaled, X.load_tile)
    ch = qw.load_chunk(BAKED[0])
    res = wx.resolve_chunk(ch)
    kinds = [p["kind"] for p in res["palette"]]
    weighted = sum(1 for (x, y, i) in ch.objs if kinds[i] != "skip") / max(1, len(ch.objs))
    assert weighted >= 0.97, "resolved %.3f of Joppa's objects; skipped: %s" % (
        weighted, sorted({res["palette"][i]["name"] for (x, y, i) in ch.objs if kinds[i] == "skip"}))
    assert "wall" in kinds and "water" in kinds and "floor" in kinds
    assert all(p["fam"] for p in res["palette"] if p["kind"] == "wall")
    assert len(res["ground"]) == 2000 and max(res["ground"]) < len(wx.atlas.entries)
    walls = [p for p in res["palette"] if p["kind"] == "wall"]
    assert any(p["fam"] == "wall_brinestalk" for p in walls), [p["fam"] for p in walls]
    assert any(p.get("radius", 0) > 0 for p in res["palette"]), "Joppa's torchposts carry a light radius"
    # painted grass stands up: no grass in the floor atlas, standing entries in the objects
    assert not any("grass" in t[0].lower() for t in wx.atlas.entries)
    standing = [p for p in res["palette"] if p["name"].startswith("[painted ") and p["name"] != "[painted ground]"]
    assert standing and all(p["kind"] == "prop" and p["art"] for p in standing)
    assert len(res["objs"]) > len(ch.objs), "the grass cells became objects"
    # Qud's light-occluders (brinestalk, trees) stand at twice the size
    big = {p["name"] for p in res["palette"] if p.get("scale") == 2}
    assert "Brinestalk" in big, big
    assert all(p.get("scale", 1) == 1 for p in res["palette"] if p["kind"] != "prop")


def test_vegetation_rule_matches_raves():
    assert ov.is_vegetation("Terrain/sw_grass2.bmp")
    assert ov.is_vegetation("assets_content_textures_tiles_tile-grass1.png")
    assert ov.is_vegetation("Creatures/sw_plant3.bmp")
    assert not ov.is_vegetation("Tiles/tile-dirt1.png")
    assert not ov.is_vegetation("Terrain/sw_ground_dots1.png")


@needs_store
@pytest.mark.skipif(not BAKED, reason="no baked Joppa chunk on this machine")
def test_fauna_comes_from_the_region(tmp_path):
    import export_godot_assets as X
    import qud_blueprints as B
    bp = B.Blueprints(qud_assets.path("data"))
    units = {"GiantDragonfly": "giant_dragonfly", "Glowpad": "glowpad", "Croc": "croc", "Glowfish": "glowfish"}
    wx = ov.WorldExporter(bp, str(tmp_path), {}, units, X.paint, X.scaled, X.load_tile)
    for path in sorted(glob.glob(os.path.join(os.path.dirname(BAKED[0]), "JoppaWorld.*.json"))):
        wx.resolve_chunk(qw.load_chunk(path))
    f = wx.fauna()
    assert [e[0] for e in f["flying"]][:1] == ["GiantDragonfly"]
    ground = [e[0] for e in f["ground"]]
    assert "Glowpad" not in ground and "Glowfish" not in ground, "rooted and aquatic things do not roam"
    assert "Croc" in ground
