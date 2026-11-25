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
var scoreboard_font: Font
var scoreboard_font_bold: FontVariation
var side_picker: Control
var btn_attackers: Button
var btn_defenders: Button
var match_end_overlay: Control
var match_end_title: Label
var match_end_score: Label
var match_end_payroll: VBoxContainer
var lbl_team_full: Label
var match_end_return: Button
var att_score_label: Label
var def_score_label: Label
var has_joined_match := false

# ---- S&D HUD refs (created in _build_ui, shown only for S&D matches) ----
var snd_bomb_label: Label
var snd_site_a_label: Label
var snd_site_b_label: Label
var snd_carrier_label: Label
var snd_action_box: VBoxContainer
var snd_action_label: Label
var snd_action_bar: ProgressBar
var snd_round_banner: Label
var _snd_banner_until: float = 0.0

func _ready() -> void:
	_build_ui()
	var ffa := _is_ffa()
	if ffa:
		# FFA (Flying Scoutsman): no sides exist — destroy the picker outright
		if side_picker != null:
			side_picker.queue_free()
			side_picker = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		btn_attackers.pressed.connect(func(): pick_side("attackers"))
		btn_defenders.pressed.connect(func(): pick_side("defenders"))
	if get_parent() is MultiplayerManager:
		setup(get_parent() as MultiplayerManager)

## FFA detection that works before the manager's _ready() runs (children ready
## first): either the manager is the Flying Scoutsman type or the FFA export
## was pre-set in _init().
func _is_ffa() -> bool:
	var mgr := get_parent()
	if mgr is FlyingScoutsmanManager:
		return true
	if mgr != null:
		var v = mgr.get("ffa_target_kills")
		if v != null and int(v) > 0:
			return true
	return false

