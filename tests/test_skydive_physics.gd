# Skydive & Dead-stick Aircraft physics test
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

	# Ground collider at y=0
	var ground = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(500, 2, 500)
	col.shape = box
	ground.add_child(col)
	ground.position = Vector3(0, -1, 0)
	world.add_child(ground)

	var pscene := load("res://scenes/player/player.tscn") as PackedScene
	var player = pscene.instantiate()
	world.add_child(player)
	player.global_position = Vector3(0, 100, 0) # 100m above ground
	await physics_frame
	await physics_frame

	# 1. Height detection
	check(player._is_high_above_ground(), "Player at y=100 is high above ground (>=50m)")
	player.global_position = Vector3(0, 20, 0) # 20m above ground
	await physics_frame
	check(not player._is_high_above_ground(), "Player at y=20 is NOT high above ground (<50m)")

	# 2. Skydive glide fall speed cap
	player.global_position = Vector3(0, 150, 0)
	player.velocity = Vector3.ZERO
	await physics_frame
	for i in 60:
		player._apply_fall_physics(1.0 / 60.0)
	check(player.is_skydiving, "Player enters skydive mode at y=150")
	check(absf(player.velocity.y - (-player.SKYDIVE_FALL_GLIDE)) < 2.0,
		"Fall speed capped to glide terminal (~-14 m/s, got %f)" % player.velocity.y)

	# 3. Aircraft dead-stick stability test
	var ascene := load("res://scenes/vehicles/aircraft.tscn") as PackedScene
	var plane = ascene.instantiate()
	world.add_child(plane)
	plane.global_position = Vector3(0, 100, 0)
	plane.linear_velocity = Vector3(0, -10, -35) # gliding forward and down
	plane._is_ejected = true
	plane._pilotless_time = 2.0 # well past cutoff
	await physics_frame

	var prev_basis: Basis = plane.global_basis
	plane._apply_rotation(0.05, false)
	# Dead-stick plane should align with its velocity vector, NOT flip 90 deg down
	var fwd_pitch: float = plane.global_basis.z.y # how much forward vector points up/down
	check(absf(fwd_pitch) < 0.8, "Dead-stick aircraft does not tumble cartoonishly (pitch component=%f)" % fwd_pitch)

	player.queue_free()
	plane.queue_free()
	ground.queue_free()
	world.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
