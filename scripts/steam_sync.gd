extends Node

## Steam Sync singleton: initializes Steamworks (AppID 480 Spacewar),
## handles overlay invites, friends joining, and party synchronization.
##
## IMPORTANT: this script must NEVER reference GodotSteam classes statically
## (Steam.xxx, SteamMultiplayerPeer.new(), ...). If the GodotSteam extension
## fails to load in an export, a static reference makes this whole autoload fail
## to compile and every button that talks to SteamSync silently does nothing.
## Use Engine.get_singleton("Steam") / ClassDB.instantiate() instead.

signal steam_initialized_status(success: bool)
signal party_member_joined(steam_id: int, member_name: String)
signal party_member_left(steam_id: int)
signal lobby_joined(lobby_id: int)
signal lobby_left
signal match_started()
signal match_joined()
signal lobbies_refreshed(lobbies: Array)

const APP_ID: int = 480
const LOBBY_GAME_TAG: String = "FPS_Tactical"
const LOG_PATH: String = "user://steam_sync.log"

const FRIEND_INVITE_DIALOG := preload("res://scenes/ui/friend_invite_dialog.gd")
const LOBBY_BROWSER_DIALOG := preload("res://scenes/ui/lobby_browser_dialog.gd")

var is_steam_running: bool = false
var steam_id: int = 0
var persona_name: String = "Player"
var current_lobby_id: int = 0
var pending_auto_join: int = 0

## Human readable reason shown in the UI when something is not working.
var last_status: String = ""

var _lobby_create_pending: bool = false

# Track party members: Array of { "id": int, "name": String }
var party_members: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE) # truncate old log
	if f:
		f.close()
	_init_steam()

func _log(msg: String) -> void:
	print("[SteamSync] ", msg)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line("%s  %s" % [Time.get_time_string_from_system(), msg])
		f.close()

## multiplayer.has_multiplayer_peer() is ALWAYS true in Godot 4 (a default OfflineMultiplayerPeer
## is installed), so it can't be used to ask "are we in an online match?".
func _has_real_peer() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)

## Returns true if we are the lobby leader or in offline mode (eligible to start matches)
func is_lobby_host() -> bool:
	if current_lobby_id == 0:
		return true
	var steam = _get_steam()
	if steam == null or not is_steam_running:
		return true
	var owner_id: int = steam.getLobbyOwner(current_lobby_id)
	return owner_id == 0 or owner_id == steam_id

func _get_steam() -> Object:
	if Engine.has_singleton("Steam"):
		return Engine.get_singleton("Steam")
	return null

func _init_steam() -> void:
	_log("Godot %s | debug_build=%s | exe=%s" % [Engine.get_version_info().get("string", "?"), OS.is_debug_build(), OS.get_executable_path()])
	var steam = _get_steam()
	if steam == null:
		last_status = "GodotSteam is not loaded (DLL missing/blocked). Steam features disabled."
		_log(last_status)
		steam_initialized_status.emit(false)
		return

	# GodotSteam >= 4.14: steamInit() only returns a bool, steamInitEx() returns
	# a Dictionary {status, verbal}. status 0 == STEAM_API_INIT_RESULT_OK.
	# Passing APP_ID here sets SteamAppId/SteamGameId, so we do NOT depend on a
	# steam_appid.txt sitting next to the exported .exe.
	var init_response = steam.steamInitEx(APP_ID, false)
	_log("steamInitEx(%d) -> %s" % [APP_ID, str(init_response)])

	var ok: bool = false
	var verbal: String = str(init_response)
	if typeof(init_response) == TYPE_DICTIONARY:
		ok = int(init_response.get("status", 1)) == 0
		verbal = str(init_response.get("verbal", init_response))
	elif typeof(init_response) == TYPE_BOOL:
		ok = init_response

	if not ok:
		last_status = "Steam failed to start: %s. Is the Steam client running and logged in?" % verbal
		_log(last_status)
		steam_initialized_status.emit(false)
		return

	is_steam_running = true
	steam_id = steam.getSteamID()
	persona_name = steam.getPersonaName()
	_log("Connected as %s (SteamID: %d)" % [persona_name, steam_id])

	if steam.has_method("initRelayNetworkAccess"):
		steam.initRelayNetworkAccess()

	# Connect callbacks (signal names verified against GodotSteam 4.23)
	var wanted: Dictionary = {
		"join_requested": _on_lobby_join_requested,
		"join_game_requested": _on_rich_presence_join,
		"lobby_created": _on_lobby_created,
		"lobby_joined": _on_lobby_joined_callback,
		"lobby_chat_update": _on_lobby_chat_update,
		"lobby_data_update": _on_lobby_data_update,
		"lobby_message": _on_lobby_message,
		"lobby_match_list": _on_lobby_match_list,
	}
	for sig_name in wanted.keys():
		if steam.has_signal(sig_name):
			steam.connect(sig_name, wanted[sig_name])
		else:
			_log("WARNING: GodotSteam has no signal '%s'" % sig_name)

	steam_initialized_status.emit(true)

	# Check if launched via Steam invite / command line argument
	_check_cmdline_auto_join()

	# If not joining via cmdline, host default lobby
	if pending_auto_join == 0:
		ensure_lobby()

