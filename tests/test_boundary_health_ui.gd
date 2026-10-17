# Boundary zone + CS-style health UI test (multiplayer-focused, offline sim)
extends SceneTree

var fails: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	_run()

func _run() -> void:
	# ---- Setup GlobalData ----
	if root.get_node_or_null("/root/GlobalData") == null:
		var gd = Node.new()
		gd.set_script(load("res://scripts/global_data.gd"))
		gd.name = "GlobalData"
		root.add_child(gd)
		await process_frame

	# ---- Load HUD ----
	var hud_scene = load("res://scenes/ui/hud.tscn") as PackedScene
	var hud = hud_scene.instantiate()
	root.add_child(hud)
	await process_frame

	# ---- Health UI CS-style test ----
	hud.update_stats(100, 100, 50, 100, 100.0, 100.0)
	check(hud.hp_label.text == "100", "Health label shows raw number '100' (got '%s')" % hud.hp_label.text)
	check(hud.armor_label.text == "50", "Armor label shows raw number '50' (got '%s')" % hud.armor_label.text)
	check(hud.health_bar.value == 100.0, "Health bar full at 100 hp")
	check(hud.armor_bar.value == 50.0, "Armor bar half at 50 armor")

	var white_col: Color = hud.hp_label.get_theme_color("font_color")
	check(white_col == Color.WHITE, "Health number is white at full HP (got %s)" % white_col)
	check(hud.health_section.modulate == Color.WHITE, "Health section normal modulate at full HP")

	# Low HP: red number + red glow section
	hud.update_stats(15, 100, 50, 100, 100.0, 100.0)
	var low_col: Color = hud.hp_label.get_theme_color("font_color")
	check(low_col.r > 0.9 and low_col.g < 0.3, "Health number turns red when hp <= 25 (got %s)" % low_col)
	check(hud.health_section.modulate.r > 1.0, "Health section glow modulate when low HP (got %s)" % hud.health_section.modulate)
	check(hud.health_bar.value == 15.0, "Health bar reflects low hp")

	# ---- Boundary zone test ----
	var zone = Node3D.new()
	zone.set_script(load("res://scripts/levels/boundary_zone.gd"))
	zone.inner_half_x = 100.0
	zone.inner_half_z = 100.0
	zone.kill_y = -10.0
	zone.warning_time = 0.6   # speed up test
	zone.max_altitude = 200.0
	root.add_child(zone)
	await process_frame

	# Player inside bounds: no warnings
	var player_scene = load("res://scenes/player/player.tscn") as PackedScene
	var p_safe = player_scene.instantiate()
	p_safe.add_to_group("player")
	root.add_child(p_safe)
	p_safe.global_position = Vector3(0, 5, 0)
	await process_frame

	# Player out of side bounds: should get warning then destroyed
	var p_out = player_scene.instantiate()
	p_out.add_to_group("player")
	root.add_child(p_out)
	p_out.global_position = Vector3(150, 5, 0) # outside inner_half_x=100
	await process_frame

	# Player below kill_y: instant void death
	var p_fall = player_scene.instantiate()
	p_fall.add_to_group("player")
	root.add_child(p_fall)
	p_fall.global_position = Vector3(0, -20, 0) # below kill_y=-10

	# Run enough frames for boundary zone to tick & count 0.6s out-of-bounds
	for i in range(80):
		await physics_frame

	check(p_fall.is_dead == true, "Player below kill_y dies instantly (void kill)")
	check(p_out.is_dead == true, "Player out of side bounds destroyed after warning period")

	# Safe player: alive + no warning shown
	check(p_safe.is_dead == false, "Player inside bounds stays alive")
	check(hud.boundary_warning.visible == false, "No boundary warning for safe player")

	# ---- Vehicle out of bounds destroyed ----
	var heli_scene = load("res://scenes/vehicles/helicopter.tscn") as PackedScene
	var heli = heli_scene.instantiate()
	heli.add_to_group("vehicles")
	root.add_child(heli)
	heli.global_position = Vector3(250, 40, 250) # outside bounds
	await process_frame

	for i in range(80):
		await physics_frame

	check(not is_instance_valid(heli) or heli.is_destroyed == true, "Vehicle outside bounds destroyed after warning period")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
