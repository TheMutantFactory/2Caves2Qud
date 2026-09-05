# Title screen and the flow into a race: race type, racer, realm. Command-line flags
# that describe a race (--auto, --newrun, --map, --realm, --rig, --screen, --track,
# --spells, --sp) or --mode=race|survivors|gauntlet|wardrobe|dump skip the menu.
extends Control

const RACE_SCENE := "res://Main.tscn"
const SURVIVORS_SCENE := "res://Survivors.tscn"
const GAUNTLET_SCENE := "res://Gauntlet.tscn"
const RIFTTYPE_SCENE := "res://RiftType.tscn"

const RACE_TYPES := [
	{"key": "gp", "title": "GRAND PRIX", "blurb": "you against seven other wizards, twenty realms of the game, rift gates between them"},
	{"key": "campaign", "title": "MONSTER CAMPAIGN", "blurb": "the realms' own monsters race you; every one you slay becomes a racer you can pick"},
	{"key": "single", "title": "SINGLE RACE", "blurb": "pick any realm and race it once"},
	{"key": "rig", "title": "TEST RIG", "blurb": "archetype NPCs holding set gaps, every spell on tap"},
	{"key": "party", "title": "LOCAL MULTIPLAYER", "blurb": "up to four racers on one screen: keyboards and gamepads, press a button to join"},
	{"key": "online", "title": "ONLINE (STEAM)", "blurb": "host a lobby or join one from the list; friends can be invited through the Steam overlay"},
]

var wardrobe: Wardrobe = null
var page := "title"
var root: Control = null
var race_type := "gp"


var shot_frames := -1
var shot_path := ""
var shot_count := 0


func _process(_dt: float) -> void:
	if shot_frames < 0:
		return
	shot_count += 1
	if shot_count >= shot_frames:
		shot_frames = -1
		_finish_screenshot()


func _finish_screenshot() -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if shot_path != "":
		get_viewport().get_texture().get_image().save_png(shot_path)
		print("saved ", shot_path)
	print("menu: page=%s players=%d" % [page, Players.count()])
	get_tree().quit()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := ""
	for a in args:
		if a.begins_with("--mode="):
			mode = a.substr(7)
		elif a.begins_with("--frames="):   # --frames=N --screenshot=path: capture the menu page and quit
			shot_frames = int(a.substr(9))
		elif a.begins_with("--screenshot="):
			shot_path = a.substr(13)
		elif a in ["--auto", "--newrun"] or a.begins_with("--rig=") or a.begins_with("--map=") or a.begins_with("--realm=") or a.begins_with("--screen=") or a.begins_with("--track=") or a.begins_with("--spells=") or a.begins_with("--sp="):
			if mode == "":
				mode = "race"
	if mode == "dump":
		_dump_mapping(args)
		return
	for a in args:
		if a.begins_with("--party=") and mode == "lobby":   # seat fake players so the lobby can be rendered
			Players.clear()
			var skins := Wardrobe.skins()
			for i in clampi(int(a.substr(8)), 1, Players.MAX):
				var pl := Players.join_with("debug:%d" % i, DriveAdapter.new("p%d" % (i + 1), "debug:%d" % i))
				pl["racer"] = {"kind": "wizard", "unit": skins[(i * 7) % skins.size()], "name": Wardrobe.racer_name(skins[(i * 7) % skins.size()])}
				pl["ready"] = i % 2 == 0
	if mode == "survivors":
		get_tree().change_scene_to_file.call_deferred(SURVIVORS_SCENE)
		return
	if mode == "rifttype":
		get_tree().change_scene_to_file.call_deferred(RIFTTYPE_SCENE)
		return
	if mode == "gauntlet":
		Campaign.new_run()
		get_tree().change_scene_to_file.call_deferred(GAUNTLET_SCENE)
		return
	if mode == "race":
		get_tree().change_scene_to_file.call_deferred(RACE_SCENE)
		return
	Campaign.rig = ""
	_show("title")
	if mode == "wardrobe":
		_open_wardrobe()
	elif mode in ["racers", "levels", "types", "lobby", "online", "rifttype_select"]:
		_show(mode.trim_suffix("_select"))
	if Campaign.rift_page:
		Campaign.rift_page = false
		_show("rifttype")
	for a in args:
		if a.begins_with("--nettest="):   # --nettest=host|browse --seconds=N: Steam lobby self test, prints nettest: and quits
			var seconds := 12.0
			for b in args:
				if b.begins_with("--seconds="):
					seconds = float(b.substr(10))
			Net.run_test(a.substr(10), seconds)
	Net.lobbies_changed.connect(_online_changed)
	Net.lobby_changed.connect(_online_changed)
	Net.race_started.connect(_start_online)
	if Net.lobby_id != 0 and mode == "":   # back from an online race: straight to the lobby
		Net.back_to_lobby()
		_show("online")


