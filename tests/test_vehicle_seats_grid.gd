# Multi-seat vehicle grid UI & CTRL+seat-number switching test suite
extends SceneTree

var fails := 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	_run()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	# 1. Test HUD seat grid box component
	var hud_scene = load("res://scenes/ui/hud.tscn") as PackedScene
	check(hud_scene != null, "hud.tscn loads")
	var hud = hud_scene.instantiate()
	root.add_child(hud)
	await process_frame

	# Simulate 4-seat vehicle (Humvee) HUD update: Seat 1 occupied, Seat 2,3,4 empty, current seat 0
	hud.update_aircraft_hud({
		"kind": "humvee",
		"name": "Humvee",
		"speed": 30.0,
		"hp": 500,
		"max_hp": 500,
		"seats_free": 3,
		"seats_total": 4,
		"seats_map": [true, false, false, false],
		"my_seat": 0
	})
	await process_frame
	check(hud.seat_grid_panel != null and hud.seat_grid_panel.visible, "Seat grid panel created and visible for 4-seat vehicle")
	check(hud._seat_boxes.size() == 4, "Seat grid has 4 seat squares")
	check(hud._seat_labels[0].text == "1", "First square labeled 1")
	check(hud._seat_labels[3].text == "4", "Fourth square labeled 4")

	# Check filled vs empty stylebox colors
	var sb0: StyleBoxFlat = hud._seat_boxes[0].get_theme_stylebox("panel")
	var sb1: StyleBoxFlat = hud._seat_boxes[1].get_theme_stylebox("panel")
	check(sb0 != null and sb0.bg_color.g > 0.6, "Seat 1 (occupied) has green background")
	check(sb1 != null and sb1.bg_color.a < 0.35, "Seat 2 (empty) has transparent gray background")
	check(sb0.border_width_left == 2, "My seat (seat 1) has highlighted border")

	# Single-seat vehicle or toggle off hides the panel
	hud.update_aircraft_hud({
		"kind": "aircraft",
		"speed": 200.0,
		"throttle": 0.5,
		"heat": 0.0,
		"overheated": false,
		"slot": -1,
		"missile_l": 0.0,
		"missile_r": 0.0,
		"bombs": 0,
		"flares": 0,
		"hp": 400,
		"max_hp": 400,
		"seats_map": [true], # single seat
		"my_seat": 0
	})
	await process_frame
	check(hud.seat_grid_panel.visible == false, "Seat grid hidden for single-seat aircraft")

	# 2. Test Helicopter seat switching
	var heli_scene = load("res://scenes/vehicles/helicopter.tscn") as PackedScene
	check(heli_scene != null, "helicopter.tscn loads")
	var heli = heli_scene.instantiate()
	world.add_child(heli)
	await process_frame

	var mock_player_script := GDScript.new()
	mock_player_script.source_code = "extends Node3D\nvar is_piloting := false\nvar hud = null\nfunc enter_aircraft(_s): is_piloting = true\nfunc switch_aircraft_seat(_s): reparent(_s, false)\nfunc exit_aircraft(_p, _d, _v=Vector3.ZERO): is_piloting = false\nfunc take_damage(_a, _b, _c, _d, _e): pass\n"
	mock_player_script.reload()

	var p1: Node3D = Node3D.new()
	p1.set_script(mock_player_script)
	p1.hud = hud
	world.add_child(p1)

	# Enter seat 0 (Pilot)
	heli.net_sync_enter(p1, 0)
	check(heli.occupants[0] == p1, "Player 1 enters seat 0 (Pilot)")

	# Press CTRL + 2 to switch to seat 1 (co-pilot / passenger)
	var ctrl_2 := InputEventKey.new()
	ctrl_2.pressed = true
	ctrl_2.ctrl_pressed = true
	ctrl_2.keycode = KEY_2
	heli._unhandled_input(ctrl_2)
	check(heli.occupants[0] == null, "Seat 0 emptied after switch")
	check(heli.occupants[1] == p1, "Player 1 successfully moved to Seat 1 (Seat 2)")

	# Switch back: CTRL + 1 to seat 0
	var ctrl_1 := InputEventKey.new()
	ctrl_1.pressed = true
	ctrl_1.ctrl_pressed = true
	ctrl_1.keycode = KEY_1
	heli._unhandled_input(ctrl_1)
	check(heli.occupants[0] == p1, "Player 1 switched back to Seat 0 (Seat 1 Pilot)")
	check(heli.occupants[1] == null, "Seat 1 emptied after switch back")

	# Block switch to occupied seat: Put player 2 in seat 2
	var p2: Node3D = Node3D.new()
	p2.set_script(mock_player_script)
	world.add_child(p2)
	heli.net_sync_enter(p2, 1) # Seat 1 occupied
	heli._unhandled_input(ctrl_2)
	check(heli.occupants[0] == p1, "Switch blocked: Player 1 stays in Seat 0 because Seat 1 is occupied")
	check(heli.occupants[1] == p2, "Player 2 remains undisturbed in Seat 1")

	# 3. Test Tank seat switching
	var tank_scene = load("res://scenes/vehicles/m1_abrams.tscn") as PackedScene
	check(tank_scene != null, "m1_abrams.tscn loads")
	var tank = tank_scene.instantiate()
	world.add_child(tank)
	await process_frame

	tank.net_sync_enter(p1, 0)
	check(tank.occupants[0] == p1, "Player 1 entered tank Seat 0 (Driver)")
	tank._unhandled_input(ctrl_2)
	check(tank.occupants[0] == null and tank.occupants[1] == p1, "Player 1 switched to tank Seat 1 (Turret Gunner)")
	tank._unhandled_input(ctrl_1)
	check(tank.occupants[0] == p1 and tank.occupants[1] == null, "Player 1 switched back to tank Seat 0 (Driver)")

	# 3b. Tank turret gunner dedicated FPS camera on CommanderHatch
	var gunner_cam: Camera3D = tank.get_node_or_null("Model/CommanderHatch/GunnerCam")
	check(gunner_cam != null, "Tank has GunnerCam under CommanderHatch")
	check(gunner_cam.current == false, "GunnerCam inactive while driving")
	tank.net_sync_exit(0)
	tank.net_sync_enter(p1, 1)
	check(gunner_cam.current == true, "Gunner seated: FPS GunnerCam becomes active view")
	check(tank.chase_cam.current == false, "Gunner seated: hull chase cam off")

	# Turret role mouse motion MUST ONLY rotate CommanderHatch, NOT main turret
	var turret_yaw_before: float = tank.turret_yaw
	var mm_gunner := InputEventMouseMotion.new()
	mm_gunner.relative = Vector2(80.0, -30.0)
	tank._input(mm_gunner)
	tank._process(0.2)
	check(tank.turret_yaw == turret_yaw_before, "Turret role DOES NOT rotate main turret head")
	check(tank.commander_hatch.rotation.y != 0.0, "Turret role rotates CommanderHatch yaw")

	# Turret role CANNOT fire main cannon
	var reload_before: float = tank.reload_timer
	tank._try_fire_cannon(1)
	check(tank.reload_timer == reload_before, "Turret role CANNOT fire main cannon (seat 1 blocked)")

	# Turret role Commander MG heat system
	check(tank.mg_heat == 0.0, "MG initially 0 heat")
	tank._fire_commander_mg()
	check(tank.mg_heat > 0.0, "MG fires and adds heat (heat: %.1f)" % tank.mg_heat)

	# Test overheat cutoff
	tank.mg_heat = 99.0
	tank._fire_commander_mg()
	check(tank.mg_overheated == true, "MG overheats when exceeding 100 heat")

	tank._unhandled_input(ctrl_1) # back to driver seat 0
	check(tank.chase_cam.current == true and gunner_cam.current == false, "Driver seat restores chase cam, FPS cam off")

	# Driver shell converges toward the crosshair point (camera center ray)
	tank._process(0.5) # settle chase camera onto orbit angles
	tank._try_fire_cannon()
	check(tank.reload_timer > 0.0, "Driver fires main cannon")
	var shell = null
	for c in root.get_children():
		if "source_tank" in c and c.get("source_tank") == tank:
			shell = c
	check(shell != null, "120mm shell spawned by driver")
	if shell != null:
		var cam_fwd: Vector3 = -tank.chase_cam.global_transform.basis.z.normalized()
		var align: float = shell.direction.normalized().dot(cam_fwd)
		check(align > 0.9, "Shell direction converges toward crosshair (dot %.3f)" % align)

	# 4. Test Humvee seat switching
	var humvee_scene = load("res://scenes/vehicles/humvee.tscn") as PackedScene
	check(humvee_scene != null, "humvee.tscn loads")
	var humvee = humvee_scene.instantiate()
	world.add_child(humvee)
	await process_frame

	humvee.net_sync_enter(p1, 0)
	check(humvee.occupants[0] == p1, "Player 1 entered Humvee Seat 0 (Driver)")
	var ctrl_4 := InputEventKey.new()
	ctrl_4.pressed = true
	ctrl_4.ctrl_pressed = true
	ctrl_4.keycode = KEY_4
	humvee._unhandled_input(ctrl_4)
	check(humvee.occupants[0] == null and humvee.occupants[3] == p1, "Player 1 switched to Humvee Seat 3 (Seat 4 rear-right)")

	p1.queue_free()
	p2.queue_free()
	hud.queue_free()
	heli.queue_free()
	tank.queue_free()
	humvee.queue_free()
	world.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
