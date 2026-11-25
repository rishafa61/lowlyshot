extends Control

@onready var btn_back = $TopBar/BtnBack
@onready var tabs = {
	"Visual": $TopBar/TabVisual,
	"Audio": $TopBar/TabAudio,
	"Gameplay": $TopBar/TabGameplay,
	"Controls": $TopBar/TabControls
}

@onready var panels = {
	"Visual": $Content/TabVisualPanel,
	"Audio": $Content/TabAudioPanel,
	"Gameplay": $Content/TabGameplayPanel,
	"Controls": $Content/TabControlsPanel
}

# Sliders
@onready var slider_hip = $Content/TabGameplayPanel/HBoxHipSens/SliderHipSens
@onready var slider_scope = $Content/TabGameplayPanel/HBoxScopeSens/SliderScopeSens
@onready var spin_hip = $Content/TabGameplayPanel/HBoxHipSens/SpinBoxHip
@onready var spin_scope = $Content/TabGameplayPanel/HBoxScopeSens/SpinBoxScope
@onready var check_fullscreen = $Content/TabVisualPanel/HBoxFullscreen/CheckFullscreen
@onready var slider_bgm = $Content/TabAudioPanel/HBoxBGM/SliderBGM
@onready var slider_sfx = $Content/TabAudioPanel/HBoxSFX/SliderSFX
@onready var slider_input = $Content/TabAudioPanel/HBoxInput/SliderInput

func _ready():
	btn_back.pressed.connect(_on_back_pressed)
	btn_back.focus_mode = Control.FOCUS_NONE

	check_fullscreen.button_pressed = GlobalSettings.fullscreen
	check_fullscreen.text = "On" if GlobalSettings.fullscreen else "Off"
	check_fullscreen.toggled.connect(_on_fullscreen_toggled)
	
	tabs["Visual"].pressed.connect(func(): set_tab("Visual"))
	tabs["Audio"].pressed.connect(func(): set_tab("Audio"))
	tabs["Gameplay"].pressed.connect(func(): set_tab("Gameplay"))
	tabs["Controls"].pressed.connect(func(): set_tab("Controls"))
	
	# Connect sliders to GlobalSettings
	slider_hip.value = GlobalSettings.hip_sensitivity_mult
	spin_hip.value = GlobalSettings.hip_sensitivity_mult
	slider_hip.value_changed.connect(_on_hip_changed)
	spin_hip.value_changed.connect(_on_hip_changed_from_spin)
	
	slider_scope.value = GlobalSettings.scope_sensitivity_mult
	spin_scope.value = GlobalSettings.scope_sensitivity_mult
	slider_scope.value_changed.connect(_on_scope_changed)
	spin_scope.value_changed.connect(_on_scope_changed_from_spin)

	# Audio sliders
	slider_bgm.value = GlobalSettings.bgm_vol
	slider_bgm.value_changed.connect(_on_bgm_changed)
	slider_sfx.value = GlobalSettings.sfx_vol
	slider_sfx.value_changed.connect(_on_sfx_changed)
	slider_input.value = GlobalSettings.mic_vol
	slider_input.value_changed.connect(_on_mic_changed)

	set_tab("Visual")
	_build_controls_guide()
	_build_debug_mode()
	_apply_settings_style()

func _open_viewmodel_offset(tuner_mode: String, wid: String = "ak47", wname: String = "AK47") -> void:
	# Spawn as a sibling overlay so the game/settings behind stay intact;
	# the tuner handles its own save/cancel and frees itself.
	var overlay := (load("res://scenes/ui/viewmodel_offset.tscn") as PackedScene).instantiate()
	overlay.mode = tuner_mode
	overlay.weapon_id = wid
	overlay.weapon_name = wname
	get_parent().add_child(overlay)
	visible = false
	overlay.tree_exiting.connect(func(): visible = true)

# ---------------- Debug Mode (dev-only): per-weapon viewmodel offset tuning ----------------

var _dm_rows := [] # [{name: String, row: Control}] — filterable weapon rows

## Lists every weapon from the catalog (id, display name) in catalog order.
func _dm_weapons() -> Array:
	var out: Array = []
	for category in GlobalData.weapons:
		for w in GlobalData.weapons[category]:
			var wid := str(w.get("id", ""))
			if wid != "" and not out.any(func(e: Array) -> bool: return e[0] == wid):
				out.append([wid, str(w.get("name", wid))])
	return out

