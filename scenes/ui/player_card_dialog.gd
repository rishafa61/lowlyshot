extends CanvasLayer
## Tactical Dossier — stylized military player card.
## Displays rank insignia, level/XP progress, career combat metrics,
## filterable match history (ALL/S&D/GW/TDM), and cash/gold reserves.

const COL_BG := Color("0b0d11")
const COL_PANEL := Color("12161f")
const COL_CARD := Color("171d28")
const COL_CARD_HOVER := Color("1d2533")
const COL_BORDER := Color("2a3445")
const COL_ACCENT := Color(1.0, 0.44, 0.08)       # Tactical Orange
const COL_CYAN := Color(0.25, 0.85, 0.95)         # Intel Cyan
const COL_GOLD := Color(1.0, 0.82, 0.2)           # Gold Reserves
const COL_GREEN := Color(0.32, 0.9, 0.48)         # Victory / Cash
const COL_RED := Color(0.95, 0.32, 0.32)          # Defeat
const COL_YELLOW := Color(0.95, 0.82, 0.3)        # Draw
const COL_TEXT := Color(0.92, 0.94, 0.96)
const COL_TEXT_DIM := Color(0.55, 0.62, 0.72)
const COL_TEXT_MUTED := Color(0.35, 0.4, 0.48)

signal closed

var _current_filter := "ALL"
var _hist_container: VBoxContainer = null
var _filter_buttons := {}

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

# ----------------- Rank calculation -----------------
func _calc_level(stats: Dictionary) -> Dictionary:
	# Score = kills*100 + headshots*50 + wins*500 + matches*100
	var xp: int = (
		int(stats.get("kills", 0)) * 100
		+ int(stats.get("headshots", 0)) * 50
		+ int(stats.get("wins", 0)) * 500
		+ int(stats.get("matches", 0)) * 100
	)
	var lvl := 1 + int(xp / 1000)
	var cur_xp := xp % 1000
	var next_xp := 1000
	var titles := [
		"RECRUIT", "PRIVATE", "CORPORAL", "SERGEANT", "LIEUTENANT",
		"CAPTAIN", "MAJOR", "COLONEL", "BRIGADIER", "VETERAN",
	]
	var title_idx = clampi(lvl - 1, 0, titles.size() - 1)
	return {
		"level": lvl, "xp": xp, "cur_xp": cur_xp, "next_xp": next_xp,
		"title": titles[title_idx],
		"progress": float(cur_xp) / float(next_xp),
	}

