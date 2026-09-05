# Rift Wizard Gauntlet: the game's generated realms in real time. See
# docs/gauntlet.md. Uses the Campaign autoload for HP, spell points, spells and
# artifacts, and Shop.gd for buying.
#
# Flags after "--": --mode=gauntlet --seed=N --auto --mute --realm=N
#   --frames=N --screenshot=path --spells=Name --screen=shop
extends Node3D

const TILE := 100.0          # world px per tile
const PLAYING := "playing"
const CLEARED := "cleared"
const DEAD := "dead"
const WON := "won"

var rng := RandomNumberGenerator.new()
var G := {}
var level := {}
var size := 18
var grid: Array = []          # rows of strings
var walk: Array = []          # [y][x] bool: walkable for walkers
var passable: Array = []      # [y][x] bool: not a wall (fliers)
var flow: Array = []          # [y][x] int distance to player, -1 unreachable
var flow_t := 0.0
var state := PLAYING
var paused := false
var t := 0.0
var auto_player := false
var screenshot_path := ""
var frames_left := -1
var frame_count := 0
var screen_arg := ""

var player: Node3D
var hero_sprite: Sprite3D
var hero_pos := Vector2.ZERO
var hero_dir := Vector2.RIGHT
var hero_speed := 380.0
var auras: Array = []      # running aura spells (see _update_auras)
var hazards: Array = []    # laid patches (Items.Hazard)
var invuln := 0.0
var cooldowns: Array = []     # per Campaign.spells index
var familiars: Array = []

var mobs: Array = []          # Sprite3D with meta
var spawners: Array = []
var bolts: Array = []
var effects: Array = []
var lines: Array = []
var pickups: Array = []       # Sprite3D with meta kind
var portals: Array = []       # Sprite3D with meta
var shadow_mesh: Mesh
var kills := 0
var message := ""
var message_t := 0.0

var cam: Camera3D
var hud: CanvasLayer
var lbl_top: Label
var lbl_stats: Label
var lbl_center: Label
var hp_fill: ColorRect
var slot_icons: Array = []
var slot_cd: Array = []
var slot_keys: Array = []
var results: Label
var shop: Shop = null
var map: Control


func cfg(key: String, default = null):
	return G.get(key, default)


func _ready() -> void:
	var args := _parse_args()
	G = Shared.tuning.get("gauntlet", {})
	if not Campaign.active or args.has("newrun"):
		Campaign.new_run(int(args.get("seed", -1)))
	if args.has("realm"):
		Campaign.level = int(args["realm"])
	if args.has("sp"):
		Campaign.sp = int(args["sp"])
	if args.has("spells"):
		for n in String(args["spells"]).split(","):
			if SpellDB.by_name.has(n):
				Campaign.buy(SpellDB.by_name[n])
	rng.seed = int(args.get("seed", Campaign.seed))
	auto_player = args.has("auto")
	screenshot_path = args.get("screenshot", "")
	frames_left = int(args.get("frames", -1))
	if frames_left >= 0 and Campaign.debug_t0_ms == 0:
		Campaign.debug_t0_ms = Time.get_ticks_msec()
	screen_arg = String(args.get("screen", ""))
	hero_speed = float(cfg("hero_speed", 380.0))

	if not _load_level(Campaign.level):
		push_error("Gauntlet: no realm dump for level %d (run tools/extract_levels.py and export)" % Campaign.level)
		return
	_build_environment()
	_build_shadow_mesh()
	_build_arena()
	_build_units()
	_build_props()
	_build_hero()
	_build_camera()
	_build_hud()
	_sync_cooldowns()
	Audio.music("battle_%d" % (1 + (Campaign.level - 1) % 12))
	say("REALM %d" % Campaign.level, 2.0)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


# ---------------------------------------------------------------- level data

func _load_level(realm: int) -> bool:
	var index_path := QUD.ROOT + "levels/index.json"
	if not FileAccess.file_exists(index_path):
		return false
	var idx = JSON.parse_string(FileAccess.open(index_path, FileAccess.READ).get_as_text())
	if not (idx is Array):
		return false
	var options := []
	for e in idx:
		if int(e["difficulty"]) == clampi(realm, 1, 21):
			options.append(e)
	if options.is_empty():
		return false
	var pick: Dictionary = options[rng.randi_range(0, options.size() - 1)]
	var path := QUD.ROOT + "levels/" + String(pick["file"])
	var d = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	if not (d is Dictionary):
		return false
	level = d
	size = int(d["size"])
	grid = d["grid"]
	walk = []
	passable = []
	for y in size:
		var wr := []
		var pr := []
		var row: String = grid[y]
		for x in size:
			var c := row[x]
			wr.append(c == ".")
			pr.append(c != "#")
		walk.append(wr)
		passable.append(pr)
	return true


func tile_at(p: Vector2) -> Vector2i:
	return Vector2i(int(p.x / TILE), int(p.y / TILE))


func tile_center(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * TILE, (y + 0.5) * TILE)


func can_stand(p: Vector2, radius: float, flying: bool) -> bool:
	for off in [Vector2(-radius, -radius), Vector2(radius, -radius), Vector2(-radius, radius), Vector2(radius, radius), Vector2.ZERO]:
		var q: Vector2 = p + off
		var tx := int(q.x / TILE)
		var ty := int(q.y / TILE)
		if tx < 0 or ty < 0 or tx >= size or ty >= size:
			return false
		if flying:
			if not passable[ty][tx]:
				return false
		elif not walk[ty][tx]:
			return false
	return true


# Try the move, then each axis alone, so walls slide.
func try_move(p: Vector2, step: Vector2, radius: float, flying: bool) -> Vector2:
	if can_stand(p + step, radius, flying):
		return p + step
	if can_stand(p + Vector2(step.x, 0), radius, flying):
		return p + Vector2(step.x, 0)
	if can_stand(p + Vector2(0, step.y), radius, flying):
		return p + Vector2(0, step.y)
	return p


func _update_flow() -> void:
	flow = []
	for y in size:
		var r := []
		for x in size:
			r.append(-1)
		flow.append(r)
	var start := tile_at(hero_pos)
	if start.x < 0 or start.y < 0 or start.x >= size or start.y >= size:
		return
	var queue := [start]
	flow[start.y][start.x] = 0
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d: int = flow[c.y][c.x]
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = c.x + off.x
			var ny: int = c.y + off.y
			if nx < 0 or ny < 0 or nx >= size or ny >= size:
				continue
			if not passable[ny][nx] or flow[ny][nx] >= 0:
				continue
			flow[ny][nx] = d + 1
			queue.append(Vector2i(nx, ny))


