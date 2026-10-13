extends Control

signal dialog_closed
signal lobby_joined(lobby_id: int)

var list_box: VBoxContainer
var lbl_status: Label
var btn_refresh: Button
var toggle_open_lobby: CheckButton
var line_code: LineEdit
var btn_join_code: Button

func _ready() -> void:
	_build_ui()
	_update_bounds()
	get_viewport().size_changed.connect(_update_bounds)
	_connect_steam()
	refresh_lobbies()

func _update_bounds() -> void:
	# FULL_RECT anchors auto-size to the CanvasLayer viewport; no manual size.
	pass

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 480)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, 24)
	for m in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "MULTIPLAYER ROOMS"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Host toggle: Open Lobby on/off
	var host_box := HBoxContainer.new()
	host_box.alignment = BoxContainer.ALIGNMENT_CENTER
	host_box.add_theme_constant_override("separation", 12)
	vbox.add_child(host_box)

	toggle_open_lobby = CheckButton.new()
	var steam_sync = get_node_or_null("/root/SteamSync")
	var is_open: bool = steam_sync.is_lobby_open() if steam_sync else false
	toggle_open_lobby.text = "OPEN LOBBY (public in list)"
	toggle_open_lobby.button_pressed = is_open
	toggle_open_lobby.toggled.connect(_on_open_toggled)
	host_box.add_child(toggle_open_lobby)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Direct code entry (for joining closed/unlisted rooms)
	var code_box := HBoxContainer.new()
	code_box.add_theme_constant_override("separation", 8)
	vbox.add_child(code_box)

	line_code = LineEdit.new()
	line_code.placeholder_text = "Paste lobby code here..."
	line_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_code.clear_button_enabled = true
	code_box.add_child(line_code)

	btn_join_code = Button.new()
	btn_join_code.text = "JOIN BY CODE"
	btn_join_code.custom_minimum_size = Vector2(130, 32)
	btn_join_code.pressed.connect(_on_join_code_pressed)
	code_box.add_child(btn_join_code)

	lbl_status = Label.new()
	lbl_status.text = "Searching for open lobbies..."
	lbl_status.add_theme_font_size_override("font_size", 13)
	lbl_status.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	vbox.add_child(lbl_status)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(list_box)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_hbox)

	btn_refresh = Button.new()
	btn_refresh.text = "REFRESH LIST"
	btn_refresh.custom_minimum_size = Vector2(140, 36)
	btn_refresh.pressed.connect(refresh_lobbies)
	btn_hbox.add_child(btn_refresh)

	var btn_close := Button.new()
	btn_close.text = "CLOSE"
	btn_close.custom_minimum_size = Vector2(100, 36)
	btn_close.pressed.connect(func():
		dialog_closed.emit()
		queue_free()
	)
	btn_hbox.add_child(btn_close)

func _on_open_toggled(pressed: bool) -> void:
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync and steam_sync.has_method("set_lobby_open"):
		var ok: bool = steam_sync.set_lobby_open(pressed)
		if ok:
			lbl_status.text = "Your lobby is now %s." % ("OPEN to public" if pressed else "CLOSED (code only)")
		else:
			toggle_open_lobby.button_pressed = !pressed
			lbl_status.text = "Only the room host can toggle lobby visibility."

func _on_join_code_pressed() -> void:
	var raw := line_code.text.strip_edges()
	if not raw.is_valid_int() or raw.to_int() <= 0:
		lbl_status.text = "Invalid lobby code. Paste numeric code copied from host."
		return
	_join_selected(raw.to_int())

func _connect_steam() -> void:
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync and steam_sync.has_signal("lobbies_refreshed"):
		steam_sync.lobbies_refreshed.connect(_on_lobbies_received)

func refresh_lobbies() -> void:
	for c in list_box.get_children():
		c.queue_free()
	lbl_status.text = "Querying Steam for open rooms..."
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync == null or not steam_sync.has_method("refresh_lobby_list"):
		lbl_status.text = "Steam not connected (SteamSync missing)."
	elif not steam_sync.is_steam_running:
		lbl_status.text = steam_sync.last_status if steam_sync.last_status != "" else "Steam not connected."
	else:
		steam_sync.refresh_lobby_list()

func _on_lobbies_received(lobbies: Array) -> void:
	for c in list_box.get_children():
		c.queue_free()
	
	# Strict client-side deduplication by numeric ID
	var seen: Dictionary = {}
	var unique: Array = []
	for lid in lobbies:
		var k := int(lid)
		if not seen.has(k):
			seen[k] = true
			unique.append(k)

	if unique.is_empty():
		lbl_status.text = "No open lobbies found. If room is closed, paste host code above."
		return

	lbl_status.text = "Found %d open room(s):" % unique.size()
	var steam = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	for lid in unique:
		var host_name = steam.getLobbyData(lid, "host_name") if steam else "Host"
		var room_name = steam.getLobbyData(lid, "name") if steam else "Tactical Match"
		var count = steam.getNumLobbyMembers(lid) if steam else 1
		if host_name.is_empty(): host_name = "Player"
		if room_name.is_empty(): room_name = "%s's Squad" % host_name

		var row := PanelContainer.new()
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		row.add_child(hbox)

		var lbl := Label.new()
		lbl.text = "🎮 %s (%d/10 players)" % [room_name, count]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(lbl)

		var btn_join := Button.new()
		btn_join.text = "JOIN"
		btn_join.custom_minimum_size = Vector2(80, 32)
		var target_id = lid
		btn_join.pressed.connect(func(): _join_selected(target_id))
		hbox.add_child(btn_join)

		list_box.add_child(row)

func _join_selected(target_id: int) -> void:
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync and steam_sync.has_method("join_lobby_by_id"):
		steam_sync.join_lobby_by_id(target_id)
		lobby_joined.emit(target_id)
		dialog_closed.emit()
		queue_free()
