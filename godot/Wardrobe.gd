# Pick a player outfit from the game's wardrobe sprites (player_*). The choice
# is saved to user://drift.cfg and used by the race, survivors and gauntlet.
#
# As a scene: --mode=wardrobe [--frames=N --screenshot=path]
class_name Wardrobe
extends CanvasLayer

signal closed

var buttons: Array = []
var frames_left := -1
var frame_count := 0
var screenshot_path := ""
var standalone := false
var lbl_current: Label


static func skin_label(unit: String) -> String:
	if unit == "player":
		return "Wizard"
	return unit.trim_prefix("player_").replace("_", " ").capitalize()


# The racer name an outfit gives: "Boar Form Wizard", or plain "Wizard" for the default robes.
static func racer_name(unit: String) -> String:
	var l := skin_label(unit)
	return l if l.ends_with("Wizard") else l + " Wizard"


static func skins() -> Array:
	var out := ["player"]
	var names: Array = QUD.manifest.get("units", {}).keys()
	names.sort()
	for n in names:
		if String(n).begins_with("player_"):
			out.append(String(n))
	return out


static func preview(unit: String) -> Texture2D:
	var tex := QUD.unit_idle(unit)
	if tex == null:
		return null
	var info: Dictionary = QUD.unit_info(unit)
	var fs := int(info.get("frame_size", 60))
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0, 0, fs, fs)
	return at


func _font(l: Control, size: int, color := Color.WHITE) -> void:
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)


func _ready() -> void:
	layer = 25
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			frames_left = int(a.substr(9))
		elif a.begins_with("--screenshot="):
			screenshot_path = a.substr(13)
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.08, 0.96)
	dim.size = Vector2(1920, 1080)
	add_child(dim)
	var title := Label.new()
	title.text = "WARDROBE"
	_font(title, 56, Color(1.0, 0.93, 0.35))
	title.position = Vector2(60, 24)
	add_child(title)
	var hint := Label.new()
	hint.text = "click or arrows + Enter to wear an outfit    Esc back"
	_font(hint, 20, Color(0.75, 0.75, 0.75))
	hint.position = Vector2(60, 90)
	add_child(hint)
	lbl_current = Label.new()
	_font(lbl_current, 26)
	lbl_current.position = Vector2(60, 124)
	add_child(lbl_current)
	_refresh_current()

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60, 170)
	scroll.size = Vector2(1800, 870)
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var first: Button = null
	for unit in skins():
		var b := Button.new()
		b.custom_minimum_size = Vector2(212, 150)
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(func(): _pick(unit))
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tr := TextureRect.new()
		tr.texture = preview(unit)
		tr.custom_minimum_size = Vector2(96, 96)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tr)
		var l := Label.new()
		l.text = skin_label(unit)
		_font(l, 17)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(l)
		b.add_child(vb)
		if unit == Campaign.skin:
			b.modulate = Color(0.7, 1.0, 0.7)
			first = b
		grid.add_child(b)
		buttons.append(b)
	if first == null and buttons.size() > 0:
		first = buttons[0]
	if first != null:
		first.call_deferred("grab_focus")


func _refresh_current() -> void:
	lbl_current.text = "Wearing: %s" % skin_label(Campaign.skin)


func _pick(unit: String) -> void:
	Campaign.set_skin(unit)
	_refresh_current()
	for b in buttons:
		b.modulate = Color.WHITE
	Audio.play("learn_spell", -6.0)
	for i in buttons.size():
		if skins()[i] == unit:
			buttons[i].modulate = Color(0.7, 1.0, 0.7)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		closed.emit()
		get_viewport().set_input_as_handled()


func _process(_dt: float) -> void:
	frame_count += 1
	if frames_left >= 0 and frame_count >= frames_left:
		frames_left = -1
		_finish_screenshot()


func _finish_screenshot() -> void:
	await RenderingServer.frame_post_draw
	if screenshot_path != "":
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		print("saved ", screenshot_path)
	print("wardrobe: %d skins, wearing %s" % [buttons.size(), Campaign.skin])
	get_tree().quit()
