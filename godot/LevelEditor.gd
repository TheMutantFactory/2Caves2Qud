# The level editor (docs/level-editor.md): an overlay over a course in free drive for devs
# and testers to improve a level quickly and save what they did.
#
# Left: a TREE of the course's sprites by source (Qud zone, scatter, placed by hand) and
# blueprint, with counts. Middle: the settings of the selected blueprint — hidden, display
# (vertical billboard / flat on the floor / on the road / off the road / voxel wall / water
# cell), scale, lift, alpha, palette tint, drop shadow, animate, solid (karts collide), and
# for scatter kinds density and the band of distances from the curb. Course settings: the
# floor mode and where the Qud zone stands (at, side, gap). Instances: click a sprite in
# the world to select it, then hide it, nudge it, move it to the next click, or place a new
# one of the selected blueprint where you click. Every change rebuilds the dressing live;
# SAVE writes shared/levels/<key>.json to the repo and the store, and the race reads it.
#
# --editor opens it (Race); --level_edit="Name:prop=value;..." applies settings from the
# command line and --level_save saves, for tests.
class_name LevelEditor
extends CanvasLayer

var track: Track
var race: Node3D
var tree: Tree
var props: VBoxContainer
var status: Label
var selected_name := ""
var selected_id := ""
var mode := ""                      # "" | "move" | "place"
var controls := {}                  # prop -> Control
var panel: PanelContainer


func _init(p_track: Track, p_race: Node3D) -> void:
	track = p_track
	race = p_race
	layer = 20


func _ready() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(1920 - 470, 10)
	panel.size = Vector2(460, 1060)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.92)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var title := _label("LEVEL EDITOR  " + track.key, 22, Color(1.0, 0.93, 0.35))
	vb.add_child(title)
	status = _label("click a sprite in the world, or a blueprint in the tree", 13, Color(0.7, 0.7, 0.7))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(status)
	var row := HBoxContainer.new()
	vb.add_child(row)
	row.add_child(_button("SAVE", func(): save()))
	row.add_child(_button("RELOAD", func(): reload()))
	row.add_child(_button("RESET KIND", func(): reset_kind()))
	row.add_child(_button("CLOSE", func(): panel.visible = false))
	tree = Tree.new()
	tree.custom_minimum_size = Vector2(0, 360)
	tree.hide_root = true
	tree.item_selected.connect(_on_tree_select)
	vb.add_child(tree)
	props = VBoxContainer.new()
	props.add_theme_constant_override("separation", 2)
	vb.add_child(props)
	_build_tree()
	_build_props()
	_build_course()


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", QUD.font())
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(fn)
	return b


# ---------------------------------------------------------------- the tree

func _build_tree() -> void:
	tree.clear()
	var root := tree.create_item()
	var by_source := {}
	for it in track.dressing_items:
		var src := String(it["source"])
		if not by_source.has(src):
			by_source[src] = {}
		var nm := String(it["name"])
		by_source[src][nm] = int(by_source[src].get(nm, 0)) + 1
	var hidden_ids: Array = track.level_overrides.get("hidden", [])
	for src in by_source.keys():
		var si := tree.create_item(root)
		si.set_text(0, "%s  (%d)" % [src, by_source[src].values().reduce(func(a, b): return a + b, 0)])
		si.set_selectable(0, false)
		var names: Array = by_source[src].keys()
		names.sort()
		for nm in names:
			var ks := track.kind_settings(nm)
			var ti := tree.create_item(si)
			var flags := ""
			if bool(ks.get("hidden", false)):
				flags += " [hidden]"
			elif ks.has("display"):
				flags += " [%s]" % String(ks["display"])
			ti.set_text(0, "%s  x%d%s" % [nm, by_source[src][nm], flags])
			ti.set_metadata(0, nm)
	if not hidden_ids.is_empty():
		var hi := tree.create_item(root)
		hi.set_text(0, "hidden instances  (%d)" % hidden_ids.size())
		hi.set_selectable(0, false)


func _on_tree_select() -> void:
	var item := tree.get_selected()
	if item == null or item.get_metadata(0) == null:
		return
	selected_name = String(item.get_metadata(0))
	selected_id = ""
	mode = ""
	_refresh_props()
	status.text = "%s: change a setting (applies live), click PLACE then the ground to add one" % selected_name


