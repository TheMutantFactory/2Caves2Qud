# The pause screen: wizard status, the ten action-bar slots, and the spell
# shop. Built in code; mouse and keyboard.
class_name Shop
extends CanvasLayer

signal closed
signal quit_requested

var race
var selected: Dictionary = {}
var grid: GridContainer
var detail_name: Label
var detail_meta: Label
var detail_desc: Label
var buy_btn: Button
var status: Label
var slots_box: HBoxContainer
var filter_tag := ""
var buttons: Array = []
var artifacts_lbl: Label
var upgrades_box: VBoxContainer
var upgrades_title: Label


func _ready() -> void:
	layer = 20
	_build()
	refresh()


func _font(l: Control, size: int, color := Color.WHITE) -> void:
	l.add_theme_font_override("font", QUD.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)


func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	_font(l, size, color)
	return l


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.size = Vector2(1920, 1080)
	add_child(dim)

	var title := _label("SPELL SHOP", 56, Color(1.0, 0.93, 0.35))
	title.position = Vector2(60, 24)
	add_child(title)
	var hint := _label("Tab / Esc resume    arrows or stick to browse, Enter / A to buy    1-0 cast in the race    hold Q in the race for the quick shop", 20, Color(0.75, 0.75, 0.75))
	hint.position = Vector2(60, 90)
	add_child(hint)

	status = _label("", 26)
	status.position = Vector2(60, 130)
	add_child(status)
	artifacts_lbl = _label("", 18, Color(0.85, 0.75, 0.55))
	artifacts_lbl.position = Vector2(700, 176)
	artifacts_lbl.size = Vector2(1160, 70)
	artifacts_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(artifacts_lbl)

	slots_box = HBoxContainer.new()
	slots_box.position = Vector2(60, 175)
	slots_box.add_theme_constant_override("separation", 8)
	add_child(slots_box)

	# tag filters
	var tags := HBoxContainer.new()
	tags.position = Vector2(60, 250)
	tags.add_theme_constant_override("separation", 6)
	add_child(tags)
	for tag in ["All", "Fire", "Lightning", "Ice", "Nature", "Arcane", "Dark", "Holy", "Sorcery", "Conjuration", "Enchantment"]:
		var b := Button.new()
		b.text = tag
		_font(b, 18)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): filter_tag = "" if tag == "All" else tag; refresh())
		tags.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60, 300)
	scroll.size = Vector2(1180, 740)
	add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	var panel := PanelContainer.new()
	panel.position = Vector2(1280, 300)
	panel.size = Vector2(580, 740)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	detail_name = _label("Pick a spell", 34, Color(1.0, 0.93, 0.35))
	vb.add_child(detail_name)
	detail_meta = _label("", 20, Color(0.8, 0.8, 0.8))
	detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_meta.custom_minimum_size = Vector2(540, 0)
	vb.add_child(detail_meta)
	detail_desc = _label("", 22)
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_desc.custom_minimum_size = Vector2(540, 120)
	vb.add_child(detail_desc)
	upgrades_title = _label("", 22, Color(0.55, 0.85, 1.0))
	vb.add_child(upgrades_title)
	var uscroll := ScrollContainer.new()
	uscroll.custom_minimum_size = Vector2(540, 250)
	uscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(uscroll)
	upgrades_box = VBoxContainer.new()
	upgrades_box.add_theme_constant_override("separation", 6)
	uscroll.add_child(upgrades_box)
	buy_btn = Button.new()
	buy_btn.text = "BUY"
	_font(buy_btn, 30)
	buy_btn.focus_mode = Control.FOCUS_NONE
	buy_btn.pressed.connect(_buy)
	vb.add_child(buy_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	var resume := Button.new()
	resume.text = "RESUME"
	_font(resume, 24)
	resume.focus_mode = Control.FOCUS_NONE
	resume.pressed.connect(func(): closed.emit())
	row.add_child(resume)
	var quit := Button.new()
	quit.text = "QUIT RUN"
	_font(quit, 24)
	quit.focus_mode = Control.FOCUS_NONE
	quit.pressed.connect(func(): quit_requested.emit())
	row.add_child(quit)


func refresh() -> void:
	status.text = "Realm %d/%d     HP %d/%d     Spell points %d     Slots %d/%d" % [
		Campaign.level, Campaign.MAX_LEVEL, int(Campaign.hp), int(Campaign.max_hp), Campaign.sp,
		Campaign.spells.size(), Campaign.MAX_SLOTS]

	for c in slots_box.get_children():
		c.queue_free()
	for i in Campaign.MAX_SLOTS:
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(64, 64)
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(60, 60)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if i < Campaign.spells.size():
			tr.texture = QUD.icon(String(Campaign.spells[i]["icon"]))
			tr.tooltip_text = String(Campaign.spells[i]["name"])
		box.add_child(tr)
		var key := _label(str((i + 1) % 10), 16, Color(0.8, 0.8, 0.8))
		box.add_child(key)
		slots_box.add_child(box)

	var arts := []
	for a in Campaign.artifacts:
		arts.append("%s (%s)" % [a["name"], a["label"]])
	artifacts_lbl.text = ("Artifacts: " + "; ".join(arts)) if arts.size() > 0 else "Artifacts: none yet. Trinkets on the track and some rift gates grant them."
	var had_focus := get_viewport().gui_get_focus_owner() != null
	for c in grid.get_children():
		c.queue_free()
	buttons.clear()
	for spell in SpellDB.spells:
		if filter_tag != "" and not (filter_tag in spell.get("tags", [])):
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(285, 70)
		b.focus_mode = Control.FOCUS_ALL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = SpellDB.icon(spell)
		b.expand_icon = true
		b.text = "  %s  (%d)" % [spell["name"], Campaign.cost(spell)]
		_font(b, 18)
		var owned := Campaign.owns(spell["name"])
		var affordable := Campaign.can_buy(spell)
		if owned:
			b.modulate = Color(0.55, 0.9, 0.55)
		elif not affordable:
			b.modulate = Color(0.5, 0.5, 0.5)
		b.focus_entered.connect(func(): _select(spell))
		b.pressed.connect(func(): _pick(spell))
		grid.add_child(b)
		buttons.append(b)
	_update_detail()
	if not had_focus and buttons.size() > 0:
		buttons[0].call_deferred("grab_focus")


# Click or press on a spell: select it, and buy when pressed again while selected.
func _pick(spell: Dictionary) -> void:
	if selected.get("name", "") == spell["name"] and Campaign.can_buy(spell):
		_buy()
	else:
		_select(spell)


func _select(spell: Dictionary) -> void:
	selected = spell
	_update_detail()


func _update_detail() -> void:
	if selected.is_empty():
		detail_name.text = "Pick a spell"
		detail_meta.text = ""
		detail_desc.text = "Spells cost their level in spell points. Each takes one of ten slots and casts with keys 1 to 0 during the race. Charges refill one per lap."
		buy_btn.disabled = true
		return
	var e := SpellDB.effect_for(selected)
	detail_name.text = String(selected["name"])
	var tags: Array = selected.get("tags", [])
	detail_meta.text = "Level %d   cost %d SP   charges %d   %s\nIn the race: %s (%s)" % [
		int(selected["level"]), Campaign.cost(selected), maxi(1, mini(12, int(selected.get("max_charges", 3)))),
		", ".join(tags), SpellDB.kind_verb(String(e["kind"])), _effect_summary(e)]
	detail_desc.text = SpellDB.description(selected)
	_update_upgrades()
	if Campaign.owns(selected["name"]):
		buy_btn.text = "OWNED"
		buy_btn.disabled = true
	elif Campaign.spells.size() >= Campaign.MAX_SLOTS:
		buy_btn.text = "NO SLOT"
		buy_btn.disabled = true
	elif not Campaign.can_buy(selected):
		buy_btn.text = "NEED %d SP" % Campaign.cost(selected)
		buy_btn.disabled = true
	else:
		buy_btn.text = "BUY for %d SP" % Campaign.cost(selected)
		buy_btn.disabled = false


# The game's named upgrades for the selected spell, buyable once it is owned.
func _update_upgrades() -> void:
	for c in upgrades_box.get_children():
		c.queue_free()
	var ups: Array = selected.get("upgrades", [])
	if ups.is_empty():
		upgrades_title.text = ""
		return
	var owned := {}
	for s in Campaign.spells:
		if s["name"] == selected["name"]:
			owned = s
	upgrades_title.text = "Upgrades (cost their level in SP%s)" % ("" if not owned.is_empty() else "; buy the spell first")
	for up in ups:
		if up.has("error"):
			continue
		var name := String(up["name"])
		var lvl := maxi(1, int(up.get("level", 1)))
		var taken: bool = (not owned.is_empty()) and bool(owned["upgrades"].has(name))
		var preview: Dictionary = (owned["effect"] if not owned.is_empty() else SpellDB.effect_for(selected)).duplicate(true)
		var res := SpellDB.apply_upgrade(preview, up)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.text = "%s   %s" % [name, "taken" if taken else "%d SP" % lvl]
		_font(b, 20)
		b.disabled = taken or owned.is_empty() or Campaign.sp < lvl
		if taken:
			b.modulate = Color(0.55, 0.9, 0.55)
		b.pressed.connect(func(): _buy_upgrade(up))
		upgrades_box.add_child(b)
		var l := _label("%s
-> %s" % [String(SpellDB.description(up)).left(150), String(res["summary"])], 16, Color(0.8, 0.8, 0.8))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(520, 0)
		upgrades_box.add_child(l)


func _buy_upgrade(up: Dictionary) -> void:
	if Campaign.upgrade(String(selected["name"]), up):
		Audio.play("learn_spell")
		refresh()
	else:
		Audio.play("menu_abort")


# Screenshots: start on the first owned spell so its upgrades show.
func preselect_owned() -> void:
	if Campaign.spells.size() > 0 and SpellDB.by_name.has(String(Campaign.spells[0]["name"])):
		_select(SpellDB.by_name[String(Campaign.spells[0]["name"])])


func _effect_summary(e: Dictionary) -> String:
	match String(e["kind"]):
		"bolt", "beam":
			return "%d %s damage, range %d" % [int(e["damage"]), e["dtype"], int(e["range"])]
		"blast":
			return "%d %s damage in a %dpx blast" % [int(e["damage"]), e["dtype"], int(e["radius"])]
		"summon":
			return "%d x %d HP chaser, %d damage, %ds" % [int(e.get("count", 1)), int(e["hp"]), int(e["damage"]), int(e["duration"])]
		"shield":
			return "absorb %d hits" % int(e["shields"])
		"heal":
			return "+%d HP" % int(e["amount"])
		"buff":
			return "+%d%% speed for %ds" % [int(100 * float(e["strength"])), int(e["duration"])]
		"blink":
			return "teleport %dpx" % int(e["distance"])
		"hex":
			return "freeze the racer ahead for %ds" % int(e["duration"])
		"melee":
			return "%d %s damage to karts within %dpx in front" % [int(e.get("damage", 0)), e.get("dtype", "Physical"), int(e.get("range", 180))]
		"burst":
			return "%d %s damage to everyone within %dpx" % [int(e.get("damage", 0)), e.get("dtype", "Arcane"), int(e.get("radius", 300))]
		"aura":
			return "%d %s damage every %.1fs for %ds within %dpx" % [int(e.get("damage", 0)), e.get("dtype", "Arcane"), float(e.get("tick", 0.8)), int(e.get("duration", 8)), int(e.get("radius", 300))]
		"patch":
			return "a %s field %dpx up the road, %d damage a tick for %ds" % [String(e.get("dtype", "Fire")).to_lower(), int(e.get("range", 0)), int(e.get("damage", 0)), int(e.get("duration", 6))]
		"empower":
			return "temporary bonuses for %ds" % int(e.get("duration", 8))
	return ""


func _buy() -> void:
	if selected.is_empty():
		return
	if Campaign.buy(selected):
		Audio.play("learn_spell")
		refresh()
	else:
		Audio.play("menu_abort")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		closed.emit()
		get_viewport().set_input_as_handled()
