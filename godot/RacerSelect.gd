# The four-player racer select (mutant-plan/strategy/2caves2qud-large-roster-character-select.md).
#
# Five regions: a shared, stable grid of COLLECTIONS in the centre and one quadrant per
# seat. A seat is UNJOINED -> COLLECTION (a marker on the shared grid) -> BROWSE (a
# private 2x5 page of that collection) -> VARIANT (the racer's numbered siblings) ->
# READY. One seat's browsing never moves another's. Utility tiles: Favorites, Recently
# Used, All Racers, Random. Player identity is redundant: colour, a big P-number badge
# and a distinct corner shape.
#
# Input comes through the local-multiplayer stack (Players / DriveAdapter frames): steer
# and throttle are the d-pad (edge-detected here), drift/cast = A confirm, item = B back,
# bumpers page. Reads qud/data/racers.json (tools/qud_racers.py); favorites and recent
# picks persist per seat in user://racers.cfg.
#
# The extras (docs/racer-select.md): LOCKS (a monster of select.lock_band or above is locked
# until slain in the Monster Campaign, Campaign.unlocked), the DUPLICATE rule (twins allowed,
# the later seat is moved to the next free variant and told so), FILTERS (key 9 cycles) and
# SORTS (key 8 cycles) per seat, keyboard SEARCH (/ types into the browser), the 3D
# racer-and-vehicle PREVIEW on a pedestal, spoken names (select.spoken_names or --spoken,
# the OS voice) and reduced motion (select.reduced_motion or --reduced_motion).
# --select_log prints `select:` lines; --select_keys=seat:action,... scripts a session.
class_name RacerSelect
extends Control

const GRID_COLS := 4
const PAGE := 10                # 2 x 5 browser
const PAGE_COLS := 5
const RECENT_MAX := 12
const QUAD := [Vector2(40, 130), Vector2(1400, 130), Vector2(40, 600), Vector2(1400, 600)]
const QUAD_SIZE := Vector2(480, 440)
const GRID_ORIGIN := Vector2(560, 150)
const TILE := Vector2(190, 190)
const SHAPES := ["square", "round", "diamond", "hexagon"]
const FILTERS := ["all", "unlocked", "flying", "light", "middleweight", "heavy"]
const SORTS := ["collection", "name", "speed", "weight"]
const FILTER_SLOT := 8          # the "9" key
const SORT_SLOT := 7            # the "8" key

signal start_requested

var catalogue := {}
var collections: Array = []
var racers := {}
var seats: Array = []           # per Players.MAX: {state, col, page, focus, variant, racer, held: {}, fav, recent}
var demo := ""
var _grid_tiles: Array = []
var _quads: Array = []
var _heading: Label
var _prompt: Label
var cfg := ConfigFile.new()
var select_log := false
var spoken := false
var reduced_motion := false
var lock_band := 6
var typing_seat := -1           # the keyboard seat whose letters go to its search
var _t := 0.0


func _ready() -> void:
	catalogue = Shared.load_json(QUD.ROOT + "data/racers.json")
	collections = catalogue.get("collections", [])
	racers = catalogue.get("racers", {})
	cfg.load("user://racers.cfg")
	for seat in Players.MAX:
		seats.append({"state": "unjoined", "col": 4 if collections.size() > 4 else 0, "page": 0, "focus": 0, "variant": 0,
			"racer": "", "held": {}, "fav": Array(cfg.get_value("seat%d" % seat, "favorites", [])),
			"recent": Array(cfg.get_value("seat%d" % seat, "recent", [])), "list": [],
			"filter": 0, "sort": 0, "search": "", "notice": ""})
	var args := OS.get_cmdline_user_args()
	select_log = "--select_log" in args
	spoken = bool(Shared.t(["select", "spoken_names"], false)) or "--spoken" in args
	reduced_motion = bool(Shared.t(["select", "reduced_motion"], false)) or "--reduced_motion" in args
	lock_band = int(Shared.t(["select", "lock_band"], 6))
	_build()
	var keys := ""
	for a in args:
		if a.begins_with("--select_demo="):
			demo = a.substr(14)
		elif a.begins_with("--select_keys="):
			keys = a.substr(14)
	if demo != "":
		_apply_demo()
	if keys != "":
		_apply_keys(keys)
	refresh()


func _log(msg: String) -> void:
	if select_log:
		print("select: " + msg)


# ---------------------------------------------------------------- locks, filters, search

static func band_of(rec: Dictionary) -> int:
	var lv := int(rec.get("level", 0))
	return 1 if lv <= 0 else 1 + (lv - 1) / 4


