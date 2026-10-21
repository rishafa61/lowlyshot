extends SceneTree

var fails: int = 0
var checks: int = 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FAIL: %s" % msg)
	else:
		print("  PASS: %s" % msg)

func _initialize() -> void:
	if root.get_node_or_null("GlobalData") == null:
		var gd := Node.new()
		gd.set_script(load("res://scripts/global_data.gd"))
		gd.name = "GlobalData"
		root.add_child(gd)
	if root.get_node_or_null("Sfx") == null:
		var sfx := Node.new()
		sfx.set_script(load("res://scripts/sfx.gd"))
		sfx.name = "Sfx"
		root.add_child(sfx)

	var hscene: PackedScene = load("res://scenes/vehicles/helicopter.tscn")
	var heli = hscene.instantiate()
	root.add_child(heli)
	for i in 2:
		await process_frame

	var world_cam := Camera3D.new()
	root.add_child(world_cam)
	world_cam.current = true

	var mock_player_script := GDScript.new()
	mock_player_script.source_code = "extends Node3D\nvar is_piloting := false\nvar player_name := 'DoorGunner'\nvar team := 'Allies'\nvar hud: Node = null\nvar last_tracer_start := Vector3.ZERO\nvar last_tracer_end := Vector3.ZERO\nfunc _ready(): hud = Node.new()\nfunc enter_aircraft(_s): is_piloting = true\nfunc switch_aircraft_seat(_s): reparent(_s, false)\nfunc exit_aircraft(_p, _d, _v=Vector3.ZERO): is_piloting = false\nfunc take_damage(_a, _b, _c, _d, _e): pass\nfunc create_tracer(from_pos: Vector3, to_pos: Vector3, _duration: float = 0.14) -> void:\n\tlast_tracer_start = from_pos\n\tlast_tracer_end = to_pos\n"
	mock_player_script.reload()

	var p_gunner_l: Node3D = Node3D.new()
	p_gunner_l.set_script(mock_player_script)
	root.add_child(p_gunner_l)

	var p_gunner_r: Node3D = Node3D.new()
	p_gunner_r.set_script(mock_player_script)
	root.add_child(p_gunner_r)

	print("--- TEST 1: Enter Left Gunner (Seat 2) ---")
	world_cam.current = true # referee: only an explicit camera set can take focus from it
	heli.net_sync_enter(p_gunner_l, 2)
	check(heli.occupants[2] == p_gunner_l, "Left gunner seated in Pass2 (seat 2)")
	check(root.get_camera_3d() == heli.mg_cams[0], "Left GunnerCam takes viewport focus")
	check(heli.chase_cam.current == false, "Chase cam disabled for gunner")
	check(root.get_camera_3d() != heli.mg_cams[1], "Right GunnerCam inactive")

	print("--- TEST 2: Enter Right Gunner (Seat 3) ---")
	heli.net_sync_enter(p_gunner_r, 3)
	check(heli.occupants[3] == p_gunner_r, "Right gunner seated in Pass3 (seat 3)")
	# Only one local player per machine: seat 3 takes the active camera
	heli._update_active_camera(3)
	check(root.get_camera_3d() == heli.mg_cams[1], "Right GunnerCam takes viewport focus for seat 3")
	check(root.get_camera_3d() != heli.mg_cams[0], "Left GunnerCam inactive")

	print("--- TEST 3: Gunner Aim Traverse & Pitch Clamping ---")
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(500.0, -300.0) # mouse moved right and up
	# Seat 3 gunner input
	heli._input(event)
	check(heli._mg_yaw_target[1] <= 0.0, "Aim yaw responds to mouse X")
	check(heli._mg_pitch_target[1] >= 0.0, "Aim pitch responds to mouse Y")

	# Clamping test
	event.relative = Vector2(99999.0, 99999.0)
	heli._input(event)
	check(heli._mg_yaw_target[1] >= -heli.MG_MAX_YAW, "Yaw clamped to -MG_MAX_YAW")
	check(heli._mg_pitch_target[1] >= -heli.MG_PITCH_DOWN, "Pitch clamped to -MG_PITCH_DOWN")

	print("--- TEST 4: Gun Node Rotation In _process ---")
	heli._process_door_mgs(0.1)
	var mg2: Node3D = heli.mg_nodes[1]
	check(mg2 != null, "MG2 node found")
	check(absf(mg2.rotation.y - (heli._mg_base_yaw[1] + heli.mg_yaw[1])) < 0.05, "MG2 node rotated toward gunner target")

	print("--- TEST 5: Firing & Tracer Exits From Barrel Tip ---")
	heli.net_sync_switch_seat(p_gunner_l, 2, 2) # ensure active camera is seat 2
	heli._update_active_camera(2)
	heli.mg_heat[0] = 0.0
	heli._fire_door_mg(0)
	check(heli.mg_heat[0] > 0.0, "MG heat increases on fire")
	check(p_gunner_l.last_tracer_start != Vector3.ZERO, "Tracer spawned")

	var barrel_l: Node3D = heli.mg_barrels[0]
	var barrel_pos: Vector3 = barrel_l.global_position
	var tracer_start: Vector3 = p_gunner_l.last_tracer_start
	var dist_to_barrel: float = tracer_start.distance_to(barrel_pos)
	print("  tracer start: ", tracer_start, " barrel center: ", barrel_pos, " dist: ", dist_to_barrel)
	check(dist_to_barrel < 1.5, "Tracer starts right at the barrel (dist < 1.5m)")

	print("--- TEST 6: Overheat Mechanics ---")
	heli.mg_heat[0] = 99.0
	heli._fire_door_mg(0)
	check(heli.mg_overheated[0] == true, "Overheat triggers at 100%")
	var prev_heat: float = heli.mg_heat[0]
	heli._fire_door_mg(0)
	check(heli.mg_heat[0] == prev_heat, "Overheated gun cannot fire")

	print("--- TEST 7: Exit Vehicle Resets Camera ---")
	# Re-enter seat 2 so it is the active seat being exited
	heli._update_active_camera(2)
	check(root.get_camera_3d() == heli.mg_cams[0], "Seat 2 camera active before exit")
	world_cam.current = true # player exit switches back to their own camera; simulate that referee
	heli.net_sync_exit(2)
	check(heli.occupants[2] == null, "Seat 2 emptied")
	check(root.get_camera_3d() != heli.mg_cams[0], "Left GunnerCam no longer has viewport focus on exit")

	heli.queue_free()
	p_gunner_l.queue_free()
	p_gunner_r.queue_free()

	print("RESULT: %s (%d fails / %d checks)" % ["OK" if fails == 0 else "FAIL", fails, checks])
	quit(0 if fails == 0 else 1)
