extends CanvasLayer

@onready var slots = [
	$WeaponMargin/VBoxContainer/Slot1,
	$WeaponMargin/VBoxContainer/Slot2,
	$WeaponMargin/VBoxContainer/Slot3,
	$WeaponMargin/VBoxContainer/Slot4,
	$WeaponMargin/VBoxContainer/Slot5
]

# Per-slot equipped weapon names (1 Primary, 2 Secondary, 3 Melee, 4 Equip1, 5 Equip2)
var weapon_slot_names: Array = ["Primary", "Secondary", "Melee", "Equip 1", "Equip 2"]

@onready var hp_label = $StatsMargin/StatsPanel/StatsRow/HealthSection/HealthTop/HealthLabel
@onready var armor_label = $StatsMargin/StatsPanel/StatsRow/ArmorSection/ArmorTop/ArmorLabel
@onready var health_bar = $StatsMargin/StatsPanel/StatsRow/HealthSection/HealthBar
@onready var armor_bar = $StatsMargin/StatsPanel/StatsRow/ArmorSection/ArmorBar
@onready var health_section = $StatsMargin/StatsPanel/StatsRow/HealthSection
@onready var stamina_bar = $StaminaContainer/StaminaBar
@onready var hit_marker = $ProgressContainer/HitMarker
@onready var blood_vignette = $BloodVignette
@onready var ammo_label = $AmmoMargin/AmmoLabel
@onready var reload_bar = $ProgressContainer/ReloadBar
@onready var cook_bar = $ProgressContainer/CookBar
@onready var skill_label = $SkillMargin/VBox/SkillLabel
@onready var skill_bar = $SkillMargin/VBox/SkillBar
@onready var skill_duration_label = $SkillDurationLabel
@onready var bow_ui = $BowUI
@onready var bow_charge_bar = $BowUI/ChargeBar
@onready var bounce_1 = $BowUI/Bounces/Bounce1/Rect
@onready var bounce_2 = $BowUI/Bounces/Bounce2/Rect
@onready var killfeed_container = $KillfeedContainer
@onready var crosshair_name = $CrosshairName
@onready var spectator_label = $SpectatorLabel
@onready var aircraft_hud = $AircraftHUD
@onready var heat_bar = $AircraftHUD/HeatBar
@onready var overheat_label = $AircraftHUD/OverheatLabel
@onready var altitude_label = $AircraftHUD/AltitudeLabel
@onready var loadout_label = $AircraftHUD/LoadoutPanel
@onready var heli_guide = $AircraftHUD/HeliGuide
@onready var heli_guide_title = $AircraftHUD/HeliGuide/VBox/Title
@onready var heli_guide_text = $AircraftHUD/HeliGuide/VBox/GuideText
@onready var boundary_warning = $BoundaryWarning
@onready var boundary_countdown = $BoundaryWarning/VBox/WarnCountdown

# Vehicle seat grid (bottom right corner UI for multi-seat vehicles)
var seat_grid_panel: PanelContainer = null
var seat_grid_container: GridContainer = null
var seat_grid_hint: Label = null
var _seat_boxes: Array[PanelContainer] = []
var _seat_labels: Array[Label] = []

# Console nodes
@onready var console_container = $ConsoleLayer/ConsoleContainer
@onready var log_label = $ConsoleLayer/ConsoleContainer/VBoxContainer/LogScrollContainer/LogContainer/LogLabel
@onready var log_scroll = $ConsoleLayer/ConsoleContainer/VBoxContainer/LogScrollContainer
@onready var input_line = $ConsoleLayer/ConsoleContainer/VBoxContainer/InputContainer/InputLine
@onready var suggestions_box = $ConsoleLayer/ConsoleContainer/VBoxContainer/SuggestionsBox

# Console state
var console_visible: bool = false
var show_fps: bool = false
var show_velocity: bool = false
var command_history: Array[String] = []
var history_index: int = -1

const AVAILABLE_COMMANDS: Array[String] = [
	"show_fps 0",
	"show_fps 1",
	"show_velocity 0",
	"show_velocity 1",
	"spawn_bot_ally 1",
	"spawn_bot_enemy 1",
	"kick_bots 1",
	"spectator 0",
	"spectator 1",
	"clear",
	"help",
	"quit"
]

var displayed_speed: float = 0.0

# Minimap
@onready var minimap_clip = $MinimapMargin/MinimapBG/MinimapClip
@onready var map_pivot = $MinimapMargin/MinimapBG/MinimapClip/MapPivot
@onready var map_world = $MinimapMargin/MinimapBG/MinimapClip/MapPivot/MapWorld
@onready var map_texture = $MinimapMargin/MinimapBG/MinimapClip/MapPivot/MapWorld/MapTexture
var enemy_blips = {}
const MAP_SCALE = 5.0 # 1 meter in 3D = 5 pixels on map


func _ready():
	# Minimap initialization
	if GlobalSettings.get("current_minimap") != null and GlobalSettings.current_minimap != "":
		var tex = load(GlobalSettings.current_minimap)
		if tex:
			map_texture.texture = tex
			map_texture.show()
	else:
		map_texture.hide()
	
	console_container.hide()
	input_line.text_submitted.connect(_on_console_submit)
	input_line.text_changed.connect(_on_input_changed)
	input_line.gui_input.connect(_on_input_gui)
	suggestions_box.item_activated.connect(_on_suggestion_selected)
	$ConsoleLayer/ConsoleContainer/VBoxContainer/HeaderBar/CloseButton.pressed.connect(toggle_console)
	
	# Set initial text without awaiting so _ready doesn't yield
	log_label.text = "Counter-Strike Console initialized.\nType 'help' for a list of commands."
	
	reload_bar.hide()
	cook_bar.hide()
	hit_marker.modulate.a = 0.0
	bow_ui.hide()
	skill_duration_label.hide()
	heat_bar.hide()
	overheat_label.hide()
	_style_heat_bar()
	_style_weapon_slots()
	_style_ammo_counter()
	_style_tactical_hud()
	_build_launcher_lock_ui()
	
	GlobalData.combat_logged.connect(print_to_console)
	GlobalData.kill_occurred.connect(_on_kill_occurred)


func _on_kill_occurred(killer: String, killer_faction: String, weapon: String, victim: String, victim_faction: String) -> void:
	add_killfeed_entry(killer, killer_faction, weapon, victim, victim_faction)

func add_killfeed_entry(killer: String, killer_faction: String, weapon: String, victim: String, victim_faction: String) -> void:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.7)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	panel.add_theme_stylebox_override("panel", style)
	
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.scroll_active = false
	label.custom_minimum_size = Vector2(0, 18)
	
	var viewer_name := ""
	var vp := get_parent()
	if vp and vp.get("player_name") != null:
		viewer_name = str(vp.get("player_name"))
	elif vp and vp.name != "":
		# In multiplayer player node name is str(peer_id); host may be "1" or "Player"
		viewer_name = str(vp.name)
	if viewer_name == "1":
		viewer_name = "Player"

	var get_color = func(faction: String, pname: String) -> String:
		# Self always yellow; resolve teammates/enemies viewer-relative
		# so each player colors the same kill their own way
		if pname != "" and pname == viewer_name:
			return "#ffeb3b"
		var mgr = _mp_manager()
		if mgr and mgr.get("match_stats") != null and mgr.match_stats.has(pname):
			var my_team := _viewer_team(mgr)
			var their_team: String = str(mgr.match_stats[pname].get("team", ""))
			if my_team != "" and their_team != "":
				return "#38bdf8" if their_team == my_team else "#ef4444"
		if faction == "Player": return "#ffeb3b" # Yellow for self
		if faction == "Ally": return "#38bdf8"   # Blue for ally
		return "#ef4444"                         # Red for enemy

	var k_col = get_color.call(killer_faction, killer)
	var v_col = get_color.call(victim_faction, victim)
	
	label.text = "[color=%s]%s[/color] [color=#cccccc]kill (%s)[/color] [color=%s]%s[/color]" % [k_col, killer, weapon, v_col, victim]
	
	panel.add_child(label)
	killfeed_container.add_child(panel)
	
	var tween = create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)

func _mp_manager() -> Node:
	var root = get_tree().current_scene
	if root is MultiplayerManager:
		return root
	for g in ["multiplayer_manager", "game_manager"]:
		var nodes = get_tree().get_nodes_in_group(g)
		if nodes.size() > 0:
			return nodes[0]
	return null