# ----------------- UI Construction -----------------
func _build_ui() -> void:
	var prof := _prof()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Dark vignette backdrop
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close()
	)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	# Main dossier frame
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 640)
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = COL_BORDER
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 24
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	panel.add_child(main_vbox)

	# --- TOP DECK: Service Ribbon + Dossier Header + Wallet ---
	var top_deck := HBoxContainer.new()
	top_deck.add_theme_constant_override("separation", 18)
	main_vbox.add_child(top_deck)

	# Insignia badge (chevron plate)
	var rank_info = _calc_level(prof.stats if prof else {})
	var insignia := PanelContainer.new()
	insignia.custom_minimum_size = Vector2(72, 72)
	var ins_style := StyleBoxFlat.new()
	ins_style.bg_color = Color(0.08, 0.1, 0.14)
	ins_style.border_width_left = 2
	ins_style.border_width_top = 2
	ins_style.border_width_right = 2
	ins_style.border_width_bottom = 3
	ins_style.border_color = COL_ACCENT
	ins_style.corner_radius_top_left = 4
	ins_style.corner_radius_top_right = 4
	ins_style.corner_radius_bottom_left = 4
	ins_style.corner_radius_bottom_right = 4
	insignia.add_theme_stylebox_override("panel", ins_style)

	var ins_vbox := VBoxContainer.new()
	ins_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ins_vbox.add_theme_constant_override("separation", -2)
	insignia.add_child(ins_vbox)

	var star := Label.new()
	star.text = "◆"
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star.add_theme_font_size_override("font_size", 20)
	star.modulate = COL_ACCENT
	ins_vbox.add_child(star)

	var lvl_lbl := Label.new()
	lvl_lbl.text = "LVL %d" % rank_info["level"]
	lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_lbl.add_theme_font_size_override("font_size", 13)
	lvl_lbl.modulate = COL_TEXT
	ins_vbox.add_child(lvl_lbl)
	top_deck.add_child(insignia)

	# Name + Title + XP bar
	var name_block := VBoxContainer.new()
	name_block.alignment = BoxContainer.ALIGNMENT_CENTER
	name_block.add_theme_constant_override("separation", 2)
	top_deck.add_child(name_block)

	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	name_block.add_child(tag_row)

	var doc_tag := Label.new()
	doc_tag.text = "OPERATOR DOSSIER //"
	doc_tag.add_theme_font_size_override("font_size", 10)
	doc_tag.modulate = COL_ACCENT
	tag_row.add_child(doc_tag)

	var title_lbl := Label.new()
	title_lbl.text = rank_info["title"]
	title_lbl.add_theme_font_size_override("font_size", 10)
	title_lbl.modulate = COL_CYAN
	tag_row.add_child(title_lbl)

	var p_name := "Player"
	var ss = get_node_or_null("/root/SteamSync")
	if ss and ss.get("persona_name") != null and str(ss.persona_name) != "":
		p_name = str(ss.persona_name)
	var name_lbl := Label.new()
	name_lbl.text = p_name.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.modulate = COL_TEXT
	name_block.add_child(name_lbl)

	# XP Progress bar
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 10)
	name_block.add_child(xp_row)

	var xp_bar := ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(220, 6)
	xp_bar.show_percentage = false
	xp_bar.min_value = 0.0
	xp_bar.max_value = 1.0
	xp_bar.value = rank_info["progress"]
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.1, 0.13)
	bar_bg.corner_radius_top_left = 2
	bar_bg.corner_radius_top_right = 2
	bar_bg.corner_radius_bottom_left = 2
	bar_bg.corner_radius_bottom_right = 2
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = COL_ACCENT
	bar_fill.corner_radius_top_left = 2
	bar_fill.corner_radius_top_right = 2
	bar_fill.corner_radius_bottom_left = 2
	bar_fill.corner_radius_bottom_right = 2
	xp_bar.add_theme_stylebox_override("background", bar_bg)
	xp_bar.add_theme_stylebox_override("fill", bar_fill)
	xp_row.add_child(xp_bar)

	var xp_txt := Label.new()
	xp_txt.text = "%d / %d XP" % [rank_info["cur_xp"], rank_info["next_xp"]]
	xp_txt.add_theme_font_size_override("font_size", 10)
	xp_txt.modulate = COL_TEXT_DIM
	xp_row.add_child(xp_txt)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_deck.add_child(spacer)

	# Currency vaults
	var vaults := HBoxContainer.new()
	vaults.add_theme_constant_override("separation", 12)
	top_deck.add_child(vaults)

	vaults.add_child(_styled_vault("COMBAT CASH", "$ %s" % _fmt_num(prof.cash if prof else 0), COL_GREEN, "$"))
	vaults.add_child(_styled_vault("WAR GOLD", "★ %s" % _fmt_num(prof.gold if prof else 0), COL_GOLD, "★"))

	# Close button
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(38, 38)
	var cl_style := StyleBoxFlat.new()
	cl_style.bg_color = Color(0.15, 0.18, 0.23)
	cl_style.border_width_left = 1
	cl_style.border_width_top = 1
	cl_style.border_width_right = 1
	cl_style.border_width_bottom = 1
	cl_style.border_color = COL_BORDER
	cl_style.corner_radius_top_left = 4
	cl_style.corner_radius_top_right = 4
	cl_style.corner_radius_bottom_left = 4
	cl_style.corner_radius_bottom_right = 4
	close_btn.add_theme_stylebox_override("normal", cl_style)
	var cl_h := cl_style.duplicate()
	cl_h.bg_color = COL_RED
	close_btn.add_theme_stylebox_override("hover", cl_h)
	close_btn.pressed.connect(_close)
	top_deck.add_child(close_btn)

	# --- DIVIDER with accent tick ---
	var div := HSeparator.new()
	var d_style := StyleBoxLine.new()
	d_style.color = COL_BORDER
	d_style.thickness = 1
	div.add_theme_stylebox_override("separator", d_style)
	main_vbox.add_child(div)

	# --- STATS MATRIX: 4 tactical metric blocks ---
	var stats_grid := GridContainer.new()
	stats_grid.columns = 4
	stats_grid.add_theme_constant_override("h_separation", 12)
	main_vbox.add_child(stats_grid)

	var s_kills = int(prof.stats.get("kills", 0)) if prof else 0
	var s_deaths = int(prof.stats.get("deaths", 0)) if prof else 0
	var s_hs = int(prof.stats.get("headshots", 0)) if prof else 0
	var s_wins = int(prof.stats.get("wins", 0)) if prof else 0
	var s_loss = int(prof.stats.get("losses", 0)) if prof else 0
	var s_draw = int(prof.stats.get("draws", 0)) if prof else 0
	var s_matches = int(prof.stats.get("matches", 0)) if prof else 0

	var kd_str := "%.2f" % (prof.get_kd() if prof else 0.0)
	var hs_pct := "%.1f%%" % ((prof.get_headshot_rate() * 100.0) if prof else 0.0)
	var win_pct := "%.1f%%" % ((prof.get_win_rate() * 100.0) if prof else 0.0)

	stats_grid.add_child(_metric_card("KILL / DEATH", kd_str, "%d KILLS / %d DEATHS" % [s_kills, s_deaths], COL_ACCENT, prof.get_kd() / 3.0 if prof else 0.0))
	stats_grid.add_child(_metric_card("HEADSHOT RATIO", hs_pct, "%d PRECISION KILLS" % s_hs, COL_CYAN, prof.get_headshot_rate() if prof else 0.0))
	stats_grid.add_child(_metric_card("WIN RATE", win_pct, "%dW  %dL  %dD" % [s_wins, s_loss, s_draw], COL_GREEN, prof.get_win_rate() if prof else 0.0))
	stats_grid.add_child(_metric_card("DEPLOYMENTS", str(s_matches), "CAREER MATCHES", COL_GOLD, 1.0))

	# --- MATCH LOG HEADER & MODE FILTER TABS ---
	var hist_header := HBoxContainer.new()
	hist_header.add_theme_constant_override("separation", 10)
	main_vbox.add_child(hist_header)

	var log_title := Label.new()
	log_title.text = "COMBAT LOG"
	log_title.add_theme_font_size_override("font_size", 13)
	log_title.modulate = COL_TEXT
	hist_header.add_child(log_title)

	var tag_bracket := Label.new()
	tag_bracket.text = "// FILTER:"
	tag_bracket.add_theme_font_size_override("font_size", 10)
	tag_bracket.modulate = COL_TEXT_MUTED
	hist_header.add_child(tag_bracket)

	for f in ["ALL", "SEARCH & DESTROY", "GROUND WAR", "DEATHMATCH"]:
		var btn := Button.new()
		btn.text = f
		btn.custom_minimum_size = Vector2(0, 26)
		_style_filter_button(btn, f == _current_filter)
		var filter_name = f
		btn.pressed.connect(func():
			_set_filter(filter_name)
		)
		_filter_buttons[f] = btn
		hist_header.add_child(btn)

	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hist_header.add_child(sp2)

	var count_lbl := Label.new()
	var total_h = prof.history.size() if prof else 0
	count_lbl.text = "LOGGED: %d ENTRIES" % total_h
	count_lbl.add_theme_font_size_override("font_size", 11)
	count_lbl.modulate = COL_TEXT_MUTED
	hist_header.add_child(count_lbl)

	# --- MATCH HISTORY SCROLL CONTAINER ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 270)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	_hist_container = VBoxContainer.new()
	_hist_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hist_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_hist_container)

	_render_history()

