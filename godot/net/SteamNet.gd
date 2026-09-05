# Autoload "Net": the Steam side of online play. Talks to GodotSteam (a GDExtension,
# installed by tools/get_godotsteam.py, absent from the repo) and degrades to "not
# available" when the extension or the Steam client is missing, so every other mode
# runs without _steam. Lobbies are the join hub: a host creates one tagged with the
# game key, guests browse the list filtered by that key and join. Race traffic will
# ride on Steam P2P between the members (not built yet).
extends Node

signal lobbies_changed
signal lobby_changed
signal chat(steam_id: int, name: String, text: String)
signal race_started(map: String, seed: int)

const GAME_KEY := "driftwizard3"
const PROTOCOL := "1"
const MAX_MEMBERS := 4
const APP_ID := 480   # Valve's SpaceWar test app until Drift Wizard has its own id

var available := false
var status := "Steam: not started"
var my_id := 0
var my_name := ""
var lobby_id := 0
var lobbies: Array = []      # [{id, name, host, members, max, protocol}] from the last refresh
var members: Array = []      # [{id, name, host}] of the lobby we are in
var searching := false
var log_lines: Array = []    # the last few events, for the menu page

var _pending_name := ""

# Race transport. Peers are strings: "steam:<id>" over Steam networking messages, or
# "udp:<ip>:<port>" over plain UDP (LAN, and two processes on one machine for tests).
var online_role := ""        # "", "host" or "guest" while a race is set up or running
var race_map := "brick"
var race_seed := 0
var _udp: PacketPeerUDP = null
var _udp_peers: Array = []   # host: guest addresses learned from their first packet
var _udp_host := ""
var _lobby_state := ""
var _relay := false
var _hooks: Array = []
const CHANNEL := 0
var _test_role := ""
var _test_t := 0.0
var _test_limit := 0.0
var _test_next := 0.0
var _test_looped := false


# The GodotSteam singleton, fetched at runtime so the script compiles (and the
# whole autoload chain boots) when the extension is not installed.
var _steam = null


func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		status = "Steam: GodotSteam not installed (run tools/get_godotsteam.py)"
		return
	_steam = Engine.get_singleton("Steam")
	if "--nosteam" in OS.get_cmdline_user_args():
		status = "Steam: off (--nosteam)"
		return
	var r: Dictionary = _steam.steamInitEx(APP_ID, false)
	if int(r.get("status", 1)) != 0:
		status = "Steam: not running (%s)" % String(r.get("verbal", ""))
		return
	available = true
	my_id = _steam.getSteamID()
	my_name = _steam.getPersonaName()
	status = "Steam: %s (app %d)" % [my_name, _steam.getAppID()]
	_hook("lobby_created", _on_lobby_created)
	_hook("lobby_match_list", _on_lobby_match_list)
	_hook("lobby_joined", _on_lobby_joined)
	_hook("lobby_chat_update", _on_lobby_chat_update)
	_hook("lobby_data_update", _on_lobby_data_update)
	_hook("lobby_message", _on_lobby_message)
	_hook("join_requested", _on_join_requested)
	_hook("persona_state_change", _on_persona_change)
	_hook("network_messages_session_request", _on_session_request)


# The Steam singleton outlives this node: every connection is undone on exit, or the
# extension calls into a freed object while it tears down and the process faults.
func _hook(sig: String, cb: Callable) -> void:
	_steam.connect(sig, cb)
	_hooks.append([sig, cb])


func _on_session_request(id: int) -> void:
	_steam.acceptSessionWithUser(id)


func _process(dt: float) -> void:
	if not available:
		return
	_steam.run_callbacks()
	if _test_role != "":
		_test_step(dt)


func _exit_tree() -> void:
	if _udp != null:
		_udp.close()
		_udp = null
	if available:
		if lobby_id != 0:
			_steam.leaveLobby(lobby_id)
		for h in _hooks:
			_steam.disconnect(h[0], h[1])
		_hooks.clear()
		_steam.steamShutdown()
		available = false


