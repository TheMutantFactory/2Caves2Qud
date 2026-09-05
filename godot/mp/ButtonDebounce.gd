# Ignores a worn microswitch letting go of itself: presses are taken at once,
# only releases wait SETTLE_TICKS to be believed.
class_name ButtonDebounce
extends RefCounted

const SETTLE_TICKS := 2

var _stable: Dictionary = {}
var _up_for: Dictionary = {}


func filter(raw: Dictionary) -> Dictionary:
	var believed := {}
	for action in raw:
		var down := bool(raw[action])
		var was := bool(_stable.get(action, false))
		if down:
			_up_for[action] = 0
			_stable[action] = true
		elif was:
			_up_for[action] = int(_up_for.get(action, 0)) + 1
			if int(_up_for[action]) >= SETTLE_TICKS:
				_stable[action] = false
		else:
			_up_for[action] = 0
		believed[action] = bool(_stable.get(action, false))
	return believed


func reset() -> void:
	_stable.clear()
	_up_for.clear()
