extends CanvasLayer

@onready var slots = [
	$WeaponMargin/VBoxContainer/Slot1,
	$WeaponMargin/VBoxContainer/Slot2,
	$WeaponMargin/VBoxContainer/Slot3,
	$WeaponMargin/VBoxContainer/Slot4
]

@onready var hp_label = $StatsMargin/VBoxContainer/HealthLabel
@onready var armor_label = $StatsMargin/VBoxContainer/ArmorLabel
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
	
	var get_color = func(faction: String):
		if faction == "Player": return "#ffeb3b" # Yellow for self
		if faction == "Ally": return "#38bdf8"   # Blue for ally
		return "#ef4444"                         # Red for enemy

	var k_col = get_color.call(killer_faction)
	var v_col = get_color.call(victim_faction)
	
	label.text = "[color=%s]%s[/color] [color=#cccccc]kill (%s)[/color] [color=%s]%s[/color]" % [k_col, killer, weapon, v_col, victim]
	
	panel.add_child(label)
	killfeed_container.add_child(panel)
	
	var tween = create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)

func show_hover_name(name_text: String, is_enemy: bool) -> void:
	crosshair_name.text = name_text
	crosshair_name.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35) if is_enemy else Color(0.35, 0.85, 1.0))
	crosshair_name.show()

func hide_hover_name() -> void:
	crosshair_name.hide()

func toggle_combat_hud(show_hud: bool) -> void:
	for node in [$StatsMargin, $WeaponMargin, $AmmoMargin, $StaminaContainer, $CrosshairContainer, $SkillMargin, $ProgressContainer, $MinimapMargin, $BowUI, $SkillDurationLabel]:
		node.visible = show_hud
	if not show_hud:
		reload_bar.hide()
		cook_bar.hide()
		hide_hover_name()

func show_spectating(name_text: String, faction: String, is_first_person: bool = false) -> void:
	var mode_str = "POV" if is_first_person else "3RD"
	spectator_label.text = "SPECTATING: %s [%s] (%s)\n(A/D cycle | E toggle mode | Scroll zoom)" % [name_text, faction, mode_str]
	spectator_label.show()

func hide_spectating() -> void:
	spectator_label.hide()

func update_weapon_slot(active_index: int) -> void:
	for i in range(slots.size()):
		if i == active_index:
			slots[i].modulate = Color(1, 1, 0, 1)
			slots[i].text = "> Slot " + str(i + 1) + " <"
		else:
			slots[i].modulate = Color(1, 1, 1, 0.5)
			slots[i].text = "  Slot " + str(i + 1) + "  "

func update_stats(hp: int, _max_hp: int, armor: int, _max_armor: int, stamina: float, max_stamina: float) -> void:
	hp_label.text = "Health: [%d]" % hp
	armor_label.text = "Armor: [%d]" % armor
	stamina_bar.max_value = max_stamina
	stamina_bar.value = stamina


func update_ammo(mag: int, reserve: int):
	ammo_label.text = "%d / %d" % [mag, reserve]

func update_reload(progress: float):
	if progress < 0.0:
		reload_bar.hide()
	else:
		reload_bar.show()
		reload_bar.value = progress * 100.0

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


func show_damage_vignette():
	blood_vignette.color = Color(1, 0, 0, 0.4)
	var tween = create_tween()
	tween.tween_property(blood_vignette, "color:a", 0.0, 0.6)

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
	var removed = 0
	for node in get_tree().get_nodes_in_group("enemy"):
		if node is CharacterBody3D:
			node.queue_free()
			removed += 1
	for node in get_tree().get_nodes_in_group("ally"):
		if node is CharacterBody3D:
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
		skill_label.modulate = Color(0.4, 1.0, 0.4)
		skill_bar.value = 1.0
	else:
		skill_label.text = "[X] " + skill_name + " (" + str(round(cooldown)) + "s)"
		skill_label.modulate = Color(1.0, 0.4, 0.4)
		skill_bar.value = 1.0 - (cooldown / max_cooldown)

func update_bow_ui(is_active: bool, charge_level: float = 0.0, bounces: int = 0):
	bow_ui.visible = is_active
	if not is_active: return
	
	bow_charge_bar.value = charge_level
	
	# Update diamond colors (empty vs filled)
	var empty = Color(0.2, 0.2, 0.2, 0.8)
	var filled = Color(0.0, 0.8, 1.0, 1.0)
	bounce_1.color = filled if bounces >= 1 else empty
	bounce_2.color = filled if bounces >= 2 else empty
