# One realm of the campaign: builds the track and racers, runs the fixed-step
# simulation, monster abilities, shinies, the lap rule, the pause shop, the
# rift gates, the chase camera and the HUD. See docs/campaign.md.
#
# Command-line (after "--"): --track=brick|volcano|ice  --seed=N  --auto  --newrun
#   --frames=N --screenshot=path   (render N frames, save the viewport, quit)
#   --screen=shop|gates            (open that overlay for the screenshot)
#   --sp=N  --spells=Name,Name     (campaign state for screenshots)
#   --learn=Name,Name --artifacts=Name,Name --hp=N   (grant spells/artifacts, set HP)
# Test rig (docs/test-rig.md): --rig=ahead:250,behind:250,swerve:420:0.8,beside:-90,parked:600
#   --cast=Name@seconds,...  --seconds=N  --timescale=X  --report=path.json  --shinies
#   in the rig: L spell picker (any spell into a slot), N enemy picker, Z slow-motion; --screen=picker|enemies
extends Node3D

const COUNTDOWN := "countdown"
const RACING := "racing"
const FINISHED := "finished"
const GATES := "gates"
const DEAD := "dead"
const FREE := "free"

var rng := RandomNumberGenerator.new()
var track: Track
var karts: Array = []
var player: Kart
var item_boxes: Array = []
var projectiles: Array = []
var patches: Array = []
var hazards: Array = []
var auras: Array = []
var escorts: Array = []      # summoned karts riding in formation (Items.Escort)
var effects: Array = []
var bolts: Array = []
var mobs: Array = []

var state := COUNTDOWN
var countdown := 3.6
var race_time := 0.0
var t := 0.0
var finish_order: Array = []
var finish_hold := 0.0
var message := ""
var message_t := 0.0
var laps := 3
var auto_player := false
var running := true
var paused := false
var monster_names: Array = []
var slain: Array = []

var cam: Camera3D
var cam_yaw := 0.0
var cam_right := Vector2.RIGHT
var hud: CanvasLayer
var lbl_lap: Label
var lbl_pos: Label
var lbl_time: Label
var lbl_track: Label
var lbl_center: Label
var lbl_help: Label
var lbl_item: Label
var lbl_realm: Label
var lbl_hp: Label
var lbl_sp: Label
var hp_fill: ColorRect
var item_icon: TextureRect
var results: Label
var speed_bar: ColorRect
var speed_fill: ColorRect
var lbl_drift: Label
var lbl_stats: Label
var slot_icons: Array = []
var slot_charges: Array = []
var shop: Shop = null
var gates: Gates = null
var quick: CanvasLayer
var quick_open := false
var quick_icons: Array = []
var quick_labels: Array = []
var artifact_row: HBoxContainer

var shadow_mesh: Mesh
var shiny_tex := {}
var spacing := 90.0
var start_grace := 0.0
var screenshot_path := ""
var frames_left := -1
var frame_count := 0
var screen_arg := ""
var C := {}
var free_mode := false
var top_view := false
var state_before_free := ""
var lbl_street: Label
var minimap: MiniMap
var tally := {"ability": 0.0, "lap": 0.0, "mob": 0.0, "bolt": 0.0, "wolf": 0.0, "dealt": 0.0, "sp_start": 0, "casts": 0}

# test rig (docs/test-rig.md)
var rig := false
var R := {}
var rig_casts: Array = []        # scheduled: [{name, t}]
var rig_scripted := false        # --cast given: the auto driver leaves the bar alone
var rig_log: Array = []          # cast records with before/after snapshots
var rig_gaps := {}               # npc name -> [sum abs error, max abs error, samples]
var player_boost_total := 0.0
var wolves_peak := 0
var track_spells: Array = []
var report_path := ""
var seconds_limit := -1.0
var rig_trace: Array = []        # one row per second: gaps, speeds, on-road flags
var rig_kinematic := true        # archetypes slide along the route; --drive makes them drive the kart physics
var picker: SpellPicker = null
var party := false               # local multiplayer: several humans, split screen, arcade rules
var humans: Array = []           # human karts in seat order (party) or [player]
var panels: Array = []           # per-human {container, viewport, cam, yaw, cam_right, hud labels}
var human_frames: Array = []
var level := {}                  # the realm dump this race is built from (empty for tracks.json tracks)
var player_ability := {}         # racing as a monster: its own attack, on a cooldown, no action bar
var player_ability_cd := 0.0
var generators: Array = []       # the realm's lairs by the road, spawning its monsters as mobs
var debug := false               # --debug (or the rig): K toggles monster attacks, [ ] change realm
var attacks_on := true
var enemies: EnemyPicker = null
var debug_keys: Array = []       # --keys=Escape@40,L@60: inject key presses on those frames (UI tests)
var overlay_closed_frame := -1   # the key that closed an overlay must not also act on the race that frame
var slow_scale := 1.0            # rig slow-motion (Z); the quick shop restores this when it closes
var online := false              # a Steam/UDP race: the host simulates, guests draw what they are told
var host := false
var guest := false
var local_humans: Array = []     # humans driven from this machine (they get the panels)
var net_karts: Dictionary = {}   # net_id -> Kart, the same ids on every machine
var next_net_id := 0
var next_box_id := 0
var net_ticks := 0
var net_live := false            # host: the world is built, runtime pickups go out as events
var guest_ready := false         # guest: the setup arrived, karts exist
var hello_t := 0.0
var placeholder: Kart = null


func _ready() -> void:
	var args := _parse_args()
	C = Shared.tuning.get("campaign", {})
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
	if args.has("learn"):
		for n in String(args["learn"]).split(","):
			if SpellDB.by_name.has(n):
				Campaign.learn(SpellDB.by_name[n])
	if args.has("artifacts"):
		for n in String(args["artifacts"]).split(","):
			if Artifacts.by_name.has(n):
				Campaign.grant_artifact(Artifacts.by_name[n])
	if args.has("hp"):
		Campaign.hp = minf(Campaign.max_hp, float(args["hp"]))
	R = Shared.tuning.get("rig", {})
	var rig_spec := String(args.get("rig", Campaign.rig))
	rig = rig_spec != ""
	debug = rig or args.has("debug")
	attacks_on = not args.has("noattacks")
	report_path = String(args.get("report", ""))
	seconds_limit = float(args.get("seconds", -1.0))
	if args.has("timescale"):
		Engine.time_scale = float(args["timescale"])
		slow_scale = Engine.time_scale
	rig_kinematic = bool(R.get("kinematic", true)) and not args.has("drive")
	if args.has("type"):    # --type=gp|campaign|single: the race type without the menu (tests)
		Campaign.race_type = String(args["type"])
	if args.has("party"):   # --party=N: N local humans in a party race (auto-driven with --auto)
		Players.clear()
		for i in clampi(int(args["party"]), 1, Players.MAX):
			var pl := Players.join_with("debug:%d" % i, DriveAdapter.new("p%d" % (i + 1), "debug:%d" % i))
			var skins := Wardrobe.skins()
			var unit: String = skins[(i * 7) % skins.size()]
			pl["racer"] = {"kind": "wizard", "unit": unit, "name": Wardrobe.racer_name(unit)}
		Campaign.race_type = "party"
	if args.has("online"):   # --online=host|guest --port=N [--guests=N] [--host_ip=..]: a UDP race between processes
		Net.setup_udp(String(args["online"]), int(args.get("port", 47001)), String(args.get("host_ip", "127.0.0.1")))
		Campaign.race_type = "online"
	online = Campaign.race_type == "online" and Net.online_role != ""
	if online:
		host = Net.online_role == "host"
		guest = not host
		Players.clear()
		var me := Players.join_with("local", ActionAdapter.new("p1"))
		me["racer"] = {"kind": "wizard", "unit": Campaign.skin, "name": Wardrobe.racer_name(Campaign.skin)}
		if host:
			for peer in Net.peers():
				var pl := Players.join_with(peer, RemoteAdapter.new("", peer))
				pl["racer"] = Net.member_racer(peer)
			for i in int(args.get("guests", 0)):   # UDP: seats for guests that have not spoken yet
				var pl := Players.join_with("pending:%d" % i, RemoteAdapter.new("", ""))
				pl["racer"] = {"kind": "wizard", "unit": "player", "name": "Wizard"}
	if args.has("keys"):
		for k in String(args["keys"]).split(","):
			var kv := k.split("@")
			debug_keys.append({"key": kv[0], "frame": int(kv[1]) if kv.size() > 1 else 30})
	if args.has("cast"):
		rig_scripted = true
		for c in String(args["cast"]).split(","):
			var kv := c.split("@")
			rig_casts.append({"name": kv[0], "t": float(kv[1]) if kv.size() > 1 else 1.0})
	rng.seed = int(args.get("seed", Campaign.seed))
	auto_player = args.has("auto")
	screenshot_path = args.get("screenshot", "")
	frames_left = int(args.get("frames", -1))
	screen_arg = String(args.get("screen", ""))
	laps = int(Shared.t(["race", "laps"], 3))
	countdown = float(Shared.t(["race", "countdown"], 3.6))

	var key: String = args.get("track", Campaign.next_track)
	if args.has("map"):
		key = String(args["map"])
	if online and not args.has("map"):
		key = Net.race_map
	if args.has("realm_file"):
		Campaign.realm_file = String(args["realm_file"])
	if key == "realm":
		level = Campaign.current_realm()
	if level.is_empty() and not Shared.tracks.has(key):
		key = Shared.track_for_level(Campaign.level)   # the Grand Prix runs the cups in order
	track = Track.new()
	add_child(track)
	if not level.is_empty():
		track.setup_level(level, rng)
	else:
		track.setup(key, rng)
	track_spells = track.spec.get("spells", [])
	laps = int(track.spec.get("laps", laps))

	_build_environment()
	_build_shadow_mesh()
	if rig:
		laps = 99
		countdown = 0.01
		if Campaign.spells.is_empty() and rig_casts.is_empty():
			for n in track_spells:      # manual testing: the whole track list on the bar
				if SpellDB.by_name.has(n):
					Campaign.learn(SpellDB.by_name[n])
			Campaign.sp = 30
		_spawn_rig(rig_spec)
		if args.has("shinies"):
			_spawn_item_boxes()
	elif guest:
		_shiny_textures()
		placeholder = Kart.new()   # stands in for our kart until the host's setup arrives
		add_child(placeholder)
		placeholder.setup("", "player", track.points[0], 0.0, true, rng, shadow_mesh)
		placeholder.visible = false
		player = placeholder
		humans = [placeholder]
	else:
		_spawn_racers(int(Shared.t(["race", "racers"], 8)))
		_spawn_item_boxes()
		_spawn_track_hazards()
		if level.is_empty():
			_spawn_mobs()
		else:
			_spawn_generators()
			_spawn_props()
	_build_camera()
	_build_hud()
	_update_camera(0.0, true)
	if party and (humans.size() > 1 or online) and not guest:
		_build_panels()
	net_live = true
	if args.has("free"):
		_set_free(true)
	tally["sp_start"] = Campaign.sp
	Audio.music("battle_%d" % (1 + (Campaign.level - 1) % 12))


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
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.25, 0.18, 0.36)
	env.fog_density = 0.003
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.1
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


# The monster's first damaging spell, mapped like a player spell, becomes its ability and is
# cast at the wizard through Items.cast_spell; a monster with none bites.
func _ability_spell_from(spells: Array, band: int) -> Dictionary:
	var pick := {}
	for sp in spells:
		if not (sp is Dictionary) or sp.has("error"):
			continue
		if float(sp.get("stats", {}).get("damage", 0)) > 0.0 and float(sp.get("range", 0)) > 2.0:
			pick = sp
			break
	if pick.is_empty():
		for sp in spells:
			if sp is Dictionary and not sp.has("error") and float(sp.get("stats", {}).get("damage", 0)) > 0.0:
				pick = sp
				break
	if pick.is_empty():
		pick = {"name": "Bite", "level": 1, "tags": ["Physical"], "damage_type": ["Physical"], "range": 1.5, "melee": true,
			"max_charges": 0, "stats": {"damage": 3.0 + band}, "asset": []}
	var owned := SpellDB.make_owned(pick)
	var e: Dictionary = owned["effect"]
	var dmg_scale := Kart.interp(C.get("ability_damage_by_band", [[1, 1.0]]), float(band))
	if float(e.get("damage", 0.0)) <= 0.0 and String(e["kind"]) in ["bolt", "beam", "blast", "melee", "burst"]:
		e["damage"] = 3.0 + band
	e["damage"] = float(e.get("damage", 0.0)) * dmg_scale
	return owned


func _ability_from(spells: Array) -> Dictionary:
	for sp in spells:
		if not (sp is Dictionary) or sp.has("error"):
			continue
		var st: Dictionary = sp.get("stats", {})
		var dmg := float(st.get("damage", 0))
		var rng_t := float(sp.get("range", 0))
		if dmg > 0.0 and rng_t > 2.0:
			var dtypes: Array = sp.get("damage_type", [])
			return {"name": sp.get("name", "Bolt"), "kind": "ranged", "damage": dmg, "range": rng_t * 90.0,
					"dtype": String(dtypes[0]) if dtypes.size() > 0 else "Arcane"}
	return {"name": "Bite", "kind": "melee", "damage": 3.0, "range": 70.0, "dtype": "Physical"}


func _spawn_racers(count: int) -> void:
	party = Campaign.race_type in ["party", "online"] and Players.count() > 0
	var n_humans := Players.count() if party else 1
	var starts := track.start_positions(count)
	var band := Campaign.band()
	var roster: Array = []
	if Campaign.race_type in ["gp", "single", "party", "online"]:
		roster = _wizard_roster(count - n_humans)
	elif not level.is_empty():
		roster = _level_roster(count - 1)
	if roster.size() < count - 1:
		roster += QUD.roster(count - 1 - roster.size(), rng, band, maxi(1, band - 2))
	if roster.size() < count - 1:
		roster += QUD.roster(count - 1 - roster.size(), rng, 9, 1)
	var hp_scale := float(C.get("monster_hp_scale", 1.0))
	for i in count:
		var k := Kart.new()
		add_child(k)
		var s: Dictionary = starts[i]
		if party and i >= count - n_humans:
			var seat_i := i - (count - n_humans)
			var pl: Dictionary = Players.players[seat_i]
			var rc: Dictionary = pl["racer"]
			var unit := String(rc.get("unit", "player"))
			if not QUD.has_unit(unit):
				unit = "player"
			k.setup(String(rc.get("name", "Wizard")), unit, s["pos"], s["heading"], true, rng, shadow_mesh, Vector2i(5, 5), Campaign.max_hp)
			k.human = seat_i
			k.remote = pl["adapter"] is RemoteAdapter
			k.label.visible = true
			k.label.modulate = Players.COLORS[int(pl["seat"]) % Players.COLORS.size()]
			k.label.text = "P%d" % (int(pl["seat"]) + 1)
			humans.append(k)
			if not k.remote:
				local_humans.append(k)
			if seat_i == 0:
				player = k
		elif i == count - 1:
			_setup_player_kart(k, s)
			k.hp = Campaign.hp
			humans = [k]
			local_humans = [k]
			k.charge_scale /= 1.0 + Campaign.bonus("drift_charge")
			player = k
		else:
			var r: Dictionary = roster[i % roster.size()] if roster.size() > 0 else {"name": "Goblin", "unit": "goblin", "hp": 7.0, "flying": false, "spells": []}
			var boss := false
			var boss_realms: Array = C.get("boss_realms", [10, 15, 20])
			var boss_realm := false
			for br in boss_realms:
				if int(br) == Campaign.level:
					boss_realm = true
			if i == 0 and boss_realm:
				var cands := QUD.bosses(Campaign.level, Campaign.level >= 20)
				if cands.is_empty():
					push_warning("no boss candidates for realm %d" % Campaign.level)
				else:
					r = cands[rng.randi_range(0, cands.size() - 1)]
					boss = true
					print("boss racer: %s (%s)" % [r["name"], r["unit"]])
			var krng := RandomNumberGenerator.new()
			krng.seed = rng.randi()
			var stats := Kart.stats_from_unit(float(r.get("hp", 10.0)), bool(r.get("flying", false)), krng)
			if boss:
				stats = Vector2i(6, 9)
			var kart_hp := maxf(3.0, float(r.get("hp", 10.0)) * hp_scale)
			if bool(r.get("wizard", false)):
				kart_hp = float(r.get("hp", 40.0))
				stats = Vector2i(rng.randi_range(4, 6), rng.randi_range(4, 6))
				k.is_wizard = true
			if boss:
				kart_hp = float(C.get("boss_hp_base", 60)) + float(C.get("boss_hp_per_realm", 8)) * Campaign.level
			k.setup(r["name"], r["unit"], s["pos"], s["heading"], false, krng, shadow_mesh, stats, kart_hp)
			if boss:
				k.label.modulate = Color(1.0, 0.6, 0.2)
				k.label.font_size = 44
			var react: Array = Shared.t(["ai", "start_reaction"], [-0.3, 0.9])
			k.ai_reaction = krng.randf_range(float(react[0]), float(react[1]))
			k.ability = _ability_from(r.get("spells", []))
			k.ability_spell = _ability_spell_from(r.get("spells", []), band)
			var cd: Array = C.get("ability_cooldown", [4.0, 8.0])
			k.ability_cd = krng.randf_range(float(cd[0]), float(cd[1]))
			monster_names.append(r["name"])
		karts.append(k)
		k.net_id = next_net_id
		next_net_id += 1
		net_karts[k.net_id] = k
	var total_len := 0.0
	for l in track.seg_len:
		total_len += l
	spacing = total_len / maxi(1, track.n)