func flow_dir(p: Vector2, flying: bool) -> Vector2:
	var c := tile_at(p)
	if c.x < 0 or c.y < 0 or c.x >= size or c.y >= size or flow.is_empty():
		return (hero_pos - p).normalized()
	var here: int = flow[c.y][c.x]
	if here <= 0:
		return (hero_pos - p).normalized()
	var best := here
	var target := Vector2i(-1, -1)
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var nx: int = c.x + off.x
		var ny: int = c.y + off.y
		if nx < 0 or ny < 0 or nx >= size or ny >= size:
			continue
		var v: int = flow[ny][nx]
		if v < 0 or v >= best:
			continue
		if not flying and not walk[ny][nx]:
			continue
		if off.x != 0 and off.y != 0 and (not passable[c.y][nx] or not passable[ny][c.x]):
			continue
		best = v
		target = Vector2i(nx, ny)
	if target.x < 0:
		return (hero_pos - p).normalized()
	return (tile_center(target.x, target.y) - p).normalized()


# ---------------------------------------------------------------- build

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.65, 0.8)
	env.ambient_light_energy = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, 25, 0)
	sun.light_energy = 1.0
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


func _mat(tex: Texture2D, color := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if tex:
		m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.texture_repeat = true
	m.roughness = 1.0
	m.metallic_specular = 0.0
	return m


func _tile_texture(x: int, y: int, kind: String) -> Texture2D:
	var ts: String = level["tileset"]
	var chasm: String = level["chasm"]
	var ov: Dictionary = level.get("tile_overrides", {})
	var key := "%d,%d" % [x, y]
	if ov.has(key):
		ts = String(ov[key][0])
		chasm = String(ov[key][1])
	if kind == "floor":
		var tex := QUD.texture("tiles/floor_%s.png" % ts)
		return tex if tex != null else QUD.texture("tiles/floor_stone.png")
	if kind == "chasm":
		return QUD.texture("tiles/chasm_%s.png" % chasm)
	var w := QUD.texture("tiles/%s_wall_%d.png" % [ts, 1 + (x * 7 + y * 13) % 4])
	return w if w != null else QUD.texture("tiles/brick_wall_1.png")


func _build_arena() -> void:
	var U := Track.U
	var groups := {}   # texture -> SurfaceTool
	var wall_h := TILE * 1.1 * U
	for y in size:
		for x in size:
			var c: String = grid[y][x]
			var x0 := x * TILE * U
			var x1 := (x + 1) * TILE * U
			var z0 := y * TILE * U
			var z1 := (y + 1) * TILE * U
			if c == "#":
				var tex := _tile_texture(x, y, "wall")
				var st: SurfaceTool = _group(groups, tex)
				# four sides + top
				var corners := [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]
				for i in 4:
					var a: Vector3 = corners[i]
					var b: Vector3 = corners[(i + 1) % 4]
					var at := a + Vector3(0, wall_h, 0)
					var bt := b + Vector3(0, wall_h, 0)
					st.set_uv(Vector2(0, 1)); st.add_vertex(a)
					st.set_uv(Vector2(1, 0)); st.add_vertex(bt)
					st.set_uv(Vector2(1, 1)); st.add_vertex(b)
					st.set_uv(Vector2(0, 1)); st.add_vertex(a)
					st.set_uv(Vector2(0, 0)); st.add_vertex(at)
					st.set_uv(Vector2(1, 0)); st.add_vertex(bt)
				var tl := Vector3(x0, wall_h, z0)
				var tr := Vector3(x1, wall_h, z0)
				var br := Vector3(x1, wall_h, z1)
				var bl := Vector3(x0, wall_h, z1)
				st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
				st.set_uv(Vector2(1, 0)); st.add_vertex(tr)
				st.set_uv(Vector2(1, 1)); st.add_vertex(br)
				st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
				st.set_uv(Vector2(1, 1)); st.add_vertex(br)
				st.set_uv(Vector2(0, 1)); st.add_vertex(bl)
			else:
				var depth := 0.0 if c == "." else -TILE * 0.6 * U
				var tex := _tile_texture(x, y, "floor" if c == "." else "chasm")
				var st: SurfaceTool = _group(groups, tex)
				var a := Vector3(x0, depth, z0)
				var b := Vector3(x1, depth, z0)
				var cc := Vector3(x1, depth, z1)
				var d := Vector3(x0, depth, z1)
				st.set_uv(Vector2(0, 0)); st.add_vertex(a)
				st.set_uv(Vector2(1, 0)); st.add_vertex(b)
				st.set_uv(Vector2(1, 1)); st.add_vertex(cc)
				st.set_uv(Vector2(0, 0)); st.add_vertex(a)
				st.set_uv(Vector2(1, 1)); st.add_vertex(cc)
				st.set_uv(Vector2(0, 1)); st.add_vertex(d)
				if c == "~":
					# chasm walls so the pit reads as a pit
					for pair in [[a, b], [b, cc], [cc, d], [d, a]]:
						var p0: Vector3 = pair[0]
						var p1: Vector3 = pair[1]
						var q0 := Vector3(p0.x, 0, p0.z)
						var q1 := Vector3(p1.x, 0, p1.z)
						st.set_uv(Vector2(0, 0)); st.add_vertex(q0)
						st.set_uv(Vector2(1, 0)); st.add_vertex(q1)
						st.set_uv(Vector2(1, 1)); st.add_vertex(p1)
						st.set_uv(Vector2(0, 0)); st.add_vertex(q0)
						st.set_uv(Vector2(1, 1)); st.add_vertex(p1)
						st.set_uv(Vector2(0, 1)); st.add_vertex(p0)
	for tex in groups:
		var st: SurfaceTool = groups[tex]
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mat(tex)
		add_child(mi)
	# a dark apron around the arena
	var apron := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size * TILE * U * 3, size * TILE * U * 3)
	quad.orientation = PlaneMesh.FACE_Y
	apron.mesh = quad
	apron.position = Vector3(size * TILE * U / 2, -0.05, size * TILE * U / 2)
	apron.material_override = _mat(null, Color(0.03, 0.02, 0.05))
	add_child(apron)


func _group(groups: Dictionary, tex: Texture2D) -> SurfaceTool:
	if not groups.has(tex):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		groups[tex] = st
	return groups[tex]


func to3(p: Vector2, lift_px := 0.0) -> Vector3:
	return Vector3(p.x * Track.U, lift_px * Track.U, p.y * Track.U)


