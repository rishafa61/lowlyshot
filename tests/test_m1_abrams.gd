# M1 Abrams Main Battle Tank test suite
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
	if root.get_node_or_null("/root/GlobalData") == null:
		var gd = Node.new()
		gd.set_script(load("res://scripts/global_data.gd"))
		gd.name = "GlobalData"
		root.add_child(gd)
		await process_frame

	var world = Node3D.new()
	root.add_child(world)

	# 1. Floor
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200, 1, 200)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)
	world.add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	await physics_frame

	# 2. Instantiate M1 Abrams tank
	var tank_scene = load("res://scenes/vehicles/m1_abrams.tscn") as PackedScene
	check(tank_scene != null, "m1_abrams.tscn loads successfully")
	var tank = tank_scene.instantiate()
	world.add_child(tank)
	tank.global_position = Vector3(0, 1.0, 0)
	await physics_frame
	await physics_frame

	# 3. Hierarchy & Seat checks (2 seats: driver and turret gunner)
	check(tank.seats.size() == 2, "Tank has exactly 2 seats (got %d)" % tank.seats.size())
	check(tank.occupants.size() == 2, "Occupants array initialized with 2 slots")
	check(tank.has_free_seat(), "Tank initially has free seats")
	check(tank.turret_node != null, "Turret node exists")
	check(tank.barrel_node != null, "Barrel node exists")
	check(tank.muzzle_node != null, "Muzzle node exists")
	check(tank.chase_cam != null, "ChaseCamera exists")

	# 4. Driver enters seat 0
	var mock_player_script := GDScript.new()
	mock_player_script.source_code = "extends Node3D\nvar is_piloting := false\nvar player_name := 'TankCommander'\nvar team := 'attackers'\nvar hud = null\nfunc enter_aircraft(_s): is_piloting = true\nfunc exit_aircraft(_p, _d, _v=Vector3.ZERO): is_piloting = false\nfunc take_damage(_a, _b, _c, _d, _e): pass\n"
	mock_player_script.reload()

	var p1: Node3D = Node3D.new()
	p1.set_script(mock_player_script)
	p1.hud = Node.new()
	world.add_child(p1)

	tank.net_sync_enter(p1, 0)
	check(tank.occupants[0] == p1, "Player 1 seated in Driver seat (0)")
	check(p1.is_piloting, "Player 1 set to piloting mode")
	check(tank.has_free_seat(), "Seat 1 still free for gunner")

	# 5. Turret gunner enters seat 1
	var p2: Node3D = Node3D.new()
	p2.set_script(mock_player_script)
	world.add_child(p2)

	tank.net_sync_enter(p2, 1)
	check(tank.occupants[1] == p2, "Player 2 seated in Turret Gunner seat (1)")
	check(not tank.has_free_seat(), "All 2 seats occupied (no more free seats)")

	# 6. Driving movement: W accelerates forward, pivot turn rotates yaw
	tank.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	for i in 60:
		tank._drive_input(1.0 / 60.0)
		tank.move_and_slide()
		await physics_frame
	Input.action_release("move_forward")
	var fwd_vel: float = tank.velocity.dot(-tank.global_basis.z)
	check(fwd_vel > 2.0, "Tank drives forward with W (%.2f m/s)" % fwd_vel)

	# Pivot turn while stationary
	tank.velocity = Vector3.ZERO
	var yaw_before: float = tank.rotation.y
	Input.action_press("move_left")
	for i in 40:
		tank._drive_input(1.0 / 60.0)
		await physics_frame
	Input.action_release("move_left")
	var yaw_delta := absf(tank.rotation.y - yaw_before)
	check(yaw_delta > 0.1, "Tank pivot steers on the spot (yaw delta: %.3f rad)" % yaw_delta)

	# 7. Independent turret aiming (traverse + pitch elevation limits)
	tank._target_turret_yaw = deg_to_rad(45.0)
	tank._target_cannon_pitch = deg_to_rad(15.0)
	for i in 30:
		tank._process(1.0 / 60.0)
		await process_frame
	check(absf(tank.turret_yaw - deg_to_rad(45.0)) < 0.1, "Turret traverses independently toward target (yaw: %.2f deg)" % rad_to_deg(tank.turret_yaw))
	check(absf(tank.cannon_pitch - deg_to_rad(15.0)) < 0.1, "Cannon elevates independently toward target (pitch: %.2f deg)" % rad_to_deg(tank.cannon_pitch))

	# Verify mouse movement pitch sign matches camera hover (mouse down = aim down)
	var mouse_down := InputEventMouseMotion.new()
	mouse_down.relative = Vector2(0.0, 50.0) # mouse dragged downward
	var cam_before: float = tank._cam_pitch
	var cannon_before: float = tank._target_cannon_pitch
	tank._input(mouse_down)
	check(tank._cam_pitch < cam_before, "Camera pitches down with downward mouse motion")
	check(tank._target_cannon_pitch < cannon_before, "Cannon depresses down with downward mouse motion (synchronized)")

	# 8. Main cannon firing + reload delay
	check(tank.reload_timer == 0.0, "Cannon initially ready to fire")
	tank._try_fire_cannon(0) # Driver fires
	check(tank.reload_timer > 2.5, "Reload delay applied after firing (%.2fs remaining)" % tank.reload_timer)

	# Firing again during reload must be blocked
	var old_timer: float = tank.reload_timer
	tank._try_fire_cannon(0)
	check(tank.reload_timer == old_timer, "Firing blocked during reload period")

	# Verify projectile spawned and moves along barrel forward
	var shell_found := false
	for c in root.get_children():
		if c.name.contains("TankShell") or c.has_method("explode"):
			shell_found = true
			check(c.speed > 80.0, "Shell moves with high tank muzzle velocity (%.1f m/s)" % c.speed)
			check(c.direct_damage >= 500.0, "Shell carries main battle tank damage (%.1f)" % c.direct_damage)
			c.queue_free()
			break
	check(shell_found, "120mm TankShell projectile spawned in scene")

	# 9. Exit Tank (speed guard)
	tank.velocity = Vector3(0, 0, 10.0) # Moving fast
	# Calling _unhandled_input while moving fast should block exit
	var mock_exit_event = InputEventAction.new()
	mock_exit_event.action = "vehicle_interact"
	mock_exit_event.pressed = true
	# p1 is still in seat 0
	tank._unhandled_input(mock_exit_event)
	check(tank.occupants[0] == p1, "Player cannot exit while tank is moving fast (> 2.5 m/s)")

	# Slow tank to stop, exit succeeds
	tank.velocity = Vector3.ZERO
	tank.net_sync_exit(1) # Gunner exits
	check(tank.occupants[1] == null, "Gunner exited seat 1 successfully")
	check(not p2.is_piloting, "Gunner restored from piloting mode")

	tank.net_sync_exit(0) # Driver exits
	check(tank.occupants[0] == null, "Driver exited seat 0 successfully")
	check(not p1.is_piloting, "Driver restored from piloting mode")

	# 10. Damage & Destruction
	check(tank.hp == 1200.0, "Tank initial HP is 1200")
	tank.take_damage(600.0, "Attacker", "Rocket", "defenders")
	check(tank.hp == 600.0, "Tank HP drops to 600 after damage")
	tank.take_damage(700.0, "Attacker", "Rocket", "defenders")
	check(tank.is_destroyed, "Tank destroyed when HP reaches 0")

	p1.queue_free()
	p2.queue_free()
	world.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
