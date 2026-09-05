# A three-card chooser (level-ups, and anything else that wants cards).
# options: [{title, lines: [String], icon: Texture2D, color: Color}]
class_name Choice
extends CanvasLayer

signal picked(index: int)

var options: Array = []


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


func setup(title: String, subtitle: String, p_options: Array) -> void:
	layer = 20
	options = p_options
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.size = Vector2(1920, 1080)
	add_child(dim)
	var t := _label(title, 56, Color(1.0, 0.93, 0.35))
	t.position = Vector2(0, 70)
	t.size = Vector2(1920, 70)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(t)
	var st := _label(subtitle, 22, Color(0.85, 0.85, 0.85))
	st.position = Vector2(160, 140)
	st.size = Vector2(1600, 60)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(st)
	var n := options.size()
	var gap := 32
	var card_w := mini(480, int((1920 - 120 - (n - 1) * gap) / maxi(1, n)))   # four or five cards still fit
	var x0 := (1920 - (n * card_w + (n - 1) * gap)) / 2
	for i in n:
		var o: Dictionary = options[i]
		var card := PanelContainer.new()
		card.position = Vector2(x0 + i * (card_w + gap), 240)
		card.size = Vector2(card_w, 620)
		var bg := StyleBoxFlat.new()
		bg.bg_color = o.get("color", Color(0.2, 0.18, 0.28))
		bg.border_color = Color(0.9, 0.85, 0.75)
		bg.set_border_width_all(4)
		bg.set_corner_radius_all(16)
		bg.set_content_margin_all(24)
		card.add_theme_stylebox_override("panel", bg)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 12)
		card.add_child(vb)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 16)
		vb.add_child(head)
		head.add_child(_label("%d" % (i + 1), 40, Color(1.0, 0.93, 0.35)))
		if o.get("icon") != null:
			var tr := TextureRect.new()
			tr.texture = o["icon"]
			tr.custom_minimum_size = Vector2(72, 72)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			head.add_child(tr)
		vb.add_child(_label(String(o.get("title", "")), 32))
		for line in o.get("lines", []):
			vb.add_child(_label(String(line), 20, Color(0.88, 0.88, 0.88)))
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_child(spacer)
		var btn := Button.new()
		btn.text = "TAKE"
		_font(btn, 26)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func(): picked.emit(i))
		vb.add_child(btn)
		add_child(card)


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
			picked.emit(idx)
			get_viewport().set_input_as_handled()
