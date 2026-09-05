# Autoload: the shared/ JSON contract (tracks + tuning), copied into qud/shared
# by tools/export_godot_assets.py so exported builds carry it too.
extends Node

var tracks := {}
var tuning := {}
var overrides := {}   # shared/overrides.json: hand-written mappings by spell/artifact name (see docs/rulebook.md)
var realms := []      # qud/levels/index.json: the game's generated realm dumps (tools/extract_levels.py)


func _ready() -> void:
	tuning = load_json("res://qud/shared/tuning.json")
	overrides = load_json("res://qud/shared/overrides.json")
	var t := load_json("res://qud/shared/tracks.json")
	for tr in t.get("tracks", []):
		tracks[tr["key"]] = tr
	if tuning.is_empty() or tracks.is_empty():
		push_error("Drift Wizard 3: qud/shared is missing. Run tools/export_godot_assets.py")
	var idx = load_json_any("res://qud/levels/index.json")
	if idx is Array:
		realms = idx


func load_json_any(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())


# The realm dumps for a difficulty (three per realm), sorted by file name.
func realm_options(difficulty: int) -> Array:
	var out := []
	for e in realms:
		if int(e["difficulty"]) == clampi(difficulty, 1, 21):
			out.append(e)
	out.sort_custom(func(a, b): return String(a["file"]) < String(b["file"]))
	return out


func load_realm(file: String) -> Dictionary:
	var d = load_json_any("res://qud/levels/" + file)
	return d if d is Dictionary else {}


func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("missing %s (run tools/export_godot_assets.py)" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func t(path: Array, default = null):
	var node = tuning
	for k in path:
		if node is Dictionary and node.has(k):
			node = node[k]
		else:
			return default
	return node