# ---------------------------------------------------------------- widgets

func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, size: int, cb: Callable, width := 520.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", QUD.font())
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(width, 64)
	b.pressed.connect(cb)
	return b


func _show(p: String) -> void:
	page = p
	if root != null:
		root.queue_free()
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.09)
	bg.size = Vector2(1920, 1080)
	root.add_child(bg)
	match p:
		"title":
			_build_title()
		"types":
			_build_types()
		"racers":
			_build_racers()
		"levels":
			_build_levels()
		"lobby":
			_build_lobby()
		"online":
			_build_online()
		"rifttype":
			_build_rifttype()
	Players.joins_enabled = p == "lobby"


# ---------------------------------------------------------------- pages

func _build_title() -> void:
	var vb := VBoxContainer.new()
	vb.position = Vector2(700, 200)
	vb.add_theme_constant_override("separation", 16)
	root.add_child(vb)
	vb.add_child(_label("DRIFT WIZARD 3", 84, Color(1.0, 0.93, 0.35)))
	vb.add_child(_label("a Rift Wizard 3 fan project. Needs the game installed.", 20, Color(0.7, 0.7, 0.7)))
	vb.add_child(Control.new())
	var b1 := _button("ENTER   RACE", 32, func(): _show("types"))
	vb.add_child(b1)
	vb.add_child(_label("%s in %s   (%d monsters unlocked as racers)" % [String(Campaign.racer.get("name", "Wizard")), Wardrobe.skin_label(Campaign.skin), Campaign.unlocked.size()], 18, Color(0.7, 0.7, 0.7)))
	vb.add_child(_button("R   RACER SELECT", 28, func(): _show("racers")))
	vb.add_child(_button("W   WARDROBE   (%s)" % Wardrobe.skin_label(Campaign.skin), 28, _open_wardrobe))
	vb.add_child(Control.new())
	vb.add_child(_label("other modes", 18, Color(0.55, 0.55, 0.55)))
	vb.add_child(_button("2   RIFT WIZARD SURVIVORS", 24, func(): get_tree().change_scene_to_file(SURVIVORS_SCENE)))
	vb.add_child(_button("3   RIFT WIZARD GAUNTLET", 24, func(): Campaign.new_run(); get_tree().change_scene_to_file(GAUNTLET_SCENE)))
	vb.add_child(_button("4   RIFT-TYPE   (side-scrolling shooter)", 24, func(): _show("rifttype")))
	vb.add_child(Control.new())
	vb.add_child(_button("Q   QUIT", 24, func(): get_tree().quit()))
	b1.call_deferred("grab_focus")
	Audio.music("title_theme")
	# the wizard on the title
	var tr := TextureRect.new()
	tr.texture = Wardrobe.preview(Campaign.racer.get("unit", Campaign.skin))
	tr.position = Vector2(380, 300)
	tr.size = Vector2(240, 240)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(tr)


func _build_types() -> void:
	var vb := VBoxContainer.new()
	vb.position = Vector2(560, 180)
	vb.add_theme_constant_override("separation", 14)
	root.add_child(vb)
	vb.add_child(_label("RACE TYPE", 60, Color(1.0, 0.93, 0.35)))
	vb.add_child(_label("Esc back", 18, Color(0.6, 0.6, 0.6)))
	vb.add_child(Control.new())
	var first: Button = null
	var i := 1
	for rt in RACE_TYPES:
		var key: String = rt["key"]
		var b := _button("%d   %s" % [i, rt["title"]], 30, func(): _pick_type(key), 800.0)
		vb.add_child(b)
		vb.add_child(_label(rt["blurb"], 18, Color(0.7, 0.7, 0.7)))
		if first == null:
			first = b
		i += 1
	if first != null:
		first.call_deferred("grab_focus")