func _sprite(unit: String, scale := 1.0) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = QUD.unit_idle(unit if QUD.has_unit(unit) else "goblin")
	s.hframes = maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
	s.pixel_size = Track.U * scale
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	var fs := int(QUD.unit_info(unit).get("frame_size", 60))
	s.position = Vector3(0, fs * Track.U * scale * 0.5, 0)
	return s


func _ability_from(spells_data: Array) -> Dictionary:
	for sp in spells_data:
		if not (sp is Dictionary):
			continue
		var dmg := float(sp.get("damage", 0))
		var rng_t := float(sp.get("range", 0))
		var dtypes: Array = sp.get("damage_type", [])
		var dtype := String(dtypes[0]) if dtypes.size() > 0 else "Arcane"
		if dmg > 0.0 and rng_t > 2.0 and not bool(sp.get("melee", false)):
			return {"name": sp.get("name", "Bolt"), "kind": "ranged", "damage": dmg, "range": rng_t * TILE, "dtype": dtype}
		if dmg > 0.0:
			return {"name": sp.get("name", "Bite"), "kind": "melee", "damage": dmg, "range": 60.0, "dtype": dtype}
	return {"name": "Bite", "kind": "melee", "damage": 3.0, "range": 60.0, "dtype": "Physical"}


func _place_mob(name: String, unit: String, pos: Vector2, mob_hp: float, flying: bool, spells_data: Array, boss := false, radius_tiles := 0) -> Sprite3D:
	var scale := 1.0 if radius_tiles == 0 else 1.0
	var s := _sprite(unit, scale)
	var stats := Kart.stats_from_unit(mob_hp, flying, rng)
	var ability := _ability_from(spells_data)
	s.set_meta("pos", pos)
	s.set_meta("hp", mob_hp)
	s.set_meta("max_hp", mob_hp)
	s.set_meta("speed", (float(cfg("mob_speed_base", 120.0)) + float(cfg("mob_speed_per_stat", 22.0)) * stats.x) * (0.7 if boss else 1.0))
	s.set_meta("damage", float(ability["damage"]) if ability["kind"] == "melee" else 3.0)
	s.set_meta("ability", ability)
	var cd: Array = cfg("ability_cooldown", [3.0, 6.0])
	s.set_meta("cd", rng.randf_range(float(cd[0]), float(cd[1])))
	s.set_meta("hit_cd", 0.0)
	s.set_meta("frozen", 0.0)
	s.set_meta("flash", 0.0)
	s.set_meta("boss", boss)
	s.set_meta("flying", flying)
	s.set_meta("name", name)
	s.set_meta("radius", 26.0 + 22.0 * radius_tiles)
	s.set_meta("t", rng.randf())
	s.set_meta("dtype", String(ability.get("dtype", "Physical")))
	var holder := Node3D.new()
	holder.add_child(s)
	var sh := MeshInstance3D.new()
	sh.mesh = shadow_mesh
	sh.position = Vector3(0, 0.5 * Track.U, 0)
	holder.add_child(sh)
	holder.position = to3(pos)
	add_child(holder)
	s.set_meta("holder", holder)
	if boss or radius_tiles > 0:
		var lbl := Label3D.new()
		lbl.text = name.to_upper()
		lbl.font = QUD.font()
		lbl.font_size = 36
		lbl.pixel_size = Track.U * 0.3
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = Color(1.0, 0.6, 0.2)
		lbl.outline_size = 8
		lbl.position = Vector3(0, (int(QUD.unit_info(unit).get("frame_size", 60)) + 20) * Track.U, 0)
		holder.add_child(lbl)
	mobs.append(s)
	return s


func _build_units() -> void:
	var hp_scale := float(cfg("mob_hp_scale", 1.0))
	for u in level["units"]:
		var asset: Array = u.get("asset", [])
		var pos := tile_center(int(u["x"]), int(u["y"]))
		if bool(u.get("is_lair", false)):
			_place_spawner(u, pos)
			continue
		var unit := String(asset[asset.size() - 1]) if asset.size() > 0 else "goblin"
		_place_mob(String(u["name"]), unit, pos, maxf(3.0, float(u.get("hp", 10)) * hp_scale), bool(u.get("flying", false)),
			u.get("spells", []), bool(u.get("is_boss", false)), int(u.get("radius", 0)))


func _place_spawner(u: Dictionary, pos: Vector2) -> void:
	var asset: Array = u.get("asset", [])
	var monster_unit := String(asset[asset.size() - 1]) if asset.size() > 0 else "goblin"
	var holder := Node3D.new()
	var base := _sprite("lair", 1.0)
	holder.add_child(base)
	var top := _sprite(monster_unit, 0.7)
	top.position.y += 10.0 * Track.U
	holder.add_child(top)
	holder.position = to3(pos)
	add_child(holder)
	var lbl := Label3D.new()
	lbl.text = String(u["name"]).to_upper()
	lbl.font = QUD.font()
	lbl.font_size = 30
	lbl.pixel_size = Track.U * 0.3
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.9, 0.35, 0.35)
	lbl.outline_size = 8
	lbl.position = Vector3(0, 80.0 * Track.U, 0)
	holder.add_child(lbl)
	var spawned: Dictionary = u.get("spawns", {})
	var mname := String(spawned.get("name", String(u["name"]).replace(" Spawner", "")))
	var mhp := float(spawned.get("hp", _hp_for(mname, 8.0)))
	spawners.append({"holder": holder, "pos": pos, "hp": float(cfg("spawner_hp", 40.0)), "max_hp": float(cfg("spawner_hp", 40.0)),
		"unit": monster_unit, "mname": mname, "mhp": mhp, "mflying": bool(spawned.get("flying", false)),
		"mspells": spawned.get("spells", _spells_for(mname)), "cd": rng.randf_range(2.0, 5.0), "label": lbl, "base": base, "top": top,
		"flash": 0.0, "name": String(u["name"])})


func _hp_for(mname: String, default: float) -> float:
	for m in QUD.monsters:
		if m.get("name", "") == mname:
			return float(m.get("max_hp", default))
	return default


func _spells_for(mname: String) -> Array:
	for m in QUD.monsters:
		if m.get("name", "") == mname:
			return m.get("spells", [])
	return []