# A monster of the lock band or above is locked until one has been slain in the Monster
# Campaign (Campaign.unlock on a kill); castes and the low bands are always open.
func locked(id: String) -> bool:
	var rec: Dictionary = racers.get(id, {})
	if String(rec.get("kind", "monster")) != "monster":
		return false
	return band_of(rec) >= lock_band and not Campaign.unlocked.has(String(rec.get("name", "")))


func _passes(seat: int, id: String) -> bool:
	var s: Dictionary = seats[seat]
	var rec: Dictionary = racers.get(id, {})
	match FILTERS[int(s["filter"])]:
		"unlocked":
			if locked(id):
				return false
		"flying":
			if not bool(rec.get("flying", false)):
				return false
		"light", "middleweight", "heavy":
			if not String(rec.get("driving_class", "")).to_lower().begins_with(FILTERS[int(s["filter"])].substr(0, 5)):
				return false
	var q: String = String(s["search"]).to_lower()
	if q != "":
		var hay := (String(rec.get("name", "")) + " " + id + " " + String(rec.get("family", "")) + " " + String(rec.get("qud", "")) + " " + " ".join(rec.get("tags", []))).to_lower()
		if not hay.contains(q):
			return false
	return true


func _apply_filters(seat: int, base: Array) -> Array:
	var s: Dictionary = seats[seat]
	var out: Array = base.filter(func(u): return racers.has(u) and _passes(seat, u))
	match SORTS[int(s["sort"])]:
		"name":
			out.sort_custom(func(a, b): return String(racers[a]["name"]) < String(racers[b]["name"]))
		"speed":
			out.sort_custom(func(a, b): return int(racers[a].get("speed", 5)) > int(racers[b].get("speed", 5)))
		"weight":
			out.sort_custom(func(a, b): return int(racers[a].get("weight", 5)) > int(racers[b].get("weight", 5)))
	return out


# Rebuild a browsing seat's list after a filter, sort or search change, keeping its racer
# under the cursor when it survives.
func _relist(seat: int) -> void:
	var s: Dictionary = seats[seat]
	if s["state"] != "browse":
		return
	var cur: String = s["list"][clampi(s["focus"], 0, s["list"].size() - 1)] if s["list"].size() > 0 else ""
	s["list"] = _list_for(seat)
	s["focus"] = maxi(0, s["list"].find(cur))
	s["page"] = s["focus"] / PAGE
	_log("seat%d filter=%s sort=%s search=%s list=%d" % [seat, FILTERS[int(s["filter"])], SORTS[int(s["sort"])], "\"%s\"" % String(s["search"]), s["list"].size()])


func _cycle_filter(seat: int) -> void:
	var s: Dictionary = seats[seat]
	s["filter"] = (int(s["filter"]) + 1) % FILTERS.size()
	_relist(seat)
	Audio.play("item_pickup", -12.0)


func _cycle_sort(seat: int) -> void:
	var s: Dictionary = seats[seat]
	s["sort"] = (int(s["sort"]) + 1) % SORTS.size()
	_relist(seat)
	Audio.play("item_pickup", -12.0)


func _search_set(seat: int, text: String) -> void:
	var s: Dictionary = seats[seat]
	s["search"] = text
	if s["state"] == "collection":
		s["col"] = _col_index("all")
		_open_collection(seat)
	else:
		_relist(seat)


func _is_keyboard_seat(seat: int) -> bool:
	var p := _player_for_seat(seat)
	return not p.is_empty() and String(p.get("controller", "")).begins_with("keyboard:")


# Keyboard search: / starts typing on the first joined keyboard seat that is browsing (or
# choosing a collection: the search opens All Racers), letters filter as they land,
# Backspace deletes, Enter or Esc stops typing and keeps the search; B clears it.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var k: InputEventKey = event
	if typing_seat < 0:
		if k.keycode == KEY_SLASH:
			for seat in seats.size():
				if seats[seat]["state"] in ["collection", "browse"] and _is_keyboard_seat(seat):
					typing_seat = seat
					_log("seat%d typing" % seat)
					get_viewport().set_input_as_handled()
					return
		return
	var s: Dictionary = seats[typing_seat]
	if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_ESCAPE:
		_log("seat%d typed \"%s\"" % [typing_seat, String(s["search"])])
		typing_seat = -1
	elif k.keycode == KEY_BACKSPACE:
		_search_set(typing_seat, String(s["search"]).left(maxi(0, String(s["search"]).length() - 1)))
	elif k.unicode >= 32 and k.unicode < 127:
		_search_set(typing_seat, String(s["search"]) + char(k.unicode))
	get_viewport().set_input_as_handled()


