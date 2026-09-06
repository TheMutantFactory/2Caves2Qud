# Autoload: the run. Persists between realm scenes (the race scene reloads
# for each realm). See docs/campaign.md.
extends Node

const MAX_LEVEL := 20
const MAX_SLOTS := 10

var active := false
var level := 1
var hp := 50.0
var max_hp := 50.0
var sp := 3
var spells: Array = []          # owned spells (SpellDB.make_owned dicts)
var artifacts: Array = []       # owned artifacts (Artifacts.make_owned dicts)
var offers: Array = []          # quick-shop offers (SpellDB entries)
var kills := 0
var next_track := "realm"     # "realm" = a track built from one of the game's realm dumps; else a tracks.json key
var realm_file := ""          # which dump of the realm (three per difficulty)
var seed := 0
var run_rng := RandomNumberGenerator.new()
var last_result := {}
var skin := "player"          # wardrobe outfit unit name, saved to user://drift.cfg
var rig := ""                 # test-rig preset set by the menu (docs/test-rig.md)
var race_type := "gp"         # gp (wizards race you), campaign (the realm's monsters), single, rig
var racer := {"kind": "wizard", "unit": "player", "name": "Wizard"}   # who you drive as
var unlocked: Array = []      # monster names slain at least once: selectable racers (saved)


func _ready() -> void:
	var cfg_file := ConfigFile.new()
	if cfg_file.load("user://drift.cfg") == OK:
		var s := String(cfg_file.get_value("wizard", "skin", "player"))
		if QUD.has_unit(s):
			skin = s
		var ul = cfg_file.get_value("unlocks", "monsters", [])
		if ul is Array:
			unlocked = ul
		var rc = cfg_file.get_value("wizard", "racer", {})
		if rc is Dictionary and rc.has("unit") and QUD.has_unit(String(rc["unit"])):
			racer = rc
	if racer.get("kind", "wizard") == "wizard":
		racer = {"kind": "wizard", "unit": skin, "name": Wardrobe.skin_label(skin) + " Wizard"}


func set_racer(kind: String, unit: String, name: String) -> void:
	racer = {"kind": kind, "unit": unit, "name": name}
	if kind == "wizard":
		skin = unit
	_save_cfg()


# A slain monster becomes a racer you can pick.
func unlock(monster_name: String) -> bool:
	if unlocked.has(monster_name):
		return false
	unlocked.append(monster_name)
	_save_cfg()
	return true


func _save_cfg() -> void:
	var cfg_file := ConfigFile.new()
	cfg_file.load("user://drift.cfg")
	cfg_file.set_value("wizard", "skin", skin)
	cfg_file.set_value("wizard", "racer", racer)
	cfg_file.set_value("unlocks", "monsters", unlocked)
	cfg_file.save("user://drift.cfg")


func set_skin(unit: String) -> void:
	skin = unit
	if racer.get("kind", "wizard") == "wizard":
		racer = {"kind": "wizard", "unit": unit, "name": Wardrobe.skin_label(unit) + " Wizard"}
	_save_cfg()
var debug_t0_ms := 0   # screenshot runs: deadline survives scene reloads


func cfg(key: String, default = null):
	return Shared.t(["campaign", key], default)


func new_run(p_seed := -1) -> void:
	active = true
	level = 1
	max_hp = float(cfg("max_hp", 50))
	hp = max_hp
	sp = int(cfg("start_sp", 3))
	spells = []
	artifacts = []
	offers = []
	kills = 0
	last_result = {}
	run_rng.seed = p_seed if p_seed >= 0 else int(Time.get_ticks_usec() % 2147483647)
	next_track = "realm"
	realm_file = ""
	seed = run_rng.randi()


func pick_track() -> String:
	realm_file = ""
	return "realm"


# The dump for the current realm: the chosen one, else one picked by the run seed.
func current_realm() -> Dictionary:
	var opts := Shared.realm_options(level)
	if opts.is_empty():
		return {}
	var e: Dictionary = opts[0]
	if realm_file != "":
		for o in opts:
			if String(o["file"]) == realm_file:
				e = o
	else:
		e = opts[abs(seed) % opts.size()]
	return Shared.load_realm(String(e["file"]))


func _random_track() -> String:
	var keys := Shared.tracks.keys()
	keys.sort()
	if keys.is_empty():
		return "brick"
	return keys[run_rng.randi_range(0, keys.size() - 1)]


func band() -> int:
	return clampi(1 + int(round((level - 1) * 8.0 / 19.0)), 1, 9)


