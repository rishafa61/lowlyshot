extends CanvasLayer
## Modal player card opened by clicking the top-left profile frame.
## Shows persistent wallet, career KD/A, headshot rate, win rate, and match history.

const UI_PLATE := Color(0.115, 0.125, 0.15, 0.96)
const UI_PLATE_HOVER := Color(0.165, 0.18, 0.21, 0.98)
const UI_ORANGE := Color(1.0, 0.44, 0.08)
const UI_TEXT := Color(0.88, 0.9, 0.93)
const UI_TEXT_DIM := Color(0.6, 0.65, 0.72)

signal closed

func _ready() -> void:
	layer = 120
	_build_ui()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()

func _prof() -> Node:
	return get_node_or_null("/root/PlayerProfile")

func _close() -> void:
	closed.emit()
	queue_free()

func _build_ui() -> void:
	var prof := _prof()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close()
	)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 560)
	var style := StyleBoxFlat.new()
	style.bg_color = UI_PLATE
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = UI_ORANGE
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)
	panel.add_child(main_vbox)

	# --- Header row: avatar badge + name + wallet + close btn ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	main_vbox.add_child(header)

	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(56, 56)
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(0.18, 0.2, 0.25)
	b_style.corner_radius_top_left = 6
	b_style.corner_radius_top_right = 6
	b_style.corner_radius_bottom_left = 6
	b_style.corner_radius_bottom_right = 6
	b_style.border_width_bottom = 3
	b_style.border_color = UI_ORANGE
	badge.add_theme_stylebox_override("panel", b_style)
	var b_lbl := Label.new()
	b_lbl.text = "★"
	b_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b_lbl.add_theme_font_size_override("font_size", 26)
	b_lbl.modulate = UI_ORANGE
	badge.add_child(b_lbl)
	header.add_child(badge)

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 2)
	header.add_child(name_box)

	var p_name := "Player"
	var ss = get_node_or_null("/root/SteamSync")
	if ss and ss.get("persona_name") != null and str(ss.persona_name) != "":
		p_name = str(ss.persona_name)
	var name_lbl := Label.new()
	name_lbl.text = p_name.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_box.add_child(name_lbl)

	var rank_lbl := Label.new()
	rank_lbl.text = "OPERATOR  •  CAREER DOSSIER"
	rank_lbl.add_theme_font_size_override("font_size", 12)
	rank_lbl.modulate = UI_TEXT_DIM
	name_box.add_child(rank_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# Wallet display
	var wallet_box := HBoxContainer.new()
	wallet_box.add_theme_constant_override("separation", 10)
	header.add_child(wallet_box)

	wallet_box.add_child(_pill("CASH", "$ %d" % prof.cash, Color(0.4, 0.9, 0.5)))
	wallet_box.add_child(_pill("GOLD", "★ %d" % prof.gold, Color(1.0, 0.85, 0.2)))

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	# --- Career stats row ---
	var stats_grid := GridContainer.new()
	stats_grid.columns = 4
	stats_grid.add_theme_constant_override("h_separation", 14)
	stats_grid.add_theme_constant_override("v_separation", 10)
	main_vbox.add_child(stats_grid)

	var kd_str := "%.2f" % prof.get_kd()
	var hs_pct := "%.1f%%" % (prof.get_headshot_rate() * 100.0)
	var win_pct := "%.1f%%" % (prof.get_win_rate() * 100.0)

	stats_grid.add_child(_stat_card("K / D RATIO", kd_str, "%d Kills / %d Deaths" % [prof.stats["kills"], prof.stats["deaths"]]))
	stats_grid.add_child(_stat_card("HEADSHOT RATE", hs_pct, "%d Headshots" % prof.stats["headshots"]))
	stats_grid.add_child(_stat_card("WIN RATE", win_pct, "%d W / %d L / %d D" % [prof.stats["wins"], prof.stats["losses"], prof.stats["draws"]]))
	stats_grid.add_child(_stat_card("MATCHES", str(prof.stats["matches"]), "Total multiplayer"))

	# --- History section header ---
	var hist_lbl := Label.new()
	hist_lbl.text = "RECENT MATCHES (%d)" % prof.history.size()
	hist_lbl.add_theme_font_size_override("font_size", 14)
	hist_lbl.modulate = UI_ORANGE
	main_vbox.add_child(hist_lbl)

	# --- History scroll list ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 220)
	main_vbox.add_child(scroll)

	var hist_list := VBoxContainer.new()
	hist_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hist_list.add_theme_constant_override("separation", 6)
	scroll.add_child(hist_list)

	if prof.history.is_empty():
		var empty := Label.new()
		empty.text = "No matches recorded yet. Play a multiplayer match to build history."
		empty.modulate = UI_TEXT_DIM
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hist_list.add_child(empty)
	else:
		for h in prof.history:
			hist_list.add_child(_history_row(h))

func _pill(label_text: String, val_text: String, col: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.09, 0.12, 0.9)
	st.corner_radius_top_left = 6
	st.corner_radius_top_right = 6
	st.corner_radius_bottom_left = 6
	st.corner_radius_bottom_right = 6
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", st)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	pc.add_child(vb)

	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 10)
	l.modulate = UI_TEXT_DIM
	vb.add_child(l)

	var v := Label.new()
	v.text = val_text
	v.add_theme_font_size_override("font_size", 14)
	v.modulate = col
	vb.add_child(v)
	return pc