func _viewer_team(mgr: Node) -> String:
	var pid := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var pdata: Dictionary = mgr.get("players_data") if mgr.get("players_data") != null else {}
	return str(pdata.get(pid, {}).get("team", ""))

func show_hover_name(name_text: String, is_enemy: bool = false) -> void:
	crosshair_name.text = name_text
	crosshair_name.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35) if is_enemy else Color(0.35, 0.85, 1.0))
	crosshair_name.show()

func hide_hover_name() -> void:
	crosshair_name.hide()

# ---------------- Vehicle enter prompt ----------------
## Keycap-styled "[F] ENTER" prompt centered on the player's screen just below
## the crosshair. Shown by vehicles when the local player steps into their
## InteractArea — screen-space so it never drifts off-vehicle or behind walls.

var enter_prompt_ui: Control = null

func show_enter_prompt() -> void:
	if enter_prompt_ui == null:
		_build_enter_prompt()
	enter_prompt_ui.visible = true
	enter_prompt_ui.modulate.a = 0.0
	enter_prompt_ui.scale = Vector2.ONE * 0.85
	var tw := create_tween().set_parallel(true)
	tw.tween_property(enter_prompt_ui, "modulate:a", 1.0, 0.12)
	tw.tween_property(enter_prompt_ui, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_enter_prompt() -> void:
	if enter_prompt_ui == null or not enter_prompt_ui.visible:
		return
	var tw := create_tween()
	tw.tween_property(enter_prompt_ui, "modulate:a", 0.0, 0.1)
	tw.tween_callback(func(): enter_prompt_ui.visible = false)

func _build_enter_prompt() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(stack)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 130) # push the row just below the crosshair
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(spacer)
	enter_prompt_ui = HBoxContainer.new()
	enter_prompt_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enter_prompt_ui.add_theme_constant_override("separation", 12)
	enter_prompt_ui.resized.connect(func():
		if enter_prompt_ui != null:
			enter_prompt_ui.pivot_offset = enter_prompt_ui.size / 2.0)
	stack.add_child(enter_prompt_ui)
	# Key cap
	var key := PanelContainer.new()
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.11, 0.92)
	sb.border_color = Color(1.0, 0.78, 0.15)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	key.add_theme_stylebox_override("panel", sb)
	var key_label := Label.new()
	key_label.text = "F"
	key_label.add_theme_font_size_override("font_size", 24)
	key_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.15))
	key.add_child(key_label)
	enter_prompt_ui.add_child(key)
	# Action text
	var txt := Label.new()
	txt.text = "ENTER"
	txt.add_theme_font_size_override("font_size", 24)
	txt.add_theme_color_override("font_color", Color(0.97, 0.97, 0.97))
	txt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	txt.add_theme_constant_override("outline_size", 8)
	enter_prompt_ui.add_child(txt)

# ---------------- Generic / Resupply interaction prompt ----------------
var _interact_prompt_ui: Control = null
var _interact_key_label: Label = null
var _interact_action_label: Label = null

func show_interact_prompt(key_str: String = "F", action_str: String = "RESUPPLY AMMO") -> void:
	if _interact_prompt_ui == null:
		_build_interact_prompt()
	_interact_key_label.text = key_str
	_interact_action_label.text = action_str
	if _interact_prompt_ui.visible and _interact_prompt_ui.modulate.a > 0.8:
		return
	_interact_prompt_ui.visible = true
	_interact_prompt_ui.modulate.a = 0.0
	_interact_prompt_ui.scale = Vector2.ONE * 0.85
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_interact_prompt_ui, "modulate:a", 1.0, 0.12)
	tw.tween_property(_interact_prompt_ui, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_interact_prompt() -> void:
	if _interact_prompt_ui == null or not _interact_prompt_ui.visible:
		return
	var tw := create_tween()
	tw.tween_property(_interact_prompt_ui, "modulate:a", 0.0, 0.1)
	tw.tween_callback(func():
		if _interact_prompt_ui:
			_interact_prompt_ui.visible = false
	)

func _build_interact_prompt() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(stack)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 130)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(spacer)
	_interact_prompt_ui = HBoxContainer.new()
	_interact_prompt_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_prompt_ui.add_theme_constant_override("separation", 12)
	_interact_prompt_ui.resized.connect(func():
		if _interact_prompt_ui != null:
			_interact_prompt_ui.pivot_offset = _interact_prompt_ui.size / 2.0
	)
	stack.add_child(_interact_prompt_ui)
	var key := PanelContainer.new()
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.11, 0.92)
	sb.border_color = Color(1.0, 0.78, 0.15)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	key.add_theme_stylebox_override("panel", sb)
	_interact_key_label = Label.new()
	_interact_key_label.text = "F"
	_interact_key_label.add_theme_font_size_override("font_size", 24)
	_interact_key_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.15))
	key.add_child(_interact_key_label)
	_interact_prompt_ui.add_child(key)
	_interact_action_label = Label.new()
	_interact_action_label.text = "RESUPPLY AMMO"
	_interact_action_label.add_theme_font_size_override("font_size", 24)
	_interact_action_label.add_theme_color_override("font_color", Color(0.97, 0.97, 0.97))
	_interact_action_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_interact_action_label.add_theme_constant_override("outline_size", 8)
	_interact_prompt_ui.add_child(_interact_action_label)

# ---------------- Launcher lock indicator ----------------
## Acquisition ring around crosshair while locking; solid diamond when locked.

var lock_ui: Control = null
var lock_ring: Control = null
var lock_box: Control = null

# ---------------- Tactical HUD chrome (reference match HUD) ----------------
## Vector-drawn icons + plate styling for the match HUD: stats plate,
## adrenaline plate, minimap compass frame. No external icon assets needed.

var _tf_font: Font = null
var _tf_bold: FontVariation = null
var _skill_fill_go: StyleBoxFlat = null
var _skill_fill_cd: StyleBoxFlat = null

