# Aircraft Altitude Meter & Gatling Explosive Splash test
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
	# Autoload GlobalData
	if root.get_node_or_null("/root/GlobalData") == null:
		var gd = Node.new()
		gd.set_script(load("res://scripts/global_data.gd"))
		gd.name = "GlobalData"
		root.add_child(gd)
		await process_frame

	var world = Node3D.new()
	root.add_child(world)

	# 1. Test HUD Altitude Label setup
	var hscene := load("res://scenes/ui/hud.tscn") as PackedScene
	var hud = hscene.instantiate()
	root.add_child(hud)
	await process_frame

	var alt_lbl: Label = hud.get_node_or_null("AircraftHUD/AltitudeLabel")
	check(alt_lbl != null, "AltitudeLabel exists under AircraftHUD")
	check(alt_lbl.offset_right <= -20.0, "AltitudeLabel placed LEFT of the crosshair (offset_right=%f)" % alt_lbl.offset_right)

	# Test update_aircraft_hud updates altitude text
	hud.toggle_aircraft_hud(true)
	hud.update_aircraft_hud({
		"kind": "aircraft",
		"slot": 0,
		"throttle": 0.5,
		"speed": 80.0,
		"hp": 1000,
		"max_hp": 1000,
		"heat": 0.0,
		"overheated": false,
		"missile_l": 0.0,
		"missile_r": 0.0,
		"bombs": 2,
		"flares": 3,
		"alt": 142.6,
	})
	check(alt_lbl.visible, "AltitudeLabel is visible in aircraft HUD")
	check(alt_lbl.text.contains("143"), "Altitude rounded properly (got '%s')" % alt_lbl.text)

	# Warning color when low (< 30m)
	hud.update_aircraft_hud({
		"kind": "aircraft",
		"slot": 0,
		"throttle": 0.5,
		"speed": 80.0,
		"hp": 1000,
		"max_hp": 1000,
		"heat": 0.0,
		"overheated": false,
		"missile_l": 0.0,
		"missile_r": 0.0,
		"bombs": 2,
		"flares": 3,
		"alt": 18.0,
	})
	var low_color = alt_lbl.get_theme_color("font_color")
	check(low_color.r > low_color.g, "AltitudeLabel turns reddish warning below 30m (r=%f, g=%f)" % [low_color.r, low_color.g])

	# 2. Test Gatling Blast Radius & Damage Area
	var ascene := load("res://scenes/vehicles/aircraft.tscn") as PackedScene
	var plane = ascene.instantiate()
	world.add_child(plane)
	await physics_frame

	check(plane.GATLING_BLAST_RADIUS == 8.0, "Gatling has 8.0m blast radius (same as AGM-65 missile)")
	check(plane.GATLING_DMG == 20.0, "Gatling damage output kept at standard 20.0")

	# Target dummy to receive splash damage
	var dummy := DummyTarget.new()
	world.add_child(dummy)
	dummy.global_position = Vector3(5, 0, 0) # 5 meters from impact (inside 8m radius)
	await physics_frame

	var impact_pos := Vector3(0, 0, 0)
	plane._gatling_splash(impact_pos, null) # null direct_hit: everyone inside radius takes splash
	check(dummy.damage_received > 0.0, "Nearby target inside 8m radius took explosive splash damage (took %f)" % dummy.damage_received)
	check(dummy.damage_received <= plane.GATLING_DMG, "Gatling splash does not exceed normal gatling damage (took %f)" % dummy.damage_received)

	# Target outside 8m radius
	dummy.damage_received = 0.0
	dummy.global_position = Vector3(12, 0, 0) # 12 meters from impact (outside 8m radius)
	await physics_frame
	plane._gatling_splash(impact_pos, null)
	check(dummy.damage_received == 0.0, "Target outside 8m blast radius took NO damage")

	# 3. Test _altitude_agl raycast
	var ground := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 2, 100)
	col.shape = box
	ground.add_child(col)
	ground.position = Vector3(0, -1, 0) # ground top is at y=0
	world.add_child(ground)

	plane.global_position = Vector3(0, 75, 0)
	await physics_frame
	var agl = plane._altitude_agl()
	check(absf(agl - 75.0) < 1.0, "Aircraft _altitude_agl detects 75m height above ground (got %f)" % agl)

	# Cleanup
	hud.queue_free()
	plane.queue_free()
	dummy.queue_free()
	ground.queue_free()
	world.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)

class DummyTarget extends CharacterBody3D:
	var damage_received: float = 0.0
	func _init() -> void:
		add_to_group("enemy")
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1, 2, 1)
		col.shape = box
		add_child(col)
	func take_damage(amount: float, _attacker: String = "", _weapon: String = "", _faction: String = "", _pos: Vector3 = Vector3.ZERO) -> float:
		damage_received += amount
		return amount