func _pick_type(key: String) -> void:
	race_type = key
	Campaign.race_type = key
	if key == "rig":
		_start_rig()
	elif key == "party":
		_show("lobby")
	elif key == "online":
		_show("online")
	elif key == "single":
		_show("levels")
	else:
		_start_race(1)


func _build_racers() -> void:
	root.add_child(_at(_label("RACER SELECT", 60, Color(1.0, 0.93, 0.35)), Vector2(60, 20)))
	root.add_child(_at(_label("wizards wear an outfit and cast from the action bar; a monster races with its own attack only.   Esc back", 18, Color(0.7, 0.7, 0.7)), Vector2(60, 88)))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60, 130)
	scroll.size = Vector2(1800, 920)
	root.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	scroll.add_child(vb)
	vb.add_child(_label("WIZARDS", 28, Color(0.55, 0.85, 1.0)))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	var first: Button = null
	for unit in Wardrobe.skins():
		var b := _racer_card(Wardrobe.skin_label(unit), unit, true, func(): _pick_racer("wizard", unit, Wardrobe.racer_name(unit)))
		if unit == Campaign.racer.get("unit", ""):
			b.modulate = Color(0.7, 1.0, 0.7)
			first = b
		grid.add_child(b)
	vb.add_child(_label("MONSTERS   (%d unlocked: slay one in a race to unlock it)" % Campaign.unlocked.size(), 28, Color(0.55, 0.85, 1.0)))
	var mgrid := GridContainer.new()
	mgrid.columns = 8
	mgrid.add_theme_constant_override("h_separation", 8)
	mgrid.add_theme_constant_override("v_separation", 8)
	vb.add_child(mgrid)
	var shown := 0
	for m in QUD.monsters:
		if m.has("error") or not bool(m.get("asset_exists", false)):
			continue
		var asset: Array = m.get("asset", [])
		if asset.size() < 2 or asset[0] != "char" or not QUD.has_unit(asset[1]) or int(m.get("radius", 0)) > 1:
			continue
		var unlocked := Campaign.unlocked.has(m["name"])
		if not unlocked and shown >= 24:
			continue   # the locked ones are a tease, not a catalogue
		var name: String = m["name"]
		var unit: String = asset[1]
		var b := _racer_card(name, unit, unlocked, func(): _pick_racer("monster", unit, name))
		if unit == Campaign.racer.get("unit", "") and Campaign.racer.get("kind", "") == "monster":
			b.modulate = Color(0.7, 1.0, 0.7)
		mgrid.add_child(b)
		shown += 1
	if first != null:
		first.call_deferred("grab_focus")


