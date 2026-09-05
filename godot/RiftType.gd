# Rift-Type: a side-scrolling shooter built from the game's realms. The realm's own
# map scrolls past sideways (its walls are the corridor, its chasms the backdrop, its
# props the scenery), its monsters fly in as formations picked from what they are
# (flyers weave, stationary things become turrets, lairs become hives, big things
# crawl across as walls), their spells are the bullets, and the realm's boss waits at
# the end. Kills give XP; every level offers one of three R-Type flavoured upgrades.
#
# Flags after "--": --mode=rifttype --realm=N --seed=N --auto --mute --timescale=X
#   --frames=N --screenshot=path   --seconds=N   --skin=unit
class_name RiftType
extends Node2D

const SW := 1920.0              # the screen (HUD coordinates)
const SH := 1080.0
const ZOOM := 1.5               # world pixels are drawn this much bigger
const W := SW / ZOOM            # the visible world: 1280 x 720
const H := SH / ZOOM
const TILE := 60.0
const ROWS := 12                # the band of the realm grid that becomes the corridor
const ROW0 := 3
const PLAYING := "playing"
const LEVELUP := "levelup"
const DEAD := "dead"
const CLEARED := "cleared"
const TAVERN := "tavern"
const ARTIFACT := "artifact"
const INTERMISSION := "intermission"
const PAUSED := "paused"
const FEEDBACK := "feedback"
const MAX_PARTY := 3
const PARTY_SLOTS := [Vector2(-70, -64), Vector2(-70, 64), Vector2(-130, 0)]

var T := {}
var rng := RandomNumberGenerator.new()
var realm := 1
var seg_grids: Array = []       # the realm's dumps (and their mirrors) laid end to end
var level_len := 0.0            # px of scrolling before the boss arena
var scroll_x := 0.0
var scroll_speed := 130.0
var t := 0.0
var state := PLAYING
var auto := false
var seconds_limit := -1.0
var frames_left := -1
var frame_count := 0
var screenshot_path := ""
var screen_arg := ""            # --screen=levelup: hold an upgrade offer open for the screenshot

var world: Node2D
var bg: ColorRect
var cells_layer: Node2D
var ents: Node2D
var cam: Camera2D
var built_cols: Dictionary = {}    # column index -> [nodes]
var solid: Dictionary = {}         # "c,r" -> true
var props_placed: Dictionary = {}

var player: Node2D
var p_sprite: Sprite2D
var p_pos := Vector2(300, H * 0.5)
var p_hp := 30.0
var p_max_hp := 30.0
var p_speed := 420.0
var invuln := 0.0
var fire_cd := 0.0
var charge := 0.0
var charging := false
var shields := 0
var charge_ring: Node2D

var enemies: Array = []
var shots: Array = []
var bullets: Array = []
var beams: Array = []
var orbs: Array = []
var familiars: Array = []
var fx: Array = []

var species: Array = []            # the realm's monsters as {name, unit, hp, flying, stationary, lair, big, spells}
var small_species: Array = []
var waves: Array = []
var wave_i := 0
var boss: Dictionary = {}
var boss_phase := 0
var boss_t := 0.0
var boss_spawned := false
var cleared_t := 0.0

var xp := 0.0
var level_n := 1
var score := 0
var kills := 0
var ups := {}                       # upgrade name -> times taken
var offer: Array = []

var hud: CanvasLayer
var lbl_top: Label
var lbl_realm: Label
var lbl_msg: Label
var lbl_center: Label
var hp_fill: ColorRect
var xp_fill: ColorRect
var boss_bar: ColorRect
var boss_fill: ColorRect
var lbl_boss: Label
var cards: Control = null
var message := ""
var message_t := 0.0
var shots_fired := 0
var p_spells: Array = []            # the game's spells on the number keys: {name, owned, cd, left, level}
var casts := 0
var buff_left := 0.0
var buff_mult := 1.0
var auras: Array = []               # player auras: {left, tick, dmg, radius, dtype}
var force: Dictionary = {}          # the Force pod
var clouds: Array = []              # boss clouds
var spell_row: HBoxContainer
var run_start_realm := 1
var species_cache: Dictionary = {}   # unit -> species built from monsters.json
var summon_cache: Dictionary = {}    # "caster|spell" -> species it summons
var abilities: Dictionary = {}       # what monsters cast this run, by mode (for the report)
var summons := 0
var companions: Array = []           # the game's tavern adventurers (companions.json)
var taverns: Array = []
var party: Array = []                # recruited companions flying with you
var tavern_offer: Array = []
var party_row: HBoxContainer
var party_casts := 0
var p_artifacts: Array = []          # Artifacts.make_owned dicts from chests
var chests: Array = []
var rifts: Array = []
var chosen_dump := 0
var intermission_t := 0.0
var intermission_kind := ""
var artifact_t := 0.0
var boss_dead_flag := false
var slain_names: Dictionary = {}     # monster name -> slain this realm
var artifact_row: HBoxContainer
var rift_goal := Vector2.ZERO
var rift_signs: Array = []
var undead: Array = []               # skeletons the Necromancer raised: {node, sprite, pos, hp, dmg, left, bite}
var raised := 0
var passive_log: Dictionary = {}     # passive name -> times it fired (for the report)
var recruit_arg := ""
var last_caster: Dictionary = {}     # the enemy whose cast is spawning bullets right now
var pause_overlay: Control = null
var feedback: FeedbackPanel = null
var state_before_pause := ""
var rift_goal_set := false
var score_at_start := 0
var death_t := -1.0
var damage_log := {}

const UPGRADES := [
	{"name": "Twin Bolt", "blurb": "one more bolt, side by side", "max": 3, "icon": "multicast"},
	{"name": "Spread", "blurb": "bolts fan out above and below", "max": 3, "icon": "fan_of_flames"},
	{"name": "Arcane Edge", "blurb": "+35% bolt damage", "max": 5, "icon": "mystic_power"},
	{"name": "Rapid Fire", "blurb": "-20% time between bolts", "max": 4, "icon": "cantrip_cascade"},
	{"name": "Familiar", "blurb": "a summoned beast orbits you and bites at what comes near", "max": 3, "icon": "wolf"},
	{"name": "Force Shield", "blurb": "+2 shield charges, each eats one hit", "max": 5, "icon": "arcane_warding"},
	{"name": "Wave Cannon", "blurb": "the charged beam grows wider and hits harder", "max": 3, "icon": "prismatic_beam"},
	{"name": "Vitality", "blurb": "+10 max HP and a full heal", "max": 5, "icon": "regeneration_aura"},
	{"name": "Swift", "blurb": "+15% movement", "max": 3, "icon": "blink"},
	{"name": "Seeking Bolts", "blurb": "bolts bend toward the nearest monster", "max": 1, "icon": "magic_missile"},
	{"name": "Piercing", "blurb": "bolts pass through what they kill", "max": 1, "icon": "void_beam"},
	{"name": "Rear Guard", "blurb": "a bolt fires backward too", "max": 1, "icon": "bone_spear"},
	{"name": "Force Pod", "blurb": "an eye rides your front and shoots with you; F or Q sends it ahead to eat bullets and ram, and calls it back", "max": 3, "icon": "floating_eye"},
]


func cfg(key: String, default):
	return T.get(key, default)


var _args_cache: Dictionary = {}


func cfg_arg(key: String, default):
	if _args_cache.is_empty():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--"):
				var kv := a.substr(2).split("=")
				_args_cache[kv[0]] = kv[1] if kv.size() > 1 else true
	return _args_cache.get(key, default)


func _ready() -> void:
	T = Shared.tuning.get("rifttype", {})
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=")
			args[kv[0]] = kv[1] if kv.size() > 1 else true
	realm = int(args.get("realm", Campaign.level if Campaign.active else 1))
	if args.has("seed"):
		rng.seed = int(args["seed"])
	else:
		rng.randomize()
	auto = args.has("auto")
	seconds_limit = float(args.get("seconds", -1.0))
	frames_left = int(args.get("frames", -1))
	screenshot_path = String(args.get("screenshot", ""))
	screen_arg = String(args.get("screen", ""))
	if args.has("timescale"):
		Engine.time_scale = float(args["timescale"])
	if args.has("mute"):
		Audio.muted = true
	recruit_arg = String(args.get("recruit", ""))   # --recruit=Necromancer,Paladin: seat companions at the start (tests)
	scroll_speed = float(cfg("scroll_speed", 130.0))
	p_max_hp = float(cfg("player_hp", 30.0))
	p_hp = p_max_hp
	p_speed = float(cfg("player_speed", 420.0))
	var skin := String(args.get("skin", Campaign.skin))
	if not QUD.has_unit(skin):
		skin = "player"

	world = Node2D.new()
	add_child(world)
	bg = ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.09)
	bg.size = Vector2(W * 2, H)
	bg.z_index = -20
	world.add_child(bg)
	cells_layer = Node2D.new()
	world.add_child(cells_layer)
	ents = Node2D.new()
	world.add_child(ents)
	cam = Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	cam.zoom = Vector2(ZOOM, ZOOM)
	world.add_child(cam)
	cam.make_current()

	_load_realm()
	_load_companions()
	_build_player(skin)
	_build_hud()
	_restore_progress()
	if recruit_arg != "":
		for nm in recruit_arg.split(","):
			for c in companions:
				if c["name"] == nm.strip_edges():
					_recruit(c)
	score_at_start = score
	_refresh_spell_hud()
	_plan_waves()
	_place_tavern()
	Audio.music("battle_%d" % (1 + (realm - 1) % 12))
	say("REALM %d   %s" % [realm, String(seg_grids[0]["tileset"]).capitalize()], 2.5)


# ---------------------------------------------------------------- the realm as a corridor

func _load_realm() -> void:
	var dumps := _realm_dumps(realm)
	var rot := int(Campaign.rift.get("dump", 0)) if Campaign.rift is Dictionary else 0
	if not dumps.is_empty() and rot > 0:
		rot = rot % dumps.size()
		dumps = dumps.slice(rot) + dumps.slice(0, rot)   # the rift you flew into leads with its dump
	if dumps.is_empty():
		dumps.append({"tileset": "stone", "chasm": "water", "grid": [], "units": [], "props": []})
	# segments: each dump once, then mirrored, until the level is long enough
	var segs := int(cfg("segments", 7))
	for i in segs:
		var lv: Dictionary = dumps[i % dumps.size()]
		var grid: Array = lv.get("grid", [])
		var cols := []
		var n := ROWS
		if not grid.is_empty():
			n = String(grid[0]).length()
		for c in n:
			var col := ""
			for r in ROWS:
				var row := String(grid[r + ROW0]) if r + ROW0 < grid.size() else ""
				var ch: String = row[c] if c < row.length() else "."
				# the outer rows are always ceiling and floor; walls near them stay as formations; in
				# the middle only the odd pillar survives
				if r == 0 or r == ROWS - 1:
					ch = "#"
				elif ch == "#" and r >= 2 and r <= ROWS - 3 and (c * 7 + r * 13 + i * 5) % 5 != 0:
					ch = "."
				col += ch
			cols.append(col)
		if (i / dumps.size()) % 2 == 1:
			cols.reverse()
		# keep the corridor flyable: at most six solid cells in a column, never a closed one
		for c in cols.size():
			var col: String = cols[c]
			if col.count("#") > 6:
				col = col.substr(0, 3) + "......" + col.substr(9)
			cols[c] = col
		seg_grids.append({"tileset": String(lv.get("tileset", "stone")), "chasm": String(lv.get("chasm", "water")), "cols": cols,
			"props": lv.get("props", []), "mirrored": (i / dumps.size()) % 2 == 1})
	var total_cols := 0
	for sg in seg_grids:
		sg["col0"] = total_cols
		total_cols += sg["cols"].size()
	level_len = total_cols * TILE
	# the first screen is open sky so the wizard can settle in
	species.clear()
	var seen := {}
	for lv in dumps:
		for u in lv.get("units", []):
			var asset: Array = u.get("asset", [])
			if asset.is_empty():
				continue
			var unit := String(asset[asset.size() - 1])
			if not QUD.has_unit(unit) or seen.has(u["name"]):
				continue
			seen[u["name"]] = true
			var info := QUD.unit_info(unit)
			var full := _monster_record(String(u["name"]).replace(" Spawner", ""))
			var spells: Array = u.get("spells", [])
			if not bool(u.get("is_lair", false)) and full.has("spells") and not full["spells"].is_empty():
				spells = full["spells"]   # the game's full records carry the description text
			species.append({"name": u["name"], "unit": unit, "hp": float(u.get("hp", 10)), "flying": bool(u.get("flying", false)),
				"stationary": bool(u.get("stationary", false)), "lair": bool(u.get("is_lair", false)), "boss": bool(u.get("is_boss", false)),
				"big": int(info.get("frame_size", 60)) > 60, "frame_size": int(info.get("frame_size", 60)), "frames": int(info.get("idle_frames", 1)),
				"spells": spells, "shields": int(u.get("shields", 0)), "tags": u.get("tags", full.get("tags", [])), "buffs": full.get("buffs", [])})
	if species.is_empty():
		species.append({"name": "Goblin", "unit": "goblin", "hp": 7, "flying": false, "stationary": false, "lair": false, "boss": false,
			"big": false, "frame_size": 60, "frames": 1, "spells": [], "shields": 0})
	for sp in species:
		if not sp["big"] and not sp["lair"] and not sp["boss"] and not sp["stationary"]:
			small_species.append(sp)
	if small_species.is_empty():
		small_species = species.duplicate()


func _col_char(c: int, r: int) -> String:
	if c < 0 or r < 0 or r >= ROWS:
		return "."
	for sg in seg_grids:
		var c0: int = sg["col0"]
		if c >= c0 and c < c0 + sg["cols"].size():
			return String(sg["cols"][c - c0])[r]
	return "."


func _seg_at(c: int) -> Dictionary:
	for sg in seg_grids:
		var c0: int = sg["col0"]
		if c >= c0 and c < c0 + sg["cols"].size():
			return sg
	return seg_grids[seg_grids.size() - 1]


func _is_solid(p: Vector2) -> bool:
	var c := int(floor(p.x / TILE))
	var r := int(floor(p.y / TILE))
	if r < 0 or r >= ROWS:
		return true
	if r == 0 or r == ROWS - 1:
		return true
	if c < 6:
		return false   # open sky at the start
	return _col_char(c, r) == "#"


func _tile_texture(sg: Dictionary, c: int, r: int, ch: String) -> Texture2D:
	var ts: String = sg["tileset"]
	if ch == "#":
		var w := QUD.texture("tiles/%s_wall_%d.png" % [ts, 1 + (c * 7 + r * 13) % 4])
		return w if w != null else QUD.texture("tiles/brick_wall_1.png")
	if ch == "~":
		return QUD.texture("tiles/chasm_%s.png" % sg["chasm"])
	var f := QUD.texture("tiles/floor_%s.png" % ts)
	return f if f != null else QUD.texture("tiles/floor_stone.png")


# Columns are built as they scroll into view and dropped once they have gone.
func _update_cells() -> void:
	var first := int(floor(scroll_x / TILE)) - 2
	var last := int(floor((scroll_x + W) / TILE)) + 2
	for c in range(first, last + 1):
		if built_cols.has(c) or c < 0:
			continue
		var nodes := []
		var sg := _seg_at(c)
		var arena := c * TILE >= level_len   # the boss arena is the rift itself
		for r in ROWS:
			var ch := _col_char(c, r) if c >= 6 else "."
			if r == 0 or r == ROWS - 1:
				ch = "#"
			elif arena:
				ch = "~"
			var s := Sprite2D.new()
			s.texture = _tile_texture(sg, c, r, ch)
			s.centered = false
			s.position = Vector2(c * TILE, r * TILE)
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if ch == "#":
				s.z_index = -5
			else:
				s.z_index = -10
				s.modulate = Color(0.5, 0.5, 0.55) if ch == "." else (Color(0.6, 0.3, 0.5) if arena else Color(0.45, 0.45, 0.6))
			if s.texture != null:
				s.scale = Vector2(TILE / s.texture.get_width(), TILE / s.texture.get_height())
			cells_layer.add_child(s)
			nodes.append(s)
		built_cols[c] = nodes
		_place_props(sg, c)
	for c in built_cols.keys():
		if c < first - 2:
			for n in built_cols[c]:
				n.queue_free()
			built_cols.erase(c)


func _place_props(sg: Dictionary, c: int) -> void:
	var local := c - int(sg["col0"])
	if bool(sg["mirrored"]):
		local = sg["cols"].size() - 1 - local
	for p in sg["props"]:
		if int(p.get("x", -1)) != local:
			continue
		var key := "%d,%d" % [c, int(p.get("y", 0))]
		if props_placed.has(key):
			continue
		props_placed[key] = true
		var asset: Array = p.get("asset", [])
		if asset.is_empty():
			continue
		var tex := QUD.texture("tiles/%s.png" % String(asset[asset.size() - 1]))
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position = Vector2(c * TILE, int(p.get("y", 0)) * TILE)
		s.z_index = -4
		s.modulate = Color(0.8, 0.8, 0.85)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.scale = Vector2(TILE / tex.get_width(), TILE / tex.get_height())
		cells_layer.add_child(s)
		built_cols[c].append(s)


# ---------------------------------------------------------------- the wizard

func _build_player(skin: String) -> void:
	player = Node2D.new()
	ents.add_child(player)
	p_sprite = Sprite2D.new()
	p_sprite.texture = QUD.unit_idle(skin)
	p_sprite.hframes = maxi(1, int(QUD.unit_info(skin).get("idle_frames", 1)))
	p_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	player.add_child(p_sprite)
	player.z_index = 5
	charge_ring = Node2D.new()
	charge_ring.z_index = 6
	player.add_child(charge_ring)
	charge_ring.draw.connect(_draw_charge)
	p_pos = Vector2(scroll_x + 300.0, H * 0.5)


func _blocked(p: Vector2) -> bool:
	return _is_solid(p + Vector2(16, 0)) or _is_solid(p + Vector2(-16, 0)) or _is_solid(p + Vector2(0, 16)) or _is_solid(p + Vector2(0, -16))


func _draw_charge() -> void:
	if charge > 0.0:
		var frac := clampf(charge / float(cfg("charge_time", 1.0)), 0.0, 1.0)
		charge_ring.draw_arc(Vector2.ZERO, 34.0 + 8.0 * frac, 0.0, TAU * frac, 24, Color(0.47, 0.78, 1.0, 0.9), 4.0)
		if frac >= 1.0:
			charge_ring.draw_arc(Vector2.ZERO, 46.0, 0.0, TAU, 24, Color(1.0, 0.93, 0.35, 0.6 + 0.4 * sin(t * 20.0)), 3.0)


