extends CanvasLayer
class_name MultiplayerHUD

# ponytail: UI built in code to dodge .tscn node-resolution flakiness.
# If you want a designer-editable scene later, recreate nodes here in the editor and delete _build_ui().

var manager: MultiplayerManager

var round_label: Label
var timer_label: Label
var objective_label: Label
var scoreboard: Control
var scoreboard_list: Container
var scoreboard_title: Label
var side_picker: Control
var btn_attackers: Button
var btn_defenders: Button
var match_end_overlay: Control
var match_end_title: Label
var match_end_score: Label
var lbl_team_full: Label
var match_end_return: Button

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	btn_attackers.pressed.connect(func(): pick_side("attackers"))
	btn_defenders.pressed.connect(func(): pick_side("defenders"))
	if get_parent() is MultiplayerManager:
		setup(get_parent() as MultiplayerManager)

func _build_ui() -> void:
	# Top-center match status box (VBox owns layout so labels never overlap)
	var top_center := VBoxContainer.new()
	top_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_center.alignment = BoxContainer.ALIGNMENT_CENTER
	top_center.position = Vector2(-160, 10)
	top_center.custom_minimum_size = Vector2(320, 0)
	top_center.add_theme_constant_override("separation", 0)
	add_child(top_center)

	objective_label = Label.new()
	objective_label.text = "Waiting for players..."
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.add_theme_font_size_override("font_size", 20)
	top_center.add_child(objective_label)

	round_label = Label.new()
	round_label.text = "DEATHMATCH"
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.add_theme_font_size_override("font_size", 22)
	top_center.add_child(round_label)

	timer_label = Label.new()
	timer_label.text = "10:00"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 32)
	top_center.add_child(timer_label)

	# Scoreboard (hold TAB)
	scoreboard = Control.new()
	scoreboard.set_anchors_preset(Control.PRESET_FULL_RECT)
	scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard.visible = false
	add_child(scoreboard)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 360)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	scoreboard_title = Label.new()
	scoreboard_title.text = "TEAM DEATHMATCH (Hold TAB)"
	scoreboard_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_title.add_theme_font_size_override("font_size", 18)
	scoreboard_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(scoreboard_title)

	var hsep := HSeparator.new()
	hsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hsep)

	# 2-column split: Attackers (Blue) vs Defenders (Red)
	scoreboard_list = HBoxContainer.new()
	scoreboard_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scoreboard_list.add_theme_constant_override("separation", 16)
	scoreboard_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(scoreboard_list)

	# Side picker overlay
	side_picker = Control.new()
	side_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(side_picker)

	var darken := ColorRect.new()
	darken.set_anchors_preset(Control.PRESET_FULL_RECT)
	darken.color = Color(0.04, 0.04, 0.06, 0.85)
	side_picker.add_child(darken)

	var s_center := CenterContainer.new()
	s_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	side_picker.add_child(s_center)

	var s_box := VBoxContainer.new()
	s_box.add_theme_constant_override("separation", 15)
	s_box.alignment = BoxContainer.ALIGNMENT_CENTER
	s_center.add_child(s_box)

	var title := Label.new()
	title.text = "CHOOSE YOUR SIDE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	s_box.add_child(title)

	btn_attackers = Button.new()
	btn_attackers.custom_minimum_size = Vector2(280, 50)
	btn_attackers.text = "ATTACKERS (Blue)"
	s_box.add_child(btn_attackers)

	btn_defenders = Button.new()
	btn_defenders.custom_minimum_size = Vector2(280, 50)
	btn_defenders.text = "DEFENDERS (Red)"
	s_box.add_child(btn_defenders)

	# Team-full notice (replaces the _toast helper main menu has, not HUD)
	lbl_team_full = Label.new()
	lbl_team_full.text = ""
	lbl_team_full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_team_full.add_theme_font_size_override("font_size", 20)
	lbl_team_full.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	s_box.add_child(lbl_team_full)

	# Match End Overlay
	match_end_overlay = Control.new()
	match_end_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	match_end_overlay.visible = false
	add_child(match_end_overlay)

	var end_darken := ColorRect.new()
	end_darken.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_darken.color = Color(0.04, 0.04, 0.07, 0.9)
	match_end_overlay.add_child(end_darken)

	var end_center := CenterContainer.new()
	end_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	match_end_overlay.add_child(end_center)

	var end_box := VBoxContainer.new()
	end_box.add_theme_constant_override("separation", 18)
	end_box.alignment = BoxContainer.ALIGNMENT_CENTER
	end_center.add_child(end_box)

	match_end_title = Label.new()
	match_end_title.text = "VICTORY"
	match_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_end_title.add_theme_font_size_override("font_size", 44)
	end_box.add_child(match_end_title)

	match_end_score = Label.new()
	match_end_score.text = "Attackers 30 — Defenders 24"
	match_end_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_end_score.add_theme_font_size_override("font_size", 22)
	end_box.add_child(match_end_score)

	match_end_return = Button.new()
	match_end_return.text = "RETURN TO LOBBY"
	match_end_return.custom_minimum_size = Vector2(240, 48)
	match_end_return.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	)
	end_box.add_child(match_end_return)

func _mk_label(pos: Vector2, font_size: int, text: String) -> Label:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	add_child(l)
	return l

func setup(mgr: MultiplayerManager) -> void:
	manager = mgr
	mgr.match_state_changed.connect(_on_state_changed)
	mgr.time_tick.connect(_on_time_tick)
	mgr.players_data_synced.connect(_on_scoreboard_sync)
	refresh_scoreboard()
	update_header()