var _poll_timer: float = 0.0
var _last_match_id: String = ""

func _process(delta: float) -> void:
	if is_steam_running:
		var steam = _get_steam()
		if steam:
			steam.run_callbacks()
			# Poll lobby state every 0.5s: failsafe if broadcast packet drops on client
			_poll_timer += delta
			if _poll_timer >= 0.5:
				_poll_timer = 0.0
				_poll_lobby_game_state()

func _poll_lobby_game_state() -> void:
	if current_lobby_id == 0 or _has_real_peer():
		return
	var steam = _get_steam()
	if steam == null:
		return
	var g_state: String = steam.getLobbyData(current_lobby_id, "game_state")
	var host_id_str: String = steam.getLobbyData(current_lobby_id, "host_steam_id")
	var match_scene: String = steam.getLobbyData(current_lobby_id, "match_scene")
	var match_id: String = steam.getLobbyData(current_lobby_id, "match_id")
	# match_id changes on every "start": never re-join a match we already left
	if g_state == "starting" and host_id_str != "" and match_id != _last_match_id:
		var host_id: int = host_id_str.to_int()
		if host_id != 0 and host_id != steam_id:
			_last_match_id = match_id
			_log("Poll detected host game_state='starting'. Joining host %d scene %s" % [host_id, match_scene])
			start_steam_client(host_id, match_scene)

## Opens the Steam friend invite overlay AND in-game friend dialog
func open_invite_overlay() -> void:
	# Always show in-game picker FIRST: guaranteed visible regardless of Steam state
	open_friend_invite_dialog()

	if not is_steam_running:
		return

	var steam = _get_steam()
	await get_tree().create_timer(0.3).timeout
	if steam != null:
		if current_lobby_id != 0:
			steam.activateGameOverlayInviteDialog(current_lobby_id)
		else:
			steam.activateGameOverlay("Friends")

## Lobby id of our current party lobby. Lazily (re)creates one if missing.
func get_lobby_id() -> int:
	if current_lobby_id == 0:
		ensure_lobby()
	return current_lobby_id

## Join a lobby by numeric ID (manual code entry fallback, no overlay needed)
func join_lobby_by_id(lobby_id: int) -> bool:
	var steam = _get_steam()
	if not is_steam_running or steam == null:
		return false
	if lobby_id <= 0:
		return false
	# Leave our own empty party lobby first so we don't sit in two lobbies.
	if current_lobby_id != 0 and current_lobby_id != lobby_id:
		steam.leaveLobby(current_lobby_id)
		current_lobby_id = 0
		party_members.clear()
	_log("joinLobby(%d)" % lobby_id)
	steam.joinLobby(lobby_id)
	return true

## Leave the current lobby and return to a solo party
func leave_lobby() -> void:
	var steam = _get_steam()
	if current_lobby_id != 0 and steam != null and is_steam_running:
		_log("leaveLobby(%d)" % current_lobby_id)
		steam.leaveLobby(current_lobby_id)
	current_lobby_id = 0
	party_members.clear()
	if steam and is_steam_running:
		steam.setRichPresence("connect", "")
		steam.setRichPresence("status", "In main menu")
	# Re-create our own empty lobby so friends can still join us later
	ensure_lobby()
	lobby_left.emit()

