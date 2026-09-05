# A mini level in a box: the selected object doing what it does in the game, on a loop,
# so feedback can point at the thing itself. Monsters fly their pattern and cast their
# abilities at a dummy wizard; the boss cycles its phases; a companion fights beside the
# wizard; a spell is cast at a dummy monster; upgrades, artifacts and pickups show as
# a card. Lives inside a SubViewport, so it has its own world and camera.
class_name Showcase
extends Node2D

const BW := 640.0
const BH := 420.0
const TILE := 60.0

var obj: Dictionary = {}
var realm := 1
var tileset := "stone"
var t := 0.0
var rng := RandomNumberGenerator.new()
var layer: Node2D
var actor: Node2D          # the object
var actor_sprite: Sprite2D
var dummy: Node2D          # the wizard (or a goblin, for spells and companions)
var dummy_sprite: Sprite2D
var bullets: Array = []
var fx: Array = []
var minions: Array = []
var spells: Array = []     # [{name, mode, cd, left, dtype, unit}]
var phase_i := 0
var lunge_t := 0.0
var caption: Label
var passive_t := 3.0
var cast_line := ""
var passive_line := ""


func _ready() -> void:
	rng.randomize()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.09)
	bg.size = Vector2(BW, BH)
	bg.z_index = -20
	add_child(bg)
	layer = Node2D.new()
	add_child(layer)
	caption = Label.new()
	caption.add_theme_font_override("font", QUD.font())
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 1)
	caption.add_theme_constant_override("shadow_offset_y", 1)
	caption.position = Vector2(10, BH - 82)
	caption.size = Vector2(BW - 20, 78)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.z_index = 20
	add_child(caption)


func _tiles() -> void:
	var floor_tex := QUD.texture("tiles/floor_%s.png" % tileset)
	if floor_tex == null:
		floor_tex = QUD.texture("tiles/floor_stone.png")
	var wall_tex := QUD.texture("tiles/%s_wall_1.png" % tileset)
	if wall_tex == null:
		wall_tex = QUD.texture("tiles/brick_wall_1.png")
	for r in int(BH / TILE) + 1:
		for c in int(BW / TILE) + 1:
			var s := Sprite2D.new()
			var edge := r == 0 or r == int(BH / TILE) - 1
			s.texture = wall_tex if edge else floor_tex
			s.centered = false
			s.position = Vector2(c * TILE, r * TILE)
			s.z_index = -10
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if s.texture != null:
				s.scale = Vector2(TILE / s.texture.get_width(), TILE / s.texture.get_height())
			if not edge:
				s.modulate = Color(0.5, 0.5, 0.55)
			layer.add_child(s)