func _build_props() -> void:
	for p in level["props"]:
		var asset: Array = p.get("asset", [])
		var pos := tile_center(int(p["x"]), int(p["y"]))
		var kind := String(p.get("type", ""))
		if kind == "Portal":
			var s := Sprite3D.new()
			s.texture = QUD.texture("tiles/portal_dormant_portal.png")
			s.pixel_size = Track.U
			s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.position = to3(pos, 30.0)
			s.set_meta("pos", pos)
			s.set_meta("open", false)
			add_child(s)
			portals.append(s)
		else:
			var tex := QUD.texture("tiles/item_%s.png" % (String(asset[asset.size() - 1]) if asset.size() > 0 else "mana_orb"))
			if tex == null:
				tex = QUD.texture("tiles/item_mana_orb.png")
			var s := Sprite3D.new()
			s.texture = tex
			s.pixel_size = Track.U * 0.9
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.position = to3(pos, 26.0)
			s.set_meta("pos", pos)
			s.set_meta("kind", "sp" if kind == "MemoryOrb" else ("artifact" if kind == "ComponentPickup" else "heart"))
			add_child(s)
			pickups.append(s)


func _drop_heart(pos: Vector2) -> void:
	var s := Sprite3D.new()
	s.texture = QUD.texture("tiles/item_ruby_heart.png")
	s.pixel_size = Track.U * 0.8
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.position = to3(pos, 24.0)
	s.set_meta("pos", pos)
	s.set_meta("kind", "heart")
	add_child(s)
	pickups.append(s)


func _build_hero() -> void:
	player = Node3D.new()
	add_child(player)
	var sh := MeshInstance3D.new()
	sh.mesh = shadow_mesh
	sh.position = Vector3(0, 0.5 * Track.U, 0)
	player.add_child(sh)
	hero_sprite = _sprite(Campaign.skin if QUD.has_unit(Campaign.skin) else "player")
	player.add_child(hero_sprite)
	var st: Array = level.get("start", [1, 1])
	hero_pos = tile_center(int(st[0]), int(st[1]))
	player.position = to3(hero_pos)
	for f in Campaign.spells:
		if String(f["effect"]["kind"]) == "summon":
			_add_familiar(f)


func _add_familiar(entry: Dictionary) -> void:
	var s := _sprite(String(entry.get("unit", "wolf")), 0.8)
	var holder := Node3D.new()
	holder.add_child(s)
	add_child(holder)
	familiars.append({"holder": holder, "sprite": s, "angle": rng.randf() * TAU, "entry": entry, "tick": 0.0})


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = float(cfg("cam_fov", 55.0))
	cam.near = 0.3
	cam.far = 800.0
	add_child(cam)
	cam.current = true
	_update_camera()


func _update_camera() -> void:
	var back := float(cfg("cam_back", 360.0)) * Track.U
	var height := float(cfg("cam_height", 640.0)) * Track.U
	if cam == null or not cam.is_inside_tree():
		return
	var target := to3(hero_pos)
	cam.position = target + Vector3(0, height, back)
	cam.look_at(target + Vector3(0, 10 * Track.U, 0), Vector3.UP)


func _label(size_px: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size_px)
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
	lbl_stats = _label(20)
	lbl_stats.position = Vector2(28, 56)
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
		slot_icons.append(icon)
		var cdr := ColorRect.new()
		cdr.color = Color(0, 0, 0, 0.65)
		cdr.position = bg.position + Vector2(4, 4)
		cdr.size = Vector2(60, 0)
		hud.add_child(cdr)
		slot_cd.append(cdr)
		var key := _label(16, Color(0.8, 0.8, 0.8))
		key.text = str((i + 1) % 10)
		key.position = bg.position + Vector2(6, 62)
		slot_keys.append(key)
	map = Control.new()
	map.position = Vector2(1920 - 28 - 234, 1080 - 28 - 234)
	map.size = Vector2(234, 234)
	map.draw.connect(_draw_map)
	hud.add_child(map)
	results = _label(30)
	results.position = Vector2(520, 300)
	results.visible = false


func _draw_map() -> void:
	var cell := map.size.x / size
	map.draw_rect(Rect2(Vector2.ZERO, map.size), Color(0, 0, 0, 0.7))
	for y in size:
		for x in size:
			var c: String = grid[y][x]
			var col := Color(0.55, 0.52, 0.5) if c == "#" else (Color(0.12, 0.2, 0.35) if c == "~" else Color(0.22, 0.2, 0.24))
			map.draw_rect(Rect2(Vector2(x * cell, y * cell), Vector2(cell, cell)), col)
	for sp in spawners:
		var p: Vector2 = sp["pos"] / TILE * cell
		map.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color(0.9, 0.3, 0.3))
	for m in mobs:
		var p: Vector2 = m.get_meta("pos") / TILE * cell
		map.draw_circle(p, 2.5, Color(0.9, 0.11, 0.14))
	for pt in portals:
		var p: Vector2 = pt.get_meta("pos") / TILE * cell
		map.draw_circle(p, 4.0, Color(0.6, 0.9, 1.0) if bool(pt.get_meta("open")) else Color(0.4, 0.4, 0.6))
	for pk in pickups:
		var p: Vector2 = pk.get_meta("pos") / TILE * cell
		map.draw_circle(p, 2.0, Color(0.47, 0.78, 1.0))
	var hp2: Vector2 = hero_pos / TILE * cell
	map.draw_circle(hp2, 4.0, Color.WHITE)
	map.draw_rect(Rect2(Vector2.ZERO, map.size), Color(0.9, 0.86, 0.78), false, 2.0)


# ---------------------------------------------------------------- spells

func _cd_for(spell_entry: Dictionary) -> float:
	var charges := 12.0 if bool(spell_entry.get("unlimited", false)) or int(spell_entry.get("max_charges", 3)) <= 0 else maxf(1.0, float(spell_entry.get("max_charges", 3)))
	return clampf(9.0 / charges + 0.6, 0.8, 8.0) * (1.0 - 0.05 * Campaign.bonus("charges"))


func _sync_cooldowns() -> void:
	while cooldowns.size() < Campaign.spells.size():
		cooldowns.append(0.0)
	var have := []
	for f in familiars:
		have.append(f["entry"])
	for s in Campaign.spells:
		if String(s["effect"]["kind"]) == "summon" and not (s in have):
			_add_familiar(s)


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


func _nearest_spawner(from: Vector2, range_px: float) -> Dictionary:
	var best := {}
	var best_d := range_px
	for sp in spawners:
		var d: float = from.distance_to(sp["pos"])
		if d < best_d:
			best_d = d
			best = sp
	return best


