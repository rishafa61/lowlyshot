# Launcher Multiplayer & Wide-Range test — headless
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
	# 1. GlobalData setup
	if root.get_node_or_null("/root/GlobalData") == null:
		var gd = Node.new()
		gd.set_script(load("res://scripts/global_data.gd"))
		gd.name = "GlobalData"
		root.add_child(gd)
		await process_frame

	# 2. Check wider acquisition range constant
	var player_script = load("res://scenes/player/player.gd")
	check(player_script != null, "player.gd loads successfully")
	# Instantiate dummy player to read constant and test lock range
	var player_scene = load("res://scenes/player/player.tscn") as PackedScene
	var player = player_scene.instantiate()
	# Strip current camera so it doesn't fail headless
	root.add_child(player)
	await process_frame

	check(player.get("LOCK_MAX_PIXEL_DIST") >= 200.0, "LOCK_MAX_PIXEL_DIST widened to >= 200px (got %f)" % player.get("LOCK_MAX_PIXEL_DIST"))

	# 3. Test AT4 rocket is_net_replica prevents duplicate damage
	var rocket_scene = load("res://scenes/weapons/heavy/at4_rocket.tscn") as PackedScene
	var dummy_vehicle = RigidBody3D.new()
	dummy_vehicle.add_to_group("vehicles")
	dummy_vehicle.global_position = Vector3(0, 0, -20)
	dummy_vehicle.set_script(load("res://scripts/vehicles/helicopter_controller.gd"))
	root.add_child(dummy_vehicle)
	var initial_hp: float = dummy_vehicle.hp

	# Authoritative rocket deals damage
	var auth_rocket = rocket_scene.instantiate()
	root.add_child(auth_rocket)
	auth_rocket.is_net_replica = false
	auth_rocket.explode(dummy_vehicle.global_position, dummy_vehicle)
	check(dummy_vehicle.hp < initial_hp, "authoritative rocket deals damage (%f -> %f)" % [initial_hp, dummy_vehicle.hp])

	# Replica rocket deals ZERO damage
	var hp_before_replica: float = dummy_vehicle.hp
	var rep_rocket = rocket_scene.instantiate()
	root.add_child(rep_rocket)
	rep_rocket.is_net_replica = true
	rep_rocket.explode(dummy_vehicle.global_position, dummy_vehicle)
	check(dummy_vehicle.hp == hp_before_replica, "replica rocket does NOT double-damage vehicle (%f == %f)" % [dummy_vehicle.hp, hp_before_replica])

	# 4. MultiplayerManager utility replication handling for AT4
	var mgr = Node.new()
	mgr.set_script(load("res://scripts/multiplayer/multiplayer_manager.gd"))
	root.add_child(mgr)
	await process_frame

	# Call _instantiate_utility_replica with at4_rocket.tscn
	mgr._instantiate_utility_replica(
		"res://scenes/weapons/heavy/at4_rocket.tscn",
		Vector3(0, 5, 0),
		Vector3.FORWARD,
		{"owner_name": "Teammate_A", "faction": "Ally"},
		42
	)
	await process_frame

	# Find replica in tree
	var found_replica: Node = null
	for c in root.get_children():
		if c.name.begins_with("AT4Rocket") and c.get("is_net_replica") == true:
			found_replica = c
			break
	check(found_replica != null, "MultiplayerManager instantiates AT4 replica")
	if found_replica:
		check(found_replica.shooter_name == "Teammate_A", "replica shooter_name assigned (%s)" % found_replica.shooter_name)
		check(found_replica.shooter_faction == "Ally", "replica shooter_faction assigned (%s)" % found_replica.shooter_faction)
		found_replica.queue_free()

	player.queue_free()
	dummy_vehicle.queue_free()
	mgr.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
