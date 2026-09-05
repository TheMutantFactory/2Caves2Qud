# Test-rig spell picker: search the game's spells and drop one straight into an
# action-bar slot, no spell points involved. L in the rig; 1-0 choose the slot.
class_name SpellPicker
extends CanvasLayer

signal closed
signal picked(spell: Dictionary, slot: int)

const DIGITS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]

var search: LineEdit
var grid: GridContainer
var lbl_slot: Label
var target_slot := 0
var matches: Array = []


func _font(l: Control, size: int, color := Color.WHITE) -> void:
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)


func _ready() -> void:
	layer = 25
	target_slot = mini(Campaign.spells.size(), Campaign.MAX_SLOTS - 1)
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.08, 0.94)
	dim.size = Vector2(1920, 1080)
	add_child(dim)
	var title := Label.new()
	title.text = "SPELL PICKER"
	_font(title, 48, Color(1.0, 0.93, 0.35))
	title.position = Vector2(60, 20)
	add_child(title)
	var hint := Label.new()
	hint.text = "type to search a name or tag    1-0 choose the slot    Enter takes the first match    click takes one    Esc back"
	_font(hint, 20, Color(0.75, 0.75, 0.75))
	hint.position = Vector2(60, 80)
	add_child(hint)

	search = LineEdit.new()
	search.placeholder_text = "search"
	search.position = Vector2(60, 118)
	search.size = Vector2(640, 46)
	_font(search, 26)
	search.text_changed.connect(func(_t): _refresh())
	search.text_submitted.connect(func(_t):
		if matches.size() > 0:
			_take(matches[0]))
	add_child(search)
	lbl_slot = Label.new()
	_font(lbl_slot, 24, Color(0.55, 0.85, 1.0))
	lbl_slot.position = Vector2(730, 126)
	add_child(lbl_slot)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60, 184)
	scroll.size = Vector2(1800, 860)
	add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	_refresh()
	search.call_deferred("grab_focus")


func _tags(s: Dictionary) -> String:
	var out := ""
	for t in s.get("tags", []):
		out += String(t).to_lower() + " "
	return out


func _refresh() -> void:
	for c in grid.get_children():
		c.queue_free()
	var q := search.text.strip_edges().to_lower()
	matches = []
	for s in SpellDB.spells:
		if q == "" or String(s["name"]).to_lower().contains(q) or _tags(s).contains(q):
			matches.append(s)
	_refresh_slot()
	for s in matches:
		var b := Button.new()
		b.custom_minimum_size = Vector2(290, 78)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _take(s))
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_theme_constant_override("separation", 10)
		var tr := TextureRect.new()
		tr.texture = SpellDB.icon(s)
		tr.custom_minimum_size = Vector2(64, 64)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tr)
		var vb := VBoxContainer.new()
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		var l := Label.new()
		l.text = String(s["name"])
		_font(l, 19)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(l)
		var e: Dictionary = SpellDB.effect_for(s)
		var l2 := Label.new()
		l2.text = "L%d  %s  %s" % [int(s.get("level", 1)), SpellDB.kind_verb(String(e["kind"])), String(e.get("dtype", ""))]
		_font(l2, 15, Color(0.7, 0.7, 0.7))
		l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(l2)
		hb.add_child(vb)
		b.add_child(hb)
		grid.add_child(b)


func _refresh_slot() -> void:
	var what := "empty"
	if target_slot < Campaign.spells.size():
		what = "replaces %s" % String(Campaign.spells[target_slot]["name"])
	lbl_slot.text = "into slot %d (%s)      %d spells" % [(target_slot + 1) % 10, what, matches.size()]


func _take(s: Dictionary) -> void:
	picked.emit(s, target_slot)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		var i := DIGITS.find(k)
		if i >= 0:
			target_slot = i
			_refresh_slot()
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE:
			closed.emit()
			get_viewport().set_input_as_handled()
