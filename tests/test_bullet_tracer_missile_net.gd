extends SceneTree

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- Running test_bullet_tracer_missile_net ---")
	
	for name in ["GlobalData", "GlobalSettings"]:
		if root.get_node_or_null("/root/" + name) == null:
			var sc = load("res://scripts/%s.gd" % ("global_data" if name == "GlobalData" else "global_settings"))
			if sc:
				var gd = Node.new()
				gd.name = name
				gd.set_script(sc)
				root.add_child(gd)
	await process_frame
	
	# 1. Test MultiplayerManager tracer spawning
	var mgr_script = load("res://scripts/multiplayer/multiplayer_manager.gd")
	assert(mgr_script != null, "multiplayer_manager.gd exists")
	var mgr = Node.new()
	mgr.set_script(mgr_script)
	root.add_child(mgr)
	await process_frame
	
	var initial_root_children := root.get_child_count()
	mgr.send_tracer(Vector3(0, 1, 0), Vector3(0, 1, 50), 0.04)
	assert(root.get_child_count() > initial_root_children, "send_tracer spawned tracer mesh in root")
	
	# 2. Test utility replica instantiation: tank shell direction & position preserved
	var shell_path := "res://scenes/weapons/heavy/tank_shell.tscn"
	var fire_dir := Vector3(0.7071, 0.0, -0.7071)
	var spawn_pos := Vector3(10, 5, 20)
	mgr._instantiate_utility_replica(shell_path, spawn_pos, fire_dir, {
		"owner_name": "Tanker",
		"faction": "Ally",
	}, 1)
	
	var found_shell = null
	for child in root.get_children():
		if child.get("shooter_name") == "Tanker" and child.get("is_net_replica") == true:
			found_shell = child
			break
	assert(found_shell != null, "Tank shell replica created in tree")
	assert(found_shell.is_net_replica == true, "Tank shell marked as net replica")
	assert(found_shell.direction.distance_to(fire_dir) < 0.01, "Tank shell replica direction set correctly")
	assert(found_shell.velocity.normalized().distance_to(fire_dir) < 0.01, "Tank shell velocity derived from fire_dir")
	
	# 3. Test AT4 rocket replica with target_vehicle
	var dummy_tank := Node3D.new()
	dummy_tank.name = "TargetVehicle"
	root.add_child(dummy_tank)
	await process_frame
	
	var at4_path := "res://scenes/weapons/heavy/at4_rocket.tscn"
	mgr._instantiate_utility_replica(at4_path, spawn_pos, fire_dir, {
		"owner_name": "Soldier",
		"faction": "Ally",
		"target_path": str(dummy_tank.get_path()),
	}, 1)
	
	var found_rocket = null
	for child in root.get_children():
		if child.get("shooter_name") == "Soldier" and child.get("is_net_replica") == true:
			found_rocket = child
			break
	assert(found_rocket != null, "AT4 rocket replica created in tree")
	assert(found_rocket.target_vehicle == dummy_tank, "AT4 replica locked onto dummy_tank")
	assert(found_rocket.is_in_group("homing_missile"), "Homing AT4 added to homing_missile group")
	
	# 4. Test is_missile_inbound on MultiplayerManager
	assert(mgr.is_missile_inbound(dummy_tank) == true, "is_missile_inbound detects incoming homing rocket")
	var other_obj := Node3D.new()
	root.add_child(other_obj)
	assert(mgr.is_missile_inbound(other_obj) == false, "is_missile_inbound returns false for non-targeted node")
	
	# 5. Test aircraft ordnance replica (missile / bomb)
	mgr._instantiate_ordnance_replica("missile", spawn_pos, fire_dir * 130.0, str(dummy_tank.get_path()), "Pilot", "Ally")
	var found_ord = null
	for child in root.get_children():
		if child is AircraftOrdnance and child.is_net_replica:
			found_ord = child
			break
	assert(found_ord != null, "Aircraft ordnance replica created")
	assert(found_ord.is_net_replica == true, "Ordnance marked as net replica")
	
	# 6. Test HUD missile warning indicator
	var hud_scene = load("res://scenes/ui/hud.tscn")
	var hud = hud_scene.instantiate()
	root.add_child(hud)
	await process_frame
	
	hud.set_missile_warning(true)
	assert(hud._missile_warn_label != null, "Missile warning label created")
	assert(hud._missile_warn_label.visible == true, "Missile warning label is visible")
	assert("MISSILE DETECTED" in hud._missile_warn_label.text, "Missile warning label text matches")
	
	# Cleanup
	hud.queue_free()
	mgr.queue_free()
	dummy_tank.queue_free()
	other_obj.queue_free()
	if found_shell: found_shell.queue_free()
	if found_rocket: found_rocket.queue_free()
	if found_ord: found_ord.queue_free()
	
	print("RESULT: OK (bullet tracer and missile net verified)")
	quit(0)
