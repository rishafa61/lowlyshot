extends Control

signal dialog_closed
signal lobby_joined(lobby_id: int)

var list_box: VBoxContainer
var lbl_status: Label
var btn_refresh: Button

func _ready() -> void:
	_build_ui()
	_update_bounds()
	get_viewport().size_changed.connect(_update_bounds)
	_connect_steam()
	refresh_lobbies()

func _update_bounds() -> void:
	set_deferred("size", get_viewport_rect().size)

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
	panel.custom_minimum_size = Vector2(520, 420)
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
	title.text = "ACTIVE MULTIPLAYER LOBBIES"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "Click a squad below to join your friend's room instantly:"
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	lbl_status = Label.new()
	lbl_status.text = "Searching for lobbies..."
	lbl_status.add_theme_font_size_override("font_size", 13)
	lbl_status.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	vbox.add_child(lbl_status)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(470, 220)
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

func _connect_steam() -> void:
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync and steam_sync.has_signal("lobbies_refreshed"):
		steam_sync.lobbies_refreshed.connect(_on_lobbies_received)

func refresh_lobbies() -> void:
	for c in list_box.get_children():
		c.queue_free()
	lbl_status.text = "Querying Steam for active rooms..."
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
	
	if lobbies.is_empty():
		lbl_status.text = "No active lobbies found. Have your friend create one, or copy/paste their code!"
		return

	lbl_status.text = "Found %d active room(s):" % lobbies.size()
	var steam = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	for lobby_id in lobbies:
		var lid: int = int(lobby_id)
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