func _racer_card(text: String, unit: String, enabled: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(216, 150)
	b.disabled = not enabled
	b.pressed.connect(cb)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = Wardrobe.preview(unit)
	tr.custom_minimum_size = Vector2(96, 96)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not enabled:
		tr.modulate = Color(0.25, 0.25, 0.3)
	vb.add_child(tr)
	var l := _label(text if enabled else "locked", 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(l)
	b.add_child(vb)
	return b


func _pick_racer(kind: String, unit: String, name: String) -> void:
	Campaign.set_racer(kind, unit, name)
	Audio.play("learn_spell", -6.0)
	_show("title")


func _build_levels() -> void:
	root.add_child(_at(_label("REALM", 60, Color(1.0, 0.93, 0.35)), Vector2(60, 20)))
	root.add_child(_at(_label("pick the realm to race, and which of its three layouts.   Esc back", 18, Color(0.7, 0.7, 0.7)), Vector2(60, 88)))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60, 130)
	scroll.size = Vector2(1800, 920)
	root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var first: Button = null
	for realm in range(1, Campaign.MAX_LEVEL + 1):
		var opts := Shared.realm_options(realm)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		var l := _label("Realm %2d" % realm, 24)
		l.custom_minimum_size = Vector2(130, 60)
		hb.add_child(l)
		if opts.is_empty():
			var b := _button("seeded loop", 20, func(): _start_race(realm), 280.0)
			hb.add_child(b)
			if first == null:
				first = b
		for e in opts:
			var f := String(e["file"])
			var b := _button("%s / %s" % [String(e["tileset"]).capitalize(), e["chasm"]], 18, func(): _start_race(realm, f), 150.0)
			hb.add_child(b)
			if first == null:
				first = b
		grid.add_child(hb)
	if first != null:
		first.call_deferred("grab_focus")


# ---------------------------------------------------------------- local multiplayer lobby

var seat_cards: Array = []
var lobby_hint: Label = null


func _build_lobby() -> void:
	root.add_child(_at(_label("LOCAL MULTIPLAYER", 60, Color(1.0, 0.93, 0.35)), Vector2(60, 20)))
	root.add_child(_at(_label("press any button on a keyboard side or a gamepad to take a seat.   left/right picks an outfit, drift or cast readies, item unreadies.   Esc back", 18, Color(0.7, 0.7, 0.7)), Vector2(60, 88)))
	lobby_hint = _label("", 26, Color(0.55, 0.85, 1.0))
	root.add_child(_at(lobby_hint, Vector2(60, 980)))
	seat_cards.clear()
	for seat in Players.MAX:
		var card := PanelContainer.new()
		card.position = Vector2(60 + seat * 450, 150)
		card.size = Vector2(430, 800)
		root.add_child(card)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 12)
		card.add_child(vb)
		var title := _label("SEAT %d" % (seat + 1), 32, Players.COLORS[seat])
		vb.add_child(title)
		var who := _label("press a button to join", 20, Color(0.6, 0.6, 0.6))
		who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		who.custom_minimum_size = Vector2(400, 0)
		vb.add_child(who)
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(400, 300)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		vb.add_child(tr)
		var outfit := _label("", 24)
		outfit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(outfit)
		var state := _label("", 26, Color(0.45, 0.9, 0.5))
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(state)
		var keys := _label("", 16, Color(0.6, 0.6, 0.6))
		keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		keys.custom_minimum_size = Vector2(400, 0)
		vb.add_child(keys)
		seat_cards.append({"card": card, "who": who, "tr": tr, "outfit": outfit, "state": state, "keys": keys, "skin_i": 0})
	_refresh_lobby()


func _refresh_lobby() -> void:
	var skins := Wardrobe.skins()
	var all_ready := Players.count() > 0
	for seat in Players.MAX:
		var c: Dictionary = seat_cards[seat]
		var p: Dictionary = {}
		for pl in Players.players:
			if int(pl["seat"]) == seat:
				p = pl
		if p.is_empty():
			c["who"].text = "press a button to join"
			c["tr"].texture = null
			c["outfit"].text = ""
			c["state"].text = ""
			c["keys"].text = ""
			continue
		var adapter: DriveAdapter = p["adapter"]
		c["who"].text = adapter.label() if String(p["controller"]) != "" else "controller unplugged, press a button on another"
		var unit := String(p["racer"]["unit"])
		c["tr"].texture = Wardrobe.preview(unit)
		c["outfit"].text = "<  %s  >" % Wardrobe.skin_label(unit)
		c["state"].text = "READY" if bool(p["ready"]) else "drift to ready"
		if adapter is KeyboardAdapter:
			c["keys"].text = "WASD drive, Shift drift, F cast, E item, Q/R change slot, Tab pause" if adapter.slot == KeyboardAdapter.Slot.LEFT else "arrows drive, numpad 0 drift, 1 cast, 2 item, . / 3 change slot, Enter pause"
		else:
			c["keys"].text = "stick or d-pad steers, RT drives, LT brakes, A drift, X cast, B item, bumpers change slot, Start pause"
		if not bool(p["ready"]):
			all_ready = false
	lobby_hint.text = ("everyone ready: seat 1 press drift or cast to start" if all_ready else ("%d seated" % Players.count())) if Players.count() > 0 else ""


