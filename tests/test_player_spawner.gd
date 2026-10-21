extends SceneTree

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- Running PlayerSpawner tests ---")
	# Autoload GlobalData (player.gd depends on it)
	if root.get_node_or_null("/root/GlobalData") == null:
		var gd = Node.new()
		gd.set_script(load("res://scripts/global_data.gd"))
		gd.name = "GlobalData"
		root.add_child(gd)
		await process_frame

	test_spawner()
	print("--- All tests passed! ---")
	quit(0)

func test_spawner():
	var root_node = Node3D.new()
	root_node.name = "Root"
	root.add_child(root_node)

	var spawner = PlayerSpawner.new()
	root_node.add_child(spawner)

	var sp1 = SpawnPoint.new()
	sp1.team = "attackers"
	root_node.add_child(sp1)
	sp1.global_position = Vector3(10, 0, 10)
	sp1.add_to_group("spawn_points")

	var player = spawner.spawn_player(777, "attackers")

	assert(player != null, "Player should be spawned")
	assert(player.name == "777", "Player peer_id name mismatch")
	assert(player.global_position.is_equal_approx(Vector3(10, 0, 10)), "Player didn't spawn at correct spawn point")

	player.queue_free()
	root_node.queue_free()