class TacticalIcon extends Control:
	var kind := "plus"
	var tint := Color.WHITE

	func _init(k: String = "plus", c: Color = Color.WHITE) -> void:
		kind = k
		tint = c
		custom_minimum_size = Vector2(20, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size
		match kind:
			"plus":
				var t := maxf(4.0, s.x * 0.26)
				draw_rect(Rect2((s.x - t) * 0.5, 1.0, t, s.y - 2.0), tint)
				draw_rect(Rect2(1.0, (s.y - t) * 0.5, s.x - 2.0, t), tint)
			"shield":
				var pts := PackedVector2Array([
					Vector2(2, 2), Vector2(s.x - 2, 2), Vector2(s.x - 2, s.y * 0.45),
					Vector2(s.x * 0.5, s.y - 1), Vector2(2, s.y * 0.45)])
				draw_colored_polygon(pts, tint)
			"bolt":
				var pts := PackedVector2Array([
					Vector2(s.x * 0.62, 1), Vector2(s.x * 0.2, s.y * 0.55),
					Vector2(s.x * 0.45, s.y * 0.55), Vector2(s.x * 0.34, s.y - 1),
					Vector2(s.x * 0.8, s.y * 0.42), Vector2(s.x * 0.54, s.y * 0.42)])
				draw_colored_polygon(pts, tint)
			"bullets":
				for i in 3:
					var x := 1.0 + i * (s.x - 3.0) / 3.0
					draw_rect(Rect2(x, s.y * 0.28, 3.4, s.y * 0.66), tint) # casing
					draw_rect(Rect2(x, 2.0, 3.4, s.y * 0.22), tint) # tip
			"rifle":
				draw_rect(Rect2(0, s.y * 0.42, s.x * 0.72, 3.0), tint) # barrel+body
				draw_rect(Rect2(s.x * 0.3, s.y * 0.55, 4.0, s.y * 0.4), tint) # grip
				draw_rect(Rect2(s.x * 0.44, s.y * 0.52, 4.0, s.y * 0.34), tint) # mag
				draw_rect(Rect2(s.x * 0.72, s.y * 0.34, s.x * 0.28, 5.0), tint) # stock
			"pistol":
				draw_rect(Rect2(1, s.y * 0.3, s.x - 2, 4.0), tint) # slide
				draw_rect(Rect2(s.x * 0.22, s.y * 0.3 + 4.0, 4.0, s.y * 0.5), tint) # grip
			"knife":
				draw_colored_polygon(PackedVector2Array([
					Vector2(1, s.y * 0.5), Vector2(s.x * 0.62, s.y * 0.28),
					Vector2(s.x * 0.62, s.y * 0.72)]), tint) # blade
				draw_rect(Rect2(s.x * 0.62, s.y * 0.42, s.x * 0.3, 3.0), tint) # handle
			"grenade":
				draw_circle(Vector2(s.x * 0.5, s.y * 0.62), s.x * 0.32, tint)
				draw_rect(Rect2(s.x * 0.38, 2.0, s.x * 0.24, s.y * 0.24), tint) # cap
			"rocket":
				draw_rect(Rect2(0, s.y * 0.42, s.x * 0.8, 4.0), tint) # tube
				draw_colored_polygon(PackedVector2Array([
					Vector2(s.x * 0.8, s.y * 0.3), Vector2(s.x - 1, s.y * 0.5),
					Vector2(s.x * 0.8, s.y * 0.7)]), tint) # warhead

func _style_tactical_hud() -> void:
	_tf_font = load("res://addons/GD-Sync/UI/Fonts/Outfit-Regular.ttf")
	if _tf_font != null:
		_tf_bold = FontVariation.new()
		_tf_bold.base_font = _tf_font
		_tf_bold.variation_embolden = 0.7
	_style_stats_plates()
	_style_skill_plate()
	_style_minimap_frame()
	# Retro-apply Outfit to the ammo labels built by _style_ammo_counter()
	if _tf_bold != null and ammo_mag_label != null:
		ammo_mag_label.add_theme_font_override("font", _tf_bold)
		ammo_reserve_label.add_theme_font_override("font", _tf_bold)

func _style_stats_plates() -> void:
	var panel: PanelContainer = $StatsMargin/StatsPanel
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.88)
	sb.border_color = Color(0.28, 0.32, 0.38, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", sb)

	# Health: white plus icon + big white number, red bar
	$StatsMargin/StatsPanel/StatsRow/HealthSection/HealthTop/HealthIcon.hide()
	var hp_icon := TacticalIcon.new("plus", Color.WHITE)
	hp_icon.custom_minimum_size = Vector2(20, 20)
	$StatsMargin/StatsPanel/StatsRow/HealthSection/HealthTop.add_child(hp_icon)
	$StatsMargin/StatsPanel/StatsRow/HealthSection/HealthTop.move_child(hp_icon, 0)
	if _tf_bold != null:
		hp_label.add_theme_font_override("font", _tf_bold)
	hp_label.add_theme_font_size_override("font_size", 28)
	_style_progress_bar(health_bar, Color(0.88, 0.22, 0.22), Color(0.2, 0.05, 0.05, 0.7))
	health_bar.custom_minimum_size = Vector2(150, 7)

	# Armor: blue shield icon + big blue number, blue bar
	$StatsMargin/StatsPanel/StatsRow/ArmorSection/ArmorTop/ArmorIcon.hide()
	var armor_icon := TacticalIcon.new("shield", Color(0.35, 0.65, 0.95))
	armor_icon.custom_minimum_size = Vector2(20, 20)
	$StatsMargin/StatsPanel/StatsRow/ArmorSection/ArmorTop.add_child(armor_icon)
	$StatsMargin/StatsPanel/StatsRow/ArmorSection/ArmorTop.move_child(armor_icon, 0)
	if _tf_bold != null:
		armor_label.add_theme_font_override("font", _tf_bold)
	armor_label.add_theme_font_size_override("font_size", 28)
	armor_label.add_theme_color_override("font_color", Color(0.35, 0.65, 0.95))
	_style_progress_bar(armor_bar, Color(0.35, 0.65, 0.95), Color(0.05, 0.12, 0.22, 0.7))
	armor_bar.custom_minimum_size = Vector2(110, 7)

	# Stamina strip blends into the plate style
	_style_progress_bar(stamina_bar, Color(0.55, 0.75, 0.35), Color(0.05, 0.06, 0.08, 0.7))
	stamina_bar.custom_minimum_size = Vector2(260, 6)

func _style_progress_bar(bar: ProgressBar, fill: Color, bg: Color) -> void:
	var f := StyleBoxFlat.new()
	f.bg_color = fill
	f.set_corner_radius_all(3)
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", f)
	bar.add_theme_stylebox_override("background", b)

func _style_skill_plate() -> void:
	var vbox: VBoxContainer = $SkillMargin/VBox

	# Rebuild: plate > [bolt icon + label] + bar
	vbox.remove_child(skill_label)
	vbox.remove_child(skill_bar)
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.88)
	sb.border_color = Color(0.28, 0.32, 0.38, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 8.0
	plate.add_theme_stylebox_override("panel", sb)
	vbox.add_child(plate)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 5)
	plate.add_child(inner)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	inner.add_child(row)
	row.add_child(TacticalIcon.new("bolt", Color(0.45, 0.92, 0.3)))
	row.add_child(skill_label)

	inner.add_child(skill_bar)

	if _tf_bold != null:
		skill_label.add_theme_font_override("font", _tf_bold)
	skill_label.add_theme_font_size_override("font_size", 18)
	skill_label.add_theme_color_override("font_color", Color(0.45, 0.92, 0.3))
	skill_bar.custom_minimum_size = Vector2(220, 5)
	_skill_fill_go = StyleBoxFlat.new()
	_skill_fill_go.bg_color = Color(0.45, 0.92, 0.3)
	_skill_fill_go.set_corner_radius_all(2)
	_skill_fill_cd = StyleBoxFlat.new()
	_skill_fill_cd.bg_color = Color(1.0, 0.62, 0.15)
	_skill_fill_cd.set_corner_radius_all(2)
	_style_progress_bar(skill_bar, Color(0.45, 0.92, 0.3), Color(0.05, 0.06, 0.08, 0.8))
	# Widen + raise the plate so the label never clips
	var margin: MarginContainer = $SkillMargin
	margin.offset_left = -150.0
	margin.offset_right = 150.0
	margin.offset_top = -104.0

func _style_minimap_frame() -> void:
	var mm: MarginContainer = $MinimapMargin
	# Notch-style frame drawn on top of the map square
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0, 0, 0, 0)
	fsb.border_color = Color(0.75, 0.78, 0.84, 0.6)
	fsb.set_border_width_all(2)
	fsb.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", fsb)
	mm.add_child(frame) # MarginContainer children all fill — last child draws on top

	# Compass letters pinned to the frame edges
	var bg: ColorRect = $MinimapMargin/MinimapBG
	_mk_compass_label("N", Control.PRESET_CENTER_TOP, bg)
	_mk_compass_label("S", Control.PRESET_CENTER_BOTTOM, bg)
	_mk_compass_label("W", Control.PRESET_CENTER_LEFT, bg)
	_mk_compass_label("E", Control.PRESET_CENTER_RIGHT, bg)
	# Player dot: reference-green
	$MinimapMargin/MinimapBG/PlayerDot.color = Color(0.45, 0.9, 0.3)

func _mk_compass_label(letter: String, preset: int, parent: Control) -> void:
	var l := Label.new()
	l.text = letter
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _tf_bold != null:
		l.add_theme_font_override("font", _tf_bold)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.92, 0.94, 0.97))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	l.set_anchors_preset(preset)
	match preset:
		Control.PRESET_CENTER_TOP:
			l.offset_left = -40; l.offset_right = 40; l.offset_top = 0; l.offset_bottom = 18
		Control.PRESET_CENTER_BOTTOM:
			l.offset_left = -40; l.offset_right = 40; l.offset_top = -18; l.offset_bottom = 0
		Control.PRESET_CENTER_LEFT:
			l.offset_left = 0; l.offset_right = 18; l.offset_top = -10; l.offset_bottom = 10
		Control.PRESET_CENTER_RIGHT:
			l.offset_left = -18; l.offset_right = 0; l.offset_top = -10; l.offset_bottom = 10
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _build_launcher_lock_ui() -> void:
	lock_ui = Control.new()
	lock_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	lock_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_ui.visible = false
	add_child(lock_ui)

	lock_ring = Control.new()
	lock_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_ui.add_child(lock_ring)
	# 24 arc segments arranged in a circle — dashed ring look while acquiring
	for i in 24:
		var seg := ColorRect.new()
		var angle := TAU * i / 24.0
		seg.size = Vector2(8, 3)
		seg.position = Vector2(cos(angle), sin(angle)) * 34.0 - seg.size * 0.5
		seg.pivot_offset = seg.size * 0.5
		seg.rotation = angle
		seg.color = Color(1.0, 0.85, 0.3, 0.85)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_ring.add_child(seg)

	lock_box = Control.new()
	lock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_ui.add_child(lock_box)
	# 4 corner brackets — diamond lock frame when locked
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var h := ColorRect.new()
		h.size = Vector2(16, 3)
		h.position = Vector2(corner.x * 20.0 - (8.0 if corner.x > 0 else -8.0) - 8.0, corner.y * 20.0 - 1.5)
		h.color = Color(1.0, 0.3, 0.25)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_box.add_child(h)
		var v := ColorRect.new()
		v.size = Vector2(3, 16)
		v.position = Vector2(corner.x * 20.0 - 1.5, corner.y * 20.0 - (8.0 if corner.y > 0 else -8.0) - 8.0)
		v.color = Color(1.0, 0.3, 0.25)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_box.add_child(v)