func _physics_process(_dt: float) -> void:
	if page == "online" and Net.available and Engine.get_physics_frames() % 300 == 0:
		Net.refresh()   # the list goes stale fast; poll while the page is open
	if page != "lobby" or seat_cards.is_empty():
		return
	var skins := Wardrobe.skins()
	var frames := Players.frames()
	var changed := false
	for i in frames.size():
		var f: DriveFrame = frames[i]
		var p: Dictionary = Players.players[i]
		var c: Dictionary = seat_cards[int(p["seat"])]
		if not bool(p["ready"]):
			var idx := skins.find(String(p["racer"]["unit"]))
			if f.next_pressed or (f.steer > 0.5 and not c.get("held", false)):
				idx = (idx + 1) % skins.size()
				changed = true
			elif f.prev_pressed or (f.steer < -0.5 and not c.get("held", false)):
				idx = (idx - 1 + skins.size()) % skins.size()
				changed = true
			c["held"] = absf(f.steer) > 0.5
			if changed:
				p["racer"] = {"kind": "wizard", "unit": skins[idx], "name": Wardrobe.racer_name(skins[idx])}
			if f.confirm_pressed:
				p["ready"] = true
				changed = true
				Audio.play("learn_spell", -6.0)
			elif f.back_pressed and String(p["controller"]) != "":
				Players.leave(String(p["controller"]))   # item/B while unready gives the seat back
				_refresh_lobby()
				return
		else:
			if f.back_pressed:
				p["ready"] = false
				changed = true
			elif f.confirm_pressed and int(p["seat"]) == int(Players.players[0]["seat"]):
				var all_ready := true
				for pl in Players.players:
					if not bool(pl["ready"]):
						all_ready = false
				if all_ready:
					_start_party()
					return
	if changed or Engine.get_physics_frames() % 30 == 0:
		_refresh_lobby()


# ---------------------------------------------------------------- online (Steam lobbies)

var online_map := "brick"


func _start_online(map: String, seed: int) -> void:
	race_type = "online"
	Campaign.new_run(seed)
	Campaign.race_type = "online"
	Campaign.level = 1
	Campaign.next_track = map
	get_tree().change_scene_to_file(RACE_SCENE)


func _online_changed() -> void:
	if page == "online":
		_show("online")


func _build_online() -> void:
	root.add_child(_at(_label("ONLINE (STEAM)", 60, Color(1.0, 0.93, 0.35)), Vector2(60, 20)))
	root.add_child(_at(_label(Net.status + "   Esc back", 20, Color(0.7, 0.7, 0.7)), Vector2(60, 88)))
	var vb := VBoxContainer.new()
	vb.position = Vector2(60, 150)
	vb.add_theme_constant_override("separation", 10)
	root.add_child(vb)
	if not Net.available:
		vb.add_child(_label("Steam must be running and signed in, with the GodotSteam plugin installed (tools/get_godotsteam.py).", 24))
		return
	if Net.lobby_id == 0:
		vb.add_child(_button("H   HOST A LOBBY", 28, Net.host, 760.0))
		vb.add_child(_button("R   REFRESH THE LIST", 28, Net.refresh, 760.0))
		vb.add_child(Control.new())
		var head := "LOBBIES   (press the number to join)"
		if Net.lobbies.is_empty():
			head = "searching..." if Net.searching else "no Drift Wizard lobbies right now"
		vb.add_child(_label(head, 24, Color(0.7, 0.7, 0.7)))
		var i := 1
		for l in Net.lobbies:
			var id: int = int(l["id"])
			var other := "" if String(l["protocol"]) == Net.PROTOCOL else "   (other version)"
			vb.add_child(_button("%d   %s   %d/%d   host %s%s" % [i, l["name"], int(l["members"]), int(l["max"]), l["host"], other], 24, func(): Net.join(id), 960.0))
			i += 1
			if i > 9:
				break
	else:
		vb.add_child(_label("LOBBY: %s%s" % [Net.lobby_name(), "   (you host)" if Net.is_host() else ""], 34, Color(0.55, 0.85, 1.0)))
		var i := 0
		for m in Net.members:
			vb.add_child(_label("%d   %s%s" % [i + 1, m["name"], "   host" if bool(m["host"]) else ""], 28, Players.COLORS[i % Players.COLORS.size()]))
			i += 1
		vb.add_child(Control.new())
		if Net.is_host():
			vb.add_child(_button("S   START THE RACE", 28, func(): Net.start_race(online_map, randi() % 1000000), 760.0))
			vb.add_child(_button("M   MAP:  %s" % online_map.to_upper(), 28, func(): pass, 760.0))
		else:
			vb.add_child(_label("waiting for the host to start the race", 24, Color(0.85, 0.85, 0.85)))
		vb.add_child(_button("I   INVITE FRIENDS   (Steam overlay)", 28, Net.invite_friends, 760.0))
		vb.add_child(_button("L   LEAVE THE LOBBY", 28, Net.leave, 760.0))
		vb.add_child(_label("the host runs the race and everyone drives their own kart; wardrobe outfits are worn", 18, Color(0.6, 0.6, 0.6)))
	var lv := VBoxContainer.new()
	lv.position = Vector2(1140, 150)
	lv.add_theme_constant_override("separation", 6)
	root.add_child(lv)
	lv.add_child(_label("EVENTS", 24, Color(0.7, 0.7, 0.7)))
	for line in Net.log_lines:
		lv.add_child(_label(String(line), 18))