func _build_ui() -> void:
	# Top-center match header: score plate / mode plate / timer plate (tactical)
	var top_center := VBoxContainer.new()
	top_center.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top_center.offset_left = -340.0
	top_center.offset_right = 340.0
	top_center.offset_top = 10.0
	top_center.alignment = BoxContainer.ALIGNMENT_CENTER
	top_center.add_theme_constant_override("separation", 3)
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_center)

	var plate_sb := _mk_plate_style()
	var plate_sb_narrow := _mk_plate_style()
	plate_sb_narrow.content_margin_left = 26.0
	plate_sb_narrow.content_margin_right = 26.0

	# Row 1 — [shield] ATT n | objective | n DEF [shield]
	var score_plate := PanelContainer.new()
	score_plate.add_theme_stylebox_override("panel", plate_sb)
	score_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	score_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_child(score_plate)

	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 14)
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_plate.add_child(score_row)

	var hdr_font := FontVariation.new()
	hdr_font.base_font = load("res://addons/GD-Sync/UI/Fonts/Outfit-Regular.ttf")
	hdr_font.variation_embolden = 0.7

	score_row.add_child(_mk_shield_icon(Color(0.95, 0.96, 0.98)))
	att_score_label = _mk_header_label(hdr_font, 22, Color(0.98, 0.72, 0.45))
	att_score_label.text = "ATT 0"
	score_row.add_child(att_score_label)

	var sep_l := _mk_header_label(hdr_font, 18, Color(0.45, 0.5, 0.56))
	sep_l.text = "|"
	score_row.add_child(sep_l)

	objective_label = Label.new()
	objective_label.text = "Waiting for players..."
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.add_theme_font_override("font", hdr_font)
	objective_label.add_theme_font_size_override("font_size", 17)
	objective_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.97))
	objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_row.add_child(objective_label)

	var sep_r := _mk_header_label(hdr_font, 18, Color(0.45, 0.5, 0.56))
	sep_r.text = "|"
	score_row.add_child(sep_r)

	def_score_label = _mk_header_label(hdr_font, 22, Color(0.55, 0.78, 0.98))
	def_score_label.text = "0 DEF"
	score_row.add_child(def_score_label)
	score_row.add_child(_mk_shield_icon(Color(0.95, 0.96, 0.98)))

	# Row 2 — mode title strip
	round_label = Label.new()
	round_label.text = "DEATHMATCH"
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.add_theme_font_override("font", hdr_font)
	round_label.add_theme_font_size_override("font_size", 16)
	round_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.94))
	round_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_child(round_label)

	# Row 3 — timer capsule with green chevrons
	var timer_plate := PanelContainer.new()
	timer_plate.add_theme_stylebox_override("panel", plate_sb_narrow)
	timer_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	timer_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_child(timer_plate)

	var timer_row := HBoxContainer.new()
	timer_row.add_theme_constant_override("separation", 12)
	timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_plate.add_child(timer_row)

	var chev_l := _mk_header_label(hdr_font, 20, Color(0.55, 0.82, 0.3))
	chev_l.text = "<"
	timer_row.add_child(chev_l)

	timer_label = Label.new()
	timer_label.text = "10:00"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_override("font", hdr_font)
	timer_label.add_theme_font_size_override("font_size", 26)
	timer_label.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_row.add_child(timer_label)

	var chev_r := _mk_header_label(hdr_font, 20, Color(0.55, 0.82, 0.3))
	chev_r.text = ">"
	timer_row.add_child(chev_r)

	# ---- S&D extras (only visible when manager is a SearchAndDestroyManager) ----
	# Bomb status line under the timer
	snd_bomb_label = Label.new()
	snd_bomb_label.text = ""
	snd_bomb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	snd_bomb_label.add_theme_font_override("font", hdr_font)
	snd_bomb_label.add_theme_font_size_override("font_size", 15)
	snd_bomb_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15))
	snd_bomb_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_child(snd_bomb_label)
	snd_bomb_label.visible = false

	# Site A / B distance row
	var site_row := HBoxContainer.new()
	site_row.add_theme_constant_override("separation", 20)
	site_row.alignment = BoxContainer.ALIGNMENT_CENTER
	site_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_child(site_row)
	snd_site_a_label = _mk_header_label(hdr_font, 14, Color(0.75, 0.8, 0.85))
	snd_site_a_label.text = ""
	snd_site_b_label = _mk_header_label(hdr_font, 14, Color(0.75, 0.8, 0.85))
	snd_site_b_label.text = ""
	site_row.add_child(snd_site_a_label)
	site_row.add_child(snd_site_b_label)

	# Carrier indicator — small "C4" tag under scores
	snd_carrier_label = Label.new()
	snd_carrier_label.text = ""
	snd_carrier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	snd_carrier_label.add_theme_font_override("font", hdr_font)
	snd_carrier_label.add_theme_font_size_override("font_size", 14)
	snd_carrier_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	snd_carrier_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_center.add_child(snd_carrier_label)
	snd_carrier_label.visible = false

	# Plant / defuse progress bar (center-bottom, above hotbar area)
	snd_action_box = VBoxContainer.new()
	snd_action_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	snd_action_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	snd_action_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	snd_action_box.offset_left = -220.0
	snd_action_box.offset_right = 220.0
	snd_action_box.offset_top = -190.0
	snd_action_box.offset_bottom = -150.0
	snd_action_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snd_action_box.visible = false
	add_child(snd_action_box)

	snd_action_label = Label.new()
	snd_action_label.text = ""
	snd_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	snd_action_label.add_theme_font_override("font", hdr_font)
	snd_action_label.add_theme_font_size_override("font_size", 18)
	snd_action_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	snd_action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snd_action_box.add_child(snd_action_label)

	snd_action_bar = ProgressBar.new()
	snd_action_bar.min_value = 0.0
	snd_action_bar.max_value = 100.0
	snd_action_bar.value = 0.0
	snd_action_bar.show_percentage = false
	snd_action_bar.custom_minimum_size = Vector2(440, 18)
	snd_action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.05, 0.06, 0.08, 0.85)
	bar_bg.set_corner_radius_all(3)
	bar_bg.border_color = Color(1.0, 0.55, 0.15, 0.6)
	bar_bg.set_border_width_all(1)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(1.0, 0.55, 0.15, 0.95)
	bar_fill.set_corner_radius_all(3)
	snd_action_bar.add_theme_stylebox_override("background", bar_bg)
	snd_action_bar.add_theme_stylebox_override("fill", bar_fill)
	snd_action_box.add_child(snd_action_bar)

	# Round end banner (center-screen compact strip)
	snd_round_banner = Label.new()
	snd_round_banner.text = ""
	snd_round_banner.set_anchors_preset(Control.PRESET_CENTER)
	snd_round_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	snd_round_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	snd_round_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	snd_round_banner.add_theme_font_override("font", hdr_font)
	snd_round_banner.add_theme_font_size_override("font_size", 34)
	snd_round_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	snd_round_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	snd_round_banner.add_theme_constant_override("outline_size", 8)
	snd_round_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snd_round_banner.visible = false
	add_child(snd_round_banner)

	# Scoreboard (hold TAB) — tactical briefing card: dark plate, team accent badges
	scoreboard = Control.new()
	scoreboard.set_anchors_preset(Control.PRESET_FULL_RECT)
	scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard.visible = false
	add_child(scoreboard)

	# Dim the battlefield behind the card so rows stay readable
	var sb_dim := ColorRect.new()
	sb_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	sb_dim.color = Color(0.0, 0.0, 0.0, 0.35)
	sb_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard.add_child(sb_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard.add_child(center)

	scoreboard_font = load("res://addons/GD-Sync/UI/Fonts/Outfit-Regular.ttf")
	scoreboard_font_bold = FontVariation.new()
	scoreboard_font_bold.base_font = scoreboard_font
	scoreboard_font_bold.variation_embolden = 0.7

	var panel := PanelContainer.new()
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.045, 0.06, 0.08, 0.94)
	panel_sb.border_color = Color(0.34, 0.42, 0.5, 0.45)
	panel_sb.set_border_width_all(1)
	panel_sb.set_corner_radius_all(8)
	panel_sb.shadow_color = Color(0, 0, 0, 0.45)
	panel_sb.shadow_size = 22
	panel_sb.content_margin_left = 22.0
	panel_sb.content_margin_right = 22.0
	panel_sb.content_margin_top = 14.0
	panel_sb.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", panel_sb)
	panel.custom_minimum_size = Vector2(760, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	scoreboard_title = Label.new()
	scoreboard_title.text = "TEAM DEATHMATCH"
	scoreboard_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_title.add_theme_font_override("font", scoreboard_font_bold)
	scoreboard_title.add_theme_font_size_override("font_size", 21)
	scoreboard_title.add_theme_color_override("font_color", Color(0.93, 0.95, 0.97))
	scoreboard_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(scoreboard_title)

	var subtitle := Label.new()
	subtitle.text = "HOLD  TAB  TO  VIEW  —  RELEASE  TO  HIDE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", scoreboard_font)
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.62, 0.7, 0.8))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(subtitle)

	var hsep := HSeparator.new()
	hsep.modulate = Color(0.4, 0.5, 0.6, 0.5)
	hsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hsep)

	# 2-column split: Attackers (Blue) vs Defenders (Red); single ranked column in FFA
	scoreboard_list = HBoxContainer.new()
	scoreboard_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scoreboard_list.add_theme_constant_override("separation", 18)
	scoreboard_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(scoreboard_list)

	# Side picker overlay — "SELECT TEAM" (AXIS vs ALLIES portrait cards)
	side_picker = Control.new()
	side_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(side_picker)

	var darken := ColorRect.new()
	darken.set_anchors_preset(Control.PRESET_FULL_RECT)
	darken.color = Color(0.03, 0.035, 0.045, 0.93)
	side_picker.add_child(darken)

	var picker_font: Font = load("res://addons/GD-Sync/UI/Fonts/Outfit-Regular.ttf")
	var picker_font_bold := FontVariation.new()
	picker_font_bold.base_font = picker_font
	picker_font_bold.variation_embolden = 0.7

	var title := Label.new()
	title.text = "SELECT TEAM"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.offset_top = 52.0
	title.offset_bottom = 104.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", picker_font_bold)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	side_picker.add_child(title)

	var s_center := CenterContainer.new()
	s_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	side_picker.add_child(s_center)

	var s_box := VBoxContainer.new()
	s_box.add_theme_constant_override("separation", 18)
	s_box.alignment = BoxContainer.ALIGNMENT_CENTER
	s_center.add_child(s_box)

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 44)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	s_box.add_child(cards_row)

	# AXIS (defenders) — left card
	btn_defenders = Button.new()
	cards_row.add_child(_mk_team_card(btn_defenders, "AXIS", "DEFENDERS", Color(0.78, 0.29, 0.16), Color(0.16, 0.16, 0.18), picker_font, picker_font_bold))

	var vs := Label.new()
	vs.text = "VS"
	vs.add_theme_font_override("font", picker_font_bold)
	vs.add_theme_font_size_override("font_size", 46)
	vs.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	cards_row.add_child(vs)

	# ALLIES (attackers) — right card
	btn_attackers = Button.new()
	cards_row.add_child(_mk_team_card(btn_attackers, "ALLIES", "ATTACKERS", Color(0.2, 0.46, 0.62), Color(0.63, 0.54, 0.38), picker_font, picker_font_bold))

	# Team-full notice (replaces the _toast helper main menu has, not HUD)
	lbl_team_full = Label.new()
	lbl_team_full.text = ""
	lbl_team_full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_team_full.add_theme_font_override("font", picker_font_bold)
	lbl_team_full.add_theme_font_size_override("font_size", 20)
	lbl_team_full.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	s_box.add_child(lbl_team_full)

	var btn_back := Button.new()
	btn_back.text = "‹  Back"
	btn_back.flat = true
	btn_back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	btn_back.grow_vertical = Control.GROW_DIRECTION_BEGIN
	btn_back.position = Vector2(28, 0)
	btn_back.offset_bottom = -26.0
	btn_back.offset_top = -70.0
	btn_back.add_theme_font_override("font", picker_font_bold)
	btn_back.add_theme_font_size_override("font_size", 19)
	btn_back.add_theme_color_override("font_color", Color(0.62, 0.66, 0.7))
	btn_back.add_theme_color_override("font_hover_color", Color(0.95, 0.96, 0.98))
	btn_back.pressed.connect(func():
		if has_joined_match:
			toggle_side_picker()
		else:
			get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	)
	side_picker.add_child(btn_back)

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

	match_end_payroll = VBoxContainer.new()
	match_end_payroll.add_theme_constant_override("separation", 4)
	match_end_payroll.alignment = BoxContainer.ALIGNMENT_CENTER
	end_box.add_child(match_end_payroll)

	match_end_return = Button.new()
	match_end_return.text = "RETURN TO LOBBY"
	match_end_return.custom_minimum_size = Vector2(240, 48)
	match_end_return.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	)
	end_box.add_child(match_end_return)