func cost(spell: Dictionary) -> int:
	return maxi(1, int(spell.get("level", 1)))


func owns(spell_name: String) -> bool:
	for s in spells:
		if s["name"] == spell_name:
			return true
	return false


func can_buy(spell: Dictionary) -> bool:
	return spells.size() < MAX_SLOTS and sp >= cost(spell) and not owns(spell["name"])


func buy(spell: Dictionary) -> bool:
	if not can_buy(spell):
		return false
	sp -= cost(spell)
	var owned := SpellDB.make_owned(spell)
	var extra := int(bonus("charges"))
	owned["max_charges"] = int(owned["max_charges"]) + extra
	owned["charges"] = int(owned["charges"]) + extra
	spells.append(owned)
	return true


func _owned(spell: Dictionary) -> Dictionary:
	var owned := SpellDB.make_owned(spell)
	var extra := int(bonus("charges"))
	owned["max_charges"] = int(owned["max_charges"]) + extra
	owned["charges"] = int(owned["charges"]) + extra
	return owned


# A spell scroll on the track: free, no SP. Returns "learned", "charge" (already owned) or "full".
func learn(spell: Dictionary) -> String:
	for s in spells:
		if s["name"] == spell["name"]:
			s["charges"] = mini(int(s["max_charges"]), int(s["charges"]) + 1)
			return "charge"
	if spells.size() >= MAX_SLOTS:
		return "full"
	spells.append(_owned(spell))
	return "learned"


# Test rig: put a spell into slot i (replacing what is there), or refill it if already owned.
func set_slot(i: int, spell: Dictionary) -> String:
	for s in spells:
		if s["name"] == spell["name"]:
			s["charges"] = int(s["max_charges"])
			s["cd"] = 0.0
			return "charge"
	var owned := _owned(spell)
	if i >= 0 and i < spells.size():
		spells[i] = owned
		return "replaced"
	spells.append(owned)
	return "learned"


var tour_index := 0            # the tour (Tour.gd): which course is next across scene reloads
var rift := {}                 # Rift-Type: the run carried from one realm to the next (see RiftType._save_progress)
var rift_page := false         # Rift-Type: the menu opens on the realm select
var temp_bonuses: Array = []   # [{bonuses: {key: value}, left: seconds}] from "empower" spells


# Buy one of the game's named upgrades for an owned spell: costs the upgrade's level in SP.
func upgrade(spell_name: String, up: Dictionary) -> bool:
	var cost_sp := maxi(1, int(up.get("level", 1)))
	for s in spells:
		if s["name"] != spell_name:
			continue
		if s["upgrades"].has(String(up["name"])) or sp < cost_sp:
			return false
		var res := SpellDB.apply_upgrade(s["effect"], up)
		s["upgrades"].append(String(up["name"]))
		s["max_charges"] = maxi(0, int(s["max_charges"]) + int(res["charges"]))
		s["charges"] = maxi(0, int(s["charges"]) + int(res["charges"]))
		s["hp_cost"] = maxi(0, int(s.get("hp_cost", 0)) + int(res["hp_cost"]))
		sp -= cost_sp
		return true
	return false


# Sum of a bonus key over owned artifacts (see Artifacts.KEYS) and running empowerments.
func bonus(key: String) -> float:
	var total := 0.0
	for a in artifacts:
		total += float(a["effect"].get(key, 0.0))
	for tb in temp_bonuses:
		total += float(tb["bonuses"].get(key, 0.0))
	return total


func add_temp_bonus(bonuses: Dictionary, seconds: float) -> void:
	temp_bonuses.append({"bonuses": bonuses.duplicate(), "left": seconds})


func owns_artifact(a_name: String) -> bool:
	for a in artifacts:
		if a["name"] == a_name:
			return true
	return false


func grant_artifact(a: Dictionary) -> Dictionary:
	if a.is_empty():
		return {}
	var owned := Artifacts.make_owned(a)
	artifacts.append(owned)
	var e: Dictionary = owned["effect"]
	if e.has("max_hp"):
		max_hp += float(e["max_hp"])
		heal(float(e["max_hp"]))
	if e.has("charges"):
		for s in spells:
			s["max_charges"] = int(s["max_charges"]) + int(e["charges"])
			s["charges"] = int(s["charges"]) + int(e["charges"])
	return owned


func grant_random_artifact() -> Dictionary:
	var names := []
	for a in artifacts:
		names.append(a["name"])
	return grant_artifact(Artifacts.random(run_rng, names))