func _player_step(dt: float) -> void:
	var move := Vector2.ZERO
	var fire := false
	var fire_held := false
	if auto:
		var ctl := _auto_control(dt)
		move = ctl["move"]
		fire_held = ctl["fire"]
		fire = fire_held
	else:
		move = Vector2(Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left"),
			Input.get_action_strength("drive_back") - Input.get_action_strength("drive_forward"))
		fire_held = Input.is_action_pressed("cast") or Input.is_action_pressed("drift")
		fire = fire_held
	if move.length() > 1.0:
		move = move.normalized()
	var speed := p_speed * (1.0 + 0.15 * int(ups.get("Swift", 0)) + _art("speed"))
	var np := p_pos + move * speed * dt
	np.x += scroll_speed * dt if state == PLAYING and not boss_spawned else 0.0
	np.y = clampf(np.y, TILE + 20.0, H - TILE - 20.0)
	# walls block: a wall ahead stops us (the scroll then carries us left on screen), a wall
	# above or below stops the climb; being crushed against the screen's edge is what hurts
	if _blocked(Vector2(np.x, p_pos.y)):
		np.x = p_pos.x
	if _blocked(np):
		np.y = p_pos.y
	if np.x < scroll_x + 40.0:
		np.x = scroll_x + 40.0
		if _blocked(np):
			_hurt(float(cfg("wall_damage", 3.0)), "Wall")
			var found := false
			for dx in [0.0, 60.0, 120.0, 180.0, 240.0]:
				for dy in [0.0, 60.0, -60.0, 120.0, -120.0, 180.0, -180.0, 240.0, -240.0, 300.0, -300.0]:
					var cand := Vector2(np.x + 30.0 + dx, clampf(np.y + dy, TILE + 20.0, H - TILE - 20.0))
					if not _blocked(cand):
						_effect("translocation", p_pos, 1.2)
						np = cand
						_effect("translocation", np, 1.2)
						Audio.play("teleport", -6.0)
						found = true
						break
				if found:
					break
	np.x = minf(np.x, scroll_x + W - 40.0)
	p_pos = np
	player.position = p_pos
	p_sprite.frame = int(t / 0.2) % p_sprite.hframes
	invuln = maxf(0.0, invuln - dt)
	p_sprite.modulate = Color(1, 1, 1, 0.5 + 0.5 * sin(t * 40.0)) if invuln > 0.0 else (Color(0.7, 1.0, 1.0) if shields > 0 else Color.WHITE)
	# fire: taps and holds send bolts; holding past the charge time and letting go fires the wave
	fire_cd -= dt
	if fire_held:
		charge += dt
		if fire and fire_cd <= 0.0 and charge < float(cfg("charge_time", 1.0)):
			_fire_bolts()
	else:
		if charge >= float(cfg("charge_time", 1.0)):
			_fire_wave()
		charge = 0.0
	charge_ring.queue_redraw()


func _fire_bolts() -> void:
	var rate := float(cfg("bolt_cooldown", 0.16)) * pow(0.8, int(ups.get("Rapid Fire", 0)))
	fire_cd = rate
	shots_fired += 1
	var n := 1 + int(ups.get("Twin Bolt", 0))
	var spread := int(ups.get("Spread", 0))
	var dmg := float(cfg("bolt_damage", 3.0)) * _damage_mult()
	var angles := [0.0]
	for i in spread:
		angles.append(deg_to_rad(12.0 * (i + 1)))
		angles.append(-deg_to_rad(12.0 * (i + 1)))
	for a in angles:
		for i in n:
			var off := Vector2(20.0, (i - (n - 1) * 0.5) * 18.0)
			_spawn_shot(p_pos + off, Vector2.RIGHT.rotated(a) * float(cfg("bolt_speed", 900.0)), dmg, "arcane")
	if int(ups.get("Rear Guard", 0)) > 0:
		_spawn_shot(p_pos + Vector2(-20, 0), Vector2.LEFT * float(cfg("bolt_speed", 900.0)), dmg, "arcane")
	if not force.is_empty() and bool(force["attached"]):
		_spawn_shot(force["pos"] + Vector2(20, 0), Vector2.RIGHT * float(cfg("bolt_speed", 900.0)), dmg * 0.8, "holy", 9.0, 1 if int(ups.get("Force Pod", 0)) >= 2 else 0)
	Audio.play("sorcery", -14.0)


func _spawn_shot(at: Vector2, vel: Vector2, dmg: float, dtype: String, radius := 10.0, pierce := -1, seek := false) -> void:
	var s := Sprite2D.new()
	s.texture = Items.effect_strip(dtype)
	s.hframes = 6
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = at
	s.rotation = vel.angle()
	s.scale = Vector2.ONE * (radius / 30.0) * 1.6
	s.z_index = 4
	ents.add_child(s)
	if pierce < 0:
		pierce = 1 if int(ups.get("Piercing", 0)) > 0 else 0
	shots.append({"node": s, "pos": at, "vel": vel, "dmg": dmg, "age": 0.0, "radius": radius, "pierce": pierce,
		"homing": seek or int(ups.get("Seeking Bolts", 0)) > 0, "dtype": dtype})


func _fire_wave() -> void:
	var lvl := int(ups.get("Wave Cannon", 0))
	var width := 60.0 + 30.0 * lvl + 20.0 * _art("beam_targets")
	var dmg := float(cfg("wave_damage", 14.0)) * (1.0 + 0.5 * lvl) * _damage_mult()
	var beam := Line2D.new()
	beam.width = width
	beam.default_color = Color(0.47, 0.78, 1.0, 0.85)
	beam.add_point(p_pos + Vector2(30, 0))
	beam.add_point(p_pos + Vector2(W, 0))
	beam.z_index = 7
	ents.add_child(beam)
	fx.append({"node": beam, "left": 0.25, "kind": "beam"})
	for e in enemies.duplicate():
		if e["pos"].x > p_pos.x and absf(e["pos"].y - p_pos.y) < width * 0.5 + e["radius"]:
			_damage_enemy(e, dmg, "lightning")
	Audio.play("sorcery", -2.0)
	_shake(6.0)


func _hurt(dmg: float, dtype: String) -> void:
	if invuln > 0.0 or state != PLAYING:
		return
	if shields > 0:
		shields -= 1
		invuln = 0.6
		_effect("shield_expire", p_pos, 1.2)
		Audio.play("shield_break")
		return
	p_hp -= dmg
	invuln = 1.2
	damage_log[dtype] = float(damage_log.get(dtype, 0.0)) + dmg
	_effect("physical" if dtype in ["Wall", "Contact"] else dtype.to_lower(), p_pos, 1.2)
	Audio.play("hit_player")
	_shake(10.0)
	if p_hp <= 0.0:
		p_hp = 0.0
		_die()


func _die() -> void:
	state = DEAD
	death_t = t
	_record_scores(false)
	Campaign.rift = {}
	Audio.play("death_player")
	Audio.music("lose_theme")
	_effect("dark", p_pos, 3.0)
	player.visible = false
	lbl_center.text = "THE WIZARD IS DEAD\n\nrealm %d   level %d   score %d   %d slain\n\nenter to fly again    esc for the menu" % [realm, level_n, score, kills]
	lbl_center.visible = true


# The demo pilot: dodge the nearest bullet or wall, line up on a monster, keep the trigger down.
func _auto_control(dt: float) -> Dictionary:
	var want_y := H * 0.5
	var nearest: Dictionary = {}
	var best := 1e9
	for e in enemies:
		if e["pos"].x < p_pos.x:
			continue
		var d: float = e["pos"].distance_to(p_pos)
		if d < best:
			best = d
			nearest = e
	if not nearest.is_empty():
		want_y = nearest["pos"].y
	var flee := 0.0
	for b in bullets:
		var rel: Vector2 = b["pos"] - p_pos
		if rel.length() < 220.0 and (b["vel"].dot(-rel) > 0.0):
			flee += -signf(rel.y) if rel.y != 0.0 else 1.0
	for c in clouds:
		var rel: Vector2 = c["pos"] - p_pos
		if rel.length() < 190.0:
			flee += -signf(rel.y) if rel.y != 0.0 else 1.0
	for e in enemies:
		if float(e["radius"]) < 30.0 and not e["boss"]:
			continue   # small things get shot, not dodged
		var rel: Vector2 = e["pos"] - p_pos
		if rel.length() < 140.0 + e["radius"]:
			flee += -signf(rel.y) if rel.y != 0.0 else 1.0
	if flee != 0.0:
		want_y = p_pos.y + 160.0 * signf(flee)
	# the corridor ahead: of the rows open through the next few columns, the one nearest our wish
	var c0 := int(floor(p_pos.x / TILE))
	var best_y := want_y
	var best_d := 1e9
	for r in range(1, ROWS - 1):
		var open := true
		for c in range(c0, c0 + 5):
			if _col_char(c, r) == "#" and c >= 6:
				open = false
				break
		if not open:
			continue
		var y := r * TILE + TILE * 0.5
		var d := absf(y - want_y)
		if d < best_d:
			best_d = d
			best_y = y
	want_y = best_y
	var move := Vector2(0.0, clampf((want_y - p_pos.y) / 40.0, -1.0, 1.0))
	var want_x := scroll_x + 320.0
	if state == CLEARED and screen_arg != "rifts":
		var goal := Vector2.ZERO
		if not chests.is_empty():
			goal = chests[0]["pos"]
		elif not rifts.is_empty():
			goal = rifts[rng.randi_range(0, rifts.size() - 1)]["pos"] if not rift_goal_set else rift_goal
			if not rift_goal_set:
				rift_goal = goal
				rift_goal_set = true
		if goal != Vector2.ZERO:
			var d := goal - p_pos
			return {"move": Vector2(clampf(d.x / 60.0, -1.0, 1.0), clampf(d.y / 60.0, -1.0, 1.0)), "fire": false}
	move.x = clampf((want_x - p_pos.x) / 100.0, -1.0, 1.0)
	# bursts of bolts (a hold longer than the charge time stops them), and every few seconds a held charge let go as the wave
	var cycle := fmod(t, 7.0)
	var fire := (fmod(t, 0.9) < 0.75) if cycle < 5.5 else (cycle < 6.8)
	return {"move": move, "fire": fire}


# ---------------------------------------------------------------- monsters

func _plan_waves() -> void:
	waves.clear()
	var x := 900.0
	var gap := float(cfg("wave_gap", 330.0))
	var i := 0
	while x < level_len - 600.0:
		var sp: Dictionary = species[rng.randi_range(0, species.size() - 1)]
		var count := 2 + int(realm / 5) + rng.randi_range(0, 2)
		var kind := "sine"
		if bool(sp["lair"]):
			kind = "hive"
			count = 1
		elif bool(sp["stationary"]):
			kind = "turret"
			count = 1 + rng.randi_range(0, 1)
		elif bool(sp["big"]):
			kind = "wall"
			count = 1
		elif bool(sp["flying"]):
			kind = ["sine", "vee", "diver", "orbit"][rng.randi_range(0, 3)]
		else:
			kind = ["column", "swarm", "vee", "sine"][rng.randi_range(0, 3)]
		waves.append({"x": x, "kind": kind, "species": sp, "count": count})
		x += gap * (1.4 if kind in ["wall", "hive"] else 1.0)
		i += 1


func _spawn_enemy(sp: Dictionary, pos: Vector2, kind: String, index: int, count: int, extra := {}) -> Dictionary:
	var node := Node2D.new()
	var s := Sprite2D.new()
	s.texture = QUD.unit_idle(sp["unit"])
	s.hframes = maxi(1, int(sp["frames"]))
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.flip_h = true
	node.add_child(s)
	node.position = pos
	node.z_index = 3
	ents.add_child(node)
	var scale := float(cfg("enemy_hp_scale", 0.35)) * (1.0 + 0.08 * realm)
	var hp := maxf(2.0, float(sp["hp"]) * scale)
	var radius := float(sp["frame_size"]) * 0.36
	var e := {"node": node, "sprite": s, "sp": sp, "pos": pos, "anchor": pos, "hp": hp, "max_hp": hp, "kind": kind, "t": 0.0,
		"i": index, "n": count, "radius": radius, "phase": rng.randf() * TAU, "shields": int(sp["shields"]), "spells": [], "flash": 0.0,
		"boss": false, "dead": false, "vel": Vector2.ZERO, "buffs": sp.get("buffs", []), "lives": 0, "tick": rng.randf(), "kids": 0,
		"mature_t": -1.0, "reinforced": false, "grow": 0.0, "retal_t": 0.0, "original_hp": hp}
	for b in e["buffs"]:
		if String(b.get("class", "")) == "ReincarnationBuff":
			e["lives"] = maxi(1, int(b.get("lives", 1)))
		elif String(b.get("class", "")) == "MatureInto":
			e["mature_t"] = clampf(float(b.get("duration", 8)) * 0.6, 4.0, 14.0)
	for k in extra:
		e[k] = extra[k]
	for spl in sp["spells"]:
		if not (spl is Dictionary):
			continue
		var cd := float(spl.get("cool_down", 0))
		var nm := String(spl.get("name", ""))
		var mode := SpellKinds.classify(spl)
		if cd <= 0.0:
			cd = 2.5 if mode == "lunge" else 4.0
		var dtypes: Array = spl.get("damage_type", [])
		e["spells"].append({"name": nm, "mode": mode, "cd": cd * float(cfg("enemy_cooldown_scale", 1.3)), "left": cd * 0.5 + rng.randf() * cd,
			"dtype": String(dtypes[0]) if not dtypes.is_empty() else "Arcane"})
	if kind == "hive" and QUD.has_unit("lair"):   # the game draws a spawner as its monster inside the lair frame
		var lair := Sprite2D.new()
		lair.texture = QUD.unit_idle("lair")
		lair.hframes = maxi(1, int(QUD.unit_info("lair").get("idle_frames", 1)))
		lair.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		lair.z_index = 1
		node.add_child(lair)
		e["lair_sprite"] = lair
		e["radius"] = 48.0
		e["hp"] = hp * 2.0
		e["max_hp"] = hp * 2.0
	if e["spells"].is_empty() and kind in ["turret", "hive", "wall"]:
		e["spells"].append({"name": "Spit", "mode": "bolt", "cd": 2.6, "left": 1.0 + rng.randf(), "dtype": "Physical"})
	enemies.append(e)
	return e


func _launch_wave(w: Dictionary) -> void:
	var sp: Dictionary = w["species"]
	var n: int = w["count"]
	var right := scroll_x + W + 80.0
	match String(w["kind"]):
		"sine":
			var y := rng.randf_range(140.0, H - 140.0)
			for i in n:
				_spawn_enemy(sp, Vector2(right + i * 70.0, y), "sine", i, n, {"amp": rng.randf_range(80.0, 220.0), "freq": rng.randf_range(1.5, 3.0), "speed": rng.randf_range(160.0, 260.0)})
		"vee":
			var y := rng.randf_range(200.0, H - 200.0)
			for i in n:
				var k := (i + 1) / 2
				var side := 1.0 if i % 2 == 1 else -1.0
				_spawn_enemy(sp, Vector2(right + k * 60.0, y + side * k * 64.0), "vee", i, n, {"speed": 210.0})
		"column":
			for i in n:
				_spawn_enemy(sp, Vector2(right + i * 40.0, 120.0 + i * 70.0), "column", i, n, {"speed": 120.0, "sweep": rng.randf_range(0.6, 1.1)})
		"diver":
			for i in n:
				_spawn_enemy(sp, Vector2(right - 400.0 + i * 160.0, -60.0 - i * 80.0), "diver", i, n, {"speed": 380.0, "dive_y": p_pos.y})
		"orbit":
			var c := Vector2(right + 120.0, rng.randf_range(260.0, H - 260.0))
			for i in n:
				_spawn_enemy(sp, c, "orbit", i, n, {"center": c, "r": 90.0 + 12.0 * n, "speed": 110.0, "spin": rng.randf_range(1.2, 2.2) * (1.0 if rng.randf() < 0.5 else -1.0)})
		"swarm":
			for i in n:
				_spawn_enemy(sp, Vector2(right + rng.randf_range(0, 300), rng.randf_range(100.0, H - 100.0)), "swarm", i, n, {"speed": rng.randf_range(150.0, 230.0)})
		"turret":
			for i in n:
				var c := int(floor((right + 200.0 + i * 300.0) / TILE))
				var top := rng.randf() < 0.5
				var y := _wall_edge(c, top)
				_spawn_enemy(sp, Vector2(c * TILE + TILE * 0.5, y), "turret", i, n, {"top": top})
		"hive":
			var c := int(floor((right + 260.0) / TILE))
			var top := rng.randf() < 0.5
			var y := _wall_edge(c, top)
			_spawn_enemy(sp, Vector2(c * TILE + TILE * 0.5, y), "hive", 0, 1, {"top": top, "hatch": 2.5, "hatched": 0})
		"wall":
			_spawn_enemy(sp, Vector2(right + 200.0, rng.randf_range(220.0, H - 220.0)), "wall", 0, 1, {"speed": 70.0, "amp": 140.0, "freq": 0.6})


# The y where a turret sits on the ceiling or the floor at column c (the nearest wall face).
func _wall_edge(c: int, top: bool) -> float:
	if top:
		var r := 0
		while r < ROWS - 2 and _col_char(c, r + 1) == "#":
			r += 1
		return (r + 1) * TILE + 28.0
	var r := ROWS - 1
	while r > 1 and _col_char(c, r - 1) == "#":
		r -= 1
	return r * TILE - 28.0


func _enemy_step(e: Dictionary, dt: float) -> void:
	var haste := float(e.get("haste", 0.0))
	if haste > 0.0:
		e["haste"] = haste - dt
	e["t"] += dt * (1.6 if haste > 0.0 else 1.0) * (1.35 if _has_buff(e, "QuickmoveBuff") else 1.0)
	var et: float = e["t"]
	e["tick"] = float(e["tick"]) - dt
	if e["tick"] <= 0.0:
		e["tick"] = 1.0
		if _enemy_passives_tick(e):
			return   # it became something else
	var p: Vector2 = e["pos"]
	if float(e.get("lunge_t", 0.0)) > 0.0:
		e["lunge_t"] = float(e["lunge_t"]) - dt
		p = p.move_toward(e["lunge_to"], 720.0 * dt)
		e["pos"] = p
		e["anchor"] = e["anchor"] + (p - e["pos"])
		e["node"].position = p
		if p.distance_to(p_pos) < float(e["radius"]) + 18.0:
			_hurt(float(cfg("contact_damage", 4.0)) + 1.0, "Physical")
			e["lunge_t"] = 0.0
		return
	match String(e["kind"]):
		"sine":
			p = e["anchor"] + Vector2(-float(e["speed"]) * et, sin(et * float(e["freq"]) + float(e["phase"]) + e["i"] * 0.4) * float(e["amp"]))
		"vee":
			p = e["anchor"] + Vector2(-float(e["speed"]) * et, sin(et * 1.2) * 30.0)
		"column":
			var sw: float = e["sweep"]
			p = e["anchor"] + Vector2(-float(e["speed"]) * et, 0)
			p.y = H * 0.5 + (H * 0.5 - 110.0) * sin(et * sw + e["i"] * 0.35)
		"diver":
			if et < 1.4:
				p = e["anchor"].lerp(Vector2(e["anchor"].x - 200.0, float(e["dive_y"])), et / 1.4)
			else:
				p += Vector2(-float(e["speed"]), 0) * dt
		"orbit":
			var c: Vector2 = e["center"] + Vector2(-float(e["speed"]) * et, 0)
			var a: float = float(e["phase"]) + et * float(e["spin"]) + TAU * e["i"] / maxi(1, e["n"])
			p = c + Vector2(cos(a), sin(a)) * float(e["r"])
		"swarm":
			var to: Vector2 = (p_pos - p).normalized()
			var wob := Vector2(sin(et * 5.0 + float(e["phase"])), cos(et * 3.7 + float(e["phase"]))) * 0.7
			p += (to * 0.6 + wob).normalized() * float(e["speed"]) * dt + Vector2(-40.0 * dt, 0)
		"turret":
			pass
		"hive":
			e["hatch"] -= dt
			if e["hatch"] <= 0.0 and int(e["hatched"]) < 6:
				e["hatch"] = 3.0
				e["hatched"] = int(e["hatched"]) + 1
				var sp: Dictionary = e["sp"].duplicate()   # a spawner hatches its own monster
				sp["lair"] = false
				sp["spells"] = _monster_record(String(sp["name"]).replace(" Spawner", "")).get("spells", sp["spells"])
				_spawn_enemy(sp, p + Vector2(0, -60.0 if bool(e["top"]) else 60.0) * -1.0, "swarm", 0, 1, {"speed": 180.0})
				_effect("dark", p, 1.0)
				summons += 1
		"wall":
			p = e["anchor"] + Vector2(-float(e["speed"]) * et, sin(et * float(e["freq"])) * float(e["amp"]))
		"minion":
			p += (p_pos - p).normalized() * 160.0 * dt
		"boss":
			_boss_step(e, dt)
			p = e["pos"]
	e["pos"] = p
	e["node"].position = p
	var s: Sprite2D = e["sprite"]
	s.frame = int(et / 0.18) % s.hframes
	if e.has("lair_sprite"):
		e["lair_sprite"].frame = int(et / 0.25) % maxi(1, e["lair_sprite"].hframes)
	e["flash"] = maxf(0.0, float(e["flash"]) - dt)
	s.modulate = Color(1.0, 0.5, 0.5) if e["flash"] > 0.0 else (Color(0.8, 1.0, 1.0) if int(e["shields"]) > 0 else (Color(1.0, 0.85, 0.6) if haste > 0.0 else Color.WHITE))
	if String(e["kind"]) == "turret":
		s.flip_h = p_pos.x < p.x
	# spells
	if p.x < scroll_x + W + 40.0 and p.x > scroll_x - 40.0:
		for spl in e["spells"]:
			spl["left"] -= dt
			if spl["left"] <= 0.0:
				spl["left"] = float(spl["cd"])
				_enemy_cast(e, spl)
	# contact
	if state == PLAYING and invuln <= 0.0 and p.distance_to(p_pos) < float(e["radius"]) + 18.0:
		_hurt(float(cfg("contact_damage", 4.0)) * (2.0 if e["boss"] else 1.0), "Contact")
		_thorns_player(e)
		if not e["boss"] and not e["kind"] in ["wall", "turret", "hive"]:
			_damage_enemy(e, 2.0, "physical")
	# gone
	if p.x < scroll_x - 240.0 or p.y < -200.0 or p.y > H + 200.0:
		_remove_enemy(e)