## progress 0..1 while acquiring; is_locked swaps ring for the lock diamond.
## screen_pos = projected vehicle position — indicator snaps onto the vehicle.
func show_lock_indicator(progress: float, is_locked: bool, screen_pos: Vector2 = Vector2.INF) -> void:
	if lock_ui == null:
		return
	lock_ui.visible = true
	var viewport_size := lock_ui.get_viewport().get_visible_rect().size
	var anchor := screen_pos
	if anchor == Vector2.INF:
		anchor = viewport_size * 0.5 # fallback: crosshair center
	# Keep indicator on-screen
	anchor = anchor.clamp(Vector2(30, 30), viewport_size - Vector2(30, 30))
	lock_ring.visible = not is_locked
	lock_box.visible = is_locked
	var target := lock_ring if not is_locked else lock_box
	target.position = anchor
	if not is_locked:
		lock_ring.rotation = 0.0
		lock_ring.scale = Vector2.ONE
		# Sweep highlight: brighten segments up to progress
		var segs := lock_ring.get_children()
		var lit := int(progress * segs.size())
		for i in segs.size():
			var seg := segs[i] as ColorRect
			seg.color = Color(1.0, 0.85, 0.3, 0.95) if i < lit else Color(1.0, 0.85, 0.3, 0.25)
	lock_box.rotation = 0.0

func hide_lock_indicator() -> void:
	if lock_ui:
		lock_ui.visible = false

func toggle_combat_hud(show_hud: bool) -> void:
	for node in [$StatsMargin, $WeaponMargin, $AmmoMargin, $StaminaContainer, $CrosshairContainer, $SkillMargin, $ProgressContainer, $MinimapMargin]:
		node.visible = show_hud
	# Bow/skill-duration UI are owned by the active operator skill — they may
	# only be hidden here, never force-shown (that's what left them stuck on).
	if not show_hud:
		bow_ui.hide()
		skill_duration_label.hide()
		reload_bar.hide()
		cook_bar.hide()
		hide_hover_name()

## Aircraft mode: hide the player HUD but KEEP the crosshair (aiming) and
## show the aircraft panel (loadout, heat bar, hull).
func toggle_aircraft_hud(show_aircraft: bool) -> void:
	for node in [$StatsMargin, $WeaponMargin, $AmmoMargin, $StaminaContainer, $SkillMargin, $ProgressContainer, $MinimapMargin]:
		node.visible = not show_aircraft
	if show_aircraft:
		bow_ui.hide()
		skill_duration_label.hide()
	# Keep StatsMargin visible in aircraft so the pilot can still monitor HP & Armor!
	$StatsMargin.visible = true
	aircraft_hud.visible = show_aircraft
	if not show_aircraft:
		heat_bar.hide()
		overheat_label.hide()
		altitude_label.hide()
		heli_guide.hide()
		if seat_grid_panel != null:
			seat_grid_panel.hide()

func update_aircraft_hud(d: Dictionary) -> void:
	if d.get("kind", "aircraft") == "helicopter":
		altitude_label.visible = false # heli guide panel already shows ALT
		var climb_txt := ("CLIMB +" if d.climb >= 0.0 else "DESC  ")
		var exit_txt := ("[F] WALK OUT" if d.get("can_walk_out", false) else "[F] BAIL OUT")
		var role := str(d.get("seat_role", "PASSENGER"))
		var is_heli_gunner: bool = role.begins_with("DOOR GUNNER")
		var heli_lines := [
			"%s   HULL %d/%d" % [str(d.get("name", "HELICOPTER")).to_upper(), int(d.hp), int(d.max_hp)],
			"ROLE: %s" % role,
			"ALT %4.0f m    SPD %3.0f km/h" % [d.get("alt", 0.0), d.speed],
			"%s %+.1f m/s" % [climb_txt, d.climb],
			"COLL %3.0f%%   ENG %3.0f%%" % [d.get("throttle", 0.0) * 100.0, d.get("engine", 0.0) * 100.0],
			"",
			"SEATS %d/%d OCCUPIED" % [d.get("seats_total", 6) - d.get("seats_free", 6), d.get("seats_total", 6)],
			"[CTRL+1-%d] Change Seat" % int(d.get("seats_total", 6)),
		]
		var h_val := float(d.get("heat", 0.0))
		var is_oh := bool(d.get("overheated", false))
		heat_bar.visible = is_heli_gunner
		overheat_label.visible = is_heli_gunner and is_oh
		if is_heli_gunner:
			heat_bar.value = h_val
			_update_heat_gauge(h_val, is_oh)
			heli_lines.append("DOOR MG: %s" % ("OVERHEATED" if is_oh else "HEAT %d%%" % roundi(h_val)))
			heli_lines.append("[HOLD LMB] Fire Door MG")
			heli_lines.append("[F] Exit Seat")
		else:
			heat_bar.hide()
			overheat_label.visible = false
			heli_lines.append(exit_txt)
		loadout_label.text = "\n".join(heli_lines)
		heli_guide.visible = true
		heli_guide_title.text = "HELICOPTER — %s" % role
		_update_seat_grid_box(d.get("seats_map", []), int(d.get("my_seat", -1)))
		return
	heli_guide.visible = false
	if d.get("kind", "aircraft") == "humvee":
		heat_bar.hide()
		overheat_label.visible = false
		altitude_label.visible = false
		var humvee_lines := [
			"%s   HULL %d/%d" % [str(d.get("name", "HUMVEE")).to_upper(), int(d.hp), int(d.max_hp)],
			"SPD %3.0f km/h" % d.speed,
			"SEATS %d/%d OCCUPIED" % [d.get("seats_total", 4) - d.get("seats_free", 4), d.get("seats_total", 4)],
			"",
			"[W/S] Drive    [A/D] Steer",
			"[SPACE] Brake    [F] Exit",
			"[CTRL+1-%d] Change Seat" % int(d.get("seats_total", 4)),
		]
		loadout_label.text = "\n".join(humvee_lines)
		_update_seat_grid_box(d.get("seats_map", []), int(d.get("my_seat", -1)))
		return
	if d.get("kind", "aircraft") == "tank":
		heat_bar.hide()
		overheat_label.visible = false
		altitude_label.visible = false
		var reload_sec: float = float(d.get("reload", 0.0))
		var status := "READY" if reload_sec <= 0.0 else "RELOAD %4.1fs" % reload_sec
		var is_gunner: bool = str(d.get("seat_role", "")) == "TURRET GUNNER"
		var tank_lines: Array = [
			"%s   HULL %d/%d" % [str(d.get("name", "M1 ABRAMS")).to_upper(), int(d.hp), int(d.max_hp)],
			"ROLE: %s" % str(d.get("seat_role", "CREW")),
			"SPD %3.0f km/h" % d.speed,
			"",
		]
		if is_gunner:
			var h_val := float(d.get("heat", 0.0))
			var is_oh := bool(d.get("overheated", false))
			heat_bar.visible = true
			heat_bar.value = h_val
			_update_heat_gauge(h_val, is_oh)
			overheat_label.visible = is_oh
			var mg_status := "OVERHEATED" if is_oh else "HEAT %d%%" % roundi(h_val)
			tank_lines.append("M2 BROWNING: %s" % mg_status)
			tank_lines.append("[HOLD LMB] Fire Cupola")
			tank_lines.append("[F] Exit Tank")
			tank_lines.append("[CTRL+1-%d] Change Seat" % int(d.get("seats_total", 2)))
		else:
			tank_lines.append("120mm CANNON: %s" % status)
			tank_lines.append("[LMB] Fire Cannon")
			tank_lines.append("[W/S] Drive   [A/D] Pivot")
			tank_lines.append("[F] Exit Tank")
			tank_lines.append("[CTRL+1-%d] Change Seat" % int(d.get("seats_total", 2)))
		loadout_label.text = "\n".join(tank_lines)
		_update_seat_grid_box(d.get("seats_map", []), int(d.get("my_seat", -1)))
		return
	# Gatling heat: vertical bar beside the crosshair — only while GAU-8 selected
	var gatling_selected: bool = d.get("slot", -1) == 0
	heat_bar.visible = gatling_selected
	overheat_label.visible = gatling_selected and d.overheated
	if gatling_selected:
		heat_bar.value = d.heat
		_update_heat_gauge(float(d.heat), bool(d.get("overheated", false)))
	# Altitude meter: left of the crosshair (AGL — height above ground/rooftops)
	var alt: float = float(d.get("alt", 0.0))
	altitude_label.visible = true
	altitude_label.text = "ALT %d m" % roundi(alt)
	altitude_label.add_theme_color_override("font_color",
		Color(1, 0.3, 0.25) if alt < 30.0 else Color(0.55, 1, 0.65)) # low-alt pull-up warning
	var missile_l := "RDY" if d.missile_l <= 0.0 else "%.1fs" % d.missile_l
	var missile_r := "RDY" if d.missile_r <= 0.0 else "%.1fs" % d.missile_r
	var gat := "OVERHEAT" if d.overheated else ("HEAT %d%%" % int(d.heat))
	var lines := [
		"SPD %3.0f km/h    THR %3d%%" % [d.speed, roundi(d.throttle * 100.0)],
		"HULL %d/%d" % [int(d.hp), int(d.max_hp)],
		"",
		("%s [1] GAU-8 30mm   %s" % [">" if d.slot == 0 else " ", gat]),
		("%s [2] AGM-65       L:%s  R:%s" % [">" if d.slot == 1 else " ", missile_l, missile_r]),
		("%s [3] MK-82 Bomb   x%d" % [">" if d.slot == 2 else " ", d.bombs]),
		("%s [4] Flare        x%d" % [">" if d.slot == 3 else " ", d.flares]),
		"",
		"[V] Rear View    [F] Bail"
	]
	loadout_label.text = "\n".join(lines)
	_update_seat_grid_box(d.get("seats_map", []), int(d.get("my_seat", -1)))

