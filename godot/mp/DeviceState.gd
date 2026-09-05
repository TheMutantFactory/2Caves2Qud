# Reads physical devices, or pretends to. Everything that touches Godot's Input
# singleton goes through here so the adapters can be driven by a fake in a test.
# Ported from the playgraph prototype (MIT, same author).
class_name DeviceState
extends RefCounted

static var _shared: DeviceState


static func shared() -> DeviceState:
	if _shared == null:
		_shared = RealDeviceState.new()
	return _shared


func is_key_down(_keycode: int) -> bool:
	return false


func is_joy_button_down(_device: int, _button: int) -> bool:
	return false


func joy_axis(_device: int, _axis: int) -> float:
	return 0.0


func connected_joypads() -> Array:
	return []


func is_real() -> bool:
	return false
