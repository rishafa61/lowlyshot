# Ground War Rework & Multiplayer Test — headless
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

	# 2. Load ground_war.tscn
	var gw_scene = load("res://scenes/levels/ground_war.tscn") as PackedScene
	check(gw_scene != null, "ground_war.tscn loads")
	var gw = gw_scene.instantiate()
	root.add_child(gw)
	await process_frame

	# 3. Ground dimensions & boundary verification
	var nav = gw.get_node_or_null("NavigationRegion3D")
	check(nav != null, "NavigationRegion3D exists")
	var ground = nav.get_node_or_null("Ground") as CSGBox3D
	check(ground != null and ground.size == Vector3(800, 1, 800), "Ground dimensions are 800x800x1 (got %s)" % (ground.size if ground else "null"))

	var boundary = gw.get_node_or_null("BoundaryZone")
	check(boundary != null, "BoundaryZone exists on map")
	check(boundary.inner_half_x >= 400.0 and boundary.inner_half_z >= 400.0, "BoundaryZone covers 800x800 map (inner_half_x=%f)" % (boundary.inner_half_x if boundary else 0.0))

	# 4. Verify new structures exist and have collision
	var outpost = nav.get_node_or_null("OutpostEast")
	check(outpost != null, "OutpostEast exists")
	var wh = outpost.get_node_or_null("Warehouse") as CSGBox3D
	check(wh != null and wh.use_collision, "Warehouse exists with use_collision")

	var wt_ne = nav.get_node_or_null("WatchtowerNE")
	check(wt_ne != null, "WatchtowerNE exists")

	var wt_sw = nav.get_node_or_null("WatchtowerSW")
	check(wt_sw != null, "WatchtowerSW exists")

	var wh_west = nav.get_node_or_null("WarehouseWest")
	check(wh_west != null, "WarehouseWest exists")

	var village = nav.get_node_or_null("VillageSW")
	check(village != null, "VillageSW exists")

	var yard = nav.get_node_or_null("ContainerYard")
	check(yard != null, "ContainerYard exists")

	var forest_e = nav.get_node_or_null("ForestEast")
	check(forest_e != null and forest_e.get_child_count() >= 16, "ForestEast has trees (got %d children)" % (forest_e.get_child_count() if forest_e else 0))

	var forest_w = nav.get_node_or_null("ForestWest")
	check(forest_w != null and forest_w.get_child_count() >= 12, "ForestWest has trees (got %d children)" % (forest_w.get_child_count() if forest_w else 0))

	var covers = nav.get_node_or_null("MidfieldCovers")
	check(covers != null and covers.get_child_count() >= 8, "MidfieldCovers exists with barriers & rocks")

	# 5. Multiplayer spawn points verification (10v10 teams)
	var sp = gw.get_node_or_null("PlayerSpawner")
	check(sp != null, "PlayerSpawner initialized")
	var sp_attackers = sp.get_spawn_point("attackers")
	var sp_defenders = sp.get_spawn_point("defenders")
	check(sp_attackers != null, "Attackers spawn point found")
	check(sp_defenders != null, "Defenders spawn point found")

	# 6. Simulate spawning attacker & defender players into the reworked map
	var p1 = sp.spawn_player(1, "attackers")
	check(p1 != null and is_instance_valid(p1), "Spawned Player 1 (Host/Attacker)")
	check(p1.global_position.y >= 0.0, "Player 1 spawned above ground (Y=%f)" % p1.global_position.y)

	var p2 = sp.spawn_player(2, "defenders")
	check(p2 != null and is_instance_valid(p2), "Spawned Player 2 (Client/Defender)")
	check(p2.global_position.y >= 0.0, "Player 2 spawned above ground (Y=%f)" % p2.global_position.y)

	# 7. Check vehicle spawners exist and are populated
	var v_spawners := []
	for node in nav.get_node("BaseAttackers").get_children():
		if node.has_method("spawn_vehicle"):
			v_spawners.append(node)
	check(v_spawners.size() >= 3, "BaseAttackers has >= 3 vehicle spawners (got %d)" % v_spawners.size())

	gw.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