func _stat_card(title: String, big_val: String, sub_text: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.14, 0.15, 0.18, 0.95)
	st.corner_radius_top_left = 6
	st.corner_radius_top_right = 6
	st.corner_radius_bottom_left = 6
	st.corner_radius_bottom_right = 6
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", st)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	pc.add_child(vb)

	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 11)
	tl.modulate = UI_TEXT_DIM
	vb.add_child(tl)

	var vl := Label.new()
	vl.text = big_val
	vl.add_theme_font_size_override("font_size", 24)
	vl.modulate = UI_TEXT
	vb.add_child(vl)

	var sl := Label.new()
	sl.text = sub_text
	sl.add_theme_font_size_override("font_size", 11)
	sl.modulate = UI_TEXT_DIM
	vb.add_child(sl)
	return pc

func _history_row(h: Dictionary) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.13, 0.14, 0.17, 0.9)
	st.corner_radius_top_left = 4
	st.corner_radius_top_right = 4
	st.corner_radius_bottom_left = 4
	st.corner_radius_bottom_right = 4
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	var res = str(h.get("result", "loss")).to_lower()
	if res == "win":
		st.border_width_left = 4
		st.border_color = Color(0.3, 0.85, 0.4)
	elif res == "draw":
		st.border_width_left = 4
		st.border_color = Color(0.9, 0.8, 0.25)
	else:
		st.border_width_left = 4
		st.border_color = Color(0.85, 0.3, 0.3)
	pc.add_theme_stylebox_override("panel", st)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	pc.add_child(hb)

	var res_lbl := Label.new()
	res_lbl.text = res.to_upper()
	res_lbl.custom_minimum_size = Vector2(60, 0)
	res_lbl.add_theme_font_size_override("font_size", 14)
	res_lbl.modulate = Color(0.3, 0.85, 0.4) if res == "win" else (Color(0.9, 0.8, 0.25) if res == "draw" else Color(0.85, 0.3, 0.3))
	hb.add_child(res_lbl)

	var mode_lbl := Label.new()
	mode_lbl.text = str(h.get("mode", "Match"))
	mode_lbl.custom_minimum_size = Vector2(160, 0)
	mode_lbl.add_theme_font_size_override("font_size", 14)
	hb.add_child(mode_lbl)

	var kda_lbl := Label.new()
	kda_lbl.text = "%d K  /  %d D  (%d HS)" % [int(h.get("kills", 0)), int(h.get("deaths", 0)), int(h.get("headshots", 0))]
	kda_lbl.custom_minimum_size = Vector2(140, 0)
	kda_lbl.add_theme_font_size_override("font_size", 13)
	kda_lbl.modulate = UI_TEXT
	hb.add_child(kda_lbl)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)

	var pay_lbl := Label.new()
	pay_lbl.text = "+$%d  +★%d" % [int(h.get("cash", 0)), int(h.get("gold", 0))]
	pay_lbl.add_theme_font_size_override("font_size", 13)
	pay_lbl.modulate = Color(1.0, 0.85, 0.2)
	hb.add_child(pay_lbl)

	var date_lbl := Label.new()
	var ts = str(h.get("timestamp", ""))
	# keep YYYY-MM-DD HH:MM
	if ts.length() >= 16:
		ts = ts.substr(0, 16).replace("T", " ")
	date_lbl.text = ts
	date_lbl.add_theme_font_size_override("font_size", 11)
	date_lbl.modulate = UI_TEXT_DIM
	hb.add_child(date_lbl)

	return pc
