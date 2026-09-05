# Rift Wizard Survivors: on foot in the Loop, monsters from the spawn tables
# arrive in waves as the realm timer climbs, owned spells cast themselves,
# kills drop XP, level-ups offer three cards. See docs/survivors.md.
#
# Flags after "--": --mode=survivors --seed=N --auto --mute
#   --frames=N --screenshot=path   --spells=Name --screen=levelup
extends Node3D

const PLAYING := "playing"
const CHOOSING := "choosing"
const PAUSED := "paused"
const DEAD := "dead"
const WON := "won"

var rng := RandomNumberGenerator.new()
var track: Track
var S := {}
var state := PLAYING
var t := 0.0
var realm := 1
var realm_t := 0.0
var auto_player := false
var screenshot_path := ""
var frames_left := -1
var frame_count := 0
var screen_arg := ""

# hero
var player: Node3D
var hero_sprite: Sprite3D
var hero_shadow: MeshInstance3D
var hero_pos := Vector2.ZERO
var hero_dir := Vector2.RIGHT
var hero_speed := 420.0
var auras: Array = []      # running aura spells (see _update_auras)
var arena: Arena = null    # realm mode: the game's realm as a walkable arena
var realm_mode := true
var realm_file := ""
var rifts: Array = []      # portal sprites; active once the realm is cleared
var cleared := false
var clear_timer := 0.0
var flow_t := 0.0
var bank := 0              # level-up picks saved toward a higher-level spell
var hazards: Array = []    # laid patches (Items.Hazard)
var hp := 50.0
var max_hp := 50.0
var shields := 0
var invuln := 0.0
var speed_bonus := 0.0
var magnet := 220.0
var cooldown_mult := 1.0
var regen := 0.0
var xp := 0
var level := 1
var kills := 0
var spells: Array = []        # {spell, level, cd, cd_max, effect, unit}
var familiars: Array = []     # {sprite, angle, damage, tick}

# field
var mobs: Array = []
var gems: Array = []
var hearts: Array = []
var bolts: Array = []         # projectiles (Items.Projectile) from hero and mobs
var effects: Array = []
var lines: Array = []
var pool: Array = []          # monster species for this realm
var spawn_acc := 0.0
var shadow_mesh: Mesh
var gem_tex: Texture2D
var heart_tex: Texture2D
var boss_alive := false
var final_boss_spawned := false
var last_realm_spawned := 0

# camera + hud
var cam: Camera3D
var hud: CanvasLayer
var lbl_top: Label
var lbl_stats: Label
var lbl_center: Label
var hp_fill: ColorRect
var xp_fill: ColorRect
var spell_icons: Array = []
var spell_lvls: Array = []
var minimap: MiniMap
var results: Label
var choice: Choice = null
var message := ""
var message_t := 0.0

# MiniMap compatibility
var karts: Array = []
var item_boxes: Array = []


func cfg(key: String, default = null):
	return S.get(key, default)


func _ready() -> void:
	var args := _parse_args()
	S = Shared.tuning.get("survivors", {})
	rng.seed = int(args.get("seed", Time.get_ticks_usec() % 2147483647))
	auto_player = args.has("auto")
	screenshot_path = args.get("screenshot", "")
	frames_left = int(args.get("frames", -1))
	screen_arg = String(args.get("screen", ""))
	hero_speed = float(cfg("hero_speed", 420.0))
	max_hp = float(cfg("hero_hp", 50.0))
	hp = max_hp
	magnet = float(cfg("magnet", 220.0))
	realm_mode = String(cfg("arena", "realm")) == "realm" and not Shared.realms.is_empty()
	if args.has("realm"):
		if realm_mode:
			realm = clampi(int(args["realm"]), 1, 21)
		else:   # jump the clock to a later realm (testing)
			t = float(maxi(0, int(args["realm"]) - 1)) * float(cfg("realm_seconds", 60.0))
	realm_file = String(args.get("realm_file", ""))

	track = Track.new()
	add_child(track)
	if realm_mode:
		track.setup_void(Vector2(3600, 3600))
	elif String(cfg("arena", "plain")) == "plain":
		track.setup_plain(rng)
	else:
		track.setup_city_open(String(cfg("city", "chicago_loop")), rng)

	_build_environment()
	_build_shadow_mesh()
	_build_hero()
	if realm_mode:
		_load_arena(realm)
	_build_camera()
	_build_hud()
	_refresh_pool()
	gem_tex = QUD.texture("tiles/item_mana_orb.png")
	heart_tex = QUD.texture("tiles/item_ruby_heart.png")
	Audio.music("battle_%d" % (1 + rng.randi_range(0, 11)))

	var starting: Array = []
	if args.has("spells"):
		for n in String(args["spells"]).split(","):
			if SpellDB.by_name.has(n):
				starting.append(SpellDB.by_name[n])
	if starting.is_empty():
		_offer_start()
	else:
		for s in starting:
			_add_spell(s)
		opened = true
		if not realm_mode:
			_opening_spawn()
	if args.has("upgrade"):   # --upgrade="Fireball:Ash Ball" (testing)
		for pair in String(args["upgrade"]).split(","):
			var kv := pair.split(":")
			if kv.size() != 2:
				continue
			for s in spells:
				if s["spell"]["name"] == kv[0]:
					for up in SpellDB.upgrade_options(s["spell"], s["taken"]):
						if String(up["name"]) == kv[1]:
							_apply_upgrade(s, up)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


# ---------------------------------------------------------------- setup

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.04, 0.03, 0.08)
	sky_mat.sky_horizon_color = Color(0.25, 0.18, 0.36)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sky_mat.ground_horizon_color = Color(0.2, 0.15, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.25, 0.18, 0.36)
	env.fog_density = 0.002
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 20, 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.92, 0.85)
	sun.shadow_enabled = true
	add_child(sun)


func _build_shadow_mesh() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			img.set_pixel(x, y, Color(0, 0, 0, clampf(1.0 - d, 0.0, 1.0) * 0.55))
	var tex := ImageTexture.create_from_image(img)
	var quad := QuadMesh.new()
	quad.size = Vector2(52, 30) * Track.U
	quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	shadow_mesh = quad


func _sprite(unit: String, scale := 1.0) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = QUD.unit_idle(unit)
	s.hframes = maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
	s.pixel_size = Track.U * scale
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	var fs := int(QUD.unit_info(unit).get("frame_size", 60))
	s.position = Vector3(0, fs * Track.U * scale * 0.5, 0)
	return s


func _build_hero() -> void:
	player = Node3D.new()
	add_child(player)
	hero_shadow = MeshInstance3D.new()
	hero_shadow.mesh = shadow_mesh
	hero_shadow.position = Vector3(0, 0.5 * Track.U, 0)
	player.add_child(hero_shadow)
	hero_sprite = _sprite(Campaign.skin if QUD.has_unit(Campaign.skin) else "player")
	player.add_child(hero_sprite)
	# start at a junction with a few streets, near the middle of the map
	var best := track.size * 0.5
	var best_d := INF
	if track.city != null:
		for id in track.city.junctions:
			var j: Dictionary = track.city.junctions[id]
			if j["streets"].size() < 3:
				continue
			var d: float = j["pos"].distance_to(track.size * 0.5)
			if d < best_d:
				best_d = d
				best = j["pos"]
	hero_pos = best
	player.position = track.to3(hero_pos)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = float(cfg("cam_fov", 60.0))
	cam.near = 0.5
	cam.far = 3000.0
	add_child(cam)
	cam.current = true
	_update_camera()


func _update_camera() -> void:
	var back := float(cfg("realm_cam_back", 520.0) if realm_mode else cfg("cam_back", 700.0)) * Track.U
	var height := float(cfg("realm_cam_height", 760.0) if realm_mode else cfg("cam_height", 1000.0)) * Track.U
	var target := track.to3(hero_pos)
	cam.position = target + Vector3(0, height, back)
	cam.look_at(target + Vector3(0, 20 * Track.U, 0), Vector3.UP)