func _cast(i: int) -> bool:
	var entry: Dictionary = Campaign.spells[i]
	var e: Dictionary = entry["effect"]
	var kind := String(e["kind"])
	var dtype := String(e.get("dtype", "Arcane"))
	var dmg := float(e.get("damage", 5.0)) + Campaign.bonus("spell_damage")
	var dur := float(e.get("duration", 4.0)) + Campaign.bonus("spell_duration")
	var rng_px := maxf(400.0, float(e.get("range", 400.0)) + Campaign.bonus("spell_range"))
	var cost := int(entry.get("hp_cost", 0))
	if cost > 0 and Campaign.hp <= cost:
		return false
	match kind:
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
				for sp in spawners.duplicate():
					var rel: Vector2 = Vector2(sp["pos"]) - hero_pos
					if rel.length() <= reach + 30.0 and rel.dot(hero_dir) > 0.0:
						_hit_spawner(sp, dmg, dtype)
						_effect_at(QUD.effect("physical"), hero_pos + hero_dir * 40.0, 6, 1.6)
						return true
			if hits.is_empty():
				return false
			for m in hits.slice(0, int(e.get("targets", 1))):
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
			for sp in spawners.duplicate():
				if hero_pos.distance_to(sp["pos"]) <= radius + 30.0 and dmg > 0.0:
					_hit_spawner(sp, dmg, dtype)
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
			h.position = to3(h.pos, 3.0)
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
		"bolt", "blast":
			var targets := _nearest_mobs(hero_pos, rng_px, maxi(1, int(e.get("count", 1))))
			var sp := _nearest_spawner(hero_pos, rng_px)
			var to := Vector2.ZERO
			var homing = null
			if targets.size() > 0 and (sp.is_empty() or hero_pos.distance_to(targets[0].get_meta("pos")) <= hero_pos.distance_to(sp["pos"])):
				to = targets[0].get_meta("pos")
				homing = targets[0]
			elif not sp.is_empty():
				to = sp["pos"]
			else:
				to = hero_pos + hero_dir * rng_px
			var radius := (float(e.get("radius", 60.0)) + Campaign.bonus("spell_radius")) * 1.3 if kind == "blast" else 0.0
			_arm_bolt(_fire_bolt(hero_pos, to, dmg, dtype, radius, homing, QUD.texture("effects/proj/fire_ball.png") if kind == "blast" else null), e)
			for extra in range(1, targets.size()):   # multi-shot: one bolt per extra target
				_arm_bolt(_fire_bolt(hero_pos, targets[extra].get_meta("pos"), dmg, dtype, radius, targets[extra], QUD.texture("effects/proj/fire_ball.png") if kind == "blast" else null), e)
		"beam":
			var n := int(e.get("targets", 1)) + int(Campaign.bonus("beam_targets"))
			var targets := _nearest_mobs(hero_pos, rng_px, n + 1)
			var sp := _nearest_spawner(hero_pos, rng_px)
			if targets.is_empty() and sp.is_empty():
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
			if not sp.is_empty() and targets.size() < n + 1:
				_line(from, sp["pos"], Items.type_color(dtype))
				_hit_spawner(sp, dmg, dtype)
		"summon":
			return false
		"shield":
			Campaign_shield(int(e.get("shields", 1)))
			_effect_at(QUD.effect("shield_apply"), hero_pos, 6)
		"heal":
			Campaign.heal(float(e.get("amount", 10.0)))
			_effect_at(QUD.effect("heal"), hero_pos, 6)
		"buff":
			hero_speed_boost = maxf(hero_speed_boost, float(e.get("duration", 4.0)) + Campaign.bonus("spell_duration"))
			_effect_at(QUD.effect("buff_apply"), hero_pos, 6)
		"blink":
			var dest := hero_pos + hero_dir * (float(e.get("distance", 340.0)) + Campaign.bonus("blink"))
			_effect_at(QUD.effect("translocation"), hero_pos, 6)
			for k in 8:
				if can_stand(dest, 22.0, false):
					hero_pos = dest
					break
				dest = hero_pos + (dest - hero_pos) * 0.8
			_effect_at(QUD.effect("translocation"), hero_pos, 6)
			Audio.play("teleport")
		"hex":
			var targets := _nearest_mobs(hero_pos, rng_px, 6)
			if targets.is_empty():
				return false
			for m in targets:
				m.set_meta("frozen", maxf(float(m.get_meta("frozen")), float(e.get("duration", 3.0)) + Campaign.bonus("spell_duration")))
				var fx := _effect_at(QUD.effect("ice"), m.get_meta("pos"), 6)
				fx.follow = m.get_meta("holder")
		_:
			return false
	if cost > 0:
		Campaign.hp = maxf(1.0, Campaign.hp - cost)
		_effect_at(QUD.effect("blood"), hero_pos, 6, 1.2)
	Audio.play("sorcery", -4.0)
	return true


func _arm_bolt(p: Items.Projectile, e: Dictionary) -> void:
	p.heal_frac = float(e.get("heal_frac", 0.0))
	if e.has("stun"):
		p.set_meta("stun", float(e["stun"]))


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
		Campaign.heal(dmg * hf)


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
			Campaign.heal(float(a["heal"]))
		var n := int(a["targets"])
		for m in _nearest_mobs(hero_pos, float(a["radius"]), n if n > 0 else 200):
			if float(a["damage"]) > 0.0:
				_hit_mob(m, float(a["damage"]), String(a["dtype"]))
				if float(a["heal_frac"]) > 0.0:
					Campaign.heal(float(a["damage"]) * float(a["heal_frac"]))
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


var shields := 0
var hero_speed_boost := 0.0


func Campaign_shield(n: int) -> void:
	shields = maxi(shields, n)


func _fire_bolt(from: Vector2, to: Vector2, dmg: float, dtype: String, radius: float, homing, tex: Texture2D = null) -> Items.Projectile:
	var p := Items.Projectile.new()
	p.texture = tex if tex != null else QUD.texture("effects/proj/arcane_bolt.png")
	p.pixel_size = Track.U * 0.8
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	p.modulate = Items.type_color(dtype).lerp(Color.WHITE, 0.5)
	p.pos = from
	p.vel = (to - from).normalized() * 1000.0
	p.damage = dmg
	p.radius = radius
	p.dtype = dtype
	p.life = 2.0
	p.set_meta("target", homing)
	p.set_meta("from_hero", true)
	add_child(p)
	bolts.append(p)
	return p


func _effect_at(tex: Texture2D, at: Vector2, frames: int, size_k := 1.4) -> Items.Effect:
	var e := Items.Effect.make(tex, to3(at, 30.0), frames, 0.07, -1.0, size_k)
	add_child(e)
	effects.append(e)
	return e