func _spawn_bullet(at: Vector2, vel: Vector2, dmg: float, dtype: String) -> void:
	var s := Sprite2D.new()
	s.texture = Items.effect_strip(dtype)
	s.hframes = 6
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = at
	s.scale = Vector2.ONE * 0.55
	s.z_index = 4
	ents.add_child(s)
	bullets.append({"node": s, "pos": at, "vel": vel, "dmg": dmg, "dtype": dtype, "age": 0.0, "owner": last_caster})


func _damage_enemy(e: Dictionary, dmg: float, dtype: String) -> void:
	if e["dead"]:
		return
	if int(e["shields"]) > 0:
		e["shields"] = int(e["shields"]) - 1
		_effect("shield_expire", e["pos"], 1.0)
		return
	if float(e.get("wither", 0.0)) > 0.0:
		dmg *= 1.25   # Withering Aura: corroded
	e["hp"] -= dmg
	e["flash"] = 0.12
	_damage_passives(e, dtype)
	if e["hp"] <= 0.0:
		_kill_enemy(e)
	elif e["boss"]:
		_refresh_boss_bar()


func _kill_enemy(e: Dictionary) -> void:
	if int(e["lives"]) > 0:   # Reincarnation: not today
		e["lives"] = int(e["lives"]) - 1
		e["hp"] = float(e["max_hp"])
		_effect("holy", e["pos"], 2.0)
		Audio.play("learn_spell", -8.0)
		_ability("reincarnate")
		if e["boss"]:
			_refresh_boss_bar()
		return
	e["dead"] = true
	kills += 1
	_death_passives(e)
	var nm := String(e["sp"]["name"])
	slain_names[nm] = int(slain_names.get(nm, 0)) + 1
	if "Living" in e["sp"].get("tags", []) and not e["boss"]:
		for a in party:
			if "NecromancyBuff" in a["buffs"]:
				_raise_skeleton(e)
				break
	if _art("kill_heal") > 0.0:
		p_hp = minf(p_max_hp, p_hp + 0.15 * _art("kill_heal"))
	if String(e["kind"]) == "wall" and not e["boss"]:
		_spawn_chest(e["pos"], false)   # minibosses carry loot
	var worth := 10 + int(e["max_hp"])
	score += worth * (10 if e["boss"] else 1)
	_effect("dark" if e["boss"] else "fire", e["pos"], 2.6 if e["boss"] else 1.4)
	Audio.play("death_enemy", -4.0)
	var n_orbs := 1 + int(e["max_hp"] / 12.0)
	for i in mini(n_orbs, 8):
		_spawn_orb(e["pos"] + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), 4.0 + e["max_hp"] / maxi(1, mini(n_orbs, 8)) * 0.5)
	if e["boss"]:
		_boss_dead()
	_remove_enemy(e)


func _remove_enemy(e: Dictionary) -> void:
	enemies.erase(e)
	e["node"].queue_free()


func _spawn_orb(at: Vector2, worth: float) -> void:
	var s := Sprite2D.new()
	s.texture = QUD.texture("tiles/item_mana_orb.png")
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2.ONE * 0.5
	s.position = at
	s.z_index = 2
	ents.add_child(s)
	orbs.append({"node": s, "pos": at, "xp": worth, "vel": Vector2(rng.randf_range(-60, 20), rng.randf_range(-60, 60))})


# ---------------------------------------------------------------- the boss

func _spawn_boss() -> void:
	boss_spawned = true
	var sp: Dictionary = {}
	for s in species:
		if bool(s["boss"]):
			sp = s
	if sp.is_empty():
		var cands := QUD.bosses(realm, realm >= 20)
		if not cands.is_empty():
			var c: Dictionary = cands[rng.randi_range(0, cands.size() - 1)]
			var info := QUD.unit_info(c["unit"])
			sp = {"name": c["name"], "unit": c["unit"], "hp": float(c.get("hp", 60)), "flying": true, "stationary": false, "lair": false, "boss": true,
				"big": int(info.get("frame_size", 60)) > 60, "frame_size": int(info.get("frame_size", 60)), "frames": int(info.get("idle_frames", 1)),
				"spells": c.get("spells", []), "shields": 0}
	if sp.is_empty():
		var best := 0.0
		for s in species:
			if float(s["hp"]) > best:
				best = float(s["hp"])
				sp = s
	var pos := Vector2(scroll_x + W + 200.0, H * 0.5)
	boss = _spawn_enemy(sp, pos, "boss", 0, 1)
	boss["boss"] = true
	boss["hp"] = float(cfg("boss_hp_base", 60.0)) + float(cfg("boss_hp_per_realm", 22.0)) * realm
	boss["max_hp"] = boss["hp"]
	boss["radius"] = maxf(boss["radius"], 44.0)
	boss["home"] = Vector2(scroll_x + W - 300.0, H * 0.5)
	if boss["spells"].is_empty():
		boss["spells"].append({"name": "Roar", "mode": "bolt", "cd": 1.6, "left": 1.0, "dtype": "Dark"})
	boss["sprite"].scale = Vector2.ONE * (1.6 if not bool(sp["big"]) else 1.0)
	boss_phase = 0
	boss_t = 0.0
	boss["phases"] = _boss_phases(sp)
	boss["cast_left"] = 0.0
	boss["cast_n"] = 0
	lbl_boss.text = "%s   casting %s" % [String(sp["name"]).to_upper(), String(boss["phases"][0]["name"]).to_upper()]
	boss_bar.visible = true
	_refresh_boss_bar()
	say("%s" % String(sp["name"]).to_upper(), 2.5)
	Audio.play("start_level")


func _refresh_boss_bar() -> void:
	if boss.is_empty():
		return
	boss_fill.size = Vector2(600.0 * clampf(float(boss["hp"]) / maxf(1.0, float(boss["max_hp"])), 0.0, 1.0), 18)


func _boss_dead() -> void:
	boss_bar.visible = false
	state = CLEARED
	cleared_t = 0.0
	score += 500 * realm
	_record_scores(true)
	Audio.music("victory_theme")
	say("REALM %d CLEARED" % realm, 3.0)
	_shake(16.0)
	for e in enemies.duplicate():
		if not e["boss"]:
			_kill_enemy(e)
	boss_dead_flag = true
	_spawn_chest(boss["pos"], true)
	_open_rifts()


# ---------------------------------------------------------------- world step

func _physics_process(dt: float) -> void:
	t += dt
	if seconds_limit > 0.0 and t >= seconds_limit:
		seconds_limit = -1.0
		frames_left = -1
		_finish_screenshot()
		return
	message_t = maxf(0.0, message_t - dt)
	match state:
		LEVELUP:
			if auto and screen_arg != "levelup":
				_pick(0)
			return
		TAVERN:
			if auto and screen_arg != "tavern":
				_tavern_pick(0)
			return
		PAUSED, FEEDBACK:
			return
		DEAD:
			_fx_step(dt)
			return
		CLEARED:
			cleared_t += dt
			cam.position = Vector2(scroll_x, 0) + _shake_offset()
			_player_step(dt)
			_fx_step(dt)
			_orbs_step(dt)
			_chests_step(dt)
			_rifts_step(dt)
			_party_step(dt)
			_undead_step(dt)
			_shots_step(dt)
			if cleared_t > 40.0 and (seconds_limit > 0.0 or frames_left >= 0):
				_finish_screenshot()   # the pilot never found a rift
			return
		ARTIFACT:
			artifact_t += dt
			if auto and artifact_t > 1.0 and screen_arg != "chest":
				_close_chest()
			return
		INTERMISSION:
			intermission_t += dt
			if auto and intermission_t > 1.5 and screen_arg != "intermission":
				_leave_intermission()
			return
	if not boss_spawned:
		scroll_x += scroll_speed * dt
		if scroll_x >= level_len:
			_spawn_boss()
	cam.position = Vector2(scroll_x, 0) + _shake_offset()
	bg.position = Vector2(scroll_x - W * 0.5, 0)
	_update_cells()
	_player_step(dt)
	if auto and int(t) % 10 == 0 and int((t - dt)) % 10 != 0:
		print("rt %3d s: hp=%d pos=%s enemies=%d shots=%d bullets=%d kills=%d wave=%d" % [int(t), int(p_hp), str(p_pos.round()), enemies.size(), shots.size(), bullets.size(), kills, wave_i])
	while wave_i < waves.size() and float(waves[wave_i]["x"]) <= scroll_x + W * 0.5:
		_launch_wave(waves[wave_i])
		wave_i += 1
	for e in enemies.duplicate():
		_enemy_step(e, dt)
	_spells_step(dt)
	_force_step(dt)
	_clouds_step(dt)
	_taverns_step(dt)
	_chests_step(dt)
	_party_step(dt)
	_undead_step(dt)
	_shots_step(dt)
	_bullets_step(dt)
	_beams_step(dt)
	_familiars_step(dt)
	_orbs_step(dt)
	_fx_step(dt)


func _shots_step(dt: float) -> void:
	for s in shots.duplicate():
		s["age"] += dt
		if s["homing"]:
			var best: Dictionary = {}
			var bd := 420.0
			for e in enemies:
				var d: float = e["pos"].distance_to(s["pos"])
				if d < bd:
					bd = d
					best = e
			if not best.is_empty():
				var want: Vector2 = (best["pos"] - s["pos"]).normalized() * s["vel"].length()
				s["vel"] = s["vel"].lerp(want, minf(1.0, dt * 6.0))
		s["pos"] += s["vel"] * dt
		var n: Sprite2D = s["node"]
		n.position = s["pos"]
		n.rotation = s["vel"].angle()
		n.frame = int(s["age"] / 0.06) % 6
		var gone: bool = s["pos"].x > scroll_x + W + 60.0 or s["pos"].x < scroll_x - 60.0 or s["pos"].y < -40.0 or s["pos"].y > H + 40.0 or _is_solid(s["pos"])
		if _is_solid(s["pos"]):
			_effect(s["dtype"], s["pos"], 0.7)
		if not gone:
			for e in enemies.duplicate():
				if e["pos"].distance_to(s["pos"]) < float(e["radius"]) + float(s["radius"]):
					if e["pos"].distance_to(p_pos) < TILE * 2.0 + float(e["radius"]):
						_thorns_player(e)   # point blank counts as melee
					_damage_enemy(e, s["dmg"], s["dtype"])
					_effect(s["dtype"], s["pos"], 0.9)
					if int(s["pierce"]) > 0:
						s["pierce"] = int(s["pierce"]) - 1
					else:
						gone = true
					break
		if gone:
			shots.erase(s)
			n.queue_free()


func _bullets_step(dt: float) -> void:
	for b in bullets.duplicate():
		b["age"] += dt
		b["pos"] += b["vel"] * dt
		var n: Sprite2D = b["node"]
		n.position = b["pos"]
		n.frame = int(b["age"] / 0.08) % 6
		n.rotation = b["vel"].angle()
		var gone: bool = b["age"] > 7.0 or b["pos"].x < scroll_x - 100.0 or b["pos"].x > scroll_x + W + 100.0 or b["pos"].y < -60.0 or b["pos"].y > H + 60.0
		if _is_solid(b["pos"]):
			gone = true
		elif state == PLAYING and b["pos"].distance_to(p_pos) < 22.0:
			var before := p_hp
			_hurt(b["dmg"], b["dtype"])
			if p_hp < before and b.has("owner") and b["owner"] is Dictionary and not b["owner"].is_empty():
				_on_kill_passives(b["owner"])
			gone = true
		if gone:
			bullets.erase(b)
			n.queue_free()


func _beams_step(dt: float) -> void:
	for b in beams.duplicate():
		b["t"] += dt
		var line: Line2D = b["node"]
		if b["t"] < 0.7:
			line.default_color.a = 0.25 + 0.25 * sin(b["t"] * 30.0)
			continue
		if not b["fired"]:
			b["fired"] = true
			line.width = 26.0
			line.default_color = Color(Items.type_color(b["dtype"]), 0.95)
			# does the wizard stand on the line?
			var rel: Vector2 = p_pos - b["from"]
			var along: float = rel.dot(b["dir"])
			var off: float = absf(rel.cross(b["dir"]))
			if along > 0.0 and off < 30.0:
				_hurt(b["dmg"], b["dtype"])
				var healer = b.get("healer")
				if healer != null and healer is Dictionary and not healer.get("dead", true):
					healer["hp"] = minf(float(healer["max_hp"]), float(healer["hp"]) + float(b["dmg"]))
					_effect("heal", healer["pos"], 0.9)
			Audio.play("sorcery", -10.0)
		if b["t"] > 0.95:
			beams.erase(b)
			line.queue_free()


func _orbs_step(dt: float) -> void:
	for o in orbs.duplicate():
		var rel: Vector2 = p_pos - o["pos"]
		if rel.length() < 260.0 or state == CLEARED:
			o["vel"] = o["vel"].lerp(rel.normalized() * 900.0, minf(1.0, dt * 6.0))
		else:
			o["vel"] = o["vel"].lerp(Vector2(-30.0, 0), minf(1.0, dt))
		o["pos"] += o["vel"] * dt
		o["node"].position = o["pos"]
		if rel.length() < 28.0:
			_gain_xp(float(o["xp"]))
			orbs.erase(o)
			o["node"].queue_free()
			Audio.play("item_pickup", -14.0)
		elif o["pos"].x < scroll_x - 100.0:
			orbs.erase(o)
			o["node"].queue_free()


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
	ents.add_child(s)
	fx.append({"node": s, "left": 0.42, "kind": "strip", "age": 0.0})


func _fx_step(dt: float) -> void:
	for f in fx.duplicate():
		f["left"] -= dt
		if f["kind"] == "strip":
			f["age"] += dt
			f["node"].frame = mini(5, int(f["age"] / 0.07))
		else:
			f["node"].modulate.a = maxf(0.0, f["left"] / 0.25)
		if f["left"] <= 0.0:
			fx.erase(f)
			f["node"].queue_free()
	shake_t = maxf(0.0, shake_t - dt)


var shake_t := 0.0
var shake_amp := 0.0


func _shake(amp: float) -> void:
	shake_amp = amp
	shake_t = 0.3


func _shake_offset() -> Vector2:
	if shake_t <= 0.0:
		return Vector2.ZERO
	return Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake_amp * (shake_t / 0.3)


# ---------------------------------------------------------------- levels and upgrades

func _xp_needed(lvl: int) -> float:
	return float(cfg("xp_base", 24.0)) * pow(float(lvl), float(cfg("xp_power", 1.45)))


func _gain_xp(amount: float) -> void:
	xp += amount
	if xp >= _xp_needed(level_n) and state == PLAYING:
		xp -= _xp_needed(level_n)
		level_n += 1
		_offer_upgrades()


func _offer_upgrades() -> void:
	state = LEVELUP
	offer.clear()
	var pool := []
	for u in UPGRADES:
		if int(ups.get(u["name"], 0)) < int(u["max"]):
			pool.append(u)
	var spells := _spell_pool()
	for k in mini(spells.size(), 4 + int(pool.size() / 3)):   # spells are about a third of the draw
		var j := rng.randi_range(0, spells.size() - 1)
		var sp: Dictionary = spells[j]
		spells.remove_at(j)
		var owned := SpellDB.make_owned(sp)
		var d := String(owned.get("desc", ""))
		if d.length() > 120:
			d = d.substr(0, 117) + "..."
		pool.append({"name": sp["name"], "blurb": d, "max": 1, "icon": owned["icon"], "spell": sp, "level": int(sp.get("level", 1))})
	while offer.size() < 3 and not pool.is_empty():
		var j := rng.randi_range(0, pool.size() - 1)
		offer.append(pool[j])
		pool.remove_at(j)
	if offer.is_empty():
		state = PLAYING
		return
	Audio.play("learn_spell", -4.0)
	cards = Control.new()
	cards.size = Vector2(SW, SH)
	hud.add_child(cards)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Vector2(SW, SH)
	cards.add_child(dim)
	var title := _label("LEVEL %d   choose an upgrade" % level_n, 44, Color(1.0, 0.93, 0.35))
	title.position = Vector2(0, 220)
	title.size = Vector2(SW, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cards.add_child(title)
	var cw := 440.0
	var x0 := (SW - (cw * offer.size() + 30.0 * (offer.size() - 1))) * 0.5
	for i in offer.size():
		var u: Dictionary = offer[i]
		var panel := PanelContainer.new()
		panel.position = Vector2(x0 + i * (cw + 30.0), 330)
		panel.size = Vector2(cw, 360)
		cards.add_child(panel)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 10)
		panel.add_child(vb)
		vb.add_child(_label("%d" % (i + 1), 40, Color(0.55, 0.85, 1.0)))
		var icon := TextureRect.new()
		icon.texture = QUD.icon(String(u["icon"]))
		icon.custom_minimum_size = Vector2(96, 96)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		vb.add_child(icon)
		var have := int(ups.get(u["name"], 0))
		if u.has("spell"):
			vb.add_child(_label("%s   spell %d" % [String(u["name"]).to_upper(), int(u["level"])], 28, Color(0.95, 0.7, 1.0)))
		else:
			vb.add_child(_label("%s%s" % [String(u["name"]).to_upper(), ("   %d/%d" % [have + 1, int(u["max"])]) if int(u["max"]) > 1 else ""], 28))
		var bl := _label(String(u["blurb"]), 20, Color(0.8, 0.8, 0.8))
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size = Vector2(cw - 40, 0)
		vb.add_child(bl)


func _pick(i: int) -> void:
	if i < 0 or i >= offer.size():
		return
	var u: Dictionary = offer[i]
	if u.has("spell"):
		_learn_spell(u["spell"])
	else:
		ups[u["name"]] = int(ups.get(u["name"], 0)) + 1
	match String(u["name"]):
		"Force Shield":
			shields += 2
		"Vitality":
			p_max_hp += 10.0
			p_hp = p_max_hp
	say(String(u["name"]).to_upper(), 1.4)
	if cards != null:
		cards.queue_free()
		cards = null
	state = PLAYING
	invuln = maxf(invuln, 0.8)


# ---------------------------------------------------------------- spells on the number keys

# Level-ups offer the game's own spells beside the upgrades; each cast maps the spell's
# effect record (the same one the karts use) onto the shooter: bolts seek, beams cross the
# screen, blasts burst on the nearest monster, summons fly as familiars for a while,
# shields, heals, buffs and blinks do what they say.
func _spell_pool() -> Array:
	var out := []
	var have := {}
	for ps in p_spells:
		have[ps["name"]] = true
	for sp in SpellDB.spells:
		if int(sp.get("level", 1)) > 2 or have.has(sp["name"]):
			continue
		var owned := SpellDB.make_owned(sp)
		var kind := String(owned["effect"].get("kind", "bolt"))
		if kind in ["bolt", "beam", "blast", "burst", "patch", "aura", "summon", "shield", "heal", "buff", "empower", "blink", "hex", "melee"]:
			out.append(sp)
	return out