func _label(size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(l)
	return l


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	lbl_top = _label(30, Color(1.0, 0.93, 0.35))
	lbl_top.position = Vector2(0, 14)
	lbl_top.size = Vector2(1920, 40)
	lbl_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.7)
	hp_bg.position = Vector2(28, 24)
	hp_bg.size = Vector2(360, 26)
	hud.add_child(hp_bg)
	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.9, 0.11, 0.14)
	hp_fill.position = hp_bg.position
	hp_fill.size = hp_bg.size
	hud.add_child(hp_fill)
	var xp_bg := ColorRect.new()
	xp_bg.color = Color(0, 0, 0, 0.7)
	xp_bg.position = Vector2(28, 56)
	xp_bg.size = Vector2(360, 16)
	hud.add_child(xp_bg)
	xp_fill = ColorRect.new()
	xp_fill.color = Color(0.47, 0.78, 1.0)
	xp_fill.position = xp_bg.position
	xp_fill.size = Vector2(0, 16)
	hud.add_child(xp_fill)
	lbl_stats = _label(20)
	lbl_stats.position = Vector2(28, 78)
	lbl_center = _label(72, Color(1.0, 0.93, 0.35))
	lbl_center.position = Vector2(0, 400)
	lbl_center.size = Vector2(1920, 100)
	lbl_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var x0 := 960 - (10 * 74) / 2
	for i in 10:
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.6)
		bg.position = Vector2(x0 + i * 74, 1080 - 96)
		bg.size = Vector2(68, 84)
		hud.add_child(bg)
		var icon := TextureRect.new()
		icon.position = bg.position + Vector2(4, 4)
		icon.size = Vector2(60, 60)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		hud.add_child(icon)
		spell_icons.append(icon)
		var lv := _label(16, Color(1.0, 0.93, 0.35))
		lv.position = bg.position + Vector2(6, 62)
		spell_lvls.append(lv)
	minimap = MiniMap.new()
	minimap.race = self
	minimap.span_px = 12000.0
	minimap.position = Vector2(1920 - 28 - 260, 1080 - 28 - 260)
	minimap.size = Vector2(260, 260)
	hud.add_child(minimap)
	results = _label(30)
	results.position = Vector2(560, 300)
	results.visible = false


func minimap_dots() -> Array:
	var out := []
	var step := maxi(1, mobs.size() / 200)
	for i in range(0, mobs.size(), step):
		var m: Sprite3D = mobs[i]
		out.append([m.get_meta("pos"), Color(0.9, 0.11, 0.14) if not m.get_meta("boss") else Color(1.0, 0.6, 0.2)])
	for g in gems:
		out.append([g.get_meta("pos"), Color(0.47, 0.78, 1.0)])
	for r in rifts:
		out.append([r.get_meta("pos"), Color(1.0, 0.93, 0.35)])
	return out


# Building collision, or nothing at all on the open field.
func _collide(p: Vector2, radius: float) -> Dictionary:
	if track.city == null:
		return {"hit": false, "pos": p, "normal": Vector2.ZERO}
	return _collide(p, radius)


func forward_dir() -> Vector2:
	return hero_dir


# ---------------------------------------------------------------- realms and spawning

func band_for(r: int) -> int:
	return clampi(1 + int(round((r - 1) * 8.0 / 19.0)), 1, 9)


func _refresh_pool() -> void:
	var band := band_for(realm)
	pool = QUD.roster(int(cfg("species_per_realm", 7)), rng, band, maxi(1, band - 2))
	if pool.is_empty():
		pool = QUD.roster(7, rng, 9, 1)


func _spawn_mob(species: Dictionary, boss := false, at := Vector2.INF, extra := {}) -> void:
	var unit: String = species["unit"]
	var info: Dictionary = QUD.unit_info(unit)
	var radius_units := int(info.get("radius", 0))
	var scale := 1.0 if not boss else (1.6 if int(info.get("frame_size", 60)) <= 60 else 1.0)
	var s := _sprite(unit, scale)
	var stats := Kart.stats_from_unit(float(species.get("hp", 10.0)), bool(species.get("flying", false)), rng)
	var hp_scale := float(cfg("mob_hp_scale", 1.0)) * (3.0 if boss else 1.0)
	var mob_hp := maxf(3.0, minf(float(cfg("boss_hp_cap", 900.0)) if boss else 1e9, float(species.get("hp", 10.0)) * hp_scale))
	var ability := _ability_from(species.get("spells", []))
	var cd: Array = cfg("ability_cooldown", [4.0, 7.0])
	var spawn_r: Array = cfg("spawn_radius", [1500.0, 2200.0])
	var pos := Vector2.ZERO
	for _try in 12:
		pos = at if at.is_finite() else hero_pos + Vector2(rng.randf_range(float(spawn_r[0]), float(spawn_r[1])), 0).rotated(rng.randf_range(0, TAU))
		pos.x = clampf(pos.x, 40.0, track.size.x - 40.0)
		pos.y = clampf(pos.y, 40.0, track.size.y - 40.0)
		if not _collide(pos, 30.0)["hit"]:
			break
	s.set_meta("pos", pos)
	s.set_meta("hp", mob_hp)
	s.set_meta("max_hp", mob_hp)
	s.set_meta("speed", (float(cfg("mob_speed_base", 150.0)) + float(cfg("mob_speed_per_stat", 25.0)) * stats.x) * (0.75 if boss else 1.0))
	s.set_meta("damage", float(ability["damage"]) if ability["kind"] == "melee" else 3.0)
	s.set_meta("ability", ability)
	s.set_meta("cd", rng.randf_range(float(cd[0]), float(cd[1])))
	s.set_meta("hit_cd", 0.0)
	s.set_meta("frozen", 0.0)
	s.set_meta("boss", boss)
	s.set_meta("name", species["name"])
	s.set_meta("radius", (26.0 if radius_units == 0 else 70.0) * scale)
	s.set_meta("t", rng.randf())
	s.set_meta("flash", 0.0)
	s.set_meta("dtype", String(ability.get("dtype", "Physical")))
	s.set_meta("flying", bool(species.get("flying", false)))
	if extra.has("from"):
		s.set_meta("from", extra["from"])
	if extra.has("spawner"):   # a lair: sits still, lets its monster out now and then
		s.set_meta("spawner", extra["spawner"])
		s.set_meta("spawn_cd", float(extra.get("spawn_cd", 7.0)))
		s.set_meta("spawn_t", float(extra.get("spawn_cd", 7.0)) * rng.randf_range(0.3, 1.0))
		s.set_meta("hp", float(extra.get("hp", 40.0)))
		s.set_meta("max_hp", float(extra.get("hp", 40.0)))
		s.set_meta("speed", 0.0)
		s.set_meta("radius", 34.0)
		s.position.y += 26.0 * Track.U
		if QUD.has_unit("lair"):
			var base := _sprite("lair", 1.3)
			s.add_sibling.call_deferred(base)
	var holder := Node3D.new()
	holder.add_child(s)
	var sh := MeshInstance3D.new()
	sh.mesh = shadow_mesh
	sh.position = Vector3(0, 0.5 * Track.U, 0)
	sh.scale = Vector3.ONE * scale
	holder.add_child(sh)
	holder.position = track.to3(pos)
	add_child(holder)
	s.set_meta("holder", holder)
	if boss:
		var lbl := Label3D.new()
		lbl.text = String(species["name"]).to_upper()
		lbl.font = QUD.font()
		lbl.font_size = 40
		lbl.pixel_size = Track.U * 0.3
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = Color(1.0, 0.6, 0.2)
		lbl.outline_size = 8
		lbl.position = Vector3(0, (int(info.get("frame_size", 60)) * scale + 20) * Track.U, 0)
		holder.add_child(lbl)
		boss_alive = true
	mobs.append(s)


func _ability_from(spells_data: Array) -> Dictionary:
	for sp in spells_data:
		if not (sp is Dictionary) or sp.has("error"):
			continue
		var st: Dictionary = sp.get("stats", {})
		var dmg := float(st.get("damage", 0))
		var rng_t := float(sp.get("range", 0))
		var dtypes: Array = sp.get("damage_type", [])
		var dtype := String(dtypes[0]) if dtypes.size() > 0 else "Arcane"
		if dmg > 0.0 and rng_t > 2.0:
			return {"name": sp.get("name", "Bolt"), "kind": "ranged", "damage": dmg, "range": rng_t * 90.0, "dtype": dtype}
		if dmg > 0.0:
			return {"name": sp.get("name", "Bite"), "kind": "melee", "damage": dmg, "range": 60.0, "dtype": dtype}
	return {"name": "Bite", "kind": "melee", "damage": 3.0, "range": 60.0, "dtype": "Physical"}


