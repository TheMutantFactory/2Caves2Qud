# A keyboard and a handful of gamepads that exist only in a test: the adapters
# cannot tell the difference, so the code under test is the shipped code.
class_name FakeDeviceState
extends DeviceState

var keys_down: Dictionary = {}
var buttons_down: Dictionary = {}
var axes: Dictionary = {}
var joypads: Array = []


func press_key(keycode: int) -> FakeDeviceState:
	keys_down[keycode] = true
	return self


func release_key(keycode: int) -> FakeDeviceState:
	keys_down.erase(keycode)
	return self


func plug_in(device: int) -> FakeDeviceState:
	if not joypads.has(device):
		joypads.append(device)
		joypads.sort()
	return self


func unplug(device: int) -> FakeDeviceState:
	joypads.erase(device)
	return self


func press_button(device: int, button: int) -> FakeDeviceState:
	buttons_down["%d:%d" % [device, button]] = true
	return self


func release_button(device: int, button: int) -> FakeDeviceState:
	buttons_down.erase("%d:%d" % [device, button])
	return self


func set_axis(device: int, axis: int, value: float) -> FakeDeviceState:
	axes["%d:%d" % [device, axis]] = value
	return self


func is_key_down(keycode: int) -> bool:
	return keys_down.has(keycode)


func is_joy_button_down(device: int, button: int) -> bool:
	return buttons_down.has("%d:%d" % [device, button])


func joy_axis(device: int, axis: int) -> float:
	return float(axes.get("%d:%d" % [device, axis], 0.0))


func connected_joypads() -> Array:
	return joypads.duplicate()
