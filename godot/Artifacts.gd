# Autoload: the game's 350 equipment items (qud/data/equipment.json) as
# campaign artifacts. Each maps to a small set of passive bonuses, from its
# stat bonuses when it has any, otherwise from its first tag.
extends Node

const KEYS := {
	"spell_damage": "+%d spell damage", "spell_range": "+%d spell range", "spell_radius": "+%d blast radius",
	"charges": "+%d charge on every spell", "spell_duration": "+%.1fs spell duration",
	"summon_damage": "+%d summon damage", "summon_count": "+%d summon", "beam_targets": "+%d beam target",
	"speed": "+%d%% top speed", "boost": "+%d%% boost strength", "drift_charge": "%d%% faster drift charge",
	"max_hp": "+%d max HP", "lap_heal": "heal %d each lap", "lap_damage": "+%d lap damage to monsters",
	"kill_heal": "heal %d per kill", "lap_shield": "+%d shield each lap", "blink": "+%d blink distance",
}

const TAG_FALLBACK := {
	"Fire": {"speed": 0.04}, "Lightning": {"boost": 0.1}, "Ice": {"drift_charge": 0.25},
	"Nature": {"max_hp": 10}, "Holy": {"lap_heal": 5}, "Dark": {"lap_damage": 4}, "Arcane": {"charges": 1},
	"Blood": {"kill_heal": 6}, "Metallic": {"lap_shield": 1}, "Conjuration": {"summon_damage": 3},
	"Sorcery": {"spell_damage": 3}, "Enchantment": {"spell_duration": 1.5}, "Translocation": {"blink": 120},
	"Chaos": {"spell_damage": 2, "speed": 0.02},
}

var items: Array = []
var by_name := {}


func _ready() -> void:
	var path := QUD.ROOT + "data/equipment.json"
	if not FileAccess.file_exists(path):
		push_error("Artifacts: missing %s (run tools/export_godot_assets.py)" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Array):
		return
	for a in data:
		if a.has("error") or not bool(a.get("asset_exists", false)):
			continue
		items.append(a)
		by_name[a["name"]] = a


func icon_name(a: Dictionary) -> String:
	var asset: Array = a.get("asset", [])
	return String(asset[asset.size() - 1]) if asset.size() > 0 else ""


func icon(a: Dictionary) -> Texture2D:
	return QUD.texture("equipment/%s.png" % icon_name(a))


func description(a: Dictionary) -> String:
	var d = a.get("description", {})
	return String(d.get("text", "")) if d is Dictionary else String(d)


func effect_for(a: Dictionary) -> Dictionary:
	var raw := {}
	for k in a.get("global_bonuses", {}):
		raw[k] = float(raw.get(k, 0.0)) + float(a["global_bonuses"][k])
	for tag in a.get("tag_bonuses", {}):
		var d: Dictionary = a["tag_bonuses"][tag]
		for k in d:
			raw[k] = float(raw.get(k, 0.0)) + float(d[k]) * 0.5
	var e := {}
	for k in raw:
		var v: float = raw[k]
		if v <= 0.0:
			continue
		match String(k):
			"damage": e["spell_damage"] = float(e.get("spell_damage", 0.0)) + v
			"range": e["spell_range"] = float(e.get("spell_range", 0.0)) + v * 90.0
			"radius": e["spell_radius"] = float(e.get("spell_radius", 0.0)) + v * 70.0
			"max_charges": e["charges"] = 1.0
			"duration": e["spell_duration"] = float(e.get("spell_duration", 0.0)) + v * 0.8
			"minion_damage", "minion_health": e["summon_damage"] = float(e.get("summon_damage", 0.0)) + maxf(1.0, v)
			"num_summons": e["summon_count"] = 1.0
			"num_targets": e["beam_targets"] = 1.0
	if e.is_empty():
		e = _from_description(description(a))
	if e.is_empty():
		var tags: Array = a.get("tags", [])
		var fb: Dictionary = TAG_FALLBACK.get(String(tags[0]) if tags.size() > 0 else "", {"max_hp": 8})
		for k in fb:
			e[k] = float(fb[k])
	# hand-written overrides replace the whole effect (shared/overrides.json, "artifacts": {name: {...}})
	var ov: Dictionary = Shared.overrides.get("artifacts", {}).get(String(a["name"]), {})
	if not ov.is_empty():
		e = {}
		for k in ov:
			if k != "notes":
				e[k] = float(ov[k])
	return e


# What the item's own text says it does, in racer terms. First two matches win.
const KEYWORDS := [
	[["gain 1 sh", "gain 2 sh", "gain sh", "shield"], {"lap_shield": 1}],
	[["summon", "minion", "allies you", "your allies"], {"summon_damage": 3}],
	[["heal"], {"kill_heal": 4}],
	[["charge", "cooldown"], {"charges": 1}],
	[["radius", "burst"], {"spell_radius": 45}],
	[["range", "line of sight"], {"spell_range": 90}],
	[["duration", "turns longer", "lasts"], {"spell_duration": 1.5}],
	[["teleport", "blink"], {"blink": 120}],
	[["max hp", "hp", "health"], {"max_hp": 10}],
	[["speed", "quick", "haste", "move"], {"speed": 0.04}],
	[["damage"], {"spell_damage": 3}],
]


func _from_description(text: String) -> Dictionary:
	var lower := text.to_lower()
	var e := {}
	for rule in KEYWORDS:
		for word in rule[0]:
			if lower.contains(word):
				for k in rule[1]:
					e[k] = float(rule[1][k])
				break
		if e.size() >= 2:
			break
	return e


func label_for(e: Dictionary) -> String:
	var parts := []
	for k in e:
		var v: float = e[k]
		var fmt: String = KEYS.get(k, "%s")
		if k in ["speed", "boost", "drift_charge"]:
			parts.append(fmt % int(round(v * 100.0)))
		elif k == "spell_duration":
			parts.append(fmt % v)
		else:
			parts.append(fmt % int(round(v)))
	return ", ".join(parts)


func make_owned(a: Dictionary) -> Dictionary:
	var e := effect_for(a)
	return {"name": a["name"], "icon": icon_name(a), "effect": e, "label": label_for(e), "desc": description(a)}


func random(rng: RandomNumberGenerator, owned_names: Array) -> Dictionary:
	if items.is_empty():
		return {}
	for _try in 40:
		var a: Dictionary = items[rng.randi_range(0, items.size() - 1)]
		if not (a["name"] in owned_names):
			return a
	return items[rng.randi_range(0, items.size() - 1)]
