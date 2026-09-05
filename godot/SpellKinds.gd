# What a monster's or companion's spell does in the shooter, read off its name, shape and
# the game's own description text. One place, no dependencies, so RiftType, Showcase and
# the feedback panel can all ask without pulling each other in.
class_name SpellKinds
extends RefCounted


# What a spell does here, from its name and shape. Shared by monsters, bosses and companions.
static func classify(spl: Dictionary) -> String:
	var nm := String(spl.get("name", "")).to_lower()
	var dtypes: Array = spl.get("damage_type", [])
	var rng_ := float(spl.get("range", 0))
	var d = spl.get("description", {})
	var text := (String(d.get("text", "")) if d is Dictionary else String(d)).to_lower()
	for w in ["drain", "siphon", "leech", "vampir"]:
		if w in nm:
			return "drain"
	if text.begins_with("summon") or text.contains("
summon"):
		return "summon"
	if text.begins_with("heal"):
		return "heal"
	for w in ["heal", "restor", "regen", "mend", "blessing", "harmony"]:
		if w in nm:
			return "heal"
	if bool(spl.get("melee", false)) or "pounce" in nm or "charge" in nm or "ambush" in nm or "swings" in nm:
		return "lunge"
	for w in ["shield", "ward", "armor", "protect", "binding"]:
		if w in nm:
			return "shield"
	for w in ["drain", "siphon", "leech", "vampir"]:
		if w in nm:
			return "drain"
	for w in ["summon", "spawn", "hatch", "call", "raise", "gather", "forge", "deploy", "torrent of", "flock", "gate", "eggs", "jar", "spew", "brew"]:
		if w in nm:
			return "summon"
	for w in ["storm", "rain", "hail", "barrage", "salvo", "volley", "shrapnel"]:
		if w in nm:
			return "rain"
	for w in ["nova", "burst", "wave", "pulse", "quake", "blast", "explosion", "shatter", "eruption", "stomp"]:
		if w in nm:
			return "ring"
	for w in ["beam", "lightning", "ray", "flamethrower", "breath"]:
		if w in nm:
			return "beam"
	for w in ["gaze", "cloud", "poison", "miasma", "curse", "hex", "aura", "spit", "acid", "rot", "plague"]:
		if w in nm:
			return "cloud"
	for w in ["teleport", "blink", "shift", "phase", "step", "passage"]:
		if w in nm:
			return "blink"
	if dtypes.is_empty() and rng_ <= 0.0:
		return "buff"
	if dtypes.is_empty():
		return "buff"
	return "bolt"
