# Autoload: the game's 186 player spells (qud/data/spells.json) and the rule
# that turns each one into a kart effect. See docs/campaign.md.
extends Node

const TILE_PX := 90.0
const RADIUS_PX := 70.0
const TURN_S := 0.8

var spells: Array = []
var by_name := {}


func _ready() -> void:
	var path := QUD.ROOT + "data/spells.json"
	if not FileAccess.file_exists(path):
		push_error("SpellDB: missing %s (run tools/export_godot_assets.py)" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Array):
		return
	for s in data:
		if s.has("error") or int(s.get("level", 0)) <= 0:
			continue
		spells.append(s)
		by_name[s["name"]] = s
	spells.sort_custom(func(a, b):
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) < int(b["level"])
		return String(a["name"]) < String(b["name"]))


func icon_name(spell: Dictionary) -> String:
	var asset: Array = spell.get("asset", [])
	if asset.size() > 0:
		return String(asset[asset.size() - 1])
	return String(spell["name"]).to_lower().replace(" ", "_")


func icon(spell: Dictionary) -> Texture2D:
	return QUD.icon(icon_name(spell))


func description(spell: Dictionary) -> String:
	var d = spell.get("description", {})
	if d is Dictionary:
		return String(d.get("text", ""))
	return String(d)


# The game casts a spell with max_charges 0 as often as you like (Level.py only checks and
# spends charges when max_charges is nonzero); here that becomes a short real-time cooldown.
# hp_cost is paid per cast, as in the game's Blood spells.
func make_owned(spell: Dictionary) -> Dictionary:
	var unlimited := int(spell.get("max_charges", 3)) <= 0
	var charges := 0 if unlimited else maxi(1, mini(12, int(spell.get("max_charges", 3))))
	return {
		"name": spell["name"],
		"level": int(spell["level"]),
		"tags": spell.get("tags", []),
		"icon": icon_name(spell),
		"desc": description(spell),
		"upgrades": [],
		"max_charges": charges,
		"charges": charges,
		"unlimited": unlimited,
		"cooldown": float(Shared.t(["campaign", "unlimited_cooldown"], 0.6)) if unlimited else 0.0,
		"cd": 0.0,
		"hp_cost": int(spell.get("hp_cost", 0)),
		"effect": effect_for(spell),
		"unit": summon_unit(spell),
	}


# Map a spell's stats and tags onto one of the kart effect kinds.
func effect_for(spell: Dictionary) -> Dictionary:
	var st: Dictionary = spell.get("stats", {})
	var tags: Array = spell.get("tags", [])
	var name := String(spell["name"])
	var dmg := float(st.get("damage", 0))
	var rng := float(spell.get("range", 5))
	var level := int(spell.get("level", 1))
	var dtypes: Array = spell.get("damage_type", [])
	var dtype := "Arcane"
	if dtypes.size() > 0:
		dtype = String(dtypes[0])
	else:
		for t in tags:   # prefer an elemental tag over Sorcery/Enchantment/Conjuration
			if Items.TYPE_COLORS.has(String(t)):
				dtype = String(t)
				break
	var e := {"kind": "bolt", "damage": maxf(dmg, 5.0 * level), "range": maxf(300.0, rng * TILE_PX), "dtype": dtype,
			  "duration": float(st.get("duration", 5)) * TURN_S}

	if bool(spell.get("melee", false)):
		e["kind"] = "melee"
		e["range"] = float(Shared.t(["campaign", "melee_range"], 90.0))
		e["targets"] = mini(4, int(st.get("num_targets", 1)))
	elif st.has("minion_health"):
		e["kind"] = "summon"
		e["hp"] = float(st.get("minion_health", 10))
		e["damage"] = maxf(2.0, float(st.get("minion_damage", 3)))
		e["duration"] = float(st.get("minion_duration", 12)) * TURN_S
		e["count"] = mini(3, int(st.get("num_summons", 1)))
	elif dmg > 0.0:
		if st.has("radius"):
			e["kind"] = "blast"
			e["radius"] = maxf(60.0, float(st.get("radius", 1)) * RADIUS_PX)
		elif "Lightning" in tags or name.containsn("bolt") or name.containsn("beam") or name.containsn("ray"):
			e["kind"] = "beam"
		else:
			e["kind"] = "bolt"
		e["targets"] = mini(4, int(st.get("num_targets", 1)))
	elif st.has("shields"):
		e["kind"] = "shield"
		e["shields"] = int(st.get("shields", 1))
	elif st.has("heal") or "Heal" in tags:
		e["kind"] = "heal"
		e["amount"] = maxf(8.0, float(st.get("heal", 4 * level)))
	elif bool(spell.get("self_target", false)) or rng <= 0.0:
		e["kind"] = "buff"
		e["strength"] = 0.2 + 0.03 * level
	elif "Translocation" in tags:
		e["kind"] = "blink"
		e["distance"] = maxf(300.0, rng * TILE_PX)
	elif st.has("duration"):
		e["kind"] = "hex"
	# hand-written overrides win over the rules above (shared/overrides.json, "spells": {name: {...}})
	var ov: Dictionary = Shared.overrides.get("spells", {}).get(name, {})
	for k in ov:
		if k != "notes":
			e[k] = ov[k]
	return e