func _build_debug_mode() -> void:
	var panel: VBoxContainer = $Content/TabVisualPanel
	var title := Label.new()
	title.text = "DEBUG MODE"
	panel.add_child(title)
	var sep := HSeparator.new()
	panel.add_child(sep)

	var search := LineEdit.new()
	search.placeholder_text = "Search weapons..."
	search.custom_minimum_size = Vector2(0, 44)
	search.clear_button_enabled = true
	panel.add_child(search)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	for entry in _dm_weapons():
		var wid: String = entry[0]
		var wname: String = entry[1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		list.add_child(row)
		var name_lbl := _cg_label(wname, 20, CG_TEXT, true)
		name_lbl.custom_minimum_size = Vector2(220, 0)
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_lbl)
		for mode_pair in [["ads", "Set ADS Offset (%s)" % wname], ["hip", "Set Hipfire Offset (%s)" % wname]]:
			var b := Button.new()
			b.text = mode_pair[1]
			b.custom_minimum_size = Vector2(260, 44)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 17)
			b.pressed.connect(_open_viewmodel_offset.bind(mode_pair[0], wid, wname))
			row.add_child(b)
		_wrap_plate(row)
		_dm_rows.append({"name": wname.to_lower(), "row": row})

	search.text_changed.connect(_on_debug_search)
	_on_debug_search("") # apply initial (no-op) filter state

func _on_debug_search(query: String) -> void:
	var q := query.to_lower().strip_edges()
	for r in _dm_rows:
		(r["row"] as Control).get_parent().visible = q == "" or (r["name"] as String).contains(q)


func set_tab(tab_name: String):
	for k in panels.keys():
		panels[k].visible = (k == tab_name)
		var b: Button = tabs[k]
		var active: bool = (k == tab_name)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.bg_color = CG_ORANGE if active else CG_PLATE
		sb.content_margin_left = 18.0
		sb.content_margin_right = 18.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		if not active:
			sb.border_width_bottom = 2
			sb.border_color = Color(0.2, 0.22, 0.26)
		for state in ["normal", "pressed", "hover", "focus"]:
			b.add_theme_stylebox_override(state, sb if active else _cg_idle_tab_sb(state))
		b.add_theme_color_override("font_color", Color.WHITE if active else CG_TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)


func _on_hip_changed(val: float):
	GlobalSettings.hip_sensitivity_mult = val
	spin_hip.value = val

func _on_hip_changed_from_spin(val: float):
	GlobalSettings.hip_sensitivity_mult = val
	slider_hip.value = val

func _on_scope_changed(val: float):
	GlobalSettings.scope_sensitivity_mult = val
	spin_scope.value = val

func _on_scope_changed_from_spin(val: float):
	GlobalSettings.scope_sensitivity_mult = val
	slider_scope.value = val

func _on_bgm_changed(val: float) -> void:
	GlobalSettings.bgm_vol = val
	var sfx = get_node_or_null("/root/Sfx")
	if sfx and sfx.has_method("apply_volumes"):
		sfx.apply_volumes()

func _on_sfx_changed(val: float) -> void:
	GlobalSettings.sfx_vol = val
	var sfx = get_node_or_null("/root/Sfx")
	if sfx and sfx.has_method("apply_volumes"):
		sfx.apply_volumes()

func _on_mic_changed(val: float) -> void:
	GlobalSettings.mic_vol = val


func _on_fullscreen_toggled(on: bool) -> void:
	# Fullscreen toggle: ON = fullscreen, OFF = windowed
	GlobalSettings.set_fullscreen(on)
	GlobalSettings.save_settings()
	check_fullscreen.text = "On" if on else "Off"


func _on_back_pressed():
	GlobalSettings.save_settings()
	get_tree().change_scene_to_file(GlobalSettings.previous_scene)


# ---------------- Control Keys Guide (styled, Player / Vehicle sub-tabs) ----------------

const CG_ORANGE := Color(1.0, 0.44, 0.08)
const CG_PLATE := Color(0.11, 0.12, 0.145, 0.96)
const CG_KEY := Color(0.19, 0.205, 0.24)
const CG_TEXT := Color(0.86, 0.88, 0.92)