# ---------------------------------------------------------------- Rift-Type realm select

var rift_realms: Array = []
var rift_sel := 0


func _build_rifttype() -> void:
	root.add_child(_at(_label("RIFT-TYPE", 60, Color(1.0, 0.93, 0.35)), Vector2(60, 20)))
	root.add_child(_at(_label("pick a realm: arrows move, enter flies.   the realm's map is the corridor, its monsters the waves, its boss the end.   Esc back", 18, Color(0.7, 0.7, 0.7)), Vector2(60, 88)))
	rift_realms.clear()
	var index: Array = []
	var f := FileAccess.open("res://qud/levels/index.json", FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Array:
			index = parsed
	var seen := {}
	for e in index:
		var r := int(e.get("difficulty", 0))
		if r <= 0 or seen.has(r):
			continue
		seen[r] = true
		rift_realms.append({"realm": r, "tileset": String(e.get("tileset", ""))})
	if rift_realms.is_empty():
		for r in range(1, 21):
			rift_realms.append({"realm": r, "tileset": ""})
	var scores := RiftType.scores_load()
	rift_sel = clampi(rift_sel, 0, rift_realms.size() - 1)
	for i in rift_realms.size():
		var rr: Dictionary = rift_realms[i]
		var realm := int(rr["realm"])
		var best := int(scores.get_value("realm", "best_%d" % realm, 0))
		var card := PanelContainer.new()
		card.position = Vector2(60 + (i % 7) * 258, 150 + int(i / 7) * 200)
		card.size = Vector2(240, 180)
		if i == rift_sel:
			card.modulate = Color(1.0, 0.93, 0.35)
		root.add_child(card)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 6)
		card.add_child(vb)
		vb.add_child(_label("REALM %d" % realm, 30, Color(1.0, 0.93, 0.35) if i == rift_sel else Color.WHITE))
		vb.add_child(_label(String(rr["tileset"]).capitalize(), 20, Color(0.8, 0.8, 0.8)))
		vb.add_child(_label(("best %d" % best) if best > 0 else "unflown", 20, Color(0.55, 0.85, 1.0) if best > 0 else Color(0.5, 0.5, 0.5)))
		var b := _button("FLY", 20, func(): _start_rifttype(realm), 200.0)
		vb.add_child(b)
	var best_run := int(scores.get_value("run", "best", 0))
	var farthest := int(scores.get_value("run", "farthest", 0))
	var plays := int(scores.get_value("run", "plays", 0))
	var line := "no runs yet" if plays == 0 else "best run %d (from realm %d to %d)     farthest realm cleared %d     %d flights" % [
		best_run, int(scores.get_value("run", "best_from", 1)), int(scores.get_value("run", "best_realm", 1)), farthest, plays]
	root.add_child(_at(_label(line, 24, Color(0.55, 0.85, 1.0)), Vector2(60, 980)))
	# the wizard you fly as
	var wz := PanelContainer.new()
	wz.position = Vector2(60, 760)
	wz.size = Vector2(1780, 200)
	root.add_child(wz)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 30)
	wz.add_child(hb)
	var tr := TextureRect.new()
	tr.texture = Wardrobe.preview(Campaign.skin)
	tr.custom_minimum_size = Vector2(180, 180)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hb.add_child(tr)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	hb.add_child(col)
	col.add_child(_label("YOUR WIZARD", 22, Color(0.55, 0.85, 1.0)))
	col.add_child(_label(Wardrobe.racer_name(Campaign.skin), 40, Color(1.0, 0.93, 0.35)))
	col.add_child(_label("[ and ] cycle the game's outfits     W opens the wardrobe", 20, Color(0.7, 0.7, 0.7)))