## Builds one team card: name, role tag, live soldier portrait, SELECT button.
func _mk_team_card(select_btn: Button, team_name: String, subtitle: String, accent: Color, tint: Color, font: Font, font_bold: Font) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.14, 0.97)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(340, 540)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)

	var name_lbl := Label.new()
	name_lbl.text = team_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_override("font", font_bold)
	name_lbl.add_theme_font_size_override("font_size", 28)
	name_lbl.add_theme_color_override("font_color", Color(0.93, 0.95, 0.97))
	box.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = subtitle
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_override("font", font)
	sub_lbl.add_theme_font_size_override("font_size", 14)
	sub_lbl.add_theme_color_override("font_color", Color(accent.r + 0.15, accent.g + 0.15, accent.b + 0.15))
	box.add_child(sub_lbl)

	# Soldier portrait: live 3D render of the shared body model, tinted per faction
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(306, 330)
	svc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(svc)

	var sv := SubViewport.new()
	sv.size = Vector2i(306, 330)
	sv.transparent_bg = true
	sv.own_world_3d = true
	svc.add_child(sv)

	var body: Node3D = load("res://scenes/characters/human_body.tscn").instantiate()
	body.rotation.y = PI # glb faces -Z (gameplay forward); portrait camera is on +Z
	sv.add_child(body)
	body.set("tint_color", tint)

	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.look_at_from_position(Vector3(0.0, 1.35, 1.8), Vector3(0.0, 1.15, 0.0))
	sv.add_child(cam)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-22, 28, 0)
	key.light_energy = 1.3
	sv.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -140, 0)
	fill.light_energy = 0.45
	sv.add_child(fill)

	# Full-width SELECT button (light plate, dark text — hover flips to accent)
	select_btn.text = "SELECT"
	select_btn.custom_minimum_size = Vector2(306, 48)
	var bn := StyleBoxFlat.new()
	bn.bg_color = Color(0.88, 0.9, 0.93)
	bn.set_corner_radius_all(4)
	var bh := StyleBoxFlat.new()
	bh.bg_color = accent
	bh.set_corner_radius_all(4)
	var bp := StyleBoxFlat.new()
	bp.bg_color = accent.darkened(0.25)
	bp.set_corner_radius_all(4)
	select_btn.add_theme_stylebox_override("normal", bn)
	select_btn.add_theme_stylebox_override("hover", bh)
	select_btn.add_theme_stylebox_override("pressed", bp)
	select_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	select_btn.add_theme_color_override("font_color", Color(0.09, 0.1, 0.12))
	select_btn.add_theme_color_override("font_hover_color", Color(0.97, 0.98, 1.0))
	select_btn.add_theme_color_override("font_pressed_color", Color(0.97, 0.98, 1.0))
	select_btn.add_theme_font_override("font", font_bold)
	select_btn.add_theme_font_size_override("font_size", 20)
	box.add_child(select_btn)

	return card

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
	# S&D extras — duck-typed so the HUD never hard-couples to the mode script
	if mgr.has_signal("bomb_state_synced"):
		mgr.bomb_state_synced.connect(_on_snd_bomb_state)
		mgr.bomb_action_progress.connect(_on_snd_action_progress)
		mgr.round_ended.connect(_on_snd_round_ended)
	refresh_scoreboard()
	update_header()

