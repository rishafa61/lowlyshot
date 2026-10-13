extends Control

## In-game invite panel: friend list + manual lobby code fallback.
## Overlay-independent: works in standalone exports where Shift+Tab is blocked.

signal invite_sent(steam_id: int, friend_name: String)
signal dialog_closed

var friend_ids: Array = []
var list_box: VBoxContainer
var lbl_status: Label
var lbl_lobby: Label
var input_code: LineEdit

func _ready() -> void:
	_build_ui()
	_update_bounds()
	get_viewport().size_changed.connect(_update_bounds)
	refresh_friends()
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync and steam_sync.has_signal("lobby_joined"):
		steam_sync.lobby_joined.connect(_on_lobby_ready)

func _update_bounds() -> void:
	# FULL_RECT anchors auto-size to the CanvasLayer viewport; no manual size.
	pass

func _on_lobby_ready(_lobby_id: int) -> void:
	_refresh_lobby_label()
	refresh_friends()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 420)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, 20)
	for m in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "INVITE FRIEND"
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	# --- Your lobby code (friend can paste this on their PC) ---
	lbl_lobby = Label.new()
	lbl_lobby.add_theme_font_size_override("font_size", 14)
	vbox.add_child(lbl_lobby)
	_refresh_lobby_label()

	var btn_copy := Button.new()
	btn_copy.text = "COPY LOBBY CODE"
	btn_copy.pressed.connect(_on_copy_code)
	vbox.add_child(btn_copy)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	lbl_status = Label.new()
	lbl_status.text = "Loading friends..."
	lbl_status.add_theme_font_size_override("font_size", 14)
	vbox.add_child(lbl_status)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(list_box)

	# --- Join by code (for the joining friend) ---
	var lbl_join := Label.new()
	lbl_join.text = "Got a code from your friend? Paste it here:"
	lbl_join.add_theme_font_size_override("font_size", 14)
	vbox.add_child(lbl_join)

	input_code = LineEdit.new()
	input_code.placeholder_text = "e.g. 109775244771794684"
	vbox.add_child(input_code)

	var btn_join := Button.new()
	btn_join.text = "JOIN LOBBY"
	btn_join.pressed.connect(_on_join_code)
	vbox.add_child(btn_join)

	var hbox_actions := HBoxContainer.new()
	hbox_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_actions.add_theme_constant_override("separation", 10)
	vbox.add_child(hbox_actions)

	var btn_browse := Button.new()
	btn_browse.text = "🔍 BROWSE ACTIVE ROOMS"
	btn_browse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_browse.pressed.connect(_on_browse_rooms)
	hbox_actions.add_child(btn_browse)

	var btn_close := Button.new()
	btn_close.text = "CLOSE"
	btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_close.pressed.connect(func():
		dialog_closed.emit()
		queue_free()
	)
	hbox_actions.add_child(btn_close)

func _refresh_lobby_label() -> void:
	var steam_sync = get_node_or_null("/root/SteamSync")
	var lid = steam_sync.get_lobby_id() if steam_sync else 0
	if lid != 0:
		lbl_lobby.text = "Lobby code: %d" % lid
	elif steam_sync and steam_sync.is_steam_running:
		lbl_lobby.text = "Lobby code: creating..."
	else:
		lbl_lobby.text = "Lobby code: (Steam not connected)"

func _on_copy_code() -> void:
	var steam_sync = get_node_or_null("/root/SteamSync")
	var lid = steam_sync.get_lobby_id() if steam_sync else 0
	if lid == 0:
		if steam_sync and steam_sync.last_status != "":
			lbl_status.text = steam_sync.last_status
		else:
			lbl_status.text = "No lobby code yet. Wait a moment and retry."
		return
	DisplayServer.clipboard_set(str(lid))
	lbl_status.text = "Lobby code copied! Send it to your friend."

func _on_join_code() -> void:
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync == null:
		return
	var code = input_code.text.strip_edges()
	if code.is_empty() or not code.is_valid_int():
		lbl_status.text = "Enter a valid numeric lobby code."
		return
	if steam_sync.join_lobby_by_id(int(code)):
		lbl_status.text = "Joining lobby..."
	else:
		lbl_status.text = "Failed to join. Check the code."

func _on_browse_rooms() -> void:
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync and steam_sync.has_method("open_lobby_browser_dialog"):
		dialog_closed.emit()
		queue_free()
		steam_sync.open_lobby_browser_dialog()

func refresh_friends() -> void:
	for c in list_box.get_children():
		c.queue_free()
	friend_ids.clear()

	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync == null or not steam_sync.is_steam_running or not Engine.has_singleton("Steam"):
		if steam_sync and steam_sync.last_status != "":
			lbl_status.text = steam_sync.last_status
		else:
			lbl_status.text = "Steam not running. Start Steam and restart."
		return
	var steam = Engine.get_singleton("Steam")
	# 0x0004 = k_EFriendFlagImmediate (regular friends)
	var count = steam.getFriendCount(0x0004)
	if count <= 0:
		lbl_status.text = "No friends found. Add friends on Steam first."
		return
	lbl_status.text = "Friends — click to invite:"
	for i in range(count):
		var f_id = steam.getFriendByIndex(i, 0x0004)
		var f_name = steam.getFriendPersonaName(f_id)
		var f_state = steam.getFriendPersonaState(f_id) # 0 offline, 1 online...
		friend_ids.append(f_id)
		var btn := Button.new()
		var state_str = "●" if f_state == 1 else "○"
		btn.text = "%s %s" % [state_str, f_name]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var fid = f_id
		var fname = f_name
		btn.pressed.connect(func(): _send_invite(fid, fname, btn))
		list_box.add_child(btn)

func _send_invite(fid: int, fname: String, btn: Button) -> void:
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync == null or not steam_sync.has_method("invite_friend_to_lobby"):
		return
	var ok = steam_sync.invite_friend_to_lobby(fid)
	if ok:
		btn.text = "✓ Invited: " + fname
		btn.disabled = true
		invite_sent.emit(fid, fname)
	else:
		btn.text = "✗ Failed: " + fname
