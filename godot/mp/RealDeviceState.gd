# The actual hardware, via Godot's Input singleton. The only file that reads it.
class_name RealDeviceState
extends DeviceState


func is_key_down(keycode: int) -> bool:
	return Input.is_physical_key_pressed(keycode)


func is_joy_button_down(device: int, button: int) -> bool:
	return Input.is_joy_button_pressed(device, button)


func joy_axis(device: int, axis: int) -> float:
	return Input.get_joy_axis(device, axis)


func connected_joypads() -> Array:
	return Input.get_connected_joypads()


func is_real() -> bool:
	return true