func _learn_spell(sp: Dictionary) -> void:
	if p_spells.size() >= 9:
		return
	var owned := SpellDB.make_owned(sp)
	var lvl := int(sp.get("level", 1))
	p_spells.append({"name": sp["name"], "owned": owned, "cd": clampf(2.5 + 1.5 * lvl, 3.0, 12.0), "left": 0.0, "level": lvl})
	_refresh_spell_hud()


func _cast_slot(i: int) -> void:
	if i < 0 or i >= p_spells.size():
		return
	var ps: Dictionary = p_spells[i]
	if float(ps["left"]) > 0.0:
		return
	var owned: Dictionary = ps["owned"]
	var e: Dictionary = owned["effect"]
	var kind := String(e.get("kind", "bolt"))
	var dtype := String(e.get("dtype", "Arcane"))
	var dmg := float(e.get("damage", 8.0)) * float(cfg("spell_damage_scale", 0.9)) * _damage_mult()
	var lvl := int(ps["level"])
	ps["left"] = float(ps["cd"]) * (0.8 if _art("charges") > 0.0 else 1.0)
	casts += 1
	match kind:
		"bolt", "hex", "melee":
			var n := maxi(1, mini(4, int(e.get("targets", 1)))) + (1 if kind == "bolt" else 0)
			for k in n:
				var ang := (k - (n - 1) * 0.5) * 0.18
				_spawn_shot(p_pos + Vector2(26, 0), Vector2.RIGHT.rotated(ang) * 720.0, dmg * 0.7, dtype, 15.0, 0, true)
		"beam":
			var beam := Line2D.new()
			beam.width = 34.0
			beam.default_color = Color(Items.type_color(dtype), 0.9)
			beam.add_point(p_pos + Vector2(30, 0))
			beam.add_point(p_pos + Vector2(W, 0))
			beam.z_index = 7
			ents.add_child(beam)
			fx.append({"node": beam, "left": 0.25, "kind": "beam"})
			for en in enemies.duplicate():
				if en["pos"].x > p_pos.x and absf(en["pos"].y - p_pos.y) < 17.0 + en["radius"]:
					_damage_enemy(en, dmg, dtype)
			_shake(4.0)
		"blast", "burst", "patch":
			var at := p_pos + Vector2(260, 0)
			var best := 1e9
			for en in enemies:
				if en["pos"].x > p_pos.x + 40.0 and en["pos"].x < scroll_x + W + 40.0:
					var d: float = en["pos"].distance_to(p_pos)
					if d < best:
						best = d
						at = en["pos"]
			_blast(at, maxf(70.0, float(e.get("radius", 90.0)) * 0.9) + 0.3 * _art("spell_radius"), dmg, dtype)
		"aura":
			auras.append({"left": maxf(4.0, float(e.get("duration", 6.0))), "tick": 0.0, "dmg": dmg * 0.35, "radius": maxf(90.0, float(e.get("radius", 120.0)) * 0.9), "dtype": dtype})
		"summon":
			var unit := String(owned.get("unit", ""))
			if unit == "" or not QUD.has_unit(unit):
				unit = "wolf"
			for k in maxi(1, mini(3, int(e.get("count", 1)))):
				_add_familiar(unit, maxf(8.0, float(e.get("duration", 12.0))), dmg * 0.5)
		"shield":
			shields += maxi(1, int(e.get("shields", 1)))
			_effect("shield_apply", p_pos, 1.4)
		"heal":
			p_hp = minf(p_max_hp, p_hp + maxf(8.0, float(e.get("amount", 10.0))))
			_effect("heal", p_pos, 1.4)
		"buff", "empower":
			buff_left = maxf(5.0, float(e.get("duration", 8.0)))
			buff_mult = 1.0 + 2.0 * float(e.get("strength", 0.25))
			_effect("buff_apply", p_pos, 1.4)
		"blink":
			var to := p_pos + Vector2(minf(300.0, float(e.get("distance", 300.0))), 0)
			to.x = minf(to.x, scroll_x + W - 80.0)
			if not _blocked(to):
				_effect("translocation", p_pos, 1.2)
				p_pos = to
				invuln = maxf(invuln, 0.8)
				_effect("translocation", p_pos, 1.2)
	Audio.play("sorcery", -4.0)
	say(String(ps["name"]).to_upper(), 0.8)


func _blast(at: Vector2, radius: float, dmg: float, dtype: String) -> void:
	_effect(dtype.to_lower(), at, radius / 28.0)
	for en in enemies.duplicate():
		if en["pos"].distance_to(at) < radius + en["radius"]:
			_damage_enemy(en, dmg, dtype)
	for b in bullets.duplicate():
		if b["pos"].distance_to(at) < radius:
			bullets.erase(b)
			b["node"].queue_free()
	_shake(5.0)


func _damage_mult() -> float:
	return (1.0 + 0.35 * int(ups.get("Arcane Edge", 0)) + 0.08 * _art("spell_damage")) * (buff_mult if buff_left > 0.0 else 1.0)


func _spells_step(dt: float) -> void:
	for ps in p_spells:
		ps["left"] = maxf(0.0, float(ps["left"]) - dt)
	buff_left = maxf(0.0, buff_left - dt)
	for a in auras.duplicate():
		a["left"] -= dt
		a["tick"] -= dt
		if a["tick"] <= 0.0:
			a["tick"] = 0.8
			_blast(p_pos, float(a["radius"]), float(a["dmg"]), String(a["dtype"]))
		if a["left"] <= 0.0:
			auras.erase(a)
	if not auto:
		for i in mini(9, p_spells.size()):
			if Input.is_action_just_pressed("slot_%d" % (i + 1)):
				_cast_slot(i)
	elif fmod(t, 1.7) < 1.0 / 60.0 * 1.5:
		for i in p_spells.size():   # the pilot casts whatever is ready
			if float(p_spells[i]["left"]) <= 0.0:
				_cast_slot(i)
				break