# The duplicate rule: twins are allowed; the later seat is moved to the first variant no
# other seat holds, and told when there is none.
func _dedupe_variant(seat: int) -> void:
	var s: Dictionary = seats[seat]
	var rec: Dictionary = racers.get(s["racer"], {})
	var nv: int = maxi(1, rec.get("variants", [1]).size())
	var taken := {}
	var twin := -1
	for o in seats.size():
		if o != seat and seats[o]["state"] in ["variant", "ready"] and seats[o]["racer"] == s["racer"]:
			taken[int(seats[o]["variant"])] = true
			twin = o if twin < 0 else twin
	s["notice"] = ""
	if twin < 0:
		return
	for v in nv:
		if not taken.has(v):
			s["variant"] = v
			s["notice"] = "TWIN OF P%d: VARIANT %d" % [twin + 1, v + 1]
			_log("seat%d twin of seat%d -> variant %d" % [seat, twin, v])
			return
	s["notice"] = "SAME LOOK AS P%d" % (twin + 1)
	_log("seat%d twin of seat%d, no free variant" % [seat, twin])


func speak(text: String) -> void:
	if not spoken or text == "":
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) and not DisplayServer.tts_get_voices_for_language("en").is_empty():
		DisplayServer.tts_stop()
		DisplayServer.tts_speak(text, String(DisplayServer.tts_get_voices_for_language("en")[0]))
		_log("say \"%s\"" % text)
	else:
		_log("say \"%s\" (no voice)" % text)


# ---------------------------------------------------------------- build

func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build() -> void:
	size = Vector2(1920, 1080)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.09)
	bg.size = size
	add_child(bg)
	_heading = _label("CHOOSE YOUR RACER", 44, Color(1.0, 0.93, 0.35))
	_heading.position = Vector2(560, 40)
	add_child(_heading)
	_prompt = _label("", 22, Color(0.75, 0.75, 0.75))
	_prompt.position = Vector2(560, 1000)
	add_child(_prompt)
	# the shared collection grid
	for i in collections.size():
		var c: Dictionary = collections[i]
		var tile := PanelContainer.new()
		tile.position = GRID_ORIGIN + Vector2((i % GRID_COLS) * (TILE.x + 10), (i / GRID_COLS) * (TILE.y + 10))
		tile.size = TILE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.11, 0.18)
		sb.set_corner_radius_all(6)
		tile.add_theme_stylebox_override("panel", sb)
		add_child(tile)
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		tile.add_child(vb)
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(0, 110)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if String(c.get("icon", "")) != "":
			tr.texture = Wardrobe.preview(String(c["icon"]))
		else:
			tr.texture = QUD.icon({"favorites": "item_ruby_heart", "recent": "item_bookshelf", "all": "item_spell_scroll", "random": "item_trinket"}.get(String(c.get("utility", "")), "item_mana_orb")) if false else _utility_icon(String(c.get("utility", "")))
		vb.add_child(tr)
		var nl := _label(String(c["name"]).to_upper(), 20)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(nl)
		var cnt := _label(("%d racers" % c["racers"].size()) if not c.has("utility") or c["utility"] == "all" else "", 14, Color(0.6, 0.6, 0.6))
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(cnt)
		var badges := HBoxContainer.new()
		badges.position = Vector2(4, 4)
		tile.add_child(badges)
		_grid_tiles.append({"tile": tile, "style": sb, "badges": badges, "count": cnt})
	for seat in Players.MAX:
		_quads.append(_build_quad(seat))


func _utility_icon(kind: String) -> Texture2D:
	return QUD.texture({"favorites": "tiles/item_ruby_heart.png", "recent": "tiles/item_bookshelf.png",
		"all": "tiles/item_spell_scroll.png", "random": "tiles/item_trinket.png"}.get(kind, "tiles/item_mana_orb.png"))


