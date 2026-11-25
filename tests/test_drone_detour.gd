# Drone must path AROUND a wall (detour steering), not grind into it.
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
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 1, 0)
	root.add_child(player)

	# Victim behind a wall: wall spans z -5..5, x ~2.25..2.75, 8m tall
	var victim = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	victim.name = "2"
	victim.team = "defenders"
	victim.position = Vector3(5, 1, 0)
	root.add_child(victim)
	victim.add_to_group("enemy")

	var wall := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 8.0, 10.0)
	col.shape = box
	wall.add_child(col)
	wall.position = Vector3(2.5, 0, 0)
	root.add_child(wall)

	var floor_body := StaticBody3D.new()
	var fcol := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(60, 0.5, 60)
	fcol.shape = fbox
	floor_body.add_child(fcol)
	floor_body.position = Vector3(0, -0.25, 0)
	root.add_child(floor_body)
	await process_frame
	await physics_frame

	var drone = (load("res://scenes/weapons/skills/hunter_drone.tscn") as PackedScene).instantiate()
	root.add_child(drone)
	drone.position = Vector3(0, 2, 0)
	drone.setup(player)
	await physics_frame

	check(drone.target == victim, "acquires victim behind wall")

	var stunned := false
	var crossed := false
	var last_x := 0.0
	for i in 700:
		await physics_frame
		if not is_instance_valid(drone):
			print("Drone freed frame ", i, " last_x=", last_x)
			break
		last_x = drone.global_position.x
		if i % 60 == 0:
			print("frame ", i, " state=", drone.get("_state"), " pos=", drone.global_position)
		if is_instance_valid(victim) and victim.get("is_drone_stunned"):
			stunned = true
			crossed = drone.global_position.x > 2.75
			break
	check(stunned, "drone reached victim through/around wall and delivered EMP")
	check(crossed, "drone crossed to the far side of the wall (x > 2.75)")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