# ---------------------------------------------------------------- the settings

func _build_props() -> void:
	for c in props.get_children():
		c.queue_free()
	controls.clear()
	props.add_child(_label("BLUEPRINT", 16, Color(1.0, 0.93, 0.35)))
	var cb := CheckBox.new()
	cb.text = "hidden"
	cb.toggled.connect(func(v): _set_prop("hidden", v))
	props.add_child(cb)
	controls["hidden"] = cb
	var ob := OptionButton.new()
	for d in Track.DISPLAYS:
		ob.add_item(d)
	ob.item_selected.connect(func(i): _set_prop("display", Track.DISPLAYS[i]))
	props.add_child(_row("display", ob))
	controls["display"] = ob
	controls["scale"] = _slider("scale", 0.25, 3.0, 0.05, 1.0)
	controls["lift"] = _slider("lift px", 0.0, 150.0, 1.0, 0.0, "lift")
	controls["alpha"] = _slider("alpha", 0.1, 1.0, 0.05, 1.0)
	var tint := OptionButton.new()
	tint.add_item("no tint")
	for k in Track.PALETTE.keys():
		tint.add_item(k)
	tint.item_selected.connect(func(i): _set_prop("tint", "" if i == 0 else Track.PALETTE.keys()[i - 1]))
	props.add_child(_row("tint", tint))
	controls["tint"] = tint
	for flag in [["shadow", "drop shadow"], ["animate", "animate (unit strips)"], ["solid", "solid: karts collide"]]:
		var fb := CheckBox.new()
		fb.text = flag[1]
		fb.toggled.connect(func(v, k = flag[0]): _set_prop(k, v))
		props.add_child(fb)
		controls[flag[0]] = fb
	props.add_child(_label("SCATTER (this blueprint's scatter entries)", 13, Color(0.7, 0.7, 0.7)))
	controls["density"] = _slider("density x", 0.0, 3.0, 0.1, 1.0)
	controls["band_min"] = _slider("band min px", 0.0, 1500.0, 10.0, 70.0)
	controls["band_max"] = _slider("band max px", 50.0, 3000.0, 10.0, 1500.0)
	props.add_child(_label("INSTANCE", 16, Color(1.0, 0.93, 0.35)))
	var irow := HBoxContainer.new()
	irow.add_child(_button("HIDE", func(): hide_instance()))
	irow.add_child(_button("MOVE", func(): _arm("move")))
	irow.add_child(_button("PLACE", func(): _arm("place")))
	props.add_child(irow)
	var nrow := HBoxContainer.new()
	for n in [["W", Vector2(0, -20)], ["A", Vector2(-20, 0)], ["S", Vector2(0, 20)], ["D", Vector2(20, 0)]]:
		nrow.add_child(_button("nudge " + n[0], func(dv = n[1]): nudge(dv)))
	props.add_child(nrow)