func _build_quad(seat: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.position = QUAD[seat]
	panel.size = QUAD_SIZE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.13)
	sb.border_color = Players.COLORS[seat]
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var badge := _label(" P%d " % (seat + 1), 30, Color(0.05, 0.04, 0.09))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Players.COLORS[seat]
	bsb.set_corner_radius_all(4 if seat == 0 else (14 if seat == 1 else 0))
	badge.add_theme_stylebox_override("normal", bsb)
	head.add_child(badge)
	var state := _label("PRESS A TO JOIN", 22, Color(0.7, 0.7, 0.7))
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(state)
	var body := Control.new()
	body.custom_minimum_size = Vector2(0, 300)
	vb.add_child(body)
	var portrait := TextureRect.new()
	portrait.position = Vector2(20, 10)
	portrait.size = Vector2(200, 260)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(portrait)
	var view := _build_preview(seat)
	view.position = Vector2(20, 10)
	view.visible = false
	body.add_child(view)
	var info := _label("", 18, Color(0.85, 0.85, 0.85))
	info.position = Vector2(240, 10)
	info.size = Vector2(220, 280)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(info)
	var grid := GridContainer.new()
	grid.columns = PAGE_COLS
	grid.position = Vector2(10, 4)
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.visible = false
	body.add_child(grid)
	var cells: Array = []
	for i in PAGE:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(86, 120)
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.14, 0.13, 0.2)
		csb.set_corner_radius_all(4)
		cell.add_theme_stylebox_override("panel", csb)
		var ctr := TextureRect.new()
		ctr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ctr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ctr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cell.add_child(ctr)
		grid.add_child(cell)
		cells.append({"cell": cell, "style": csb, "tex": ctr})
	var name_l := _label("", 26, Color.WHITE)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(name_l)
	var sub := _label("", 16, Color(0.6, 0.6, 0.6))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)
	return {"panel": panel, "style": sb, "state": state, "portrait": portrait, "info": info, "grid": grid,
		"cells": cells, "name": name_l, "sub": sub, "view": view, "view_unit": ""}


# The racer-and-vehicle preview: the racer's idle sprite (the vehicle IS the sprite in this
# engine: a kart is a Qud creature on the road) on a pedestal in the seat's colour, in its
# own little world, turning slowly unless reduced motion is on.
func _build_preview(seat: int) -> SubViewportContainer:
	var box := SubViewportContainer.new()
	box.size = Vector2(200, 260)
	box.stretch = true
	var vp := SubViewport.new()
	vp.size = Vector2i(200, 260)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	box.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 46, 150)
	cam.look_at_from_position(cam.position, Vector3(0, 34, 0), Vector3.UP)
	cam.fov = 38
	world.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var pivot := Node3D.new()
	world.add_child(pivot)
	var ped := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 34
	cyl.bottom_radius = 38
	cyl.height = 7
	ped.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Players.COLORS[seat].darkened(0.35)
	ped.material_override = mat
	pivot.add_child(ped)
	var spr := Sprite3D.new()
	spr.pixel_size = 1.0
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	pivot.add_child(spr)
	box.set_meta("pivot", pivot)
	box.set_meta("sprite", spr)
	box.set_meta("frames", 1)
	return box


func _show_preview(seat: int, unit: String) -> void:
	var q: Dictionary = _quads[seat]
	var box: SubViewportContainer = q["view"]
	if q["view_unit"] == unit:
		return
	q["view_unit"] = unit
	var spr: Sprite3D = box.get_meta("sprite")
	var info: Dictionary = QUD.unit_info(unit)
	var fs := int(info.get("frame_size", 60))
	var frames := maxi(1, int(info.get("idle_frames", 1)))
	spr.texture = QUD.unit_idle(unit)
	spr.hframes = frames
	spr.frame = 0
	spr.position = Vector3(0, fs * 0.5 + 4.0, 0)
	box.set_meta("frames", frames)
	_log("seat%d preview unit=%s frames=%d" % [seat, unit, frames])


func _process(delta: float) -> void:
	_t += delta
	for seat in _quads.size():
		var box: SubViewportContainer = _quads[seat]["view"]
		if not box.visible:
			continue
		var spr: Sprite3D = box.get_meta("sprite")
		var pivot: Node3D = box.get_meta("pivot")
		spr.frame = int(_t / 0.2) % maxi(1, int(box.get_meta("frames")))
		if reduced_motion:
			pivot.rotation.y = 0.0
			spr.rotation.y = 0.0
		else:
			pivot.rotation.y = _t * 0.6
			spr.rotation.y = sin(_t * 0.6) * 0.35      # a flat sprite: sway, never edge-on


# ---------------------------------------------------------------- state

func _list_for(seat: int) -> Array:
	var s: Dictionary = seats[seat]
	var c: Dictionary = collections[s["col"]]
	match String(c.get("utility", "")):
		"favorites":
			return _apply_filters(seat, s["fav"])
		"recent":
			return _apply_filters(seat, s["recent"])
		"random":
			return []
	return _apply_filters(seat, c["racers"])


func join(seat: int) -> void:
	var s: Dictionary = seats[seat]
	if s["state"] != "unjoined":
		return
	s["state"] = "collection"
	# open where the player left off: recent first, else the starter collection (Castes)
	if s["recent"].size() > 0:
		s["col"] = _col_index("recent")
	else:
		s["col"] = _col_index("castes")
	Audio.play("start_level", -8.0)