# Quick-shop offers: affordable, unowned spells, biased toward the pricier ones.
func roll_offers(count: int) -> void:
	offers = []
	var pool := []
	var weights := PackedFloat32Array()
	for s in SpellDB.spells:
		if cost(s) <= sp and not owns(s["name"]):
			pool.append(s)
			weights.append(float(cost(s)))
	while offers.size() < count and pool.size() > 0:
		var i := run_rng.rand_weighted(weights)
		offers.append(pool[i])
		pool.remove_at(i)
		weights.remove_at(i)


# Castable now: a charge left (or an unlimited spell off cooldown) and enough HP to pay for it.
func slot_ready(i: int) -> bool:
	if i < 0 or i >= spells.size():
		return false
	var s: Dictionary = spells[i]
	if bool(s.get("unlimited", false)):
		if float(s.get("cd", 0.0)) > 0.0:
			return false
	elif int(s["charges"]) <= 0:
		return false
	return int(s.get("hp_cost", 0)) < hp


func spend_charge(i: int) -> void:
	if i < 0 or i >= spells.size():
		return
	var s: Dictionary = spells[i]
	if bool(s.get("unlimited", false)):
		s["cd"] = float(s.get("cooldown", 0.6))
	else:
		s["charges"] = maxi(0, int(s["charges"]) - 1)
	hp = maxf(1.0, hp - int(s.get("hp_cost", 0)))


func tick_cooldowns(dt: float) -> void:
	for s in spells:
		if float(s.get("cd", 0.0)) > 0.0:
			s["cd"] = maxf(0.0, float(s["cd"]) - dt)
	for tb in temp_bonuses.duplicate():
		tb["left"] -= dt
		if tb["left"] <= 0.0:
			temp_bonuses.erase(tb)


func lap_refill() -> void:
	for s in spells:
		s["charges"] = mini(int(s["max_charges"]), int(s["charges"]) + 1)


func refill_all() -> void:
	for s in spells:
		s["charges"] = int(s["max_charges"])
		s["cd"] = 0.0


func take_damage(amount: float) -> bool:
	hp = maxf(0.0, hp - amount)
	return hp <= 0.0


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


# Three rift gates to choose from after a realm: track, reward, monster preview.
func gate_options(monster_names: Array) -> Array:
	var keys := Shared.tracks.keys()
	keys.sort()
	var rewards := [
		{"label": "+%d spell points" % int(cfg("gate_sp", 2)), "sp": int(cfg("gate_sp", 2)), "hp": 0.0, "charges": false},
		{"label": "heal %d and +1 spell point" % int(cfg("gate_heal", 25)), "sp": 1, "hp": float(cfg("gate_heal", 25)), "charges": false},
		{"label": "full recharge and +1 spell point", "sp": 1, "hp": 0.0, "charges": true},
		{"label": "an artifact and +1 spell point", "sp": 1, "hp": 0.0, "charges": false, "artifact": true},
	]
	var first := run_rng.randi_range(0, rewards.size() - 1)
	var out := []
	var nxt := Shared.realm_options(level + 1)
	for i in 3:
		var preview := []
		for k in mini(3, monster_names.size()):
			preview.append(monster_names[(i * 3 + k) % monster_names.size()])
		var gate := {"reward": rewards[(first + i) % rewards.size()], "preview": preview}
		if not nxt.is_empty() and next_track == "realm":
			var e: Dictionary = nxt[i % nxt.size()]
			gate["track"] = "realm"
			gate["realm_file"] = String(e["file"])
			gate["label"] = "Realm %d: %s %s" % [level + 1, String(e["tileset"]).capitalize(), String(e["chasm"])]
			var d := Shared.load_realm(String(e["file"]))
			preview.clear()
			for u in d.get("units", []):
				if not bool(u.get("is_lair", false)) and not preview.has(u["name"]) and preview.size() < 3:
					preview.append(u["name"])
		else:
			gate["track"] = keys[(keys.find(next_track) + 1 + i) % keys.size()] if keys.size() > 0 else "brick"
		out.append(gate)
	return out


func apply_gate(gate: Dictionary) -> void:
	level += 1
	next_track = gate["track"]
	realm_file = String(gate.get("realm_file", ""))
	seed = run_rng.randi()
	var r: Dictionary = gate["reward"]
	sp += int(r.get("sp", 0))
	heal(float(r.get("hp", 0.0)))
	if r.get("charges", false):
		refill_all()
	if r.get("artifact", false):
		grant_random_artifact()