func _update_seat_grid_box(seats_map: Array, my_seat: int) -> void:
	var total := seats_map.size()
	if total < 2:
		if seat_grid_panel != null:
			seat_grid_panel.hide()
		return
	if seat_grid_panel == null:
		_build_seat_grid_box(total)
	seat_grid_panel.show()
	if _seat_boxes.size() != total:
		for b in _seat_boxes:
			b.queue_free()
		_seat_boxes.clear()
		_seat_labels.clear()
		seat_grid_container.columns = mini(total, 2)
		for i in total:
			var box := PanelContainer.new()
			box.custom_minimum_size = Vector2(36, 36)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var lbl := Label.new()
			lbl.text = str(i + 1)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 15)
			lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
			lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			lbl.add_theme_constant_override("outline_size", 3)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(lbl)
			seat_grid_container.add_child(box)
			_seat_boxes.append(box)
			_seat_labels.append(lbl)
		seat_grid_hint.text = "[CTRL+1-%d] SEAT" % total
	for i in total:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(3)
		var occupied: bool = i < seats_map.size() and bool(seats_map[i])
		if occupied:
			sb.bg_color = Color(0.15, 0.78, 0.25, 0.78) # green = filled
		else:
			sb.bg_color = Color(0.5, 0.5, 0.5, 0.2)     # transparent gray = empty
		if i == my_seat:
			sb.set_border_width_all(2)
			sb.border_color = Color(1.0, 1.0, 0.3, 0.95) # yellow/white border = current seat
		else:
			sb.set_border_width_all(1)
			sb.border_color = Color(0.3, 0.3, 0.3, 0.45) if not occupied else Color(0.2, 0.9, 0.3, 0.6)
		_seat_boxes[i].add_theme_stylebox_override("panel", sb)
		_seat_labels[i].modulate = Color(1, 1, 1, 1.0) if occupied else Color(1, 1, 1, 0.45)

func _build_seat_grid_box(total: int) -> void:
	seat_grid_panel = PanelContainer.new()
	seat_grid_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seat_grid_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	seat_grid_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	seat_grid_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	seat_grid_panel.offset_left = -210.0
	seat_grid_panel.offset_top = -170.0
	seat_grid_panel.offset_right = -20.0
	seat_grid_panel.offset_bottom = -20.0
	var panel_bg := StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.04, 0.04, 0.04, 0.45)
	panel_bg.set_corner_radius_all(4)
	panel_bg.content_margin_left = 8.0
	panel_bg.content_margin_right = 8.0
	panel_bg.content_margin_top = 6.0
	panel_bg.content_margin_bottom = 6.0
	seat_grid_panel.add_theme_stylebox_override("panel", panel_bg)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	seat_grid_panel.add_child(vb)
	var title_lbl := Label.new()
	title_lbl.text = "SEATS"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.85))
	title_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	title_lbl.add_theme_constant_override("outline_size", 2)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title_lbl)
	seat_grid_container = GridContainer.new()
	seat_grid_container.columns = mini(total, 2)
	seat_grid_container.add_theme_constant_override("h_separation", 6)
	seat_grid_container.add_theme_constant_override("v_separation", 6)
	seat_grid_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(seat_grid_container)
	seat_grid_hint = Label.new()
	seat_grid_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seat_grid_hint.add_theme_font_size_override("font_size", 10)
	seat_grid_hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85, 0.75))
	seat_grid_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	seat_grid_hint.add_theme_constant_override("outline_size", 2)
	seat_grid_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(seat_grid_hint)
	add_child(seat_grid_panel)

func _heat_color(heat_val: float) -> Color:
	# Gradation: 0-40% White->Yellow, 40-80% Yellow->Red, >=80% solid/pulsing Red
	var h := clampf(heat_val, 0.0, 100.0)
	if h < 40.0:
		return Color.WHITE.lerp(Color(1.0, 0.9, 0.1), h / 40.0)
	elif h < 80.0:
		return Color(1.0, 0.9, 0.1).lerp(Color(1.0, 0.15, 0.1), (h - 40.0) / 40.0)
	return Color(1.0, 0.15, 0.1)

# ---------------- Heat gauge (thermometer chrome) ----------------
## Decorative frame drawn around heat_bar: bracket end caps + graduation ticks
## + HEAT caption, styled after the reference gauge. Shared by the jet gatling,
## tank cupola MG and heli door MGs — all drive the same heat_bar column.

var heat_gauge_chrome: HeatGaugeChrome = null

func _style_heat_bar() -> void:
	heat_bar.offset_left = 36.0 # 12px column inset inside the 18px chrome frame, nudged right of crosshair
	heat_bar.offset_right = 48.0
	heat_bar.offset_top = -44.0
	heat_bar.offset_bottom = 44.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.08, 0.62)
	heat_bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color.WHITE
	heat_bar.add_theme_stylebox_override("fill", fill)
	heat_gauge_chrome = HeatGaugeChrome.new()
	heat_gauge_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_bar.get_parent().add_child(heat_gauge_chrome)
	heat_bar.get_parent().move_child(heat_gauge_chrome, 0) # draw behind the fill column
	heat_gauge_chrome.set_anchors_preset(Control.PRESET_CENTER)
	heat_gauge_chrome.offset_left = 14.0
	heat_gauge_chrome.offset_top = -64.0
	heat_gauge_chrome.offset_right = 70.0
	heat_gauge_chrome.offset_bottom = 76.0
	heat_gauge_chrome.visible = heat_bar.visible
	heat_bar.visibility_changed.connect(func() -> void:
		if heat_gauge_chrome != null:
			heat_gauge_chrome.visible = heat_bar.visible)
	# HEAT caption under the bottom cap
	var cap := Label.new()
	cap.text = "HEAT"
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", Color(0.93, 0.95, 0.97))
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	cap.add_theme_constant_override("outline_size", 3)
	cap.position = Vector2(0, 122)
	cap.size = Vector2(56, 14)
	heat_gauge_chrome.add_child(cap)
	# keep OVERHEATED text clear of the gauge
	overheat_label.offset_left = 78.0
	overheat_label.offset_right = 188.0