func _col_index(id: String) -> int:
	for i in collections.size():
		if String(collections[i]["id"]) == id:
			return i
	return 0


func _open_collection(seat: int) -> void:
	var s: Dictionary = seats[seat]
	var c: Dictionary = collections[s["col"]]
	if String(c.get("utility", "")) == "random":
		_random_pick(seat)
		return
	var lst := _list_for(seat)
	if lst.is_empty():
		Audio.play("menu_abort", -6.0)
		return
	s["list"] = lst
	s["state"] = "browse"
	var remembered := lst.find(String(s.get("last_racer", "")))
	s["focus"] = maxi(0, remembered)
	s["page"] = s["focus"] / PAGE
	s["notice"] = ""
	_log("seat%d browse %s list=%d" % [seat, String(c["id"]), lst.size()])
	Audio.play("item_pickup", -8.0)


# Random respects locks, the seat's filters and search, and the duplicate rule.
func _random_pick(seat: int) -> void:
	var s: Dictionary = seats[seat]
	var all: Array = _apply_filters(seat, collections[_col_index("all")]["racers"]).filter(func(u): return not locked(u))
	if all.is_empty():
		s["notice"] = "NOTHING MATCHES"
		Audio.play("menu_abort", -6.0)
		return
	s["list"] = all
	s["racer"] = all[randi() % all.size()]
	s["variant"] = 0
	s["state"] = "variant"
	s["from_random"] = true
	_dedupe_variant(seat)
	_log("seat%d random %s" % [seat, String(s["racer"])])
	speak(String(racers[s["racer"]]["name"]))
	Audio.play("item_pickup", -8.0)


func _choose(seat: int) -> void:
	var s: Dictionary = seats[seat]
	var lst: Array = s["list"]
	if lst.is_empty():
		return
	var id: String = lst[clampi(s["focus"], 0, lst.size() - 1)]
	if locked(id):
		s["notice"] = "LOCKED: SLAY ONE IN THE MONSTER CAMPAIGN"
		_log("seat%d locked %s (band %d)" % [seat, id, band_of(racers[id])])
		Audio.play("menu_abort", -6.0)
		return
	s["racer"] = id
	s["last_racer"] = s["racer"]
	s["variant"] = 0
	s["state"] = "variant"
	s["from_random"] = false
	_dedupe_variant(seat)
	_log("seat%d choose %s variant=%d" % [seat, id, int(s["variant"])])
	speak(String(racers[id]["name"]))
	Audio.play("item_pickup", -6.0)


func _ready_up(seat: int) -> void:
	var s: Dictionary = seats[seat]
	s["state"] = "ready"
	var rec: Dictionary = racers[s["racer"]]
	var recent: Array = s["recent"]
	recent.erase(s["racer"])
	recent.push_front(s["racer"])
	while recent.size() > RECENT_MAX:
		recent.pop_back()
	_save(seat)
	_log("seat%d ready %s variant=%d" % [seat, String(s["racer"]), int(s["variant"])])
	Audio.play("learn_spell", -6.0)
	_assign(seat, rec)


func _assign(seat: int, rec: Dictionary) -> void:
	var v: Dictionary = rec["variants"][clampi(seats[seat]["variant"], 0, rec["variants"].size() - 1)]
	var kind := "wizard" if String(rec.get("kind", "monster")) == "caste" else "monster"
	var p := _player_for_seat(seat)
	if not p.is_empty():
		p["racer"] = {"kind": kind, "unit": String(v["unit"]), "name": String(v["name"])}
		p["ready"] = true
	if seat == 0 or Players.count() <= 1:
		Campaign.set_racer(kind, String(v["unit"]), String(v["name"]))


func _player_for_seat(seat: int) -> Dictionary:
	for pl in Players.players:
		if int(pl["seat"]) == seat:
			return pl
	return {}


func _toggle_fav(seat: int) -> void:
	var s: Dictionary = seats[seat]
	var u := ""
	if s["state"] == "browse" and not s["list"].is_empty():
		u = s["list"][clampi(s["focus"], 0, s["list"].size() - 1)]
	elif s["state"] in ["variant", "ready"]:
		u = s["racer"]
	if u == "":
		return
	if s["fav"].has(u):
		s["fav"].erase(u)
	else:
		s["fav"].append(u)
	_save(seat)
	Audio.play("item_pickup", -10.0)


func _save(seat: int) -> void:
	cfg.set_value("seat%d" % seat, "favorites", seats[seat]["fav"])
	cfg.set_value("seat%d" % seat, "recent", seats[seat]["recent"])
	cfg.save("user://racers.cfg")