func _on_scoreboard_sync(_d: Dictionary, _s: Dictionary, _m: Dictionary = {}) -> void:
	refresh_scoreboard()
	update_header()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:
		return
	if event.keycode == KEY_TAB:
		# Scoreboard shows while cursor stays hidden and camera stays captured
		scoreboard.visible = event.pressed
		if scoreboard.visible:
			refresh_scoreboard()
	elif event.keycode == KEY_M and event.pressed:
		if manager and int(manager.ffa_target_kills) > 0:
			return # No sides in FFA
		toggle_side_picker()
	elif event.keycode == KEY_ESCAPE and event.pressed and side_picker != null and side_picker.visible and has_joined_match:
		toggle_side_picker()
		get_viewport().set_input_as_handled()

func toggle_side_picker() -> void:
	if side_picker == null:
		return
	side_picker.visible = not side_picker.visible
	if side_picker.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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
	if _is_snd() and state != MultiplayerManager.MatchState.MATCH_END:
		round_label.text = "SEARCH & DESTROY  —  ROUND %d / FIRST TO %d" % [manager.current_round, manager.rounds_to_win]
		if state == MultiplayerManager.MatchState.ROUND_END:
			_snd_show_banner(_snd_round_result_text())
		elif state == MultiplayerManager.MatchState.WARMUP:
			_snd_show_banner("ROUND %d — %s" % [manager.current_round, _snd_local_side_text()])

func _is_snd() -> bool:
	return manager != null and manager.has_signal("bomb_state_synced")

func _snd_round_result_text() -> String:
	match manager.round_win_reason:
		"elimination":
			return "%s WIN — TEAM ELIMINATED" % manager.round_winner.to_upper()
		"defused":
			return "BOMB DEFUSED — DEFENDERS WIN"
		"detonated":
			return "TARGET DESTROYED — ATTACKERS WIN"
		"time":
			return "TIME EXPIRED — DEFENDERS WIN"
	return "ROUND OVER"

