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
	# 1. CapsuleEnemy drop & reset
	var enemy = (load("res://scenes/enemies/capsule_enemy.tscn") as PackedScene).instantiate()
	root.add_child(enemy)
	enemy.global_position = Vector3(0, 0, 0)
	for i in 3: await process_frame
	var e_wh: Node3D = enemy.find_child("WeaponHolder", true, false)
	check(e_wh != null, "Enemy has WeaponHolder")
	check(is_equal_approx(e_wh.position.y, 1.2), "Enemy initial WeaponHolder at Y=1.2 (got %0.3f)" % e_wh.position.y)

	enemy.die()
	for i in 40: await process_frame
	check(e_wh.position.y < 0.15, "Enemy WeaponHolder dropped to floor on death (got %0.3f)" % e_wh.position.y)
	check(absf(e_wh.rotation_degrees.z) > 60.0, "Enemy WeaponHolder tilted flat on floor (got %0.1f deg)" % e_wh.rotation_degrees.z)

	enemy.respawn()
	for i in 3: await process_frame
	check(is_equal_approx(e_wh.position.y, 1.2), "Enemy WeaponHolder restored to Y=1.2 on respawn (got %0.3f)" % e_wh.position.y)
	check(is_equal_approx(e_wh.rotation_degrees.z, 0.0), "Enemy WeaponHolder rotation restored to 0 on respawn")

	# 2. CapsuleAlly drop & reset
	var ally = (load("res://scenes/enemies/capsule_ally.tscn") as PackedScene).instantiate()
	root.add_child(ally)
	ally.global_position = Vector3(40, 0, 0)
	for i in 3: await process_frame
	var a_wh: Node3D = ally.find_child("WeaponHolder", true, false)
	check(a_wh != null, "Ally has WeaponHolder")
	check(is_equal_approx(a_wh.position.y, 1.2), "Ally initial WeaponHolder at Y=1.2 (got %0.3f)" % a_wh.position.y)

	ally.die()
	for i in 40: await process_frame
	check(a_wh.position.y < 0.15, "Ally WeaponHolder dropped to floor on death (got %0.3f)" % a_wh.position.y)
	check(absf(a_wh.rotation_degrees.z) > 60.0, "Ally WeaponHolder tilted flat on floor (got %0.1f deg)" % a_wh.rotation_degrees.z)

	ally.respawn()
	for i in 3: await process_frame
	check(is_equal_approx(a_wh.position.y, 1.2), "Ally WeaponHolder restored to Y=1.2 on respawn (got %0.3f)" % a_wh.position.y)
	check(is_equal_approx(a_wh.rotation_degrees.z, 0.0), "Ally WeaponHolder rotation restored to 0 on respawn")

	# 3. Player puppet weapon drop & reset
	var puppet = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	puppet.is_puppet = true
	root.add_child(puppet)
	puppet.global_position = Vector3(6, 0, 0)
	puppet._setup_puppet()
	for i in 3: await process_frame

	var p_gun: Node3D = puppet.get("_puppet_gun_holder")
	check(p_gun != null, "Puppet has _puppet_gun_holder")
	if p_gun:
		check(is_equal_approx(p_gun.position.y, 1.35), "Puppet initial gun at Y=1.35 (got %0.3f)" % p_gun.position.y)
		puppet.net_play_death()
		await create_timer(0.5).timeout
		check(p_gun.position.y < 0.15, "Puppet gun dropped to floor on death (got %0.3f)" % p_gun.position.y)
		check(absf(p_gun.rotation_degrees.z) > 60.0, "Puppet gun tilted flat on floor (got %0.1f deg)" % p_gun.rotation_degrees.z)

		puppet.respawn()
		for i in 3: await process_frame
		check(is_equal_approx(p_gun.position.y, 1.35), "Puppet gun restored to Y=1.35 on respawn (got %0.3f)" % p_gun.position.y)
		check(is_equal_approx(p_gun.rotation_degrees.z, 0.0), "Puppet gun rotation restored to 0 on respawn")

	# 4. Local player death drop
	var local_p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(local_p)
	local_p.global_position = Vector3(9, 0, 0)
	for i in 3: await process_frame
	local_p.die()
	await create_timer(0.6).timeout
	check(local_p.head.position.y < 0.35, "Local player camera dropped on death (got %0.3f)" % local_p.head.position.y)
	check(local_p.weapon_holder.position.y < -0.2, "Local player viewmodel dropped on death (got %0.3f)" % local_p.weapon_holder.position.y)

	local_p.respawn()
	for i in 3: await process_frame
	check(is_equal_approx(local_p.head.position.y, 1.8), "Local player camera restored to Y=1.8 on respawn (got %0.3f)" % local_p.head.position.y)
	check(is_equal_approx(local_p.weapon_holder.position.y, local_p.WEAPON_POS_HIP.y), "Local player viewmodel restored to WEAPON_POS_HIP on respawn (got %0.3f)" % local_p.weapon_holder.position.y)

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
