extends Control

@onready var btn_left_play = $LeftNav/VBoxContainer/BtnPlay
@onready var btn_giant_play = $RightPanel/VBoxContainer/GiantPlayBtn
@onready var btn_loadout = $LeftNav/VBoxContainer/BtnLoadout
@onready var btn_operator = $LeftNav/VBoxContainer/BtnOperator
@onready var btn_quit = $LeftNav/VBoxContainer/BtnSetting # Repurposed briefly to test exit if needed, or just let it do nothing
@onready var character_pivot = $"3DEnvironment"


# Play Overlay Nodes
@onready var play_overlay = $PlayOverlay
@onready var btn_close_play = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/Sidebar/BtnClosePlay
@onready var btn_campaign = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/Sidebar/BtnCampaign
@onready var btn_practice = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/Sidebar/BtnPractice
@onready var btn_multiplayer = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/Sidebar/BtnMultiplayer

@onready var map_list = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/MapArea/MapList
@onready var map_desc = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/MapArea/MapDesc
@onready var btn_start_game = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/MapArea/MarginStart/BtnStartGame

@onready var party_ui = $PartyUI
@onready var party_slots: Array = [$PartyUI/Slot1, $PartyUI/Slot2, $PartyUI/Slot3, $PartyUI/Slot4]
# standby slot 3D bodies removed: lobby keeps host pedestal; joined players show in-match only.
# ponytail: spawn in-match peer bodies from player_spawner on peer_connected / match join; add when netcode lands.

var selected_mode = "Practice"
var maps = {
	"Campaign": [
		{"name": "Operation Sandstorm", "scene": "res://scenes/levels/campaign_map.tscn", "desc": "Infiltrate the trench, eliminate 5 hostiles, and reach the extraction zone."}
	],
	"Practice": [
		{"name": "Test Arena", "scene": "res://scenes/levels/test_arena.tscn", "desc": "A simple sandbox arena to practice movement and aim."}
	],
	"Multiplayer": [
		{"name": "Team Deathmatch", "scene": "res://scenes/levels/multiplayer_arena.tscn", "desc": "5v5 Arena. Pick a side, eliminate the enemy team."}
	]
}

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Back in the menu = leave any online match (closes the peer; every return path ends here)
	var _ss = get_node_or_null("/root/SteamSync")
	if _ss and _ss.has_method("leave_steam_game"):
		_ss.leave_steam_game()
	# Root Control has no parent Control (child of Viewport Window):
	# anchors do not auto-size root, so pin to 0 and match window via deferred + resize signal.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	anchor_right = 0.0
	anchor_bottom = 0.0
	call_deferred("_apply_root_size")
	get_viewport().size_changed.connect(_apply_root_size)
	btn_left_play.pressed.connect(_on_play_pressed)
	btn_giant_play.pressed.connect(_on_play_pressed)
	btn_loadout.pressed.connect(_on_loadout_pressed)
	btn_operator.pressed.connect(_on_operator_pressed)
	btn_quit.pressed.connect(_on_setting_pressed)

	play_overlay.hide()
	btn_close_play.pressed.connect(func():
		play_overlay.hide()
		party_ui.show()
	)
	
	btn_campaign.pressed.connect(func(): set_play_mode("Campaign"))
	btn_practice.pressed.connect(func(): set_play_mode("Practice"))
	btn_multiplayer.pressed.connect(func(): set_play_mode("Multiplayer"))
	
	map_list.item_selected.connect(_on_map_selected)
	btn_start_game.pressed.connect(_on_start_game_pressed)
	
	set_play_mode("Practice")
	_init_party_system()

func _init_party_system() -> void:
	for i in party_slots.size():
		var slot_ui = party_slots[i]
		slot_ui.setup(i)
		slot_ui.invite_pressed.connect(_on_party_invite)
		slot_ui.kick_pressed.connect(_on_party_kick)
	
	# Bottom squad action bar: guaranteed visible & clickable on any resolution
	var squad_bar := HBoxContainer.new()
	squad_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	squad_bar.add_theme_constant_override("separation", 16)
	squad_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	squad_bar.offset_top = -64
	squad_bar.offset_bottom = -16
	squad_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	party_ui.add_child(squad_bar)

	var btn_invite := Button.new()
	btn_invite.text = "➕ INVITE FRIENDS"
	btn_invite.custom_minimum_size = Vector2(160, 42)
	btn_invite.pressed.connect(func(): _on_party_invite(0))
	squad_bar.add_child(btn_invite)

	var btn_browse := Button.new()
	btn_browse.text = "🔍 BROWSE ROOMS"
	btn_browse.custom_minimum_size = Vector2(160, 42)
	btn_browse.pressed.connect(func():
		var sync = get_node_or_null("/root/SteamSync")
		if sync and sync.has_method("open_lobby_browser_dialog"):
			sync.open_lobby_browser_dialog()
		else:
			_toast("SteamSync failed to load - check steam_sync.log / the console window")
	)
	squad_bar.add_child(btn_browse)

	var btn_copy := Button.new()
	btn_copy.text = "📋 COPY LOBBY CODE"
	btn_copy.custom_minimum_size = Vector2(170, 42)
	btn_copy.pressed.connect(func():
		var sync = get_node_or_null("/root/SteamSync")
		if sync == null:
			_toast("SteamSync failed to load - check steam_sync.log / the console window")
			return
		var lid: int = sync.get_lobby_id()
		if lid != 0:
			DisplayServer.clipboard_set(str(lid))
			btn_copy.text = "✓ COPIED!"
			get_tree().create_timer(2.0).timeout.connect(func():
				if is_instance_valid(btn_copy):
					btn_copy.text = "📋 COPY LOBBY CODE"
			)
		elif sync.is_steam_running:
			_toast("Creating your Steam lobby... click again in a second")
		else:
			_toast(sync.last_status if sync.last_status != "" else "Steam is not connected")
	)
	squad_bar.add_child(btn_copy)

	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync:
		steam_sync.party_member_joined.connect(_on_steam_friend_joined)
		steam_sync.party_member_left.connect(_on_steam_friend_left)
		for member in steam_sync.party_members:
			_on_steam_friend_joined(member.get("id", 0), member.get("name", ""))

