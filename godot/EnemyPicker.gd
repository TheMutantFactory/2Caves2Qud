# Test-rig enemy picker: see the archetype NPCs on the track, remove them, and add
# new ones by archetype, gap, lane and monster. N in the rig.
class_name EnemyPicker
extends CanvasLayer

signal closed
signal add_requested(kind: String, dist: float, lat: float, unit: String, name: String)
signal remove_requested(kart: Kart)
signal clear_requested

const KINDS := ["ahead", "behind", "swerve", "beside", "parked"]

var race
var kind := "ahead"
var kind_buttons := {}
var dist_edit: LineEdit
var lat_edit: LineEdit
var search: LineEdit
var grid: GridContainer
var list: VBoxContainer
var lbl_count: Label
var monsters: Array = []


func _font(l: Control, size: int, color := Color.WHITE) -> void:
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)


func _label(text: String, size: int, pos: Vector2, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	_font(l, size, color)
	l.position = pos
	add_child(l)
	return l


func _ready() -> void:
	layer = 25
	for m in QUD.monsters:
		if m.has("error") or not bool(m.get("asset_exists", false)):
			continue
		var asset: Array = m.get("asset", [])
		if asset.size() < 2 or asset[0] != "char" or not QUD.has_unit(asset[1]):
			continue
		monsters.append({"name": m["name"], "unit": asset[1], "hp": float(m.get("max_hp", 10)), "tags": m.get("tags", [])})
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.08, 0.94)
	dim.size = Vector2(1920, 1080)
	add_child(dim)
	_label("ENEMIES", 48, Vector2(60, 20), Color(1.0, 0.93, 0.35))
	_label("left: who is on the track    right: pick an archetype, a gap and a lane, then click a monster to add it    Esc back", 20, Vector2(60, 80), Color(0.75, 0.75, 0.75))

	# ---- left: current NPCs
	_label("ON THE TRACK", 26, Vector2(60, 124), Color(0.55, 0.85, 1.0))
	var clear := Button.new()
	clear.text = "remove all"
	_font(clear, 20)
	clear.position = Vector2(400, 122)
	clear.pressed.connect(func(): clear_requested.emit(); refresh())
	add_child(clear)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60, 170)
	scroll.size = Vector2(620, 880)
	add_child(scroll)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	# ---- right: add
	_label("ADD", 26, Vector2(740, 124), Color(0.55, 0.85, 1.0))
	var x := 740.0
	for k in KINDS:
		var b := Button.new()
		b.text = k
		b.toggle_mode = true
		_font(b, 22)
		b.custom_minimum_size = Vector2(150, 40)
		b.position = Vector2(x, 164)
		b.pressed.connect(func(): _set_kind(k))
		add_child(b)
		kind_buttons[k] = b
		x += 160
	_set_kind("ahead")
	_label("gap px", 20, Vector2(740, 216), Color(0.75, 0.75, 0.75))
	dist_edit = LineEdit.new()
	dist_edit.text = "250"
	_font(dist_edit, 22)
	dist_edit.position = Vector2(830, 210)
	dist_edit.size = Vector2(120, 40)
	add_child(dist_edit)
	_label("lane (-1..1)", 20, Vector2(980, 216), Color(0.75, 0.75, 0.75))
	lat_edit = LineEdit.new()
	lat_edit.text = "0"
	_font(lat_edit, 22)
	lat_edit.position = Vector2(1130, 210)
	lat_edit.size = Vector2(100, 40)
	add_child(lat_edit)
	_label("beside: gap is the side offset in px.  swerve: lane is the amplitude.", 17, Vector2(1250, 218), Color(0.6, 0.6, 0.6))
	search = LineEdit.new()
	search.placeholder_text = "search monsters by name or tag"
	_font(search, 22)
	search.position = Vector2(740, 262)
	search.size = Vector2(700, 40)
	search.text_changed.connect(func(_t): _refresh_monsters())
	add_child(search)
	lbl_count = Label.new()
	_font(lbl_count, 20, Color(0.75, 0.75, 0.75))
	lbl_count.position = Vector2(1460, 268)
	add_child(lbl_count)
	var mscroll := ScrollContainer.new()
	mscroll.position = Vector2(740, 312)
	mscroll.size = Vector2(1120, 738)
	add_child(mscroll)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	mscroll.add_child(grid)
	refresh()
	_refresh_monsters()


func _set_kind(k: String) -> void:
	kind = k
	for name in kind_buttons:
		kind_buttons[name].button_pressed = name == k
		kind_buttons[name].modulate = Color(0.7, 1.0, 0.7) if name == k else Color.WHITE


func refresh() -> void:
	for c in list.get_children():
		c.queue_free()
	if race == null:
		return
	for kart in race.karts:
		if kart.is_player:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := Label.new()
		l.text = "%s   %s   %d HP" % [kart.display_name, kart.unit, int(kart.hp)]
		_font(l, 20)
		l.custom_minimum_size = Vector2(470, 36)
		row.add_child(l)
		var b := Button.new()
		b.text = "remove"
		_font(b, 18)
		b.pressed.connect(func(): remove_requested.emit(kart); refresh())
		row.add_child(b)
		list.add_child(row)
	if list.get_child_count() == 0:
		var l := Label.new()
		l.text = "nobody: the wizard is alone"
		_font(l, 20, Color(0.6, 0.6, 0.6))
		list.add_child(l)


func _refresh_monsters() -> void:
	for c in grid.get_children():
		c.queue_free()
	var q := search.text.strip_edges().to_lower()
	var shown := 0
	var total := 0
	for m in monsters:
		var tags := ""
		for t in m["tags"]:
			tags += String(t).to_lower() + " "
		if q != "" and not String(m["name"]).to_lower().contains(q) and not tags.contains(q):
			continue
		total += 1
		shown += 1
		var b := Button.new()
		b.custom_minimum_size = Vector2(272, 74)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _add(m))
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_theme_constant_override("separation", 8)
		var tr := TextureRect.new()
		tr.texture = Wardrobe.preview(m["unit"])
		tr.custom_minimum_size = Vector2(64, 64)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tr)
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.text = String(m["name"])
		_font(l, 18)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(l)
		var l2 := Label.new()
		l2.text = "%d HP" % int(m["hp"])
		_font(l2, 14, Color(0.7, 0.7, 0.7))
		l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(l2)
		hb.add_child(vb)
		b.add_child(hb)
		grid.add_child(b)
	lbl_count.text = "%d monsters" % total


func _add(m: Dictionary) -> void:
	var dist := float(dist_edit.text) if dist_edit.text.is_valid_float() else 250.0
	var lat := float(lat_edit.text) if lat_edit.text.is_valid_float() else 0.0
	add_requested.emit(kind, dist, lat, String(m["unit"]), String(m["name"]))
	refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