func _snd_local_side_text() -> String:
	var my_peer := multiplayer.get_unique_id() if GlobalData.is_networked() else 1
	if manager.players_data.has(my_peer):
		return "ATTACKING" if manager.players_data[my_peer].get("team", "") == "attackers" else "DEFENDING"
	return ""

func _snd_show_banner(text: String) -> void:
	if snd_round_banner == null:
		return
	snd_round_banner.text = text
	snd_round_banner.visible = true
	_snd_banner_until = Time.get_ticks_msec() / 1000.0 + 4.0

func _on_snd_bomb_state(b_state: String, site_id: String, carrier_name: String, _b_timer: int) -> void:
	if snd_bomb_label == null or not _is_snd():
		return
	snd_bomb_label.visible = true
	match b_state:
		"CARRIED":
			var who := carrier_name if carrier_name != "" else "?"
			snd_bomb_label.text = "C4: CARRIED BY %s" % who
			snd_bomb_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		"DROPPED":
			snd_bomb_label.text = "C4: DROPPED — PICK IT UP!"
			snd_bomb_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
		"PLANTING":
			snd_bomb_label.text = "C4: BEING PLANTED..."
			snd_bomb_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15))
		"PLANTED":
			snd_bomb_label.text = "BOMB PLANTED AT SITE %s" % site_id
			snd_bomb_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		"DEFUSING":
			snd_bomb_label.text = "BOMB BEING DEFUSED..."
			snd_bomb_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		"DEFUSED":
			snd_bomb_label.text = "BOMB DEFUSED"
			snd_bomb_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		"DETONATED":
			snd_bomb_label.text = "BOMB DETONATED"
			snd_bomb_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		_:
			snd_bomb_label.text = ""

	# Carrier tag (only meaningful while carried)
	if snd_carrier_label:
		if b_state == "CARRIED":
			var mine := carrier_name != "" and carrier_name == _local_player_name()
			snd_carrier_label.visible = mine
			snd_carrier_label.text = "YOU CARRY THE BOMB"
		else:
			snd_carrier_label.visible = false

func _local_player_name() -> String:
	if not manager:
		return "Player"
	var my_peer := multiplayer.get_unique_id() if GlobalData.is_networked() else 1
	if manager.players_data.has(my_peer):
		return manager.players_data[my_peer].get("name", "Player")
	return "Player"

func _on_snd_action_progress(act: String, peer: int, prog: float) -> void:
	if snd_action_box == null or snd_action_bar == null or snd_action_label == null:
		return
	if prog < 0.0 or act == "":
		snd_action_box.visible = false
		return
	snd_action_box.visible = true
	var who := "TEAMMATE" if peer != (multiplayer.get_unique_id() if GlobalData.is_networked() else 1) else "YOU"
	snd_action_label.text = "%s — %s (%d%%)" % [act.replace("ING", "ING"), who, int(prog * 100.0)]
	snd_action_bar.value = prog * 100.0

func _on_snd_round_ended(_winner: String, _reason: String) -> void:
	if snd_action_box:
		snd_action_box.visible = false

func _snd_update_site_indicators() -> void:
	if snd_site_a_label == null or snd_site_b_label == null or manager == null:
		return
	var my_peer := multiplayer.get_unique_id() if GlobalData.is_networked() else 1
	var local_player: Node3D = null
	var container := get_tree().current_scene
	if container:
		local_player = container.get_node_or_null(str(my_peer))
		if local_player == null:
			for p in get_tree().get_nodes_in_group("player"):
				if p.name == str(my_peer) or (my_peer == 1 and p.name == "Player"):
					local_player = p
					break

	for site in get_tree().get_nodes_in_group("bombsite"):
		var sid := str(site.get("site_id"))
		var dist_text := ""
		if local_player:
			var d := local_player.global_position.distance_to(site.global_position)
			dist_text = "SITE %s  %dm" % [sid, int(d)]
		else:
			dist_text = "SITE %s" % sid
		if sid == "A":
			snd_site_a_label.text = dist_text
		elif sid == "B":
			snd_site_b_label.text = dist_text

	# Highlight planted site
	if _is_snd():
		var planted_color := Color(1.0, 0.2, 0.2)
		var idle_color := Color(0.75, 0.8, 0.85)
		if manager.planted_site_id == "A":
			snd_site_a_label.add_theme_color_override("font_color", planted_color)
			snd_site_b_label.add_theme_color_override("font_color", idle_color)
		elif manager.planted_site_id == "B":
			snd_site_b_label.add_theme_color_override("font_color", planted_color)
			snd_site_a_label.add_theme_color_override("font_color", idle_color)
		else:
			snd_site_a_label.add_theme_color_override("font_color", idle_color)
			snd_site_b_label.add_theme_color_override("font_color", idle_color)