func _log(line: String) -> void:
	print("net: ", line)
	log_lines.append(line)
	if log_lines.size() > 8:
		log_lines.pop_front()


# ---------------------------------------------------------------- lobbies

func host(lobby_name := "") -> void:
	if not available or lobby_id != 0:
		return
	_pending_name = lobby_name if lobby_name != "" else "%s's race" % my_name
	_log("creating a lobby")
	_steam.createLobby(_steam.LOBBY_TYPE_PUBLIC, MAX_MEMBERS)


func _on_lobby_created(result: int, id: int) -> void:
	if result != _steam.RESULT_OK:
		_log("lobby creation failed (%d)" % result)
		return
	lobby_id = id
	_steam.setLobbyMemberData(id, "unit", Campaign.skin)
	_steam.setLobbyData(id, "game", GAME_KEY)
	_steam.setLobbyData(id, "state", "lobby")
	_steam.setLobbyData(id, "protocol", PROTOCOL)
	_steam.setLobbyData(id, "name", _pending_name)
	_steam.setLobbyData(id, "host", my_name)
	_steam.setLobbyData(id, "max", str(MAX_MEMBERS))
	_steam.setLobbyJoinable(id, true)
	_log("hosting lobby %d" % id)
	_refresh_members()
	lobby_changed.emit()