func _start_rifttype(realm: int) -> void:
	Campaign.new_run()
	Campaign.level = realm
	Campaign.rift = {}
	get_tree().change_scene_to_file(RIFTTYPE_SCENE)


func _start_party() -> void:
	Players.joins_enabled = false
	race_type = "party"
	Campaign.new_run()
	Campaign.race_type = "party"
	Campaign.level = 1
	Campaign.skin = String(Players.players[0]["racer"]["unit"])
	get_tree().change_scene_to_file(RACE_SCENE)


func _at(c: Control, pos: Vector2) -> Control:
	c.position = pos
	return c


# ---------------------------------------------------------------- launching

func _start_race(realm: int, realm_file := "") -> void:
	Campaign.new_run()
	Campaign.level = realm
	Campaign.realm_file = realm_file
	Campaign.race_type = race_type
	get_tree().change_scene_to_file(RACE_SCENE)


func _start_rig() -> void:
	Campaign.new_run()
	Campaign.race_type = "rig"
	Campaign.rig = "ahead:250,behind:250,swerve:420,beside:-90"
	get_tree().change_scene_to_file(RACE_SCENE)


func _open_wardrobe() -> void:
	if wardrobe != null:
		return
	wardrobe = Wardrobe.new()
	add_child(wardrobe)
	wardrobe.closed.connect(func():
		wardrobe.queue_free()
		wardrobe = null
		if Campaign.racer.get("kind", "wizard") == "wizard":
			Campaign.set_racer("wizard", Campaign.skin, Wardrobe.racer_name(Campaign.skin))
		_show("title"))