func _show_match_end_screen() -> void:
	if not manager:
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var a = manager.team_scores.get("attackers", 0)
	var d = manager.team_scores.get("defenders", 0)
	var local_team = "attackers"
	if manager.match_stats.has("Player"):
		local_team = manager.match_stats["Player"].get("team", "attackers")

	# Free-for-all: win is determined by who reached target_kills (ffa_winner_name)
	var is_ffa: bool = manager != null and int(manager.ffa_target_kills) > 0
	var is_win: bool = false
	var is_draw: bool = false

	if is_ffa:
		var my_name := _local_player_name()
		var winner: String = str(manager.get("ffa_winner_name"))
		is_win = (winner != "" and (winner == my_name or winner == "Player"))
		if winner != "":
			match_end_score.text = "%s won with %d kills!" % [winner, int(manager.ffa_target_kills)]
		else:
			match_end_score.text = "Match complete"
	else:
		is_win = (local_team == "attackers" and a > d) or (local_team == "defenders" and d > a)
		is_draw = (a == d)
		match_end_score.text = "Attackers %d  —  %d Defenders" % [a, d]

	if is_draw:
		match_end_title.text = "DRAW"
		match_end_title.modulate = Color(0.9, 0.85, 0.3)
	elif is_win:
		match_end_title.text = "VICTORY"
		match_end_title.modulate = Color(0.3, 0.9, 0.4)
	else:
		match_end_title.text = "DEFEAT"
		match_end_title.modulate = Color(0.95, 0.3, 0.3)

	_show_payroll("win" if is_win else ("draw" if is_draw else "loss"))
	scoreboard.visible = true
	match_end_overlay.visible = true

