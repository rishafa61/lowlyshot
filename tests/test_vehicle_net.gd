# Vehicle network puppet test — headless: verifies each vehicle controller
# accepts remote transforms via net_set_target and lerps toward them,
# so occupied vehicles move on every peer (no "crazy frog" floating rider).
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

func _test_vehicle(scene_path: String, tag: String) -> void:
	var packed: PackedScene = load(scene_path)
	check(packed != null, tag + ": scene loads")
	var v: RigidBody3D = (packed as PackedScene).instantiate()
	root.add_child(v)
	await physics_frame
	await physics_frame

	check(v.has_method("net_set_target"), tag + ": net_set_target exists")
	check(v.has_method("net_release_puppet"), tag + ": net_release_puppet exists")
	var start := v.global_position
	var want := start + Vector3(10, 5, -7)
	v.net_set_target(want, Vector3(0, 0.5, 0), Vector3.ZERO, 0.0)
	check(v.get("_net_puppet") == true, tag + ": puppet armed")
	check(v.freeze == true, tag + ": puppet frozen (no local physics fight)")
	for i in 60:
		await physics_frame
	check(v.global_position.distance_to(want) < 1.5, tag + ": follows network transform (%s)" % v.global_position)
	v.net_release_puppet()
	await physics_frame
	check(v.get("_net_puppet") == false, tag + ": puppet released")
	check(v.freeze == false, tag + ": physics resumed")
	v.queue_free()
	await process_frame

func _run() -> void:
	await _test_vehicle("res://scenes/vehicles/helicopter.tscn", "heli")
	await _test_vehicle("res://scenes/vehicles/humvee.tscn", "humvee")
	await _test_vehicle("res://scenes/vehicles/aircraft.tscn", "aircraft")
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