# ----------------- Filter logic -----------------
func _set_filter(f: String) -> void:
	_current_filter = f
	for k in _filter_buttons.keys():
		_style_filter_button(_filter_buttons[k], k == _current_filter)
	_render_history()

func _style_filter_button(b: Button, active: bool) -> void:
	b.add_theme_font_size_override("font_size", 11)
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	if active:
		sb.bg_color = COL_ACCENT
		b.add_theme_color_override("font_color", Color(1, 1, 1))
	else:
		sb.bg_color = Color(0.13, 0.16, 0.21)
		sb.border_width_bottom = 1
		sb.border_color = COL_BORDER
		b.add_theme_color_override("font_color", COL_TEXT_DIM)
	b.add_theme_stylebox_override("normal", sb)
	var h := sb.duplicate()
	if not active:
		h.bg_color = COL_CARD_HOVER
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _render_history() -> void:
	if _hist_container == null:
		return
	for c in _hist_container.get_children():
		c.queue_free()

	var prof := _prof()
	var entries: Array = prof.history if prof else []
	var shown := 0
	for h in entries:
		var mode_str = str(h.get("mode", "")).to_upper()
		if _current_filter != "ALL":
			if _current_filter == "SEARCH & DESTROY" and not mode_str.contains("SEARCH"):
				continue
			elif _current_filter == "GROUND WAR" and not mode_str.contains("GROUND"):
				continue
			elif _current_filter == "DEATHMATCH" and not (mode_str.contains("DEATHMATCH") or mode_str.contains("TDM")):
				continue
		_hist_container.add_child(_history_row(h))
		shown += 1

	if shown == 0:
		var empty_panel := PanelContainer.new()
		var es := StyleBoxFlat.new()
		es.bg_color = Color(0.09, 0.11, 0.14, 0.6)
		es.corner_radius_top_left = 4
		es.corner_radius_top_right = 4
		es.corner_radius_bottom_left = 4
		es.corner_radius_bottom_right = 4
		es.content_margin_top = 36
		es.content_margin_bottom = 36
		empty_panel.add_theme_stylebox_override("panel", es)

		var empty_lbl := Label.new()
		empty_lbl.text = "NO RECENT DEPLOYMENTS IN THIS CATEGORY"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.modulate = COL_TEXT_MUTED
		empty_panel.add_child(empty_lbl)
		_hist_container.add_child(empty_panel)