func _refresh_spell_hud() -> void:
	for c in spell_row.get_children():
		c.queue_free()
	for i in p_spells.size():
		var ps: Dictionary = p_spells[i]
		var box := Control.new()
		box.custom_minimum_size = Vector2(72, 84)
		spell_row.add_child(box)
		var icon := TextureRect.new()
		icon.texture = QUD.icon(String(ps["owned"]["icon"]))
		icon.size = Vector2(56, 56)
		icon.position = Vector2(8, 0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		box.add_child(icon)
		var key := _label(str(i + 1), 18, Color(0.55, 0.85, 1.0))
		key.position = Vector2(2, -4)
		box.add_child(key)
		var cd := _label("", 18, Color(1.0, 0.93, 0.35))
		cd.position = Vector2(8, 58)
		box.add_child(cd)
		box.set_meta("icon", icon)
		box.set_meta("cd", cd)


func _update_spell_hud() -> void:
	var i := 0
	for box in spell_row.get_children():
		if i >= p_spells.size():
			break
		var ps: Dictionary = p_spells[i]
		var left := float(ps["left"])
		box.get_meta("icon").modulate = Color.WHITE if left <= 0.0 else Color(0.35, 0.35, 0.35)
		box.get_meta("cd").text = "" if left <= 0.0 else "%.1f" % left
		i += 1


# ---------------------------------------------------------------- familiars and the Force pod

func _add_familiar(unit: String, duration: float, dmg: float) -> void:
	var s := Sprite2D.new()
	s.texture = QUD.unit_idle(unit)
	s.hframes = maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2.ONE * 0.8
	s.z_index = 5
	ents.add_child(s)
	familiars.append({"node": s, "angle": rng.randf() * TAU, "cd": 0.5, "unit": unit, "left": duration, "dmg": dmg})
	_effect("conjuration", p_pos, 1.2)


func _familiars_step(dt: float) -> void:
	var want := int(ups.get("Familiar", 0))
	var permanent := 0
	for f in familiars:
		if float(f["left"]) < 0.0:
			permanent += 1
	while permanent < want:
		var unit := "wolf"
		for cand in ["wolf", "bat", "spark_spirit", "ghost"]:
			if QUD.has_unit(cand):
				unit = cand
				if permanent % 2 == 0:
					break
		_add_familiar(unit, -1.0, float(cfg("bolt_damage", 3.0)) * 0.8)
		permanent += 1
	var i := 0
	for f in familiars.duplicate():
		if float(f["left"]) >= 0.0:
			f["left"] = float(f["left"]) - dt
			if float(f["left"]) <= 0.0:
				_effect("dark", f["node"].position, 0.8)
				familiars.erase(f)
				f["node"].queue_free()
				continue
		f["angle"] += dt * 2.2
		var pos: Vector2 = p_pos + Vector2(cos(f["angle"] + TAU * i / maxi(1, familiars.size())), sin(f["angle"] + TAU * i / maxi(1, familiars.size()))) * 78.0
		var n: Sprite2D = f["node"]
		n.position = pos
		n.frame = int(t / 0.2) % n.hframes
		f["cd"] -= dt
		if f["cd"] <= 0.0:
			var best: Dictionary = {}
			var bd := 520.0
			for e in enemies:
				var d: float = e["pos"].distance_to(pos)
				if d < bd:
					bd = d
					best = e
			if not best.is_empty():
				f["cd"] = 0.7
				_spawn_shot(pos, (best["pos"] - pos).normalized() * 700.0, float(f["dmg"]) * _damage_mult() * (1.0 + 0.15 * _art("summon_damage")), "physical", 8.0, 0)
		i += 1


# The Force: an eye that rides the front of the wizard and shoots with it, or is sent
# ahead to fight on its own: it eats bullets, rams what it touches and fires forward.
# F or Q sends it out and calls it back.
func _force_step(dt: float) -> void:
	var lvl := int(ups.get("Force Pod", 0))
	if lvl <= 0:
		return
	if force.is_empty():
		var unit := "floating_eyeball" if QUD.has_unit("floating_eyeball") else ("flaming_eyeball" if QUD.has_unit("flaming_eyeball") else "bat")
		var s := Sprite2D.new()
		s.texture = QUD.unit_idle(unit)
		s.hframes = maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.scale = Vector2.ONE * 1.1
		s.z_index = 6
		ents.add_child(s)
		force = {"node": s, "pos": p_pos + Vector2(46, 0), "attached": true, "cd": 0.0, "ram": 0.0}
		_effect("conjuration", force["pos"], 1.4)
		say("THE FORCE", 1.2)
	var toggle := false
	if auto:
		toggle = fmod(t, 9.0) < 1.0 / 60.0 * 1.5
	else:
		toggle = Input.is_action_just_pressed("free_drive") or Input.is_action_just_pressed("quick_shop")
	if toggle:
		force["attached"] = not bool(force["attached"])
		Audio.play("teleport", -10.0)
	var fp: Vector2 = force["pos"]
	if bool(force["attached"]):
		fp = fp.lerp(p_pos + Vector2(46, 0), minf(1.0, dt * 14.0))
	else:
		var want := Vector2(minf(p_pos.x + 330.0, scroll_x + W - 60.0), p_pos.y)
		fp = fp.lerp(want, minf(1.0, dt * 3.5))
		if _blocked(fp):
			fp.y = p_pos.y
	force["pos"] = fp
	var n: Sprite2D = force["node"]
	n.position = fp
	n.frame = int(t / 0.15) % n.hframes
	n.modulate = Color(1.0, 1.0, 1.0) if bool(force["attached"]) else Color(1.0, 0.85, 0.7)
	# eats bullets
	for b in bullets.duplicate():
		if b["pos"].distance_to(fp) < 34.0:
			bullets.erase(b)
			b["node"].queue_free()
			_effect("shield_expire", fp, 0.7)
	# rams
	force["ram"] = float(force["ram"]) - dt
	if force["ram"] <= 0.0:
		force["ram"] = 0.25
		for e in enemies.duplicate():
			if e["pos"].distance_to(fp) < 34.0 + e["radius"]:
				_damage_enemy(e, (2.0 + 1.5 * lvl) * _damage_mult(), "physical")
	# fires forward on its own when detached (attached, it fires with the bolts)
	if not bool(force["attached"]):
		force["cd"] = float(force["cd"]) - dt
		if force["cd"] <= 0.0:
			force["cd"] = 0.3
			var dmg := float(cfg("bolt_damage", 3.0)) * (0.7 + 0.3 * lvl) * _damage_mult()
			_spawn_shot(fp + Vector2(20, 0), Vector2.RIGHT * 850.0, dmg, "holy", 9.0, 1 if lvl >= 2 else 0)
			if lvl >= 3:
				_spawn_shot(fp, Vector2.RIGHT.rotated(0.5) * 850.0, dmg * 0.7, "holy", 8.0, 0)
				_spawn_shot(fp, Vector2.RIGHT.rotated(-0.5) * 850.0, dmg * 0.7, "holy", 8.0, 0)


# ---------------------------------------------------------------- the run across realms, scores

func _save_progress(next_realm: int) -> void:
	var names := []
	for ps in p_spells:
		names.append(ps["name"])
	var pnames := []
	for a in party:
		pnames.append(a["comp"]["name"])
	var anames := []
	for a in p_artifacts:
		anames.append(a["name"])
	Campaign.rift = {"realm": next_realm, "score": score, "level_n": level_n, "xp": xp, "ups": ups.duplicate(), "spells": names,
		"max_hp": p_max_hp, "hp": p_hp, "shields": shields, "kills": kills, "start_realm": run_start_realm, "party": pnames, "artifacts": anames}


func _restore_progress() -> void:
	var r: Dictionary = Campaign.rift
	if r.is_empty() or int(r.get("realm", -1)) != realm:
		run_start_realm = realm
		return
	score = int(r["score"])
	level_n = int(r["level_n"])
	xp = float(r["xp"])
	ups = r["ups"].duplicate()
	p_max_hp = float(r["max_hp"])
	p_hp = minf(p_max_hp, float(r["hp"]) + 10.0)
	shields = int(r["shields"])
	kills = int(r["kills"])
	run_start_realm = int(r.get("start_realm", realm))
	for nm in r["spells"]:
		if SpellDB.by_name.has(nm):
			_learn_spell(SpellDB.by_name[nm])
	for pn in r.get("party", []):
		for c in companions:
			if c["name"] == pn:
				_recruit(c)
	for an in r.get("artifacts", []):
		if Artifacts.by_name.has(an):
			p_artifacts.append(Artifacts.make_owned(Artifacts.by_name[an]))
	_refresh_artifact_hud()
	Campaign.rift = {}


static func scores_load() -> ConfigFile:
	var c := ConfigFile.new()
	c.load("user://rifttype.cfg")
	return c


func _record_scores(cleared: bool) -> void:
	if auto:
		return   # the demo pilot's flights are not the player's
	var c := scores_load()
	var realm_score := score - score_at_start
	if realm_score > int(c.get_value("realm", "best_%d" % realm, 0)):
		c.set_value("realm", "best_%d" % realm, realm_score)
	if cleared and realm > int(c.get_value("run", "farthest", 0)):
		c.set_value("run", "farthest", realm)
	if score > int(c.get_value("run", "best", 0)):
		c.set_value("run", "best", score)
		c.set_value("run", "best_realm", realm)
		c.set_value("run", "best_from", run_start_realm)
	c.set_value("run", "plays", int(c.get_value("run", "plays", 0)) + 1)
	c.save("user://rifttype.cfg")


# ---------------------------------------------------------------- boss phases from its spells

# Each of the boss's own spells becomes a phase: melee is a charge, beams sweep, summons
# call the thing they name, storms rain from above, novas ring, gazes and clouds linger,
# anything else is an aimed spread. The boss announces what it casts.
func _boss_phases(sp: Dictionary) -> Array:
	var phases := []
	for spl in sp["spells"]:
		if not (spl is Dictionary):
			continue
		var nm := String(spl.get("name", "Attack"))
		var low := nm.to_lower()
		var dtypes: Array = spl.get("damage_type", [])
		var dtype := String(dtypes[0]) if not dtypes.is_empty() else "Dark"
		var kind: String = {"lunge": "charge", "beam": "beam", "drain": "beam", "summon": "summon", "rain": "rain", "ring": "ring", "cloud": "cloud"}.get(SpellKinds.classify(spl), "spread")
		if low == "":
			kind = "spread"
		phases.append({"kind": kind, "name": nm, "dtype": dtype, "unit": ""})
	if phases.is_empty():
		phases = [{"kind": "spread", "name": "Roar", "dtype": "Dark", "unit": ""}, {"kind": "charge", "name": "Charge", "dtype": "Physical", "unit": ""},
			{"kind": "ring", "name": "Nova", "dtype": "Dark", "unit": ""}, {"kind": "summon", "name": "Summon", "dtype": "Dark", "unit": ""}]
	return phases


func _boss_step(e: Dictionary, dt: float) -> void:
	boss_t += dt
	var p: Vector2 = e["pos"]
	var home: Vector2 = e["home"]
	var phases: Array = e["phases"]
	var ph: Dictionary = phases[boss_phase % phases.size()]
	var kind := String(ph["kind"])
	var dtype := String(ph["dtype"])
	var dmg := float(cfg("enemy_damage", 4.0)) + 0.25 * realm
	if boss_t > 4.5:
		boss_t = 0.0
		boss_phase += 1
		ph = phases[boss_phase % phases.size()]
		kind = String(ph["kind"])
		lbl_boss.text = "%s   casting %s" % [String(e["sp"]["name"]).to_upper(), String(ph["name"]).to_upper()]
		e["cast_left"] = 0.0
		e["cast_n"] = 0
	e["cast_left"] = float(e.get("cast_left", 0.0)) - dt
	match kind:
		"charge":   # a committed dash at where the wizard was when it wound up, then back
			if boss_t < 0.7:
				e["dash_to"] = Vector2(p_pos.x + 40.0, p_pos.y)
				p = p.lerp(home + Vector2(60, 0), minf(1.0, dt * 3.0))
			elif boss_t < 2.0:
				p = p.lerp(e.get("dash_to", home), minf(1.0, dt * 4.0))
			else:
				p = p.lerp(home, minf(1.0, dt * 2.5))
		"beam":
			p = p.lerp(home + Vector2(0, sin(e["t"] * 1.2) * 100.0), minf(1.0, dt * 2.0))
			if e["cast_left"] <= 0.0 and int(e["cast_n"]) < 3:
				e["cast_left"] = 1.3
				e["cast_n"] = int(e["cast_n"]) + 1
				for k in 3:
					var dir: Vector2 = (p_pos - p).normalized().rotated((k - 1) * 0.35)
					var line := Line2D.new()
					line.width = 6.0
					line.default_color = Color(Items.type_color(dtype), 0.35)
					line.add_point(p)
					line.add_point(p + dir * 2600.0)
					line.z_index = 2
					ents.add_child(line)
					beams.append({"node": line, "from": p, "dir": dir, "t": 0.0, "dmg": dmg * 1.5, "dtype": dtype, "fired": false})
		"summon":
			p = p.lerp(home, minf(1.0, dt * 2.0))
			if e["cast_left"] <= 0.0 and int(e["cast_n"]) < 1:
				e["cast_left"] = 9.0
				e["cast_n"] = 1
				var sp := _summon_species(String(e["sp"]["name"]), String(ph["name"]))
				for k in 3:
					_spawn_enemy(sp, p + Vector2(-70.0, (k - 1) * 110.0), "minion", k, 3)
				summons += 3
				_effect("conjuration", p, 2.0)
		"rain":
			p = p.lerp(home + Vector2(0, sin(e["t"] * 2.0) * 160.0), minf(1.0, dt * 2.0))
			if e["cast_left"] <= 0.0 and int(e["cast_n"]) < 14:
				e["cast_left"] = 0.22
				e["cast_n"] = int(e["cast_n"]) + 1
				var x := scroll_x + rng.randf_range(80.0, W - 80.0)
				_spawn_bullet(Vector2(x, TILE + 10.0), Vector2(rng.randf_range(-40.0, 40.0), 300.0), dmg, dtype)
		"ring":
			p = p.lerp(home, minf(1.0, dt * 2.0))
			if e["cast_left"] <= 0.0 and int(e["cast_n"]) < 2:
				e["cast_left"] = 2.0
				e["cast_n"] = int(e["cast_n"]) + 1
				var off := 0.0 if int(e["cast_n"]) == 1 else TAU / 28.0
				for k in 14:
					var a := TAU * k / 14.0 + off
					_spawn_bullet(p, Vector2(cos(a), sin(a)) * 240.0, dmg, dtype)
				Audio.play("sorcery", -4.0)
		"cloud":
			p = p.lerp(home + Vector2(0, sin(e["t"] * 1.0) * 200.0), minf(1.0, dt * 2.0))
			if e["cast_left"] <= 0.0 and int(e["cast_n"]) < 2:
				e["cast_left"] = 2.2
				e["cast_n"] = int(e["cast_n"]) + 1
				_spawn_cloud(p + Vector2(-80.0, 0), dtype, dmg * 0.6)
		_:   # spread
			p = p.lerp(Vector2(home.x, H * 0.5 + sin(e["t"] * 1.4) * (H * 0.5 - 140.0)), minf(1.0, dt * 3.0))
			if e["cast_left"] <= 0.0 and int(e["cast_n"]) < 3:
				e["cast_left"] = 1.2
				e["cast_n"] = int(e["cast_n"]) + 1
				var dir: Vector2 = (p_pos - p).normalized()
				var speed := float(cfg("enemy_bolt_speed", 330.0)) + 6.0 * realm
				for k in 5:
					_spawn_bullet(p, dir.rotated((k - 2) * 0.22) * speed, dmg, dtype)
	e["pos"] = p


# A lingering cloud drifts left; standing in it hurts every half second.
func _spawn_cloud(at: Vector2, dtype: String, dmg: float) -> void:
	var s := Sprite2D.new()
	s.texture = Items.effect_strip(dtype)
	s.hframes = 6
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = at
	s.scale = Vector2.ONE * 3.2
	s.modulate = Color(1, 1, 1, 0.55)
	s.z_index = 3
	ents.add_child(s)
	clouds.append({"node": s, "pos": at, "left": 7.0, "tick": 0.0, "dmg": dmg, "dtype": dtype})


func _clouds_step(dt: float) -> void:
	for c in clouds.duplicate():
		c["left"] -= dt
		c["tick"] -= dt
		c["pos"] += Vector2(-45.0, sin(c["left"] * 2.0) * 20.0) * dt
		var n: Sprite2D = c["node"]
		n.position = c["pos"]
		n.frame = int(c["left"] / 0.12) % 6
		if c["tick"] <= 0.0 and c["pos"].distance_to(p_pos) < 80.0:
			c["tick"] = 0.9
			invuln = 0.0
			_hurt(float(c["dmg"]) * 0.7, String(c["dtype"]))
		if c["left"] <= 0.0 or c["pos"].x < scroll_x - 200.0:
			clouds.erase(c)
			n.queue_free()


# ---------------------------------------------------------------- every ability, from the game's data

# What a spell does here: see SpellKinds.classify (kept out of this script so the feedback
# panel and the showcase can use it without depending on the whole level).
static func classify_spell(spl: Dictionary) -> String:
	return SpellKinds.classify(spl)


# The full monster record (monsters.json) for a name, if the game knows it.
func _monster_record(name: String) -> Dictionary:
	for m in QUD.monsters:
		if String(m.get("name", "")) == name:
			return m
	return {}


func _species_from_record(m: Dictionary) -> Dictionary:
	var asset: Array = m.get("asset", [])
	if asset.size() < 2 or not QUD.has_unit(asset[asset.size() - 1]):
		return {}
	var unit := String(asset[asset.size() - 1])
	if species_cache.has(unit):
		return species_cache[unit]
	var info := QUD.unit_info(unit)
	var sp := {"name": m["name"], "unit": unit, "hp": float(m.get("max_hp", 10)), "flying": bool(m.get("flying", false)),
		"stationary": bool(m.get("stationary", false)), "lair": bool(m.get("is_lair", false)), "boss": bool(m.get("is_boss", false)),
		"big": int(info.get("frame_size", 60)) > 60, "frame_size": int(info.get("frame_size", 60)), "frames": int(info.get("idle_frames", 1)),
		"spells": m.get("spells", []), "shields": int(m.get("shields", 0)), "tags": m.get("tags", []), "buffs": m.get("buffs", [])}
	species_cache[unit] = sp
	return sp


func _species_for_unit(unit: String) -> Dictionary:
	for sp in species:
		if sp["unit"] == unit:
			return sp
	if species_cache.has(unit):
		return species_cache[unit]
	for m in QUD.monsters:
		var asset: Array = m.get("asset", [])
		if not asset.is_empty() and String(asset[asset.size() - 1]) == unit:
			return _species_from_record(m)
	return {}


func _monster_by_loose_name(n: String) -> Dictionary:
	var low := n.to_lower().strip_edges()
	var forms := [low, low.trim_suffix("s"), low.trim_suffix("es"), low.replace("ies", "y"), low.replace("ves", "f"), low.replace("wolves", "wolf")]
	for m in QUD.monsters:
		var mn := String(m.get("name", "")).to_lower()
		for f in forms:
			if mn == f:
				return m
	# last word alone ("Summon 3 Bone Knight Archers" -> "Bone Knight Archer")
	for m in QUD.monsters:
		var mn := String(m.get("name", "")).to_lower()
		for f in forms:
			if f.length() > 4 and (mn.ends_with(f) or f.ends_with(mn)) and absi(mn.length() - f.length()) <= 8:
				return m
	return {}


# What a summoning spell brings: read off the game's own text ("Summon 3 Ash Imps"),
# else the spell's name, else a small monster of the realm.
func _summon_species(caster_name: String, spell_name: String) -> Dictionary:
	var key := caster_name + "|" + spell_name
	if summon_cache.has(key):
		return summon_cache[key]
	var found: Dictionary = {}
	var rec := _monster_record(caster_name)
	var text := ""
	for spl in rec.get("spells", []):
		if String(spl.get("name", "")) == spell_name:
			var d = spl.get("description", {})
			text = String(d.get("text", "")) if d is Dictionary else String(d)
	if text != "":
		var re := RegEx.new()
		re.compile("(?i)summons?\\s+(?:a|an|\\d+|several|some|the)?\\s*(?:temporary\\s+|ferocious\\s+|random\\s+)?([A-Za-z' -]+?)(?:\\s+(?:in|at|on|around|surrounding|from|near|to|adjacent|for|with|that|which|next)\\b|$|[.,\\n])")
		var m := re.search(text)
		if m != null:
			var mr := _monster_by_loose_name(m.get_string(1))
			if not mr.is_empty():
				found = _species_from_record(mr)
	if found.is_empty():
		var words := spell_name.to_lower().replace("summon", "").replace("call", "").replace("gather", "").strip_edges()
		if words.length() > 3:
			var mr := _monster_by_loose_name(words)
			if not mr.is_empty():
				found = _species_from_record(mr)
	if found.is_empty() or bool(found.get("big", false)):
		found = small_species[rng.randi_range(0, small_species.size() - 1)]
	summon_cache[key] = found
	return found


func _enemy_cast(e: Dictionary, spl: Dictionary) -> void:
	last_caster = e
	var p: Vector2 = e["pos"]
	var dmg := float(cfg("enemy_damage", 4.0)) + 0.25 * realm
	var dtype: String = spl["dtype"]
	var mode := String(spl["mode"])
	var kind := String(e["kind"])
	var fixed := kind in ["turret", "hive", "wall"]
	match mode:
		"bolt":
			var dir: Vector2 = (p_pos - p).normalized()
			var speed := float(cfg("enemy_bolt_speed", 330.0)) + 6.0 * realm
			_spawn_bullet(p, dir * speed, dmg, dtype)
			if e["boss"]:
				_spawn_bullet(p, dir.rotated(0.3) * speed, dmg, dtype)
				_spawn_bullet(p, dir.rotated(-0.3) * speed, dmg, dtype)
		"beam", "drain":
			var dir: Vector2 = (p_pos - p).normalized()
			var line := Line2D.new()
			line.width = 6.0
			line.default_color = Color(Items.type_color(dtype), 0.35)
			line.add_point(p)
			line.add_point(p + dir * 2600.0)
			line.z_index = 2
			ents.add_child(line)
			beams.append({"node": line, "from": p, "dir": dir, "t": 0.0 if mode == "beam" else 0.35, "dmg": dmg * (1.5 if mode == "beam" else 1.0), "dtype": dtype, "fired": false, "healer": e if mode == "drain" else null})
		"summon":
			var sp := _summon_species(String(e["sp"]["name"]), String(spl["name"]))
			var n := 3 if e["boss"] else 2
			for i in n:
				var mk := _spawn_enemy(sp, p + Vector2(-50.0, (i - (n - 1) * 0.5) * 70.0), "minion", i, n)
				mk["summoned"] = true
			_effect("conjuration", p, 1.4)
			summons += n
		"rain":
			var n := 7 if e["boss"] else 4
			for i in n:
				var x := p_pos.x + (i - (n - 1) * 0.5) * 70.0 + rng.randf_range(-20.0, 20.0)
				_spawn_bullet(Vector2(x, TILE + 10.0), Vector2(0, 260.0 + 8.0 * realm), dmg, dtype)
		"ring":
			var n := 14 if e["boss"] else 8
			for i in n:
				var a := TAU * i / n + float(e["phase"])
				_spawn_bullet(p, Vector2(cos(a), sin(a)) * 230.0, dmg, dtype)
		"cloud":
			_spawn_cloud(p + (p_pos - p).normalized() * 90.0, dtype, dmg * 0.6)
		"heal":
			for o in enemies:
				if o["pos"].distance_to(p) < 320.0 and o["hp"] < o["max_hp"]:
					o["hp"] = minf(float(o["max_hp"]), float(o["hp"]) + float(o["max_hp"]) * 0.2)
					_effect("heal", o["pos"], 0.9)
			if e["boss"]:
				_refresh_boss_bar()
		"shield":
			for o in enemies:
				if o["pos"].distance_to(p) < 320.0 and int(o["shields"]) < 3:
					o["shields"] = int(o["shields"]) + 1
					_effect("shield_apply", o["pos"], 0.9)
		"blink":
			if not fixed and not e["boss"]:
				_effect("translocation", p, 1.0)
				var to := Vector2(clampf(p_pos.x + rng.randf_range(260.0, 520.0), scroll_x + 200.0, scroll_x + W - 60.0), clampf(p_pos.y + rng.randf_range(-140.0, 140.0), TILE + 40.0, H - TILE - 40.0))
				e["pos"] = to
				e["anchor"] = to
				e["t"] = 0.0
				_effect("translocation", to, 1.0)
		"buff":
			e["haste"] = 4.0
			_effect("buff_apply", p, 1.0)
		"lunge":
			if not fixed and p.distance_to(p_pos) < 460.0:
				e["lunge_to"] = p_pos
				e["lunge_t"] = 0.55
	if mode != "lunge":
		abilities[mode] = int(abilities.get(mode, 0)) + 1


# ---------------------------------------------------------------- the tavern and the party

func _load_companions() -> void:
	companions.clear()
	var f := FileAccess.open("res://qud/data/companions.json", FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Array):
		return
	for c in parsed:
		var asset: Array = c.get("asset", [])
		if asset.size() < 2 or not QUD.has_unit(asset[asset.size() - 1]):
			continue
		companions.append(c)


func _place_tavern() -> void:
	if companions.is_empty():
		return
	var c := int(level_len * 0.45 / TILE)
	var best_r := -1
	for r in range(3, ROWS - 3):
		if _col_char(c, r) != "#" and _col_char(c + 1, r) != "#" and _col_char(c - 1, r) != "#":
			if best_r < 0 or absi(r - ROWS / 2) < absi(best_r - ROWS / 2):
				best_r = r
	if best_r < 0:
		return
	var s := Sprite2D.new()
	s.texture = QUD.texture("tiles/item_tavern.png")
	if s.texture == null:
		return
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2.ONE * (TILE * 1.4 / s.texture.get_width())
	s.position = Vector2(c * TILE + TILE * 0.5, best_r * TILE + TILE * 0.5)
	s.z_index = 2
	ents.add_child(s)
	var sign := _label("TAVERN", 14, Color(1.0, 0.93, 0.35))
	sign.position = Vector2(-30, -58)
	s.add_child(sign)
	taverns.append({"node": s, "pos": s.position, "used": false})


func _taverns_step(_dt: float) -> void:
	for tv in taverns:
		if bool(tv["used"]):
			continue
		var n: Sprite2D = tv["node"]
		n.modulate = Color(1, 1, 1, 0.75 + 0.25 * sin(t * 4.0))
		if tv["pos"].distance_to(p_pos) < 56.0:
			tv["used"] = true
			n.modulate = Color(0.5, 0.5, 0.5)
			_open_tavern()


func _open_tavern() -> void:
	var pool := companions.duplicate()
	for a in party:
		pool = pool.filter(func(c): return c["name"] != a["comp"]["name"])
	if pool.is_empty() or party.size() >= MAX_PARTY:
		say("THE TAVERN IS FULL", 1.2)
		return
	state = TAVERN
	tavern_offer.clear()
	while tavern_offer.size() < 3 and not pool.is_empty():
		var j := rng.randi_range(0, pool.size() - 1)
		tavern_offer.append(pool[j])
		pool.remove_at(j)
	Audio.play("learn_spell", -4.0)
	cards = Control.new()
	cards.size = Vector2(SW, SH)
	hud.add_child(cards)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Vector2(SW, SH)
	cards.add_child(dim)
	var title := _label("THE TAVERN   an adventurer joins your party  (1, 2, 3   or 4 to drink alone)", 40, Color(1.0, 0.93, 0.35))
	title.position = Vector2(0, 200)
	title.size = Vector2(SW, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cards.add_child(title)
	var cw := 480.0
	var x0 := (SW - (cw * tavern_offer.size() + 30.0 * (tavern_offer.size() - 1))) * 0.5
	for i in tavern_offer.size():
		var c: Dictionary = tavern_offer[i]
		var panel := PanelContainer.new()
		panel.position = Vector2(x0 + i * (cw + 30.0), 300)
		panel.size = Vector2(cw, 440)
		cards.add_child(panel)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 8)
		panel.add_child(vb)
		vb.add_child(_label("%d" % (i + 1), 40, Color(0.55, 0.85, 1.0)))
		var unit := String(c["asset"][c["asset"].size() - 1])
		var tr := TextureRect.new()
		var strip := QUD.unit_idle(unit)
		if strip != null:
			var one := AtlasTexture.new()   # the first frame of the idle strip
			one.atlas = strip
			var fw := float(strip.get_width()) / maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
			one.region = Rect2(0, 0, fw, strip.get_height())
			tr.texture = one
		tr.custom_minimum_size = Vector2(120, 120)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		vb.add_child(tr)
		var cs: Dictionary = c.get("companion_stats", {})
		vb.add_child(_label("%s   HP %d%s" % [String(c["name"]).to_upper(), int(cs.get("minion_health", c.get("max_hp", 50))), ("   shields %d" % int(cs.get("shields", 0))) if int(cs.get("shields", 0)) > 0 else ""], 26, Color(0.95, 0.7, 1.0)))
		var lines := []
		for spl in c.get("spells", []):
			lines.append("%s (%s)" % [String(spl.get("name", "")), SpellKinds.classify(spl)])
		var bl := _label(", ".join(lines), 18, Color(0.8, 0.8, 0.8))
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size = Vector2(cw - 40, 0)
		vb.add_child(bl)
		var dtext := _passives_text(c)
		if dtext.length() > 220:
			dtext = dtext.substr(0, 217) + "..."
		var dl := _label(dtext, 16, Color(0.75, 0.75, 0.6))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(cw - 40, 0)
		vb.add_child(dl)


func _tavern_pick(i: int) -> void:
	if cards != null:
		cards.queue_free()
		cards = null
	state = PLAYING
	invuln = maxf(invuln, 0.8)
	if i < 0 or i >= tavern_offer.size():
		return
	_recruit(tavern_offer[i])
	say("%s JOINS THE PARTY" % String(tavern_offer[i]["name"]).to_upper(), 1.6)


func _recruit(c: Dictionary) -> void:
	var unit := String(c["asset"][c["asset"].size() - 1])
	var node := Node2D.new()
	var s := Sprite2D.new()
	s.texture = QUD.unit_idle(unit)
	s.hframes = maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.add_child(s)
	node.z_index = 5
	node.position = p_pos + Vector2(-80, 0)
	ents.add_child(node)
	var cs: Dictionary = c.get("companion_stats", {})
	var hp := float(cs.get("minion_health", c.get("max_hp", 50))) * float(cfg("party_hp_scale", 0.4))
	var buffs := []
	for b in c.get("buffs", []):
		if b is Dictionary:
			buffs.append(String(b.get("class", "")))
	var a := {"node": node, "sprite": s, "comp": c, "pos": node.position, "hp": hp, "max_hp": hp, "shields": int(cs.get("shields", c.get("shields", 0))),
		"dmg": float(cs.get("minion_damage", 10)) * float(cfg("party_damage_scale", 0.5)), "spells": [], "flash": 0.0, "hurt_cd": 0.0, "lunge_t": 0.0, "lunge_to": Vector2.ZERO,
		"buffs": buffs, "tags": c.get("tags", []), "reinc": 0, "bonus_dmg": 0.0, "enraged": 0.0, "enrage_used": false, "resist": {}, "aura_t": rng.randf(), "regen_t": 0.0}
	for spl in c.get("spells", []):
		if not (spl is Dictionary):
			continue
		var cd := float(spl.get("cool_down", 0))
		var mode := SpellKinds.classify(spl)
		if cd <= 0.0:
			cd = 2.5 if mode == "lunge" else 4.0
		var dtypes: Array = spl.get("damage_type", [])
		a["spells"].append({"name": String(spl.get("name", "")), "mode": mode, "cd": cd * 1.2, "left": rng.randf() * cd, "dtype": String(dtypes[0]) if not dtypes.is_empty() else "Holy"})
	party.append(a)
	_effect("conjuration", node.position, 1.4)
	_refresh_party_hud()


func _party_step(dt: float) -> void:
	var i := 0
	for a in party.duplicate():
		var slot: Vector2 = PARTY_SLOTS[i % PARTY_SLOTS.size()]
		var want := p_pos + slot
		want.x = maxf(want.x, scroll_x + 30.0)
		if _blocked(want):
			want = p_pos + Vector2(-40.0, 0)
		var p: Vector2 = a["pos"]
		if float(a["lunge_t"]) > 0.0:
			a["lunge_t"] = float(a["lunge_t"]) - dt
			p = p.move_toward(a["lunge_to"], 760.0 * dt)
			for e in enemies.duplicate():
				if e["pos"].distance_to(p) < e["radius"] + 22.0:
					_damage_enemy(e, float(a["dmg"]) * 1.2, "physical")
					var th := _thorns(e)
					if not th.is_empty():
						a["hurt_cd"] = 0.0
						_hurt_ally(a, float(th["dmg"]), String(th["dtype"]))
						_ability("thorns")
					a["lunge_t"] = 0.0
					break
		else:
			p = p.lerp(want, minf(1.0, dt * 6.0))
		a["pos"] = p
		a["node"].position = p
		var s: Sprite2D = a["sprite"]
		s.frame = int(t / 0.2) % s.hframes
		a["flash"] = maxf(0.0, float(a["flash"]) - dt)
		a["hurt_cd"] = maxf(0.0, float(a["hurt_cd"]) - dt)
		s.modulate = Color(1.0, 0.5, 0.5) if a["flash"] > 0.0 else (Color(1.0, 0.6, 0.4) if float(a["enraged"]) > 0.0 else (Color(0.8, 1.0, 1.0) if int(a["shields"]) > 0 else Color.WHITE))
		_ally_passives(a, dt)
		# what they know
		for spl in a["spells"]:
			spl["left"] = float(spl["left"]) - dt * (2.0 if float(a["enraged"]) > 0.0 else 1.0)
			if spl["left"] <= 0.0:
				if _ally_cast(a, spl):
					spl["left"] = float(spl["cd"])
		# what hits them
		if float(a["hurt_cd"]) <= 0.0:
			for b in bullets.duplicate():
				if b["pos"].distance_to(p) < 26.0:
					_hurt_ally(a, float(b["dmg"]), String(b["dtype"]))
					bullets.erase(b)
					b["node"].queue_free()
					break
			for e in enemies:
				if e["pos"].distance_to(p) < float(e["radius"]) + 18.0:
					_hurt_ally(a, float(cfg("contact_damage", 3.0)), "Physical")
					break
		i += 1


func _hurt_ally(a: Dictionary, dmg: float, dtype: String) -> void:
	a["hurt_cd"] = 0.8
	a["flash"] = 0.2
	var buffs: Array = a["buffs"]
	if "QuickmoveBuff" in buffs and rng.randf() < 0.5:   # Quickstep: half of what comes at the hunter misses
		_effect("translocation", a["pos"], 0.7)
		_passive("Quickstep")
		return
	if int(a["shields"]) > 0:
		a["shields"] = int(a["shields"]) - 1
		_effect("shield_expire", a["pos"], 0.9)
		return
	var resist: Dictionary = a["resist"]
	if float(resist.get(dtype, 0.0)) > 0.0:
		dmg *= 0.5   # Adaptive Armor / Berserker Rage: the type that hurt it last hurts half as much
	a["hp"] = float(a["hp"]) - dmg
	_effect(dtype.to_lower(), a["pos"], 0.9)
	if "AdaptiveArmorBuff" in buffs or "BerserkerRageBuff" in buffs:
		resist[dtype] = 3.0
		_passive("Adaptive Armor" if "AdaptiveArmorBuff" in buffs else "Berserker Rage")
	if "BerserkerRageBuff" in buffs:
		a["bonus_dmg"] = minf(10.0, float(a["bonus_dmg"]) + 1.0)
	if "BerserkerEnrageBuff" in buffs and not bool(a["enrage_used"]) and float(a["hp"]) < float(a["max_hp"]) * 0.5:
		a["enrage_used"] = true
		a["enraged"] = 10.0
		_effect("buff_apply", a["pos"], 1.4)
		say("%s IS BERSERK" % String(a["comp"]["name"]).to_upper(), 1.4)
		_passive("Enrage")
	if "TeleportOnDamage" in buffs and float(a["hp"]) > 0.0:   # Evasion: away, and a shield
		_effect("translocation", a["pos"], 0.9)
		a["pos"] = Vector2(clampf(a["pos"].x + rng.randf_range(-120.0, 120.0), scroll_x + 40.0, scroll_x + W - 40.0), clampf(a["pos"].y + rng.randf_range(-120.0, 120.0), TILE + 30.0, H - TILE - 30.0))
		a["shields"] = int(a["shields"]) + 1
		_passive("Evasion")
	if a["hp"] <= 0.0:
		if int(a["reinc"]) > 0:   # Encore: the Bard comes back for another number
			a["reinc"] = int(a["reinc"]) - 1
			a["hp"] = float(a["max_hp"])
			_effect("holy", a["pos"], 1.8)
			say("ENCORE", 1.4)
			_passive("Encore")
			return
		say("%s FALLS" % String(a["comp"]["name"]).to_upper(), 1.6)
		_effect("dark", a["pos"], 1.8)
		Audio.play("death_enemy", -2.0)
		var where: Vector2 = a["pos"]
		var living: bool = "Living" in a["tags"]
		party.erase(a)
		a["node"].queue_free()
		_refresh_party_hud()
		if living:
			for v in party:
				if "ValkyrieOath" in v["buffs"]:   # the Valkyrie takes the fallen one's place and acts at once
					_effect("holy", v["pos"], 1.0)
					v["pos"] = where
					_effect("holy", where, 1.4)
					for spl in v["spells"]:
						spl["left"] = 0.0
					_passive("Valkyrie's Oath")


func _nearest_enemy(from: Vector2, max_d: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_d
	for e in enemies:
		if e["pos"].x < scroll_x - 40.0 or e["pos"].x > scroll_x + W + 40.0:
			continue
		var d: float = e["pos"].distance_to(from)
		if d < bd:
			bd = d
			best = e
	return best


func _ally_cast(a: Dictionary, spl: Dictionary) -> bool:
	var p: Vector2 = a["pos"]
	var dmg := (float(a["dmg"]) + float(a["bonus_dmg"])) * (2.0 if float(a["enraged"]) > 0.0 else 1.0)
	var dtype := String(spl["dtype"])
	var target := _nearest_enemy(p, 620.0)
	if "SilveredBuff" in a["buffs"] and not target.is_empty():   # silvered weapons burn the unholy
		for tg in target["sp"].get("tags", []):
			if String(tg) in ["Blood", "Dark", "Undead"]:
				_damage_enemy(target, dmg * 0.8, "holy")
				_effect("holy", target["pos"], 1.0)
				_passive("Silvered")
				break
	if "EncoreBuff" in a["buffs"] and rng.randf() < 0.06 * (party.size() + 1) and int(a["reinc"]) < 2:
		a["reinc"] = int(a["reinc"]) + 1
		_effect("holy", p, 1.0)
		_passive("Encore earned")
	match String(spl["mode"]):
		"lunge":
			if target.is_empty() or target["pos"].distance_to(p) > 300.0:
				return false
			a["lunge_to"] = target["pos"]
			a["lunge_t"] = 0.5
		"bolt", "cloud", "rain", "ring", "blink":
			if target.is_empty():
				return false
			var n := 3 if String(spl["mode"]) in ["rain", "ring"] else 1
			for k in n:
				_spawn_shot(p, (target["pos"] - p).normalized().rotated((k - (n - 1) * 0.5) * 0.2) * 720.0, dmg * 0.6, dtype, 11.0, 0, true)
		"beam", "drain":
			if target.is_empty():
				return false
			var beam := Line2D.new()
			beam.width = 22.0
			beam.default_color = Color(Items.type_color(dtype), 0.85)
			beam.add_point(p)
			beam.add_point(p + (target["pos"] - p).normalized() * W)
			beam.z_index = 7
			ents.add_child(beam)
			fx.append({"node": beam, "left": 0.2, "kind": "beam"})
			var dir: Vector2 = (target["pos"] - p).normalized()
			for e in enemies.duplicate():
				var rel: Vector2 = e["pos"] - p
				if rel.dot(dir) > 0.0 and absf(rel.cross(dir)) < 16.0 + e["radius"]:
					_damage_enemy(e, dmg * 0.8, dtype)
			if String(spl["mode"]) == "drain":
				a["hp"] = minf(float(a["max_hp"]), float(a["hp"]) + dmg * 0.4)
		"summon":
			var sp := _summon_species(String(a["comp"]["name"]), String(spl["name"]))
			_add_familiar(String(sp["unit"]), 16.0, dmg * 0.5)
		"heal":
			var did := false
			if p_hp < p_max_hp:
				p_hp = minf(p_max_hp, p_hp + 6.0 + realm * 0.5)
				_effect("heal", p_pos, 1.0)
				did = true
			for o in party:
				if float(o["hp"]) < float(o["max_hp"]):
					o["hp"] = minf(float(o["max_hp"]), float(o["hp"]) + float(o["max_hp"]) * 0.25)
					_effect("heal", o["pos"], 0.8)
					did = true
			if not did:
				return false
		"shield":
			if shields >= 3:
				return false
			shields += 1
			_effect("shield_apply", p_pos, 1.0)
		"buff":
			buff_left = maxf(buff_left, 4.0)
			buff_mult = maxf(buff_mult, 1.3)
			_effect("buff_apply", p_pos, 0.9)
	party_casts += 1
	return true


func _refresh_party_hud() -> void:
	for c in party_row.get_children():
		c.queue_free()
	for a in party:
		var l := _label("", 18, Color(0.95, 0.7, 1.0))
		party_row.add_child(l)
		a["label"] = l


func _update_party_hud() -> void:
	for a in party:
		if a.has("label") and is_instance_valid(a["label"]):
			a["label"].text = "%s  %d/%d%s" % [String(a["comp"]["name"]), int(a["hp"]), int(a["max_hp"]), ("  +%d" % int(a["shields"])) if int(a["shields"]) > 0 else ""]


# ---------------------------------------------------------------- artifacts and chests

# What an owned artifact's effect means in the shooter: damage, HP, speed, shields,
# heal on kill, wider blasts and beams, longer buffs, stronger and more familiars.
func _art(key: String) -> float:
	var total := 0.0
	for a in p_artifacts:
		total += float(a["effect"].get(key, 0.0))
	return total


func _spawn_chest(at: Vector2, big: bool) -> void:
	var s := Sprite2D.new()
	s.texture = QUD.texture("tiles/item_equipment_chest.png")
	if s.texture == null:
		return
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2.ONE * (1.3 if big else 1.0)
	s.position = Vector2(clampf(at.x, scroll_x + 120.0, scroll_x + W - 120.0), clampf(at.y, TILE + 50.0, H - TILE - 50.0))
	s.z_index = 2
	ents.add_child(s)
	var sign := _label("CHEST", 14, Color(1.0, 0.93, 0.35))
	sign.position = Vector2(-26, -50)
	s.add_child(sign)
	chests.append({"node": s, "pos": s.position, "vel": Vector2(-40.0, 0), "big": big})
	_effect("holy", s.position, 1.4)


func _chests_step(dt: float) -> void:
	for c in chests.duplicate():
		if state == PLAYING:
			c["pos"] += c["vel"] * dt
		c["pos"].x = maxf(c["pos"].x, scroll_x + 60.0)
		c["node"].position = c["pos"]
		c["node"].modulate = Color(1, 1, 1, 0.8 + 0.2 * sin(t * 5.0))
		if c["pos"].distance_to(p_pos) < 50.0:
			chests.erase(c)
			c["node"].queue_free()
			_open_chest()
		elif c["pos"].x < scroll_x - 100.0:
			chests.erase(c)
			c["node"].queue_free()


func _open_chest() -> void:
	var owned_names := []
	for a in p_artifacts:
		owned_names.append(a["name"])
	var a := Artifacts.random(rng, owned_names)
	if a.is_empty():
		return
	var owned := Artifacts.make_owned(a)
	p_artifacts.append(owned)
	_apply_artifact(owned)
	_refresh_artifact_hud()
	Audio.play("learn_spell", -2.0)
	state = ARTIFACT
	artifact_t = 0.0
	cards = Control.new()
	cards.size = Vector2(SW, SH)
	hud.add_child(cards)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.size = Vector2(SW, SH)
	cards.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(SW * 0.5 - 380, 300)
	panel.size = Vector2(760, 380)
	cards.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(_label("ARTIFACT", 24, Color(0.55, 0.85, 1.0)))
	var icon := TextureRect.new()
	icon.texture = Artifacts.icon(a)
	icon.custom_minimum_size = Vector2(96, 96)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vb.add_child(icon)
	vb.add_child(_label(String(a["name"]).to_upper(), 34, Color(1.0, 0.93, 0.35)))
	vb.add_child(_label(String(owned["label"]), 24, Color(0.95, 0.7, 1.0)))
	var d := String(owned.get("desc", ""))
	if d.length() > 220:
		d = d.substr(0, 217) + "..."
	var dl := _label(d, 18, Color(0.8, 0.8, 0.8))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(720, 0)
	vb.add_child(dl)
	vb.add_child(_label("enter to fly on", 16, Color(0.6, 0.6, 0.6)))


func _apply_artifact(owned: Dictionary) -> void:
	var e: Dictionary = owned["effect"]
	if e.has("max_hp"):
		p_max_hp += float(e["max_hp"])
		p_hp = minf(p_max_hp, p_hp + float(e["max_hp"]))
	if e.has("lap_shield"):
		shields += int(e["lap_shield"])


func _close_chest() -> void:
	if cards != null:
		cards.queue_free()
		cards = null
	state = PLAYING if not boss_dead_flag else CLEARED
	invuln = maxf(invuln, 0.8)


func _refresh_artifact_hud() -> void:
	for c in artifact_row.get_children():
		c.queue_free()
	for a in p_artifacts:
		var icon := TextureRect.new()
		icon.texture = QUD.icon(String(a["icon"]))
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.tooltip_text = "%s: %s" % [a["name"], a["label"]]
		artifact_row.add_child(icon)


# ---------------------------------------------------------------- the rifts after the boss

func _realm_dumps(r: int) -> Array:
	var index: Array = []
	var f := FileAccess.open("res://qud/levels/index.json", FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Array:
			index = parsed
	var files := []
	for e in index:
		if int(e.get("difficulty", 0)) == r:
			files.append(String(e["file"]))
	if files.is_empty():
		for e in index:
			files.append(String(e["file"]))
	var dumps := []
	for fn in files:
		var d := FileAccess.open("res://qud/levels/" + fn, FileAccess.READ)
		if d == null:
			continue
		var lv = JSON.parse_string(d.get_as_text())
		if lv is Dictionary:
			dumps.append(lv)
	return dumps


func _dump_species(lv: Dictionary, limit: int) -> Array:
	var out := []
	var seen := {}
	for u in lv.get("units", []):
		var asset: Array = u.get("asset", [])
		if asset.is_empty():
			continue
		var unit := String(asset[asset.size() - 1])
		if not QUD.has_unit(unit) or seen.has(unit) or bool(u.get("is_lair", false)):
			continue
		if int(QUD.unit_info(unit).get("frame_size", 60)) > 60:
			continue
		seen[unit] = true
		out.append({"name": u.get("name", unit), "unit": unit})
		if out.size() >= limit:
			break
	return out


# Three rifts, one per dump of the next realm, each ringed by the monsters that wait
# behind it. Fly into one to choose.
func _open_rifts() -> void:
	var nxt := _realm_dumps(realm + 1)
	if nxt.is_empty():
		nxt = _realm_dumps(realm)
	var n := mini(3, nxt.size())
	for k in n:
		var lv: Dictionary = nxt[k]
		var pos := Vector2(scroll_x + W * 0.72, H * (0.5 + (k - (n - 1) * 0.5) * 0.3))
		var s := Sprite2D.new()
		s.texture = QUD.texture("tiles/portal_active_portal.png")
		if s.texture != null:
			s.hframes = maxi(1, int(s.texture.get_width() / s.texture.get_height()))   # the sheet is frames across
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.scale = Vector2.ONE * 1.8
		s.position = pos
		s.z_index = 2
		ents.add_child(s)
		var sign := _label("RIFT   %s" % String(lv.get("tileset", "")).capitalize(), 16, Color(1.0, 0.93, 0.35))
		sign.position = pos + Vector2(-50, 62)
		sign.z_index = 4
		ents.add_child(sign)
		rift_signs.append(sign)
		var ring := []
		var sps := _dump_species(lv, 4)
		for i in sps.size():
			var m := Sprite2D.new()
			m.texture = QUD.unit_idle(sps[i]["unit"])
			m.hframes = maxi(1, int(QUD.unit_info(sps[i]["unit"]).get("idle_frames", 1)))
			m.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			m.scale = Vector2.ONE * 0.8
			m.z_index = 3
			m.modulate = Color(0.85, 0.85, 1.0, 0.9)
			ents.add_child(m)
			ring.append(m)
		rifts.append({"node": s, "pos": pos, "dump": k, "ring": ring, "phase": rng.randf() * TAU, "tileset": String(lv.get("tileset", ""))})
	_effect("translocation", Vector2(scroll_x + W * 0.72, H * 0.5), 2.0)
	say("THE RIFTS OPEN   fly into one", 3.0)


func _rifts_step(dt: float) -> void:
	for r in rifts:
		r["phase"] += dt * 1.3
		var n: Sprite2D = r["node"]
		n.frame = int(t / 0.12) % maxi(1, n.hframes)
		n.modulate = Color(1, 1, 1, 0.85 + 0.15 * sin(t * 6.0))
		var ring: Array = r["ring"]
		for i in ring.size():
			var a: float = float(r["phase"]) + TAU * i / maxi(1, ring.size())
			var m: Sprite2D = ring[i]
			m.position = r["pos"] + Vector2(cos(a), sin(a) * 0.55) * 78.0
			m.frame = int(t / 0.2) % m.hframes
			m.flip_h = sin(a) > 0.0
			m.z_index = 3 if cos(a + PI * 0.5) > 0.0 else 1
		if state == CLEARED and r["pos"].distance_to(p_pos) < 44.0:
			_enter_rift(r)
			return


func _enter_rift(r: Dictionary) -> void:
	chosen_dump = int(r["dump"])
	_effect("translocation", p_pos, 1.6)
	Audio.play("teleport", -4.0)
	_intermission()


# ---------------------------------------------------------------- transition screens

func _intermission() -> void:
	state = INTERMISSION
	intermission_t = 0.0
	if cards != null:
		cards.queue_free()
	cards = Control.new()
	cards.size = Vector2(SW, SH)
	hud.add_child(cards)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.92)
	dim.size = Vector2(SW, SH)
	cards.add_child(dim)
	var kinds := ["summary", "bestiary", "party", "carry", "preview"]
	if slain_names.is_empty():
		kinds.erase("bestiary")
	if p_artifacts.is_empty() and p_spells.is_empty():
		kinds.erase("carry")
	var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
	intermission_kind = kind
	var vb := VBoxContainer.new()
	vb.position = Vector2(260, 180)
	vb.add_theme_constant_override("separation", 14)
	cards.add_child(vb)
	match kind:
		"summary":
			vb.add_child(_label("REALM %d CLEARED" % realm, 64, Color(1.0, 0.93, 0.35)))
			vb.add_child(_label("%s   in %d seconds" % [String(seg_grids[0]["tileset"]).capitalize(), int(t)], 28, Color(0.8, 0.8, 0.8)))
			vb.add_child(_label("%d slain     %d summoned things     score %d     level %d" % [kills, summons, score, level_n], 28))
			vb.add_child(_label("took %s" % _took_text(), 22, Color(0.7, 0.7, 0.7)))
		"bestiary":
			var nm: String = slain_names.keys()[rng.randi_range(0, slain_names.size() - 1)]
			var sp := _species_by_name(nm)
			vb.add_child(_label("BESTIARY", 30, Color(0.55, 0.85, 1.0)))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 40)
			vb.add_child(row)
			if not sp.is_empty():
				row.add_child(_portrait(String(sp["unit"]), 180))
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 8)
			row.add_child(col)
			col.add_child(_label(nm.to_upper(), 48, Color(1.0, 0.93, 0.35)))
			col.add_child(_label("you slew %d this realm" % int(slain_names[nm]), 26))
			var lines := []
			for spl in sp.get("spells", []):
				if spl is Dictionary:
					lines.append("%s (%s)" % [String(spl.get("name", "")), SpellKinds.classify(spl)])
			var bl := _label(", ".join(lines) if not lines.is_empty() else "no spells: it just bit", 20, Color(0.8, 0.8, 0.8))
			bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bl.custom_minimum_size = Vector2(900, 0)
			col.add_child(bl)
			col.add_child(_label("HP %d%s%s" % [int(sp.get("hp", 0)), "   flies" if bool(sp.get("flying", false)) else "", "   shielded" if int(sp.get("shields", 0)) > 0 else ""], 20, Color(0.7, 0.7, 0.7)))
		"party":
			vb.add_child(_label("THE PARTY" if not party.is_empty() else "YOU FLY ALONE", 48, Color(1.0, 0.93, 0.35)))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 50)
			vb.add_child(row)
			row.add_child(_portrait(p_sprite.texture.resource_path.get_file().trim_suffix("_idle.png") if p_sprite.texture != null else "player", 150))
			for a in party:
				var col := VBoxContainer.new()
				col.add_child(_portrait(String(a["comp"]["asset"][a["comp"]["asset"].size() - 1]), 150))
				col.add_child(_label("%s  %d/%d" % [String(a["comp"]["name"]), int(a["hp"]), int(a["max_hp"])], 20, Color(0.95, 0.7, 1.0)))
				row.add_child(col)
			vb.add_child(_label("the tavern waits halfway through the next realm" if party.size() < MAX_PARTY else "a full table", 22, Color(0.7, 0.7, 0.7)))
		"carry":
			vb.add_child(_label("WHAT YOU CARRY", 48, Color(1.0, 0.93, 0.35)))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 26)
			vb.add_child(row)
			for ps in p_spells:
				var col := VBoxContainer.new()
				var ic := TextureRect.new()
				ic.texture = QUD.icon(String(ps["owned"]["icon"]))
				ic.custom_minimum_size = Vector2(80, 80)
				ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				col.add_child(ic)
				col.add_child(_label(String(ps["name"]), 16))
				row.add_child(col)
			for a in p_artifacts:
				var col := VBoxContainer.new()
				var ic := TextureRect.new()
				ic.texture = QUD.icon(String(a["icon"]))
				ic.custom_minimum_size = Vector2(80, 80)
				ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				col.add_child(ic)
				col.add_child(_label(String(a["name"]), 16, Color(0.95, 0.7, 1.0)))
				row.add_child(col)
			var upl := []
			for k in ups:
				upl.append("%s x%d" % [k, int(ups[k])] if int(ups[k]) > 1 else String(k))
			var ul := _label(", ".join(upl), 22, Color(0.8, 0.8, 0.8))
			ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ul.custom_minimum_size = Vector2(1300, 0)
			vb.add_child(ul)
		"preview":
			var nxt := _realm_dumps(realm + 1)
			var lv: Dictionary = nxt[chosen_dump % nxt.size()] if not nxt.is_empty() else {}
			vb.add_child(_label("REALM %d   %s" % [realm + 1, String(lv.get("tileset", "")).capitalize()], 56, Color(1.0, 0.93, 0.35)))
			vb.add_child(_label("through the rift, these wait:", 26, Color(0.8, 0.8, 0.8)))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 40)
			vb.add_child(row)
			for sp in _dump_species(lv, 6):
				var col := VBoxContainer.new()
				col.add_child(_portrait(String(sp["unit"]), 120))
				col.add_child(_label(String(sp["name"]), 16))
				row.add_child(col)
	var hint := _label("enter to fly on", 20, Color(0.6, 0.6, 0.6))
	hint.position = Vector2(260, SH - 120)
	cards.add_child(hint)