func _on_scoreboard_sync(_d: Dictionary, _s: Dictionary, _m: Dictionary = {}) -> void:
	refresh_scoreboard()
	update_header()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:
		return
	if event.keycode != KEY_TAB:
		return
	# Scoreboard shows while cursor stays hidden and camera stays captured
	scoreboard.visible = event.pressed
	if scoreboard.visible:
		refresh_scoreboard()

func _on_state_changed(state: int) -> void:
	match state:
		MultiplayerManager.MatchState.WAITING:
			objective_label.text = "Waiting for players..."
		MultiplayerManager.MatchState.WARMUP:
			objective_label.text = "Round starting..."
		MultiplayerManager.MatchState.ACTIVE:
			update_header()
		MultiplayerManager.MatchState.ROUND_END:
			objective_label.text = "Round Over"
		MultiplayerManager.MatchState.MATCH_END:
			objective_label.text = "Match Over"
			_show_match_end_screen()
		_:
			objective_label.text = "Objective"

func _show_match_end_screen() -> void:
	if not manager:
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var a = manager.team_scores.get("attackers", 0)
	var d = manager.team_scores.get("defenders", 0)
	var local_team = "attackers"
	if manager.match_stats.has("Player"):
		local_team = manager.match_stats["Player"].get("team", "attackers")

	var is_win = (local_team == "attackers" and a > d) or (local_team == "defenders" and d > a)
	var is_draw = (a == d)

	if is_draw:
		match_end_title.text = "DRAW"
		match_end_title.modulate = Color(0.9, 0.85, 0.3)
	elif is_win:
		match_end_title.text = "VICTORY"
		match_end_title.modulate = Color(0.3, 0.9, 0.4)
	else:
		match_end_title.text = "DEFEAT"
		match_end_title.modulate = Color(0.95, 0.3, 0.3)

	match_end_score.text = "Attackers %d  —  %d Defenders" % [a, d]
	scoreboard.visible = true
	match_end_overlay.visible = true

func _on_time_tick(t: int) -> void:
	var mins = floori(float(t) / 60.0)
	var secs = t % 60
	timer_label.text = "%d:%02d" % [mins, secs]

func update_header() -> void:
	if not manager:
		return
	var a = manager.team_scores.get("attackers", 0)
	var d = manager.team_scores.get("defenders", 0)
	objective_label.text = "ATT %d — %d DEF   |   First to %d" % [a, d, manager.target_kills]

func refresh_scoreboard() -> void:
	if not scoreboard_list:
		return
	for c in scoreboard_list.get_children():
		c.queue_free()
	if not manager:
		return
	var a = manager.team_scores.get("attackers", 0)
	var d = manager.team_scores.get("defenders", 0)
	scoreboard_title.text = "TEAM DEATHMATCH   —   ATTACKERS %d : %d DEFENDERS" % [a, d]
	var ally_names: Array = []
	var enemy_names: Array = []

	# Pull all stats from match_stats (covers players AND bots)
	var stats: Dictionary = manager.match_stats if manager.match_stats else {}
	for entry_name in stats.keys():
		var s: Dictionary = stats[entry_name]
		var kills: int = s.get("kills", 0)
		var deaths: int = s.get("deaths", 0)
		var team: String = s.get("team", "attackers")
		var display = "%s (K:%d D:%d)" % [entry_name, kills, deaths]
		if team == "attackers":
			if entry_name == "Player":
				display = "You (K:%d D:%d)" % [kills, deaths]
			ally_names.append(display)
		else:
			if entry_name == "Player":
				display = "You (K:%d D:%d)" % [kills, deaths]
			enemy_names.append(display)

	# Two team columns
	var attackers_box := VBoxContainer.new()
	attackers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attackers_box.add_theme_constant_override("separation", 4)
	attackers_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_list.add_child(attackers_box)

	var defenders_box := VBoxContainer.new()
	defenders_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	defenders_box.add_theme_constant_override("separation", 4)
	defenders_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_list.add_child(defenders_box)

	var a_head := Label.new()
	a_head.text = "ATTACKERS — %d" % manager.team_scores.get("attackers", 0)
	a_head.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	a_head.add_theme_font_size_override("font_size", 17)
	a_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	attackers_box.add_child(a_head)

	var d_head := Label.new()
	d_head.text = "DEFENDERS — %d" % manager.team_scores.get("defenders", 0)
	d_head.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	d_head.add_theme_font_size_override("font_size", 17)
	d_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	defenders_box.add_child(d_head)

	# Pad shorter column so rows line up horizontally
	var max_rows = max(ally_names.size(), enemy_names.size())
	while ally_names.size() < max_rows:
		ally_names.append("")
	while enemy_names.size() < max_rows:
		enemy_names.append("")

	for i in max_rows:
		attackers_box.add_child(_mk_row(str(ally_names[i]), Color(0.5, 0.85, 1.0)))
		defenders_box.add_child(_mk_row(str(enemy_names[i]), Color(1.0, 0.6, 0.5)))

func _mk_row(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text if text != "" else "—"
	l.modulate = color if text != "" else Color(1, 1, 1, 0.15)
	l.add_theme_font_size_override("font_size", 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func bot_display_name(bot: Node) -> String:
	var n = bot.get("bot_name")
	if n != null and str(n) != "":
		return str(n)
	return str(bot.name)

func pick_side(team: String) -> void:
	if not manager:
		return
	if multiplayer.has_multiplayer_peer():
		# Cap humans at 5 per side: full team stays on picker with notice
		if not manager.can_join_team(team):
			lbl_team_full.text = "%s IS FULL (5 MAX) — PICK OTHER SIDE" % team.to_upper()
			return
		manager.request_join_team.rpc_id(1, team)
	else:
		manager.request_join_team_local(team)
	side_picker.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