func all_ready() -> bool:
	var any := false
	for s in seats:
		if s["state"] == "unjoined":
			continue
		any = true
		if s["state"] != "ready":
			return false
	return any


# ---------------------------------------------------------------- input (one seat's frame)

func _edge(s: Dictionary, key: String, down: bool) -> bool:
	var was: bool = s["held"].get(key, false)
	s["held"][key] = down
	return down and not was


func handle(seat: int, f: DriveFrame) -> bool:
	"""Apply one DriveFrame to a seat. Returns true when the shared START was requested."""
	var s: Dictionary = seats[seat]
	var right := _edge(s, "right", f.steer > 0.5) or f.next_pressed
	var left := _edge(s, "left", f.steer < -0.5) or f.prev_pressed
	var up := _edge(s, "up", f.throttle > 0.5)
	var down := _edge(s, "down", f.throttle < -0.5)
	var fav := _edge(s, "fav", f.slot == 9)      # Y / slot 0
	var filt := _edge(s, "filter", f.slot == FILTER_SLOT)
	var srt := _edge(s, "sort", f.slot == SORT_SLOT)
	if typing_seat == seat:
		return false                             # the letters are a search, not a drive
	if filt and s["state"] in ["collection", "browse"]:
		_cycle_filter(seat)
	if srt and s["state"] in ["collection", "browse"]:
		_cycle_sort(seat)
	match String(s["state"]):
		"unjoined":
			if f.confirm_pressed:
				join(seat)
		"collection":
			var n := collections.size()
			if right:
				s["col"] = (s["col"] + 1) % n
			elif left:
				s["col"] = (s["col"] - 1 + n) % n
			elif down:
				s["col"] = mini(n - 1, s["col"] + GRID_COLS)
			elif up:
				s["col"] = maxi(0, s["col"] - GRID_COLS)
			if f.confirm_pressed:
				_open_collection(seat)
			elif f.back_pressed:
				s["state"] = "unjoined"
				var p := _player_for_seat(seat)
				if not p.is_empty() and String(p["controller"]) != "":
					Players.leave(String(p["controller"]))
			if fav:
				s["col"] = _col_index("favorites")
		"browse":
			var lst: Array = s["list"]
			var n := lst.size()
			if n > 0:
				if f.next_pressed or (right and s["focus"] % PAGE == PAGE - 1):
					s["focus"] = mini(n - 1, (s["focus"] / PAGE + 1) * PAGE) if s["focus"] / PAGE < (n - 1) / PAGE else s["focus"]
				elif right:
					s["focus"] = mini(n - 1, s["focus"] + 1)
				elif f.prev_pressed:
					s["focus"] = maxi(0, (s["focus"] / PAGE - 1) * PAGE)
				elif left:
					s["focus"] = maxi(0, s["focus"] - 1)
				elif down and s["focus"] % PAGE < PAGE_COLS:
					s["focus"] = mini(n - 1, s["focus"] + PAGE_COLS)
				elif up and s["focus"] % PAGE >= PAGE_COLS:
					s["focus"] -= PAGE_COLS
				s["page"] = s["focus"] / PAGE
				if right or left or up or down or f.next_pressed or f.prev_pressed:
					speak(String(racers[lst[clampi(s["focus"], 0, n - 1)]]["name"]))
			if f.confirm_pressed:
				_choose(seat)
			elif f.back_pressed:
				if String(s["search"]) != "":
					_search_set(seat, "")          # B clears the search before it leaves
				else:
					s["state"] = "collection"
			if fav:
				_toggle_fav(seat)
		"variant":
			var rec: Dictionary = racers.get(s["racer"], {})
			var nv: int = rec.get("variants", [1]).size()
			if bool(s.get("from_random", false)) and (left or right):
				_random_pick(seat)
			elif right:
				s["variant"] = (s["variant"] + 1) % maxi(1, nv)
				s["notice"] = ""
			elif left:
				s["variant"] = (s["variant"] - 1 + nv) % maxi(1, nv)
				s["notice"] = ""
			if f.confirm_pressed:
				_ready_up(seat)
			elif f.back_pressed:
				s["state"] = "collection" if bool(s.get("from_random", false)) else "browse"
			if fav:
				_toggle_fav(seat)
		"ready":
			if f.back_pressed:
				s["state"] = "variant"
				var p := _player_for_seat(seat)
				if not p.is_empty():
					p["ready"] = false
			elif f.confirm_pressed and seat == _first_seat() and all_ready():
				return true
	return false


func _first_seat() -> int:
	for i in seats.size():
		if seats[i]["state"] != "unjoined":
			return i
	return 0


# ---------------------------------------------------------------- draw

