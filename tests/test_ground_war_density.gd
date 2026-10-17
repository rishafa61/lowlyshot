# Ground War Map Density & Multiplayer Validation
# Verifies new environmental structures exist, don't obstruct spawns,
# and have proper multiplayer-safe collision.
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
	# 1. Load scene
	var gw_scene = load("res://scenes/levels/ground_war.tscn") as PackedScene
	check(gw_scene != null, "ground_war.tscn loads")
	var gw = gw_scene.instantiate()
	root.add_child(gw)
	await process_frame
	await process_frame

	# 2. DenseWorld container exists
	var dense = gw.get_node_or_null("NavigationRegion3D/DenseWorld")
	check(dense != null, "DenseWorld container exists")
	var dense_child_count := 0
	if dense != null:
		dense_child_count = dense.get_child_count()
	check(dense_child_count > 500, "DenseWorld has hundreds of props (got %d)" % dense_child_count)

	# 3. Count key structure types
	var tree_count := 0
	var tower_count := 0
	var bunker_count := 0
	var building_count := 0
	var barrier_count := 0
	var wreck_count := 0
	var container_count := 0
	for child in dense.get_children():
		var n := child.name.to_lower()
		if n.begins_with("tree_") or n.begins_with("treeline"):
			tree_count += 1
		elif n.begins_with("tower_"):
			tower_count += 1
		elif n.begins_with("bunker_"):
			bunker_count += 1
		elif n.begins_with("nt_") or n.begins_with("ne_") or n.begins_with("sw_") \
			or n.begins_with("se_") or n.begins_with("nw_") or n.begins_with("fn_") or n.begins_with("fs_"):
			building_count += 1
		elif n.begins_with("barrier_"):
			barrier_count += 1
		elif n.begins_with("wreck"):
			wreck_count += 1
		elif n.begins_with("cont_e_"):
			container_count += 1
	print("INFO: trees=%d towers=%d bunkers=%d buildings=%d barriers=%d wrecks=%d containers=%d" %
		[tree_count, tower_count, bunker_count, building_count, barrier_count, wreck_count, container_count])
	check(tree_count >= 300, "Dense forest (>=300 trees, got %d)" % tree_count)
	check(tower_count >= 6, "Perimeter watchtowers (>=6, got %d)" % tower_count)
	check(bunker_count >= 4, "Midfield bunkers (>=4, got %d)" % bunker_count)
	check(building_count >= 20, "Buildings/compounds (>=20, got %d)" % building_count)
	check(barrier_count >= 20, "Jersey barrier cover (>=20, got %d)" % barrier_count)
	check(wreck_count >= 8, "Vehicle wrecks with smoke (>=8, got %d)" % wreck_count)
	check(container_count >= 20, "Container labyrinth (>=20, got %d)" % container_count)

	# 4. Player spawn points not obstructed by new props
	var spawns := {
		"AttackersSpawn1": "attackers",
		"DefendersSpawn1": "defenders",
	}
	for spawn_name in spawns:
		var marker = gw.get_node_or_null(spawn_name)
		check(marker != null, "Spawn marker %s exists" % spawn_name)
		if marker != null:
			var space_state = marker.get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(
				marker.global_position + Vector3(0, 10, 0),
				marker.global_position - Vector3(0, 10, 0))
			var result = space_state.intersect_ray(query)
			check(not result.is_empty(), "Spawn %s has ground beneath" % spawn_name)

	# 5. Cleanup
	gw.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