func refresh() -> void:
	if not available or searching:
		return
	searching = true
	_steam.addRequestLobbyListStringFilter("game", GAME_KEY, _steam.LOBBY_COMPARISON_EQUAL)
	_steam.addRequestLobbyListDistanceFilter(_steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	_steam.addRequestLobbyListResultCountFilter(50)
	_steam.requestLobbyList()


func _on_lobby_match_list(list: Array) -> void:
	searching = false
	lobbies.clear()
	for id in list:
		var lid := int(id)
		lobbies.append({"id": lid, "name": _steam.getLobbyData(lid, "name"), "host": _steam.getLobbyData(lid, "host"),
			"members": _steam.getNumLobbyMembers(lid), "max": int(_steam.getLobbyData(lid, "max")), "protocol": _steam.getLobbyData(lid, "protocol")})
	_log("%d lobbies found" % lobbies.size())
	lobbies_changed.emit()


func join(id: int) -> void:
	if not available or id == 0:
		return
	if lobby_id != 0:
		leave()
	_log("joining lobby %d" % id)
	_steam.joinLobby(id)


func _on_lobby_joined(lobby: int, _perms: int, _locked: bool, response: int) -> void:
	if response != _steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_log("could not join lobby %d (response %d)" % [lobby, response])
		lobby_changed.emit()
		return
	lobby_id = lobby
	_steam.setLobbyMemberData(lobby, "unit", Campaign.skin)
	_lobby_state = _steam.getLobbyData(lobby, "state")
	_log("in lobby %d (%s)" % [lobby, _steam.getLobbyData(lobby, "name")])
	_refresh_members()
	lobby_changed.emit()


func _on_join_requested(lobby: int, _friend: int) -> void:
	join(lobby)   # accepted a friend's invite through the overlay


func leave() -> void:
	if not available or lobby_id == 0:
		return
	_steam.leaveLobby(lobby_id)
	_log("left lobby %d" % lobby_id)
	lobby_id = 0
	members.clear()
	lobby_changed.emit()


func is_host() -> bool:
	return lobby_id != 0 and int(_steam.getLobbyOwner(lobby_id)) == my_id


func lobby_name() -> String:
	return _steam.getLobbyData(lobby_id, "name") if lobby_id != 0 else ""


func invite_friends() -> void:
	if lobby_id != 0:
		_steam.activateGameOverlayInviteDialog(lobby_id)


func _refresh_members() -> void:
	members.clear()
	if lobby_id == 0:
		return
	var owner := int(_steam.getLobbyOwner(lobby_id))
	for i in _steam.getNumLobbyMembers(lobby_id):
		var id := int(_steam.getLobbyMemberByIndex(lobby_id, i))
		var n: String = _steam.getFriendPersonaName(id)
		if n == "" or n == "[unknown]":
			n = "player %d" % (i + 1)
			_steam.requestUserInformation(id, true)   # the name arrives through persona_state_change
		members.append({"id": id, "name": n, "host": id == owner})


func _on_lobby_chat_update(lobby: int, changed: int, _by: int, state: int) -> void:
	if lobby != lobby_id:
		return
	var who: String = _steam.getFriendPersonaName(changed)
	if state & _steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
		_log("%s joined" % who)
	else:
		_log("%s left" % who)
	_refresh_members()
	lobby_changed.emit()


func _on_lobby_data_update(_ok: int, lobby: int, _member: int) -> void:
	if lobby != lobby_id:
		return
	_refresh_members()
	lobby_changed.emit()
	var st: String = _steam.getLobbyData(lobby, "state")
	if st == "racing" and _lobby_state != "racing" and not is_host():
		_lobby_state = st
		race_map = _steam.getLobbyData(lobby, "map")
		race_seed = int(_steam.getLobbyData(lobby, "seed"))
		online_role = "guest"
		_relay_up()
		_log("the host started a race on %s" % race_map)
		race_started.emit(race_map, race_seed)
	elif st != "racing":
		_lobby_state = st


func _on_persona_change(_id: int, _flags: int) -> void:
	if lobby_id != 0:
		_refresh_members()
		lobby_changed.emit()


func say(text: String) -> void:
	if lobby_id != 0:
		_steam.sendLobbyChatMsg(lobby_id, text)


func _on_lobby_message(lobby: int, user: int, text: String, _kind: int) -> void:
	if lobby != lobby_id:
		return
	var n: String = _steam.getFriendPersonaName(user)
	_log("%s: %s" % [n, text])
	chat.emit(user, n, text)


# ---------------------------------------------------------------- self test
# --nettest=host|browse --seconds=N: the host creates a lobby and answers chat; the
# browser refreshes until it sees a Drift Wizard lobby, joins it and says hello.

func run_test(role: String, seconds: float) -> void:
	_test_role = role
	_test_limit = seconds
	if not available:
		_log("test aborted: " + status)
		get_tree().quit()
		return
	chat.connect(_test_chat)
	if role == "host":
		host("test lobby")


func _test_chat(_id: int, n: String, text: String) -> void:
	if _test_role == "host" and not text.begins_with("hello back"):
		say("hello back, " + n)


func _test_step(dt: float) -> void:
	_test_t += dt
	if _test_t >= _test_next:
		_test_next = _test_t + 2.0
		refresh()
		if _test_role == "host" and lobby_id != 0 and _test_t > 3.0 and not _test_looped:
			_test_looped = true
			send("steam:%d" % my_id, ["ping", 1])
		for pm in poll():
			_log("message from %s: %s" % [pm[0], str(pm[1])])
		if _test_role == "browse" and lobby_id == 0:
			for l in lobbies:
				if String(l["protocol"]) == PROTOCOL:
					join(int(l["id"]))
					break
		elif _test_role == "browse" and lobby_id != 0 and _test_t < 6.0:
			say("hello from the browser")
	if _test_t >= _test_limit:
		var names := []
		for m in members:
			names.append(m["name"])
		print("nettest: role=%s lobby=%d lobbies=%d members=%s" % [_test_role, lobby_id, lobbies.size(), ", ".join(names)])
		leave()
		_test_role = ""
		get_tree().quit()


# ---------------------------------------------------------------- race transport

# Host: everyone in the lobby races on this map with this seed. Guests get it through
# the lobby data and change scene themselves.
func start_race(map: String, seed: int) -> void:
	race_map = map
	race_seed = seed
	online_role = "host"
	if lobby_id != 0:
		_relay_up()
		_steam.setLobbyData(lobby_id, "map", map)
		_steam.setLobbyData(lobby_id, "seed", str(seed))
		_steam.setLobbyData(lobby_id, "state", "racing")
		_steam.setLobbyJoinable(lobby_id, false)
		_lobby_state = "racing"
	race_started.emit(map, seed)


# Steam's relay network is brought up only for a Steam race (it is not torn down cleanly
# at exit, and every other mode never needs it).
func _relay_up() -> void:
	if available and not _relay:
		_relay = true
		_steam.initRelayNetworkAccess()


func back_to_lobby() -> void:
	online_role = ""
	if lobby_id != 0 and is_host():
		_steam.setLobbyData(lobby_id, "state", "lobby")
		_steam.setLobbyJoinable(lobby_id, true)
	_lobby_state = "lobby"
	_udp_peers.clear()


func set_my_unit(unit: String) -> void:
	if lobby_id != 0:
		_steam.setLobbyMemberData(lobby_id, "unit", unit)


# Plain UDP instead of Steam: --online=host --port=N / --online=guest --port=N [--host_ip=...].
func setup_udp(role: String, port: int, host_ip := "127.0.0.1") -> void:
	online_role = role
	_udp = PacketPeerUDP.new()
	if role == "host":
		_udp.bind(port, "*")
		_log("udp host on port %d" % port)
	else:
		_udp.bind(0, "*")
		_udp_host = "udp:%s:%d" % [host_ip, port]
		_log("udp guest of %s" % _udp_host)


func host_peer() -> String:
	if _udp != null:
		return _udp_host
	if lobby_id != 0:
		return "steam:%d" % int(_steam.getLobbyOwner(lobby_id))
	return ""


# The host's guests: lobby members other than us, or the UDP addresses that have spoken.
func peers() -> Array:
	if _udp != null:
		return _udp_peers.duplicate()
	var out := []
	for m in members:
		if int(m["id"]) != my_id:
			out.append("steam:%d" % int(m["id"]))
	return out


func member_racer(peer: String) -> Dictionary:
	if peer.begins_with("steam:") and lobby_id != 0:
		var id := int(peer.substr(6))
		var unit: String = _steam.getLobbyMemberData(lobby_id, id, "unit")
		if unit == "" or not QUD.has_unit(unit):
			unit = "player"
		return {"kind": "wizard", "unit": unit, "name": _steam.getFriendPersonaName(id)}
	return {"kind": "wizard", "unit": "player", "name": peer.get_slice(":", 2) if peer.begins_with("udp:") else "Wizard"}


func send(peer: String, msg: Array, reliable := false) -> void:
	var bytes := var_to_bytes(msg)
	if peer.begins_with("udp:"):
		if _udp == null:
			return
		_udp.set_dest_address(peer.get_slice(":", 1), int(peer.get_slice(":", 2)))
		_udp.put_packet(bytes)
	elif peer.begins_with("steam:") and available:
		_steam.sendMessageToUser(int(peer.substr(6)), bytes, _steam.NETWORKING_SEND_RELIABLE if reliable else _steam.NETWORKING_SEND_UNRELIABLE, CHANNEL)


func broadcast(msg: Array, reliable := false) -> void:
	for p in peers():
		send(p, msg, reliable)


# Everything that arrived since the last call, as [peer, msg] pairs.
func poll() -> Array:
	var out := []
	if _udp != null:
		while _udp.get_available_packet_count() > 0:
			var bytes := _udp.get_packet()
			var peer := "udp:%s:%d" % [_udp.get_packet_ip(), _udp.get_packet_port()]
			if online_role == "host" and not _udp_peers.has(peer):
				_udp_peers.append(peer)
				_log("guest %s connected" % peer)
			var v = bytes_to_var(bytes)
			if v is Array:
				out.append([peer, v])
	elif available:
		var msgs: Array = _steam.receiveMessagesOnChannel(CHANNEL, 64)
		for m in msgs:
			var from := int(m.get("identity", m.get("remote_steam_id", 0)))
			if from == 0 and m.has("identity_steam_id"):
				from = int(m["identity_steam_id"])
			var v = bytes_to_var(m.get("payload", PackedByteArray()))
			if v is Array:
				out.append(["steam:%d" % from, v])
	return out
