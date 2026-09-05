# Autoload: access to the exported game assets under res://qud/ (gitignored,
# generated from the player's own Rift Wizard 3 install).
extends Node

const ROOT := "res://qud/"

var manifest := {}
var monsters := []
var _tex := {}


func _ready() -> void:
	manifest = Shared.load_json(ROOT + "manifest.json")
	monsters = _load_array(ROOT + "data/monsters.json")


func _load_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Array else []


func texture(rel: String) -> Texture2D:
	if _tex.has(rel):
		return _tex[rel]
	var path := ROOT + rel
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		var gp := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(gp):
			var img := Image.load_from_file(gp)
			if img:
				tex = ImageTexture.create_from_image(img)
	if tex == null:
		push_warning("QUD: missing texture %s" % rel)
	_tex[rel] = tex
	return tex


func has_unit(unit: String) -> bool:
	return manifest.get("units", {}).has(unit)


func unit_info(unit: String) -> Dictionary:
	return manifest.get("units", {}).get(unit, {"frame_size": 60, "idle_frames": 1, "attack_frames": 1, "radius": 0})


func unit_idle(unit: String) -> Texture2D:
	return texture("units/%s_idle.png" % unit)


func icon(spell: String) -> Texture2D:
	return texture("icons/%s.png" % spell)


func effect(name: String) -> Texture2D:
	return texture("effects/%s.png" % name)


func font() -> Font:
	var path := ROOT + "fonts/SpecialElite-Regular.ttf"
	if ResourceLoader.exists(path):
		return load(path)
	return ThemeDB.fallback_font


# Boss candidates for a realm: rare monsters by tier, or final bosses at the end.
func bosses(realm: int, final := false) -> Array:
	var band := clampi(1 + int(round((realm - 1) * 8.0 / 19.0)), 1, 9)
	var out := []
	for m in monsters:
		if m.has("error") or not bool(m.get("asset_exists", false)):
			continue
		var asset: Array = m.get("asset", [])
		if asset.size() < 2 or asset[0] != "char" or not has_unit(asset[1]):
			continue
		for r in m.get("roles", []):
			var role := String(r.get("role", ""))
			var ok := false
			if final and role == "final_boss":
				ok = true
			elif not final and role == "rare" and int(m.get("radius", 0)) <= 1:
				var tier := String(r.get("tier", "easy"))
				ok = (band <= 3 and tier == "easy") or (band > 3 and band <= 6 and tier in ["easy", "med"]) or (band > 6)
			if ok:
				out.append({"name": m["name"], "unit": asset[1], "hp": float(m.get("max_hp", 30)), "flying": bool(m.get("flying", false)),
					"spells": m.get("spells", []), "radius": int(m.get("radius", 0))})
				break
	return out


# Racers from the game's spawn tables: common monsters with a single-tile sprite.
func roster(count: int, rng: RandomNumberGenerator, max_band := 4, min_band := 1) -> Array:
	var pool := []
	var seen := {}
	for m in monsters:
		if m.has("error") or m.get("radius", 0) != 0 or not m.get("asset_exists", false):
			continue
		var ok := false
		for r in m.get("roles", []):
			if r.get("role") == "spawn" and int(r.get("difficulty_band", 99)) <= max_band and int(r.get("difficulty_band", 0)) >= min_band:
				ok = true
		if not ok or seen.has(m["name"]):
			continue
		var asset: Array = m.get("asset", [])
		if asset.size() < 2 or asset[0] != "char" or not has_unit(asset[1]):
			continue
		seen[m["name"]] = true
		pool.append({"name": m["name"], "unit": asset[1], "hp": float(m.get("max_hp", 10)), "flying": bool(m.get("flying", false)), "spells": m.get("spells", [])})
	if pool.size() < count:
		for n in ["goblin", "bat", "hornet", "orc", "ghost", "mantis", "boggart", "kobold", "green_slime", "witch", "pumpkinhead", "ogre"]:
			if has_unit(n) and not seen.has(n):
				pool.append({"name": n.capitalize(), "unit": n, "hp": 10.0, "flying": n in ["bat", "hornet", "ghost"]})
				seen[n] = true
	var out := []
	var idx := []
	for i in pool.size():
		idx.append(i)
	for i in range(idx.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	for i in min(count, idx.size()):
		out.append(pool[idx[i]])
	return out
