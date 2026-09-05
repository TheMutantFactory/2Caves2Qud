# Turns "is this button down right now" into "was it pressed this tick", tracked
# here rather than read from the engine so a live frame and a replayed frame are
# indistinguishable downstream.
class_name ButtonEdges
extends RefCounted

var _was_down: Dictionary = {}


func resolve(down_by_action: Dictionary) -> Dictionary:
	var pressed := {}
	for action in down_by_action:
		pressed[action] = bool(down_by_action[action]) and not bool(_was_down.get(action, false))
	_was_down = down_by_action.duplicate()
	return pressed


func reset() -> void:
	_was_down.clear()


# Adopt the current state as history without reporting any of it as a press: a
# button held while a pad was picked up is not something the player just did.
func assume(down_by_action: Dictionary) -> void:
	_was_down = down_by_action.duplicate()
