# Autoload: input actions defined in code (keyboard + gamepad) so the mapping
# is readable here instead of buried in project.godot.
extends Node


func _ready() -> void:
	_action("drive_forward", [_key(KEY_W), _key(KEY_UP), _btn(JOY_BUTTON_A), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action("drive_back", [_key(KEY_S), _key(KEY_DOWN), _btn(JOY_BUTTON_B), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_action("steer_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("steer_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action("drift", [_key(KEY_SHIFT), _key(KEY_SPACE), _btn(JOY_BUTTON_RIGHT_SHOULDER), _btn(JOY_BUTTON_LEFT_SHOULDER)])
	_action("cast", [_key(KEY_ENTER), _key(KEY_CTRL), _key(KEY_E), _btn(JOY_BUTTON_X)])
	_action("view_toggle", [_key(KEY_M), _btn(JOY_BUTTON_Y)])
	_action("pause", [_key(KEY_TAB), _key(KEY_P), _key(KEY_ESCAPE), _btn(JOY_BUTTON_START)])
	_action("confirm", [_key(KEY_ENTER), _key(KEY_SPACE), _btn(JOY_BUTTON_A)])
	_action("quick_shop", [_key(KEY_Q), _btn(JOY_BUTTON_Y)])
	_action("free_drive", [_key(KEY_F), _btn(JOY_BUTTON_BACK)])
	_action("spell_picker", [_key(KEY_L)])   # test rig
	_action("slow_mo", [_key(KEY_Z)])        # test rig
	_action("enemy_picker", [_key(KEY_N)])   # test rig
	_action("debug_attacks", [_key(KEY_K)])  # debug: monster attacks on/off
	_action("debug_skip", [_key(KEY_BRACKETRIGHT)])   # debug: next realm
	_action("debug_back", [_key(KEY_BRACKETLEFT)])    # debug: previous realm
	var slot_keys := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
	for i in slot_keys.size():
		_action("slot_%d" % (i + 1), [_key(slot_keys[i])])


func _action(name: String, events: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.3)
	for ev in events:
		InputMap.action_add_event(name, ev)


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	return ev


func _btn(index: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = index
	return ev


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	return ev