# Archetype NPCs around the wizard: "kind:dist[:lat]" per entry. dist is px along the
# route (behind is negated), lat a fraction of half the road width (swerve: amplitude).
func _spawn_rig(spec: String) -> void:
	var s: Dictionary = track.start_positions(1)[0]
	var k := Kart.new()
	add_child(k)
	_setup_player_kart(k, s)
	k.hp = Campaign.hp
	player = k
	karts.append(k)
	player.route_px = track.progress_px(player)
	player.route_idx = 0
	for part in spec.split(","):
		var kv := part.strip_edges().split(":")
		if kv.is_empty() or kv[0] == "":
			continue
		var kind := String(kv[0])
		var dist := float(kv[1]) if kv.size() > 1 else 250.0
		var lat := float(kv[2]) if kv.size() > 2 else 0.0
		if kind == "swerve" and kv.size() <= 2:
			lat = float(R.get("swerve_amplitude", 0.55))
		var unit := String(kv[3]) if kv.size() > 3 else ""   # kind:dist:lat:unit
		_add_rig_npc(kind, dist, lat, unit, unit.capitalize() if unit != "" else "")
	var total := 0.0
	for l in track.seg_len:
		total += l
	spacing = total / maxi(1, track.n)


const RIG_UNITS := ["goblin", "orc", "bat", "kobold", "ogre", "witch", "mantis", "ghost"]


# One archetype NPC at its target spot. dist: px along the route (+ ahead; behind is
# negated; beside: side offset in px), lat: lane as a fraction of half the road width.
func _add_rig_npc(kind: String, dist: float, lat: float, unit := "", mname := "") -> Kart:
	if kind == "behind" and dist > 0.0:
		dist = -dist
	var label_n := int(absf(dist))
	if kind == "beside":
		lat = dist / (track.width * 0.5)
		dist = 0.0
	var pt := track.point_at_px(player.route_px + dist)
	var dir: Vector2 = pt["dir"]
	var nrm := Vector2(-dir.y, dir.x)
	var npc := Kart.new()
	add_child(npc)
	var krng := RandomNumberGenerator.new()
	krng.seed = rng.randi()
	var n_npcs := karts.size() - 1
	if unit == "" or not QUD.has_unit(unit):
		unit = RIG_UNITS[n_npcs % RIG_UNITS.size()]
	var start: Vector2 = pt["pos"] + nrm * (0.0 if kind == "swerve" else lat) * track.width * 0.5
	var label := "%s %d" % [kind.to_upper(), label_n]
	if mname != "":
		label = "%s %d %s" % [kind.to_upper(), label_n, mname]
	npc.setup(label, unit, start, atan2(dir.y, dir.x), false, krng, shadow_mesh, Vector2i(5, 5), float(R.get("npc_hp", 200)))
	npc.archetype = kind
	npc.rig_dist = dist
	npc.rig_lat = lat
	npc.no_items = true
	npc.speed_scale = float(R.get("speed_scale", 1.45))
	npc.next_wp = (int(pt["index"]) + 1) % track.n
	npc.lap = 1 if dist >= 0.0 else 0
	npc.route_px = player.route_px + dist
	npc.route_idx = int(pt["index"])
	karts.append(npc)
	monster_names.append(npc.display_name)
	return npc


func _remove_rig_npc(kart: Kart) -> void:
	if kart == null or kart.is_player or not karts.has(kart):
		return
	karts.erase(kart)
	finish_order.erase(kart)
	kart.queue_free()


func _open_enemies() -> void:
	if enemies != null or picker != null or shop != null:
		return
	paused = true
	enemies = EnemyPicker.new()
	enemies.race = self
	add_child(enemies)
	enemies.add_requested.connect(func(kind, dist, lat, unit, mname):
		var npc := _add_rig_npc(kind, dist, lat, unit, mname)
		say("%s ADDED" % npc.display_name, 1.2))
	enemies.remove_requested.connect(_remove_rig_npc)
	enemies.clear_requested.connect(func():
		for kart in karts.duplicate():
			_remove_rig_npc(kart))
	enemies.closed.connect(_close_enemies)


func _close_enemies() -> void:
	if enemies == null:
		return
	enemies.queue_free()
	enemies = null
	paused = false
	overlay_closed_frame = Engine.get_process_frames()


# You, as the racer chosen on the menu: a wizard in an outfit with the action bar, or an
# unlocked monster with nothing but its own attack.
func _setup_player_kart(k: Kart, s: Dictionary) -> void:
	var rc: Dictionary = Campaign.racer
	var unit := String(rc.get("unit", Campaign.skin))
	if not QUD.has_unit(unit):
		unit = "player"
	var stats := Vector2i(5, 5)
	if String(rc.get("kind", "wizard")) == "monster":
		var m := _monster_by_name(String(rc.get("name", "")))
		if not m.is_empty():
			var krng := RandomNumberGenerator.new()
			krng.seed = 7
			stats = Kart.stats_from_unit(float(m.get("max_hp", 10)), bool(m.get("flying", false)), krng)
			player_ability = _ability_spell_from(m.get("spells", []), Campaign.band())
			player_ability["effect"]["damage"] = float(player_ability["effect"].get("damage", 0.0)) / maxf(0.1, Kart.interp(C.get("ability_damage_by_band", [[1, 1.0]]), float(Campaign.band())))
	k.setup(String(rc.get("name", "Wizard")), unit, s["pos"], s["heading"], true, rng, shadow_mesh, stats, Campaign.max_hp)


func _monster_by_name(mname: String) -> Dictionary:
	for m in QUD.monsters:
		if m.get("name", "") == mname:
			return m
	return {}


# Other wizards in other outfits, each with one spell from the track's list as its attack.
func _wizard_roster(count: int) -> Array:
	var out := []
	var skins := Wardrobe.skins()
	skins.erase(String(Campaign.racer.get("unit", "")))
	var pick := []
	for i in count:
		if skins.is_empty():
			break
		var j := rng.randi_range(0, skins.size() - 1)
		pick.append(skins[j])
		skins.remove_at(j)
	for unit in pick:
		var spells := []
		if not track_spells.is_empty():
			var sname: String = track_spells[rng.randi_range(0, track_spells.size() - 1)]
			if SpellDB.by_name.has(sname):
				spells.append(SpellDB.by_name[sname])
		out.append({"name": Wardrobe.skin_label(unit), "unit": unit, "hp": float(C.get("wizard_racer_hp", 40)), "flying": false,
			"spells": spells, "wizard": true})
	return out


# The realm's monsters (not its lairs) as racers, one of each kind, shuffled.
func _level_roster(count: int) -> Array:
	var seen := {}
	var pool := []
	for u in level.get("units", []):
		if bool(u.get("is_lair", false)) or seen.has(u["name"]):
			continue
		var asset: Array = u.get("asset", [])
		if asset.size() < 2 or asset[0] != "char" or not QUD.has_unit(asset[1]):
			continue
		if int(u.get("radius", 0)) > 1:
			continue
		seen[u["name"]] = true
		pool.append({"name": u["name"], "unit": asset[1], "hp": float(u.get("hp", 10)), "flying": bool(u.get("flying", false)),
			"spells": _full_spells(u.get("spells", []))})
	pool.shuffle()
	return pool.slice(0, count)


# The dumps keep a compact spell list; give them the shape SpellDB expects.
func _full_spells(compact: Array) -> Array:
	var out := []
	for sp in compact:
		if not (sp is Dictionary):
			continue
		var dtypes: Array = sp.get("damage_type", [])
		out.append({"name": sp.get("name", "Attack"), "level": 1, "tags": dtypes, "damage_type": dtypes,
			"range": float(sp.get("range", 1.5)), "melee": bool(sp.get("melee", false)), "max_charges": 0,
			"stats": {"damage": float(sp.get("damage", 0))}, "asset": []})
	return out


# The course's own surface: ice that slides, fire and gas that hurt, water and oil and
# slime that slow (a slip), warm static that stuns — fixed patches from tracks.json.
# tex: a 4-frame strip under tiles/ (cloud_<x>_cloud or pad_<x>). stun: seconds on a tick.
const HAZARD_KINDS := {
	"ice": {"tex": "cloud_ice_cloud", "dtype": "Ice", "damage": 0.0, "slip": true, "stun": 0.0, "tint": Color(0.8, 0.95, 1.0)},
	"fire": {"tex": "cloud_thunder_cloud", "dtype": "Fire", "damage": 4.0, "slip": false, "stun": 0.0, "tint": Color(1.0, 0.45, 0.2)},
	"poison": {"tex": "cloud_rainstorm_cloud", "dtype": "Poison", "damage": 2.5, "slip": false, "stun": 0.0, "tint": Color(0.4, 0.9, 0.3)},
	"water": {"tex": "cloud_rainstorm_cloud", "dtype": "Ice", "damage": 0.0, "slip": true, "stun": 0.0, "tint": Color(0.3, 0.6, 1.0)},
	"oil": {"tex": "cloud_thunder_cloud", "dtype": "Physical", "damage": 0.0, "slip": true, "stun": 0.0, "tint": Color(0.35, 0.3, 0.45)},
	"slime": {"tex": "cloud_rainstorm_cloud", "dtype": "Poison", "damage": 1.5, "slip": true, "stun": 0.0, "tint": Color(0.5, 0.8, 0.2)},
	"static": {"tex": "cloud_ice_cloud", "dtype": "Arcane", "damage": 1.0, "slip": false, "stun": 0.5, "tint": Color(0.9, 0.5, 1.0)},
	"barrier": {"tex": "pad_barrier", "dtype": "Arcane", "damage": 2.0, "slip": false, "stun": 0.9, "tint": Color(0.5, 0.8, 1.0)},
	"wheel": {"tex": "pad_barrier", "dtype": "Physical", "damage": 1.0, "slip": false, "stun": 0.6, "tint": Color(0.9, 0.85, 0.6)},
	"cart": {"tex": "cloud_thunder_cloud", "dtype": "Physical", "damage": 1.0, "slip": true, "stun": 0.3, "tint": Color(0.8, 0.65, 0.4)},
	"bell": {"tex": "cloud_ice_cloud", "dtype": "Arcane", "damage": 0.0, "slip": false, "stun": 0.8, "tint": Color(1.0, 0.85, 0.3)},
	"jump": {"tex": "pad_jump", "dtype": "Physical", "damage": 0.0, "slip": false, "stun": 0.0, "tint": Color(1.0, 1.0, 1.0)},
}
const JUMP_SECONDS := 0.9
const JUMP_BOOST := 0.35

var course_hazards: Array = []     # [{h, kind, period, duty, phase, on}]
var hazard_log := false


func _spawn_track_hazards() -> void:
	var n := 0
	hazard_log = OS.get_cmdline_user_args().has("--hazard-log")
	for kart in karts:
		kart.branch_log = hazard_log
	for spot in track.hazard_spots():
		var kind := String(spot["kind"])
		var spec: Dictionary = HAZARD_KINDS.get(kind, HAZARD_KINDS["fire"])
		var h := Items.Hazard.new()
		h.pos = spot["pos"]
		h.radius = float(spot["radius"])
		h.damage = float(spec["damage"])
		h.dtype = String(spec["dtype"])
		h.slip = bool(spec["slip"])
		h.stun = float(spec["stun"])
		h.tick = 0.7
		h.life = 1.0e9      # the course's own, for the whole race
		h.owner_kart = null
		h.position = track.to3(h.pos, 3.0)
		h.build(QUD.texture("tiles/%s.png" % String(spec["tex"])), 4, spec["tint"], track)
		add_child(h)
		if kind != "jump":
			hazards.append(h)      # damage / slip / stun through the ordinary hazard loop
		var period := float(spot.get("period", 0.0))
		course_hazards.append({"h": h, "kind": kind, "period": period, "duty": float(spot.get("duty", 0.5)),
			"phase": float(spot.get("phase", 0.0)), "on": true, "laps": spot.get("laps", []),
			"per_lap": spot.get("per_lap", {}), "base": {"period": period, "duty": float(spot.get("duty", 0.5)), "phase": float(spot.get("phase", 0.0))}})
		n += 1
	if n > 0:
		var cycling := 0
		var pads := 0
		var lapped := 0
		for c in course_hazards:
			if c["period"] > 0.0:
				cycling += 1
			if c["kind"] == "jump":
				pads += 1
			if not (c["laps"] as Array).is_empty() or not (c["per_lap"] as Dictionary).is_empty():
				lapped += 1
		print("hazards: %d course patches (%s), %d cycling, %d jump pads, %d lap-gated" % [n, track.key, cycling, pads, lapped])
	_apply_lap_sets(1)


# The course develops by lap (Lap 1 teaches, Lap 2 complicates, Lap 3 escalates): a
# hazard's "laps" says which laps it is live on and "per_lap" overrides its period / duty /
# phase on a given lap. The lap is the LEADER's, so the course changes for everyone at
# once; a hazard that is not yet live is drawn faint from the start — the preview.
var course_lap := 0


func _leader_lap() -> int:
	var best := 1
	for kart in karts:
		if kart.alive and not kart.finished:
			best = maxi(best, int(kart.lap))
	return clampi(best, 1, laps)


func _apply_lap_sets(lap: int) -> void:
	course_lap = lap
	var live := 0
	for c in course_hazards:
		var gate: Array = c["laps"]
		c["lap_ok"] = gate.is_empty() or gate.has(lap) or gate.has(float(lap))
		var base: Dictionary = c["base"]
		var ov: Dictionary = (c["per_lap"] as Dictionary).get(str(lap), {})
		c["period"] = float(ov.get("period", base["period"]))
		c["duty"] = float(ov.get("duty", base["duty"]))
		c["phase"] = float(ov.get("phase", base["phase"]))
		if c["lap_ok"]:
			live += 1
	if hazard_log:
		print("lap %d: hazard set %d / %d live" % [lap, live, course_hazards.size()])
	var notes: Dictionary = track.spec.get("lap_notes", {})
	if notes.has(str(lap)) and lap > 1:
		say(String(notes[str(lap)]).to_upper(), 2.4)


