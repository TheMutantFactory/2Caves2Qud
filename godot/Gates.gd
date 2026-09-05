# Rift gate selection after a realm: three cards, pick one with a click or 1-3.
class_name Gates
extends CanvasLayer

signal picked(gate: Dictionary)

var options: Array = []
var cards: Array = []


func _font(l: Control, size: int, color := Color.WHITE) -> void:
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	_font(l, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func setup(p_options: Array, result_text: String) -> void:
	layer = 20
	options = p_options
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.size = Vector2(1920, 1080)
	add_child(dim)

	var title := _label("CHOOSE A RIFT", 60, Color(1.0, 0.93, 0.35))
	title.position = Vector2(0, 60)
	title.size = Vector2(1920, 80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var res := _label(result_text, 22, Color(0.85, 0.85, 0.85))
	res.position = Vector2(160, 140)
	res.size = Vector2(1600, 80)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(res)

	var colors := {"brick": Color(0.36, 0.33, 0.3), "volcano": Color(0.45, 0.2, 0.16), "ice": Color(0.2, 0.32, 0.45)}
	for i in options.size():
		var g: Dictionary = options[i]
		var card := PanelContainer.new()
		card.position = Vector2(180 + i * 540, 250)
		card.size = Vector2(500, 620)
		var bg := StyleBoxFlat.new()
		bg.bg_color = colors.get(g["track"], Color(0.25, 0.25, 0.3))
		bg.border_color = Color(0.9, 0.85, 0.75)
		bg.set_border_width_all(4)
		bg.set_corner_radius_all(16)
		bg.set_content_margin_all(24)
		card.add_theme_stylebox_override("panel", bg)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 14)
		card.add_child(vb)
		vb.add_child(_label("%d" % (i + 1), 40, Color(1.0, 0.93, 0.35)))
		var track_name: String = String(g.get("label", Shared.tracks.get(g["track"], {}).get("name", g["track"])))
		vb.add_child(_label("Realm %d" % (Campaign.level + 1), 26, Color(0.85, 0.85, 0.85)))
		vb.add_child(_label(track_name, 34))
		vb.add_child(_label("Reward: %s" % g["reward"]["label"], 24, Color(0.6, 0.95, 0.6)))
		vb.add_child(_label("Monsters seen through the rift:", 20, Color(0.8, 0.8, 0.8)))
		for m in g["preview"]:
			vb.add_child(_label("  %s" % m, 22))
		var btn := Button.new()
		btn.text = "ENTER"
		_font(btn, 28)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func(): picked.emit(g))
		vb.add_child(btn)
		add_child(card)
		cards.append(card)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		var idx := -1
		if k == KEY_1:
			idx = 0
		elif k == KEY_2:
			idx = 1
		elif k == KEY_3:
			idx = 2
		if idx >= 0 and idx < options.size():
			picked.emit(options[idx])
			get_viewport().set_input_as_handled()
