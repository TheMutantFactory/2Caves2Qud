# Gamepad control for one kart: left stick or d-pad steers, right trigger drives,
# left trigger brakes (the stick's vertical axis as a fallback), A drifts, X casts
# the selected slot, B uses the item, bumpers move the selection, Start pauses.
# Deadzones, debounce and a settle window after a hot-plug come from playgraph.
class_name GamepadAdapter
extends DriveAdapter

const DEADZONE := 0.22
const CONNECT_SETTLE_TICKS := 3

const BUTTONS := {
	"drift": JOY_BUTTON_A, "cast": JOY_BUTTON_X, "item": JOY_BUTTON_B, "next": JOY_BUTTON_RIGHT_SHOULDER,
	"prev": JOY_BUTTON_LEFT_SHOULDER, "pause": JOY_BUTTON_START, "back": JOY_BUTTON_Y,
}
const DPAD := {"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT, "up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN}

var device: int = 0
var devices: DeviceState = DeviceState.shared()
var _edges := ButtonEdges.new()
var _debounce := ButtonDebounce.new()
var _settle_left := 0
var _was_connected := false
var _polled_once := false


func _init(p_player_id: String = "", p_device: int = 0) -> void:
	super(p_player_id, controller_id_for(p_device))
	device = p_device


static func controller_id_for(p_device: int) -> String:
	return "gamepad:%d" % [p_device]


func label() -> String:
	var n := Input.get_joy_name(device) if devices.is_real() else ""
	return ("Pad %d" % (device + 1)) + (("  " + n) if n != "" else "")


func _poll(tick: int) -> DriveFrame:
	var connected := is_connected_source()
	if connected and not _was_connected and _polled_once:
		_settle_left = CONNECT_SETTLE_TICKS
	elif not connected and _was_connected:
		_debounce.reset()
	_was_connected = connected
	_polled_once = true
	var down := _debounce.filter(_read_buttons())
	if _settle_left > 0:
		_settle_left -= 1
		_edges.assume(down)
		return DriveFrame.neutral(tick, player_id)
	return build_frame(tick, _read_stick(), _read_triggers(), down)


# Pure mapping, so it can be tested with no hardware.
func build_frame(tick: int, stick: Vector2, triggers: Vector2, down: Dictionary) -> DriveFrame:
	var f := DriveFrame.neutral(tick, player_id)
	f.steer = stick.x
	if bool(down.get("left", false)) or bool(down.get("right", false)):
		f.steer = (1.0 if down.get("right", false) else 0.0) - (1.0 if down.get("left", false) else 0.0)
	f.throttle = triggers.y - triggers.x   # right trigger drives, left brakes
	if absf(f.throttle) < 0.01:
		f.throttle = -stick.y            # stick forward = drive
		if bool(down.get("up", false)) or bool(down.get("down", false)):
			f.throttle = (1.0 if down.get("up", false) else 0.0) - (1.0 if down.get("down", false) else 0.0)
	var pressed := _edges.resolve(down)
	f.drift_held = bool(down.get("drift", false))
	f.cast_pressed = bool(pressed.get("cast", false))
	f.item_pressed = bool(pressed.get("item", false))
	f.next_pressed = bool(pressed.get("next", false))
	f.prev_pressed = bool(pressed.get("prev", false))
	f.pause_pressed = bool(pressed.get("pause", false))
	f.confirm_pressed = bool(pressed.get("drift", false)) or bool(pressed.get("cast", false))
	f.back_pressed = bool(pressed.get("back", false)) or bool(pressed.get("item", false))
	return f.sanitize()


func is_connected_source() -> bool:
	return devices.connected_joypads().has(device)


func _read_stick() -> Vector2:
	return Vector2(apply_deadzone(devices.joy_axis(device, JOY_AXIS_LEFT_X), DEADZONE),
		apply_deadzone(devices.joy_axis(device, JOY_AXIS_LEFT_Y), DEADZONE))


func _read_triggers() -> Vector2:
	return Vector2(clampf(devices.joy_axis(device, JOY_AXIS_TRIGGER_LEFT), 0.0, 1.0),
		clampf(devices.joy_axis(device, JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0))


func _read_buttons() -> Dictionary:
	var down := {}
	for action in BUTTONS:
		down[action] = devices.is_joy_button_down(device, BUTTONS[action])
	for action in DPAD:
		down[action] = devices.is_joy_button_down(device, DPAD[action])
	return down


static func apply_deadzone(value: float, deadzone: float) -> float:
	var magnitude := absf(value)
	if magnitude <= deadzone:
		return 0.0
	return signf(value) * (magnitude - deadzone) / (1.0 - deadzone)


static func any_button_down(device_index: int, devices: DeviceState = null) -> bool:
	var source := devices if devices != null else DeviceState.shared()
	for action in BUTTONS:
		if source.is_joy_button_down(device_index, BUTTONS[action]):
			return true
	return false