func _update_heat_gauge(heat_val: float, is_overheated: bool) -> void:
	heat_bar.modulate = _heat_color(heat_val)
	if heat_gauge_chrome != null:
		heat_gauge_chrome.overheated = is_overheated

class HeatGaugeChrome extends Control:
	var overheated := false:
		set(v):
			if overheated != v:
				overheated = v
				queue_redraw()

	func _draw() -> void:
		var cx: float = size.x * 0.5
		var accent: Color = Color(1.0, 0.38, 0.32) if overheated else Color(0.93, 0.95, 0.97)
		var ink: Color = Color(0.04, 0.05, 0.07, 0.95)
		var col := Rect2(cx - 9.0, 20.0, 18.0, 88.0) # frames the 12px fill column cleanly with 3px interior margin
		# column border
		draw_rect(col, ink, false, 2.0)
		# bracket end caps (trapezoid + center tab), scaled down
		var top_pts := PackedVector2Array([
			Vector2(cx - 15.0, 20.0), Vector2(cx - 6.0, 10.0), Vector2(cx - 3.0, 10.0),
			Vector2(cx - 3.0, 6.0), Vector2(cx + 3.0, 6.0), Vector2(cx + 3.0, 10.0),
			Vector2(cx + 6.0, 10.0), Vector2(cx + 15.0, 20.0)])
		var bot_pts := PackedVector2Array([
			Vector2(cx - 15.0, 108.0), Vector2(cx - 6.0, 118.0), Vector2(cx - 3.0, 118.0),
			Vector2(cx - 3.0, 122.0), Vector2(cx + 3.0, 122.0), Vector2(cx + 3.0, 118.0),
			Vector2(cx + 6.0, 118.0), Vector2(cx + 15.0, 108.0)])
		for pts in [top_pts, bot_pts]:
			var outline: PackedVector2Array = pts.duplicate()
			outline.append(pts[0])
			draw_colored_polygon(pts, accent)
			draw_polyline(outline, ink, 2.0)

func show_boundary_warning(seconds_left: float) -> void:
	boundary_warning.show()
	boundary_countdown.text = "TURN BACK OR DESTROYED IN %.1fs" % maxf(0.0, seconds_left)

func hide_boundary_warning() -> void:
	boundary_warning.hide()

func show_spectating(name_text: String, faction: String, is_first_person: bool = false) -> void:
	var mode_str = "POV" if is_first_person else "3RD"
	spectator_label.text = "SPECTATING: %s [%s] (%s)\n(A/D cycle | E toggle mode | Scroll zoom)" % [name_text, faction, mode_str]
	spectator_label.show()

func hide_spectating() -> void:
	spectator_label.hide()

func set_weapon_names(names: Array) -> void:
	for i in slots.size():
		weapon_slot_names[i] = str(names[i]) if i < names.size() else weapon_slot_names[i]
	if slots.size() > 0:
		update_weapon_slot(-1) # redraw names, no active slot change info
	# Re-mark the active slot if the player script tells us (cheap: next switch fixes it)

# ---------------- Loadout slot cards ----------------
## Reference-style weapon list: dark plates, olive-green highlight for the
## equipped slot plus a right chevron; each row gets a small vector weapon icon.

var _slot_sb_sel: StyleBoxFlat = null
var _slot_sb_idle: StyleBoxFlat = null
const SLOT_ICON_KINDS: Array[String] = ["rifle", "pistol", "knife", "grenade", "rocket"]

func _style_weapon_slots() -> void:
	var vbox := $WeaponMargin/VBoxContainer as VBoxContainer
	if vbox != null:
		vbox.add_theme_constant_override("separation", 4)
	_slot_sb_sel = _make_slot_sb(Color(0.1, 0.13, 0.06, 0.9), Color(0.48, 0.78, 0.25))
	_slot_sb_idle = _make_slot_sb(Color(0.05, 0.06, 0.08, 0.72), Color(0.32, 0.36, 0.32, 0.55))
	for i in slots.size():
		var s = slots[i]
		s.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		s.add_theme_constant_override("outline_size", 4)
		# Vector weapon icon docked left of the text (text clears it via margin)
		var icon := TacticalIcon.new(SLOT_ICON_KINDS[i] if i < SLOT_ICON_KINDS.size() else "rifle", Color(0.85, 0.88, 0.92, 0.9))
		icon.position = Vector2(10, 7)
		s.add_child(icon)
	update_weapon_slot(-1)

func _make_slot_sb(bg: Color, accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = accent
	sb.border_width_left = 3
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 36.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb

func update_weapon_slot(active_index: int) -> void:
	for i in range(slots.size()):
		var label := "%d. %s" % [i + 1, weapon_slot_names[i]]
		var is_sel := i == active_index
		slots[i].modulate = Color.WHITE
		slots[i].text = (label + "   ›") if is_sel else ("  " + label)
		if _slot_sb_sel != null:
			slots[i].add_theme_stylebox_override("normal", _slot_sb_sel if is_sel else _slot_sb_idle)
			slots[i].add_theme_color_override("font_color",
				Color(0.62, 0.88, 0.34) if is_sel else Color(0.85, 0.88, 0.93, 0.75))

func update_stats(hp: int, max_hp: int, armor: int, max_armor: int, stamina: float, max_stamina: float) -> void:
	hp_label.text = "%d" % hp
	armor_label.text = "%d" % armor
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina
	health_bar.max_value = maxf(float(max_hp), 1.0)
	health_bar.value = clampf(float(hp), 0.0, health_bar.max_value)
	armor_bar.max_value = maxf(float(max_armor), 1.0)
	armor_bar.value = clampf(float(armor), 0.0, armor_bar.max_value)
	# CS:GO low-HP peripheral cue: when hp <= 25, flash/glow bright red across number + bar
	var is_low := hp <= 25
	var hp_color := Color(1.0, 0.2, 0.2) if is_low else Color.WHITE
	hp_label.add_theme_color_override("font_color", hp_color)
	health_section.modulate = Color(1.3, 0.6, 0.6) if is_low else Color.WHITE


func update_ammo(mag: int, reserve: int):
	ammo_label.text = "%d / %d" % [mag, reserve] # legacy fallback
	if ammo_mag_label != null:
		ammo_mag_label.text = str(mag)
	if ammo_reserve_label != null:
		ammo_reserve_label.text = str(reserve)

# ---------------- Ammo counter ----------------
## Big mag number, thin slash, smaller reserve — baseline-aligned on a dark
## strip, bottom-right. Styled after the reference counter.

var ammo_mag_label: Label = null
var ammo_reserve_label: Label = null

func _style_ammo_counter() -> void:
	ammo_label.hide()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.88)
	sb.border_color = Color(0.25, 0.28, 0.32, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END # hug content, right-aligned
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 8)
	panel.add_child(hb)

	# 3 vertical bullets icon on the left
	var bullet_icon := TacticalIcon.new("bullets", Color(0.85, 0.88, 0.92, 0.85))
	bullet_icon.custom_minimum_size = Vector2(16, 26)
	hb.add_child(bullet_icon)

	ammo_mag_label = _make_ammo_label(40, Color.WHITE)
	hb.add_child(ammo_mag_label)
	var slash := _make_ammo_label(22, Color(0.55, 0.58, 0.62, 0.75))
	slash.text = "/"
	hb.add_child(slash)
	ammo_reserve_label = _make_ammo_label(24, Color(0.65, 0.68, 0.72, 0.92))
	hb.add_child(ammo_reserve_label)
	$AmmoMargin.add_child(panel)