const SUMMON_BY_TAG := {
	"Fire": "fire_elemental", "Ice": "ice_elemental", "Lightning": "spark_spirit", "Nature": "wolf",
	"Dark": "ghost", "Holy": "angelic_singer", "Arcane": "void_child", "Blood": "blood_wolf",
	"Metallic": "golem", "Chaos": "chaos_spirit", "Poison": "green_slime",
}


# Which unit sprite a summon spell produces: a unit named in the spell, else by tag.
func summon_unit(spell: Dictionary) -> String:
	var name := String(spell["name"]).to_lower()
	var words := name.replace("summon", "").replace("call", "").strip_edges().split(" ", false)
	for w in words:
		for cand in [w, w.trim_suffix("s"), w.trim_suffix("es")]:
			if QUD.has_unit(cand):
				return cand
	if words.size() >= 2:
		for i in range(words.size() - 1):
			var two := "%s_%s" % [words[i], words[i + 1]]
			if QUD.has_unit(two):
				return two
	for tag in spell.get("tags", []):
		if SUMMON_BY_TAG.has(tag) and QUD.has_unit(SUMMON_BY_TAG[tag]):
			return SUMMON_BY_TAG[tag]
	return "wolf"


# ---------------------------------------------------------------- the game's named upgrades

# The upgrades of a spell not yet taken (by name), cheapest first.
func upgrade_options(spell: Dictionary, taken: Array) -> Array:
	var out := []
	for up in spell.get("upgrades", []):
		if up.has("error") or taken.has(String(up.get("name", ""))):
			continue
		out.append(up)
	out.sort_custom(func(a, b): return int(a.get("level", 1)) < int(b.get("level", 1)))
	return out