func _spawn_boss() -> void:
	var band := band_for(realm)
	var candidates := []
	for m in QUD.monsters:
		var is_final := realm >= 20
		if m.has("error") or (int(m.get("radius", 0)) > 1 and not is_final) or not bool(m.get("asset_exists", false)):
			continue
		var asset: Array = m.get("asset", [])
		if asset.size() < 2 or not QUD.has_unit(asset[1]):
			continue
		for r in m.get("roles", []):
			var role := String(r.get("role", ""))
			var ok := false
			if realm >= 20 and role == "final_boss":
				ok = true
			elif realm < 20 and role == "rare":
				var tier := String(r.get("tier", "easy"))
				ok = (band <= 3 and tier == "easy") or (band > 3 and band <= 6 and tier in ["easy", "med"]) or (band > 6)
			if ok:
				candidates.append({"name": m["name"], "unit": asset[1], "hp": float(m.get("max_hp", 30)), "flying": bool(m.get("flying", false)), "spells": m.get("spells", [])})
				break
	if candidates.is_empty():
		return
	var pick: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	_spawn_mob(pick, true)
	print("boss: %s (%s) realm %d" % [pick["name"], pick["unit"], realm])
	say("%s APPROACHES" % String(pick["name"]).to_upper(), 2.5)
	Audio.play("enemy")
	if realm >= 20:
		final_boss_spawned = true


# ---------------------------------------------------------------- spells

func _cd_for(spell: Dictionary, lvl: int, extra_charges := 0) -> float:
	var charges := 12.0 if int(spell.get("max_charges", 3)) <= 0 else maxf(1.0, float(spell.get("max_charges", 3)) + extra_charges)   # 0 = unlimited in the game
	var base := clampf(9.0 / charges + 0.6, 0.8, 8.0)
	return base * pow(0.9, lvl - 1) * cooldown_mult * float(cfg("cooldown_scale", 1.0))


func _add_spell(spell: Dictionary) -> void:
	for s in spells:
		if s["spell"]["name"] == spell["name"]:
			s["level"] += 1
			s["cd_max"] = _cd_for(spell, s["level"])
			return
	var e := SpellDB.effect_for(spell)
	var entry := {"spell": spell, "level": 1, "cd": 0.5, "cd_max": _cd_for(spell, 1), "effect": e, "unit": SpellDB.summon_unit(spell), "taken": [], "extra_charges": 0}
	spells.append(entry)
	if e["kind"] == "summon":
		_add_familiar(entry)
	elif e["kind"] == "buff":
		speed_bonus += 0.08
	Audio.play("learn_spell")


func _add_familiar(entry: Dictionary) -> void:
	var s := _sprite(String(entry["unit"]), 0.8)
	s.modulate = Items.type_color(String(entry["effect"].get("dtype", "Nature"))).lerp(Color.WHITE, 0.5)
	var holder := Node3D.new()
	holder.add_child(s)
	add_child(holder)
	familiars.append({"holder": holder, "sprite": s, "angle": rng.randf() * TAU, "damage": float(entry["effect"].get("damage", 3.0)), "tick": 0.0, "entry": entry})


func _spell_damage(entry: Dictionary) -> float:
	return (float(entry["effect"].get("damage", 5.0)) + Campaign.bonus("spell_damage")) * (1.0 + 0.25 * (int(entry["level"]) - 1))


func _spell_targets(entry: Dictionary) -> int:
	return int(entry["effect"].get("targets", 1)) + (int(entry["level"]) - 1) / 2


func _nearest_mobs(from: Vector2, range_px: float, count: int) -> Array:
	var cand := []
	for m in mobs:
		var d: float = from.distance_to(m.get_meta("pos"))
		if d <= range_px:
			cand.append([d, m])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for i in mini(count, cand.size()):
		out.append(cand[i][1])
	return out


func _cast(entry: Dictionary) -> bool:
	var e: Dictionary = entry["effect"]
	var kind := String(e["kind"])
	var dtype := String(e.get("dtype", "Arcane"))
	var dmg := _spell_damage(entry)
	var dur := float(e.get("duration", 4.0)) + Campaign.bonus("spell_duration")
	var rng_px := maxf(500.0, float(e.get("range", 500.0)) * 1.4)
	var cost := int(entry["spell"].get("hp_cost", 0))
	if cost > 0 and hp <= cost:
		return false
	match kind:
		"bolt":
			var targets := _nearest_mobs(hero_pos, rng_px * 1.6, maxi(_spell_targets(entry), int(e.get("count", 1))))
			if targets.is_empty():
				return false
			for m in targets:
				_arm_bolt(_fire_bolt(hero_pos, m.get_meta("pos"), dmg, dtype, 0.0, m), e)
		"melee":
			var reach := float(e.get("range", 180.0)) + 40.0
			var hits := []
			for m in mobs:
				var rel: Vector2 = m.get_meta("pos") - hero_pos
				var d := rel.length()
				if d <= reach + float(m.get_meta("radius")) and rel.dot(hero_dir) > d * 0.2:
					hits.append(m)
			hits.sort_custom(func(a, b): return hero_pos.distance_squared_to(a.get_meta("pos")) < hero_pos.distance_squared_to(b.get_meta("pos")))
			if hits.is_empty():
				return false
			for m in hits.slice(0, _spell_targets(entry)):
				_hit_mob(m, dmg, dtype)
				_stun_mob(m, float(e.get("stun", 0.3)))
				_shove_mob(m, hero_dir, float(e.get("shove", 260.0)))
				_drain(dmg, e)
			_effect_at(QUD.effect("physical"), hero_pos + hero_dir * 40.0, 6, 1.6)
		"burst":
			var radius := float(e.get("radius", 300.0)) * 1.2
			var any := false
			for m in _nearest_mobs(hero_pos, radius, 200):
				if bool(e.get("only_stunned", false)) and float(m.get_meta("frozen")) <= 0.0:
					continue
				var away: Vector2 = (Vector2(m.get_meta("pos")) - hero_pos).normalized()
				if dmg > 0.0:
					_hit_mob(m, dmg, dtype)
					_drain(dmg, e)
				_stun_mob(m, float(e.get("stun", 0.3)))
				_shove_mob(m, away, float(e.get("shove", 0.0)))
				any = true
			_ring(radius, dtype)
			if not any and dmg > 0.0 and not bool(e.get("only_stunned", false)):
				return false
		"aura":
			auras.append({"damage": dmg, "radius": float(e.get("radius", 300.0)) * 1.2, "tick": float(e.get("tick", 0.8)),
				"left": dur, "next": 0.3, "targets": int(e.get("targets", 0)), "heal": float(e.get("heal", 0.0)),
				"heal_frac": float(e.get("heal_frac", 0.0)), "dtype": dtype, "stun": float(e.get("stun", 0.0)),
				"shove": float(e.get("shove", 0.0)), "slip": bool(e.get("slip", false))})
			_effect_at(QUD.effect("buff_apply"), hero_pos, 6)
		"patch":
			var h := Items.Hazard.new()
			h.pos = hero_pos + hero_dir * float(e.get("range", 0.0))
			h.radius = float(e.get("radius", 200.0)) * 1.2
			h.damage = dmg
			h.tick = float(e.get("tick", 0.8))
			h.life = dur
			h.dtype = dtype
			h.slip = bool(e.get("slip", false))
			h.position = track.to3(h.pos, 3.0)
			add_child(h)
			if dtype == "Ice":
				h.build_flat(QUD.texture("tiles/cloud_ice_cloud.png"), 4, Color.WHITE)
			elif dtype == "Lightning":
				h.build_flat(QUD.texture("tiles/cloud_thunder_cloud.png"), 4, Color.WHITE)
			elif dtype == "Nature":
				h.build_flat(QUD.texture("tiles/cloud_rainstorm_cloud.png"), 4, Color.WHITE)
			else:
				h.build_flat(Items.effect_strip(dtype), 6, Items.type_color(dtype).lerp(Color.WHITE, 0.3))
			hazards.append(h)
		"empower":
			Campaign.add_temp_bonus(e.get("bonuses", {}), dur)
			_effect_at(QUD.effect("buff_apply"), hero_pos, 6)

		"blast":
			var targets := _nearest_mobs(hero_pos, rng_px * 1.6, maxi(1, int(e.get("count", 1))))
			if targets.is_empty():
				return false
			for m in targets:
				_arm_bolt(_fire_bolt(hero_pos, m.get_meta("pos"), dmg, dtype, float(e.get("radius", 60.0)) * 1.5, m, QUD.texture("effects/proj/fire_ball.png")), e)
		"beam":
			var targets := _nearest_mobs(hero_pos, rng_px, _spell_targets(entry) + 1)
			if targets.is_empty():
				return false
			var from := hero_pos
			for m in targets:
				var p: Vector2 = m.get_meta("pos")
				_line(from, p, Items.type_color(dtype))
				var d_here := dmg
				if float(e.get("hp_frac", 0.0)) > 0.0:
					d_here = maxf(dmg, float(m.get_meta("max_hp")) * float(e["hp_frac"]))
				_hit_mob(m, d_here, dtype)
				_stun_mob(m, float(e.get("stun", 0.0)))
				_drain(d_here, e)
				from = p
		"summon":
			for f in familiars:
				if f["entry"] == entry:
					f["damage"] = dmg
			return false
		"shield":
			shields = maxi(shields, int(e.get("shields", 1)) + int(entry["level"]) - 1)
			_effect_at(QUD.effect("shield_apply"), hero_pos, 6)
		"heal":
			hp = minf(max_hp, hp + float(e.get("amount", 8.0)) * (1.0 + 0.25 * (int(entry["level"]) - 1)))
			_effect_at(QUD.effect("heal"), hero_pos, 6)
		"buff":
			return false
		"blink":
			var threats := _nearest_mobs(hero_pos, 260.0, 12)
			if threats.size() < 4:
				return false
			var away := Vector2.ZERO
			for m in threats:
				away += (hero_pos - m.get_meta("pos")).normalized()
			if away.length_squared() < 0.01:
				away = hero_dir
			_effect_at(QUD.effect("translocation"), hero_pos, 6)
			var dest := hero_pos + away.normalized() * float(e.get("distance", 340.0))
			if (realm_mode and arena.can_stand(dest, 22.0, false)) or (not realm_mode and not _collide(dest, 26.0)["hit"]):
				hero_pos = dest
			_effect_at(QUD.effect("translocation"), hero_pos, 6)
			Audio.play("teleport")
		"hex":
			var targets := _nearest_mobs(hero_pos, rng_px, 6 + 3 * int(entry["level"]))
			if targets.is_empty():
				return false
			for m in targets:
				m.set_meta("frozen", maxf(float(m.get_meta("frozen")), float(e.get("duration", 3.0))))
				var fx := _effect_at(QUD.effect("ice"), m.get_meta("pos"), 6)
				fx.follow = m.get_meta("holder")
		_:
			return false
	if cost > 0:
		hp = maxf(1.0, hp - cost)
		_effect_at(QUD.effect("blood"), hero_pos, 6, 1.2)
	Audio.play("sorcery", -6.0)
	return true


