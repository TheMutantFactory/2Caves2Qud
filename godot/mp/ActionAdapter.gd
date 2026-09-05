# The single-player controls (Godot's action map: WASD/arrows/pad to drive, Shift or
# space to drift, Enter/E/X for the pickup, number keys for the action bar) as a
# DriveAdapter, so a person racing online drives their kart the way they do offline.
# The pickup button is "item"; a number key both selects that slot and casts it.
class_name ActionAdapter
extends DriveAdapter

var _edges := ButtonEdges.new()


func _init(p_player_id: String = "") -> void:
	super(p_player_id, "actions")


func label() -> String:
	return "keyboard / gamepad"


func _poll(tick: int) -> DriveFrame:
	var f := DriveFrame.neutral(tick, player_id)
	f.throttle = Input.get_action_strength("drive_forward") - Input.get_action_strength("drive_back")
	f.steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	f.drift_held = Input.is_action_pressed("drift")
	var down := {"item": Input.is_action_pressed("cast"), "pause": Input.is_action_pressed("pause"), "confirm": Input.is_action_pressed("confirm")}
	for i in Campaign.MAX_SLOTS:
		down["slot_%d" % (i + 1)] = Input.is_action_pressed("slot_%d" % (i + 1))
	var pressed := _edges.resolve(down)
	f.item_pressed = bool(pressed["item"])
	f.pause_pressed = bool(pressed["pause"])
	f.confirm_pressed = bool(pressed["confirm"]) or bool(pressed["item"])
	for i in Campaign.MAX_SLOTS:
		if bool(pressed["slot_%d" % (i + 1)]):
			f.slot = i
			f.cast_pressed = true
			break
	return f.sanitize()