# Apply one of the game's upgrades to a mapped effect. The game stores what an upgrade
# changes (bonuses to existing stats, new stats it introduces, added damage types); the
# numeric ones map like the base stats do, flags fall back to the upgrade's own text.
# Returns {"summary": String, "charges": int, "hp_cost": int} (the last two are deltas).
func apply_upgrade(e: Dictionary, up: Dictionary) -> Dictionary:
	var kind := String(e.get("kind", "bolt"))
	var text := String(description(up)).to_lower()
	var changes := []
	var charges := 0
	var hp_cost := 0
	var numeric := false
	var amounts := {}
	var fresh := {}   # attributes the base spell did not have: in the game they set the value, not add to it
	for src in [up.get("bonuses", {}), up.get("new_attributes", {})]:
		for k in src:
			amounts[k] = float(amounts.get(k, 0.0)) + float(src[k])
	for k in up.get("new_attributes", {}):
		fresh[k] = true
	for attr in amounts:
		var v: float = amounts[attr]
		if fresh.has(attr) and attr in ["num_targets", "num_summons", "shields"]:
			# set-to: the effect already has a base of 1, so add what is beyond it
			var base := int(e.get({"num_targets": "targets", "num_summons": "count", "shields": "shields"}[attr], 1))
			v = maxf(0.0, v - base)
			if v <= 0.0:
				continue
		match attr:
			"damage":
				e["damage"] = float(e.get("damage", 0.0)) + v
				changes.append("+%d damage" % int(v))
				numeric = true
			"range":
				if kind == "blink":
					e["distance"] = float(e.get("distance", 340.0)) + v * TILE_PX
				else:
					e["range"] = float(e.get("range", 300.0)) + v * TILE_PX
				changes.append("+%d range" % int(v))
				numeric = true
			"radius":
				e["radius"] = float(e.get("radius", 60.0)) + v * RADIUS_PX
				if kind in ["bolt", "beam"] and v > 0.0:
					e["kind"] = "blast"   # a radius on a single-target spell: it bursts now
					changes.append("bursts")
				changes.append("+%d radius" % int(v))
				numeric = true
			"duration":
				if kind in ["aura", "patch", "buff", "empower", "hex", "summon"]:
					e["duration"] = float(e.get("duration", 4.0)) + v * TURN_S
					changes.append("+%.1fs" % (v * TURN_S))
				elif text.contains("stun") or text.contains("frozen") or text.contains("freez") or text.contains("petrif") or text.contains("blind"):
					e["stun"] = minf(2.5, float(e.get("stun", 0.0)) + v * TURN_S * 0.5)
					changes.append("stuns %.1fs" % float(e["stun"]))
				else:
					e["damage"] = float(e.get("damage", 0.0)) + v * 1.5   # poison, burning, bleeding: damage over time, collapsed
					changes.append("+%d damage over time" % int(v * 1.5))
				numeric = true
			"num_targets":
				e["targets"] = int(e.get("targets", 1)) + int(v)
				if kind == "bolt":
					e["count"] = maxi(int(e.get("count", 1)), int(e["targets"]))
				changes.append("+%d targets" % int(v))
				numeric = true
			"num_summons":
				e["count"] = int(e.get("count", 1)) + int(v)
				changes.append("+%d summons" % int(v))
				numeric = true
			"minion_damage":
				e["damage"] = float(e.get("damage", 0.0)) + v
				changes.append("+%d summon damage" % int(v))
				numeric = true
			"minion_health":
				e["damage"] = float(e.get("damage", 0.0)) + v * 0.2
				changes.append("tougher summons")
				numeric = true
			"minion_duration":
				e["duration"] = float(e.get("duration", 8.0)) + v * TURN_S
				changes.append("longer summons")
				numeric = true
			"max_charges":
				charges += int(v)
				changes.append("+%d charges" % int(v))
				numeric = true
			"hp_cost":
				hp_cost += int(v)
				changes.append("%+d HP cost" % int(v))
				numeric = true
			"shields":
				e["shields"] = int(e.get("shields", 1)) + int(v)
				if kind != "shield":
					e["kind"] = "shield"
				changes.append("+%d shields" % int(v))
				numeric = true
			"heal":
				e["amount"] = float(e.get("amount", 8.0)) + v
				if kind == "heal":
					changes.append("+%d healing" % int(v))
				else:
					e["heal_frac"] = maxf(float(e.get("heal_frac", 0.0)), 0.5)
					changes.append("drains")
				numeric = true
			_:
				pass
	for dt in up.get("damage_type", []):
		e["damage"] = float(e.get("damage", 0.0)) * 1.2
		changes.append("+%s damage" % String(dt))
		numeric = true
	if not numeric:
		# a pure flag: read the game's words
		if text.contains("stun") or text.contains("petrif"):
			e["stun"] = maxf(float(e.get("stun", 0.0)), 1.2)
			changes.append("stuns")
		elif text.contains("freez") or text.contains("frozen"):
			e["stun"] = maxf(float(e.get("stun", 0.0)), 1.6)
			changes.append("freezes")
		elif text.contains("blind"):
			e["stun"] = maxf(float(e.get("stun", 0.0)), 0.8)
			changes.append("blinds")
		elif text.contains("heal") or text.contains("drain") or text.contains("lifesteal"):
			e["heal_frac"] = maxf(float(e.get("heal_frac", 0.0)), 0.5)
			changes.append("drains")
		elif text.contains("bounce") or text.contains("chain") or text.contains("additional") or text.contains("more target") or text.contains("extra target"):
			e["targets"] = int(e.get("targets", 1)) + 1
			if kind == "bolt":
				e["count"] = maxi(int(e.get("count", 1)), int(e["targets"]))
			changes.append("+1 target")
		elif text.contains("radius") or text.contains("burst") or text.contains("area"):
			e["radius"] = float(e.get("radius", 60.0)) + RADIUS_PX
			if kind in ["bolt", "beam"]:
				e["kind"] = "blast"
			changes.append("bigger area")
		elif text.contains("summon"):
			e["count"] = int(e.get("count", 1)) + 1
			changes.append("+1 summon")
		elif text.contains("teleport") or text.contains("blink"):
			e["distance"] = float(e.get("distance", 340.0)) + 2 * TILE_PX
			changes.append("further")
		elif text.contains("pull"):
			e["shove"] = -500.0
			changes.append("pulls")
		elif text.contains("push") or text.contains("knock"):
			e["shove"] = 500.0
			changes.append("shoves")
		elif text.contains("poison") or text.contains("burn") or text.contains("bleed") or text.contains("acid"):
			e["damage"] = float(e.get("damage", 0.0)) * 1.3
			changes.append("+30% damage over time")
		else:
			e["damage"] = float(e.get("damage", 0.0)) * 1.2
			changes.append("+20% damage")
	return {"summary": ", ".join(changes), "charges": charges, "hp_cost": hp_cost}


static func kind_verb(kind: String) -> String:
	return {"bolt": "shoots", "blast": "hurls", "beam": "strikes", "summon": "summons", "shield": "shields",
			"heal": "heals", "buff": "boosts", "blink": "blinks", "hex": "freezes", "melee": "swipes",
			"burst": "erupts", "aura": "radiates", "patch": "lays", "empower": "empowers"}.get(kind, "casts")
