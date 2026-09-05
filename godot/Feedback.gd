# The feedback panel: a list of the things in the game right now, a live showcase of the
# selected one doing what it does, and a box to say what you think. Entries append to
# user://feedback.jsonl, one JSON object per line, in the shape a later upload (the
# Cloudflare hookup) will send as-is. See docs/feedback.md.
class_name FeedbackPanel
extends CanvasLayer

signal closed

const FILE := "user://feedback.jsonl"
const SW := 1920.0
const SH := 1080.0

var objects: Array = []
var context: Dictionary = {}
var realm := 1
var tileset := "stone"
var list: ItemList
var text: TextEdit
var showcase: Showcase
var status: Label
var detail: Label
var selected := -1
var initial_pick := -1


func setup(p_objects: Array, p_context: Dictionary, p_realm: int, p_tileset: String, pick := -1) -> void:
	objects = p_objects
	context = p_context
	realm = p_realm
	tileset = p_tileset
	initial_pick = pick


func _label(txt: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _ready() -> void:
	layer = 60
	var root := Control.new()
	root.size = Vector2(SW, SH)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.94)
	dim.size = Vector2(SW, SH)
	root.add_child(dim)
	var title := _label("FEEDBACK", 52, Color(1.0, 0.93, 0.35))
	title.position = Vector2(60, 24)
	root.add_child(title)
	var hint := _label("pick a thing (or leave the first line selected for general notes), watch it act, write what you think.   ctrl+enter sends   esc back", 18, Color(0.7, 0.7, 0.7))
	hint.position = Vector2(60, 90)
	root.add_child(hint)

	list = ItemList.new()
	list.position = Vector2(60, 130)
	list.size = Vector2(560, 620)
	list.add_theme_font_override("font", QUD.font())
	list.add_theme_font_size_override("font_size", 20)
	list.add_item("no object: general feedback")
	for o in objects:
		list.add_item("%s   %s" % [String(o.get("kind", "")), String(o.get("name", ""))])
		var icon: Texture2D = null
		if o.has("icon"):
			icon = QUD.icon(String(o["icon"]))
		list.set_item_metadata(list.item_count - 1, o)
	list.item_selected.connect(_select)
	root.add_child(list)

	var svc := SubViewportContainer.new()
	svc.position = Vector2(660, 130)
	svc.size = Vector2(Showcase.BW, Showcase.BH)
	svc.scale = Vector2(1.5, 1.5)   # the box renders at its own size and is blown up whole
	root.add_child(svc)
	var sv := SubViewport.new()
	sv.size = Vector2i(int(Showcase.BW), int(Showcase.BH))
	sv.handle_input_locally = false
	svc.add_child(sv)
	showcase = Showcase.new()
	sv.add_child(showcase)
	var frame := ReferenceRect.new()
	frame.editor_only = false
	frame.border_color = Color(0.4, 0.4, 0.5)
	frame.position = svc.position
	frame.size = svc.size * 1.5
	root.add_child(frame)

	detail = _label("", 18, Color(0.85, 0.85, 0.85))
	detail.position = Vector2(60, 762)
	detail.size = Vector2(1800, 30)
	root.add_child(detail)

	text = TextEdit.new()
	text.position = Vector2(60, 800)
	text.size = Vector2(1800, 170)
	text.add_theme_font_override("font", QUD.font())
	text.add_theme_font_size_override("font_size", 20)
	text.placeholder_text = "what worked, what did not, what you expected..."
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	root.add_child(text)

	var send := Button.new()
	send.text = "SEND   (ctrl+enter)"
	send.add_theme_font_override("font", QUD.font())
	send.add_theme_font_size_override("font_size", 24)
	send.position = Vector2(60, 985)
	send.size = Vector2(360, 56)
	send.pressed.connect(_send)
	root.add_child(send)
	var back := Button.new()
	back.text = "BACK   (esc)"
	back.add_theme_font_override("font", QUD.font())
	back.add_theme_font_size_override("font_size", 24)
	back.position = Vector2(440, 985)
	back.size = Vector2(300, 56)
	back.pressed.connect(func(): closed.emit())
	root.add_child(back)
	status = _label("", 20, Color(0.55, 0.85, 1.0))
	status.position = Vector2(770, 998)
	root.add_child(status)

	var pick := clampi(initial_pick + 1, 0, list.item_count - 1)
	list.select(pick)
	_select(pick)
	text.call_deferred("grab_focus")


func _select(i: int) -> void:
	selected = i - 1
	if i <= 0:
		showcase.show_object({"kind": "thing", "name": "General", "text": "General feedback about Rift-Type, realm %d." % realm, "unit": Campaign.skin}, realm, tileset)
		detail.text = "general feedback"
		return
	var o: Dictionary = objects[selected]
	showcase.show_object(o, realm, tileset)
	detail.text = String(o.get("text", "")).get_slice("\n", 0)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			closed.emit()
			get_viewport().set_input_as_handled()
		elif (event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER) and event.ctrl_pressed:
			_send()
			get_viewport().set_input_as_handled()


func _send() -> void:
	var body := text.text.strip_edges()
	if body == "":
		status.text = "write something first"
		return
	var obj: Variant = null
	if selected >= 0:
		var o: Dictionary = objects[selected]
		obj = {"kind": o.get("kind", ""), "name": o.get("name", ""), "unit": o.get("unit", "")}
	var entry := {
		"time": Time.get_datetime_string_from_system(true),
		"game": "drift-wizard-3",
		"version": ProjectSettings.get_setting("application/config/version", ""),
		"object": obj,
		"text": body,
		"context": context,
	}
	var err := save(entry)
	if err == OK:
		status.text = "saved to %s   (%d entries)" % [ProjectSettings.globalize_path(FILE), count()]
		text.text = ""
		Audio.play("learn_spell", -6.0)
	else:
		status.text = "could not write %s (error %d)" % [FILE, err]


static func save(entry: Dictionary) -> int:
	var f := FileAccess.open(FILE, FileAccess.READ_WRITE) if FileAccess.file_exists(FILE) else FileAccess.open(FILE, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.seek_end()
	f.store_line(JSON.stringify(entry))
	f.close()
	return OK


static func count() -> int:
	if not FileAccess.file_exists(FILE):
		return 0
	var f := FileAccess.open(FILE, FileAccess.READ)
	var n := 0
	while not f.eof_reached():
		if f.get_line().strip_edges() != "":
			n += 1
	return n