func _sprite(unit: String, scale := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = QUD.unit_idle(unit)
	s.hframes = maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2.ONE * scale
	return s


# obj: {kind: monster|boss|companion|spell|upgrade|artifact|thing, name, unit, spells, summons, icon, text, big, lair, stationary}
func show_object(p_obj: Dictionary, p_realm: int, p_tileset: String) -> void:
	obj = p_obj
	realm = p_realm
	tileset = p_tileset
	for c in layer.get_children():
		c.queue_free()
	bullets.clear()
	fx.clear()
	minions.clear()
	spells.clear()
	t = 0.0
	phase_i = 0
	_tiles()
	var kind := String(obj.get("kind", "thing"))
	cast_line = ""
	passive_line = ""
	_compose_caption()
	match kind:
		"monster", "boss":
			dummy = _make(Campaign.skin if QUD.has_unit(Campaign.skin) else "player", Vector2(110, BH * 0.5), 1.0)
			dummy_sprite = dummy.get_child(0)
			actor = _make(String(obj["unit"]), Vector2(BW - 130, BH * 0.5), 1.5 if kind == "boss" and not bool(obj.get("big", false)) else 1.0)
			actor_sprite = actor.get_child(0)
			actor_sprite.flip_h = true
			if bool(obj.get("lair", false)) and QUD.has_unit("lair"):
				var lair := _sprite("lair")
				lair.z_index = 1
				actor.add_child(lair)
			for spl in obj.get("spells", []):
				if spl is Dictionary:
					var cd := float(spl.get("cool_down", 0))
					var mode := SpellKinds.classify(spl)
					var dtypes: Array = spl.get("damage_type", [])
					spells.append({"name": String(spl.get("name", "")), "mode": mode, "cd": clampf(cd, 2.0, 6.0) if cd > 0.0 else 3.0, "left": 1.0 + spells.size() * 1.2,
						"dtype": String(dtypes[0]) if not dtypes.is_empty() else "Arcane", "unit": String(obj.get("summons", {}).get(String(spl.get("name", "")), "goblin"))})
		"companion":
			dummy = _make("goblin" if QUD.has_unit("goblin") else "player", Vector2(BW - 120, BH * 0.5), 1.0)
			dummy_sprite = dummy.get_child(0)
			dummy_sprite.flip_h = true
			var wiz := _make(Campaign.skin if QUD.has_unit(Campaign.skin) else "player", Vector2(150, BH * 0.5), 1.0)
			actor = _make(String(obj["unit"]), Vector2(90, BH * 0.5 + 60), 1.0)
			actor_sprite = actor.get_child(0)
			for spl in obj.get("spells", []):
				if spl is Dictionary:
					var cd := float(spl.get("cool_down", 0))
					var mode := SpellKinds.classify(spl)
					var dtypes: Array = spl.get("damage_type", [])
					spells.append({"name": String(spl.get("name", "")), "mode": mode, "cd": clampf(cd, 2.0, 6.0) if cd > 0.0 else 3.0, "left": 1.0 + spells.size() * 1.2,
						"dtype": String(dtypes[0]) if not dtypes.is_empty() else "Holy", "unit": String(obj.get("summons", {}).get(String(spl.get("name", "")), "wolf"))})
		"spell":
			dummy = _make("goblin" if QUD.has_unit("goblin") else "player", Vector2(BW - 130, BH * 0.5), 1.0)
			dummy_sprite = dummy.get_child(0)
			dummy_sprite.flip_h = true
			actor = _make(Campaign.skin if QUD.has_unit(Campaign.skin) else "player", Vector2(120, BH * 0.5), 1.0)
			actor_sprite = actor.get_child(0)
			spells.append({"name": String(obj["name"]), "mode": String(obj.get("mode", "bolt")), "cd": 2.4, "left": 0.8, "dtype": String(obj.get("dtype", "Arcane")), "unit": String(obj.get("unit", "wolf"))})
		_:
			actor = Node2D.new()
			actor.position = Vector2(BW * 0.5, BH * 0.42)
			layer.add_child(actor)
			var icon := Sprite2D.new()
			var tex: Texture2D = null
			if obj.has("icon"):
				tex = QUD.icon(String(obj["icon"]))
			if tex == null and obj.has("tile"):
				tex = QUD.texture("tiles/%s.png" % String(obj["tile"]))
			if tex == null and obj.has("unit") and QUD.has_unit(String(obj["unit"])):
				icon = _sprite(String(obj["unit"]))
				tex = icon.texture
			icon.texture = tex
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if tex != null:
				icon.scale = Vector2.ONE * minf(3.0, 140.0 / maxf(1.0, tex.get_height()))
			actor.add_child(icon)
			actor_sprite = icon


func _make(unit: String, at: Vector2, scale: float) -> Node2D:
	var n := Node2D.new()
	n.position = at
	var s := _sprite(unit, scale)
	n.add_child(s)
	n.z_index = 3
	layer.add_child(n)
	return n


func _process(dt: float) -> void:
	t += dt
	if obj.is_empty():
		return
	var kind := String(obj.get("kind", "thing"))
	if actor_sprite != null and actor_sprite.hframes > 1:
		actor_sprite.frame = int(t / 0.2) % actor_sprite.hframes
	if dummy_sprite != null and dummy_sprite.hframes > 1:
		dummy_sprite.frame = int(t / 0.2) % dummy_sprite.hframes
	match kind:
		"monster":
			_monster_motion(dt)
			passive_t -= dt
			if passive_t <= 0.0:
				passive_t = 6.0
				_act_monster_passives()
		"boss":
			actor.position = Vector2(BW - 130, BH * 0.5 + sin(t * 1.4) * (BH * 0.5 - 90.0))
		"companion":
			actor.position = Vector2(90 + sin(t * 1.5) * 12.0, BH * 0.5 + 60 + cos(t * 1.1) * 10.0)
			passive_t -= dt
			if passive_t <= 0.0:
				passive_t = 5.0
				_act_passives()
		"spell":
			pass
		_:
			actor.position.y = BH * 0.42 + sin(t * 2.0) * 6.0
	if lunge_t > 0.0:
		lunge_t -= dt
	for spl in spells:
		spl["left"] = float(spl["left"]) - dt
		if spl["left"] <= 0.0:
			spl["left"] = float(spl["cd"])
			_cast(spl)
	_step_bullets(dt)
	_step_minions(dt)
	_step_fx(dt)


func _monster_motion(dt: float) -> void:
	if bool(obj.get("stationary", false)) or bool(obj.get("lair", false)):
		actor.position = Vector2(BW - 130, BH * 0.5 + sin(t * 0.8) * 20.0)
		return
	if lunge_t > 0.0:
		actor.position = actor.position.move_toward(dummy.position + Vector2(50, 0), 500.0 * dt)
		return
	var cycle := fmod(t, 7.0)
	var x := BW + 40.0 - cycle * (BW + 80.0) / 7.0
	actor.position = Vector2(x, BH * 0.5 + sin(t * 2.2) * 90.0)
	actor_sprite.flip_h = true


func _target() -> Vector2:
	return dummy.position if dummy != null else Vector2(BW * 0.5, BH * 0.5)


func _cast(spl: Dictionary) -> void:
	var p: Vector2 = actor.position
	var dtype := String(spl["dtype"])
	var to := _target()
	var dir := (to - p).normalized()
	match String(spl["mode"]):
		"bolt", "hex", "melee":
			_bullet(p, dir * 300.0, dtype)
			if String(obj.get("kind", "")) == "boss":
				_bullet(p, dir.rotated(0.3) * 300.0, dtype)
				_bullet(p, dir.rotated(-0.3) * 300.0, dtype)
		"beam", "drain":
			var line := Line2D.new()
			line.width = 14.0
			line.default_color = Color(Items.type_color(dtype), 0.85)
			line.add_point(p)
			line.add_point(p + dir * 900.0)
			line.z_index = 6
			layer.add_child(line)
			fx.append({"node": line, "left": 0.3, "kind": "beam"})
			_effect(dtype, to, 1.2)
		"summon":
			for i in 2:
				var m := _make(String(spl["unit"]), p + Vector2(-30.0 * (1 if p.x > BW * 0.5 else -1), (i - 0.5) * 60.0), 0.8)
				m.get_child(0).flip_h = p.x > BW * 0.5
				minions.append({"node": m, "left": 4.0, "vel": Vector2(-60.0 if p.x > BW * 0.5 else 60.0, (i - 0.5) * 20.0)})
			_effect("conjuration", p, 1.2)
		"rain":
			for i in 5:
				_bullet(Vector2(to.x + (i - 2) * 50.0, TILE + 10.0), Vector2(0, 220.0), dtype)
		"ring":
			for i in 8:
				var a := TAU * i / 8.0
				_bullet(p, Vector2(cos(a), sin(a)) * 200.0, dtype)
		"cloud":
			var s := Sprite2D.new()
			s.texture = Items.effect_strip(dtype)
			s.hframes = 6
			s.position = p + dir * 70.0
			s.scale = Vector2.ONE * 2.2
			s.modulate = Color(1, 1, 1, 0.55)
			s.z_index = 4
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			layer.add_child(s)
			fx.append({"node": s, "left": 2.5, "kind": "cloud", "vel": dir * 40.0})
		"heal", "shield", "buff", "blast", "burst", "patch", "aura":
			var name: String = {"heal": "heal", "shield": "shield_apply", "buff": "buff_apply"}.get(String(spl["mode"]), dtype)
			_effect(String(name), p if String(spl["mode"]) in ["heal", "shield", "buff"] else to, 1.6)
		"blink":
			_effect("translocation", p, 1.0)
			actor.position = Vector2(clampf(p.x + rng.randf_range(-160.0, 160.0), 80.0, BW - 80.0), clampf(p.y + rng.randf_range(-100.0, 100.0), TILE + 40.0, BH - TILE - 40.0))
			_effect("translocation", actor.position, 1.0)
		"lunge":
			lunge_t = 0.5
	fx_caption(spl)


# A monster's passives, acted out: it dies into what it dies into, breeds, grows up,
# explodes, comes back.
func _act_monster_passives() -> void:
	var recs: Array = obj.get("buff_recs", [])
	for b in recs:
		if not (b is Dictionary):
			continue
		var cls := String(b.get("class", ""))
		var p: Vector2 = actor.position
		match cls:
			"SpawnOnDeath", "SplittingBuff", "RespawnAs", "BoxOfWoeBuff", "MushboomBuff":
				_effect("dark", p, 1.6)
				var i := 0
				for rec in b.get("spawns", []):
					var asset: Array = rec.get("asset", [])
					var unit := String(asset[asset.size() - 1]) if not asset.is_empty() else ""
					if unit == "" or not QUD.has_unit(unit):
						continue
					var n := 2 if cls == "SplittingBuff" else clampi(int(rec.get("count", 1)), 1, 3)
					for k in n:
						var m := _make(unit, p + Vector2(-30.0 - 30.0 * k, (k - (n - 1) * 0.5) * 50.0 + i * 20.0), 0.9 if cls == "SplittingBuff" else 1.0)
						m.get_child(0).flip_h = true
						minions.append({"node": m, "left": 3.5, "vel": Vector2(-70.0, 0.0)})
					i += 1
				if cls == "MushboomBuff":
					_effect("poison", p, 2.4)
				actor.visible = false
				fx.append({"node": actor, "left": 1.6, "kind": "hide"})
				_set_passive("\npassive: " + String(b.get("tooltip", "")).get_slice("\n", 0))
				return
			"DeathExplosion", "PhoenixBuff", "FireBomberBuff", "IceBomberBuff", "VoidBomberBuff", "BadBalloonBuff", "SpikedWheelBuff":
				var dtypes: Array = b.get("damage_type", [])
				var dtype := String(dtypes[0]) if not dtypes.is_empty() else ("Fire" if "Fire" in cls or cls == "PhoenixBuff" else ("Ice" if "Ice" in cls else ("Arcane" if "Void" in cls else "Physical")))
				_effect(dtype, p, 3.0)
				if cls == "SpikedWheelBuff":
					for k in 8:
						var a := TAU * k / 8.0
						_bullet(p, Vector2(cos(a), sin(a)) * 240.0, "Physical")
				actor.visible = false
				fx.append({"node": actor, "left": 1.6, "kind": "hide"})
				_set_passive("\npassive: it dies in a burst of %s" % dtype.to_lower())
				return
			"GeneratorBuff", "SummonReinforcements", "SummonOnKill":
				for rec in b.get("spawns", []):
					var asset: Array = rec.get("asset", [])
					var unit := String(asset[asset.size() - 1]) if not asset.is_empty() else ""
					if unit != "" and QUD.has_unit(unit):
						var m := _make(unit, p + Vector2(-50.0, 40.0), 0.9)
						m.get_child(0).flip_h = true
						minions.append({"node": m, "left": 4.0, "vel": Vector2(-80.0, 0.0)})
				_effect("conjuration", p, 1.2)
				_set_passive("\npassive: " + String(b.get("tooltip", "")).get_slice("\n", 0))
				return
			"MatureInto", "ChanceToBecome":
				for rec in b.get("spawns", []):
					var asset: Array = rec.get("asset", [])
					var unit := String(asset[asset.size() - 1]) if not asset.is_empty() else ""
					if unit != "" and QUD.has_unit(unit):
						_effect("buff_apply", p, 1.6)
						var grown := _sprite(unit)
						grown.flip_h = true
						actor.add_child(grown)
						actor_sprite.visible = false
						fx.append({"node": grown, "left": 2.5, "kind": "swap", "back": actor_sprite})
				_set_passive("\npassive: " + String(b.get("tooltip", "")).get_slice("\n", 0))
				return
			"Thorns", "CurseRetaliation":
				_effect("physical", p, 1.6)
				if dummy != null:
					_effect("dark", dummy.position, 1.0)
				_set_passive("passive: " + String(b.get("tooltip", "")).get_slice("
", 0) + "  (touching it, or shooting it from within two tiles)")
				return
			"ReincarnationBuff":
				_effect("dark", p, 1.4)
				_effect("holy", p, 2.0)
				_set_passive("\npassive: " + String(b.get("tooltip", "")).get_slice("\n", 0))
				return
			"RegenBuff", "TrollRegenBuff", "HealAuraBuff", "ShieldRegenBuff", "RegenShieldsBuff":
				_effect("heal" if "Regen" in cls and "Shield" not in cls or cls == "HealAuraBuff" else "shield_apply", p, 1.4)
				_set_passive("\npassive: " + String(b.get("tooltip", "")).get_slice("\n", 0))
				return
			"DamageAuraBuff", "ToxicAura", "LamasuCorruptionAura":
				var dtypes: Array = b.get("damage_type", [])
				_effect(String(dtypes[0]) if not dtypes.is_empty() else "Poison", p, 2.6)
				_set_passive("\npassive: " + String(b.get("tooltip", "")).get_slice("\n", 0))
				return


# The passives, acted out: the Necromancer's kill rises as a skeleton, auras pulse,
# shields come back, the Assassin slips away.
func _act_passives() -> void:
	var buffs: Array = obj.get("buffs", [])
	if "NecromancyBuff" in buffs and dummy != null:
		_effect("dark", dummy.position, 1.4)
		var unit := "skeletal" if QUD.has_unit("skeletal") else "goblin"
		var m := _make(unit, dummy.position + Vector2(-40, 0), 1.0)
		m.get_child(0).modulate = Color(0.85, 0.95, 1.0)
		minions.append({"node": m, "left": 4.0, "vel": Vector2(-70.0, 0.0)})
		_set_passive("\npassive: the slain goblin rises as a skeleton and fights for you")
	elif "HealAuraBuff" in buffs or "HolyAuraBuff" in buffs:
		_effect("heal" if "HealAuraBuff" in buffs else "holy", actor.position, 2.2)
		_set_passive(("\npassive: heals allies nearby every turn" if "HealAuraBuff" in buffs else "\npassive: holy damage around, allies healed"))
	elif "WitheringAura" in buffs and dummy != null:
		_effect("dark", dummy.position, 1.6)
		_set_passive("\npassive: enemies nearby corrode and take more damage")
	elif "ShieldRegenBuff" in buffs:
		_effect("shield_apply", actor.position, 1.2)
		_set_passive("\npassive: shields grow back")
	elif "TeleportOnDamage" in buffs or "TeleportyBuff" in buffs or "QuickmoveBuff" in buffs:
		_effect("translocation", actor.position, 1.0)
		actor.position += Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-40.0, 40.0))
		_effect("translocation", actor.position, 1.0)
		_set_passive("\npassive: slips out of harm's way")
	elif "BerserkerEnrageBuff" in buffs or "BerserkerRageBuff" in buffs:
		_effect("buff_apply", actor.position, 1.4)
		_set_passive("\npassive: every wound makes it angrier and tougher")
	elif "EncoreBuff" in buffs:
		_effect("holy", actor.position, 1.2)
		_set_passive("\npassive: a good performance earns an encore, a life back")
	elif "ValkyrieOath" in buffs:
		_effect("holy", actor.position, 1.2)
		_set_passive("\npassive: when a living ally falls she takes their place at once")


func fx_caption(spl: Dictionary) -> void:
	cast_line = "casting %s (%s)" % [String(spl["name"]), String(spl["mode"])]
	_compose_caption()


func _set_passive(line: String) -> void:
	passive_line = line.trim_prefix("
")
	_compose_caption()


# Three lines: what it is, what it does without casting, what it is casting now.
func _compose_caption() -> void:
	var text := String(obj.get("text", ""))
	var lines := [text.get_slice("
", 0)]
	if passive_line != "":
		lines.append(passive_line)
	elif text.get_slice_count("
") > 1 and text.get_slice("
", 1) != "":
		lines.append(text.get_slice("
", 1))
	if cast_line != "":
		lines.append(cast_line)
	caption.text = "
".join(lines)


func _bullet(at: Vector2, vel: Vector2, dtype: String) -> void:
	var s := Sprite2D.new()
	s.texture = Items.effect_strip(dtype)
	s.hframes = 6
	s.position = at
	s.scale = Vector2.ONE * 0.5
	s.rotation = vel.angle()
	s.z_index = 5
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(s)
	bullets.append({"node": s, "vel": vel, "age": 0.0, "dtype": dtype})


func _step_bullets(dt: float) -> void:
	for b in bullets.duplicate():
		b["age"] += dt
		var n: Sprite2D = b["node"]
		n.position += b["vel"] * dt
		n.frame = int(b["age"] / 0.08) % 6
		var gone := n.position.x < -20.0 or n.position.x > BW + 20.0 or n.position.y < 0.0 or n.position.y > BH
		if dummy != null and n.position.distance_to(dummy.position) < 26.0 and b["age"] > 0.2:
			_effect(String(b["dtype"]), n.position, 1.0)
			gone = true
		if gone:
			bullets.erase(b)
			n.queue_free()


func _step_minions(dt: float) -> void:
	for m in minions.duplicate():
		m["left"] -= dt
		var n: Node2D = m["node"]
		n.position += m["vel"] * dt
		var s: Sprite2D = n.get_child(0)
		s.frame = int(t / 0.2) % s.hframes
		if m["left"] <= 0.0 or n.position.x < -40.0 or n.position.x > BW + 40.0:
			minions.erase(m)
			n.queue_free()


func _effect(name: String, at: Vector2, size := 1.0) -> void:
	var s := Sprite2D.new()
	s.texture = QUD.effect(name.to_lower())
	if s.texture == null:
		s.texture = QUD.effect("arcane")
	s.hframes = 6
	s.position = at
	s.scale = Vector2.ONE * size
	s.z_index = 8
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(s)
	fx.append({"node": s, "left": 0.42, "kind": "strip", "age": 0.0})


func _step_fx(dt: float) -> void:
	for f in fx.duplicate():
		f["left"] -= dt
		var n: Node2D = f["node"]
		match String(f["kind"]):
			"strip":
				f["age"] += dt
				n.frame = mini(5, int(f["age"] / 0.07))
			"beam":
				n.modulate.a = maxf(0.0, f["left"] / 0.3)
			"cloud":
				n.position += f["vel"] * dt
				n.frame = int(t / 0.12) % 6
			"hide", "swap":
				pass
		if f["left"] <= 0.0:
			fx.erase(f)
			if f["kind"] == "hide":
				n.visible = true
				_effect("translocation", n.position, 1.0)
			elif f["kind"] == "swap":
				f["back"].visible = true
				n.queue_free()
			else:
				n.queue_free()
