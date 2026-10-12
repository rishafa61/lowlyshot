extends SceneTree

func _init():
	print("--- Running PlayerSpawner tests ---")
	test_spawner()
	print("--- All tests passed! ---")
	quit(0)

func test_spawner():
	var root = Node3D.new()
	root.name = "Root"
	
	var spawner = PlayerSpawner.new()
	root.add_child(spawner)
	
	var sp1 = SpawnPoint.new()
	sp1.team = "attackers"
	sp1.global_position = Vector3(10, 0, 10)
	root.add_child(sp1)
	
	# Emulate SceneTree group behavior which isn't immediate in raw SceneTree script mode
	# since Node._ready adds it to group, we explicitly add here for the test runtime
	sp1.add_to_group("spawn_points")
	
	var player = spawner.spawn_player(777, "attackers")
	
	assert(player != null, "Player should be spawned")
	assert(player.name == "777", "Player peer_id name mismatch")
	assert(player.global_position.is_equal_approx(Vector3(10, 0, 10)), "Player didn't spawn at correct spawn point")
	
	spawner.free()
	sp1.free()
	player.free()
	root.free()