func _row(text: String, c: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := _label(text, 14)
	l.custom_minimum_size = Vector2(110, 0)
	h.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(c)
	return h


func _slider(text: String, lo: float, hi: float, step: float, dflt: float, prop := "") -> HSlider:
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = dflt
	var key := prop if prop != "" else text.split(" ")[0]
	sl.value_changed.connect(func(v): _set_prop(key, v))
	props.add_child(_row(text, sl))
	return sl


func _refresh_props() -> void:
	var ks := track.kind_settings(selected_name)
	_updating = true
	(controls["hidden"] as CheckBox).button_pressed = bool(ks.get("hidden", false))
	var disp := String(ks.get("display", "billboard"))
	(controls["display"] as OptionButton).select(maxi(0, Track.DISPLAYS.find(disp)))
	(controls["scale"] as HSlider).value = float(ks.get("scale", 1.0))
	(controls["lift"] as HSlider).value = float(ks.get("lift", 0.0))
	(controls["alpha"] as HSlider).value = float(ks.get("alpha", 1.0))
	var tint := String(ks.get("tint", ""))
	(controls["tint"] as OptionButton).select(0 if tint == "" else Track.PALETTE.keys().find(tint) + 1)
	for flag in ["shadow", "animate", "solid"]:
		(controls[flag] as CheckBox).button_pressed = bool(ks.get(flag, flag == "animate"))
	(controls["density"] as HSlider).value = float(ks.get("density", 1.0))
	(controls["band_min"] as HSlider).value = float(ks.get("band_min", 70.0))
	(controls["band_max"] as HSlider).value = float(ks.get("band_max", 1500.0))
	_updating = false


var _updating := false


func _set_prop(prop: String, value) -> void:
	if _updating or selected_name == "":
		return
	set_kind(selected_name, prop, value)


func set_kind(name: String, prop: String, value) -> void:
	var kinds: Dictionary = track.level_overrides.get("kinds", {})
	var ks: Dictionary = kinds.get(name, {})
	ks[prop] = value
	kinds[name] = ks
	track.level_overrides["kinds"] = kinds
	_apply(prop in ["density", "band_min", "band_max"])


func reset_kind() -> void:
	if selected_name == "":
		return
	(track.level_overrides.get("kinds", {}) as Dictionary).erase(selected_name)
	_apply(true)
	_refresh_props()


func _apply(recollect := false) -> void:
	if recollect:
		track._collect_dressing()
	track.rebuild_dressing()
	_build_tree()
	var st: Dictionary = track.dressing_stats
	status.text = "%d items: %d sprites, %d walls, %d water, %d hidden, %d under the road, %d solid" % [
		st["items"], st["sprites"], st["walls"], st["liquids"], st["hidden"], st["on_road"], st["solid"]]


# ---------------------------------------------------------------- the course

func _build_course() -> void:
	var box := VBoxContainer.new()
	props.add_child(box)
	box.add_child(_label("COURSE", 16, Color(1.0, 0.93, 0.35)))
	var fm := OptionButton.new()
	fm.add_item("tiled ground")
	fm.add_item("qud floor (dots and grasses)")
	fm.select(1 if String(track.spec.get("floor_mode", "")) == "qud" else 0)
	fm.item_selected.connect(func(i): _course_set("floor_mode", "qud" if i == 1 else "tiled"); track.rebuild_ground("qud" if i == 1 else ""))
	box.add_child(_row("floor", fm))
	var zone := {}
	for e in track.spec.get("dressing", []):
		if e.has("zone"):
			zone = e
			break
	if not zone.is_empty():
		var zo: Dictionary = (track.level_overrides.get("course", {}) as Dictionary).get("zone", {})
		for f in [["at", 0.0, 1.0, 0.005, float(zone.get("at", 0.0))], ["side", -1.0, 1.0, 2.0, float(zone.get("side", 1.0))], ["gap", 0.0, 1200.0, 10.0, float(zone.get("gap", 140.0))]]:
			var sl := HSlider.new()
			sl.min_value = f[1]
			sl.max_value = f[2]
			sl.step = f[3]
			sl.value = float(zo.get(f[0], f[4]))
			sl.value_changed.connect(func(v, k = f[0]): _zone_set(k, v))
			box.add_child(_row("zone " + String(f[0]), sl))


func _course_set(prop: String, value) -> void:
	var c: Dictionary = track.level_overrides.get("course", {})
	c[prop] = value
	track.level_overrides["course"] = c


func _zone_set(prop: String, value: float) -> void:
	var c: Dictionary = track.level_overrides.get("course", {})
	var z: Dictionary = c.get("zone", {})
	z[prop] = value
	c["zone"] = z
	track.level_overrides["course"] = c
	_apply(true)


# ---------------------------------------------------------------- instances

func _arm(m: String) -> void:
	mode = m
	if m == "move" and selected_id == "":
		status.text = "select an instance first (click it in the world)"
		mode = ""
	elif m == "place" and selected_name == "":
		status.text = "select a blueprint in the tree first"
		mode = ""
	else:
		status.text = ("click the ground to move %s there" % selected_id) if m == "move" else ("click the ground to place a %s" % selected_name)


func hide_instance() -> void:
	if selected_id == "":
		return
	var hidden: Array = track.level_overrides.get("hidden", [])
	if not hidden.has(selected_id):
		hidden.append(selected_id)
	track.level_overrides["hidden"] = hidden
	selected_id = ""
	_apply()


func nudge(dv: Vector2) -> void:
	if selected_id == "":
		return
	var cur := _instance_pos(selected_id) + dv * track.scale_k * 0.5
	_move_to(selected_id, cur)


func _instance_pos(id: String) -> Vector2:
	var moves: Dictionary = track.level_overrides.get("moves", {})
	if moves.has(id):
		return Vector2(float(moves[id][0]), float(moves[id][1]))
	for it in track.dressing_items:
		if String(it["id"]) == id:
			return it["pos"]
	return Vector2.ZERO


func _move_to(id: String, p: Vector2) -> void:
	var moves: Dictionary = track.level_overrides.get("moves", {})
	moves[id] = [p.x, p.y]
	track.level_overrides["moves"] = moves
	_apply()


func place_extra(name: String, p: Vector2) -> void:
	var extras: Array = track.level_overrides.get("extras", [])
	extras.append({"name": name, "x": p.x, "y": p.y})
	track.level_overrides["extras"] = extras
	_apply(true)


func _unhandled_input(event: InputEvent) -> void:
	if not panel.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
			panel.visible = true
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		panel.visible = false
		return
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mp: Vector2 = event.position
	if panel.get_global_rect().has_point(mp):
		return
	if mode == "move" or mode == "place":
		var ground := _ground_point(cam, mp)
		if mode == "move":
			_move_to(selected_id, ground)
		else:
			place_extra(selected_name, ground)
		mode = ""
		get_viewport().set_input_as_handled()
		return
	# pick the nearest dressing node on screen
	var best := ""
	var best_d := 28.0
	for id in track.dressing_nodes.keys():
		var node: Node3D = track.dressing_nodes[id]
		if not is_instance_valid(node) or cam.is_position_behind(node.global_position):
			continue
		var sp := cam.unproject_position(node.global_position)
		var dd := sp.distance_to(mp)
		if dd < best_d:
			best_d = dd
			best = String(id)
	if best != "":
		selected_id = best
		for it in track.dressing_items:
			if String(it["id"]) == best:
				selected_name = String(it["name"])
				_refresh_props()
				break
		status.text = "instance %s  (%s)" % [best, selected_name]
		get_viewport().set_input_as_handled()


# Where a click lands on the ground: the camera ray against the plane at the wizard's height.
func _ground_point(cam: Camera3D, mp: Vector2) -> Vector2:
	var origin := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var player_y := 0.0
	if "player" in race and race.player != null:
		player_y = race.player.position.y
	if absf(dir.y) < 0.0001:
		return Vector2.ZERO
	var k := (player_y - origin.y) / dir.y
	var hit := origin + dir * maxf(0.0, k)
	return Vector2(hit.x, hit.z) / Track.U


# ---------------------------------------------------------------- save / load / CLI

func _paths() -> Array:
	var repo := ProjectSettings.globalize_path("res://").path_join("../shared/levels")
	var store := ProjectSettings.globalize_path(QUD.ROOT + "shared/levels")
	return [repo, store]


func save() -> void:
	var text := JSON.stringify(track.level_overrides, "  ")
	var wrote := []
	for dir in _paths():
		DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(dir.path_join(track.key + ".json"), FileAccess.WRITE)
		if f != null:
			f.store_string(text + "\n")
			wrote.append(dir)
	status.text = "saved shared/levels/%s.json (%d copies)" % [track.key, wrote.size()]
	print("editor: saved %s -> %s" % [track.key, ", ".join(wrote)])


func reload() -> void:
	track.load_level_overrides()
	_apply(true)
	_refresh_props()


# --level_edit="Name:prop=value;Name:prop=value"  (value: true/false, a number, or a word)
func apply_cli(script: String) -> void:
	for part in script.split(";"):
		var nm_rest := part.split(":", true, 1)
		if nm_rest.size() < 2:
			continue
		var kv := String(nm_rest[1]).split("=", true, 1)
		if kv.size() < 2:
			continue
		var v: Variant = kv[1]
		if kv[1] == "true" or kv[1] == "false":
			v = kv[1] == "true"
		elif kv[1].is_valid_float():
			v = kv[1].to_float()
		selected_name = String(nm_rest[0])
		set_kind(selected_name, kv[0], v)
		print("editor: %s %s=%s" % [selected_name, kv[0], str(v)])