## Direct lobby invite without overlay: works in non-Steam exports
func invite_friend_to_lobby(friend_id: int) -> bool:
	var steam = _get_steam()
	if not is_steam_running or steam == null:
		return false
	if current_lobby_id == 0:
		_log("No lobby yet; cannot invite friend %d" % friend_id)
		ensure_lobby()
		return false
	# 1. Official Steam lobby invite (triggers Steam chat invite card)
	var ok = steam.inviteUserToLobby(current_lobby_id, friend_id)
	_log("Invite sent to %d: %s" % [friend_id, str(ok)])
	return bool(ok)

## Open in-game friend invite dialog (overlay-independent)
func open_friend_invite_dialog() -> void:
	_open_dialog(FRIEND_INVITE_DIALOG, "FriendInviteCanvas")

## Open in-game lobby browser dialog
func open_lobby_browser_dialog() -> void:
	_open_dialog(LOBBY_BROWSER_DIALOG, "LobbyBrowserCanvas")

func _open_dialog(dialog_script: GDScript, canvas_name: String) -> void:
	var root := get_tree().root
	# Close the other modal first to avoid overlapping dialogs
	var other_name = "LobbyBrowserCanvas" if canvas_name == "FriendInviteCanvas" else "FriendInviteCanvas"
	if root.has_node(other_name):
		root.get_node(other_name).queue_free()
	if root.has_node(canvas_name):
		return
	var canvas := CanvasLayer.new()
	canvas.name = canvas_name
	canvas.layer = 120
	var dialog = dialog_script.new()
	canvas.add_child(dialog)
	dialog.dialog_closed.connect(func(): canvas.queue_free())
	root.add_child(canvas)

## Create a lobby for party joining (no-op if we already have/are creating one).
## Defaults to invisible (private-by-code): only listed when the host opens it.
func ensure_lobby() -> void:
	var steam = _get_steam()
	if not is_steam_running or steam == null:
		return
	if current_lobby_id != 0 or _lobby_create_pending:
		return
	_lobby_create_pending = true
	_log("createLobby(invisible, 10)")
	# 3 = Invisible so the room only shows up after the host toggles "Open Lobby"
	steam.createLobby(3, 10)

## Refresh public lobby browser: friends can join without invite or code
func refresh_lobby_list() -> void:
	var steam = _get_steam()
	if not is_steam_running or steam == null:
		lobbies_refreshed.emit([])
		return
	steam.addRequestLobbyListDistanceFilter(3) # 3 = worldwide (default only returns nearby lobbies)
	steam.addRequestLobbyListStringFilter("game", LOBBY_GAME_TAG, 0) # 0 = EqualTo
	steam.addRequestLobbyListStringFilter("is_open", "1", 0) # only rooms the host opened
	steam.addRequestLobbyListResultCountFilter(50)
	steam.requestLobbyList()

func _on_lobby_match_list(lobbies: Array) -> void:
	# Deduplicate: Steam can return the same room more than once.
	var seen: Dictionary = {}
	var unique: Array = []
	for lid in lobbies:
		var key := int(lid)
		if not seen.has(key):
			seen[key] = true
			unique.append(key)
	_log("Lobby list refreshed: %d lobbies (%d unique)" % [lobbies.size(), unique.size()])
	lobbies_refreshed.emit(unique)

## Host toggles room visibility in the lobby browser. Open = listed publicly;
## closed = invisible, joinable only via lobby code/invite.
func set_lobby_open(open: bool) -> bool:
	var steam = _get_steam()
	if current_lobby_id == 0 or not is_steam_running or steam == null:
		return false
	if not is_lobby_host():
		return false
	steam.setLobbyType(current_lobby_id, 2 if open else 3)
	steam.setLobbyData(current_lobby_id, "is_open", "1" if open else "0")
	steam.setLobbyJoinable(current_lobby_id, true)
	_log("lobby %d set %s" % [current_lobby_id, "OPEN" if open else "CLOSED"])
	return true

func is_lobby_open() -> bool:
	var steam = _get_steam()
	if current_lobby_id == 0 or not is_steam_running or steam == null:
		return false
	return steam.getLobbyData(current_lobby_id, "is_open") == "1"