## Pays out and displays the post-match payroll (multiplayer matches only).
func _show_payroll(result: String) -> void:
	for c in match_end_payroll.get_children():
		c.queue_free()
	if not GlobalData.is_networked():
		return
	var prof = get_node_or_null("/root/PlayerProfile")
	if prof == null or not prof.is_tracking():
		return
	var payroll: Dictionary = prof.finish_match(result)
	var title := Label.new()
	title.text = "— MATCH PAYROLL (%s) —" % str(payroll.get("mode", "MATCH"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.modulate = Color(1.0, 0.8, 0.3)
	match_end_payroll.add_child(title)
	for line in payroll.get("lines", []):
		if int(line[1]) == 0 and int(line[2]) == 0:
			continue
		var row := Label.new()
		row.text = "%s   +%d CASH%s" % [line[0], int(line[1]), ("  +%d GOLD" % int(line[2])) if int(line[2]) > 0 else ""]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 15)
		match_end_payroll.add_child(row)
	var total := Label.new()
	total.text = "TOTAL:  +%d CASH   +%d GOLD" % [int(payroll.get("cash", 0)), int(payroll.get("gold", 0))]
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total.add_theme_font_size_override("font_size", 19)
	total.modulate = Color(1.0, 0.85, 0.2)
	match_end_payroll.add_child(total)

func _physics_process(_delta: float) -> void:
	# Flag ownership changes don't fire sync signals — poll for a live header
	if manager and manager.score_limit > 0:
		update_header()
	# S&D: live site distances + banner auto-hide
	if _is_snd():
		_snd_update_site_indicators()
		if snd_round_banner and snd_round_banner.visible:
			if Time.get_ticks_msec() / 1000.0 > _snd_banner_until:
				snd_round_banner.visible = false

func _on_time_tick(t: int) -> void:
	if _is_snd():
		if manager.current_bomb_state == 3 or manager.current_bomb_state == 4: # PLANTED or DEFUSING
			timer_label.text = "BOMB %ds" % manager.bomb_timer
			timer_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
			return
		else:
			timer_label.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
	var mins = floori(float(t) / 60.0)
	var secs = t % 60
	timer_label.text = "%d:%02d" % [mins, secs]

func update_header() -> void:
	if not manager:
		return
	round_label.text = manager.mode_title
	var a = manager.team_scores.get("attackers", 0)
	var d = manager.team_scores.get("defenders", 0)
	att_score_label.text = "ATT %d" % a
	def_score_label.text = "%d DEF" % d
	if manager.score_limit > 0:
		var flag_status := "NEUTRAL"
		var flags := get_tree().get_nodes_in_group("flagpoint")
		if not flags.is_empty():
			var f = flags[0]
			if f.get("contested"):
				flag_status = "CONTESTED"
			elif f.get("owner_team") == "attackers":
				flag_status = "HELD BY ATTACKERS"
			elif f.get("owner_team") == "defenders":
				flag_status = "HELD BY DEFENDERS"
		objective_label.text = "FLAG: %s (Cap: %d)" % [flag_status, manager.score_limit]
	elif manager and int(manager.ffa_target_kills) > 0:
		att_score_label.text = ""
		def_score_label.text = ""
		# Display the current leader
		var leader := "None"
		var leader_k := 0
		for k in manager.match_stats.keys():
			var s: Dictionary = manager.match_stats[k]
			var kills: int = s.get("kills", 0)
			if kills > leader_k:
				leader_k = kills
				leader = str(k)
		if leader_k > 0:
			att_score_label.text = "LEAD: %s (%d)" % [leader, leader_k]
		objective_label.text = "First to %d Kills" % int(manager.ffa_target_kills)
	elif _is_snd():
		objective_label.text = "ROUND %d" % manager.current_round
	else:
		objective_label.text = "First to %d" % manager.target_kills

const SB_COL_ATTACKERS := Color(0.45, 0.75, 1.0)
const SB_COL_DEFENDERS := Color(1.0, 0.48, 0.42)
const SB_COL_TEXT := Color(0.88, 0.91, 0.94)
const SB_COL_DIM := Color(0.52, 0.58, 0.66)
const SB_COL_GOLD := Color(1.0, 0.8, 0.35)
const SB_KD_WIDTH := 42.0

func refresh_scoreboard() -> void:
	if not scoreboard_list:
		return
	for c in scoreboard_list.get_children():
		c.queue_free()
	if not manager:
		return
	var a := int(manager.team_scores.get("attackers", 0))
	var d := int(manager.team_scores.get("defenders", 0))
	var is_ffa_sb: bool = int(manager.ffa_target_kills) > 0
	if is_ffa_sb:
		scoreboard_title.text = "%s   —   FIRST TO %d KILLS" % [manager.mode_title, int(manager.ffa_target_kills)]
	else:
		scoreboard_title.text = "%s   —   ATTACKERS %d : %d DEFENDERS" % [manager.mode_title, a, d]

	# Pull all stats from match_stats (strictly human players and AI bots)
	var entries: Array = [] # {name, kills, deaths, team, local}
	var stats: Dictionary = manager.match_stats if manager.match_stats else {}
	for entry_name in stats.keys():
		var sname := str(entry_name).strip_edges()
		if not _is_combatant_name(sname):
			continue
		var s: Dictionary = stats[entry_name]
		var is_local := sname == "Player"
		entries.append({
			"name": "You" if is_local else sname,
			"kills": int(s.get("kills", 0)),
			"deaths": int(s.get("deaths", 0)),
			"team": str(s.get("team", "attackers")),
			"local": is_local,
		})
	var by_kills := func(x: Dictionary, y: Dictionary) -> bool:
		if int(x.kills) != int(y.kills):
			return int(x.kills) > int(y.kills)
		return int(x.deaths) < int(y.deaths)

	if is_ffa_sb:
		entries.sort_custom(by_kills)
		scoreboard_list.add_child(_mk_score_column("", Color(0.9, 0.93, 0.96), entries, true, -1))
	else:
		var atk: Array = entries.filter(func(e): return str(e.team) != "defenders")
		var dfn: Array = entries.filter(func(e): return str(e.team) == "defenders")
		atk.sort_custom(by_kills)
		dfn.sort_custom(by_kills)
		scoreboard_list.add_child(_mk_score_column("ATTACKERS", SB_COL_ATTACKERS, atk, false, a))
		scoreboard_list.add_child(_mk_score_column("DEFENDERS", SB_COL_DEFENDERS, dfn, false, d))

## One team/leaderboard column: accent badge header, K/D column captions, stat rows.
func _mk_score_column(title: String, color: Color, rows: Array, ranked: bool, score: int) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if title != "":
		col.add_child(_mk_team_badge(title, color, score))
	col.add_child(_mk_column_header(ranked))
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "NO COMBATANTS"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_override("font", scoreboard_font)
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(SB_COL_DIM.r, SB_COL_DIM.g, SB_COL_DIM.b, 0.6))
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(empty)
		return col
	for i in rows.size():
		col.add_child(_mk_score_row(rows[i], color, ranked, i + 1))
	return col

## Colored team banner with the live team score on the right.
func _mk_team_badge(title: String, color: Color, score: int) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.14)
	sb.border_color = color
	sb.border_width_left = 3
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	var name_l := Label.new()
	name_l.text = title
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.add_theme_font_override("font", scoreboard_font_bold)
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", color.lightened(0.25))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(name_l)
	if score >= 0:
		var score_l := Label.new()
		score_l.text = str(score)
		score_l.add_theme_font_override("font", scoreboard_font_bold)
		score_l.add_theme_font_size_override("font_size", 15)
		score_l.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
		score_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(score_l)
	return pc

## Small caption row aligning OPERATOR / K / D over the stat columns below.
func _mk_column_header(ranked: bool) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.0)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 0.0
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	if ranked:
		var rank_l := Label.new()
		rank_l.text = "#"
		rank_l.custom_minimum_size = Vector2(26, 0)
		rank_l.add_theme_font_override("font", scoreboard_font_bold)
		rank_l.add_theme_font_size_override("font_size", 11)
		rank_l.add_theme_color_override("font_color", SB_COL_DIM)
		rank_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(rank_l)
	var name_l := Label.new()
	name_l.text = "OPERATOR"
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.add_theme_font_override("font", scoreboard_font_bold)
	name_l.add_theme_font_size_override("font_size", 11)
	name_l.add_theme_color_override("font_color", SB_COL_DIM)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(name_l)
	for caption in ["K", "D"]:
		var c := Label.new()
		c.text = caption
		c.custom_minimum_size = Vector2(SB_KD_WIDTH, 0)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_theme_font_override("font", scoreboard_font_bold)
		c.add_theme_font_size_override("font_size", 11)
		c.add_theme_color_override("font_color", SB_COL_DIM)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(c)
	return pc

