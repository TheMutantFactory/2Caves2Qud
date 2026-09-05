# A human on another machine: their DriveFrames arrive over the network and are
# handed out one tick at a time. Frames that pile up between polls are merged
# (latest axes, every press kept) so a button tap is never lost; when nothing new
# has arrived the last axes are repeated with the presses cleared.
class_name RemoteAdapter
extends DriveAdapter

var peer := ""              # transport address (Net peer id)
var _pending: Array = []    # DriveFrames received since the last poll
var _last: DriveFrame = null
var last_seen := 0.0        # seconds since the last frame arrived


func _init(p_player_id: String = "", p_peer: String = "") -> void:
	super(p_player_id, "net:" + p_peer)
	peer = p_peer


func label() -> String:
	return "online"


func push(f: DriveFrame) -> void:
	_pending.append(f)
	last_seen = 0.0


func _poll(tick: int) -> DriveFrame:
	var f := DriveFrame.neutral(tick, player_id)
	if _pending.is_empty():
		if _last != null:
			f.steer = _last.steer
			f.throttle = _last.throttle
			f.drift_held = _last.drift_held
		return f
	for p in _pending:
		f.steer = p.steer
		f.throttle = p.throttle
		f.drift_held = p.drift_held
		f.cast_pressed = f.cast_pressed or p.cast_pressed
		f.item_pressed = f.item_pressed or p.item_pressed
		f.next_pressed = f.next_pressed or p.next_pressed
		f.prev_pressed = f.prev_pressed or p.prev_pressed
		f.pause_pressed = f.pause_pressed or p.pause_pressed
		f.confirm_pressed = f.confirm_pressed or p.confirm_pressed
		f.back_pressed = f.back_pressed or p.back_pressed
		if p.slot >= 0:
			f.slot = p.slot
	_pending.clear()
	_last = f
	return f
