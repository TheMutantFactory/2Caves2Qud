# Autoload: the local players. Press a button on any keyboard slot or gamepad to
# join (up to MAX), each with its own adapter, racer and colour; survives scene
# changes so the lobby's choices reach the race. Hot-plug: a pad pulled out leaves
# its player waiting, and the next pad to press a button takes that seat.
# The join flow is ported from playgraph's ControllerHub + PlayerRoster (MIT).
extends Node

signal joined(index: int)
signal dropped(index: int)

const MAX := 4
const COLORS := [Color(1.0, 0.93, 0.35), Color(0.47, 0.78, 1.0), Color(0.45, 0.9, 0.5), Color(1.0, 0.5, 0.6)]

var players: Array = []        # [{id, controller, adapter, racer: {kind, unit, name}, ready}]
var joins_enabled := false
var devices: DeviceState = DeviceState.shared()
var tick := 0
var _pending: Dictionary = {}
var _orphans: Array = []       # player dicts whose controller went away, oldest first


func _ready() -> void:
	Input.joy_connection_changed.connect(_device_changed)


func count() -> int:
	return players.size()


func by_controller(controller_id: String) -> Dictionary:
	for p in players:
		if p["controller"] == controller_id:
			return p
	return {}


func clear() -> void:
	players.clear()
	_orphans.clear()


# Everyone's frame for this tick, in seat order.
func frames() -> Array:
	tick += 1
	var out := []
	for p in players:
		out.append(p["adapter"].poll(tick))
	return out


func _input(event: InputEvent) -> void:
	if not joins_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		for slot in [KeyboardAdapter.Slot.LEFT, KeyboardAdapter.Slot.RIGHT]:
			if KeyboardAdapter.slot_uses_key(slot, event.physical_keycode):
				_pending["keyboard:%d" % [slot]] = slot
	elif event is InputEventJoypadButton and event.pressed:
		_pending[GamepadAdapter.controller_id_for(event.device)] = event.device


func _physics_process(_dt: float) -> void:
	if not joins_enabled:
		_pending.clear()
		return
	var presses := _pending
	_pending = {}
	for cid in presses:
		_report(String(cid), presses[cid])
	for device in devices.connected_joypads():
		if GamepadAdapter.any_button_down(device, devices):
			_report(GamepadAdapter.controller_id_for(device), device)
	for slot in [KeyboardAdapter.Slot.LEFT, KeyboardAdapter.Slot.RIGHT]:
		if KeyboardAdapter.any_key_down(slot, devices):
			_report("keyboard:%d" % [slot], slot)


func _report(controller_id: String, source) -> void:
	if not by_controller(controller_id).is_empty():
		return
	join_with(controller_id, _adapter_for(controller_id, source))


func _adapter_for(controller_id: String, source) -> DriveAdapter:
	if controller_id.begins_with("keyboard:"):
		var k := KeyboardAdapter.new("", source)
		k.devices = devices
		return k
	var g := GamepadAdapter.new("", int(source))
	g.devices = devices
	return g


# Any transport can join through here: a phone or a network peer hands in its own adapter.
func join_with(controller_id: String, adapter: DriveAdapter) -> Dictionary:
	var p: Dictionary = {}
	if not _orphans.is_empty():
		p = _orphans.pop_front()   # the seat that lost its pad goes to the next pad that speaks
	else:
		if players.size() >= MAX:
			return {}
		var seat := _next_seat()
		p = {"id": "p%d" % (seat + 1), "seat": seat, "racer": {"kind": "wizard", "unit": Campaign.skin if seat == 0 else "player", "name": "Wizard"}, "ready": false}
		players.append(p)
		players.sort_custom(func(a, b): return int(a["seat"]) < int(b["seat"]))
	p["controller"] = controller_id
	adapter.player_id = p["id"]
	adapter.controller_id = controller_id
	p["adapter"] = adapter
	p["ready"] = false
	adapter.poll(tick)   # the press that took the seat is history, not this player's first command
	joined.emit(int(p["seat"]))
	return p


func leave(controller_id: String) -> void:
	var p := by_controller(controller_id)
	if p.is_empty():
		return
	players.erase(p)
	_orphans.erase(p)
	dropped.emit(int(p["seat"]))


func _next_seat() -> int:
	var used := {}
	for p in players:
		used[int(p["seat"])] = true
	for s in MAX:
		if not used.has(s):
			return s
	return MAX - 1


func _device_changed(device: int, connected: bool) -> void:
	if connected:
		return   # a pad plugged in by accident takes no seat until it presses something
	var p := by_controller(GamepadAdapter.controller_id_for(device))
	if p.is_empty():
		return
	p["controller"] = ""
	if not _orphans.has(p):
		_orphans.append(p)