## One combatant row: [rank] name | kills | deaths; local player gets a lit plate.
func _mk_score_row(e: Dictionary, color: Color, ranked: bool, rank: int) -> Control:
	var is_local: bool = bool(e.local)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	if is_local:
		sb.bg_color = Color(1, 1, 1, 0.09)
		sb.border_color = SB_COL_GOLD
		sb.border_width_left = 3
	else:
		sb.bg_color = Color(1, 1, 1, 0.03)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	if ranked:
		var rank_l := Label.new()
		rank_l.text = str(rank)
		rank_l.custom_minimum_size = Vector2(26, 0)
		rank_l.add_theme_font_override("font", scoreboard_font_bold)
		rank_l.add_theme_font_size_override("font_size", 14)
		match rank:
			1: rank_l.add_theme_color_override("font_color", SB_COL_GOLD)
			2: rank_l.add_theme_color_override("font_color", Color(0.82, 0.86, 0.9))
			3: rank_l.add_theme_color_override("font_color", Color(0.87, 0.62, 0.4))
			_: rank_l.add_theme_color_override("font_color", SB_COL_DIM)
		rank_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(rank_l)
	var name_l := Label.new()
	name_l.text = str(e.name)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.add_theme_font_override("font", scoreboard_font_bold if is_local else scoreboard_font)
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0) if is_local else color.lightened(0.35))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(name_l)
	var k_l := Label.new()
	k_l.text = str(e.kills)
	k_l.custom_minimum_size = Vector2(SB_KD_WIDTH, 0)
	k_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k_l.add_theme_font_override("font", scoreboard_font_bold if is_local else scoreboard_font)
	k_l.add_theme_font_size_override("font_size", 14)
	k_l.add_theme_color_override("font_color", Color(0.95, 0.97, 0.99))
	k_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(k_l)
	var d_l := Label.new()
	d_l.text = str(e.deaths)
	d_l.custom_minimum_size = Vector2(SB_KD_WIDTH, 0)
	d_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d_l.add_theme_font_override("font", scoreboard_font)
	d_l.add_theme_font_size_override("font_size", 14)
	d_l.add_theme_color_override("font_color", SB_COL_DIM)
	d_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(d_l)
	return pc

## Beveled tactical plate stylebox used across top match status segments.
func _mk_plate_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.15, 0.93)
	sb.border_color = Color(0.32, 0.38, 0.44, 0.75)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb

func _mk_header_label(font: Font, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Shield icon drawn in code as vector polygon so no asset file is needed.
func _mk_shield_icon(col: Color) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(16, 18)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var draw_node := Node2D.new()
	c.add_child(draw_node)
	draw_node.draw.connect(func():
		var pts := PackedVector2Array([
			Vector2(1, 2), Vector2(15, 2), Vector2(15, 9),
			Vector2(8, 16), Vector2(1, 9)
		])
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_node.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.25))
		draw_node.draw_polyline(outline, col, 1.5)
	)
	return c

func bot_display_name(bot: Node) -> String:
	var n = bot.get("bot_name")
	if n != null and str(n) != "":
		return str(n)
	return str(bot.name)

## Filters non-combatant entities ("World", sentries, vehicles) from the scoreboard.
func _is_combatant_name(name_str: String) -> bool:
	if name_str == "" or name_str == "World":
		return false
	var lower := name_str.to_lower()
	for kw in ["turret", "vehicle", "helicopter", "aircraft", "chinook", "humvee"]:
		if kw in lower:
			return false
	return true

func pick_side(team: String) -> void:
	if not manager:
		return
	var is_ffa := int(manager.ffa_target_kills) > 0
	if is_ffa:
		team = "all"
	if multiplayer.has_multiplayer_peer():
		# Cap humans at team_size per side: full team stays on picker with notice
		if not is_ffa and not manager.can_join_team(team):
			lbl_team_full.text = "%s IS FULL (%d MAX) — PICK OTHER SIDE" % [team.to_upper(), manager.team_size]
			return
		# Already on this side? Just close — no pointless respawn.
		var my_id = multiplayer.get_unique_id()
		if not is_ffa and manager.players_data.has(my_id) and manager.players_data[my_id].get("team", "") == team:
			toggle_side_picker()
			return
		var ss = get_node_or_null("/root/SteamSync")
		var my_name := str(ss.get("persona_name")) if ss != null else ""
		manager.request_join_team.rpc_id(1, team, my_name)
	else:
		manager.request_join_team_local(team)
	has_joined_match = true
	if side_picker and side_picker.visible:
		toggle_side_picker()