func _make_ammo_label(size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.size_flags_vertical = Control.SIZE_SHRINK_END # baseline-align across font sizes
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

func update_reload(progress: float):
	if progress < 0.0:
		reload_bar.hide()
	else:
		reload_bar.show()
		reload_bar.value = progress * 100.0

## Center-screen floating hint that rises and fades (e.g. "Need to be closer")
func show_center_hint(hint_text: String, col: Color = Color(1.0, 0.55, 0.15)) -> void:
	var hint := Label.new()
	hint.text = hint_text
	hint.add_theme_color_override("font_color", col)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	hint.add_theme_constant_override("outline_size", 5)
	hint.add_theme_font_size_override("font_size", 20)
	hint.custom_minimum_size = Vector2(500, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$DamageTextSpawn.add_child(hint)
	hint.position = Vector2(-250, -70)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(hint, "position:y", -110.0, 0.8).as_relative()
	tween.tween_property(hint, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(hint.queue_free)

## Incoming homing missile (AT4 / AGM-65) warning for aircraft + helicopters.
## Flashing red banner + fast beeps while anything is locked onto the vehicle.
var _missile_warn_label: Label = null
var _missile_warn_until: float = 0.0

func set_missile_warning(active: bool) -> void:
	if active:
		if _missile_warn_label == null:
			_missile_warn_label = Label.new()
			_missile_warn_label.text = "▲▼ MISSILE DETECTED — DEPLOY FLARES [F] ▼▲"
			_missile_warn_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
			_missile_warn_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			_missile_warn_label.add_theme_constant_override("outline_size", 6)
			_missile_warn_label.add_theme_font_size_override("font_size", 26)
			_missile_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_missile_warn_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
			_missile_warn_label.offset_left = -300
			_missile_warn_label.offset_right = 300
			_missile_warn_label.offset_top = 70
			_missile_warn_label.offset_bottom = 106
			_missile_warn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_missile_warn_label)
		_missile_warn_until = Time.get_ticks_msec() / 1000.0 + 0.4
		if not _missile_warn_label.visible:
			_missile_warn_label.visible = true
			_missile_warn_label.modulate.a = 1.0
			Sfx.oneshot2d("beep") # lock tone; re-fires while the threat persists

func _process(_delta: float) -> void:
	# Blink + auto-hide shortly after the last frame the missile was inbound
	if _missile_warn_label != null and _missile_warn_label.visible:
		var now := Time.get_ticks_msec() / 1000.0
		if now >= _missile_warn_until:
			_missile_warn_label.visible = false
		else:
			_missile_warn_label.modulate.a = 0.45 + 0.55 * absf(sin(now * 14.0))

func show_hit_marker(damage_amount: float = 0.0):
	hit_marker.modulate.a = 1.0
	var tween = create_tween()
	tween.tween_property(hit_marker, "modulate:a", 0.0, 0.2)
	
	if damage_amount > 0.0:
		# Spawn a brand new Label for this hit so rapid-fire numbers overlap beautifully
		var floating_text = Label.new()
		floating_text.text = str(round(damage_amount))
		
		# Copy styling from the template damage_text
		floating_text.add_theme_color_override("font_color", Color(1, 0.8, 0.2, 1))
		floating_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		floating_text.add_theme_constant_override("outline_size", 4)
		floating_text.add_theme_font_size_override("font_size", 22)
		floating_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		floating_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		$DamageTextSpawn.add_child(floating_text)
		
		# Center it and bump it slightly up
		floating_text.position = Vector2(-20, -30) 
		# Randomize the horizontal pop slightly so multiple shots don't perfectly stack
		floating_text.position.x += randf_range(-15.0, 15.0)
		
		var dmg_tween = create_tween().set_parallel(true)
		dmg_tween.tween_property(floating_text, "position:y", -80.0, 0.5).as_relative()
		dmg_tween.tween_property(floating_text, "modulate:a", 0.0, 0.5)
		dmg_tween.chain().tween_callback(floating_text.queue_free)


var vignette_tween: Tween = null

func show_damage_vignette():
	# Kill old fade so stacked hits keep flash bright
	if vignette_tween and vignette_tween.is_valid():
		vignette_tween.kill()
	blood_vignette.color = Color(1, 0, 0, 0.45)
	vignette_tween = create_tween()
	vignette_tween.tween_property(blood_vignette, "color:a", 0.0, 0.8)

## Directional hit indicator: red arrow around crosshair pointing at shooter
func show_damage_direction(angle_rad: float) -> void:
	var center: Vector2 = get_viewport().get_visible_rect().size / 2.0
	var arrow := Label.new()
	arrow.text = "➤"
	arrow.add_theme_font_size_override("font_size", 34)
	arrow.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15, 0.95))
	arrow.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	arrow.add_theme_constant_override("outline_size", 5)
	arrow.custom_minimum_size = Vector2(44, 44)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.size = Vector2(44, 44)
	arrow.pivot_offset = Vector2(22, 22)
	arrow.rotation = angle_rad - PI / 2.0 # ➤ glyph faces +x; rotate so tip aims outward
	add_child(arrow)
	arrow.position = center + Vector2.UP.rotated(angle_rad) * 110.0 - Vector2(22, 22)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(arrow, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tw.chain().tween_callback(arrow.queue_free)

func show_flash_vignette(duration: float):
	blood_vignette.color = Color(1, 1, 1, 1.0)
	var tween = create_tween()
	tween.tween_interval(duration * 0.25) # Hold full white briefly
	tween.tween_property(blood_vignette, "color:a", 0.0, duration * 0.75)


func _unhandled_input(event):
	if event.is_action_pressed("debug_toggle"):
		toggle_console()
		get_viewport().set_input_as_handled()

func toggle_console():
	console_visible = !console_visible
	console_container.visible = console_visible
	if console_visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		input_line.call_deferred("grab_focus")
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_viewport().gui_release_focus()

func _on_console_submit(new_text: String):
	var cmd = new_text.strip_edges()
	input_line.clear()
	suggestions_box.hide()
	if cmd == "":
		return
	
	command_history.append(cmd)
	history_index = command_history.size()
	print_to_console("] " + cmd)
	execute_command(cmd)

func _on_input_changed(new_text: String) -> void:
	var query: String = new_text.strip_edges().to_lower()
	if query == "":
		suggestions_box.hide()
		return
	var matches: Array[String] = []
	for c in AVAILABLE_COMMANDS:
		if c.to_lower().begins_with(query):
			matches.append(c)
	# ponytail: prefix-only match; upgrade to fuzzy/substring when list grows.
	suggestions_box.clear()
	if matches.is_empty():
		suggestions_box.hide()
		return
	for m in matches:
		suggestions_box.add_item(m)
	suggestions_box.show()
	suggestions_box.select(0)
	suggestions_box.ensure_current_is_visible()

func _on_suggestion_selected(index: int) -> void:
	input_line.text = suggestions_box.get_item_text(index)
	input_line.caret_column = input_line.text.length()
	suggestions_box.hide()
	input_line.grab_focus()

func _on_input_gui(event: InputEvent) -> void:
	if not console_visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:
				if suggestions_box.visible and suggestions_box.item_count > 0:
					var sel = suggestions_box.get_selected_items()
					var idx = sel[0] if sel.size() > 0 else 0
					_on_suggestion_selected(idx)
					get_viewport().set_input_as_handled()
			KEY_UP:
				if suggestions_box.visible and suggestions_box.item_count > 0:
					var sel = suggestions_box.get_selected_items()
					var idx = (sel[0] - 1) if sel.size() > 0 else (suggestions_box.item_count - 1)
					if idx < 0: idx = suggestions_box.item_count - 1
					suggestions_box.select(idx)
					suggestions_box.ensure_current_is_visible()
					get_viewport().set_input_as_handled()
					return
				
				if command_history.is_empty():
					return
				history_index = maxi(0, history_index - 1)
				input_line.text = command_history[history_index]
				input_line.caret_column = input_line.text.length()
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				if suggestions_box.visible and suggestions_box.item_count > 0:
					var sel = suggestions_box.get_selected_items()
					var idx = (sel[0] + 1) if sel.size() > 0 else 0
					if idx >= suggestions_box.item_count: idx = 0
					suggestions_box.select(idx)
					suggestions_box.ensure_current_is_visible()
					get_viewport().set_input_as_handled()
					return
				
				if command_history.is_empty():
					return
				history_index += 1
				if history_index >= command_history.size():
					history_index = command_history.size()
					input_line.clear()
				else:
					input_line.text = command_history[history_index]
					input_line.caret_column = input_line.text.length()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				if suggestions_box.visible and suggestions_box.item_count > 0:
					var sel = suggestions_box.get_selected_items()
					if sel.size() > 0:
						_on_suggestion_selected(sel[0])
						get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				toggle_console()
				get_viewport().set_input_as_handled()

func print_to_console(msg: String):
	if log_label.text == "":
		log_label.text = msg
	else:
		log_label.text += "\n" + msg
	await get_tree().process_frame
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)