# ----------------- Component Builders -----------------
func _styled_vault(title: String, val: String, accent_color: Color, _sym: String) -> PanelContainer:
	var pc := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.1, 0.13, 0.95)
	st.border_width_left = 1
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 2
	st.border_color = accent_color.darkened(0.4)
	st.corner_radius_top_left = 4
	st.corner_radius_top_right = 4
	st.corner_radius_bottom_left = 4
	st.corner_radius_bottom_right = 4
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", st)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -1)
	pc.add_child(vb)

	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 9)
	tl.modulate = COL_TEXT_MUTED
	vb.add_child(tl)

	var vl := Label.new()
	vl.text = val
	vl.add_theme_font_size_override("font_size", 16)
	vl.modulate = accent_color
	vb.add_child(vl)
	return pc

func _metric_card(title: String, big_val: String, sub: String, accent: Color, fill_pct: float) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = COL_CARD
	st.border_width_left = 1
	st.border_width_top = 1
	st.border_width_right = 1
	st.border_width_bottom = 2
	st.border_color = COL_BORDER
	st.corner_radius_top_left = 4
	st.corner_radius_top_right = 4
	st.corner_radius_bottom_left = 4
	st.corner_radius_bottom_right = 4
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", st)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	pc.add_child(vb)

	var top_row := HBoxContainer.new()
	vb.add_child(top_row)

	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 10)
	tl.modulate = COL_TEXT_DIM
	top_row.add_child(tl)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(sp)

	var pip := Label.new()
	pip.text = "▮"
	pip.add_theme_font_size_override("font_size", 10)
	pip.modulate = accent
	top_row.add_child(pip)

	var vl := Label.new()
	vl.text = big_val
	vl.add_theme_font_size_override("font_size", 26)
	vl.modulate = COL_TEXT
	vb.add_child(vl)

	# Mini meter bar
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 3)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(fill_pct, 0.0, 1.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.1, 0.13)
	var fg := StyleBoxFlat.new()
	fg.bg_color = accent
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	vb.add_child(bar)

	var sl := Label.new()
	sl.text = sub
	sl.add_theme_font_size_override("font_size", 10)
	sl.modulate = COL_TEXT_MUTED
	vb.add_child(sl)
	return pc