func _arm_bolt(p: Items.Projectile, e: Dictionary) -> void:
	p.heal_frac = float(e.get("heal_frac", 0.0))
	if e.has("stun"):
		p.set_meta("stun", float(e["stun"]))


func _heal_hero(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


# ---------------------------------------------------------------- shared spell helpers (the kinds the race has)

func _stun_mob(m: Sprite3D, seconds: float) -> void:
	if seconds > 0.0 and is_instance_valid(m) and mobs.has(m):
		m.set_meta("frozen", maxf(float(m.get_meta("frozen")), seconds))


func _shove_mob(m: Sprite3D, dir: Vector2, px_per_s: float) -> void:
	if px_per_s != 0.0 and is_instance_valid(m) and mobs.has(m):
		m.set_meta("pos", Vector2(m.get_meta("pos")) + dir * px_per_s * 0.25)


func _drain(dmg: float, e: Dictionary) -> void:
	var hf := float(e.get("heal_frac", 0.0))
	if hf > 0.0:
		_heal_hero(dmg * hf)


func _ring(radius: float, dtype: String) -> void:
	var tex := Items.effect_strip(dtype)
	_effect_at(tex, hero_pos, 6, 1.3)
	var n := clampi(int(radius / 55.0), 6, 14)
	for i in n:
		var ang := TAU * i / n
		_effect_at(tex, hero_pos + Vector2(cos(ang), sin(ang)) * radius * 0.85, 6, 1.2)


func _update_auras(dt: float) -> void:
	for a in auras.duplicate():
		a["left"] -= dt
		a["next"] -= dt
		if a["left"] <= 0.0:
			auras.erase(a)
			continue
		if a["next"] > 0.0:
			continue
		a["next"] = float(a["tick"])
		if float(a["heal"]) > 0.0:
			_heal_hero(float(a["heal"]))
		var n := int(a["targets"])
		for m in _nearest_mobs(hero_pos, float(a["radius"]), n if n > 0 else 200):
			if float(a["damage"]) > 0.0:
				_hit_mob(m, float(a["damage"]), String(a["dtype"]))
				if float(a["heal_frac"]) > 0.0:
					_heal_hero(float(a["damage"]) * float(a["heal_frac"]))
			_stun_mob(m, float(a["stun"]) + (0.5 if bool(a["slip"]) else 0.0))
			if float(a["shove"]) != 0.0 and is_instance_valid(m):
				_shove_mob(m, (Vector2(m.get_meta("pos")) - hero_pos).normalized(), float(a["shove"]))
			if is_instance_valid(m) and mobs.has(m):
				_line(hero_pos, m.get_meta("pos"), Items.type_color(String(a["dtype"])))


func _update_hazards(dt: float) -> void:
	for h in hazards.duplicate():
		if not h.tick_hazard(dt):
			hazards.erase(h)
			h.queue_free()
			continue
		if h.next_tick > 0.0:
			continue
		h.next_tick = h.tick
		for m in _nearest_mobs(h.pos, h.radius, 200):
			if h.damage > 0.0:
				_hit_mob(m, h.damage, h.dtype)
			if h.slip:
				_stun_mob(m, 0.6)


func _fire_bolt(from: Vector2, to: Vector2, dmg: float, dtype: String, radius: float, homing: Sprite3D, tex: Texture2D = null) -> Items.Projectile:
	var p := Items.Projectile.new()
	p.texture = tex if tex != null else QUD.texture("effects/proj/arcane_bolt.png")
	p.pixel_size = Track.U * 0.8
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.modulate = Items.type_color(dtype).lerp(Color.WHITE, 0.5)
	p.pos = from
	p.vel = (to - from).normalized() * 1100.0
	p.damage = dmg
	p.radius = radius
	p.dtype = dtype
	p.life = 2.0
	p.set_meta("target", homing)
	p.set_meta("from_hero", true)
	add_child(p)
	bolts.append(p)
	return p


func _effect_at(tex: Texture2D, at: Vector2, frames: int, size := 1.4) -> Items.Effect:
	var e := Items.Effect.make(tex, track.to3(at, 30.0), frames, 0.07, -1.0, size)
	add_child(e)
	effects.append(e)
	return e


func _line(a: Vector2, b: Vector2, color: Color) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(track.to3(a) + Vector3(0, 1.5, 0))
	im.surface_add_vertex(track.to3(b) + Vector3(0, 1.5, 0))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.set_meta("life", 0.15)
	add_child(mi)
	lines.append(mi)


# ---------------------------------------------------------------- damage

func _hit_mob(m: Sprite3D, dmg: float, dtype: String) -> void:
	if not is_instance_valid(m) or not mobs.has(m):
		return
	var h := float(m.get_meta("hp")) - dmg
	m.set_meta("hp", h)
	m.set_meta("flash", 0.2)
	_effect_at(Items.effect_strip(dtype), m.get_meta("pos"), 6, 1.2)
	if h <= 0.0:
		_kill_mob(m)


func _kill_mob(m: Sprite3D) -> void:
	kills += 1
	var pos: Vector2 = m.get_meta("pos")
	var value := maxi(1, int(round(float(m.get_meta("max_hp")) / 4.0)))
	_drop_gem(pos, value)
	if bool(m.get_meta("boss")):
		boss_alive = false
		for i in 6:
			_drop_gem(pos + Vector2(rng.randf_range(-80, 80), rng.randf_range(-80, 80)), value)
		_drop_heart(pos)
		say("%s SLAIN" % String(m.get_meta("name")).to_upper(), 2.0)
		Audio.play("death_boss")
		if final_boss_spawned:
			_win()
	elif rng.randf() < float(cfg("heart_chance", 0.03)):
		_drop_heart(pos)
	Audio.play("death_enemy", -8.0)
	var holder: Node3D = m.get_meta("holder")
	mobs.erase(m)
	holder.queue_free()
	if realm_mode and mobs.is_empty() and not cleared and state == PLAYING:
		_on_cleared()


func _drop_gem(pos: Vector2, value: int) -> void:
	var g := Sprite3D.new()
	g.texture = gem_tex
	g.pixel_size = Track.U * (0.5 + 0.1 * minf(5.0, value / 5.0))
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	g.set_meta("pos", pos)
	g.set_meta("value", value)
	g.set_meta("life", float(cfg("gem_life", 60.0)))
	g.position = track.to3(pos, 20.0)
	add_child(g)
	gems.append(g)


func _drop_heart(pos: Vector2) -> void:
	var h := Sprite3D.new()
	h.texture = heart_tex
	h.pixel_size = Track.U * 0.8
	h.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	h.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	h.set_meta("pos", pos)
	h.position = track.to3(pos, 24.0)
	add_child(h)
	hearts.append(h)


func _hurt(amount: float, dtype: String) -> void:
	if invuln > 0.0:
		return
	if shields > 0:
		shields -= 1
		_effect_at(QUD.effect("shield_expire"), hero_pos, 6)
		Audio.play("shield_break")
		invuln = 0.3
		return
	hp = maxf(0.0, hp - amount)
	invuln = float(cfg("hurt_invuln", 0.5))
	_effect_at(Items.effect_strip(dtype), hero_pos, 6, 1.4)
	Audio.play("hit_player")
	hero_sprite.modulate = Color(1.0, 0.45, 0.45)
	if hp <= 0.0:
		_die()


func _die() -> void:
	state = DEAD
	Audio.play("death_player")
	Audio.music("lose_theme")
	results.text = "THE WIZARD IS DEAD\n\nSurvived %s, realm %d, level %d, %d monsters slain\n\nenter to try again    esc for the menu" % [_fmt_time(t), realm, level, kills]
	results.visible = true


func _win() -> void:
	state = WON
	Audio.music("victory_theme")
	results.text = "THE RIFTS ARE CLOSED\n\nSurvived %s, level %d, %d monsters slain\n\nenter to play again    esc for the menu" % [_fmt_time(t), level, kills]
	results.visible = true


# ---------------------------------------------------------------- level-ups

func _xp_needed() -> int:
	var l := level - 1
	return int(cfg("xp_base", 12)) + int(cfg("xp_step", 10)) * l + int(float(cfg("xp_quad", 3.0)) * l * l)


func _gain_xp(v: int) -> void:
	xp += v
	while xp >= _xp_needed() and state == PLAYING:
		xp -= _xp_needed()
		level += 1
		_offer_level_up()
		break


# A card for one of the game's named upgrades: its own text, then what it does here.
func _upgrade_option(entry: Dictionary, up: Dictionary) -> Dictionary:
	var preview: Dictionary = entry["effect"].duplicate(true)
	var res := SpellDB.apply_upgrade(preview, up)
	var lvl := int(up.get("level", 1))
	var lines := [String(SpellDB.description(up)).left(160), "-> %s" % String(res["summary"])]
	if lvl > 1:
		lines.append("costs %d banked pick%s" % [lvl - 1, "s" if lvl > 2 else ""])
	return {"title": "%s: %s" % [entry["spell"]["name"], up["name"]], "lines": lines, "icon": SpellDB.icon(entry["spell"]),
		"color": Items.type_color(String(entry["effect"].get("dtype", "Arcane"))).darkened(0.5), "spell": entry["spell"], "upgrade": up}


func _apply_upgrade(entry: Dictionary, up: Dictionary) -> void:
	var res := SpellDB.apply_upgrade(entry["effect"], up)
	entry["taken"].append(String(up["name"]))
	entry["level"] += 1
	entry["extra_charges"] = int(entry.get("extra_charges", 0)) + int(res["charges"])
	entry["cd_max"] = _cd_for(entry["spell"], entry["level"], int(entry["extra_charges"]))
	if int(res["hp_cost"]) != 0:
		entry["spell"] = entry["spell"].duplicate()
		entry["spell"]["hp_cost"] = maxi(0, int(entry["spell"].get("hp_cost", 0)) + int(res["hp_cost"]))
	for f in familiars:
		if f["entry"] == entry:
			f["damage"] = _spell_damage(entry)
	print("upgrade: %s -> %s: %s" % [entry["spell"]["name"], up["name"], res["summary"]])
	say("%s: %s" % [String(up["name"]).to_upper(), res["summary"]], 2.5)


func _spell_option(spell: Dictionary, upgrade: bool) -> Dictionary:
	var e := SpellDB.effect_for(spell)
	var lines := []
	if upgrade:
		lines.append("Upgrade: +25% damage, faster, more targets")
	lines.append("%s (%s)" % [SpellDB.kind_verb(String(e["kind"])), _effect_summary(e)])
	lines.append(SpellDB.description(spell).left(140))
	return {"title": String(spell["name"]) + (" +" if upgrade else ""), "lines": lines, "icon": SpellDB.icon(spell),
			"color": Items.type_color(String(e.get("dtype", "Arcane"))).darkened(0.65), "spell": spell}


func _effect_summary(e: Dictionary) -> String:
	match String(e["kind"]):
		"bolt", "beam":
			return "%d %s damage" % [int(e["damage"]), e["dtype"]]
		"blast":
			return "%d %s damage, area" % [int(e["damage"]), e["dtype"]]
		"summon":
			return "orbiting familiar, %d damage" % int(e["damage"])
		"shield":
			return "absorb %d hits" % int(e["shields"])
		"heal":
			return "+%d HP" % int(e["amount"])
		"buff":
			return "+8% move speed"
		"blink":
			return "dash away when surrounded"
		"hex":
			return "freeze the nearest monsters"
		"melee":
			return "%d %s damage to what is in front, knocked back" % [int(e.get("damage", 0)), e.get("dtype", "Physical")]
		"burst":
			return "%d %s damage to everything around you" % [int(e.get("damage", 0)), e.get("dtype", "Arcane")]
		"aura":
			if float(e.get("damage", 0.0)) <= 0.0:
				return "heals %d every %.1fs for %ds" % [int(e.get("heal", 0)), float(e.get("tick", 0.8)), int(e.get("duration", 8))]
			return "%d %s damage every %.1fs for %ds" % [int(e.get("damage", 0)), e.get("dtype", "Arcane"), float(e.get("tick", 0.8)), int(e.get("duration", 8))]
		"patch":
			return "a %s field on the ground ahead, %d damage a tick" % [String(e.get("dtype", "Fire")).to_lower(), int(e.get("damage", 0))]
		"empower":
			var parts := []
			for k in e.get("bonuses", {}):
				parts.append("%s +%s" % [String(k).replace("_", " "), str(e["bonuses"][k])])
			return "%s for %ds" % [", ".join(parts), int(e.get("duration", 8))]
	return ""


func _passive_option(kind: String) -> Dictionary:
	var info: Array = {
		"hp": ["Tough", "+15 max HP and heal 15", Color(0.3, 0.5, 0.3)],
		"speed": ["Quick", "+12% move speed", Color(0.5, 0.45, 0.2)],
		"magnet": ["Greedy", "+60% gem pickup range", Color(0.25, 0.4, 0.55)],
		"cooldown": ["Hasty", "-12% spell cooldowns", Color(0.45, 0.3, 0.5)],
		"regen": ["Vigor", "+1 HP per second", Color(0.5, 0.3, 0.3)],
	}[kind]
	return {"title": info[0], "lines": [info[1]], "icon": null, "color": info[2], "passive": kind}


func _offer_level_up() -> void:
	state = CHOOSING
	var opts := []
	var owned := {}
	for s in spells:
		owned[s["spell"]["name"]] = s
	var pool_spells := []
	for sp in SpellDB.spells:
		if int(sp["level"]) <= mini(9, 1 + bank) and not owned.has(sp["name"]):   # banked picks buy higher levels
			pool_spells.append(sp)
	var picks := 0
	var tries := 0
	while opts.size() < 3 and tries < 30:
		tries += 1
		var r := rng.randf()
		if r < 0.45 and pool_spells.size() > 0 and spells.size() < 10:
			var sp: Dictionary = pool_spells[rng.randi_range(0, pool_spells.size() - 1)]
			pool_spells.erase(sp)
			opts.append(_spell_option(sp, false))
		elif r < 0.75 and spells.size() > 0 and picks < 2:
			var s: Dictionary = spells[rng.randi_range(0, spells.size() - 1)]
			var dup := false
			for o in opts:
				if o.has("spell") and o["spell"]["name"] == s["spell"]["name"]:
					dup = true
			if dup:
				continue
			# one of the game's own upgrades for it, the cheapest still affordable with banked picks
			var affordable := []
			for up in SpellDB.upgrade_options(s["spell"], s["taken"]):
				if int(up.get("level", 1)) <= 1 + bank:
					affordable.append(up)
			if not affordable.is_empty():
				opts.append(_upgrade_option(s, affordable[rng.randi_range(0, mini(1, affordable.size() - 1))]))
				picks += 1
			elif int(s["level"]) < 6:
				opts.append(_spell_option(s["spell"], true))
				picks += 1
		else:
			var kinds := ["hp", "speed", "magnet", "cooldown", "regen"]
			var k: String = kinds[rng.randi_range(0, kinds.size() - 1)]
			var dup := false
			for o in opts:
				if o.get("passive", "") == k:
					dup = true
			if dup:
				continue
			opts.append(_passive_option(k))
	opts.append({"title": "Bank this pick", "lines": ["Save it for a bigger spell: %d banked now, so level-%d spells can turn up next time." % [bank, bank + 2],
		"Taking a level-N spell spends N-1 banked picks."], "icon": QUD.texture("tiles/item_spell_scroll.png"),
		"color": Color(0.16, 0.16, 0.2), "bank": true})
	if screen_arg == "levelup" and spells.size() > 0:   # screenshots: show a named upgrade first
		var ups := SpellDB.upgrade_options(spells[0]["spell"], spells[0]["taken"])
		if not ups.is_empty():
			opts.insert(0, _upgrade_option(spells[0], ups[0]))
			opts.resize(4)
	choice = Choice.new()
	add_child(choice)
	choice.setup("LEVEL %d" % level, "pick one   (%d banked)" % bank, opts)
	choice.picked.connect(_on_choice)
	Audio.play("victory_level")
	if auto_player and screen_arg != "levelup":
		_on_choice.call_deferred(rng.randi_range(0, opts.size() - 1))


func _offer_start() -> void:
	state = CHOOSING
	var opts := []
	var names := []
	var quick := 3.0 * float(cfg("cooldown_scale", 1.0))
	for sp in SpellDB.spells:
		var e := SpellDB.effect_for(sp)
		if int(sp["level"]) == 1 and e["kind"] in ["bolt", "blast", "beam", "melee"] and _cd_for(sp, 1) <= quick:
			names.append(String(sp["name"]))
	if names.is_empty():   # never an empty choice: any level-1 damaging spell
		for sp in SpellDB.spells:
			if int(sp["level"]) == 1 and float(sp.get("stats", {}).get("damage", 0)) > 0.0:
				names.append(String(sp["name"]))
	names.shuffle()
	for n in names:
		if opts.size() < 3:
			opts.append(_spell_option(SpellDB.by_name[n], false))
	choice = Choice.new()
	add_child(choice)
	choice.setup("RIFT WIZARD SURVIVORS", "choose your first spell. WASD walk, Tab pause (Q there quits to the menu)", opts)
	choice.picked.connect(_on_choice)
	if auto_player:
		_on_choice.call_deferred(0)


func _on_choice(i: int) -> void:
	var o: Dictionary = choice.options[i]
	if o.get("bank", false):
		bank += 1
		say("PICK BANKED (%d)" % bank, 1.2)
	elif o.has("upgrade"):
		for s in spells:
			if s["spell"]["name"] == o["spell"]["name"]:
				_apply_upgrade(s, o["upgrade"])
		bank = maxi(0, bank - (int(o["upgrade"].get("level", 1)) - 1))
	elif o.has("spell"):
		var was_owned := false
		for s in spells:
			if s["spell"]["name"] == o["spell"]["name"]:
				was_owned = true
		if not was_owned:
			bank = maxi(0, bank - (int(o["spell"].get("level", 1)) - 1))
		_add_spell(o["spell"])
	elif o.has("passive"):
		match String(o["passive"]):
			"hp":
				max_hp += 15.0
				hp = minf(max_hp, hp + 15.0)
			"speed":
				speed_bonus += 0.12
			"magnet":
				magnet *= 1.6
			"cooldown":
				cooldown_mult *= 0.88
				for s in spells:
					s["cd_max"] = _cd_for(s["spell"], s["level"])
			"regen":
				regen += 1.0
	choice.queue_free()
	choice = null
	state = PLAYING
	if not opened:
		opened = true
		_opening_spawn()
	if xp >= _xp_needed():
		_gain_xp(0)


# ---------------------------------------------------------------- realm arenas

# Build the game's realm r as the arena: walls, chasms, its monsters and lairs where the
# game put them, its orbs and components as pickups, its rifts as the way on.
func _load_arena(r: int) -> bool:
	for m in mobs.duplicate():
		var holder: Node3D = m.get_meta("holder")
		holder.queue_free()
	mobs.clear()
	for lst in [gems, hearts, bolts, hazards, rifts]:
		for x in lst:
			x.queue_free()
		lst.clear()
	auras.clear()
	familiars_reset()
	if arena != null:
		arena.queue_free()
	arena = Arena.new()
	arena.tile_px = float(cfg("realm_tile_px", 200.0))
	add_child(arena)
	if not arena.load_realm(r, rng, realm_file):
		push_error("Survivors: no realm dump for realm %d (run tools/extract_levels.py and the exporter)" % r)
		return false
	realm_file = ""
	arena.build()
	track.size = Vector2(arena.px_size(), arena.px_size())
	hero_pos = arena.start_pos()
	player.position = track.to3(hero_pos)
	arena.update_flow(hero_pos)
	cleared = false
	clear_timer = 0.0
	boss_alive = false
	_place_level_units()
	_place_level_props()
	say("REALM %d   %s" % [r, String(arena.level.get("tileset", "")).capitalize()], 2.5)
	return true


func familiars_reset() -> void:
	for f in familiars:
		var holder: Node3D = f["holder"]
		holder.position = track.to3(hero_pos)


# The dumps keep a compact spell list; give it the shape _ability_from expects.
func _full_spells(compact: Array) -> Array:
	var out := []
	for sp in compact:
		if not (sp is Dictionary):
			continue
		var dtypes: Array = sp.get("damage_type", [])
		out.append({"name": sp.get("name", "Attack"), "tags": dtypes, "damage_type": dtypes, "range": float(sp.get("range", 1.5)),
			"melee": bool(sp.get("melee", false)), "stats": {"damage": float(sp.get("damage", 0))}})
	return out


func _place_level_units() -> void:
	for u in arena.level.get("units", []):
		var asset: Array = u.get("asset", [])
		if asset.is_empty():
			continue
		var unit := String(asset[asset.size() - 1])
		if not QUD.has_unit(unit):
			continue
		var pos := arena.tile_center(int(u.get("x", 0)), int(u.get("y", 0)))
		var species := {"name": u.get("name", unit), "unit": unit, "hp": float(u.get("hp", 10)), "flying": bool(u.get("flying", false)),
			"spells": _full_spells(u.get("spells", []))}
		if bool(u.get("is_lair", false)):
			var cd := 7.0
			for sp in u.get("spells", []):
				if sp is Dictionary and float(sp.get("cool_down", 0)) > 0.0:
					cd = float(sp["cool_down"]) * float(cfg("spawner_cooldown_scale", 0.8))
			_spawn_mob(species, false, pos, {"spawner": species.duplicate(), "spawn_cd": cd, "hp": float(u.get("hp", 40))})
		else:
			_spawn_mob(species, bool(u.get("is_boss", false)) or bool(u.get("is_final_boss", false)), pos)


func _place_level_props() -> void:
	var dormant := QUD.texture("tiles/portal_dormant_portal.png")
	for p in arena.level.get("props", []):
		var pos := arena.tile_center(int(p.get("x", 0)), int(p.get("y", 0)))
		match String(p.get("type", "")):
			"MemoryOrb":
				_drop_gem(pos, int(cfg("orb_xp", 8)))
				gems[gems.size() - 1].set_meta("life", 99999.0)
			"ComponentPickup":
				_drop_heart(pos)
			"Portal":
				var s := Sprite3D.new()
				s.texture = dormant
				s.pixel_size = Track.U * 1.6
				s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
				s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				s.set_meta("pos", pos)
				s.position = track.to3(pos, 40.0)
				add_child(s)
				rifts.append(s)


func _on_cleared() -> void:
	cleared = true
	var active := QUD.texture("tiles/portal_active_portal.png")
	for r in rifts:
		if active != null:
			r.texture = active
	if realm >= 21:
		_win()
		return
	if rifts.is_empty():
		clear_timer = 3.0
		say("REALM CLEARED", 3.0)
	else:
		say("REALM CLEARED   walk into a rift", 4.0)
	Audio.play("victory_level")


func _next_realm() -> void:
	realm += 1
	if realm > 21:
		_win()
		return
	_refresh_pool()
	_load_arena(realm)
	Audio.play("start_level")


# A few monsters right at the start, close enough to matter.
var opened := false


func _opening_spawn() -> void:
	if pool.is_empty():
		return
	var n := int(cfg("opening_mobs", 3))
	var dist := float(cfg("opening_distance", 480.0))
	for i in n:
		var ang := TAU * i / n + rng.randf_range(-0.4, 0.4)
		_spawn_mob(pool[rng.randi_range(0, pool.size() - 1)], false, hero_pos + Vector2(cos(ang), sin(ang)) * dist)


# ---------------------------------------------------------------- simulation

func say(text: String, duration := 1.5) -> void:
	message = text
	message_t = duration


func _physics_process(dt: float) -> void:
	if state != PLAYING:
		return
	t += dt
	realm_t += dt
	message_t = maxf(0.0, message_t - dt)
	invuln = maxf(0.0, invuln - dt)
	if regen > 0.0:
		hp = minf(max_hp, hp + regen * dt)

	if realm_mode:
		flow_t -= dt
		if flow_t <= 0.0:
			flow_t = 0.25
			arena.update_flow(hero_pos)
		if cleared:
			if clear_timer > 0.0:
				clear_timer -= dt
				if clear_timer <= 0.0:
					_next_realm()
					return
			for r in rifts:
				if hero_pos.distance_to(r.get_meta("pos")) < 70.0:
					_next_realm()
					return
	else:
		# realm timer
		var realm_len := float(cfg("realm_seconds", 60.0))
		var new_realm := 1 + int(t / realm_len)
		if new_realm != realm and new_realm <= 21:
			realm = new_realm
			_refresh_pool()
			say("REALM %d" % realm, 2.0)
			Audio.play("start_level")
		if realm != last_realm_spawned and realm >= 2 and realm_t >= 0.0:
			last_realm_spawned = realm
			_spawn_boss()

	_move_hero(dt)
	_update_spells(dt)
	_update_auras(dt)
	_update_hazards(dt)
	Campaign.tick_cooldowns(dt)
	_update_familiars(dt)
	_spawn(dt)
	_update_mobs(dt)
	_update_bolts(dt)
	_update_pickups(dt)
	for e in effects.duplicate():
		if not e.tick(dt):
			effects.erase(e)
			e.queue_free()
	for l in lines.duplicate():
		l.set_meta("life", float(l.get_meta("life")) - dt)
		if float(l.get_meta("life")) <= 0.0:
			lines.erase(l)
			l.queue_free()
	_update_camera()


func _move_hero(dt: float) -> void:
	var dir := Vector2.ZERO
	if auto_player:
		var threats := _nearest_mobs(hero_pos, 700.0, 16)
		for m in threats:
			var rel: Vector2 = hero_pos - m.get_meta("pos")
			dir += rel.normalized() / maxf(0.2, rel.length() / 300.0)
		var best_g: Sprite3D = null
		var best_d := 900.0
		for g in gems:
			var d: float = hero_pos.distance_to(g.get_meta("pos"))
			if d < best_d:
				best_d = d
				best_g = g
		if best_g != null:
			dir += (best_g.get_meta("pos") - hero_pos).normalized() * 0.8
		if dir.length_squared() < 0.01:
			dir = Vector2(cos(t * 0.3), sin(t * 0.3))
	else:
		dir = Vector2(Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left"),
					  Input.get_action_strength("drive_back") - Input.get_action_strength("drive_forward"))
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	if dir.length_squared() > 0.01:
		hero_dir = dir.normalized()
		var step := dir * hero_speed * (1.0 + speed_bonus) * dt
		if realm_mode:
			hero_pos = arena.try_move(hero_pos, step, 22.0, false)
		else:
			var np := hero_pos + step
			var r := _collide(np, 24.0)
			if r["hit"]:
				np = r["pos"]
			np.x = clampf(np.x, 40.0, track.size.x - 40.0)
			np.y = clampf(np.y, 40.0, track.size.y - 40.0)
			hero_pos = np
	player.position = track.to3(hero_pos)
	hero_sprite.frame = int(t / 0.2) % maxi(1, hero_sprite.hframes)
	hero_sprite.flip_h = hero_dir.x < 0.0
	hero_sprite.modulate = hero_sprite.modulate.lerp(Color.WHITE, minf(1.0, 6.0 * dt))


func _update_spells(dt: float) -> void:
	for s in spells:
		s["cd"] -= dt
		if s["cd"] <= 0.0:
			if _cast(s):
				s["cd"] = s["cd_max"]
			else:
				s["cd"] = 0.3


func _update_familiars(dt: float) -> void:
	for f in familiars:
		f["angle"] += dt * 2.6
		var p := hero_pos + Vector2(cos(f["angle"]), sin(f["angle"])) * 170.0
		var holder: Node3D = f["holder"]
		holder.position = track.to3(p)
		var s: Sprite3D = f["sprite"]
		s.frame = int(t / 0.2) % maxi(1, s.hframes)
		s.flip_h = cos(f["angle"] + PI / 2) < 0.0
		f["tick"] -= dt
		if f["tick"] <= 0.0:
			f["tick"] = 0.45
			for m in _nearest_mobs(p, 70.0, 4):
				_hit_mob(m, float(f["damage"]), String(f["entry"]["effect"].get("dtype", "Physical")))


func _spawned_by(spawner: Sprite3D) -> int:
	var n := 0
	for m in mobs:
		if m.has_meta("from") and m.get_meta("from") == spawner:
			n += 1
	return n


func _spawn(dt: float) -> void:
	if pool.is_empty() or realm_mode:
		return
	var rate := float(cfg("spawn_base", 1.5)) + float(cfg("spawn_per_realm", 0.6)) * (realm - 1)
	spawn_acc += rate * dt
	var cap := int(cfg("max_mobs", 350))
	while spawn_acc >= 1.0 and mobs.size() < cap:
		spawn_acc -= 1.0
		_spawn_mob(pool[rng.randi_range(0, pool.size() - 1)])
	if spawn_acc > 5.0:
		spawn_acc = 5.0


func _update_mobs(dt: float) -> void:
	var cd: Array = cfg("ability_cooldown", [4.0, 7.0])
	var despawn := float(cfg("despawn_radius", 3600.0))
	var dmg_scale := Kart.interp(cfg("damage_by_band", [[1, 1.0]]), float(band_for(realm))) * float(cfg("contact_damage_scale", 0.6))
	for m in mobs.duplicate():
		var pos: Vector2 = m.get_meta("pos")
		var frozen := float(m.get_meta("frozen"))
		var to := hero_pos - pos
		var dist := to.length()
		if m.has_meta("spawner"):
			var st := float(m.get_meta("spawn_t")) - dt
			if st <= 0.0 and mobs.size() < int(cfg("max_mobs", 350)) and _spawned_by(m) < int(cfg("spawner_cap", 4)):
				st = float(m.get_meta("spawn_cd"))
				var sp: Dictionary = m.get_meta("spawner")
				var where := pos + Vector2(float(cfg("realm_tile_px", 200.0)) * 0.7, 0).rotated(rng.randf_range(0, TAU))
				if arena == null or arena.can_stand(where, 18.0, bool(sp.get("flying", false))):
					_spawn_mob(sp, false, where, {"from": m})
					_effect_at(QUD.effect("conjuration"), where, 6)
			m.set_meta("spawn_t", st)
			var fl2 := float(m.get_meta("flash"))
			m.modulate = Color(1.0, 0.5, 0.5) if fl2 > 0.0 else Color.WHITE
			m.set_meta("flash", maxf(0.0, fl2 - dt))
			m.frame = int((t + float(m.get_meta("t"))) / 0.3) % maxi(1, m.hframes)
			continue
		if not realm_mode and dist > despawn and not bool(m.get_meta("boss")):
			# too far behind: teleport back to the spawn ring rather than wander forever
			var spawn_r: Array = cfg("spawn_radius", [1500.0, 2200.0])
			pos = hero_pos + Vector2(float(spawn_r[1]), 0).rotated(rng.randf_range(0, TAU))
			m.set_meta("pos", pos)
			to = hero_pos - pos
			dist = to.length()
		if frozen > 0.0:
			m.set_meta("frozen", frozen - dt)
			m.modulate = Color(0.6, 0.85, 1.0)
		else:
			var speed := float(m.get_meta("speed"))
			if dist > 1.0 and realm_mode:
				var dir := arena.flow_dir(pos, bool(m.get_meta("flying"))) if dist > 90.0 else to / dist
				pos = arena.try_move(pos, dir * speed * dt, 18.0, bool(m.get_meta("flying")))
				m.set_meta("pos", pos)
			elif dist > 1.0:
				var step := to / dist * speed * dt
				var np := pos + step
				var r := _collide(np, 20.0)
				if r["hit"]:
					# slide along the wall
					var n: Vector2 = r["normal"]
					np = r["pos"] + (step - n * step.dot(n)) * 0.5
					var r2 := _collide(np, 20.0)
					if r2["hit"]:
						np = r2["pos"]
				pos = np
				m.set_meta("pos", pos)
			var fl := float(m.get_meta("flash"))
			m.modulate = Color(1.0, 0.5, 0.5) if fl > 0.0 else Color.WHITE
			m.set_meta("flash", maxf(0.0, fl - dt))
			# attack
			var hit_cd := float(m.get_meta("hit_cd")) - dt
			var radius := float(m.get_meta("radius"))
			if dist < radius + 26.0 and hit_cd <= 0.0:
				_hurt(maxf(1.0, float(m.get_meta("damage")) * dmg_scale), String(m.get_meta("dtype")))
				hit_cd = 1.0
			m.set_meta("hit_cd", hit_cd)
			var a: Dictionary = m.get_meta("ability")
			if a["kind"] == "ranged":
				var acd := float(m.get_meta("cd")) - dt
				if acd <= 0.0 and dist < float(a["range"]) + 300.0:
					acd = rng.randf_range(float(cd[0]), float(cd[1]))
					var p := Items.Projectile.new()
					p.texture = QUD.texture("effects/proj/arcane_bolt.png")
					p.pixel_size = Track.U * 0.7
					p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					p.modulate = Items.type_color(String(a["dtype"]))
					p.pos = pos
					p.vel = to.normalized() * 520.0
					p.damage = maxf(1.0, float(a["damage"]) * float(cfg("ranged_damage_scale", 0.6)) * dmg_scale / float(cfg("contact_damage_scale", 0.6)))
					p.dtype = String(a["dtype"])
					p.life = 3.0
					p.set_meta("from_hero", false)
					add_child(p)
					bolts.append(p)
				m.set_meta("cd", acd)
		var holder: Node3D = m.get_meta("holder")
		holder.position = track.to3(pos)
		m.frame = int((t + float(m.get_meta("t"))) / 0.2) % maxi(1, m.hframes)
		m.flip_h = to.x < 0.0


func _update_bolts(dt: float) -> void:
	for p in bolts.duplicate():
		if p.has_meta("target"):
			var tg = p.get_meta("target")
			if tg != null and is_instance_valid(tg) and mobs.has(tg):
				var want: Vector2 = (tg.get_meta("pos") - p.pos).normalized() * p.vel.length()
				p.vel = p.vel.lerp(want, minf(1.0, 6.0 * dt))
		p.pos += p.vel * dt
		p.life -= dt
		p.age += dt
		p.position = track.to3(p.pos, 24.0)
		var alive: bool = p.life > 0.0
		if bool(p.get_meta("from_hero")):
			var hit: Sprite3D = null
			for m in mobs:
				if p.pos.distance_squared_to(m.get_meta("pos")) < pow(float(m.get_meta("radius")) + 14.0, 2):
					hit = m
					break
			if hit != null:
				if p.radius > 0.0:
					for m in _nearest_mobs(p.pos, p.radius, 40):
						_hit_mob(m, p.damage, p.dtype)
						if p.has_meta("stun"):
							_stun_mob(m, float(p.get_meta("stun")))
						if p.heal_frac > 0.0:
							_heal_hero(p.damage * p.heal_frac)
					_effect_at(Items.effect_strip(p.dtype), p.pos, 6, 2.2)
				else:
					_hit_mob(hit, p.damage, p.dtype)
					if p.has_meta("stun"):
						_stun_mob(hit, float(p.get_meta("stun")))
					if p.heal_frac > 0.0:
						_heal_hero(p.damage * p.heal_frac)
				alive = false
		else:
			if p.pos.distance_squared_to(hero_pos) < 30.0 * 30.0:
				_hurt(p.damage, p.dtype)
				alive = false
		if (realm_mode and arena.blocks_shot(p.pos)) or (not realm_mode and _collide(p.pos, 4.0)["hit"]):
			alive = false
		if not alive:
			bolts.erase(p)
			p.queue_free()


func _update_pickups(dt: float) -> void:
	for g in gems.duplicate():
		var pos: Vector2 = g.get_meta("pos")
		var life := float(g.get_meta("life")) - dt
		g.set_meta("life", life)
		var d := hero_pos.distance_to(pos)
		if d < magnet:
			pos = pos.move_toward(hero_pos, (600.0 + (magnet - d) * 3.0) * dt)
			g.set_meta("pos", pos)
			g.position = track.to3(pos, 20.0)
		if d < 30.0 or life <= 0.0:
			if d < 30.0:
				_gain_xp(int(g.get_meta("value")))
				Audio.play("item_pickup", -10.0)
			gems.erase(g)
			g.queue_free()
	for h in hearts.duplicate():
		if hero_pos.distance_to(h.get_meta("pos")) < 40.0:
			hp = minf(max_hp, hp + float(cfg("heart_heal", 15.0)))
			say("+%d HP" % int(cfg("heart_heal", 15.0)), 0.8)
			Audio.play("item_pickup")
			hearts.erase(h)
			h.queue_free()


# ---------------------------------------------------------------- hud

func _process(_delta: float) -> void:
	if state == PAUSED and Input.is_action_just_pressed("quick_shop"):
		get_tree().change_scene_to_file("res://Menu.tscn")
		return
	if Input.is_action_just_pressed("pause"):
		if state == PLAYING:
			state = PAUSED
			say("PAUSED     Tab resume     Q quit to menu", 999.0)
		elif state == PAUSED:
			state = PLAYING
			message_t = 0.0
		elif state in [DEAD, WON]:
			get_tree().change_scene_to_file("res://Menu.tscn")
	if state in [DEAD, WON] and Input.is_action_just_pressed("confirm"):
		get_tree().reload_current_scene()
		return
	if Input.is_action_just_pressed("free_drive") and state == PLAYING:
		pass

	lbl_top.text = "%s     REALM %d / 20     level %d     kills %d     monsters %d%s" % [_fmt_time(t), realm, level, kills, mobs.size(), ("     banked %d" % bank) if bank > 0 else ""]
	hp_fill.size = Vector2(360.0 * clampf(hp / maxf(1.0, max_hp), 0.0, 1.0), 26)
	xp_fill.size = Vector2(360.0 * clampf(float(xp) / maxf(1.0, float(_xp_needed())), 0.0, 1.0), 16)
	lbl_stats.text = "HP %d / %d%s     XP %d / %d" % [int(hp), int(max_hp), "   shield x%d" % shields if shields > 0 else "", xp, _xp_needed()]
	for i in 10:
		if i < spells.size():
			spell_icons[i].texture = SpellDB.icon(spells[i]["spell"])
			spell_icons[i].modulate = Color.WHITE if spells[i]["cd"] <= 0.05 else Color(0.6, 0.6, 0.6)
			spell_lvls[i].text = "L%d" % int(spells[i]["level"])
		else:
			spell_icons[i].texture = null
			spell_lvls[i].text = ""
	lbl_center.text = message if message_t > 0.0 else ""
	if minimap != null:
		minimap.queue_redraw()

	frame_count += 1
	if screen_arg == "levelup" and frame_count == 30 and state == PLAYING:
		level += 1
		_offer_level_up()
	if frames_left >= 0 and frame_count >= frames_left:
		frames_left = -1
		_finish_screenshot()


func _fmt_time(tm: float) -> String:
	var m := int(tm / 60.0)
	var s := int(tm) % 60
	return "%02d:%02d" % [m, s]


func _finish_screenshot() -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if screenshot_path != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png(screenshot_path)
		print("saved ", screenshot_path)
	print("survivors: state=%s t=%s realm=%d level=%d hp=%d kills=%d mobs=%d spells=%d fps=%d" % [
		state, _fmt_time(t), realm, level, int(hp), kills, mobs.size(), spells.size(), Engine.get_frames_per_second()])
	get_tree().quit()