# Cycling hazards switch on for `duty` of every `period` seconds, with an amber cue in the
# second before; jump pads loft any kart that crosses them while live.
func _update_course_hazards(_dt: float) -> void:
	if course_hazards.is_empty():
		return
	var lap := _leader_lap()
	if lap != course_lap:
		_apply_lap_sets(lap)
	for c in course_hazards:
		var h: Items.Hazard = c["h"]
		var period: float = c["period"]
		var on: bool = c.get("lap_ok", true)
		var cue := 0.0
		if on and period > 0.0:
			var ph := fposmod(t + float(c["phase"]), period)
			var live := period * float(c["duty"])
			on = ph < live
			if not on:
				var until := period - ph
				cue = clampf(1.0 - until, 0.0, 1.0)
		if on != bool(c["on"]):
			c["on"] = on
			if on and player.alive and player.pos.distance_to(h.pos) < 1100.0:
				play("sfx_ability_forcefield_create" if String(c["kind"]) in ["barrier", "wheel", "bell"] else "start_level", -10.0)
			if hazard_log:
				print("hazard: %s %s t=%.2f" % [String(c["kind"]), "on" if on else "off", t])
		h.active = on
		h.cue = cue
		if String(c["kind"]) == "jump" and on:
			for kart in karts:
				if not kart.alive or kart.air_t > 0.0:
					continue
				if kart.pos.distance_to(h.pos) <= h.radius + kart.RADIUS:
					kart.launch(JUMP_SECONDS, JUMP_BOOST)
					if kart.is_player:
						play("sfx_ability_jump", -4.0)
					if hazard_log:
						print("jump: %s t=%.2f" % [kart.display_name, t])


# The realm's lairs stand by the road and let out their monster every so often.
func _spawn_generators() -> void:
	var lair_tex := QUD.unit_idle("lair") if QUD.has_unit("lair") else null
	var i := 0
	for u in level.get("units", []):
		if not bool(u.get("is_lair", false)):
			continue
		var asset: Array = u.get("asset", [])
		var unit := String(asset[asset.size() - 1]) if asset.size() > 0 else ""
		if not QUD.has_unit(unit):
			continue
		var idx := rng.randi_range(8, track.n - 1)
		var d := track.direction_at(idx)
		var nrm := Vector2(-d.y, d.x)
		var side := 1.0 if (i % 2 == 0) else -1.0
		var pos: Vector2 = track.points[idx] + nrm * side * (track.width * 0.5 + 70.0)
		var holder := Node3D.new()
		holder.position = track.to3(pos)
		add_child(holder)
		if lair_tex != null:
			var base := Sprite3D.new()
			base.texture = lair_tex
			base.hframes = maxi(1, int(QUD.unit_info("lair").get("idle_frames", 1)))
			base.pixel_size = Track.U * 1.3
			base.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			base.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			base.position = Vector3(0, 30 * Track.U, 0)
			holder.add_child(base)
		var s := Sprite3D.new()
		s.texture = QUD.unit_idle(unit)
		s.hframes = maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
		s.pixel_size = Track.U * 0.8 * 60.0 / float(QUD.unit_info(unit).get("frame_size", 60))
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.position = Vector3(0, 52 * Track.U, 0)
		holder.add_child(s)
		var cd := 7.0
		for sp in u.get("spells", []):
			if sp is Dictionary and float(sp.get("cool_down", 0)) > 0.0:
				cd = float(sp["cool_down"]) * 0.8
		generators.append({"pos": pos, "unit": unit, "name": String(u.get("name", "Lair")), "cd": cd, "t": cd * rng.randf_range(0.3, 1.0),
			"road_idx": idx, "spawned": []})
		i += 1


# One of a generator's monsters wandering the road near it, a blocker like the old mobs.
func _spawn_generator_mob(g: Dictionary) -> void:
	var unit: String = g["unit"]
	var s := Sprite3D.new()
	s.texture = QUD.unit_idle(unit)
	s.hframes = maxi(1, int(QUD.unit_info(unit).get("idle_frames", 1)))
	s.pixel_size = Track.U * 60.0 / float(QUD.unit_info(unit).get("frame_size", 60))   # big sheets drawn at one tile
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var d := track.direction_at(int(g["road_idx"]))
	s.set_meta("pos", Vector2(g["pos"]) + Vector2(-d.y, d.x) * -sign((Vector2(g["pos"]) - track.points[int(g["road_idx"])]).dot(Vector2(-d.y, d.x))) * 80.0)
	s.set_meta("vel", Vector2(float(C.get("generator_mob_speed", 60.0)), 0).rotated(rng.randf_range(0, TAU)))
	s.set_meta("blocking", true)
	s.set_meta("t", rng.randf())
	s.set_meta("home", g["pos"])
	add_child(s)
	mobs.append(s)
	g["spawned"].append(s)


func _update_generators(dt: float) -> void:
	var cap := int(C.get("generator_cap", 3))
	for g in generators:
		g["t"] -= dt
		if g["t"] > 0.0:
			continue
		g["t"] = float(g["cd"])
		var alive := []
		for m in g["spawned"]:
			if is_instance_valid(m):
				alive.append(m)
		g["spawned"] = alive
		if alive.size() < cap:
			_spawn_generator_mob(g)


# The realm's pickups: memory orbs give a spell point, components an artifact, rifts decorate the line.
func _spawn_props() -> void:
	var portal_tex := QUD.texture("tiles/portal_dormant_portal.png")
	for p in level.get("props", []):
		var kind := String(p.get("type", ""))
		if kind == "MemoryOrb":
			_spawn_shiny(track.points[rng.randi_range(4, track.n - 1)] + _lane(), "sp")
		elif kind == "ComponentPickup":
			_spawn_shiny(track.points[rng.randi_range(4, track.n - 1)] + _lane(), "trinket")
		elif kind == "Portal" and portal_tex != null:
			var s := Sprite3D.new()
			s.texture = portal_tex
			s.pixel_size = Track.U * 1.4
			s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			var d := track.direction_at(0)
			var nrm := Vector2(-d.y, d.x)
			s.position = track.to3(track.points[0] + nrm * (track.width * 0.5 + 60.0) * (1.0 if rng.randf() < 0.5 else -1.0), 40.0)
			add_child(s)


func _lane() -> Vector2:
	return Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0))


func _shiny_textures() -> void:
	shiny_tex = {
		"spell": QUD.texture("tiles/item_mana_orb.png"),
		"scroll": QUD.texture("tiles/item_spell_scroll.png"),
		"heart": QUD.texture("tiles/item_ruby_heart.png"),
		"sp": QUD.texture("tiles/item_bookshelf.png"),
		"trinket": QUD.texture("tiles/item_trinket.png"),
		"coin": QUD.texture("tiles/item_mana_orb.png"),
	}


func _spawn_item_boxes() -> void:
	_shiny_textures()
	var odds: Dictionary = C.get("shiny_odds", {"spell": 5, "heart": 2, "sp": 2, "trinket": 1}).duplicate()
	if track_spells.is_empty():
		odds.erase("scroll")
	var kinds := odds.keys()
	var weights := PackedFloat32Array()
	for k in kinds:
		weights.append(float(odds[k]))
	_spawn_coin_lines()
	var scroll_i := 0
	for p in track.item_positions():
		var kind: String = kinds[rng.rand_weighted(weights)]
		var box := _spawn_shiny(p, kind)
		if kind == "scroll":
			var sname: String = track_spells[scroll_i % track_spells.size()]
			scroll_i += 1
			_scroll_icon(box, sname)


func _scroll_icon(box: Sprite3D, sname: String) -> void:
	box.set_meta("spell", sname)
	var icon := Sprite3D.new()
	icon.texture = SpellDB.icon(SpellDB.by_name[sname]) if SpellDB.by_name.has(sname) else null
	icon.pixel_size = Track.U * 0.7
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	icon.position = Vector3(0, 42.0 * Track.U, 0)
	box.add_child(icon)


# Speed coins in short lines along the road: each one adds top speed until the kart is hit.
func _spawn_coin_lines() -> void:
	var lines := int(round(float(C.get("coin_lines", 6)) * track.scale_k))
	var per := int(C.get("coins_per_line", 5))
	if lines <= 0 or track.n < 20:
		return
	for li in lines:
		var start := rng.randi_range(4, track.n - 1)
		var lane := rng.randf_range(-0.55, 0.55)
		for c in per:
			var idx := (start + c) % track.n
			var d := track.direction_at(idx)
			var nrm := Vector2(-d.y, d.x)
			var s := _spawn_shiny(track.points[idx] + nrm * lane * track.width * 0.5, "coin")
			s.modulate = Color(1.0, 0.85, 0.3)
			s.pixel_size = Track.U * 0.6


func _spawn_shiny(p: Vector2, kind: String, respawn := true) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = shiny_tex.get(kind, shiny_tex["spell"])
	s.pixel_size = Track.U * 0.9
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.set_meta("pos", p)
	s.set_meta("kind", kind)
	s.set_meta("respawn", 0.0)
	s.set_meta("respawns", respawn)
	s.set_meta("net", next_box_id)
	next_box_id += 1
	s.position = track.to3(p, 30.0)
	add_child(s)
	item_boxes.append(s)
	if host and net_live:
		_net_ev(["shiny", int(s.get_meta("net")), p.x, p.y, kind, respawn])
	return s


func _spawn_mobs() -> void:
	var density := track.scale_k * track.scale_k
	for spec in [["bat", 4, 160.0, false], ["green_slime", 3, 25.0, true]]:
		if not QUD.has_unit(spec[0]):
			continue
		for _i in int(round(spec[1] * density)):
			var i := rng.randi_range(6, track.n - 1)
			var d := track.direction_at(i)
			var nrm := Vector2(-d.y, d.x)
			var s := Sprite3D.new()
			s.texture = QUD.unit_idle(spec[0])
			s.hframes = maxi(1, int(QUD.unit_info(spec[0]).get("idle_frames", 1)))
			s.pixel_size = Track.U
			s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.set_meta("pos", track.points[i] + nrm * rng.randf_range(-0.3, 0.3) * track.width)
			s.set_meta("vel", Vector2(spec[2], 0).rotated(rng.randf_range(0, TAU)))
			s.set_meta("blocking", spec[3])
			s.set_meta("t", rng.randf())
			add_child(s)
			mobs.append(s)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = float(Shared.t(["godot", "cam_fov"], 70.0))
	cam.near = 0.2
	cam.far = 2000.0
	add_child(cam)
	cam.current = true
	cam_yaw = player.heading


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
	lbl_realm = _label(22, Color(1.0, 0.93, 0.35))
	lbl_realm.position = Vector2(28, 14)
	lbl_lap = _label(36)
	lbl_lap.position = Vector2(28, 40)
	lbl_pos = _label(36)
	lbl_pos.position = Vector2(28, 82)
	lbl_time = _label(22)
	lbl_time.position = Vector2(28, 128)

	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.7)
	hp_bg.position = Vector2(28, 162)
	hp_bg.size = Vector2(300, 24)
	hud.add_child(hp_bg)
	hp_fill = ColorRect.new()
	hp_fill.color = Color(0.9, 0.11, 0.14)
	hp_fill.position = hp_bg.position
	hp_fill.size = Vector2(300, 24)
	hud.add_child(hp_fill)
	lbl_hp = _label(18)
	lbl_hp.position = Vector2(34, 162)
	lbl_sp = _label(22, Color(0.55, 0.85, 1.0))
	lbl_sp.position = Vector2(28, 192)

	lbl_street = _label(26, Color(1.0, 0.93, 0.35))
	lbl_street.position = Vector2(960 - 300, 40)
	lbl_street.size = Vector2(600, 34)
	lbl_street.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_track = _label(20, Color(0.85, 0.85, 0.85))
	lbl_track.text = track.track_name
	lbl_track.position = Vector2(960 - 200, 10)
	lbl_track.size = Vector2(400, 30)
	lbl_track.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_center = _label(84, Color(1.0, 0.93, 0.35))
	lbl_center.position = Vector2(0, 400)
	lbl_center.size = Vector2(1920, 120)
	lbl_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_help = _label(20)
	lbl_help.text = "WASD/arrows drive   shift/space drift   E pickup   1-0 cast   hold Q quick shop   Tab shop   F free drive"
	if rig:
		lbl_help.text = "1-0 cast   L spells   N enemies   Z slow-motion   K attacks   [ ] realm   Tab shop   F free drive   WASD drive   shift drift"
	elif debug:
		lbl_help.text += "   K attacks on/off   [ ] realm"
	lbl_help.position = Vector2(0, 520)
	lbl_help.size = Vector2(1920, 30)
	lbl_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var slot := ColorRect.new()
	slot.color = Color(0, 0, 0, 0.55)
	slot.position = Vector2(1920 - 140, 24)
	slot.size = Vector2(110, 110)
	hud.add_child(slot)
	item_icon = TextureRect.new()
	item_icon.position = Vector2(1920 - 130, 34)
	item_icon.size = Vector2(90, 90)
	item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item_icon.stretch_mode = TextureRect.STRETCH_SCALE
	item_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hud.add_child(item_icon)
	lbl_item = _label(18)
	lbl_item.position = Vector2(1920 - 180, 140)
	lbl_item.size = Vector2(190, 24)
	lbl_item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	speed_bar = ColorRect.new()
	speed_bar.color = Color(0, 0, 0, 0.7)
	speed_bar.position = Vector2(28, 1080 - 60)
	speed_bar.size = Vector2(300, 22)
	hud.add_child(speed_bar)
	speed_fill = ColorRect.new()
	speed_fill.color = Color(0.9, 0.11, 0.14)
	speed_fill.position = speed_bar.position
	speed_fill.size = Vector2(0, 22)
	hud.add_child(speed_fill)
	lbl_drift = _label(20, Color(1.0, 0.93, 0.35))
	lbl_drift.position = Vector2(342, 1080 - 62)
	lbl_stats = _label(18, Color(0.67, 0.67, 0.67))
	lbl_stats.position = Vector2(28, 1080 - 84)

	# action bar: ten slots, keys 1-0
	var x0 := 960 - (10 * 74) / 2
	for i in Campaign.MAX_SLOTS:
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
		var key := _label(16, Color(0.8, 0.8, 0.8))
		key.text = str((i + 1) % 10)
		key.position = bg.position + Vector2(6, 62)
		var ch := _label(18, Color(1.0, 0.93, 0.35))
		ch.position = bg.position + Vector2(40, 60)
		slot_charges.append(ch)

	artifact_row = HBoxContainer.new()
	artifact_row.position = Vector2(1920 - 28 - 10 * 46, 170)
	artifact_row.add_theme_constant_override("separation", 2)
	artifact_row.alignment = BoxContainer.ALIGNMENT_END
	artifact_row.size = Vector2(10 * 46, 44)
	hud.add_child(artifact_row)

	# quick shop: a strip of offers shown in slow motion while Q is held
	quick = CanvasLayer.new()
	quick.layer = 15
	quick.visible = false
	add_child(quick)
	var qbg := ColorRect.new()
	qbg.color = Color(0, 0, 0, 0.7)
	qbg.position = Vector2(960 - 4 * 190, 640)
	qbg.size = Vector2(8 * 190, 200)
	quick.add_child(qbg)
	var qt := Label.new()
	qt.text = "QUICK SHOP   press 1-4 to buy   release Q to race"
	qt.add_theme_font_override("font", QUD.font())
	qt.add_theme_font_size_override("font_size", 24)
	qt.add_theme_color_override("font_color", Color(1.0, 0.93, 0.35))
	qt.position = qbg.position + Vector2(20, 10)
	quick.add_child(qt)
	for i in int(C.get("quick_offers", 4)):
		var icon := TextureRect.new()
		icon.position = qbg.position + Vector2(30 + i * 370, 50)
		icon.size = Vector2(80, 80)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		quick.add_child(icon)
		quick_icons.append(icon)
		var l := Label.new()
		l.add_theme_font_override("font", QUD.font())
		l.add_theme_font_size_override("font_size", 20)
		l.position = qbg.position + Vector2(120 + i * 370, 50)
		l.size = Vector2(240, 130)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		quick.add_child(l)
		quick_labels.append(l)

	minimap = MiniMap.new()
	minimap.race = self
	minimap.position = Vector2(1920 - 28 - 300, 1080 - 28 - 300)
	minimap.size = Vector2(300, 300)
	hud.add_child(minimap)

	results = _label(30)
	results.position = Vector2(660, 260)
	results.visible = false