func _line(a: Vector2, b: Vector2, color: Color) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(to3(a) + Vector3(0, 1.5, 0))
	im.surface_add_vertex(to3(b) + Vector3(0, 1.5, 0))
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
	Audio.play("hit_enemy", -8.0)
	if h <= 0.0:
		_kill_mob(m)


func _kill_mob(m: Sprite3D) -> void:
	kills += 1
	Campaign.kills += 1
	var pos: Vector2 = m.get_meta("pos")
	if bool(m.get_meta("boss")):
		Campaign.sp += 3
		_drop_heart(pos)
		say("%s SLAIN  +3 SP" % String(m.get_meta("name")).to_upper(), 2.0)
		Audio.play("death_boss")
	else:
		if rng.randf() < float(cfg("heart_chance", 0.06)):
			_drop_heart(pos)
		Audio.play("death_enemy", -6.0)
	if Campaign.bonus("kill_heal") > 0.0:
		Campaign.heal(Campaign.bonus("kill_heal"))
	var holder: Node3D = m.get_meta("holder")
	mobs.erase(m)
	holder.queue_free()
	_check_clear()


func _hit_spawner(sp: Dictionary, dmg: float, dtype: String) -> void:
	sp["hp"] = float(sp["hp"]) - dmg
	sp["flash"] = 0.2
	_effect_at(Items.effect_strip(dtype), sp["pos"], 6, 1.4)
	Audio.play("hit_enemy", -6.0)
	if float(sp["hp"]) <= 0.0:
		var holder: Node3D = sp["holder"]
		spawners.erase(sp)
		holder.queue_free()
		Campaign.sp += int(cfg("spawner_sp", 2))
		kills += 1
		say("%s DESTROYED  +%d SP" % [String(sp["name"]).to_upper(), int(cfg("spawner_sp", 2))], 1.8)
		Audio.play("death_boss")
		_effect_at(QUD.effect("dark"), sp["pos"], 6, 2.2)
		_check_clear()


func _hurt(amount: float, dtype: String) -> void:
	if invuln > 0.0 or state != PLAYING:
		return
	if shields > 0:
		shields -= 1
		_effect_at(QUD.effect("shield_expire"), hero_pos, 6)
		Audio.play("shield_break")
		invuln = 0.3
		return
	invuln = float(cfg("hurt_invuln", 0.5))
	_effect_at(Items.effect_strip(dtype), hero_pos, 6, 1.4)
	Audio.play("hit_player")
	hero_sprite.modulate = Color(1.0, 0.45, 0.45)
	if Campaign.take_damage(amount):
		_die()


func _die() -> void:
	state = DEAD
	Audio.play("death_player")
	Audio.music("lose_theme")
	results.text = "THE WIZARD IS DEAD\n\nRealm %d, %d monsters slain this run\n\nenter for a new run    esc for the menu" % [Campaign.level, Campaign.kills]
	results.visible = true


func _check_clear() -> void:
	if state != PLAYING or not mobs.is_empty() or not spawners.is_empty():
		return
	state = CLEARED
	for pt in portals:
		pt.set_meta("open", true)
		pt.texture = QUD.texture("tiles/portal_active_portal.png")
	say("REALM CLEARED: ENTER A RIFT", 3.0)
	Audio.play("victory_level")


func _next_realm() -> void:
	Campaign.level += 1
	Campaign.sp += int(Shared.t(["campaign", "gate_sp"], 2))
	Campaign.seed = Campaign.run_rng.randi()
	Campaign.refill_all()
	state = "leaving"
	if Campaign.level > 21:
		state = WON
		Audio.music("victory_theme")
		results.text = "ALL TWENTY-ONE REALMS CLEARED\n\n%d monsters slain\n\nenter for a new run    esc for the menu" % Campaign.kills
		results.visible = true
		return
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- simulation

func say(text: String, duration := 1.5) -> void:
	message = text
	message_t = duration


func _physics_process(dt: float) -> void:
	if paused or state in [DEAD, WON]:
		return
	t += dt
	message_t = maxf(0.0, message_t - dt)
	invuln = maxf(0.0, invuln - dt)
	hero_speed_boost = maxf(0.0, hero_speed_boost - dt)
	flow_t -= dt
	if flow_t <= 0.0:
		flow_t = 0.25
		_update_flow()
	_move_hero(dt)
	_hero_casts(dt)
	_update_auras(dt)
	_update_hazards(dt)
	Campaign.tick_cooldowns(dt)
	_update_familiars(dt)
	_update_spawners(dt)
	_update_mobs(dt)
	_update_bolts(dt)
	_update_pickups()
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
		var threats := _nearest_mobs(hero_pos, 260.0, 8)
		for m in threats:
			var rel: Vector2 = hero_pos - m.get_meta("pos")
			dir += rel.normalized()
		var goal := Vector2.ZERO
		if state == CLEARED and portals.size() > 0:
			goal = portals[0].get_meta("pos")
		elif not spawners.is_empty():
			goal = spawners[0]["pos"]
		elif not mobs.is_empty():
			goal = mobs[0].get_meta("pos")
		if goal != Vector2.ZERO:
			var f := _flow_toward(goal)
			dir += f * 0.9
		if dir.length_squared() < 0.01:
			dir = Vector2(cos(t * 0.7), sin(t * 0.7))
	else:
		dir = Vector2(Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left"),
					  Input.get_action_strength("drive_back") - Input.get_action_strength("drive_forward"))
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	if dir.length_squared() > 0.01:
		hero_dir = dir.normalized()
		var speed := hero_speed * (1.0 + Campaign.bonus("speed")) * (1.35 if hero_speed_boost > 0.0 else 1.0)
		hero_pos = try_move(hero_pos, dir * speed * dt, 22.0, false)
	player.position = to3(hero_pos)
	hero_sprite.frame = int(t / 0.2) % maxi(1, hero_sprite.hframes)
	hero_sprite.flip_h = hero_dir.x < 0.0
	hero_sprite.modulate = hero_sprite.modulate.lerp(Color(0.7, 1.0, 1.0) if shields > 0 else Color.WHITE, minf(1.0, 6.0 * dt))


# direction of the first step of a path from the hero to a goal tile (BFS from goal)
func _flow_toward(goal: Vector2) -> Vector2:
	var saved_pos := hero_pos
	hero_pos = goal
	_update_flow()
	hero_pos = saved_pos
	var d := flow_dir(hero_pos, false)
	_update_flow()
	return d


