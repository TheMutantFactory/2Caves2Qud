# Normalized per-player kart input for one simulation tick. Keyboard, gamepad and,
# later, phone or network sources all produce these through a DriveAdapter; nothing
# downstream knows what a keycode is. Plain data: serializable and comparable.
class_name DriveFrame
extends RefCounted

const AXIS_QUANTUM := 0.001

var tick: int = 0
var player_id: String = ""

var steer: float = 0.0        # -1 left .. 1 right
var throttle: float = 0.0     # -1 brake/reverse .. 1 accelerate
var drift_held: bool = false
var cast_pressed: bool = false      # the selected action-bar slot
var item_pressed: bool = false      # the pickup item
var next_pressed: bool = false      # move the selection right
var prev_pressed: bool = false      # move the selection left
var pause_pressed: bool = false
var confirm_pressed: bool = false   # menus: take / ready (same button as cast)
var back_pressed: bool = false      # menus: leave / unready (same button as item)
var slot: int = -1                  # an absolute slot pick (number keys), -1 for none


static func neutral(p_tick: int, p_player_id: String) -> DriveFrame:
	var f := DriveFrame.new()
	f.tick = p_tick
	f.player_id = p_player_id
	return f


func sanitize() -> DriveFrame:
	steer = snappedf(clampf(steer, -1.0, 1.0), AXIS_QUANTUM)
	throttle = snappedf(clampf(throttle, -1.0, 1.0), AXIS_QUANTUM)
	return self


func to_dict() -> Dictionary:
	return {"tick": tick, "player_id": player_id, "steer": steer, "throttle": throttle, "drift_held": drift_held,
		"cast_pressed": cast_pressed, "item_pressed": item_pressed, "next_pressed": next_pressed, "prev_pressed": prev_pressed,
		"pause_pressed": pause_pressed, "confirm_pressed": confirm_pressed, "back_pressed": back_pressed, "slot": slot}


static func from_dict(d: Dictionary) -> DriveFrame:
	var f := DriveFrame.new()
	f.tick = int(d.get("tick", 0))
	f.player_id = String(d.get("player_id", ""))
	f.steer = float(d.get("steer", 0.0))
	f.throttle = float(d.get("throttle", 0.0))
	f.drift_held = bool(d.get("drift_held", false))
	f.cast_pressed = bool(d.get("cast_pressed", false))
	f.item_pressed = bool(d.get("item_pressed", false))
	f.next_pressed = bool(d.get("next_pressed", false))
	f.prev_pressed = bool(d.get("prev_pressed", false))
	f.pause_pressed = bool(d.get("pause_pressed", false))
	f.confirm_pressed = bool(d.get("confirm_pressed", false))
	f.back_pressed = bool(d.get("back_pressed", false))
	f.slot = int(d.get("slot", -1))
	return f


# Wire form: a flat array, small enough to send every tick.
func to_array() -> Array:
	var bits := (1 if drift_held else 0) | (2 if cast_pressed else 0) | (4 if item_pressed else 0) | (8 if next_pressed else 0) 		| (16 if prev_pressed else 0) | (32 if pause_pressed else 0) | (64 if confirm_pressed else 0) | (128 if back_pressed else 0)
	return [tick, steer, throttle, bits, slot]


static func from_array(a: Array, p_player_id := "") -> DriveFrame:
	var f := DriveFrame.new()
	if a.size() < 5:
		return f
	f.tick = int(a[0])
	f.player_id = p_player_id
	f.steer = float(a[1])
	f.throttle = float(a[2])
	var bits := int(a[3])
	f.drift_held = bits & 1 != 0
	f.cast_pressed = bits & 2 != 0
	f.item_pressed = bits & 4 != 0
	f.next_pressed = bits & 8 != 0
	f.prev_pressed = bits & 16 != 0
	f.pause_pressed = bits & 32 != 0
	f.confirm_pressed = bits & 64 != 0
	f.back_pressed = bits & 128 != 0
	f.slot = int(a[4])
	return f.sanitize()


func has_press() -> bool:
	return cast_pressed or item_pressed or next_pressed or prev_pressed or pause_pressed or confirm_pressed or back_pressed or slot >= 0


func copy() -> DriveFrame:
	return DriveFrame.from_dict(to_dict())


func is_neutral() -> bool:
	return is_zero_approx(steer) and is_zero_approx(throttle) and not drift_held and not cast_pressed and not item_pressed \
		and not next_pressed and not prev_pressed and not pause_pressed and not confirm_pressed and not back_pressed and slot < 0