func play(name: String, volume_db := 0.0) -> void:
	Audio.play(name, volume_db)


# ---------------------------------------------------------------- simulation

func _set_free(on: bool) -> void:
	if on == free_mode:
		return
	free_mode = on
	track.set_free_mode(on)
	if on:
		state_before_free = state
		state = FREE
		say("FREE DRIVE", 1.5)
	else:
		state = state_before_free if state_before_free != "" and state_before_free != COUNTDOWN else RACING
		say("RACE ON", 1.5)


func _physics_process(dt: float) -> void:
	if state == DEAD and seconds_limit > 0.0:
		t += dt   # a timed run still ends after the results screen
		if t >= seconds_limit:
			seconds_limit = -1.0
			frames_left = -1
			_finish_screenshot()
	if guest:
		_guest_step(dt)
		return
	if not running or paused or state == GATES or state == DEAD:
		return
	t += dt
	message_t = maxf(0.0, message_t - dt)
	if state == FREE:
		_free_step(dt)
		return

	if host:
		_host_receive()
	if party:
		human_frames = Players.frames()
		for kart in humans:
			if kart.respawn_t > 0.0:
				kart.respawn_t -= dt
				if kart.respawn_t <= 0.0:
					_respawn_human(kart)
	if state == COUNTDOWN:
		var before := int(ceil(countdown))
		countdown -= dt
		if int(ceil(countdown)) != before and countdown > 0.0:
			play("menu_confirm")
		for kart in karts:
			_track_start_hold(kart, dt)
		if countdown <= 0.0:
			state = RACING
			say("GO!", 1.0)
			play("start_level")
			_resolve_start_boosts()
	elif state == RACING:
		race_time += dt

	for kart in karts:
		var throttle := 0.0
		var steer := 0.0
		var drift := false
		var use := false
		if state != COUNTDOWN:
			if party and kart.human >= 0 and not kart.finished and (not auto_player or kart.remote):
				var f: DriveFrame = human_frames[kart.human] if kart.human < human_frames.size() else DriveFrame.neutral(0, "")
				if kart.respawn_t <= 0.0:
					throttle = f.throttle
					steer = f.steer
					drift = f.drift_held
					use = f.item_pressed
			elif kart.is_player and not auto_player and not kart.finished:
				throttle = Input.get_action_strength("drive_forward") - Input.get_action_strength("drive_back")
				steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
				drift = Input.is_action_pressed("drift")
				use = Input.is_action_just_pressed("cast")
			else:
				var c: Dictionary = kart.rig_control(dt, track, player, R) if kart.archetype != "" else kart.ai_control(dt, track, karts, kart.ai_drift_prob)
				throttle = c["throttle"] * (0.6 if kart.finished else 1.0)
				steer = c["steer"]
				drift = c["drift"]
				use = c["use"]
		if rig and rig_kinematic and kart.archetype != "":
			kart.rig_move(dt, track, player, R)
		else:
			kart.apply_control(dt, throttle, steer, drift, track)
		if use and kart.item != "" and state == RACING:
			_net_ev(["item", kart.net_id, kart.item])
			Items.use(self, kart)
		if track.advance(kart):
			if party and kart.human >= 0 and state == RACING:
				_human_lap(kart)
			elif kart.is_player and state == RACING and not rig:
				_player_lap()
			if kart.lap > laps and not kart.finished:
				kart.finished = true
				kart.finish_time = race_time
				finish_order.append(kart)
				if kart.is_player:
					say("FINISHED %s" % ordinal(finish_order.size()), 3.0)

	if state == RACING:
		_update_generators(dt)
		Campaign.tick_cooldowns(dt)
		if party:
			_party_casts(dt)
		else:
			_player_casts()
		_late_start_boosts(dt)
		_update_slipstream(dt)
		if rig:
			_rig_step(dt)
		else:
			_update_abilities(dt)
	_collide_karts()
	_update_items(dt)
	_update_world(dt)
	_update_ranks()

	var all_done := player.finished
	if party:
		all_done = true
		for h in humans:
			if not h.finished:
				all_done = false
	if state == RACING and all_done:
		finish_hold += dt
		if finish_hold > 2.0:
			_level_complete()

	_update_camera(dt)
	if not panels.is_empty():
		_update_panels(dt)
	if host:
		net_ticks += 1
		if net_ticks % 3 == 0:
			_host_broadcast()
	if seconds_limit > 0.0 and t >= seconds_limit:
		seconds_limit = -1.0
		frames_left = -1
		_finish_screenshot()


# ---------------------------------------------------------------- test rig

func _rig_step(dt: float) -> void:
	for kart in karts:
		if not (rig_kinematic and kart.archetype != ""):
			kart.update_route(track)
	if player.boost_t > 0.0:
		player_boost_total += dt
	wolves_peak = maxi(wolves_peak, escorts.size())
	if int(t) != int(t - dt):
		var row := {"t": int(t), "player_speed": int(player.speed()), "player_road": track.on_road(player.pos, player.next_wp), "npcs": []}
		for kart in karts:
			if kart.archetype != "":
				row["npcs"].append([kart.archetype, int(kart.route_px - player.route_px), int(kart.speed()), track.on_road(kart.pos, kart.next_wp), int(kart.stun_t * 10) / 10.0])
		rig_trace.append(row)
	for c in rig_casts.duplicate():
		if t >= float(c["t"]):
			rig_casts.erase(c)
			_rig_cast(String(c["name"]))
	if t > float(R.get("settle_time", 3.0)):
		for kart in karts:
			if kart.archetype == "" or kart.archetype == "parked" or kart.archetype == "beside":
				continue
			if kart.stun_t > 0.0:
				kart.rig_recover = float(R.get("recover_time", 5.0))
				continue
			if kart.rig_recover > 0.0:
				kart.rig_recover -= dt
				continue
			var err := absf(kart.route_px - player.route_px - kart.rig_dist)
			var g: Array = rig_gaps.get(kart.display_name, [0.0, 0.0, 0])
			g[0] += err
			g[1] = maxf(g[1], err)
			g[2] += 1
			rig_gaps[kart.display_name] = g


func _rig_cast(name: String) -> void:
	var idx := -1
	for i in Campaign.spells.size():
		if Campaign.spells[i]["name"] == name:
			idx = i
	var rec := {"name": name, "t": t, "slot": idx, "ok": false, "kind": "", "before": _rig_snapshot()}
	if idx >= 0:
		var s: Dictionary = Campaign.spells[idx]
		rec["kind"] = String(s["effect"]["kind"])
		rec["effect"] = s["effect"]
		rec["unlimited"] = bool(s.get("unlimited", false))
		rec["hp_cost"] = int(s.get("hp_cost", 0))
		rec["charges_before"] = int(s["charges"])
		rec["ready"] = Campaign.slot_ready(idx)
		if rec["ready"]:
			rec["ok"] = cast_for(player, s)
			if rec["ok"]:
				_spend(idx)
		rec["charges_after"] = int(s["charges"])
		rec["cd_after"] = float(s.get("cd", 0.0))
	rec["after"] = _rig_snapshot()
	rig_log.append(rec)
	print("rig cast: %s ok=%s kind=%s" % [name, rec["ok"], rec["kind"]])


func _rig_snapshot() -> Dictionary:
	var npcs := []
	player.update_route(track)
	var p_px := player.route_px
	var boost_left := player.boost_t
	for b in player.boosts.values():
		boost_left = maxf(boost_left, float(b[1]))
	for kart in karts:
		if kart.is_player:
			continue
		npcs.append({"name": kart.display_name, "archetype": kart.archetype, "hp": kart.hp, "damage_taken": kart.damage_taken,
			"stun_t": kart.stun_t, "stun_total": kart.stun_total, "slip_t": kart.slip_t, "alive": kart.alive,
			"gap_px": kart.route_px - p_px, "speed": kart.speed()})
	var bonuses := {}
	for key in Artifacts.KEYS:
		var b := Campaign.bonus(key)
		if b != 0.0:
			bonuses[key] = b
	return {"t": t, "hp": Campaign.hp, "shields": player.shields, "boost_t": boost_left, "boost_mult": player.boost_mult,
		"progress_px": p_px, "speed": player.speed(), "wolves": escorts.size(), "projectiles": projectiles.size(),
		"patches": patches.size(), "hazards": hazards.size(), "auras": auras.size(), "bonuses": bonuses, "coins": player.coins, "npcs": npcs}


func _rig_report() -> Dictionary:
	var gaps := []
	for kart in karts:
		if kart.archetype == "":
			continue
		var g: Array = rig_gaps.get(kart.display_name, [0.0, 0.0, 0])
		gaps.append({"name": kart.display_name, "archetype": kart.archetype, "dist": kart.rig_dist, "lat": kart.rig_lat,
			"mean_err": g[0] / maxi(1, g[2]), "max_err": g[1], "samples": g[2], "alive": kart.alive})
	var names := []
	for s in Campaign.spells:
		names.append(s["name"])
	var arts := []
	for a in Campaign.artifacts:
		arts.append(a["name"])
	var bonuses := {}
	for key in Artifacts.KEYS:
		var b := Campaign.bonus(key)
		if b != 0.0:
			bonuses[key] = b
	return {"track": track.key, "t": t, "frames": frame_count, "end": _rig_snapshot(), "casts": rig_log, "gaps": gaps,
		"player_boost_total": player_boost_total, "wolves_peak": wolves_peak, "slain": slain, "spells": names,
		"artifacts": arts, "bonuses": bonuses, "tally": tally, "trace": rig_trace}


# Free drive: the wizard roams the whole grid, monsters keep running their route,
# no laps, no lap rule, no abilities.
func _free_step(dt: float) -> void:
	for kart in karts:
		var throttle := 0.0
		var steer := 0.0
		var drift := false
		if kart.is_player and not auto_player:
			throttle = Input.get_action_strength("drive_forward") - Input.get_action_strength("drive_back")
			steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
			drift = Input.is_action_pressed("drift")
		else:
			var c: Dictionary = kart.ai_control(dt, track, karts, kart.ai_drift_prob)
			throttle = c["throttle"]
			steer = c["steer"]
			drift = c["drift"]
		kart.apply_control(dt, throttle, steer, drift, track)
		if not kart.is_player:
			track.advance(kart)
	_collide_karts()
	_update_world(dt)
	for kart in karts:
		kart.progress = track.progress(kart)
	_update_camera(dt)


func say(text: String, duration := 1.2) -> void:
	message = text
	message_t = duration


static func ordinal(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		suf = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, suf]


func _player_casts() -> void:
	if quick_open:
		return
	if not player_ability.is_empty():
		player_ability_cd = maxf(0.0, player_ability_cd - 1.0 / 60.0)
		var want := (Input.is_action_just_pressed("cast") or Input.is_action_just_pressed("slot_1")) and not auto_player
		if auto_player and fmod(t, 3.0) < 1.0 / 60.0 * 1.5:
			want = true
		if want and player_ability_cd <= 0.0:
			if cast_for(player, player_ability):
				player_ability_cd = float(C.get("monster_racer_cooldown", 3.0))
				tally["casts"] += 1
		return
	if auto_player:
		if rig_scripted:
			return
		# the demo driver casts whatever is ready every couple of seconds
		if fmod(t, 2.5) < 1.0 / 60.0 * 1.5:
			for i in Campaign.spells.size():
				if Campaign.slot_ready(i) and cast_for(player, Campaign.spells[i]):
					_spend(i)
					break
		return
	for i in Campaign.MAX_SLOTS:
		if Input.is_action_just_pressed("slot_%d" % (i + 1)) and Campaign.slot_ready(i):
			if cast_for(player, Campaign.spells[i]):
				_spend(i)


func cast_for(kart: Kart, spell: Dictionary) -> bool:
	var ok := Items.cast_spell(self, kart, spell)
	if ok and host:
		_net_ev(["cast", kart.net_id, String(spell["name"])])
	return ok


# Pay for a cast that went off: a charge or a cooldown, plus the spell's HP cost.
func _spend(i: int) -> void:
	var cost := int(Campaign.spells[i].get("hp_cost", 0))
	Campaign.spend_charge(i)
	tally["casts"] += 1
	if cost > 0:
		player.hp = Campaign.hp
		spawn_effect(QUD.effect("blood"), player.position + Vector3(0, 30 * Track.U, 0), 6, 0.06, -1.0, 1.2)
		say("-%d HP" % cost, 0.6)


# The lap rule: leading, every monster takes damage; otherwise you take damage per rank behind.
func _player_lap() -> void:
	Campaign.lap_refill()
	Campaign.roll_offers(int(C.get("quick_offers", 4)))
	if Campaign.bonus("lap_heal") > 0.0:
		heal_kart(player, Campaign.bonus("lap_heal"))
	if Campaign.bonus("lap_shield") > 0.0:
		player.shields += int(Campaign.bonus("lap_shield"))
	if player.rank <= 1:
		# a share of each monster's max HP, so realm-1 bats and realm-20 arbiters both need several leading laps
		var pct := float(C.get("lap_damage_lead_pct", 0.2))
		var min_dmg := float(C.get("lap_damage_lead_min", 2))
		for kart in karts.duplicate():
			if not kart.is_player and kart.alive:
				var dmg: float = maxf(min_dmg, kart.max_hp * pct) + Campaign.bonus("lap_damage")
				hit_kart(kart, dmg, "Holy", player, 0.4, "lap")
		say("LAP IN 1ST: MONSTERS TAKE %d%%" % int(pct * 100), 1.6)
		play("victory_level")
	else:
		var dmg := minf(float(C.get("lap_damage_cap", 8)), float(C.get("lap_damage_per_rank", 2)) * (player.rank - 1))
		hit_kart(player, dmg, "Dark", null, 0.0, "lap")
		say("LAP IN %s: -%d HP" % [ordinal(player.rank), int(dmg)], 1.6)


func _track_start_hold(kart: Kart, dt: float) -> void:
	var pressed := false
	if party and kart.human >= 0:
		pressed = kart.human < human_frames.size() and human_frames[kart.human].throttle > 0.5
	elif kart.is_player and not auto_player:
		pressed = Input.is_action_pressed("drive_forward")
	else:
		pressed = countdown <= kart.ai_reaction
	kart.start_hold = kart.start_hold + dt if pressed else 0.0


func _resolve_start_boosts() -> void:
	var st: Dictionary = Shared.tuning.get("start", {})
	for kart in karts:
		var hold: float = kart.start_hold
		if hold > float(st.get("burnout_hold", 0.9)):
			kart.stun(float(st.get("burnout_stun", 0.7)))
			if kart.is_player:
				say("BURNOUT", 1.2)
		elif hold > 0.0 and hold <= float(st.get("window_before", 0.35)):
			kart.add_boost("start", float(st.get("strength", 0.35)), float(st.get("time", 1.0)))
			if kart.is_player:
				say("ROCKET START", 1.2)
	start_grace = float(st.get("window_after", 0.15))


func _late_start_boosts(dt: float) -> void:
	if start_grace <= 0.0:
		return
	start_grace -= dt
	var st: Dictionary = Shared.tuning.get("start", {})
	if not auto_player and not player.boosts.has("start") and player.stun_t <= 0.0:
		if Input.is_action_pressed("drive_forward"):
			player.add_boost("start", float(st.get("strength", 0.35)) * 0.6, float(st.get("time", 1.0)))
			say("GOOD START", 1.0)
			start_grace = 0.0


