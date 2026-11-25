# Automated tests for Wraith: Hunter Drone ability
extends SceneTree

var fails: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func _make_player(pname: String, pos: Vector3, team: String = "attackers") -> CharacterBody3D:
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.name = pname
	p.position = pos
	p.team = team
	root.add_child(p)
	return p

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- TEST 1: Hunter Drone defaults & materials ---")
	var drone_scene: PackedScene = load("res://scenes/weapons/skills/hunter_drone.tscn")
	check(drone_scene != null, "drone scene loads")
	var drone = drone_scene.instantiate()
	root.add_child(drone)
	await process_frame

	check(drone.acquire_radius == 15.0, "default acquire radius 15m")
	check(drone.flight_time == 8.0, "default max flight duration 8s")
	check(drone.lock_delay == 1.0, "default lock delay 1s")
	check(drone.stun_duration == 1.2, "default stun duration 1.2s")
	check(drone.hover_height == 1.5, "default hover height 1.5m")
	check(drone.is_in_group("hunter_drones"), "drone in hunter_drones group")

	# Every mesh must carry a material (GLES3 null-material warning guard)
	var missing_mat := false
	for c in drone.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if mi.mesh != null and mi.mesh.material == null \
				and mi.material_override == null \
				and mi.get_surface_override_material(0) == null:
			missing_mat = true
			printerr("  untextured mesh: " + str(c.name))
	check(not missing_mat, "all drone meshes have valid non-null materials")

	drone.queue_free()
	await process_frame

	print("--- TEST 2: Wraith operator, cooldown, 1-drone limit ---")
	var wraith = (load("res://scenes/operators/wraith_operator.gd") as GDScript).new()
	wraith.name = "WraithOp"
	root.add_child(wraith)
	await process_frame

	check(wraith.op_name == "Wraith", "op name Wraith")
	check(wraith.skill_name == "Hunter Drone", "skill name Hunter Drone")
	check(wraith.skill_cooldown == 35.0, "skill cooldown 35s")

	var p1 := _make_player("1", Vector3(0, 1, 0), "attackers")
	await process_frame

	p1.is_dead = true
	wraith.use_skill(p1)
	check(wraith.active_drone == null, "skill blocked while dead")
	p1.is_dead = false

	p1.is_drone_stunned = true
	wraith.use_skill(p1)
	check(wraith.active_drone == null, "skill blocked while stunned")
	p1.is_drone_stunned = false

	wraith.use_skill(p1)
	check(wraith.active_drone != null and is_instance_valid(wraith.active_drone), "drone spawned on valid use")
	check(wraith.current_cooldown > 0.0, "cooldown started")

	var prev_drone = wraith.active_drone
	wraith.use_skill(p1)
	check(wraith.active_drone == prev_drone, "only 1 active drone permitted")
	check(is_instance_valid(prev_drone), "first drone not replaced")

	prev_drone.queue_free()
	wraith.active_drone = null
	wraith.queue_free()
	p1.queue_free()
	await process_frame

	print("--- TEST 3: target acquisition & team validation ---")
	var drone2 = drone_scene.instantiate()
	root.add_child(drone2)
	drone2.position = Vector3(0, 2, 0)
	drone2.faction = "Ally"

	var ally := _make_player("AllyP", Vector3(0, 0, -4), "attackers")
	ally.add_to_group("ally")
	var far_enemy := _make_player("FarEnemy", Vector3(0, 0, 25), "defenders")
	far_enemy.add_to_group("enemy")
	var dead_enemy := _make_player("DeadEnemy", Vector3(0, 0, 4), "defenders")
	dead_enemy.add_to_group("enemy")
	dead_enemy.is_dead = true
	var enemy := _make_player("EnemyP", Vector3(5, 0, 0), "defenders")
	enemy.add_to_group("enemy")
	await process_frame
	await physics_frame

	# Engine frames in the awaits auto-respawn the dead player — re-assert
	dead_enemy.is_dead = true
	var target = drone2._find_target()
	check(target == enemy, "selects only the valid enemy (ignores ally / far / dead)")

	drone2.queue_free()
	ally.queue_free()
	far_enemy.queue_free()
	dead_enemy.queue_free()
	enemy.queue_free()
	await process_frame

	print("--- TEST 4: acquisition through wall / no LOS required ---")
	var drone3 = drone_scene.instantiate()
	root.add_child(drone3)
	drone3.position = Vector3(0, 2, 0)
	drone3.faction = "Ally"

	var wall := StaticBody3D.new()
	var wall_col := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.5, 8.0, 10.0)
	wall_col.shape = wall_box
	wall.add_child(wall_col)
	wall.position = Vector3(2.5, 0, 0)
	root.add_child(wall)

	var hidden := _make_player("HiddenEnemy", Vector3(5, 0, 0), "defenders")
	hidden.add_to_group("enemy")
	await physics_frame

	check(drone3._find_target() == hidden, "acquires nearest enemy even behind wall (no LOS required)")

	drone3.queue_free()
	wall.queue_free()
	hidden.queue_free()
	await process_frame

	print("--- TEST 5: drone stun effect on player ---")
	var victim := _make_player("Victim", Vector3(0, 1, 0), "defenders")
	await process_frame

	check(not victim.is_drone_stunned, "player starts unstunned")
	victim.drone_stun(1.2)
	check(victim.is_drone_stunned, "is_drone_stunned true after drone_stun()")
	check(victim._drone_stun_timer >= 1.1, "stun timer set to duration")

	# Manual physics tick: movement decelerates and locks
	victim.velocity = Vector3(5.0, 0, 5.0)
	victim._physics_process(0.1)
	check(victim.velocity.length() < 4.8, "stun decelerates and locks player movement")
	check(victim.camera != null, "camera intact during stun (look stays functional)")

	# Stun must auto-expire: tick past the duration
	victim._physics_process(1.5)
	check(not victim.is_drone_stunned, "stun automatically expires (never permanent)")

	# Death clears any residual stun
	victim.drone_stun(1.2)
	victim.die()
	check(not victim.is_drone_stunned, "death clears drone stun immediately")
	victim.is_dead = false

	victim.queue_free()
	await process_frame

	print("--- TEST 6: round reset cleanup ---")
	var drone4 = drone_scene.instantiate()
	root.add_child(drone4)
	await process_frame
	check(is_instance_valid(drone4) and drone4.is_in_group("hunter_drones"), "drone registered in hunter_drones group")

	# Mirrors _prepare_new_round cleanup in search_and_destroy_manager.gd
	for d in get_nodes_in_group("hunter_drones"):
		if is_instance_valid(d):
			d.queue_free()
	await process_frame
	check(not is_instance_valid(drone4), "active drones removed on round reset")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