# [category, [[keys, description], ...]] — keys split on "+" into separate keycaps.
const CG_PLAYER_DATA := [
	["MOVEMENT", [
		["W A S D", "Move"],
		["SPACE", "Jump"],
		["SHIFT", "Sprint"],
		["CTRL / C", "Crouch"],
		["SHIFT + C", "Slide"],
		["Q / E", "Lean left / right"],
	]],
	["COMBAT", [
		["LMB", "Fire / light melee"],
		["RMB", "ADS / scope / heavy melee"],
		["R", "Reload"],
	]],
	["LOADOUT", [
		["1 / 2", "Primary / secondary weapon"],
		["3", "Melee"],
		["4", "Grenade (hold LMB to cook)"],
	]],
	["GENERAL", [
		["F", "Interact / enter vehicle"],
		["ESC", "Pause menu"],
		["~", "Toggle debug menu"],
	]],
]

const CG_VEHICLE_DATA := [
	["ALL VEHICLES", [
		["F", "Enter / exit vehicle"],
		["CTRL + 1-9", "Switch seat"],
		["ALT", "Free-look camera"],
		["V", "Look behind"],
	]],
	["HELICOPTER", [
		["W / S", "Collective up / down"],
		["A / D", "Yaw left / right"],
		["SHIFT", "Engine boost"],
		["C", "Descend / cut landing"],
	]],
	["PLANE", [
		["W / S", "Throttle up / down"],
		["A / D", "Roll"],
		["SHIFT", "Throttle up fast"],
		["SPACE", "Brake / cut power"],
		["LMB / RMB", "Missile left / right"],
	]],
	["GROUND VEHICLES", [
		["W / S", "Drive forward / back"],
		["A / D", "Steer"],
		["SPACE", "Handbrake"],
		["SHIFT", "Boost / fast accel"],
		["LMB", "Fire cannon / MG"],
	]],
]

var _cg_font: Font = null
var _cg_font_bold: FontVariation = null
var _cg_pages := {}
var _cg_tab_btns := {}

func _build_controls_guide() -> void:
	var panel: VBoxContainer = $Content/TabControlsPanel
	_cg_font = load("res://addons/GD-Sync/UI/Fonts/Outfit-Regular.ttf")
	if _cg_font != null:
		_cg_font_bold = FontVariation.new()
		_cg_font_bold.base_font = _cg_font
		_cg_font_bold.variation_embolden = 0.7

	# Title lockup
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	panel.add_child(title_row)
	title_row.add_child(_cg_label("CONTROL KEYS", 30, Color.WHITE, true))
	title_row.add_child(_cg_label("GUIDE", 30, CG_ORANGE, true))
	var underline := ColorRect.new()
	underline.color = CG_ORANGE
	underline.custom_minimum_size = Vector2(0, 3)
	panel.add_child(underline)

	# Sub-tabs
	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 10)
	panel.add_child(tabs_row)

	# Style top-level tabs and back button
	if _cg_font_bold != null:
		btn_back.add_theme_font_override("font", _cg_font_bold)
	btn_back.add_theme_stylebox_override("normal", _cg_idle_tab_sb("normal"))
	btn_back.add_theme_stylebox_override("hover", _cg_idle_tab_sb("hover"))
	btn_back.add_theme_stylebox_override("pressed", _cg_idle_tab_sb("pressed"))
	btn_back.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in tabs.keys():
		var tb: Button = tabs[k]
		if _cg_font_bold != null:
			tb.add_theme_font_override("font", _cg_font_bold)
		tb.focus_mode = Control.FOCUS_NONE
	for page in ["Player", "Vehicle"]:
		var b := Button.new()
		b.text = ("ON FOOT" if page == "Player" else "VEHICLES") + " CONTROLS"
		b.custom_minimum_size = Vector2(220, 46)
		b.focus_mode = Control.FOCUS_NONE
		if _cg_font_bold != null:
			b.add_theme_font_override("font", _cg_font_bold)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_cg_show.bind(page))
		tabs_row.add_child(b)
		_cg_tab_btns[page] = b

	# Pages share one scroll area; hidden page has no layout weight
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var data_by_page := {"Player": CG_PLAYER_DATA, "Vehicle": CG_VEHICLE_DATA}
	for page in data_by_page:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 14)
		scroll.add_child(box)
		_cg_pages[page] = box
		for cat in data_by_page[page]:
			box.add_child(_cg_category(cat[0], cat[1]))
	_cg_show("Player")