func _update_slipstream(dt: float) -> void:
	var sl: Dictionary = Shared.tuning.get("slipstream", {})
	var length := float(sl.get("length", 360.0))
	var width := float(sl.get("width", 70.0))
	var min_ratio := float(sl.get("min_speed_ratio", 0.6))
	var collect := float(sl.get("collect_time", 1.5))
	for a in karts:
		a.in_slip = false
		var fwd: Vector2 = a.forward()
		var side := Vector2(-fwd.y, fwd.x)
		for b in karts:
			if b == a:
				continue
			var rel: Vector2 = b.pos - a.pos
			var ahead := rel.dot(fwd)
			if ahead > 0.0 and ahead < length and absf(rel.dot(side)) < width and b.speed() > min_ratio * b.max_speed and a.speed() > 200.0:
				a.in_slip = true
				break
		if a.in_slip:
			a.slip_charge += dt
			if a.slip_charge >= collect:
				a.add_boost("slipstream", float(sl.get("strength", 0.18)), float(sl.get("time", 1.6)))
				a.slip_charge = 0.0
		else:
			a.slip_charge = maxf(0.0, a.slip_charge - dt * 2.0)


# Monsters use their real spell against the wizard on a cooldown.
func _update_abilities(dt: float) -> void:
	if not player.alive or not attacks_on:
		return
	var cd: Array = C.get("ability_cooldown", [4.0, 8.0])
	for kart in karts:
		if kart.is_player or not kart.alive or kart.ability_spell.is_empty():
			continue
		kart.ability_cd -= dt
		if kart.ability_cd > 0.0 or kart.stun_t > 0.0:
			continue
		var e: Dictionary = kart.ability_spell["effect"]
		var reach := maxf(300.0, float(e.get("range", e.get("radius", 300.0))) * 1.2)
		if kart.pos.distance_to(player.pos) > reach:
			continue
		if cast_for(kart, kart.ability_spell):
			kart.ability_cd = kart.rng.randf_range(float(cd[0]), float(cd[1]))
			play("enemy", -8.0)
		else:
			kart.ability_cd = 0.5


func _behind_frac(kart: Kart) -> float:
	var leader: Kart = karts[0]
	for k in karts:
		if k.progress > leader.progress:
			leader = k
	var px := maxf(0.0, (leader.progress - kart.progress) * spacing)
	px *= 1.0 + maxi(0, 8 - karts.size()) * float(Shared.t(["items", "small_field_pct"], 0.125))
	var seconds := px / float(Shared.t(["kart", "max_speed"], 780.0))
	return minf(1.0, seconds / float(Shared.t(["items", "far_seconds"], 8.0)))


func _collide_karts() -> void:
	var min_d := player.RADIUS * 2.0
	var push_k := float(Shared.t(["bump", "push"], 0.5))
	for i in karts.size():
		for j in range(i + 1, karts.size()):
			var a: Kart = karts[i]
			var b: Kart = karts[j]
			var rel: Vector2 = b.pos - a.pos
			var d2 := rel.length_squared()
			if d2 <= 0.0 or d2 >= min_d * min_d:
				continue
			var d := sqrt(d2)
			var total := a.mass + b.mass
			var push := rel / d * (min_d - d) * push_k * 2.0
			a.pos -= push * (b.mass / total)
			b.pos += push * (a.mass / total)
			var va := a.vel
			var vb := b.vel
			var wa := a.mass / total
			a.vel = va * (0.4 + 0.6 * wa) + vb * (0.6 * (1.0 - wa))
			b.vel = vb * (0.4 + 0.6 * (1.0 - wa)) + va * (0.6 * wa)


func _update_items(dt: float) -> void:
	var respawn := float(Shared.t(["items", "respawn"], 5.0))
	for box in item_boxes.duplicate():
		var r: float = box.get_meta("respawn")
		r = maxf(0.0, r - dt)
		box.set_meta("respawn", r)
		box.visible = r <= 0.0
		if r > 0.0:
			continue
		var p: Vector2 = box.get_meta("pos")
		var kind: String = box.get_meta("kind")
		box.position = track.to3(p, 30.0 + sin(t * 4.0) * 5.0)
		for kart in karts:
			if kart.pos.distance_squared_to(p) >= 34.0 * 34.0:
				continue
			var taken := false
			if kart.no_items:
				continue
			if kind == "coin":
				var cmax := int(C.get("coin_max", 6))
				if kart.coins < cmax:
					kart.coins += 1
					taken = true
					if kart.is_player:
						play("item_pickup", -4.0)
			elif kind == "spell":
				if kart.item == "":
					kart.item = Items.roll(kart.rng, _behind_frac(kart))
					taken = true
					if kart.is_player:
						play("item_pickup")
			elif kart.is_player:
				taken = true
				play("item_pickup")
				if kind == "heart":
					heal_kart(kart, float(C.get("heart_heal", 15)))
					_say_to(kart, "+%d HP" % int(C.get("heart_heal", 15)), 0.8)
				elif kind == "sp":
					Campaign.sp += 1
					say("+1 SPELL POINT", 0.8)
				elif kind == "scroll":
					var sname: String = box.get_meta("spell")
					var res := "full"
					if SpellDB.by_name.has(sname):
						res = _human_learn(kart, SpellDB.by_name[sname]) if party else Campaign.learn(SpellDB.by_name[sname])
					if res == "learned":
						_say_to(kart, "LEARNED %s" % sname.to_upper(), 1.4)
						play("learn_spell")
					elif res == "charge":
						_say_to(kart, "%s +1 CHARGE" % sname.to_upper(), 1.0)
					else:
						_say_to(kart, "SPELLBOOK FULL", 1.0)
						taken = false
				elif kind == "trinket":
					var art := Campaign.grant_random_artifact()
					if art.is_empty():
						Campaign.sp += 2
						say("TRINKET: +2 SPELL POINTS", 0.8)
					else:
						say("ARTIFACT: %s" % String(art["name"]).to_upper(), 2.0)
						_refresh_artifacts()
			if taken:
				if bool(box.get_meta("respawns")):
					box.set_meta("respawn", respawn)
					_net_ev(["box", int(box.get_meta("net")), respawn])
				else:
					_net_ev(["box", int(box.get_meta("net")), -1.0])
					item_boxes.erase(box)
					box.queue_free()
				break


func _update_world(dt: float) -> void:
	for p in projectiles.duplicate():
		var alive: bool = p.tick(dt, track)
		var hit: Kart = null
		for kart in karts:
			if kart == p.owner_kart and p.age < 0.3:
				continue
			if p.player_only and not kart.is_player:
				continue
			if kart.alive and kart.pos.distance_squared_to(p.pos) < pow(kart.RADIUS + 18.0 + p.radius * 0.8, 2):
				hit = kart
				break
		if hit != null:
			play(p.hit_sound, -2.0)     # the slug's impact, the grenade's detonation
			if p.radius > 0.0:
				for kart in karts.duplicate():
					if kart != p.owner_kart and kart.alive and kart.pos.distance_to(p.pos) < p.radius + kart.RADIUS + 18.0:
						hit_kart(kart, p.damage, p.dtype, p.owner_kart, p.stun, p.cause)
						if p.heal_frac > 0.0 and p.owner_kart != null and is_instance_valid(p.owner_kart):
							heal_kart(p.owner_kart, p.damage * p.heal_frac)
				spawn_effect(Items.effect_strip(p.dtype), p.position, 6, 0.07, -1.0, 2.0 + p.radius / 90.0)
			else:
				hit_kart(hit, p.damage, p.dtype, p.owner_kart, p.stun, p.cause)
				if p.shove != 0.0 and p.vel.length_squared() > 1.0:
					hit.vel += p.vel.normalized() * p.shove
			if p.radius <= 0.0 and p.heal_frac > 0.0 and p.owner_kart != null and is_instance_valid(p.owner_kart):
				heal_kart(p.owner_kart, p.damage * p.heal_frac)
			alive = false
		elif not alive:
			if p.radius > 0.0:
				play(p.hit_sound, -4.0)  # a grenade going off where it fell
			spawn_effect(Items.effect_strip(p.dtype), p.position, 6, 0.05)
		if not alive:
			projectiles.erase(p)
			p.queue_free()

	_update_course_hazards(dt)
	for h in hazards.duplicate():
		if not h.tick_hazard(dt):
			hazards.erase(h)
			h.queue_free()
			continue
		if h.next_tick > 0.0 or not h.active:
			continue
		h.next_tick = h.tick
		for kart in karts.duplicate():
			if kart == h.owner_kart or not kart.alive or kart.air_t > 0.0:
				continue
			if kart.pos.distance_to(h.pos) > h.radius + kart.RADIUS:
				continue
			if h.damage > 0.0 or h.stun > 0.0:
				hit_kart(kart, h.damage, h.dtype, h.owner_kart, h.stun, "hazard")
			if h.slip:
				kart.slip_t = maxf(kart.slip_t, 1.2)

	for a in auras.duplicate():
		a["left"] -= dt
		a["next"] -= dt
		var owner: Kart = a["owner"]
		if a["left"] <= 0.0 or not is_instance_valid(owner) or not owner.alive:
			auras.erase(a)
			continue
		if a["next"] > 0.0:
			continue
		a["next"] = float(a["tick"])
		if float(a["heal"]) > 0.0:
			heal_kart(owner, float(a["heal"]))
		if float(a["damage"]) <= 0.0 and float(a["stun"]) <= 0.0 and float(a["shove"]) == 0.0 and not bool(a["slip"]):
			continue
		var near := []
		for kart in karts:
			if not Items.valid_target(owner, kart):
				continue
			if kart.pos.distance_to(owner.pos) <= float(a["radius"]) + kart.RADIUS:
				near.append(kart)
		near.sort_custom(func(x, y): return x.pos.distance_squared_to(owner.pos) < y.pos.distance_squared_to(owner.pos))
		var n := int(a["targets"])
		if n > 0:
			near = near.slice(0, n)
		for kart in near:
			if float(a["damage"]) > 0.0:
				hit_kart(kart, float(a["damage"]), String(a["dtype"]), owner, float(a["stun"]), "aura")
			elif float(a["stun"]) > 0.0:
				kart.stun(float(a["stun"]))
			if bool(a["slip"]):
				kart.slip_t = maxf(kart.slip_t, 1.2)
			if float(a["shove"]) != 0.0:
				var away: Vector2 = (kart.pos - owner.pos).normalized()
				kart.vel += away * float(a["shove"])
			if float(a["heal_frac"]) > 0.0:
				heal_kart(owner, float(a["damage"]) * float(a["heal_frac"]))
			spawn_bolt(owner.position, kart.position, Items.type_color(String(a["dtype"])))

	for patch in patches.duplicate():
		if not patch.tick(dt):
			patches.erase(patch)
			patch.queue_free()
			continue
		for kart in karts:
			if kart == patch.owner_kart and patch.t < 1.5:
				continue
			if kart.pos.distance_squared_to(patch.pos) < patch.RADIUS * patch.RADIUS and kart.slip_t <= 0.2:
				if kart.slip_t <= 0.0:
					var e := spawn_effect(QUD.effect("ice"), kart.position, 6)
					e.follow = kart
				kart.slip_t = 1.4

	_update_escorts(dt)

	for mob in mobs:
		var pos: Vector2 = mob.get_meta("pos")
		var vel: Vector2 = mob.get_meta("vel")
		var mt: float = mob.get_meta("t") + dt
		pos += vel * dt
		if pos.x < 40.0 or pos.x > track.size.x - 40.0:
			vel.x *= -1.0
		if pos.y < 40.0 or pos.y > track.size.y - 40.0:
			vel.y *= -1.0
		if rng.randf() < 0.3 * dt:
			vel = vel.rotated(deg_to_rad(rng.randf_range(-60.0, 60.0)))
		if mob.has_meta("home") and pos.distance_to(mob.get_meta("home")) > 420.0:
			vel = (Vector2(mob.get_meta("home")) - pos).normalized() * vel.length()
		mob.set_meta("pos", pos)
		mob.set_meta("vel", vel)
		mob.set_meta("t", mt)
		var lift: float = 0.0 if mob.get_meta("blocking") else 30.0
		mob.position = track.to3(pos, lift) + Vector3(0, 30.0 * Track.U, 0)
		mob.frame = int(mt / 0.2) % maxi(1, mob.hframes)
		mob.flip_h = vel.dot(cam_right) < 0.0
		if not mob.get_meta("blocking"):
			continue
		for kart in karts:
			var rel: Vector2 = kart.pos - pos
			if rel.length_squared() < pow(kart.RADIUS + 24.0, 2) and rel.length_squared() > 0.0:
				kart.pos += rel.normalized() * 6.0
				kart.vel *= 0.6
				if kart.stun_t <= 0.0 and kart.speed() > 250.0:
					kart.stun(0.4)
					if kart.is_player:
						hit_kart(kart, float(C.get("mob_damage", 2)), "Physical", null, 0.0, "mob")

	for e in effects.duplicate():
		if not e.tick(dt):
			effects.erase(e)
			e.queue_free()
	for b in bolts.duplicate():
		b.set_meta("life", float(b.get_meta("life")) - dt)
		if float(b.get_meta("life")) <= 0.0:
			bolts.erase(b)
			b.queue_free()


func _update_ranks() -> void:
	for kart in karts:
		kart.progress = track.progress(kart)
	var finished := finish_order.duplicate()
	finished.sort_custom(func(a, b): return a.finish_time < b.finish_time)
	var rest := karts.filter(func(k): return not k.finished)
	rest.sort_custom(func(a, b): return a.progress > b.progress)
	var i := 1
	for kart in finished + rest:
		kart.rank = i
		i += 1
	var ai: Dictionary = Shared.tuning.get("ai", {})
	var floor_ := float(ai.get("skill_floor", 0.93))
	var cap: Array = ai.get("speed_cap", [[0, 1.0]])
	var dprob: Array = ai.get("drift_prob", [[0, 0.6]])
	for kart in karts:
		if kart.is_player:
			kart.speed_scale = 1.0 + Campaign.bonus("speed")
			continue
		if kart.archetype != "":
			continue
		var ahead_px: float = (kart.progress - player.progress) * spacing
		kart.speed_scale = Kart.interp(cap, ahead_px) * (floor_ + (1.0 - floor_) * kart.ai_skill)
		kart.ai_drift_prob = Kart.interp(dprob, ahead_px)


# ---------------------------------------------------------------- local multiplayer (party)

# A human kart at zero HP: out for a few seconds, then back on the line where it fell.
func _human_down(kart: Kart) -> void:
	kart.respawn_t = float(C.get("party_respawn", 3.0))
	kart.vel = Vector2.ZERO
	kart.stun(kart.respawn_t)
	kart.coins = 0
	spawn_effect(QUD.effect("dark"), kart.position + Vector3(0, 30 * Track.U, 0), 6, 0.07, -1.0, 2.0)
	play("death_player")
	_net_ev(["down", kart.net_id])
	_say_to(kart, "WRECKED", 2.0)


func _respawn_human(kart: Kart) -> void:
	kart.hp = kart.max_hp
	if kart == player:
		Campaign.hp = kart.hp
	kart.shields = 0
	kart.stun_t = 0.0
	var pt := track.point_at_px(track.progress_px(kart))
	kart.pos = pt["pos"]
	kart.heading = atan2(pt["dir"].y, pt["dir"].x)
	kart.vel = Vector2.ZERO
	spawn_effect(QUD.effect("translocation"), kart.position + Vector3(0, 30 * Track.U, 0), 6)
	_net_ev(["respawn", kart.net_id])


# The lap rule per human: lead and every monster pays; trail and you pay.
func _human_lap(kart: Kart) -> void:
	for s in kart.spells:
		s["charges"] = mini(int(s["max_charges"]), int(s["charges"]) + 1)
	if kart == player:
		Campaign.lap_refill()
	if kart.rank <= 1:
		var pct := float(C.get("lap_damage_lead_pct", 0.2))
		var min_dmg := float(C.get("lap_damage_lead_min", 2))
		for other in karts.duplicate():
			if other.human < 0 and not other.is_player and other.alive:
				hit_kart(other, maxf(min_dmg, other.max_hp * pct), "Holy", kart, 0.4, "lap")
		_say_to(kart, "LAP IN 1ST: MONSTERS TAKE %d%%" % int(pct * 100), 1.6)
	else:
		var dmg := minf(float(C.get("lap_damage_cap", 8)), float(C.get("lap_damage_per_rank", 2)) * (kart.rank - 1))
		hit_kart(kart, dmg, "Dark", null, 0.0, "lap")
		_say_to(kart, "LAP IN %s: -%d HP" % [ordinal(kart.rank), int(dmg)], 1.6)


