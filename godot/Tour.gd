# The tour (docs/tour.md): the game drives the wizard through every course in cup order, in
# real time, so a person can watch and talk back. SPACE pauses and opens the note box: what
# is typed is saved to reports/tour-feedback.md with the course, the spot (lap or section,
# loop fraction, waypoint), the race time and a screenshot taken the instant of the pause;
# Enter saves and resumes, Esc resumes without saving. N and B jump to the next or previous
# course, T takes the wheel from the auto-driver, A gives it back. A course runs until the
# wizard has done a lap (a section race: finished) or the time cap, then the next loads.
#
# --tour opens it (Race); --tour_start=N begins at that course; --tour_seconds=N caps each.
# --tour_test pauses at 3 s, files a note and moves on, for a headless check.
class_name Tour
extends CanvasLayer

var race: Node3D
var track: Track
var order: Array = []
var index := 0
var cap := 120.0
var strip: Label
var hint: Label
var note_panel: PanelContainer
var note: TextEdit
var note_status: Label
var shot: Image = null
var paused_here := false
var elapsed := 0.0
var done := false
var notes := 0
var test_mode := false


func _init(p_race: Node3D, p_track: Track) -> void:
	race = p_race
	track = p_track
	layer = 15
	order = Shared.track_order.filter(func(k): return k != "chicago_loop")
	index = maxi(0, order.find(track.key))


static func key_for(i: int) -> String:
	var order := Shared.track_order.filter(func(k): return k != "chicago_loop")
	if order.is_empty():
		return "joppa"
	return String(order[clampi(i, 0, order.size() - 1)])


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	strip = _label("", 24, Color(1.0, 0.93, 0.35))
	strip.position = Vector2(0, 150)
	strip.size = Vector2(1920, 34)
	strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(strip)
	hint = _label("SPACE pause + note    N next    B back    T take the wheel    A auto", 18, Color(0.85, 0.85, 0.85))
	hint.position = Vector2(0, 184)
	hint.size = Vector2(1920, 28)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	note_panel = PanelContainer.new()
	note_panel.position = Vector2(460, 300)
	note_panel.size = Vector2(1000, 420)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.94)
	sb.set_corner_radius_all(8)
	note_panel.add_theme_stylebox_override("panel", sb)
	note_panel.visible = false
	add_child(note_panel)
	var vb := VBoxContainer.new()
	note_panel.add_child(vb)
	vb.add_child(_label("PAUSED  -  what do you see?", 26, Color(1.0, 0.93, 0.35)))
	note_status = _label("", 16, Color(0.7, 0.7, 0.7))
	vb.add_child(note_status)
	note = TextEdit.new()
	note.custom_minimum_size = Vector2(980, 260)
	note.add_theme_font_override("font", QUD.font())
	note.add_theme_font_size_override("font_size", 20)
	note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vb.add_child(note)
	vb.add_child(_label("Enter saves the note with a screenshot and resumes    Esc resumes without saving    Shift+Enter for a new line", 15, Color(0.6, 0.6, 0.6)))
	_refresh_strip()
	var args := _args()
	cap = float(args.get("tour_seconds", 120.0))
	test_mode = args.has("tour_test")


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out


func _refresh_strip() -> void:
	var spec: Dictionary = Shared.tracks.get(track.key, {})
	strip.text = "TOUR  %d / %d    %s    %s    %ds left" % [index + 1, order.size(), String(spec.get("name", track.key)), String(spec.get("cup", "")), int(maxf(0.0, cap - elapsed))]


func _process(dt: float) -> void:
	if done or paused_here:
		return
	if race.state == race.RACING:
		elapsed += dt
	_refresh_strip()
	var player = race.player
	var lap_done: bool = player != null and (player.finished or (not track.open and player.lap > 1))
	if (lap_done or elapsed >= cap) and race.state == race.RACING:
		advance(1)
	if test_mode and elapsed >= 3.0 and notes == 0:
		pause_for_note()
		note.text = "tour test note: the road here reads well"
		if _args().has("tour_hold"):
			notes = -1                      # stay paused with the panel up (for a screenshot)
		else:
			save_note()
			advance(1)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if paused_here:
		if event.keycode == KEY_ESCAPE:
			resume()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if not event.shift_pressed:
				save_note()
				get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_SPACE, KEY_P:
			pause_for_note()
		KEY_N:
			advance(1)
		KEY_B:
			advance(-1)
		KEY_T:
			race.auto_player = false
			hint.text = "YOU DRIVE (WASD, shift drift)    A gives the wheel back    SPACE pause + note    N next    B back"
		KEY_A:
			race.auto_player = true
			hint.text = "SPACE pause + note    N next    B back    T take the wheel    A auto"
		_:
			return
	get_viewport().set_input_as_handled()


func pause_for_note() -> void:
	if paused_here:
		return
	shot = get_viewport().get_texture().get_image()      # the moment, before the panel covers it
	paused_here = true
	race.paused = true
	note_panel.visible = true
	note.text = ""
	note.grab_focus()
	note_status.text = "%s   %s %d   at %.2f of the loop (wp %d)   race time %s" % [
		String(Shared.tracks.get(track.key, {}).get("name", track.key)), track.stage_name().to_lower(),
		track.stage_of(race.player), _frac(), race.player.next_wp, _mmss(race.race_time)]


func resume() -> void:
	paused_here = false
	race.paused = false
	note_panel.visible = false
	shot = null


func _frac() -> float:
	return float(race.player.next_wp) / float(maxi(1, track.n)) if race.player != null else 0.0


func _mmss(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


func _reports_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../reports")


func save_note() -> void:
	var text := note.text.strip_edges()
	if text == "":
		resume()
		return
	var dir := _reports_dir()
	DirAccess.make_dir_recursive_absolute(dir.path_join("tour"))
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var png := "tour/%s-%s.png" % [track.key, stamp]
	if shot != null:
		shot.save_png(dir.path_join(png))
	var spec: Dictionary = Shared.tracks.get(track.key, {})
	var entry := "## %s (%s) — %s %d, %.2f of the loop, wp %d, race time %s\n\n%s\n\n![%s](%s)\n\n_%s_\n\n" % [
		String(spec.get("name", track.key)), track.key, track.stage_name().to_lower(), track.stage_of(race.player),
		_frac(), race.player.next_wp, _mmss(race.race_time), text, track.key, png, Time.get_datetime_string_from_system()]
	var path := dir.path_join("tour-feedback.md")
	var existed := FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if existed else FileAccess.WRITE)
	if f != null:
		if existed:
			f.seek_end()
		else:
			f.store_string("# Tour feedback\n\nNotes taken on the tour (--tour), newest last. Each has the course, the spot and a screenshot.\n\n")
		f.store_string(entry)
	notes += 1
	print("tour: note %d on %s at %.2f -> %s" % [notes, track.key, _frac(), path])
	resume()


func advance(step: int) -> void:
	var next := index + step
	if next >= order.size():
		done = true
		strip.text = "TOUR COMPLETE  -  %d courses, %d notes in reports/tour-feedback.md    Esc quits" % [order.size(), notes]
		hint.text = ""
		print("tour: complete")
		if test_mode:
			get_tree().quit()
		return
	next = maxi(0, next)
	print("tour: %s -> %s" % [track.key, String(order[next])])
	Campaign.tour_index = next
	if test_mode:
		get_tree().quit()
		return
	get_tree().reload_current_scene()