func refresh() -> void:
	# collection tiles: markers of every seat choosing a collection
	for i in _grid_tiles.size():
		var t: Dictionary = _grid_tiles[i]
		for b in t["badges"].get_children():
			b.queue_free()
		var focused := false
		for seat in seats.size():
			var s: Dictionary = seats[seat]
			if s["state"] in ["collection", "browse", "variant", "ready"] and s["col"] == i:
				var badge := _label(" P%d " % (seat + 1), 16, Color(0.05, 0.04, 0.09))
				var bsb := StyleBoxFlat.new()
				bsb.bg_color = Players.COLORS[seat]
				badge.add_theme_stylebox_override("normal", bsb)
				t["badges"].add_child(badge)
				if s["state"] == "collection":
					focused = true
		t["style"].border_color = Color(1, 1, 1) if focused else Color(0.12, 0.11, 0.18)
		t["style"].set_border_width_all(3 if focused else 0)
	var joined := 0
	for seat in seats.size():
		var s: Dictionary = seats[seat]
		var q: Dictionary = _quads[seat]
		if s["state"] != "unjoined":
			joined += 1
		q["grid"].visible = s["state"] == "browse"
		q["portrait"].visible = s["state"] in ["unjoined", "collection"]
		q["view"].visible = s["state"] in ["variant", "ready"]
		q["info"].visible = s["state"] != "browse"
		q["style"].bg_color = Color(0.09, 0.08, 0.13) if s["state"] != "unjoined" else Color(0.06, 0.055, 0.09)
		q["style"].border_color = Players.COLORS[seat] if s["state"] != "unjoined" else Players.COLORS[seat].darkened(0.6)
		match String(s["state"]):
			"unjoined":
				q["state"].text = "PRESS A TO JOIN"
				q["portrait"].texture = null
				q["info"].text = ""
				q["name"].text = ""
				q["sub"].text = "keyboard: WASD side or arrows side, or any gamepad button"
			"collection":
				var c: Dictionary = collections[s["col"]]
				q["state"].text = "CHOOSING"
				q["portrait"].texture = Wardrobe.preview(String(c["icon"])) if String(c.get("icon", "")) != "" else _utility_icon(String(c.get("utility", "")))
				q["info"].text = String(c["description"])
				q["name"].text = String(c["name"]).to_upper()
				q["sub"].text = "A open   B leave   Y favorites"
			"browse":
				var c: Dictionary = collections[s["col"]]
				var lst: Array = s["list"]
				var pages := maxi(1, (lst.size() + PAGE - 1) / PAGE)
				q["state"].text = "PAGE %d / %d    %d / %d" % [s["page"] + 1, pages, s["focus"] + 1, lst.size()]
				if typing_seat == seat:
					q["state"].text = "SEARCH: %s_" % String(s["search"])
				elif String(s["search"]) != "":
					q["state"].text = "\"%s\"  %d / %d" % [String(s["search"]), s["focus"] + 1, lst.size()]
				for i in PAGE:
					var cd: Dictionary = q["cells"][i]
					var idx: int = s["page"] * PAGE + i
					if idx < lst.size():
						cd["tex"].texture = Wardrobe.preview(String(racers[lst[idx]]["unit"]))
						cd["tex"].modulate = Color(0.35, 0.35, 0.4) if locked(lst[idx]) else Color.WHITE
						cd["cell"].visible = true
						var foc: bool = idx == int(s["focus"])
						cd["style"].border_color = Players.COLORS[seat] if foc else Color(0.14, 0.13, 0.2)
						cd["style"].set_border_width_all(4 if foc else 0)
						cd["style"].bg_color = Color(0.2, 0.19, 0.28) if foc else Color(0.14, 0.13, 0.2)
					else:
						cd["cell"].visible = false
				var focused_id: String = lst[clampi(s["focus"], 0, lst.size() - 1)] if lst.size() > 0 else ""
				var rec: Dictionary = racers.get(focused_id, {})
				q["name"].text = (("* " if s["fav"].has(focused_id) else "") + String(rec.get("name", ""))).to_upper()
				if focused_id != "" and locked(focused_id):
					q["name"].text += "   [LOCKED]"
				var extras := ""
				if int(s["filter"]) > 0:
					extras += "   filter: " + FILTERS[int(s["filter"])]
				if int(s["sort"]) > 0:
					extras += "   sort: " + SORTS[int(s["sort"])]
				if String(s["notice"]) != "":
					q["sub"].text = String(s["notice"]) + "\nA choose   B back   9 filter   8 sort   / search"
				elif lst.is_empty():
					q["sub"].text = "nothing matches%s\nB clears the search   9 filter   8 sort" % extras
				else:
					q["sub"].text = "%s   %s%s\nA choose   B back   bumpers page   Y favorite   9 filter   8 sort   / search" % [String(c["name"]), String(rec.get("driving_class", "")), extras]
			"variant", "ready":
				var rec: Dictionary = racers.get(s["racer"], {})
				var vars: Array = rec.get("variants", [])
				var vi: int = clampi(s["variant"], 0, maxi(0, vars.size() - 1))
				var v: Dictionary = vars[vi] if vars.size() > 0 else {"unit": rec.get("unit", ""), "name": rec.get("name", "")}
				_show_preview(seat, String(v["unit"]))
				q["name"].text = (("* " if s["fav"].has(s["racer"]) else "") + String(v["name"])).to_upper()
				var st := "Speed %d   Weight %d\n%s" % [int(rec.get("speed", 5)), int(rec.get("weight", 5)), String(rec.get("driving_class", ""))]
				if String(rec.get("kind", "")) == "monster":
					st += "\nraces with its own attack, no action bar"
				q["info"].text = st
				if s["state"] == "variant":
					q["state"].text = "CHOOSE A VARIANT" if vars.size() > 1 else "CONFIRM"
					q["sub"].text = ("VARIANT %d / %d   left/right" % [vi + 1, vars.size()]) if vars.size() > 1 else ("left/right reroll" if bool(s.get("from_random", false)) else "no variants")
					q["sub"].text += "   A ready   B back   Y favorite"
				else:
					q["state"].text = "READY  -  B TO CHANGE"
					q["sub"].text = ("VARIANT %d / %d" % [vi + 1, vars.size()]) if vars.size() > 1 else ""
				if String(s["notice"]) != "":
					q["sub"].text = String(s["notice"]) + "\n" + q["sub"].text
	if joined == 0:
		_heading.text = "CHOOSE YOUR RACER"
		_prompt.text = "press A on a keyboard side (WASD / arrows) or a gamepad to join.   Esc back"
	elif all_ready():
		_heading.text = "START RACE"
		_prompt.text = "everyone is ready: P%d press A to pick a course.   B changes your racer" % (_first_seat() + 1)
	else:
		_heading.text = "CHOOSE YOUR RACER   (%d joined)" % joined
		_prompt.text = "d-pad or stick moves   A select   B back   bumpers page   Y favorite   Esc back      twins allowed: a twin gets the next variant"