func _cg_show(page: String) -> void:
	for k in _cg_pages:
		_cg_pages[k].visible = (k == page)
	for k in _cg_tab_btns:
		var b: Button = _cg_tab_btns[k]
		var active: bool = (k == page)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.bg_color = CG_ORANGE if active else CG_PLATE
		sb.content_margin_left = 20.0
		sb.content_margin_right = 20.0
		sb.content_margin_top = 10.0
		sb.content_margin_bottom = 10.0
		if not active:
			sb.border_width_bottom = 2
			sb.border_color = Color(0.2, 0.22, 0.26)
		for state in ["normal", "pressed", "hover", "focus"]:
			b.add_theme_stylebox_override(state, sb if active else _cg_idle_tab_sb(state))
		b.add_theme_color_override("font_color", Color.WHITE if active else CG_TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)

func _cg_idle_tab_sb(_state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.bg_color = CG_PLATE
	sb.content_margin_left = 20.0
	sb.content_margin_right = 20.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	if _state == "hover":
		sb.bg_color = CG_PLATE.lightened(0.04)
		sb.border_width_bottom = 2
		sb.border_color = CG_ORANGE
	elif _state == "pressed":
		sb.bg_color = CG_PLATE.darkened(0.2)
		sb.border_width_bottom = 2
		sb.border_color = CG_ORANGE
	else:
		sb.border_width_bottom = 2
		sb.border_color = Color(0.2, 0.22, 0.26)
	return sb

func _cg_category(title: String, rows: Array) -> Control:
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CG_PLATE
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 14.0
	sb.border_width_left = 3
	sb.border_color = CG_ORANGE
	plate.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	plate.add_child(box)
	box.add_child(_cg_label(title, 15, CG_ORANGE, true))
	for r in rows:
		box.add_child(_cg_row(r[0], r[1]))
	return plate

func _cg_row(keys: String, desc: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var key_box := HBoxContainer.new()
	key_box.custom_minimum_size = Vector2(240, 0)
	key_box.add_theme_constant_override("separation", 6)
	row.add_child(key_box)
	var parts := keys.split("+")
	for i in parts.size():
		var t := parts[i].strip_edges()
		if not t.is_empty():
			if i > 0:
				key_box.add_child(_cg_label("+", 13, Color(0.6, 0.65, 0.7), true))
			key_box.add_child(_cg_keycap(t))
	var d := _cg_label(desc, 16, CG_TEXT, false)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(d)
	return row

func _cg_keycap(text: String) -> Control:
	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CG_KEY
	sb.set_corner_radius_all(5)
	sb.border_width_bottom = 3
	sb.border_color = Color(0.09, 0.095, 0.115)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	cap.add_theme_stylebox_override("panel", sb)
	cap.add_child(_cg_label(text, 15, Color.WHITE, true))
	return cap

func _cg_label(text: String, font_size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	if bold and _cg_font_bold != null:
		l.add_theme_font_override("font", _cg_font_bold)
	elif _cg_font != null:
		l.add_theme_font_override("font", _cg_font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


# ---------------- Settings tabs restyle: plate cards, scaled-up widgets ----------------

func _apply_settings_style() -> void:
	_cg_font = load("res://addons/GD-Sync/UI/Fonts/Outfit-Regular.ttf")
	if _cg_font != null:
		_cg_font_bold = FontVariation.new()
		_cg_font_bold.base_font = _cg_font
		_cg_font_bold.variation_embolden = 0.7

	var bg := get_node_or_null("Background") as ColorRect
	if bg != null:
		bg.color = Color(0.055, 0.06, 0.075)
	_add_settings_vignette()

	for panel_path in ["Content/TabVisualPanel", "Content/TabAudioPanel", "Content/TabGameplayPanel"]:
		var panel := get_node_or_null(panel_path) as VBoxContainer
		if panel == null:
			continue
		panel.add_theme_constant_override("separation", 16)
		for child in panel.get_children():
			if child is Label:
				child.text = child.text.to_upper()
				if _cg_font_bold != null:
					child.add_theme_font_override("font", _cg_font_bold)
				child.add_theme_font_size_override("font_size", 36)
			elif child is HSeparator:
				child.add_theme_color_override("separator", Color(CG_ORANGE.r, CG_ORANGE.g, CG_ORANGE.b, 0.45))
				child.custom_minimum_size = Vector2(0, 4)
			elif child is HBoxContainer:
				_wrap_plate(child)
				_style_row(child)
	_sm_style_top_bar()

func _wrap_plate(row: Control) -> void:
	var parent := row.get_parent()
	var idx := row.get_index()
	var plate := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CG_PLATE
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	plate.add_theme_stylebox_override("panel", sb)
	parent.remove_child(row)
	parent.add_child(plate)
	parent.move_child(plate, idx)
	plate.add_child(row)
func _style_row(row: HBoxContainer) -> void:
	row.custom_minimum_size = Vector2(0, 60)
	for c in row.get_children():
		if c is Label:
			c.custom_minimum_size = Vector2(320, 0)
			c.add_theme_font_size_override("font_size", 20)
			c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		elif c is HSlider:
			_style_slider(c)
		elif c is SpinBox:
			c.custom_minimum_size = Vector2(110, 42)
			c.add_theme_font_size_override("font_size", 18)
			c.alignment = HORIZONTAL_ALIGNMENT_CENTER
		elif c is OptionButton:
			_style_option(c)
		elif c is CheckButton:
			c.add_theme_font_size_override("font_size", 18)

func _style_slider(s: HSlider) -> void:
	s.custom_minimum_size = Vector2(0, 34)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(0.075, 0.08, 0.095)
	groove.set_corner_radius_all(4)
	groove.content_margin_top = 5.0
	groove.content_margin_bottom = 5.0
	s.add_theme_stylebox_override("slider", groove)
	s.add_theme_stylebox_override("grabber_area", _cg_fill_sb(CG_ORANGE))
	s.add_theme_stylebox_override("grabber_area_highlight", _cg_fill_sb(CG_ORANGE.lightened(0.15)))
	s.add_theme_icon_override("grabber", _cg_circle_icon(Color(0.92, 0.93, 0.95)))
	s.add_theme_icon_override("grabber_highlight", _cg_circle_icon(CG_ORANGE))
	s.add_theme_icon_override("grabber_disabled", _cg_circle_icon(Color(0.45, 0.47, 0.5)))

func _cg_fill_sb(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb

func _cg_circle_icon(color: Color) -> ImageTexture:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.72, 1.0])
	grad.colors = PackedColorArray([color, Color(color.r, color.g, color.b, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 24
	gt.height = 24
	return ImageTexture.create_from_image(gt.get_image())

func _style_option(o: OptionButton) -> void:
	o.custom_minimum_size = Vector2(220, 44)
	o.add_theme_font_size_override("font_size", 18)
	if _cg_font != null:
		o.add_theme_font_override("font", _cg_font)
	o.focus_mode = Control.FOCUS_NONE
	for entry in [["normal", CG_PLATE, false], ["hover", CG_PLATE.lightened(0.05), true], ["pressed", CG_PLATE.darkened(0.15), true], ["focus", CG_PLATE, false]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = entry[1]
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 16.0
		sb.content_margin_right = 16.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		if entry[2]:
			sb.border_width_bottom = 2
			sb.border_color = CG_ORANGE
		o.add_theme_stylebox_override(entry[0], sb)
	o.add_theme_color_override("font_color", CG_TEXT)
	o.add_theme_color_override("font_hover_color", Color.WHITE)
	o.add_theme_color_override("font_pressed_color", Color.WHITE)
	var pm := o.get_popup()
	if pm != null:
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(0.09, 0.095, 0.115, 0.98)
		panel.set_corner_radius_all(6)
		panel.border_width_bottom = 2
		panel.border_color = CG_ORANGE
		panel.content_margin_top = 6.0
		panel.content_margin_bottom = 6.0
		pm.add_theme_stylebox_override("panel", panel)
		pm.add_theme_font_size_override("font_size", 18)
		if _cg_font != null:
			pm.add_theme_font_override("font", _cg_font)
		var hov := StyleBoxFlat.new()
		hov.bg_color = Color(CG_ORANGE.r, CG_ORANGE.g, CG_ORANGE.b, 0.25)
		hov.content_margin_left = 12.0
		hov.content_margin_right = 12.0
		pm.add_theme_stylebox_override("hover", hov)

func _sm_style_top_bar() -> void:
	# Re-assert font sizing scaled up for top tabs
	for k in tabs:
		tabs[k].add_theme_font_size_override("font_size", 19)
	btn_back.add_theme_font_size_override("font_size", 20)

func _add_settings_vignette() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.55, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.45)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, -0.5)
	gt.width = 512
	gt.height = 512
	var vignette := TextureRect.new()
	vignette.name = "SettingsVignette"
	vignette.texture = gt
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	move_child(vignette, 1)  # above Background, below all UI
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