func execute_command(cmd_string: String):
	var parts = cmd_string.split(" ", false)
	if parts.size() == 0:
		return
	var cmd = parts[0].to_lower()
	var arg = parts[1] if parts.size() > 1 else ""

	match cmd:
		"show_fps", "cl_showfps":
			if arg == "1":
				show_fps = true
				print_to_console("show_fps = 1")
			elif arg == "0":
				show_fps = false
				print_to_console("show_fps = 0")
			else:
				print_to_console("Usage: show_fps 1 or 0 (current: %d)" % (1 if show_fps else 0))
		"show_velocity", "cl_showpos":
			if arg == "1":
				show_velocity = true
				print_to_console("show_velocity = 1")
			elif arg == "0":
				show_velocity = false
				print_to_console("show_velocity = 0")
			else:
				print_to_console("Usage: show_velocity 1 or 0 (current: %d)" % (1 if show_velocity else 0))
		"clear":
			log_label.text = ""
		"spawn_bot_ally":
			_spawn_bots("res://scenes/enemies/capsule_ally.tscn", arg)
		"spawn_bot_enemy":
			_spawn_bots("res://scenes/enemies/capsule_enemy.tscn", arg)
		"kick_bots":
			_kick_bots()
		"spectator":
			var players = get_tree().get_nodes_in_group("player")
			if players.size() == 0:
				print_to_console("No player in scene")
				return
			var p = players[0]
			if arg == "1":
				p.enter_spectator_mode()
				print_to_console("spectator = 1 (A/D cycle targets)")
			elif arg == "0":
				p.exit_spectator_mode()
				print_to_console("spectator = 0")
			else:
				print_to_console("Usage: spectator 1 or 0 (current: %d)" % (1 if p.is_spectating else 0))
		"help":
			print_to_console("Available commands:")
			print_to_console("  show_fps <0|1>       - Toggle FPS display")
			print_to_console("  show_velocity <0|1>  - Toggle player speed display")
			print_to_console("  spawn_bot_ally <n>   - Spawn n ally bots near player")
			print_to_console("  spawn_bot_enemy <n>  - Spawn n enemy bots near player")
			print_to_console("  kick_bots 1          - Despawn all bots")
			print_to_console("  clear                - Clear console log")
			print_to_console("  quit                 - Exit game")
		"quit", "exit":
			get_tree().quit()
		_:
			print_to_console("Unknown command: " + cmd)

func _spawn_bots(scene_path: String, count_arg: String) -> void:
	var count = 1
	if count_arg != "":
		count = count_arg.to_int()
	if count <= 0:
		print_to_console("Spawn count must be > 0")
		return
	var player_pos = Vector3.ZERO
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_pos = players[0].global_position
	var root = get_tree().current_scene
	var mgr: MultiplayerManager = root as MultiplayerManager if root is MultiplayerManager else null

	for i in count:
		var spawn_offset = Vector3(randf_range(-5, 5), 0.5, randf_range(-5, 5))
		if spawn_offset.length() < 2.0:
			spawn_offset = spawn_offset.normalized() * 2.5
		var spawn_pos = player_pos + spawn_offset
		var team = "attackers" if scene_path.contains("ally") else "defenders"
		if mgr and GlobalData.is_networked():
			if multiplayer.is_server():
				mgr.host_spawn_bot(scene_path, spawn_pos, team)
			else:
				print_to_console("Only the host can spawn bots in online matches")
				return
		else:
			var scene = load(scene_path) as PackedScene
			if not scene:
				print_to_console("Failed to load scene: " + scene_path)
				return
			var bot = scene.instantiate()
			bot.position = spawn_pos
			root.add_child(bot)
	print_to_console("Spawned %d bot(s)" % count)

func _kick_bots() -> void:
	var root = get_tree().current_scene
	var mgr: MultiplayerManager = root as MultiplayerManager if root is MultiplayerManager else null
	if mgr and GlobalData.is_networked():
		if not multiplayer.is_server():
			print_to_console("Only the host can kick bots in online matches")
			return
		print_to_console("Kicked %d bot(s)" % mgr.host_kick_bots())
		return
	# Offline: players share the ally/enemy groups (team groups), so only free
	# nodes that actually are bots.
	var removed = 0
	if mgr:
		removed = mgr.host_kick_bots()
	for node in get_tree().get_nodes_in_group("enemy") + get_tree().get_nodes_in_group("ally"):
		if node is CharacterBody3D and "bot_name" in node and not node.is_queued_for_deletion():
			node.queue_free()
			removed += 1
	print_to_console("Kicked %d bot(s)" % removed)

func update_debug(vel: Vector3):
	var text_lines: Array[String] = []
	if show_fps:
		text_lines.append("FPS: %d" % Engine.get_frames_per_second())
	if show_velocity:
		var actual_speed = Vector2(vel.x, vel.z).length()
		displayed_speed = lerp(displayed_speed, actual_speed, 0.1)
		text_lines.append("Speed: %.2f m/s" % displayed_speed)
	
	if text_lines.size() > 0:
		$OverlayStatsLabel.show()
		$OverlayStatsLabel.text = "\n".join(text_lines)
	else:
		$OverlayStatsLabel.hide()

func update_cook_bar(progress: float):
	if progress < 0.0:
		cook_bar.hide()
	else:
		cook_bar.show()
		cook_bar.value = progress * 100.0


func update_minimap(player_pos: Vector3, player_rot_y: float):
	var enemies = get_tree().get_nodes_in_group("enemy")
	
	var current_ids = []
	for e in enemies:
		if e.get("is_dead") == true:
			continue
		if e.get("health") != null and float(e.get("health")) <= 0.0:
			continue
		current_ids.append(e.get_instance_id())
	
	for id in enemy_blips.keys():
		if not current_ids.has(id):
			enemy_blips[id].queue_free()
			enemy_blips.erase(id)
	
	# Shift MapWorld so player is at local origin (0,0)
	map_world.position = Vector2(-player_pos.x * MAP_SCALE, -player_pos.z * MAP_SCALE)
	
	# Rotate Pivot so MapWorld rotates around the player
	map_pivot.rotation = -player_rot_y
	
	for e in enemies:
		if e.get("is_dead") == true or (e.get("health") != null and float(e.get("health")) <= 0.0): continue
		var id = e.get_instance_id()
		if not enemy_blips.has(id):
			var blip = ColorRect.new()
			blip.custom_minimum_size = Vector2(4, 4)
			blip.color = Color(1, 0, 0, 1)
			map_world.add_child(blip)
			enemy_blips[id] = blip
		
		# Position blips in world space
		enemy_blips[id].position = Vector2(e.global_position.x * MAP_SCALE - 2, e.global_position.z * MAP_SCALE - 2)

func update_skill_duration(duration: float):
	if duration > 0:
		skill_duration_label.show()
		skill_duration_label.text = "%.1fs" % duration
	else:
		skill_duration_label.hide()

func update_skill_ui(skill_name: String, cooldown: float, max_cooldown: float):
	if cooldown <= 0:
		skill_label.text = "[X] " + skill_name + " READY"
		skill_label.modulate = Color(0.55, 1.0, 0.45)
		skill_bar.value = 1.0
		if _skill_fill_go != null:
			skill_bar.add_theme_stylebox_override("fill", _skill_fill_go)
	else:
		skill_label.text = "[X] " + skill_name + " (" + str(round(cooldown)) + "s)"
		skill_label.modulate = Color(1.0, 0.55, 0.35)
		skill_bar.value = 1.0 - (cooldown / max_cooldown)
		if _skill_fill_cd != null:
			skill_bar.add_theme_stylebox_override("fill", _skill_fill_cd)

func update_bow_ui(is_active: bool, charge_level: float = 0.0, bounces: int = 0):
	bow_ui.visible = is_active
	if not is_active: return
	
	bow_charge_bar.value = charge_level
	
	# Update diamond colors (empty vs filled)
	var empty = Color(0.2, 0.2, 0.2, 0.8)
	var filled = Color(0.0, 0.8, 1.0, 1.0)
	bounce_1.color = filled if bounces >= 1 else empty
	bounce_2.color = filled if bounces >= 2 else empty