func _took_text() -> String:
	var parts := []
	for k in damage_log:
		parts.append("%s %d" % [String(k).to_lower(), int(damage_log[k])])
	return ", ".join(parts) if not parts.is_empty() else "nothing at all"


func _species_by_name(nm: String) -> Dictionary:
	for sp in species:
		if sp["name"] == nm:
			return sp
	for sp in species_cache.values():
		if sp["name"] == nm:
			return sp
	var rec := _monster_record(nm)
	return _species_from_record(rec) if not rec.is_empty() else {}


func _portrait(unit: String, size: int) -> TextureRect:
	var tr := TextureRect.new()
	var strip := QUD.unit_idle(unit)
	if strip != null:
		var one := AtlasTexture.new()
		one.atlas = strip
		var fw := float(strip.get_width()) / maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
		one.region = Rect2(0, 0, fw, strip.get_height())
		tr.texture = one
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return tr


func _leave_intermission() -> void:
	if seconds_limit > 0.0 or frames_left >= 0:
		_finish_screenshot()   # a timed run reports here instead of flying on
		return
	_save_progress(realm + 1)
	Campaign.rift["dump"] = chosen_dump
	realm += 1
	if Campaign.active:
		Campaign.level = realm
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- monster passives
# The game's buffs, read off monsters.json (tooltip, what they spawn, counts, chances):
# things that die into other things, split, come back as something else or reincarnate,
# explode, breed, grow up, call reinforcements, hit back, regenerate, and hurt or heal
# what stands near them.