func _history_row(h: Dictionary) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var res = str(h.get("result", "loss")).to_lower()

	var accent: Color
	var tag_text: String
	match res:
		"win":
			accent = COL_GREEN
			tag_text = "VICTORY"
		"draw":
			accent = COL_YELLOW
			tag_text = "DRAW"
		_:
			accent = COL_RED
			tag_text = "DEFEAT"

	var st := StyleBoxFlat.new()
	st.bg_color = COL_CARD
	st.border_width_left = 3
	st.border_color = accent
	st.corner_radius_top_left = 2
	st.corner_radius_top_right = 2
	st.corner_radius_bottom_left = 2
	st.corner_radius_bottom_right = 2
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", st)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	pc.add_child(hb)

	# Outcome badge
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(74, 24)
	var b_st := StyleBoxFlat.new()
	b_st.bg_color = accent.darkened(0.7)
	b_st.corner_radius_top_left = 2
	b_st.corner_radius_top_right = 2
	b_st.corner_radius_bottom_left = 2
	b_st.corner_radius_bottom_right = 2
	badge.add_theme_stylebox_override("panel", b_st)
	var b_lbl := Label.new()
	b_lbl.text = tag_text
	b_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b_lbl.add_theme_font_size_override("font_size", 11)
	b_lbl.modulate = accent
	badge.add_child(b_lbl)
	hb.add_child(badge)

	# Mode
	var mode_lbl := Label.new()
	mode_lbl.text = str(h.get("mode", "Match")).to_upper()
	mode_lbl.custom_minimum_size = Vector2(170, 0)
	mode_lbl.add_theme_font_size_override("font_size", 13)
	mode_lbl.modulate = COL_TEXT
	hb.add_child(mode_lbl)

	# Combat performance: K / D / HS
	var k := int(h.get("kills", 0))
	var d := int(h.get("deaths", 0))
	var hs := int(h.get("headshots", 0))
	var stat_box := HBoxContainer.new()
	stat_box.custom_minimum_size = Vector2(180, 0)
	stat_box.add_theme_constant_override("separation", 10)
	hb.add_child(stat_box)

	stat_box.add_child(_mini_stat("K", str(k), COL_TEXT))
	stat_box.add_child(_mini_stat("D", str(d), COL_TEXT_DIM))
	stat_box.add_child(_mini_stat("HS", str(hs), COL_CYAN))

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)

	# Payroll reward pill
	var c_rew := int(h.get("cash", 0))
	var g_rew := int(h.get("gold", 0))
	var pay_box := HBoxContainer.new()
	pay_box.add_theme_constant_override("separation", 8)
	hb.add_child(pay_box)

	if c_rew > 0:
		var c_lbl := Label.new()
		c_lbl.text = "+$%d" % c_rew
		c_lbl.add_theme_font_size_override("font_size", 12)
		c_lbl.modulate = COL_GREEN
		pay_box.add_child(c_lbl)
	if g_rew > 0:
		var g_lbl := Label.new()
		g_lbl.text = "+★%d" % g_rew
		g_lbl.add_theme_font_size_override("font_size", 12)
		g_lbl.modulate = COL_GOLD
		pay_box.add_child(g_lbl)

	# Timestamp
	var ts = str(h.get("timestamp", ""))
	if ts.length() >= 16:
		ts = ts.substr(5, 11).replace("T", " ") # MM-DD HH:MM
	var date_lbl := Label.new()
	date_lbl.text = ts
	date_lbl.add_theme_font_size_override("font_size", 11)
	date_lbl.modulate = COL_TEXT_MUTED
	hb.add_child(date_lbl)

	return pc

func _mini_stat(tag: String, val: String, val_col: Color) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	var t := Label.new()
	t.text = tag
	t.add_theme_font_size_override("font_size", 10)
	t.modulate = COL_TEXT_MUTED
	hb.add_child(t)
	var v := Label.new()
	v.text = val
	v.add_theme_font_size_override("font_size", 13)
	v.modulate = val_col
	hb.add_child(v)
	return hb

func _fmt_num(n: int) -> String:
	if n < 1000:
		return str(n)
	var s := str(n)
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return out
