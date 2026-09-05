# Turns some source of control into DriveFrames. Subclasses are the only place
# allowed to know about keycodes, device ids or wire formats. Polling twice for
# the same tick returns the same frame, so button edges are never consumed twice.
class_name DriveAdapter
extends RefCounted

var player_id: String = ""
var controller_id: String = ""

var _cached_tick: int = -1
var _cached_frame: DriveFrame = null


func _init(p_player_id: String = "", p_controller_id: String = "") -> void:
	player_id = p_player_id
	controller_id = p_controller_id


func poll(tick: int) -> DriveFrame:
	if _cached_frame != null and _cached_tick == tick:
		return _cached_frame.copy()
	_cached_frame = _poll(tick)
	_cached_tick = tick
	return _cached_frame.copy()


func invalidate_cache() -> void:
	_cached_tick = -1
	_cached_frame = null


func _poll(tick: int) -> DriveFrame:
	return DriveFrame.neutral(tick, player_id)


func is_connected_source() -> bool:
	return true


func label() -> String:
	return controller_id