# --mode=dump --out=path: write what SpellDB/Artifacts currently make of every spell and
# artifact, plus the tuning, for tools/export_rules.py.
func _dump_mapping(args: PackedStringArray) -> void:
	var out := ""
	for a in args:
		if a.begins_with("--out="):
			out = a.substr(6)
	var spells := []
	for s in SpellDB.spells:
		var owned := SpellDB.make_owned(s)
		spells.append({"name": s["name"], "effect": owned["effect"], "charges": owned["max_charges"], "unlimited": owned["unlimited"],
			"cooldown": owned["cooldown"], "hp_cost": owned["hp_cost"], "summon_unit": owned["unit"]})
	var arts := []
	for a in Artifacts.items:
		var owned := Artifacts.make_owned(a)
		arts.append({"name": a["name"], "effect": owned["effect"], "label": owned["label"]})
	var rules := {
		"melee": "game melee flag -> 'melee': a swipe at karts within campaign.melee_range px in front (stun 0.3 s, shove campaign.melee_shove); damage = max(damage, 5*level)",
		"summon": "stats.minion_health -> 'summon': min(3, num_summons) karts riding in formation with the caster for minion_duration turns * 0.8 s, biting karts within reach",
		"blast": "damage and stats.radius -> 'blast': a fireball projectile that detonates near a kart, radius max(60, radius * 70) px",
		"beam": "damage and (Lightning tag or bolt/beam/ray in the name) -> 'beam': instant hits on up to num_targets (max 4) karts ahead within range",
		"bolt": "any other damaging spell -> 'bolt': a homing projectile; damage = max(damage, 5*level), range = max(300, range*90) px",
		"shield": "stats.shields -> 'shield': that many hits absorbed",
		"heal": "stats.heal or Heal tag -> 'heal': max(8, heal or 4*level) HP",
		"buff": "self_target or range 0 without damage -> 'buff': a speed boost of 0.2 + 0.03*level for duration turns * 0.8 s",
		"blink": "Translocation tag -> 'blink': jump max(300, range*90) px along the track",
		"hex": "otherwise a duration -> 'hex': stun the kart ahead for min(3.5, duration*0.8) s and make it slide",
		"burst/aura/patch/empower": "only from shared/overrides.json: damage around the caster; periodic hits or heals for a while; a hazard laid up the road; temporary artifact-style bonuses",
		"charges": "max_charges capped at 12; 0 = unlimited on a campaign.unlimited_cooldown real-time cooldown; hp_cost paid per cast, refused at 0 HP",
		"artifacts": "global_bonuses map to kart bonuses when they have any; otherwise the item's description (shield, summon, heal, charge, radius, range, duration, teleport, HP, speed, damage), otherwise the first tag",
		"lap_rule": "leading at the line: every monster takes campaign.lap_damage_lead_pct of its max HP; otherwise the wizard takes lap_damage_per_rank per rank behind, capped",
	}
	var data := {"spells": spells, "artifacts": arts, "mapping_rules": rules, "tuning": Shared.tuning}
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(data, "  "))
			f.close()
			print("dump: %d spells, %d artifacts -> %s" % [spells.size(), arts.size(), out])
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if wardrobe != null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k == KEY_ESCAPE:
			if page == "title":
				get_tree().quit()
			else:
				if page == "online":
					Net.leave()
				_show("title")
			return
		if page == "title":
			if k == KEY_ENTER or k == KEY_KP_ENTER:
				_show("types")
			elif k == KEY_R:
				_show("racers")
			elif k == KEY_W:
				_open_wardrobe()
			elif k == KEY_T:
				_start_rig()
			elif k == KEY_2:
				get_tree().change_scene_to_file(SURVIVORS_SCENE)
			elif k == KEY_3:
				Campaign.new_run()
				get_tree().change_scene_to_file(GAUNTLET_SCENE)
			elif k == KEY_4:
				_show("rifttype")
			elif k == KEY_Q:
				get_tree().quit()
		elif page == "online":
			if k == KEY_H:
				Net.host()
			elif k == KEY_R:
				Net.refresh()
			elif k == KEY_L:
				Net.leave()
			elif k == KEY_I:
				Net.invite_friends()
			elif k == KEY_S and Net.lobby_id != 0 and Net.is_host():
				Net.start_race(online_map, randi() % 1000000)
			elif k == KEY_M and Net.lobby_id != 0 and Net.is_host():
				var keys: Array = Shared.tracks.keys()
				online_map = keys[(keys.find(online_map) + 1) % keys.size()]
				_show("online")
			elif k >= KEY_1 and k <= KEY_9 and Net.lobby_id == 0:
				var i := k - KEY_1
				if i < Net.lobbies.size():
					Net.join(int(Net.lobbies[i]["id"]))
		elif page == "rifttype":
			var n := rift_realms.size()
			if k == KEY_RIGHT:
				rift_sel = (rift_sel + 1) % n
				_show("rifttype")
			elif k == KEY_LEFT:
				rift_sel = (rift_sel - 1 + n) % n
				_show("rifttype")
			elif k == KEY_DOWN:
				rift_sel = mini(n - 1, rift_sel + 7)
				_show("rifttype")
			elif k == KEY_UP:
				rift_sel = maxi(0, rift_sel - 7)
				_show("rifttype")
			elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
				_start_rifttype(int(rift_realms[rift_sel]["realm"]))
			elif k == KEY_BRACKETRIGHT or k == KEY_BRACKETLEFT:
				var skins := Wardrobe.skins()
				var idx := skins.find(Campaign.skin)
				idx = (idx + (1 if k == KEY_BRACKETRIGHT else -1) + skins.size()) % skins.size()
				Campaign.set_skin(skins[idx])
				_show("rifttype")
			elif k == KEY_W:
				_open_wardrobe()
		elif page == "types":
			var digits := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]
			var i := digits.find(k)
			if i >= 0 and i < RACE_TYPES.size():
				_pick_type(String(RACE_TYPES[i]["key"]))