var _toast_label: Label
var _toast_token: int = 0

## Small on-screen message so a failing button is never a silent no-op in exported builds.
func _toast(msg: String) -> void:
	print("[MainMenu] ", msg)
	if _toast_label == null or not is_instance_valid(_toast_label):
		_toast_label = Label.new()
		_toast_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_toast_label.offset_top = -112
		_toast_label.offset_bottom = -72
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_toast_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_toast_label.add_theme_constant_override("outline_size", 6)
		_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		party_ui.add_child(_toast_label)
	_toast_label.text = msg
	_toast_label.show()
	_toast_token += 1
	var token := _toast_token
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_instance_valid(_toast_label) and _toast_token == token:
			_toast_label.hide()
	)

func _on_party_invite(_slot_idx: int) -> void:
	# Always open the in-game dialog directly — never a silent no-op.
	print("[INVITE] slot clicked, opening dialog")
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync and steam_sync.has_method("open_friend_invite_dialog"):
		steam_sync.open_friend_invite_dialog()
		return
	_toast("SteamSync failed to load - check steam_sync.log / the console window")
	# ponytail: lobby slot fills only from real join (_on_steam_friend_joined); add fallback backfill when offline co-op lands.

func _on_steam_friend_joined(steam_id: int, member_name: String) -> void:
	if member_name.is_empty():
		return
	print("Steam friend joined party: %s (ID: %d)" % [member_name, steam_id])
	for i in party_slots.size():
		if not party_slots[i].is_filled:
			party_slots[i].fill(member_name)
			return

func _on_steam_friend_left(steam_id: int) -> void:
	print("Steam friend left party (ID: %d)" % steam_id)
	var steam = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	var target_name = steam.getFriendPersonaName(steam_id) if steam else str(steam_id)
	for i in party_slots.size():
		if party_slots[i].is_filled and (party_slots[i].player_name == target_name or party_slots[i].player_name == str(steam_id)):
			_on_party_kick(i)
			return

func _on_party_kick(slot_idx: int) -> void:
	party_slots[slot_idx].clear()


func _process(delta):
	# Slowly rotate the character pedestal for visual flair
	character_pivot.rotation.y += 0.2 * delta

func _on_play_pressed():
	play_overlay.show()
	party_ui.hide()

func set_play_mode(mode: String):
	selected_mode = mode
	
	# Highlight sidebar
	btn_campaign.modulate = Color(1, 1, 1, 1)
	btn_practice.modulate = Color(1, 1, 1, 1)
	btn_multiplayer.modulate = Color(1, 1, 1, 1)
	
	if mode == "Campaign": btn_campaign.modulate = Color(1, 0.8, 0.2, 1)
	if mode == "Practice": btn_practice.modulate = Color(1, 0.8, 0.2, 1)
	if mode == "Multiplayer": btn_multiplayer.modulate = Color(1, 0.8, 0.2, 1)
	
	# Populate map list
	map_list.clear()
	for m in maps[mode]:
		map_list.add_item(m["name"])
	
	# Select first by default
	if map_list.item_count > 0:
		map_list.select(0)
		_on_map_selected(0)

func _on_map_selected(index: int):
	var map_data = maps[selected_mode][index]
	map_desc.text = map_data["desc"]
	
	# Disable start button if scene is empty (Coming Soon)
	btn_start_game.disabled = (map_data["scene"] == "")

func _on_start_game_pressed():
	var items = map_list.get_selected_items()
	if items.size() > 0:
		var map_data = maps[selected_mode][items[0]]
		if map_data["scene"] != "":
			if selected_mode == "Campaign":
				GlobalSettings.current_minimap = "res://assets/textures/minimap.png"
			else:
				GlobalSettings.current_minimap = ""
			
			var steam_sync = get_node_or_null("/root/SteamSync")
			# Guard: if in a Steam party lobby and not the host, block match start
			if steam_sync and steam_sync.current_lobby_id != 0 and not steam_sync.is_lobby_host():
				btn_start_game.text = "ONLY HOST CAN START"
				var t = get_tree().create_timer(2.0)
				t.timeout.connect(func(): if is_instance_valid(btn_start_game): btn_start_game.text = "START GAME")
				return

			# Multiplayer AND Practice (training ground): party follows the host in
			var should_host_steam = steam_sync and selected_mode in ["Multiplayer", "Practice"] and steam_sync.party_members.size() > 0
			if should_host_steam and steam_sync.is_steam_running and ClassDB.class_exists("SteamMultiplayerPeer"):
				steam_sync.start_steam_host(map_data["scene"])
				get_tree().change_scene_to_file(map_data["scene"])
				return
			get_tree().change_scene_to_file(map_data["scene"])


func _on_loadout_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/loadout_menu.tscn")

func _on_setting_pressed():
	GlobalSettings.previous_scene = "res://scenes/ui/main_menu.tscn"
	get_tree().change_scene_to_file("res://scenes/ui/settings_menu.tscn")

func _on_operator_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/operator_menu.tscn")

func _apply_root_size() -> void:
	# Run after layout pass so nothing overrides size back to 64x64.
	await get_tree().process_frame
	var vp_size = get_viewport_rect().size
	size = vp_size
	if is_instance_valid(party_ui):
		party_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		party_ui.size = vp_size