# Every human casts the selected slot with one button and moves the selection with two.
func _party_casts(dt: float) -> void:
	for kart in humans:
		if kart.human < 0 or kart.human >= human_frames.size():
			continue
		var f: DriveFrame = human_frames[kart.human]
		var spells: Array = kart.spells if (kart != player or online) else Campaign.spells
		if spells.is_empty():
			continue
		if f.slot >= 0:
			kart.slot = f.slot
		if f.next_pressed:
			kart.slot = (kart.slot + 1) % spells.size()
		if f.prev_pressed:
			kart.slot = (kart.slot - 1 + spells.size()) % spells.size()
		kart.slot = clampi(kart.slot, 0, spells.size() - 1)
		for s in spells:
			if float(s.get("cd", 0.0)) > 0.0:
				s["cd"] = maxf(0.0, float(s["cd"]) - dt)
		var wants: bool = f.cast_pressed or (auto_player and not kart.remote and fmod(t, 2.5) < 1.0 / 60.0 * 1.5)   # the demo driver casts every couple of seconds
		if wants and kart.respawn_t <= 0.0:
			var s: Dictionary = spells[kart.slot]
			var ready := (bool(s.get("unlimited", false)) and float(s.get("cd", 0.0)) <= 0.0) or (not bool(s.get("unlimited", false)) and int(s["charges"]) > 0)
			ready = ready and int(s.get("hp_cost", 0)) < kart.hp
			if ready and cast_for(kart, s):
				if bool(s.get("unlimited", false)):
					s["cd"] = float(s.get("cooldown", 0.6))
				else:
					s["charges"] = int(s["charges"]) - 1
				var cost := int(s.get("hp_cost", 0))
				if cost > 0:
					kart.hp = maxf(1.0, kart.hp - cost)
					if kart == player:
						Campaign.hp = kart.hp
				tally["casts"] += 1


# A scroll picked up by a human in party mode goes on that kart's own bar.
func _human_learn(kart: Kart, spell: Dictionary) -> String:
	if kart == player and not online:
		return Campaign.learn(spell)
	for s in kart.spells:
		if s["name"] == spell["name"]:
			s["charges"] = mini(int(s["max_charges"]), int(s["charges"]) + 1)
			return "charge"
	if kart.spells.size() >= Campaign.MAX_SLOTS:
		return "full"
	kart.spells.append(SpellDB.make_owned(spell))
	return "learned"


# A message for one human: their panel in party mode, the shared banner otherwise.
func _say_to(kart: Kart, text: String, duration := 1.2) -> void:
	for pn in panels:
		if pn["kart"] == kart:
			pn["message"] = text
			pn["message_t"] = duration
			return
	if host and kart.remote:
		var peer := _peer_of(kart)
		if peer != "":
			Net.send(peer, ["say", text, duration], true)
	elif kart == player:
		say(text, duration)


# ---------------------------------------------------------------- online (host and guest)
# The host runs the race exactly like a party race, with the guests' karts driven by
# RemoteAdapters fed from the network, and tells everyone the kart state twenty times a
# second plus the events that need drawing. A guest builds the same track, spawns karts
# from the host's setup message, eases them toward the reported positions, and sends
# its own DriveFrame every tick.

func _net_ev(msg: Array) -> void:
	if host and net_live:
		Net.broadcast(msg, true)


func _peer_of(kart: Kart) -> String:
	for p in Players.players:
		if int(p["seat"]) == kart.human:
			return String(p["controller"])
	return ""


func _host_receive() -> void:
	for pm in Net.poll():
		var peer: String = pm[0]
		var msg: Array = pm[1]
		if msg.is_empty():
			continue
		match String(msg[0]):
			"hello":
				_host_hello(peer)
			"f":
				var p := Players.by_controller(peer)
				if not p.is_empty() and p["adapter"] is RemoteAdapter and msg.size() > 1:
					p["adapter"].push(DriveFrame.from_array(msg[1], String(p["id"])))


# A guest announced itself: give it a seat (a pending UDP seat, or the lobby seat that
# already carries its address) and the world.
func _host_hello(peer: String) -> void:
	var p := Players.by_controller(peer)
	if p.is_empty():
		for pl in Players.players:
			if String(pl["controller"]).begins_with("pending:"):
				pl["controller"] = peer
				pl["adapter"].peer = peer
				p = pl
				break
	if p.is_empty():
		return
	var seat := int(p["seat"])
	var klist := []
	for kart in karts:
		klist.append([kart.net_id, kart.display_name, kart.unit, kart.is_player, kart.is_wizard, kart.human, kart.max_hp, kart.hp,
			kart.pos.x, kart.pos.y, kart.heading, kart.stat_speed, kart.stat_weight])
	var blist := []
	for box in item_boxes:
		var bp: Vector2 = box.get_meta("pos")
		blist.append([int(box.get_meta("net")), bp.x, bp.y, String(box.get_meta("kind")), String(box.get_meta("spell")) if box.has_meta("spell") else "",
			bool(box.get_meta("respawns")), float(box.get_meta("respawn"))])
	Net.send(peer, ["setup", laps, klist, blist, seat], true)


func _host_broadcast() -> void:
	var klist := []
	for kart in karts:
		var flags := (1 if kart.finished else 0) | (2 if kart.alive else 0) | (4 if kart.drifting else 0)
		klist.append([kart.net_id, kart.pos.x, kart.pos.y, kart.heading, kart.vel.x, kart.vel.y, kart.hp, kart.lap, kart.rank, flags,
			kart.respawn_t, kart.coins, kart.item, kart.shields, kart.drift_stage, kart.boost_t, kart.stun_t, kart.finish_time])
	var bars := {}
	for kart in humans:
		if not kart.remote:
			continue
		var sl := []
		for sp in kart.spells:
			sl.append([sp["name"], int(sp["charges"]), float(sp.get("cd", 0.0)), bool(sp.get("unlimited", false)), int(sp.get("hp_cost", 0)),
				int(sp["max_charges"]), String(sp["icon"])])
		bars[kart.net_id] = [sl, kart.slot]
	Net.broadcast(["s", net_ticks, state, countdown, race_time, klist, bars], false)


func _guest_step(dt: float) -> void:
	t += dt
	for pm in Net.poll():
		_guest_msg(pm[1])
	if seconds_limit > 0.0 and t >= seconds_limit:
		seconds_limit = -1.0
		frames_left = -1
		_finish_screenshot()
		return
	if not guest_ready:
		hello_t -= dt
		if hello_t <= 0.0:
			hello_t = 1.0
			Net.send(Net.host_peer(), ["hello"], true)
		return
	var frames := Players.frames()
	var f: DriveFrame = frames[0] if not frames.is_empty() else DriveFrame.neutral(0, "")
	if auto_player and player.alive and not player.finished and state == RACING:
		track.advance(player)   # the AI steers at the next waypoint, which only the host tracks otherwise
		var c: Dictionary = player.ai_control(dt, track, karts, 0.5)
		f.throttle = c["throttle"]
		f.steer = c["steer"]
		f.drift_held = c["drift"]
		f.item_pressed = c["use"]
		if fmod(t, 2.5) < 1.0 / 60.0 * 1.5 and not player.spells.is_empty():
			f.cast_pressed = true
	Net.send(Net.host_peer(), ["f", f.to_array()], f.has_press())
	message_t = maxf(0.0, message_t - dt)
	for kart in karts:
		kart.net_age += dt
		var target: Vector2 = kart.net_pos + kart.vel * minf(kart.net_age, 0.25)
		kart.pos = kart.pos.lerp(target, minf(1.0, dt * 10.0))
		kart.heading = lerp_angle(kart.heading, kart.net_heading, minf(1.0, dt * 10.0))
		kart.anim_t += dt * clampf(kart.vel.length() / 400.0, 0.2, 2.0)
		kart.hit_flash = maxf(0.0, kart.hit_flash - dt)
		kart.respawn_t = maxf(0.0, kart.respawn_t - dt)
	_guest_world(dt)
	if not panels.is_empty():
		_update_panels(dt)
	_update_camera(dt)


# Visual-only world: things fly and fade, nothing takes damage here.
func _guest_world(dt: float) -> void:
	for p in projectiles.duplicate():
		if not p.tick(dt, track):
			spawn_effect(Items.effect_strip(p.dtype), p.position, 6, 0.05)
			projectiles.erase(p)
			p.queue_free()
	for h in hazards.duplicate():
		if not h.tick_hazard(dt):
			hazards.erase(h)
			h.queue_free()
	for patch in patches.duplicate():
		if not patch.tick(dt):
			patches.erase(patch)
			patch.queue_free()
	for a in auras.duplicate():
		a["left"] -= dt
		if a["left"] <= 0.0:
			auras.erase(a)
	for e in effects.duplicate():
		if not e.tick(dt):
			effects.erase(e)
			e.queue_free()
	for b in bolts.duplicate():
		b.set_meta("life", float(b.get_meta("life")) - dt)
		if float(b.get_meta("life")) <= 0.0:
			bolts.erase(b)
			b.queue_free()


func _guest_msg(msg: Array) -> void:
	if msg.is_empty():
		return
	var kind := String(msg[0])
	if kind == "setup":
		if not guest_ready:
			_guest_setup(msg)
		return
	if not guest_ready:
		return
	match kind:
		"s":
			_guest_state(msg)
		"cast":
			var kart: Kart = net_karts.get(int(msg[1]))
			if kart != null and SpellDB.by_name.has(String(msg[2])):
				Items.cast_spell(self, kart, SpellDB.make_owned(SpellDB.by_name[String(msg[2])]))
		"item":
			var kart: Kart = net_karts.get(int(msg[1]))
			if kart != null:
				kart.item = String(msg[2])
				Items.use(self, kart)
		"hit":
			var kart: Kart = net_karts.get(int(msg[1]))
			if kart != null:
				kart.hit_flash = 0.35
				spawn_effect(Items.effect_strip(String(msg[2])), kart.position + Vector3(0, 30 * Track.U, 0), 6, 0.07, -1.0, 1.4)
				play("hit_player" if kart == player else "hit_enemy", 0.0 if kart == player else -4.0)
		"slain":
			var kart: Kart = net_karts.get(int(msg[1]))
			if kart != null:
				spawn_effect(QUD.effect("dark"), kart.position + Vector3(0, 30 * Track.U, 0), 6, 0.07, -1.0, 2.0)
				play("death_enemy")
				karts.erase(kart)
				net_karts.erase(kart.net_id)
				kart.queue_free()
		"down":
			var kart: Kart = net_karts.get(int(msg[1]))
			if kart != null:
				spawn_effect(QUD.effect("dark"), kart.position + Vector3(0, 30 * Track.U, 0), 6, 0.07, -1.0, 2.0)
				if kart == player:
					play("death_player")
		"respawn":
			var kart: Kart = net_karts.get(int(msg[1]))
			if kart != null:
				kart.net_age = 0.0
				spawn_effect(QUD.effect("translocation"), kart.position + Vector3(0, 30 * Track.U, 0), 6)
		"shiny":
			var sh := _spawn_shiny(Vector2(float(msg[2]), float(msg[3])), String(msg[4]), bool(msg[5]))
			sh.set_meta("net", int(msg[1]))
			if String(msg[4]) == "coin":
				sh.modulate = Color(1.0, 0.85, 0.3)
				sh.pixel_size = Track.U * 0.6
		"box":
			for box in item_boxes.duplicate():
				if int(box.get_meta("net")) != int(msg[1]):
					continue
				if float(msg[2]) < 0.0:
					item_boxes.erase(box)
					box.queue_free()
				else:
					box.set_meta("respawn", float(msg[2]))
					box.visible = false
				if Vector2(box.get_meta("pos")).distance_to(player.pos) < 60.0:
					play("item_pickup")
				break
		"say":
			_say_to(player, String(msg[1]), float(msg[2]))
		"results":
			state = DEAD
			for c in hud.get_children():
				if c != results:
					c.visible = false
			for pn in panels:
				pn["container"].visible = false
			results.text = String(msg[1])
			results.visible = true
			results.position = Vector2(560, 300)
			results.add_theme_font_size_override("font_size", 40)
			Audio.music("victory_theme")


func _guest_setup(msg: Array) -> void:
	laps = int(msg[1])
	var seat := int(msg[4])
	for e in msg[2]:
		var k := Kart.new()
		add_child(k)
		var krng := RandomNumberGenerator.new()
		krng.seed = int(e[0]) + 1
		k.setup(String(e[1]), String(e[2]), Vector2(float(e[8]), float(e[9])), float(e[10]), bool(e[3]), krng, shadow_mesh,
			Vector2i(int(e[11]), int(e[12])), float(e[6]))
		k.hp = float(e[7])
		k.is_wizard = bool(e[4])
		k.human = int(e[5])
		k.net_id = int(e[0])
		k.net_pos = k.pos
		k.net_heading = k.heading
		if k.human >= 0:
			k.label.visible = true
			k.label.modulate = Players.COLORS[k.human % Players.COLORS.size()]
			k.label.text = "P%d" % (k.human + 1)
			k.remote = k.human != seat
		karts.append(k)
		net_karts[k.net_id] = k
		if k.human == seat:
			player = k
	for b in msg[3]:
		var sh := _spawn_shiny(Vector2(float(b[1]), float(b[2])), String(b[3]), bool(b[5]))
		sh.set_meta("net", int(b[0]))
		sh.set_meta("respawn", float(b[6]))
		if String(b[4]) != "":
			_scroll_icon(sh, String(b[4]))
		if String(b[3]) == "coin":
			sh.modulate = Color(1.0, 0.85, 0.3)
			sh.pixel_size = Track.U * 0.6
	if player == placeholder:
		push_warning("online: no kart for seat %d" % seat)
		return
	placeholder.queue_free()
	placeholder = null
	humans = [player]
	local_humans = [player]
	guest_ready = true
	_build_panels()
	_update_camera(0.0, true)
	print("online guest: seat %d, %d karts, %d pickups" % [seat, karts.size(), item_boxes.size()])


func _guest_state(msg: Array) -> void:
	if state != DEAD:
		state = String(msg[2])
		countdown = float(msg[3])
		race_time = float(msg[4])
	for e in msg[5]:
		var kart: Kart = net_karts.get(int(e[0]))
		if kart == null:
			continue
		kart.net_pos = Vector2(float(e[1]), float(e[2]))
		kart.net_heading = float(e[3])
		kart.vel = Vector2(float(e[4]), float(e[5]))
		if kart.net_age < 0.0:
			kart.pos = kart.net_pos
			kart.heading = kart.net_heading
		kart.net_age = 0.0
		kart.hp = float(e[6])
		kart.lap = int(e[7])
		kart.rank = int(e[8])
		var flags := int(e[9])
		kart.finished = flags & 1 != 0
		kart.alive = flags & 2 != 0
		kart.drifting = flags & 4 != 0
		kart.respawn_t = float(e[10])
		kart.coins = int(e[11])
		kart.item = String(e[12])
		kart.shields = int(e[13])
		kart.drift_stage = int(e[14])
		kart.boost_t = float(e[15])
		kart.stun_t = float(e[16])
		kart.finish_time = float(e[17])
	var bars: Dictionary = msg[6]
	if bars.has(player.net_id):
		var bar: Array = bars[player.net_id]
		var spells := []
		for sp in bar[0]:
			spells.append({"name": sp[0], "charges": int(sp[1]), "cd": float(sp[2]), "unlimited": bool(sp[3]), "hp_cost": int(sp[4]),
				"max_charges": int(sp[5]), "icon": sp[6]})
		player.spells = spells
		player.slot = int(bar[1])