func _hero_casts(dt: float) -> void:
	_sync_cooldowns()
	for i in Campaign.spells.size():
		cooldowns[i] = maxf(0.0, float(cooldowns[i]) - dt)
	if auto_player:
		for i in Campaign.spells.size():
			if float(cooldowns[i]) <= 0.0 and _cast(i):
				cooldowns[i] = _cd_for(Campaign.spells[i])
				break
		return
	for i in Campaign.spells.size():
		if Input.is_action_just_pressed("slot_%d" % (i + 1)) and float(cooldowns[i]) <= 0.0:
			if _cast(i):
				cooldowns[i] = _cd_for(Campaign.spells[i])
			else:
				Audio.play("menu_abort", -6.0)


func _update_familiars(dt: float) -> void:
	for f in familiars:
		f["angle"] += dt * 2.6
		var p := hero_pos + Vector2(cos(f["angle"]), sin(f["angle"])) * 120.0
		var holder: Node3D = f["holder"]
		holder.position = to3(p)
		var s: Sprite3D = f["sprite"]
		s.frame = int(t / 0.2) % maxi(1, s.hframes)
		f["tick"] -= dt
		if f["tick"] <= 0.0:
			f["tick"] = 0.45
			var e: Dictionary = f["entry"]["effect"]
			var dmg := float(e.get("damage", 3.0)) + Campaign.bonus("summon_damage")
			for m in _nearest_mobs(p, 60.0, 3):
				_hit_mob(m, dmg, String(e.get("dtype", "Physical")))
			var sp := _nearest_spawner(p, 70.0)
			if not sp.is_empty():
				_hit_spawner(sp, dmg, String(e.get("dtype", "Physical")))


func _update_spawners(dt: float) -> void:
	var cap := int(cfg("spawner_cap", 5))
	for sp in spawners:
		sp["flash"] = maxf(0.0, float(sp["flash"]) - dt)
		var top: Sprite3D = sp["top"]
		top.modulate = Color(1.0, 0.5, 0.5) if float(sp["flash"]) > 0.0 else Color.WHITE
		top.frame = int(t / 0.25) % maxi(1, top.hframes)
		var lbl: Label3D = sp["label"]
		lbl.text = "%s  %d" % [String(sp["name"]).to_upper(), int(ceil(float(sp["hp"])))]
		sp["cd"] = float(sp["cd"]) - dt
		if float(sp["cd"]) <= 0.0:
			var mine := 0
			for m in mobs:
				if m.get_meta("holder").has_meta("from") and m.get_meta("holder").get_meta("from") == sp["name"]:
					mine += 1
			if mine < cap and mobs.size() < int(cfg("max_mobs", 80)):
				var c := tile_at(sp["pos"])
				var spots := []
				for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = c.x + off.x
					var ny: int = c.y + off.y
					if nx >= 0 and ny >= 0 and nx < size and ny < size and walk[ny][nx]:
						spots.append(tile_center(nx, ny))
				if spots.size() > 0:
					var m := _place_mob(String(sp["mname"]), String(sp["unit"]), spots[rng.randi_range(0, spots.size() - 1)],
						maxf(3.0, float(sp["mhp"]) * float(cfg("mob_hp_scale", 1.0))), bool(sp["mflying"]), sp["mspells"])
					m.get_meta("holder").set_meta("from", sp["name"])
					_effect_at(QUD.effect("dark"), sp["pos"], 6, 1.2)
					Audio.play("summon", -8.0)
			var cdr: Array = cfg("spawner_cooldown", [5.0, 8.0])
			sp["cd"] = rng.randf_range(float(cdr[0]), float(cdr[1]))


func _update_mobs(dt: float) -> void:
	var cd: Array = cfg("ability_cooldown", [3.0, 6.0])
	var dmg_scale := Kart.interp(cfg("damage_by_realm", [[1, 0.6], [10, 1.0], [21, 1.5]]), float(Campaign.level)) * float(cfg("contact_damage_scale", 0.6))
	for m in mobs.duplicate():
		var pos: Vector2 = m.get_meta("pos")
		var frozen := float(m.get_meta("frozen"))
		var to := hero_pos - pos
		var dist := to.length()
		var flying := bool(m.get_meta("flying"))
		if frozen > 0.0:
			m.set_meta("frozen", frozen - dt)
			m.modulate = Color(0.6, 0.85, 1.0)
		else:
			var speed := float(m.get_meta("speed"))
			var a: Dictionary = m.get_meta("ability")
			var want_dist := 0.0 if a["kind"] == "melee" else float(a["range"]) * 0.6
			if dist > want_dist + 10.0:
				var d := flow_dir(pos, flying)
				if dist < TILE * 1.2:
					d = to.normalized()
				pos = try_move(pos, d * speed * dt, 18.0, flying)
				m.set_meta("pos", pos)
			var fl := float(m.get_meta("flash"))
			m.modulate = Color(1.0, 0.5, 0.5) if fl > 0.0 else Color.WHITE
			m.set_meta("flash", maxf(0.0, fl - dt))
			var hit_cd := float(m.get_meta("hit_cd")) - dt
			var radius := float(m.get_meta("radius"))
			if dist < radius + 24.0 and hit_cd <= 0.0:
				_hurt(maxf(1.0, float(m.get_meta("damage")) * dmg_scale), String(m.get_meta("dtype")))
				hit_cd = 1.0
			m.set_meta("hit_cd", hit_cd)
			if a["kind"] == "ranged":
				var acd := float(m.get_meta("cd")) - dt
				if acd <= 0.0 and dist < float(a["range"]) + 100.0 and _line_clear(pos, hero_pos):
					acd = rng.randf_range(float(cd[0]), float(cd[1]))
					var p := Items.Projectile.new()
					p.texture = QUD.texture("effects/proj/arcane_bolt.png")
					p.pixel_size = Track.U * 0.7
					p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					p.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					p.modulate = Items.type_color(String(a["dtype"]))
					p.pos = pos
					p.vel = to.normalized() * 480.0
					p.damage = maxf(1.0, float(a["damage"]) * float(cfg("ranged_damage_scale", 0.5)) * dmg_scale / float(cfg("contact_damage_scale", 0.6)))
					p.dtype = String(a["dtype"])
					p.life = 3.0
					p.set_meta("from_hero", false)
					add_child(p)
					bolts.append(p)
					Audio.play("enemy", -10.0)
				m.set_meta("cd", acd)
		var holder: Node3D = m.get_meta("holder")
		holder.position = to3(pos)
		m.frame = int((t + float(m.get_meta("t"))) / 0.2) % maxi(1, m.hframes)
		m.flip_h = to.x < 0.0