func _has_buff(e: Dictionary, cls: String) -> bool:
	for b in e["buffs"]:
		if String(b.get("class", "")) == cls:
			return true
	return false


func _ability(name: String) -> void:
	abilities[name] = int(abilities.get(name, 0)) + 1


# A species for one of a passive's "spawns" records.
func _spawn_species(rec: Dictionary) -> Dictionary:
	var mr := _monster_by_loose_name(String(rec.get("name", "")))
	if not mr.is_empty():
		var sp := _species_from_record(mr)
		if not sp.is_empty():
			return sp
	var asset: Array = rec.get("asset", [])
	if asset.size() >= 2 and QUD.has_unit(asset[asset.size() - 1]):
		var unit := String(asset[asset.size() - 1])
		var info := QUD.unit_info(unit)
		return {"name": rec.get("name", unit), "unit": unit, "hp": float(rec.get("max_hp", 10)), "flying": bool(rec.get("flying", false)),
			"stationary": bool(rec.get("stationary", false)), "lair": false, "boss": false, "big": int(info.get("frame_size", 60)) > 60,
			"frame_size": int(info.get("frame_size", 60)), "frames": int(info.get("idle_frames", 1)), "spells": [], "shields": 0, "tags": [], "buffs": []}
	return {}


func _spawn_kids(e: Dictionary, rec: Dictionary, n: int, kind := "minion", hp_scale := 1.0) -> int:
	var sp := _spawn_species(rec)
	if sp.is_empty() or bool(sp.get("big", false)) and n > 1:
		return 0
	var made := 0
	for i in n:
		var off := Vector2(rng.randf_range(-50.0, 50.0), (i - (n - 1) * 0.5) * 56.0)
		var k := _spawn_enemy(sp, e["pos"] + off, kind, i, n, {"speed": 170.0} if kind == "swarm" else {})
		if hp_scale != 1.0:
			k["hp"] = float(k["max_hp"]) * hp_scale
			k["max_hp"] = k["hp"]
		made += 1
	summons += made
	return made


func _death_passives(e: Dictionary) -> void:
	var p: Vector2 = e["pos"]
	for b in e["buffs"]:
		var cls := String(b.get("class", ""))
		match cls:
			"SpawnOnDeath", "BoxOfWoeBuff":
				for rec in b.get("spawns", []):
					_spawn_kids(e, rec, clampi(int(rec.get("count", b.get("num_spawns", 1))), 1, 3))
				_effect("conjuration", p, 1.4)
				_ability("death_spawn")
			"SplittingBuff":
				for rec in b.get("spawns", []):
					_spawn_kids(e, rec, clampi(int(b.get("children", 2)), 1, 3), "swarm", 0.5)
				_effect("dark", p, 1.2)
				_ability("split")
			"RespawnAs":
				for rec in b.get("spawns", []):
					_spawn_kids(e, rec, 1)
				_effect("translocation", p, 1.4)
				_ability("respawn_as")
			"DeathExplosion", "PhoenixBuff", "FireBomberBuff", "IceBomberBuff", "VoidBomberBuff", "BadBalloonBuff":
				var dtypes: Array = b.get("damage_type", [])
				var dtype := String(dtypes[0]) if not dtypes.is_empty() else ("Fire" if "Fire" in cls or cls == "PhoenixBuff" else ("Ice" if "Ice" in cls else ("Arcane" if "Void" in cls else "Physical")))
				var radius := maxf(70.0, float(b.get("radius", 1)) * 55.0)
				var dmg := maxf(3.0, float(b.get("damage", 8)) * 0.5)
				_effect(dtype.to_lower(), p, radius / 28.0)
				_shake(5.0)
				if p.distance_to(p_pos) < radius + 18.0:
					invuln = 0.0
					_hurt(dmg, dtype)
				for a in party:
					if a["pos"].distance_to(p) < radius + 18.0:
						_hurt_ally(a, dmg, dtype)
				_ability("explode")
			"MushboomBuff":
				_spawn_cloud(p, "Poison", 2.0)
				_ability("spore_cloud")
			"SpikedWheelBuff":
				for i in 8:
					var a := TAU * i / 8.0
					_spawn_bullet(p, Vector2(cos(a), sin(a)) * 320.0, float(cfg("enemy_damage", 4.0)) + 0.25 * realm, "Physical")
				_ability("bone_spears")
	# the hungry ones nearby grow on a death
	for o in enemies:
		if o == e or o["pos"].distance_to(p) > 420.0:
			continue
		for b in o["buffs"]:
			var cls := String(b.get("class", ""))
			if cls == "SoulEaterBuff" or cls == "MonsterGrowthBuff" or (cls == "DeathEaterBuff" and "Undead" in e["sp"].get("tags", [])):
				o["max_hp"] = float(o["max_hp"]) * 1.1
				o["hp"] = minf(float(o["max_hp"]), float(o["hp"]) + float(o["max_hp"]) * 0.1)
				o["grow"] = float(o["grow"]) + 1.0
				_effect("blood", o["pos"], 0.9)
				_ability("grow")
				break


# Thorns: whoever strikes it in melee bleeds for it. Here that is touching it, biting or
# lunging at it, or shooting it from within two tiles.
func _thorns(e: Dictionary) -> Dictionary:
	for b in e["buffs"]:
		var cls := String(b.get("class", ""))
		if cls == "Thorns" or cls == "CurseRetaliation":
			var dtypes: Array = b.get("damage_type", [])
			return {"dmg": maxf(1.0, float(b.get("damage", 2)) * 0.8), "dtype": String(dtypes[0]) if not dtypes.is_empty() else ("Physical" if cls == "CurseRetaliation" else "Dark")}
	return {}


func _thorns_player(e: Dictionary) -> void:
	var th := _thorns(e)
	if th.is_empty() or state != PLAYING:
		return
	invuln = 0.0
	_hurt(float(th["dmg"]), String(th["dtype"]))
	_effect("physical", e["pos"], 1.0)
	_ability("thorns")


func _damage_passives(e: Dictionary, dtype: String) -> void:
	for b in e["buffs"]:
		var cls := String(b.get("class", ""))
		match cls:
			"RetaliationBuff", "SparkingSoul":
				e["retal_t"] = float(e["retal_t"])
				if t - float(e["retal_t"]) > 0.6:
					e["retal_t"] = t
					var dtypes: Array = b.get("damage_type", [])
					_spawn_bullet(e["pos"], (p_pos - e["pos"]).normalized() * 380.0, maxf(2.0, float(b.get("damage", 3)) * 0.8), String(dtypes[0]) if not dtypes.is_empty() else "Arcane")
					_ability("retaliate")
			"SummonReinforcements":
				if not bool(e["reinforced"]) and float(e["hp"]) < float(e["max_hp"]) * float(b.get("health_pct", 50)) / 100.0:
					e["reinforced"] = true
					for rec in b.get("spawns", []):
						_spawn_kids(e, rec, clampi(int(b.get("num_sum", 2)), 1, 4))
					_effect("translocation", e["pos"], 1.6)
					say("%s CALLS FOR HELP" % String(e["sp"]["name"]).to_upper(), 1.4)
					_ability("reinforce")
			"ChainedCyclopsBuff", "BerserkerEnrageBuff":
				if not bool(e["reinforced"]) and float(e["hp"]) < float(e["max_hp"]) * 0.5:
					e["reinforced"] = true
					e["haste"] = 10.0
					_effect("buff_apply", e["pos"], 1.4)
					_ability("berserk")


func _on_kill_passives(e: Dictionary) -> void:
	if e.get("dead", true):
		return
	for b in e["buffs"]:
		if String(b.get("class", "")) == "SummonOnKill":
			for rec in b.get("spawns", []):
				_spawn_kids(e, rec, 1)
			_effect("conjuration", e["pos"], 1.2)
			_ability("summon_on_kill")


# Once a second. Returns true when the monster turned into something else and is gone.
func _enemy_passives_tick(e: Dictionary) -> bool:
	var p: Vector2 = e["pos"]
	var on_screen := p.x > scroll_x - 40.0 and p.x < scroll_x + W + 40.0
	for b in e["buffs"]:
		var cls := String(b.get("class", ""))
		match cls:
			"GeneratorBuff":
				if on_screen and int(e["kids"]) < 5 and rng.randf() < clampf(float(b.get("spawn_chance", 0.1)) * 0.8, 0.03, 0.4):
					for rec in b.get("spawns", []):
						e["kids"] = int(e["kids"]) + _spawn_kids(e, rec, 1, "swarm")
					_effect("conjuration", p, 1.0)
					_ability("generator")
			"MatureInto", "ChanceToBecome":
				var due := false
				if cls == "MatureInto":
					e["mature_t"] = float(e["mature_t"]) - 1.0
					due = float(e["mature_t"]) <= 0.0
				else:
					due = rng.randf() < clampf(float(b.get("chance", 0.02)) * 3.0, 0.01, 0.3)
				if due and on_screen:
					for rec in b.get("spawns", []):
						var sp := _spawn_species(rec)
						if sp.is_empty():
							continue
						var grown := _spawn_enemy(sp, p, String(e["kind"]) if String(e["kind"]) != "minion" else "swarm", int(e["i"]), int(e["n"]), {"speed": 150.0})
						grown["anchor"] = e["anchor"]
						grown["t"] = e["t"]
						for k in ["amp", "freq", "speed", "sweep", "dive_y", "center", "r", "spin", "top"]:
							if e.has(k):
								grown[k] = e[k]
						_effect("buff_apply", p, 1.4)
						_ability("mature")
						_remove_enemy(e)
						return true
			"SlimeBuff":
				if rng.randf() < 0.5:
					e["hp"] = float(e["hp"]) + float(e["original_hp"]) * 0.1
					if float(e["hp"]) > float(e["max_hp"]):
						e["max_hp"] = float(e["hp"])
					if float(e["hp"]) >= float(e["original_hp"]) * 2.0 and on_screen:
						var made := 0
						for rec in b.get("spawns", []):
							made += _spawn_kids(e, rec, 2, "swarm")
						if made > 0:
							_effect("poison", p, 1.4)
							_ability("slime_split")
							_remove_enemy(e)
							return true
			"RegenBuff", "TrollRegenBuff":
				if float(e["hp"]) < float(e["max_hp"]):
					e["hp"] = minf(float(e["max_hp"]), float(e["hp"]) + maxf(1.0, float(e["max_hp"]) * 0.06))
					if int(t) % 3 == 0:
						_effect("heal", p, 0.8)
					_ability("regen")
			"ShieldRegenBuff", "RegenShieldsBuff", "GuardsmanBuff":
				if int(e["shields"]) < maxi(1, int(b.get("shield_max", 2))) and int(t) % 3 == 0:
					e["shields"] = int(e["shields"]) + 1
					_effect("shield_apply", p, 0.8)
					_ability("shield_regen")
			"HealAuraBuff":
				for o in enemies:
					if o != e and float(o["hp"]) < float(o["max_hp"]) and o["pos"].distance_to(p) < maxf(120.0, float(b.get("radius", 4)) * 55.0):
						o["hp"] = minf(float(o["max_hp"]), float(o["hp"]) + maxf(1.0, float(o["max_hp"]) * 0.08))
						_effect("heal", o["pos"], 0.7)
						_ability("heal_aura")
			"DamageAuraBuff", "ToxicAura", "LamasuCorruptionAura", "WitheringAura":
				if on_screen and state == PLAYING:
					var radius := maxf(110.0, float(b.get("radius", 2)) * 55.0)
					var dtypes: Array = b.get("damage_type", [])
					var dtype := String(dtypes[0]) if not dtypes.is_empty() else ("Poison" if cls == "ToxicAura" else "Dark")
					if p_pos.distance_to(p) < radius:
						invuln = 0.0
						_hurt(maxf(1.0, float(b.get("damage", 2)) * 0.4), dtype)
						_effect(dtype.to_lower(), p, radius / 40.0)
						_ability("damage_aura")
			"TeleportyBuff":
				if on_screen and rng.randf() < 0.08 and not String(e["kind"]) in ["turret", "hive", "wall", "boss"]:
					_effect("translocation", p, 0.9)
					var to := Vector2(clampf(p.x + rng.randf_range(-160.0, 160.0), scroll_x + 200.0, scroll_x + W - 60.0), clampf(p.y + rng.randf_range(-120.0, 120.0), TILE + 40.0, H - TILE - 40.0))
					e["anchor"] = e["anchor"] + (to - p)
					e["pos"] = to
					e["node"].position = to
					_effect("translocation", to, 0.9)
					_ability("teleporty")
	return false


# ---------------------------------------------------------------- companion passives

func _passive(name: String) -> void:
	passive_log[name] = int(passive_log.get(name, 0)) + 1


# The game's own words for what a companion does without casting.
func _passives_text(c: Dictionary) -> String:
	var tips := []
	for b in c.get("buffs", []):
		if b is Dictionary:
			var tip := String(b.get("tooltip", "")).replace("\n", " ")
			var re := RegEx.new()
			re.compile("\\[([^\\]:]+)(?::[^\\]]*)?\\]")
			tip = re.sub(tip, "$1", true)
			for rec in b.get("spawns", []):   # "summon a {name}" -> the spawn's name, one per placeholder
				var at := tip.find("{name}")
				if at >= 0:
					tip = tip.substr(0, at) + String(rec.get("name", "")) + tip.substr(at + 6)
			tip = tip.replace("{name}", "something").replace("  ", " ")
			if tip != "" and not tip.begins_with("("):
				tips.append(tip)
	return "passive: " + "  |  ".join(tips) if not tips.is_empty() else ""


func _ally_passives(a: Dictionary, dt: float) -> void:
	var buffs: Array = a["buffs"]
	var p: Vector2 = a["pos"]
	if float(a["enraged"]) > 0.0:
		a["enraged"] = float(a["enraged"]) - dt
	var resist: Dictionary = a["resist"]
	for k in resist.keys():
		resist[k] = float(resist[k]) - dt
		if resist[k] <= 0.0:
			resist.erase(k)
	a["aura_t"] = float(a["aura_t"]) - dt
	if a["aura_t"] <= 0.0:
		a["aura_t"] = 1.0
		if "HealAuraBuff" in buffs:   # Paladin: heal allies within 4 tiles
			var did := false
			if p_hp < p_max_hp and p_pos.distance_to(p) < 260.0:
				p_hp = minf(p_max_hp, p_hp + 1.5)
				did = true
			for o in party:
				if float(o["hp"]) < float(o["max_hp"]) and o["pos"].distance_to(p) < 260.0:
					o["hp"] = minf(float(o["max_hp"]), float(o["hp"]) + 2.0)
					did = true
			if did:
				_effect("heal", p, 0.7)
				_passive("Healing Aura")
		if "HolyAuraBuff" in buffs:   # Cleric: holy damage around, allies healed instead
			var hit := false
			for e in enemies.duplicate():
				if e["pos"].distance_to(p) < 260.0:
					_damage_enemy(e, 2.0, "holy")
					hit = true
			if hit:
				_effect("holy", p, 1.6)
				_passive("Holy Aura")
			if p_hp < p_max_hp and p_pos.distance_to(p) < 260.0:
				p_hp = minf(p_max_hp, p_hp + 1.0)
		if "WitheringAura" in buffs:   # Witch Doctor: corrosion on everything near
			for e in enemies:
				if e["pos"].distance_to(p) < 320.0:
					e["wither"] = 1.3
					_passive("Withering Aura")
		if "TeleportyBuff" in buffs and rng.randf() < 0.04:   # Dragon Knight fidgets through space
			_effect("translocation", p, 0.7)
			a["pos"] = p + Vector2(rng.randf_range(-90.0, 90.0), rng.randf_range(-90.0, 90.0))
			_passive("Passive Teleportation")
	for e in enemies:
		if float(e.get("wither", 0.0)) > 0.0:
			e["wither"] = float(e["wither"]) - dt
	if "ShieldRegenBuff" in buffs:   # Paladin: a shield back every few seconds, up to two
		a["regen_t"] = float(a["regen_t"]) - dt
		if a["regen_t"] <= 0.0:
			a["regen_t"] = 6.0
			if int(a["shields"]) < 2:
				a["shields"] = int(a["shields"]) + 1
				_effect("shield_apply", p, 0.8)
				_passive("Shield Regeneration")