# ---------------------------------------------------------------- damage

func hit_kart(target: Kart, damage: float, dtype: String, source: Kart, stun_time: float, cause := "bolt") -> void:
	if guest or not target.alive:   # guests only draw hits the host reports
		return
	if target.shields > 0:
		target.shields -= 1
		spawn_effect(QUD.effect("shield_expire"), target.position + Vector3(0, 30 * Track.U, 0), 6)
		play("shield_break")
		return
	target.damage_taken += damage
	if target.coins > 0 and damage > 0.0:
		_spill_coins(target)
	if target.is_player:
		tally[cause] = float(tally.get(cause, 0.0)) + damage
		play("hit_player")
	else:
		if source != null and source.is_player:
			tally["dealt"] += damage
		play("hit_enemy", -4.0)
	if stun_time > 0.0:
		target.stun(stun_time)
	else:
		target.hit_flash = 0.35
	spawn_effect(Items.effect_strip(dtype), target.position + Vector3(0, 30 * Track.U, 0), 6, 0.07, -1.0, 1.4)
	_net_ev(["hit", target.net_id, dtype])
	if party and target.human >= 0:
		target.hp = maxf(0.0, target.hp - damage)
		if target == player:
			Campaign.hp = target.hp
		if target.hp <= 0.0 and target.respawn_t <= 0.0:
			_human_down(target)
	elif target.is_player:
		target.hp = maxf(0.0, target.hp - damage)
		if Campaign.take_damage(damage):
			_wizard_dead(source)
	else:
		if target.take_damage(damage):
			_slay(target, source)


# A hit spills the kart's speed coins onto the road behind it, where anyone can pick them up.
func _spill_coins(kart: Kart) -> void:
	var n := mini(kart.coins, int(C.get("coin_spill", 3)))
	kart.coins = 0
	var back := -kart.forward()
	for i in n:
		var p: Vector2 = kart.pos + back * (50.0 + 40.0 * i) + Vector2(-back.y, back.x) * kart.rng.randf_range(-40.0, 40.0)
		var s := _spawn_shiny(p, "coin", false)
		s.modulate = Color(1.0, 0.85, 0.3)
		s.pixel_size = Track.U * 0.6
		s.set_meta("respawn", 0.6)   # not grabbed back by the kart that just lost them
	if kart.is_player:
		say("COINS LOST", 0.8)


func heal_kart(kart: Kart, amount: float) -> void:
	if guest:
		return
	if party and kart.human >= 0:
		kart.hp = minf(kart.max_hp, kart.hp + amount)
		if kart == player:
			Campaign.hp = kart.hp
	elif kart.is_player:
		Campaign.heal(amount)
		kart.hp = Campaign.hp
	else:
		kart.hp = minf(kart.max_hp, kart.hp + amount)


func _slay(kart: Kart, source: Kart) -> void:
	kart.alive = false
	slain.append(kart.display_name)
	if source == null or source.is_player:
		Campaign.kills += 1
		Campaign.sp += int(C.get("kill_sp", 1))
		if not kart.is_wizard and Campaign.unlock(kart.display_name):
			say("%s UNLOCKED AS A RACER" % kart.display_name.to_upper(), 2.2)
			play("learn_spell")
		if Campaign.bonus("kill_heal") > 0.0:
			heal_kart(player, Campaign.bonus("kill_heal"))
		say("%s SLAIN  +%d SP" % [kart.display_name.to_upper(), int(C.get("kill_sp", 1))], 1.5)
	spawn_effect(QUD.effect("dark"), kart.position + Vector3(0, 30 * Track.U, 0), 6, 0.07, -1.0, 2.0)
	play("death_enemy")
	_net_ev(["slain", kart.net_id])
	_spawn_shiny(kart.pos, "heart", false)
	karts.erase(kart)
	net_karts.erase(kart.net_id)
	finish_order.erase(kart)
	kart.queue_free()


func _wizard_dead(_source: Kart) -> void:
	state = DEAD
	player.alive = false
	play("death_player")
	Audio.music("lose_theme")
	for c in hud.get_children():
		if c != results:
			c.visible = false
	results.text = "THE WIZARD IS DEAD\n\nRealm %d, %d monsters slain\n\nenter to try again" % [Campaign.level, Campaign.kills]
	results.visible = true


func _level_complete() -> void:
	state = GATES
	Campaign.hp = player.hp
	for c in hud.get_children():
		if c != results:
			c.visible = false
	Audio.music("victory_theme")
	if party:
		var lines := []
		var order := humans.duplicate()
		order.sort_custom(func(a, b): return a.rank < b.rank)
		for h in order:
			lines.append("%s   P%d %s   %s" % [ordinal(h.rank), h.human + 1, h.display_name, _fmt_time(maxf(0.0, h.finish_time))])
		results.text = "RESULTS

%s

enter for the menu" % "
".join(lines)
		results.visible = true
		results.position = Vector2(560, 300)
		results.add_theme_font_size_override("font_size", 40)
		state = DEAD
		_net_ev(["results", results.text])
		if host:
			_host_broadcast()
		return
	var taken := float(tally["ability"]) + float(tally["lap"]) + float(tally["mob"]) + float(tally["bolt"]) + float(tally["wolf"])
	var result := "Realm %d cleared in %s, %s place.   Slain %d (%s).   Dealt %d, took %d (spells %d, laps %d, bumps %d, bolts %d, wolves %d).   Cast %d, +%d SP" % [
		Campaign.level, _fmt_time(maxf(0.0, player.finish_time)), ordinal(player.rank), slain.size(),
		", ".join(slain) if slain.size() > 0 else "none", int(tally["dealt"]), int(taken), int(tally["ability"]),
		int(tally["lap"]), int(tally["mob"]), int(tally["bolt"]), int(tally["wolf"]), int(tally["casts"]),
		Campaign.sp - int(tally["sp_start"])]
	if Campaign.level >= Campaign.MAX_LEVEL:
		results.text = "YOU HAVE CROSSED ALL TWENTY RIFTS\n\n%s\n\nenter for a new run" % result
		results.visible = true
		state = DEAD
		return
	gates = Gates.new()
	add_child(gates)
	gates.setup(Campaign.gate_options(monster_names), result)
	gates.picked.connect(_on_gate_picked)


# Debug: jump to another realm without racing it.
func _debug_realm(delta: int) -> void:
	Campaign.level = clampi(Campaign.level + delta, 1, Campaign.MAX_LEVEL)
	Campaign.next_track = Campaign.pick_track()
	Campaign.seed = Campaign.run_rng.randi()
	get_tree().reload_current_scene()


func _on_gate_picked(gate: Dictionary) -> void:
	Campaign.apply_gate(gate)
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- summons

# Formation slots around an owner: one rides beside it, up to ring_max form a fixed ring
# (it moves with the kart, it does not orbit), more than that fall into a road-following
# grid behind it. Escorts bite enemy karts that come within reach.
func _formation(owner: Kart, n: int) -> Array:
	var S: Dictionary = Shared.tuning.get("summons", {})
	var fwd := owner.forward()
	var right := Vector2(-fwd.y, fwd.x)
	var half := track.width * 0.5
	var slots := []
	if n == 1:
		slots.append(owner.pos + right * float(S.get("beside_lateral", 0.55)) * half)
	elif n <= int(S.get("ring_max", 8)):
		var r := float(S.get("ring_radius", 110.0))
		for i in n:
			var ang := TAU * i / n
			slots.append(owner.pos + fwd * cos(ang) * r + right * sin(ang) * r)
	else:
		# a grid of road cells centred on the owner, nearest cells first, the owner's own cell left free
		owner.update_route(track)
		var lanes: Array = S.get("grid_lanes", [-0.6, 0.6, 0.0])
		var row_px := float(S.get("grid_row_px", 75.0))
		var cells := []
		var rows := int(ceil(float(n) / lanes.size())) + 2
		for r in range(-rows, rows + 1):
			for li in lanes.size():
				var lane := float(lanes[li])
				if r == 0 and lane == 0.0:
					continue
				cells.append({"r": r, "lane": lane, "d": absf(r) * row_px + absf(lane) * half * 0.6 + (0.0 if r > 0 else 5.0)})
		cells.sort_custom(func(x, y): return x["d"] < y["d"])
		for k in n:
			var c: Dictionary = cells[k]
			var pt := track.point_at_px(owner.route_px + float(c["r"]) * row_px)
			var d: Vector2 = pt["dir"]
			var nrm := Vector2(-d.y, d.x)
			slots.append(Vector2(pt["pos"]) + nrm * float(c["lane"]) * half)
	return slots


func _update_escorts(dt: float) -> void:
	if escorts.is_empty():
		return
	var S: Dictionary = Shared.tuning.get("summons", {})
	var follow := float(S.get("follow_rate", 8.0))
	var bite_range := float(S.get("bite_range", 60.0))
	var bite_cd := float(S.get("bite_cooldown", 1.0))
	var by_owner := {}
	for e in escorts.duplicate():
		if not e.tick(dt) or e.owner_kart == null or not is_instance_valid(e.owner_kart) or not e.owner_kart.alive:
			escorts.erase(e)
			e.queue_free()
			continue
		if not by_owner.has(e.owner_kart):
			by_owner[e.owner_kart] = []
		by_owner[e.owner_kart].append(e)
	for owner in by_owner:
		var group: Array = by_owner[owner]
		var slots := _formation(owner, group.size())
		for i in group.size():
			var e = group[i]
			e.pos = e.pos.lerp(slots[i], minf(1.0, follow * dt))
			e.heading = owner.heading
			e.place(track, cam_right)
			if e.bite_cd > 0.0:
				continue
			for kart in karts:
				if not Items.valid_target(owner, kart):
					continue
				if kart.pos.distance_to(e.pos) <= bite_range + kart.RADIUS:
					hit_kart(kart, e.damage, "Physical", owner, 0.5, "wolf")
					spawn_effect(QUD.effect("fang"), kart.position + Vector3(0, 30 * Track.U, 0), 6, 0.06)
					e.bite_cd = bite_cd
					break


# ---------------------------------------------------------------- effects

# A periodic effect around a kart for a while: damage the nearest `targets` karts (0 = all)
# within radius every tick, and/or heal the owner. From the "aura" spell kind.
func add_aura(owner: Kart, e: Dictionary, dtype: String) -> void:
	var dur := float(e.get("duration", 8.0)) + Campaign.bonus("spell_duration")
	auras.append({"owner": owner, "damage": float(e.get("damage", 0.0)) + (Campaign.bonus("spell_damage") if float(e.get("damage", 0.0)) > 0.0 else 0.0),
		"radius": float(e.get("radius", 300.0)) + Campaign.bonus("spell_radius"), "tick": float(e.get("tick", 0.8)),
		"left": dur, "next": 0.3, "targets": int(e.get("targets", 0)), "heal": float(e.get("heal", 0.0)),
		"heal_frac": float(e.get("heal_frac", 0.0)), "dtype": dtype, "stun": float(e.get("stun", 0.0)),
		"shove": float(e.get("shove", 0.0)), "slip": bool(e.get("slip", false))})
	var fx := spawn_effect(Items.effect_strip(dtype), owner.position + Vector3(0, 30 * Track.U, 0), 6, 0.1, dur, 1.6)
	fx.follow = owner


func spawn_effect(tex: Texture2D, at: Vector3, frames: int, frame_time := 0.07, duration := -1.0, size := 1.0) -> Items.Effect:
	var e := Items.Effect.make(tex, at, frames, frame_time, duration, size)
	add_child(e)
	effects.append(e)
	return e


func spawn_bolt(a: Vector3, b: Vector3, color := Color(1.0, 0.93, 0.35)) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(a + Vector3(0, 1.5, 0))
	im.surface_add_vertex(b + Vector3(0, 1.5, 0))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.set_meta("life", 0.18)
	add_child(mi)
	bolts.append(mi)


# ---------------------------------------------------------------- pause / shop

func _open_shop() -> void:
	if shop != null or picker != null or enemies != null:
		return
	if not player_ability.is_empty():
		say("MONSTERS DON'T SHOP", 1.0)
		return
	paused = true
	hud.visible = false
	shop = Shop.new()
	shop.race = self
	add_child(shop)
	shop.closed.connect(_close_shop)
	shop.quit_requested.connect(func(): get_tree().quit())


func _close_shop() -> void:
	if shop == null:
		return
	shop.queue_free()
	shop = null
	paused = false
	hud.visible = true
	overlay_closed_frame = Engine.get_process_frames()


func _open_picker() -> void:
	if picker != null or shop != null or enemies != null:
		return
	paused = true
	picker = SpellPicker.new()
	add_child(picker)
	picker.picked.connect(_on_picked)
	picker.closed.connect(_close_picker)


func _on_picked(spell: Dictionary, slot: int) -> void:
	var res := Campaign.set_slot(slot, spell)
	if res == "charge":
		say("%s RECHARGED" % String(spell["name"]).to_upper(), 1.2)
	else:
		say("%s IN SLOT %d" % [String(spell["name"]).to_upper(), (mini(slot, Campaign.spells.size() - 1) + 1) % 10], 1.4)
	play("learn_spell")
	_close_picker()


func _close_picker() -> void:
	if picker == null:
		return
	picker.queue_free()
	picker = null
	paused = false
	overlay_closed_frame = Engine.get_process_frames()


func _toggle_slow() -> void:
	var steps: Array = R.get("slow_steps", [1.0, 0.3, 0.1])
	var i := -1
	for k in steps.size():
		if is_equal_approx(float(steps[k]), slow_scale):
			i = k
	slow_scale = float(steps[(i + 1) % steps.size()])
	if not quick_open:
		Engine.time_scale = slow_scale
	say("SLOW-MOTION x%s" % str(slow_scale) if slow_scale < 1.0 else "FULL SPEED", 1.0)


# ---------------------------------------------------------------- camera + HUD

func _update_camera(dt: float, snap := false) -> void:
	var back := float(Shared.t(["godot", "cam_back"], 260.0))
	var height := float(Shared.t(["godot", "cam_height"], 110.0))
	var ahead := float(Shared.t(["godot", "cam_ahead"], 200.0))
	if snap:
		cam_yaw = player.heading
	else:
		cam_yaw += Kart.wrap_angle(player.heading - cam_yaw) * minf(1.0, 5.0 * dt)
	var f := Vector2(cos(cam_yaw), sin(cam_yaw))
	cam_right = Vector2(-f.y, f.x)
	var eye_px := player.pos - f * back
	var eye := Vector3(eye_px.x * Track.U, (maxf(track.height_px(eye_px), track.height_px(player.pos)) + height) * Track.U, eye_px.y * Track.U)
	var look := track.to3(player.pos + f * ahead, 40.0)
	if top_view:
		eye = track.to3(player.pos) + Vector3(0.0, 700.0 * Track.U, 0.5)
		look = track.to3(player.pos)
	cam.position = eye
	cam.look_at(look, Vector3.UP)


# ---------------------------------------------------------------- split screen

