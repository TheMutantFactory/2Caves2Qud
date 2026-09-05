# One keyboard, two drivers: the LEFT slot is WASD with shift to drift, the RIGHT
# slot is the arrows with the numpad. The only file that mentions a keycode.
class_name KeyboardAdapter
extends DriveAdapter

enum Slot { LEFT, RIGHT }

const LAYOUTS := {
	Slot.LEFT: {
		"left": KEY_A, "right": KEY_D, "up": KEY_W, "down": KEY_S,
		"drift": KEY_SHIFT, "cast": KEY_F, "item": KEY_E, "next": KEY_R, "prev": KEY_Q, "pause": KEY_TAB,
	},
	Slot.RIGHT: {
		"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN,
		"drift": KEY_KP_0, "cast": KEY_KP_1, "item": KEY_KP_2, "next": KEY_KP_3, "prev": KEY_KP_PERIOD, "pause": KEY_KP_ENTER,
	},
}

const LABELS := {Slot.LEFT: "Keyboard WASD", Slot.RIGHT: "Keyboard arrows"}

var slot: Slot = Slot.LEFT
var devices: DeviceState = DeviceState.shared()
var _layout: Dictionary = {}
var _edges := ButtonEdges.new()


func _init(p_player_id: String = "", p_slot: Slot = Slot.LEFT) -> void:
	super(p_player_id, "keyboard:%d" % [p_slot])
	slot = p_slot
	_layout = LAYOUTS[p_slot]


func _poll(tick: int) -> DriveFrame:
	var f := DriveFrame.neutral(tick, player_id)
	var down := {}
	for action in _layout:
		down[action] = devices.is_key_down(_layout[action])
	var pressed := _edges.resolve(down)
	f.steer = (1.0 if down["right"] else 0.0) - (1.0 if down["left"] else 0.0)
	f.throttle = (1.0 if down["up"] else 0.0) - (1.0 if down["down"] else 0.0)
	f.drift_held = down["drift"]
	f.cast_pressed = pressed["cast"]
	f.item_pressed = pressed["item"]
	f.next_pressed = pressed["next"]
	f.prev_pressed = pressed["prev"]
	f.pause_pressed = pressed["pause"]
	f.confirm_pressed = pressed["cast"]
	f.back_pressed = pressed["item"]
	return f.sanitize()


func label() -> String:
	return LABELS[slot]


static func slot_uses_key(s: Slot, keycode: int) -> bool:
	return LAYOUTS[s].values().has(keycode)


static func any_key_down(s: Slot, devices: DeviceState = null) -> bool:
	var source := devices if devices != null else DeviceState.shared()
	for action in LAYOUTS[s]:
		if source.is_key_down(LAYOUTS[s][action]):
			return true
	return false