func _line_clear(a: Vector2, b: Vector2) -> bool:
	var steps := int(a.distance_to(b) / (TILE * 0.5)) + 1
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / steps)
		var c := tile_at(p)
		if c.x < 0 or c.y < 0 or c.x >= size or c.y >= size or not passable[c.y][c.x]:
			return false
	return true


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
		p.position = to3(p.pos, 24.0)
		var alive: bool = p.life > 0.0
		if bool(p.get_meta("from_hero")):
			var hit: Sprite3D = null
			for m in mobs:
				if p.pos.distance_squared_to(m.get_meta("pos")) < pow(float(m.get_meta("radius")) + 14.0, 2):
					hit = m
					break
			var hit_sp := {}
			if hit == null:
				for sp in spawners:
					if p.pos.distance_squared_to(sp["pos"]) < 40.0 * 40.0:
						hit_sp = sp
						break
			if hit != null or not hit_sp.is_empty():
				if p.radius > 0.0:
					for m in _nearest_mobs(p.pos, p.radius, 30):
						_hit_mob(m, p.damage, p.dtype)
						if p.has_meta("stun"):
							_stun_mob(m, float(p.get_meta("stun")))
						if p.heal_frac > 0.0:
							Campaign.heal(p.damage * p.heal_frac)
					for sp in spawners.duplicate():
						if p.pos.distance_to(sp["pos"]) < p.radius + 30.0:
							_hit_spawner(sp, p.damage, p.dtype)
					_effect_at(Items.effect_strip(p.dtype), p.pos, 6, 2.2)
				elif hit != null:
					_hit_mob(hit, p.damage, p.dtype)
					if p.has_meta("stun"):
						_stun_mob(hit, float(p.get_meta("stun")))
					if p.heal_frac > 0.0:
						Campaign.heal(p.damage * p.heal_frac)
				else:
					_hit_spawner(hit_sp, p.damage, p.dtype)
				alive = false
		else:
			if p.pos.distance_squared_to(hero_pos) < 28.0 * 28.0:
				_hurt(p.damage, p.dtype)
				alive = false
		var c := tile_at(p.pos)
		if c.x < 0 or c.y < 0 or c.x >= size or c.y >= size or not passable[c.y][c.x]:
			alive = false
		if not alive:
			bolts.erase(p)
			p.queue_free()


func _update_pickups() -> void:
	for pk in pickups.duplicate():
		if hero_pos.distance_to(pk.get_meta("pos")) > 40.0:
			continue
		var kind := String(pk.get_meta("kind"))
		if kind == "sp":
			Campaign.sp += 1
			say("MEMORY ORB: +1 SP", 0.9)
		elif kind == "heart":
			Campaign.heal(float(cfg("heart_heal", 15.0)))
			say("+%d HP" % int(cfg("heart_heal", 15.0)), 0.8)
		elif kind == "artifact":
			var art := Campaign.grant_random_artifact()
			if art.is_empty():
				Campaign.sp += 2
				say("+2 SP", 0.8)
			else:
				say("ARTIFACT: %s" % String(art["name"]).to_upper(), 2.0)
		Audio.play("item_pickup")
		pickups.erase(pk)
		pk.queue_free()
	if state == CLEARED:
		for pt in portals:
			if hero_pos.distance_to(pt.get_meta("pos")) < 45.0:
				Audio.play("teleport")
				_next_realm()
				return


# ---------------------------------------------------------------- shop / hud

func _open_shop() -> void:
	if shop != null:
		return
	paused = true
	hud.visible = false
	shop = Shop.new()
	shop.race = self
	add_child(shop)
	shop.closed.connect(_close_shop)
	shop.quit_requested.connect(func(): get_tree().change_scene_to_file("res://Menu.tscn"))


func _close_shop() -> void:
	if shop == null:
		return
	shop.queue_free()
	shop = null
	paused = false
	hud.visible = true
	_sync_cooldowns()


func play(name: String, volume_db := 0.0) -> void:
	Audio.play(name, volume_db)


func _process(_delta: float) -> void:
	if shop == null and Input.is_action_just_pressed("pause"):
		if state in [DEAD, WON]:
			get_tree().change_scene_to_file("res://Menu.tscn")
		else:
			_open_shop()
	if state in [DEAD, WON] and Input.is_action_just_pressed("confirm"):
		Campaign.new_run()
		get_tree().reload_current_scene()
		return
	if level.is_empty():
		return
	lbl_top.text = "REALM %d / 21   %s %s     monsters %d   spawners %d   kills %d" % [
		Campaign.level, String(level["tileset"]).capitalize(), String(level["chasm"]), mobs.size(), spawners.size(), kills]
	hp_fill.size = Vector2(360.0 * clampf(Campaign.hp / maxf(1.0, Campaign.max_hp), 0.0, 1.0), 26)
	lbl_stats.text = "HP %d / %d%s     SP %d     artifacts %d" % [int(Campaign.hp), int(Campaign.max_hp),
		"   shield x%d" % shields if shields > 0 else "", Campaign.sp, Campaign.artifacts.size()]
	for i in 10:
		if i < Campaign.spells.size():
			var s: Dictionary = Campaign.spells[i]
			slot_icons[i].texture = QUD.icon(String(s["icon"]))
			var cdv := float(cooldowns[i]) if i < cooldowns.size() else 0.0
			var frac := clampf(cdv / maxf(0.1, _cd_for(s)), 0.0, 1.0)
			slot_cd[i].size = Vector2(60, 60.0 * frac)
			slot_icons[i].modulate = Color.WHITE if cdv <= 0.0 else Color(0.75, 0.75, 0.75)
		else:
			slot_icons[i].texture = null
			slot_cd[i].size = Vector2(60, 0)
	lbl_center.text = message if message_t > 0.0 else ""
	map.queue_redraw()

	frame_count += 1
	if screen_arg == "shop" and frame_count == 30:
		_open_shop()
	if frames_left >= 0 and Time.get_ticks_msec() - Campaign.debug_t0_ms >= frames_left * 1000 / 60:
		frames_left = -1
		_finish_screenshot()


func _finish_screenshot() -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if screenshot_path != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png(screenshot_path)
		print("saved ", screenshot_path)
	print("gauntlet: state=%s realm=%d t=%.0f hp=%d sp=%d spells=%d mobs=%d spawners=%d kills=%d fps=%d" % [
		state, Campaign.level, t, int(Campaign.hp), Campaign.sp, Campaign.spells.size(), mobs.size(), spawners.size(), kills, Engine.get_frames_per_second()])
	get_tree().quit()