# One SubViewport per human, sharing the world, each with its own chase camera and a
# small HUD. The main camera and HUD stay for the shared banner only.
func _build_panels() -> void:
	var rects := ViewLayout.panels(local_humans.size(), Rect2(0, 0, 1920, 1080))
	var holder := Control.new()
	holder.name = "Panels"
	holder.size = Vector2(1920, 1080)
	add_child(holder)
	for i in local_humans.size():
		var kart: Kart = local_humans[i]
		var svc := SubViewportContainer.new()
		svc.position = rects[i].position
		svc.size = rects[i].size
		svc.stretch = true
		holder.add_child(svc)
		var sv := SubViewport.new()
		sv.size = Vector2i(rects[i].size)
		sv.own_world_3d = false
		sv.handle_input_locally = false
		svc.add_child(sv)
		var c := Camera3D.new()
		c.fov = cam.fov
		c.near = cam.near
		c.far = cam.far
		sv.add_child(c)
		c.current = true
		var lay := CanvasLayer.new()
		sv.add_child(lay)
		var col: Color = Players.COLORS[maxi(0, kart.human) % Players.COLORS.size()]
		var name_l := _panel_label(lay, 22, col, Vector2(14, 8))
		name_l.text = "P%d  %s" % [kart.human + 1, kart.display_name]
		var pos_l := _panel_label(lay, 30, Color.WHITE, Vector2(14, 34))
		var hp_bg := ColorRect.new()
		hp_bg.color = Color(0, 0, 0, 0.7)
		hp_bg.position = Vector2(14, 74)
		hp_bg.size = Vector2(200, 16)
		lay.add_child(hp_bg)
		var hp_fill_p := ColorRect.new()
		hp_fill_p.color = Color(0.9, 0.11, 0.14)
		hp_fill_p.position = hp_bg.position
		hp_fill_p.size = hp_bg.size
		lay.add_child(hp_fill_p)
		var info_l := _panel_label(lay, 18, Color(0.85, 0.85, 0.85), Vector2(14, 94))
		var msg_l := _panel_label(lay, 40, Color(1.0, 0.93, 0.35), Vector2(0, rects[i].size.y * 0.35))
		msg_l.size = Vector2(rects[i].size.x, 60)
		msg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var icon := TextureRect.new()
		icon.position = Vector2(14, rects[i].size.y - 80)
		icon.size = Vector2(56, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		lay.add_child(icon)
		var spell_l := _panel_label(lay, 18, Color(1.0, 0.93, 0.35), Vector2(78, rects[i].size.y - 76))
		var item_icon := TextureRect.new()
		item_icon.position = Vector2(rects[i].size.x - 70, rects[i].size.y - 80)
		item_icon.size = Vector2(56, 56)
		item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		item_icon.stretch_mode = TextureRect.STRETCH_SCALE
		item_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		lay.add_child(item_icon)
		panels.append({"container": svc, "viewport": sv, "cam": c, "yaw": kart.heading, "cam_right": Vector2.RIGHT, "kart": kart,
			"pos": pos_l, "hp_fill": hp_fill_p, "info": info_l, "msg": msg_l, "icon": icon, "spell": spell_l, "item": item_icon,
			"message": "", "message_t": 0.0})
	# the shared HUD keeps only the banner; the main camera is parked
	for c in hud.get_children():
		if c != lbl_center and c != results:
			c.visible = false
	hud.layer = 30
	cam.current = false


func _panel_label(lay: CanvasLayer, size: int, color: Color, pos: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.position = pos
	lay.add_child(l)
	return l


func _update_panels(dt: float) -> void:
	var back := float(Shared.t(["godot", "cam_back"], 260.0))
	var height := float(Shared.t(["godot", "cam_height"], 110.0))
	var ahead := float(Shared.t(["godot", "cam_ahead"], 200.0))
	for pn in panels:
		var kart: Kart = pn["kart"]
		var yaw: float = pn["yaw"]
		yaw += Kart.wrap_angle(kart.heading - yaw) * minf(1.0, 5.0 * dt)
		pn["yaw"] = yaw
		var f := Vector2(cos(yaw), sin(yaw))
		pn["cam_right"] = Vector2(-f.y, f.x)
		var eye_px := kart.pos - f * back
		var eye := Vector3(eye_px.x * Track.U, (maxf(track.height_px(eye_px), track.height_px(kart.pos)) + height) * Track.U, eye_px.y * Track.U)
		var c: Camera3D = pn["cam"]
		c.position = eye
		c.look_at(track.to3(kart.pos + f * ahead, 40.0), Vector3.UP)
		pn["message_t"] = maxf(0.0, float(pn["message_t"]) - dt)


func _refresh_panel_huds() -> void:
	for pn in panels:
		var kart: Kart = pn["kart"]
		pn["pos"].text = "%s   LAP %d/%d" % [ordinal(kart.rank), mini(kart.lap, laps), laps]
		pn["hp_fill"].size = Vector2(200.0 * clampf(kart.hp / maxf(1.0, kart.max_hp), 0.0, 1.0), 16)
		pn["info"].text = "HP %d   coins %d%s" % [int(kart.hp), kart.coins, ("   shield x%d" % kart.shields) if kart.shields > 0 else ""]
		pn["msg"].text = String(pn["message"]) if float(pn["message_t"]) > 0.0 else ("WRECKED %.0f" % kart.respawn_t if kart.respawn_t > 0.0 else "")
		var spells: Array = kart.spells if (kart != player or online) else Campaign.spells
		if spells.is_empty():
			pn["icon"].texture = null
			pn["spell"].text = "no spells: run over a scroll"
		else:
			var s: Dictionary = spells[clampi(kart.slot, 0, spells.size() - 1)]
			pn["icon"].texture = QUD.icon(String(s["icon"]))
			var charge := ("oo" if float(s.get("cd", 0.0)) <= 0.0 else "%.1f" % float(s["cd"])) if bool(s.get("unlimited", false)) else str(int(s["charges"]))
			pn["spell"].text = "%s  %s   (%d/%d)" % [s["name"], charge, kart.slot + 1, spells.size()]
		pn["item"].texture = QUD.icon(kart.item) if kart.item != "" else null


func _refresh_artifacts() -> void:
	for c in artifact_row.get_children():
		c.queue_free()
	for a in Campaign.artifacts:
		var tr := TextureRect.new()
		tr.texture = QUD.texture("equipment/%s.png" % a["icon"])
		tr.custom_minimum_size = Vector2(44, 44)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.tooltip_text = "%s: %s" % [a["name"], a["label"]]
		artifact_row.add_child(tr)


func _set_quick(open: bool) -> void:
	if open == quick_open:
		return
	quick_open = open
	quick.visible = open
	Engine.time_scale = float(C.get("quick_shop_timescale", 0.15)) if open else slow_scale
	if open:
		if Campaign.offers.is_empty():
			Campaign.roll_offers(int(C.get("quick_offers", 4)))
		_refresh_quick()


func _refresh_quick() -> void:
	for i in quick_icons.size():
		if i < Campaign.offers.size():
			var s: Dictionary = Campaign.offers[i]
			quick_icons[i].texture = SpellDB.icon(s)
			var can := Campaign.can_buy(s)
			quick_labels[i].text = "%d  %s\n%d SP  %s" % [i + 1, s["name"], Campaign.cost(s), SpellDB.kind_verb(String(SpellDB.effect_for(s)["kind"]))]
			quick_labels[i].add_theme_color_override("font_color", Color.WHITE if can else Color(0.5, 0.5, 0.5))
		else:
			quick_icons[i].texture = null
			quick_labels[i].text = "sold out" if Campaign.sp > 0 else "no spell points"


func _quick_buys() -> void:
	for i in quick_icons.size():
		if i < Campaign.offers.size() and Input.is_action_just_pressed("slot_%d" % (i + 1)):
			var s: Dictionary = Campaign.offers[i]
			if Campaign.buy(s):
				say("BOUGHT %s" % String(s["name"]).to_upper(), 1.0)
				Campaign.offers.remove_at(i)
				_refresh_quick()


func _process(_delta: float) -> void:
	var want_quick := (Input.is_action_pressed("quick_shop") or screen_arg == "quick") and state == RACING and shop == null and picker == null and not auto_player
	_set_quick(want_quick)
	if quick_open:
		_quick_buys()
	var overlay_free := picker == null and shop == null and enemies == null and Engine.get_process_frames() != overlay_closed_frame
	if rig and overlay_free and state != DEAD:
		if Input.is_action_just_pressed("spell_picker"):
			_open_picker()
		if Input.is_action_just_pressed("enemy_picker"):
			_open_enemies()
	if debug and overlay_free and state != DEAD:
		if Input.is_action_just_pressed("debug_attacks"):
			attacks_on = not attacks_on
			say("MONSTER ATTACKS %s" % ("ON" if attacks_on else "OFF"), 1.0)
		if Input.is_action_just_pressed("debug_skip"):
			_debug_realm(1)
		if Input.is_action_just_pressed("debug_back"):
			_debug_realm(-1)
		if Input.is_action_just_pressed("slow_mo"):
			_toggle_slow()
	if overlay_free and state != GATES and state != DEAD and Input.is_action_just_pressed("free_drive"):
		_set_free(not free_mode)
	if overlay_free and state != GATES and Input.is_action_just_pressed("pause"):
		if state == DEAD:
			get_tree().quit()
		elif online:
			get_tree().change_scene_to_file("res://Menu.tscn")   # no shop online; leaving the race is the pause
			return
		else:
			_open_shop()
	if overlay_free and state == DEAD and Input.is_action_just_pressed("confirm"):
		if party:
			get_tree().change_scene_to_file("res://Menu.tscn")
			return
		Campaign.new_run()
		get_tree().reload_current_scene()
		return

	for kart in karts:
		kart.update_visual(track, cam_right, t)
	if minimap != null:
		minimap.queue_redraw()
	if not panels.is_empty():
		_refresh_panel_huds()

	lbl_realm.text = ("TEST RIG" if rig else "REALM %d / %d%s" % [Campaign.level, Campaign.MAX_LEVEL, ("  " + String(level.get("tileset", "")).capitalize()) if not level.is_empty() else ""]) + ("   FREE DRIVE (F)" if free_mode else "") + ("   SLOW x%s (Z)" % str(slow_scale) if slow_scale < 1.0 else "")
	lbl_street.text = track.street_name_at(player.pos) if track.city != null else ""
	lbl_lap.text = "LAP %d/%d" % [mini(player.lap, laps), laps]
	lbl_pos.text = "POS %d/%d" % [player.rank, karts.size()]
	lbl_time.text = _fmt_time(race_time)
	hp_fill.size = Vector2(300.0 * clampf(Campaign.hp / maxf(1.0, Campaign.max_hp), 0.0, 1.0), 24)
	lbl_hp.text = "HP %d / %d%s" % [int(Campaign.hp), int(Campaign.max_hp), "   shield x%d" % player.shields if player.shields > 0 else ""]
	lbl_sp.text = "SP %d     kills %d     coins %d" % [Campaign.sp, Campaign.kills, player.coins] + ("     ATTACKS OFF (K)" if not attacks_on else "")
	if player.item != "":
		item_icon.texture = QUD.icon(player.item)
		lbl_item.text = Items.KINDS.get(player.item, player.item)
	else:
		item_icon.texture = null
		lbl_item.text = "no pickup"
	for i in Campaign.MAX_SLOTS:
		if not player_ability.is_empty():
			if i == 0:
				slot_icons[i].texture = QUD.icon(String(player_ability.get("icon", "melee_attack")))
				slot_icons[i].modulate = Color.WHITE if player_ability_cd <= 0.0 else Color(0.35, 0.35, 0.35)
				slot_charges[i].text = String(player_ability["name"]) if player_ability_cd <= 0.0 else "%.1f" % player_ability_cd
			else:
				slot_icons[i].texture = null
				slot_charges[i].text = ""
			continue
		if i < Campaign.spells.size():
			var s: Dictionary = Campaign.spells[i]
			slot_icons[i].texture = QUD.icon(String(s["icon"]))
			var ready := Campaign.slot_ready(i)
			slot_icons[i].modulate = Color.WHITE if ready else Color(0.35, 0.35, 0.35)
			var txt := ""
			if bool(s.get("unlimited", false)):
				txt = "oo" if float(s.get("cd", 0.0)) <= 0.0 else "%.1f" % float(s["cd"])
			else:
				txt = str(int(s["charges"]))
			if int(s.get("hp_cost", 0)) > 0:
				txt += " -%d" % int(s["hp_cost"])
			slot_charges[i].text = txt
			slot_charges[i].add_theme_color_override("font_color", Color(1.0, 0.45, 0.45) if int(s.get("hp_cost", 0)) > 0 else Color(1.0, 0.93, 0.35))
		else:
			slot_icons[i].texture = null
			slot_charges[i].text = ""
	var frac := clampf(player.speed() / (player.max_speed * 1.5), 0.0, 1.0)
	speed_fill.size = Vector2(300.0 * frac, 22)
	speed_fill.color = Color(1.0, 0.93, 0.35) if player.boost_t > 0.0 else Color(0.9, 0.11, 0.14)
	lbl_stats.text = "SPD %d  WGT %d" % [player.stat_speed, player.stat_weight]
	if player.drifting:
		var names := ["DRIFT", "DRIFT +", "DRIFT ++", "DRIFT +++"]
		var colors := [Color(0.8, 0.8, 0.85), Color(1.0, 0.93, 0.35), Color(0.9, 0.24, 0.14), Color(0.47, 0.78, 1.0)]
		lbl_drift.text = names[mini(3, player.drift_stage)]
		lbl_drift.add_theme_color_override("font_color", colors[mini(3, player.drift_stage)])
	elif player.in_slip:
		var sl := float(Shared.t(["slipstream", "collect_time"], 1.5))
		lbl_drift.text = "DRAFT %d%%" % int(100.0 * player.slip_charge / sl)
		lbl_drift.add_theme_color_override("font_color", Color(0.47, 0.78, 1.0))
	else:
		lbl_drift.text = ""
	if artifact_row.get_child_count() != Campaign.artifacts.size():
		_refresh_artifacts()
	if state == COUNTDOWN:
		var num := int(ceil(countdown))
		lbl_center.text = str(num) if num > 0 else "GO!"
		lbl_help.visible = true
	else:
		lbl_center.text = message if message_t > 0.0 else ""
		lbl_help.visible = rig

	frame_count += 1
	for k in debug_keys:
		if int(k["frame"]) == frame_count or int(k["frame"]) + 2 == frame_count:
			var ev := InputEventKey.new()
			ev.keycode = OS.find_keycode_from_string(String(k["key"]))
			ev.physical_keycode = ev.keycode
			ev.pressed = int(k["frame"]) == frame_count
			Input.parse_input_event(ev)
			print("debug key %s %s at frame %d" % [k["key"], "down" if ev.pressed else "up", frame_count])
	if screen_arg != "" and frame_count == 20:
		if screen_arg == "shop":
			_open_shop()
			if shop != null:
				shop.call_deferred("preselect_owned")
		elif screen_arg == "gates":
			_level_complete()
		elif screen_arg == "quick":
			state = RACING
			auto_player = false
		elif screen_arg == "free":
			_set_free(true)
		elif screen_arg == "top":
			top_view = true
		elif screen_arg == "picker":
			_open_picker()
		elif screen_arg == "enemies":
			_open_enemies()
	if frames_left >= 0 and frame_count >= frames_left:
		frames_left = -1
		_finish_screenshot()


func _fmt_time(tm: float) -> String:
	var m := int(tm / 60.0)
	var s := tm - m * 60.0
	return "%d:%05.2f" % [m, s]


func _finish_screenshot() -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if screenshot_path != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png(screenshot_path)
		print("saved ", screenshot_path)
	print("ui: picker=%s enemies=%s shop=%s paused=%s npcs=%d" % [picker != null, enemies != null, shop != null, paused, karts.size() - 1])
	if online:
		print("online: role=%s seat=%d ready=%s karts=%d lap=%d progress=%.2f rank=%d spells=%d pickups=%d" % ["host" if host else "guest", player.human, str(guest_ready or host), karts.size(), player.lap, player.progress if host else track.progress(player), player.rank, player.spells.size(), item_boxes.size()])
	print("race: state=%s realm=%d lap=%d rank=%d karts=%d hp=%d sp=%d spells=%d slain=%d fps=%d tally=%s" % [
		state, Campaign.level, player.lap, player.rank, karts.size(), int(Campaign.hp), Campaign.sp,
		Campaign.spells.size(), slain.size(), Engine.get_frames_per_second(), JSON.stringify(tally)])
	if rig:
		var rep := _rig_report()
		print("rig: " + JSON.stringify(rep))
		if report_path != "":
			var f := FileAccess.open(report_path, FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify(rep, "  "))
				f.close()
	get_tree().quit()