## Check cmdline args for Steam invite auto-join
## ("+connect_lobby <id>" as two args, "+connect_lobby=<id>", or a raw lobby ID)
func _check_cmdline_auto_join() -> void:
	var args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	_log("cmdline args: %s" % str(args))
	for i in args.size():
		var a: String = args[i]
		var candidate: int = 0
		if a == "+connect_lobby" and i + 1 < args.size():
			candidate = args[i + 1].to_int()
		elif a.begins_with("+connect_lobby"):
			candidate = a.substr("+connect_lobby".length()).strip_edges().trim_prefix("=").to_int()
		elif a.is_valid_int() and a.length() >= 15:
			candidate = a.to_int()
		if candidate > 100000000000000000: # SteamID64 range check
			pending_auto_join = candidate
			_log("Detected cmdline lobby join: %d" % candidate)
			join_lobby_by_id(candidate)
			return

func _on_lobby_created(connect_code: int, lobby_id: int) -> void:
	_lobby_create_pending = false
	var steam = _get_steam()
	if connect_code == 1 and steam != null:
		current_lobby_id = lobby_id
		steam.setLobbyJoinable(lobby_id, true)
		steam.setLobbyData(lobby_id, "game", LOBBY_GAME_TAG)
		steam.setLobbyData(lobby_id, "name", "%s's Tactical Squad" % persona_name)
		steam.setLobbyData(lobby_id, "host_name", persona_name)
		steam.setLobbyData(lobby_id, "host_steam_id", str(steam_id))
		steam.setLobbyData(lobby_id, "game_state", "in_lobby")
		steam.setLobbyData(lobby_id, "is_open", "0") # hidden until host opens it
		# Rich Presence "connect" = friends list shows "Join Game" (not just "Invite to Watch")
		steam.setRichPresence("connect", str(lobby_id))
		steam.setRichPresence("status", "In lobby - inviting friends")
		_log("Party lobby created: %d" % lobby_id)
	else:
		last_status = "Could not create Steam lobby (result code %d). Try again." % connect_code
		_log(last_status)

func _on_lobby_join_requested(lobby_id: int, friend_id: int) -> void:
	_log("Join requested for lobby %d by friend %d" % [lobby_id, friend_id])
	join_lobby_by_id(lobby_id)

func _on_rich_presence_join(friend_id: int, connect_str: String) -> void:
	_log("Rich presence join requested from %d with '%s'" % [friend_id, connect_str])
	if connect_str != "" and connect_str.is_valid_int():
		join_lobby_by_id(connect_str.to_int())