# --select_demo=browse,variant,ready,unjoined: seat states for a screenshot
func _apply_demo() -> void:
	var states := demo.split(",")
	for seat in mini(states.size(), seats.size()):
		var st := String(states[seat])
		if st == "unjoined":
			continue
		join(seat)
		seats[seat]["col"] = _col_index(["mutantfolk", "beasts", "robots", "castes"][seat % 4])
		if st == "collection":
			continue
		_open_collection(seat)
		seats[seat]["focus"] = (seat * 7) % maxi(1, seats[seat]["list"].size())
		while seats[seat]["focus"] < seats[seat]["list"].size() - 1 and locked(seats[seat]["list"][seats[seat]["focus"]]):
			seats[seat]["focus"] += 1          # the demo shows a racer that can be chosen
		seats[seat]["page"] = seats[seat]["focus"] / PAGE
		if st == "browse":
			continue
		_choose(seat)
		if st == "variant":
			continue
		_ready_up(seat)


# --select_keys=seat:action,...  actions: join a b left right up down next prev fav filter
# sort random all type:<text> — one DriveFrame each, so the script drives the real handler.
func _apply_keys(script: String) -> void:
	for step in script.split(","):
		var parts := step.split(":", true, 1)
		if parts.size() < 2:
			continue
		var seat := int(parts[0])
		var act := String(parts[1])
		var f := DriveFrame.new()
		match act:
			"join", "a":
				f.confirm_pressed = true
			"b":
				f.back_pressed = true
			"left":
				f.steer = -1.0
			"right":
				f.steer = 1.0
			"up":
				f.throttle = 1.0
			"down":
				f.throttle = -1.0
			"next":
				f.next_pressed = true
			"prev":
				f.prev_pressed = true
			"fav":
				f.slot = 9
			"filter":
				f.slot = FILTER_SLOT
			"sort":
				f.slot = SORT_SLOT
			"random":
				seats[seat]["col"] = _col_index("random")
				continue
			"all":
				seats[seat]["col"] = _col_index("all")
				continue
			_:
				if act.begins_with("type"):
					_search_set(seat, act.substr(5))
				continue
		handle(seat, f)
		handle(seat, DriveFrame.new())      # release, so the next edge counts

