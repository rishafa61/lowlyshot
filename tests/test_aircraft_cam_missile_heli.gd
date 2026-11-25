# Aircraft camera roll-lag, missile vehicle lock-on, heli passenger bail safety
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

	# Floor so _is_grounded() ray hits
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100, 1, 100)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)
	world.add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)

	var ascene := load("res://scenes/vehicles/aircraft.tscn") as PackedScene
	var plane = ascene.instantiate()
	world.add_child(plane)
	await physics_frame
	await physics_frame

	# --- 1. Camera roll lag: ChasePivot is top_level, eases behind the plane ---
	check(plane.chase_pivot.top_level, "ChasePivot is top_level (decoupled from airframe)")
	plane.chase_cam.current = true
	plane._cam_fwd = -plane.global_basis.z
	plane._cam_up = plane.global_basis.y

	# Simulate an instant 60-degree roll (A/D input): camera must NOT snap fully
	plane.global_rotation = Vector3(0, 0, deg_to_rad(60.0))
	await physics_frame
	plane._update_camera_lag(1.0 / 60.0)
	var cam_basis: Basis = plane.chase_pivot.global_basis
	var target_right: Vector3 = plane.global_basis.x
	var dot_partial: float = cam_basis.x.dot(target_right)
	check(dot_partial > 0.2 and dot_partial < 0.999,
		"Camera roll lags behind instant bank (dot=%.3f, 1.0 would be rigid)" % dot_partial)

	# After settling time the camera catches up
	for i in 120:
		plane._update_camera_lag(1.0 / 60.0)
	var dot_settled: float = plane.chase_pivot.global_basis.x.dot(plane.global_basis.x)
	check(dot_settled > 0.99, "Camera catches up after roll stops (dot=%.3f)" % dot_settled)
	check(absf(plane.chase_pivot.global_basis.z.dot(plane.global_basis.z) - 1.0) < 0.01,
		"Camera forward stays aligned (orthonormal basis)")

	# --- 1b. Fluid camera: lag deepens while accelerating or turning over ---
	plane.global_rotation = Vector3.ZERO
	await physics_frame
	plane.linear_velocity = Vector3.ZERO
	plane.angular_velocity = Vector3.ZERO
	var pos_target: Vector3 = plane.global_position + plane.global_basis * Vector3(0, 5.2, 0)
	# Steady flight: camera closes most of a 10m gap in one frame
	plane._accel_smooth = 0.0
	plane._last_vel = Vector3.ZERO
	plane._cam_pos = pos_target + plane.global_basis * Vector3(0, 0, 10)
	plane.chase_pivot.global_position = plane._cam_pos
	plane._update_camera_lag(1.0 / 60.0)
	var gap_steady: float = plane._cam_pos.distance_to(pos_target)
	# Hard acceleration (~30 m/s^2 smoothed): same 10m gap, slower close
	plane._accel_smooth = 30.0
	plane._cam_pos = pos_target + plane.global_basis * Vector3(0, 0, 10)
	plane.chase_pivot.global_position = plane._cam_pos
	plane._update_camera_lag(1.0 / 60.0)
	var gap_accel: float = plane._cam_pos.distance_to(pos_target)
	check(gap_accel > gap_steady + 0.5,
		"Camera trails harder while accelerating (gap %.2f vs steady %.2f)" % [gap_accel, gap_steady])
	# Turning over: same instant bank, deeper lag with high roll rate.
	# Freeze the body (a rolled plane tumbles under physics) and realign the
	# camera to the unrolled airframe first — otherwise the pivot starts the
	# run still lagging from section 1's roll and the comparison is diluted.
	plane._accel_smooth = 0.0
	plane.freeze = true
	plane.global_rotation = Vector3.ZERO
	await physics_frame
	plane.angular_velocity = Vector3.ZERO
	plane._cam_fwd = -plane.global_basis.z
	plane._cam_up = plane.global_basis.y
	plane.chase_pivot.global_basis = plane.global_basis
	plane.global_rotation = Vector3(0, 0, deg_to_rad(60.0))
	await physics_frame
	for i in 8:
		plane._update_camera_lag(1.0 / 60.0)
	var dot_steady_turn: float = plane.chase_pivot.global_basis.x.dot(plane.global_basis.x)
	plane.global_rotation = Vector3.ZERO
	await physics_frame
	plane.angular_velocity = Vector3(0, 0, 5.0) # hard roll rate
	plane._cam_fwd = -plane.global_basis.z
	plane._cam_up = plane.global_basis.y
	plane.chase_pivot.global_basis = plane.global_basis
	plane.global_rotation = Vector3(0, 0, deg_to_rad(60.0))
	await physics_frame
	for i in 8:
		plane._update_camera_lag(1.0 / 60.0)
	var dot_hard_turn: float = plane.chase_pivot.global_basis.x.dot(plane.global_basis.x)
	plane.freeze = false # restore physics for later sections
	check(dot_hard_turn < dot_steady_turn - 0.1,
		"Camera lags deeper while rolling over (dot %.3f vs %.3f steady)" % [dot_hard_turn, dot_steady_turn])
	plane.angular_velocity = Vector3.ZERO

	# --- 2. Missile lock-on mechanism (AT4-style) ---
	check(plane.LOCK_MAX_PIXEL_DIST == 240.0, "Lock cone matches AT4 launcher (240px)")
	check(plane.LOCK_HOLD_TIME > 0.0, "Lock hold time configured (%.1fs)" % plane.LOCK_HOLD_TIME)
	check(not plane._locked_target, "No lock target when nothing in crosshair")

	var ord_script = load("res://scripts/vehicles/aircraft_ordnance.gd")
	var missile = ord_script.spawn_missile(Vector3.ZERO, Vector3.FORWARD, "Pilot", "Player", plane, null)
	check(missile.target_vehicle == null, "Missile without lock flies straight")
	var dummy := Node3D.new()
	missile.free()
	missile = ord_script.spawn_missile(Vector3.ZERO, Vector3.FORWARD, "Pilot", "Player", plane, dummy)
	check(missile.target_vehicle == dummy, "Missile with lock stores target vehicle")
	check(missile.turn_rate > 0.0, "Missile has homing turn rate")
	missile.free()

	# Homing: missile steers toward target over time
	missile = ord_script.spawn_missile(Vector3(0, 100, 0), Vector3.FORWARD, "Pilot", "Player", plane, null)
	world.add_child(missile)
	missile._armed = true
	var moving_target := Node3D.new()
	world.add_child(moving_target)
	moving_target.global_position = Vector3(50, 100, 0) # 90 deg to the right
	missile.target_vehicle = moving_target
	var v0: Vector3 = missile.linear_velocity.normalized()
	for i in 30:
		missile._physics_process(1.0 / 60.0)
	var v1: Vector3 = missile.linear_velocity.normalized()
	check(v0.dot(v1) < 0.99, "Missile steers toward locked target (dot=%.3f)" % v0.dot(v1))
	missile.queue_free()
	moving_target.queue_free()

	# --- 3. Heli passenger bail: player body can no longer explode the heli ---
	var hscene := load("res://scenes/vehicles/helicopter.tscn") as PackedScene
	var heli = hscene.instantiate()
	world.add_child(heli)
	await physics_frame

	var pscene := load("res://scenes/player/player.tscn") as PackedScene
	var passenger = pscene.instantiate()
	world.add_child(passenger)
	await physics_frame

	heli.net_sync_enter(passenger, 1)
	check(heli.occupants[1] == passenger, "Passenger seated in heli")
	check(not heli.is_destroyed, "Heli intact before bail")

	# Passenger exits airborne at cruise speed -> body re-contacts airframe
	heli.linear_velocity = Vector3(0, 0, -35.0) # > 32 m/s hard-crash threshold
	heli.global_rotation = Vector3(0.05, 0, 0.05)
	heli.net_sync_exit(1)
	check(not heli.is_destroyed, "Heli survives passenger exiting mid-air (seat emptied)")
	# The exited player's body touches the airframe — must NOT explode
	heli._on_impact(passenger)
	check(not heli.is_destroyed, "Heli impact from passenger body does NOT explode heli")
	check(not passenger.is_piloting, "Passenger freed from seat")

	# --- 4. Rear pylon collider sits at the VISUAL pylon (not blocking the ramp) ---
	var pylon := heli.get_node_or_null("ColRearPylon") as CollisionShape3D
	check(pylon != null, "ColRearPylon node exists")
	if pylon:
		check(pylon.position.y > 3.5 and pylon.position.z > 3.5,
			"ColRearPylon relocated to visual pylon (y=%.2f z=%.2f, was 0.9/3.2)" % [pylon.position.y, pylon.position.z])

	# --- 5. Parked engineless heli never explodes from contact bumps ---
	heli.engine_power = 0.0
	heli.linear_velocity = Vector3(0, 0, -40.0) # solver-spike simulation
	var wall := StaticBody3D.new()
	world.add_child(wall)
	heli._on_impact(wall)
	check(not heli.is_destroyed, "Parked engineless heli survives spike-speed contact")
	wall.queue_free()

	# --- 6. Aircraft reverse taxi: grounded + idle throttle + S backs up ---
	var mock_script := GDScript.new()
	mock_script.source_code = "extends Node3D\nvar is_piloting := false\nfunc enter_aircraft(_s): is_piloting = true\nfunc exit_aircraft(_p, _d, _v=Vector3.ZERO): is_piloting = false\nfunc take_damage(_a, _b, _c, _d, _e): pass\n"
	mock_script.reload()
	var pilot: Node3D = Node3D.new()
	pilot.set_script(mock_script)
	world.add_child(pilot)
	plane.net_sync_enter(pilot, 0)
	plane.throttle = 0.0
	plane.can_sleep = false
	plane.global_transform = Transform3D(Basis(), Vector3(0, 1.5, 40))
	plane.linear_velocity = Vector3.ZERO
	plane.angular_velocity = Vector3.ZERO
	Input.action_press("move_backward")
	var reverse_speed := 0.0
	for i in 60:
		await physics_frame
		# reverse is +global_basis.z (opposite of forward = -z)
		reverse_speed = plane.linear_velocity.dot(plane.global_basis.z)
	Input.action_release("move_backward")
	check(reverse_speed > 0.5, "Aircraft reverses on ground with S (%.2f m/s backward)" % reverse_speed)
	# --- 7. Aircraft look behind: V flips camera to rear ---
	plane.chase_cam.current = true
	plane.active_pilot = pilot # pilot seated for input check
	plane._cam_fwd = -plane.global_basis.z
	plane._cam_up = plane.global_basis.y
	plane._update_camera_lag(1.0 / 60.0)
	var forward_dot: float = plane._cam_fwd.dot(-plane.global_basis.z)
	check(forward_dot > 0.9, "Camera initially faces forward (dot=%.2f)" % forward_dot)

	Input.action_press("camera_look_back")
	plane._update_camera_lag(1.0 / 60.0)
	var rear_dot: float = plane._cam_fwd.dot(plane.global_basis.z)
	check(rear_dot > 0.9, "V key flips camera forward vector to tail/behind (dot=%.2f)" % rear_dot)

	Input.action_release("camera_look_back")
	plane._update_camera_lag(1.0 / 60.0)
	var forward_again: float = plane._cam_fwd.dot(-plane.global_basis.z)
	check(forward_again > 0.9, "Releasing V restores forward camera (dot=%.2f)" % forward_again)
	plane.active_pilot = null
	pilot.queue_free()

	# --- 8. SteamSync leave_lobby method exists and cleans up ---
	var sync_inst = root.get_node_or_null("/root/SteamSync")
	check(sync_inst != null and sync_inst.has_method("leave_lobby"), "SteamSync autoload has leave_lobby method")
	if sync_inst:
		sync_inst.current_lobby_id = 99999
		sync_inst.party_members.clear()
		sync_inst.party_members.append({"id": 123, "name": "Buddy"})
		sync_inst.is_steam_running = false # offline path: no real Steam calls in headless
		var fired: Array = []
		var on_left = func(): fired.append(true)
		sync_inst.lobby_left.connect(on_left, CONNECT_ONE_SHOT)
		sync_inst.leave_lobby()
		check(sync_inst.current_lobby_id == 0, "leave_lobby resets current_lobby_id to 0")
		check(sync_inst.party_members.is_empty(), "leave_lobby clears party members")
		check(not fired.is_empty(), "leave_lobby emits lobby_left signal")
		sync_inst.is_steam_running = true

	plane.queue_free()
	heli.queue_free()
	passenger.queue_free()
	world.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