func _on_lobby_joined_callback(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response == 1:
		current_lobby_id = lobby_id
		_log("Successfully joined lobby: %d" % lobby_id)
		var steam = _get_steam()
		if steam:
			steam.setRichPresence("connect", str(lobby_id))
			steam.setRichPresence("status", "In party lobby")
		lobby_joined.emit(lobby_id)
		_refresh_lobby_members()
		# If joining an already-started match, connect immediately
		_poll_lobby_game_state()
	else:
		last_status = "Failed to join lobby (response %d). The room may be full, closed or on another AppID." % response
		_log(last_status)

func _on_lobby_chat_update(_lobby_id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	var steam = _get_steam()
	if not is_steam_running or steam == null:
		return
	var member_name: String = steam.getFriendPersonaName(changed_id)

	# 1 = Joined, 2 = Left, 4 = Disconnected, 8 = Kicked, 16 = Banned
	if chat_state == 1:
		_log("Friend joined lobby: %s" % member_name)
		add_party_member(changed_id, member_name)
	elif chat_state in [2, 4, 8, 16]:
		_log("Friend left lobby: %s" % member_name)
		remove_party_member(changed_id)

func _refresh_lobby_members() -> void:
	var steam = _get_steam()
	if not is_steam_running or steam == null:
		return
	var count: int = steam.getNumLobbyMembers(current_lobby_id)
	for i in range(count):
		var member_id: int = steam.getLobbyMemberByIndex(current_lobby_id, i)
		if member_id != steam_id:
			var m_name: String = steam.getFriendPersonaName(member_id)
			add_party_member(member_id, m_name)

func add_party_member(p_id: int, p_name: String) -> void:
	for m in party_members:
		if m["id"] == p_id:
			return
	party_members.append({"id": p_id, "name": p_name})
	party_member_joined.emit(p_id, p_name)

func remove_party_member(p_id: int) -> void:
	for i in range(party_members.size() - 1, -1, -1):
		if party_members[i]["id"] == p_id:
			party_members.remove_at(i)
			party_member_left.emit(p_id)
			break

## Host launches multiplayer match: starts SteamMultiplayerPeer as server, updates lobby metadata
func start_steam_host(scene_path: String) -> bool:
	if not is_steam_running or not ClassDB.class_exists("SteamMultiplayerPeer"):
		return false
	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_host(0)
	if err != OK:
		push_error("[SteamSync] create_host failed: " + str(err))
		return false
	multiplayer.multiplayer_peer = peer
	_log("Steam server host initialized (peer ID: %d)" % multiplayer.get_unique_id())

	var steam = _get_steam()
	if current_lobby_id != 0 and steam != null:
		steam.setLobbyData(current_lobby_id, "host_steam_id", str(steam_id))
		steam.setLobbyData(current_lobby_id, "match_scene", scene_path)
		var match_id := str(Time.get_ticks_usec())
		steam.setLobbyData(current_lobby_id, "match_id", match_id)
		steam.setLobbyData(current_lobby_id, "game_state", "starting")
		# Direct broadcast to every lobby member — lobby chat messages are
		# guaranteed delivery, unlike lobby data update notifications.
		var msg := "START_GAME|%d|%s|%s" % [steam_id, scene_path, match_id]
		var send_ok = steam.sendLobbyChatMsg(current_lobby_id, msg)
		_log("Sent lobby broadcast (ok=%s): %s" % [str(send_ok), msg])
	match_started.emit()
	return true

## Client connects to Steam host peer: joins match scene
func start_steam_client(host_id: int, match_scene: String) -> bool:
	if not is_steam_running or not ClassDB.class_exists("SteamMultiplayerPeer"):
		return false
	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_client(host_id, 0)
	if err != OK:
		push_error("[SteamSync] create_client failed: " + str(err))
		return false
	multiplayer.multiplayer_peer = peer
	_log("Steam client connected to host: %d (peer ID: %d)" % [host_id, multiplayer.get_unique_id()])
	match_joined.emit()
	if match_scene != "":
		get_tree().change_scene_to_file(match_scene)
	return true

func _on_lobby_message(lobby_id: int, user: int, message: String, _chat_type: int) -> void:
	if lobby_id != current_lobby_id:
		return
	_log("Received lobby message from %d: %s" % [user, message])
	if message.begins_with("START_GAME|"):
		var parts = message.split("|")
		if parts.size() >= 3:
			var host_id = parts[1].to_int()
			var match_scene = parts[2]
			var msg_match_id: String = parts[3] if parts.size() >= 4 else ""
			if host_id != steam_id and not _has_real_peer() and (msg_match_id == "" or msg_match_id != _last_match_id):
				_last_match_id = msg_match_id
				_log("Host started game. Connecting client to host: %d, scene: %s" % [host_id, match_scene])
				start_steam_client(host_id, match_scene)

func _on_lobby_data_update(success: bool, lobby_id: int, _member_id: int) -> void:
	var steam = _get_steam()
	if not success or lobby_id != current_lobby_id or steam == null:
		return
	var g_state: String = steam.getLobbyData(lobby_id, "game_state")
	var host_id_str: String = steam.getLobbyData(lobby_id, "host_steam_id")
	var match_scene: String = steam.getLobbyData(lobby_id, "match_scene")

	# Friend detects host started game: auto connect to host peer and load match scene
	if g_state == "starting" and host_id_str != "":
		var host_id: int = host_id_str.to_int()
		var data_match_id: String = steam.getLobbyData(lobby_id, "match_id")
		if host_id != steam_id and not _has_real_peer() and data_match_id != _last_match_id:
			_last_match_id = data_match_id
			_log("Host started game. Connecting...")
			start_steam_client(host_id, match_scene)

## Close peer and return to lobby state
func leave_steam_game() -> void:
	if _has_real_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null # falls back to the default offline peer
	var steam = _get_steam()
	if current_lobby_id != 0 and is_steam_running and steam != null:
		# only the lobby owner can change lobby data; harmless no-op for clients
		steam.setLobbyData(current_lobby_id, "game_state", "in_lobby")