# The Necromancer's oath: what lived and died fights for you now, bones and all.
func _raise_skeleton(e: Dictionary) -> void:
	var sp: Dictionary = e["sp"]
	var unit := "skeletal"
	if bool(sp.get("flying", false)) and QUD.has_unit("skeletal_flying"):
		unit = "skeletal_flying"
	elif bool(sp.get("stationary", false)) and QUD.has_unit("skeletal_stationary"):
		unit = "skeletal_stationary"
	if not QUD.has_unit(unit):
		return
	var node := Node2D.new()
	var s := Sprite2D.new()
	s.texture = QUD.unit_idle(unit)
	s.hframes = maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.modulate = Color(0.85, 0.95, 1.0)
	node.add_child(s)
	node.position = e["pos"]
	node.z_index = 4
	ents.add_child(node)
	var tag := _label(String(sp["name"]).to_lower(), 9, Color(0.7, 0.8, 0.9, 0.8))
	tag.position = Vector2(-30, -42)
	node.add_child(tag)
	undead.append({"node": node, "sprite": s, "pos": e["pos"], "hp": maxf(3.0, float(e["max_hp"])), "dmg": 2.0 + 0.3 * realm, "left": 25.0, "bite": 0.0,
		"stationary": bool(sp.get("stationary", false)), "home": Vector2(rng.randf_range(-260.0, -80.0), rng.randf_range(-170.0, 170.0))})
	_effect("dark", e["pos"], 1.4)
	Audio.play("summon", -8.0)
	raised += 1
	_passive("Necromancy")


func _undead_step(dt: float) -> void:
	for u in undead.duplicate():
		u["left"] = float(u["left"]) - dt
		u["bite"] = maxf(0.0, float(u["bite"]) - dt)
		var p: Vector2 = u["pos"]
		var target := _nearest_enemy(p, 700.0)
		if not bool(u["stationary"]):
			if target.is_empty():
				var home: Vector2 = p_pos + u["home"] + Vector2(0, 14.0 * sin(t * 1.3 + float(u["left"])))
				home.y = clampf(home.y, TILE + 30.0, H - TILE - 30.0)
				p = p.move_toward(home, 160.0 * dt)
			else:
				p = p.move_toward(target["pos"], 190.0 * dt)
		u["pos"] = p
		u["node"].position = p
		var s: Sprite2D = u["sprite"]
		s.frame = int(t / 0.22) % s.hframes
		s.flip_h = not target.is_empty() and target["pos"].x < p.x
		if not target.is_empty() and float(u["bite"]) <= 0.0 and target["pos"].distance_to(p) < float(target["radius"]) + 26.0:
			u["bite"] = 0.6
			_damage_enemy(target, float(u["dmg"]), "physical")
			_effect("physical", target["pos"], 0.7)
			var th := _thorns(target)
			if not th.is_empty():
				u["hp"] = float(u["hp"]) - float(th["dmg"])
				_effect(String(th["dtype"]).to_lower(), p, 0.7)
				_ability("thorns")
		for b in bullets.duplicate():
			if b["pos"].distance_to(p) < 24.0:
				u["hp"] = float(u["hp"]) - float(b["dmg"])
				bullets.erase(b)
				b["node"].queue_free()
				_effect(String(b["dtype"]), p, 0.7)
		if u["left"] <= 0.0 or float(u["hp"]) <= 0.0 or p.x < scroll_x - 120.0:
			_effect("dark", p, 1.0)
			undead.erase(u)
			u["node"].queue_free()


# ---------------------------------------------------------------- pause and feedback

func _pause() -> void:
	state_before_pause = state
	state = PAUSED
	pause_overlay = Control.new()
	pause_overlay.size = Vector2(SW, SH)
	hud.add_child(pause_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(SW, SH)
	pause_overlay.add_child(dim)
	var vb := VBoxContainer.new()
	vb.position = Vector2(SW * 0.5 - 300, 340)
	vb.add_theme_constant_override("separation", 18)
	pause_overlay.add_child(vb)
	vb.add_child(_label("PAUSED", 64, Color(1.0, 0.93, 0.35)))
	vb.add_child(_label("enter or esc   resume", 30))
	vb.add_child(_label("F   feedback: pick a thing in this realm, watch it act, tell us", 30))
	vb.add_child(_label("Q   quit to the realm select", 30))


func _resume() -> void:
	if pause_overlay != null:
		pause_overlay.queue_free()
		pause_overlay = null
	state = state_before_pause if state_before_pause != "" else PLAYING
	invuln = maxf(invuln, 0.5)


func _open_feedback(pick := -1) -> void:
	if feedback != null:
		return
	state = FEEDBACK
	if pause_overlay != null:
		pause_overlay.visible = false
	feedback = FeedbackPanel.new()
	feedback.setup(_feedback_objects(), _feedback_context(), realm, String(seg_grids[0]["tileset"]), pick)
	add_child(feedback)
	feedback.closed.connect(func():
		feedback.queue_free()
		feedback = null
		state = PAUSED
		if pause_overlay != null:
			pause_overlay.visible = true)


# Everything in this realm a person might want to talk about, as showcase objects.
func _feedback_objects() -> Array:
	var out := []
	out.append({"kind": "wizard", "name": Wardrobe.racer_name(Campaign.skin), "unit": Campaign.skin, "text": "You. HP %d / %d, level %d, %d slain this realm." % [int(p_hp), int(p_max_hp), level_n, kills]})
	var boss_sp := _boss_species()
	if not boss_sp.is_empty():
		out.append(_monster_object(boss_sp, "boss"))
	for sp in species:
		if not boss_sp.is_empty() and sp["name"] == boss_sp["name"]:
			continue
		out.append(_monster_object(sp, "monster"))
	for a in party:
		var c: Dictionary = a["comp"]
		var lines := []
		for spl in c.get("spells", []):
			if spl is Dictionary:
				lines.append("%s (%s)" % [String(spl.get("name", "")), SpellKinds.classify(spl)])
		out.append({"kind": "companion", "name": c["name"], "unit": String(c["asset"][c["asset"].size() - 1]), "spells": c.get("spells", []), "buffs": a["buffs"],
			"summons": _summon_map(String(c["name"]), c.get("spells", [])), "text": "%s, HP %d / %d. %s\n%s" % [c["name"], int(a["hp"]), int(a["max_hp"]), ", ".join(lines), _passives_text(c)]})
	for ps in p_spells:
		var owned: Dictionary = ps["owned"]
		var e: Dictionary = owned["effect"]
		out.append({"kind": "spell", "name": ps["name"], "icon": owned["icon"], "mode": String(e.get("kind", "bolt")), "dtype": String(e.get("dtype", "Arcane")),
			"unit": String(owned.get("unit", "wolf")), "text": "%s (level %d, %s, cooldown %.0fs). %s" % [ps["name"], int(ps["level"]), String(e.get("kind", "bolt")), float(ps["cd"]), String(owned.get("desc", "")).get_slice("\n", 0)]})
	for k in ups:
		for u in UPGRADES:
			if u["name"] == k:
				out.append({"kind": "upgrade", "name": k, "icon": u["icon"], "text": "%s x%d. %s" % [k, int(ups[k]), String(u["blurb"])]})
	for a in p_artifacts:
		out.append({"kind": "artifact", "name": a["name"], "icon": a["icon"], "text": "%s: %s. %s" % [a["name"], a["label"], String(a.get("desc", "")).get_slice("\n", 0)]})
	if int(ups.get("Force Pod", 0)) > 0:
		out.append({"kind": "thing", "name": "The Force", "unit": "floating_eyeball", "text": "The Force pod: rides your front, or is sent ahead with F or Q to eat bullets and ram."})
	out.append({"kind": "thing", "name": "Tavern", "tile": "item_tavern", "text": "The tavern halfway through the realm: fly in, an adventurer joins."})
	out.append({"kind": "thing", "name": "Chest", "tile": "item_equipment_chest", "text": "A chest from a boss or a miniboss: one of the game's artifacts."})
	out.append({"kind": "thing", "name": "Rift", "tile": "portal_dormant_portal", "text": "The three rifts after the boss, each ringed by the monsters of the realm behind it."})
	out.append({"kind": "thing", "name": "XP orb", "tile": "item_mana_orb", "text": "Experience from kills; pulls toward you when close."})
	out.append({"kind": "thing", "name": "Corridor and walls", "tile": "%s_wall_1" % String(seg_grids[0]["tileset"]), "text": "The realm's map as the corridor: walls block, a crush against the edge hurts and blinks you clear."})
	return out


func _monster_object(sp: Dictionary, kind: String) -> Dictionary:
	var lines := []
	for spl in sp.get("spells", []):
		if spl is Dictionary:
			lines.append("%s (%s)" % [String(spl.get("name", "")), SpellKinds.classify(spl)])
	var traits := []
	if bool(sp.get("flying", false)):
		traits.append("flies")
	if bool(sp.get("stationary", false)):
		traits.append("stationary")
	if bool(sp.get("lair", false)):
		traits.append("spawner")
	if bool(sp.get("big", false)):
		traits.append("big")
	var buffs := []
	for b in sp.get("buffs", []):
		if b is Dictionary:
			buffs.append(String(b.get("class", "")))
	return {"kind": kind, "name": sp["name"], "unit": sp["unit"], "spells": sp.get("spells", []), "summons": _summon_map(String(sp["name"]), sp.get("spells", [])),
		"stationary": bool(sp.get("stationary", false)), "lair": bool(sp.get("lair", false)), "big": bool(sp.get("big", false)), "buffs": buffs, "buff_recs": sp.get("buffs", []),
		"text": "%s, HP %d%s. %s\n%s" % [sp["name"], int(sp.get("hp", 0)), (" (" + ", ".join(traits) + ")") if not traits.is_empty() else "", ", ".join(lines) if not lines.is_empty() else "no spells: it bites", _passives_text(sp)]}


func _summon_map(caster: String, spls: Array) -> Dictionary:
	var out := {}
	for spl in spls:
		if spl is Dictionary and SpellKinds.classify(spl) == "summon":
			var sp := _summon_species(caster, String(spl.get("name", "")))
			out[String(spl.get("name", ""))] = String(sp.get("unit", "goblin"))
	return out


func _boss_species() -> Dictionary:
	if not boss.is_empty():
		return boss["sp"]
	for sp in species:
		if bool(sp["boss"]):
			return sp
	return {}


func _feedback_context() -> Dictionary:
	var names := []
	for ps in p_spells:
		names.append(ps["name"])
	var pnames := []
	for a in party:
		pnames.append(a["comp"]["name"])
	var anames := []
	for a in p_artifacts:
		anames.append(a["name"])
	return {"mode": "rifttype", "realm": realm, "tileset": String(seg_grids[0]["tileset"]), "t": snappedf(t, 0.1), "state": state_before_pause,
		"level": level_n, "score": score, "kills": kills, "hp": int(p_hp), "max_hp": int(p_max_hp), "upgrades": ups.duplicate(), "spells": names,
		"party": pnames, "artifacts": anames, "skin": Campaign.skin, "boss_reached": boss_spawned, "seed": rng.seed}


# ---------------------------------------------------------------- hud

func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	lbl_realm = _label("", 26, Color(1.0, 0.93, 0.35))
	lbl_realm.position = Vector2(24, 14)
	hud.add_child(lbl_realm)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.7)
	hp_bg.position = Vector2(24, 54)
	hp_bg.size = Vector2(300, 20)
	hud.add_child(hp_bg)
	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.9, 0.11, 0.14)
	hp_fill.position = hp_bg.position
	hp_fill.size = hp_bg.size
	hud.add_child(hp_fill)
	var xp_bg := ColorRect.new()
	xp_bg.color = Color(0, 0, 0, 0.7)
	xp_bg.position = Vector2(24, 80)
	xp_bg.size = Vector2(300, 10)
	hud.add_child(xp_bg)
	xp_fill = ColorRect.new()
	xp_fill.color = Color(0.47, 0.78, 1.0)
	xp_fill.position = xp_bg.position
	xp_fill.size = Vector2(0, 10)
	hud.add_child(xp_fill)
	lbl_top = _label("", 20, Color(0.85, 0.85, 0.85))
	lbl_top.position = Vector2(24, 96)
	hud.add_child(lbl_top)
	lbl_msg = _label("", 44, Color(1.0, 0.93, 0.35))
	lbl_msg.position = Vector2(0, 150)
	lbl_msg.size = Vector2(SW, 60)
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(lbl_msg)
	lbl_center = _label("", 40, Color(1.0, 0.93, 0.35))
	lbl_center.position = Vector2(0, 360)
	lbl_center.size = Vector2(SW, 300)
	lbl_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_center.visible = false
	hud.add_child(lbl_center)
	boss_bar = ColorRect.new()
	boss_bar.color = Color(0, 0, 0, 0.7)
	boss_bar.position = Vector2(SW * 0.5 - 300.0, 30)
	boss_bar.size = Vector2(600, 18)
	boss_bar.visible = false
	hud.add_child(boss_bar)
	boss_fill = ColorRect.new()
	boss_fill.color = Color(0.85, 0.3, 0.9)
	boss_fill.size = Vector2(600, 18)
	boss_bar.add_child(boss_fill)
	lbl_boss = _label("", 22, Color(0.95, 0.7, 1.0))
	lbl_boss.position = Vector2(0, -30)
	lbl_boss.size = Vector2(600, 30)
	lbl_boss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar.add_child(lbl_boss)
	artifact_row = HBoxContainer.new()
	artifact_row.position = Vector2(24, 122)
	artifact_row.add_theme_constant_override("separation", 6)
	hud.add_child(artifact_row)
	party_row = HBoxContainer.new()
	party_row.position = Vector2(SW - 700, 60)
	party_row.add_theme_constant_override("separation", 18)
	hud.add_child(party_row)
	spell_row = HBoxContainer.new()
	spell_row.position = Vector2(24, SH - 130)
	spell_row.add_theme_constant_override("separation", 6)
	hud.add_child(spell_row)
	var help := _label("arrows / WASD fly     hold enter, E or shift to fire, hold longer and release for the wave cannon     1-9 cast a spell     F or Q the Force     esc pause / feedback", 16, Color(0.6, 0.6, 0.6))
	help.position = Vector2(24, SH - 34)
	hud.add_child(help)


func say(text: String, duration := 1.2) -> void:
	message = text
	message_t = duration


func _process(_dt: float) -> void:
	lbl_realm.text = "REALM %d   %s" % [realm, String(seg_grids[0]["tileset"]).capitalize()]
	hp_fill.size = Vector2(300.0 * clampf(p_hp / maxf(1.0, p_max_hp), 0.0, 1.0), 20)
	xp_fill.size = Vector2(300.0 * clampf(xp / maxf(1.0, _xp_needed(level_n)), 0.0, 1.0), 10)
	var upl := []
	for k in ups:
		upl.append("%s x%d" % [k, int(ups[k])] if int(ups[k]) > 1 else String(k))
	lbl_top.text = "HP %d / %d%s     LEVEL %d     SCORE %d     %d slain     %s" % [int(p_hp), int(p_max_hp), ("   shield x%d" % shields) if shields > 0 else "", level_n, score, kills, ", ".join(upl)]
	lbl_msg.text = message if message_t > 0.0 else ""
	_update_spell_hud()
	_update_party_hud()
	if state in [PLAYING, CLEARED] and not auto:
		if Input.is_action_just_pressed("pause"):
			_pause()
			return
	elif state == PAUSED:
		if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("confirm"):
			_resume()
		elif Input.is_action_just_pressed("free_drive"):
			_open_feedback()
		elif Input.is_action_just_pressed("quick_shop"):
			Campaign.rift_page = true
			get_tree().change_scene_to_file("res://Menu.tscn")
			return
	elif state == FEEDBACK:
		pass   # the panel owns the keyboard
	elif state == LEVELUP and not auto:
		for i in 3:
			if Input.is_action_just_pressed("slot_%d" % (i + 1)):
				_pick(i)
	elif state == TAVERN and not auto:
		for i in 3:
			if Input.is_action_just_pressed("slot_%d" % (i + 1)):
				_tavern_pick(i)
		if Input.is_action_just_pressed("slot_4") or Input.is_action_just_pressed("pause"):
			_tavern_pick(-1)
	elif state == ARTIFACT and not auto:
		if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("cast") or Input.is_action_just_pressed("pause"):
			_close_chest()
	elif state == INTERMISSION and not auto:
		if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("cast"):
			_leave_intermission()
	elif state == DEAD:
		if Input.is_action_just_pressed("confirm"):
			get_tree().reload_current_scene()
			return
		if Input.is_action_just_pressed("pause"):
			Campaign.rift_page = true
			get_tree().change_scene_to_file("res://Menu.tscn")
			return
	frame_count += 1
	if screen_arg == "levelup" and frame_count == 30 and state == PLAYING:
		level_n += 1
		_offer_upgrades()
	if screen_arg == "tavern" and frame_count == 30 and state == PLAYING:
		_open_tavern()
	if screen_arg == "chest" and frame_count == 30 and state == PLAYING:
		_spawn_chest(p_pos + Vector2(30, 0), true)
	if screen_arg == "rifts" and frame_count == 30 and state == PLAYING:
		boss_spawned = true
		boss_dead_flag = true
		state = CLEARED
		_open_rifts()
	if screen_arg == "intermission" and frame_count == 30 and state == PLAYING:
		slain_names["Goblin"] = 3
		_intermission()
	if screen_arg == "pause" and frame_count == 30 and state == PLAYING:
		_pause()
	if screen_arg == "feedback" and frame_count == 30 and state == PLAYING:
		_pause()
		var pick := 2 if species.size() > 1 else 0   # a monster, so the showcase has something to do
		var want := String(cfg_arg("pick", ""))
		if want != "":
			var objs := _feedback_objects()
			for i in objs.size():
				if String(objs[i]["name"]) == want:
					pick = i
		_open_feedback(pick)
	if screen_arg == "feedback" and frame_count == 80 and auto and feedback != null:
		feedback.text.text = "demo pilot: automated feedback entry"   # proves the save path end to end
		feedback._send()
		print("feedback: %s" % feedback.status.text)
	if frames_left >= 0 and frame_count >= frames_left:
		frames_left = -1
		_finish_screenshot()


func _finish_screenshot() -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if screenshot_path != "":
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		print("saved ", screenshot_path)
	var names := []
	for ps in p_spells:
		names.append(ps["name"])
	var ph := []
	if not boss.is_empty():
		for x in boss.get("phases", []):
			ph.append("%s:%s" % [x["name"], x["kind"]])
	var pnames := []
	for a in party:
		pnames.append(a["comp"]["name"])
	var anames := []
	for a in p_artifacts:
		anames.append(a["name"])
	print("rifttype: realm=%d t=%.1f state=%s hp=%d level=%d score=%d kills=%d waves=%d/%d enemies=%d boss=%s ups=%s spells=%s casts=%d shots=%d died_at=%.1f took=%s phases=%s abilities=%s summons=%d party=%s party_casts=%d artifacts=%s rift=%d screen=%s raised=%d passives=%s" % [
		realm, t, state, int(p_hp), level_n, score, kills, wave_i, waves.size(), enemies.size(), str(boss_spawned), JSON.stringify(ups), JSON.stringify(names), casts, shots_fired, death_t, JSON.stringify(damage_log), JSON.stringify(ph), JSON.stringify(abilities), summons, JSON.stringify(pnames), party_casts, JSON.stringify(anames), chosen_dump, intermission_kind, raised, JSON.stringify(passive_log)])
	get_tree().quit()
