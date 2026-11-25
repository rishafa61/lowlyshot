extends SceneTree

var fails := 0

func check(c: bool, m: String) -> void:
	if not c:
		fails += 1
		printerr("FAIL: " + m)
	else:
		print("PASS: " + m)

func _initialize() -> void:
	var sc = load("res://scenes/characters/human_body.tscn") as PackedScene
	check(sc != null, "human_body.tscn loads")
	var body: HumanBody = sc.instantiate() as HumanBody
	root.add_child(body)
	for i in 2: await process_frame

	var pm = body.get_node_or_null("PlayerModel") as Node3D
	check(pm != null, "PlayerModel child present")
	check(absf(pm.scale.y - 0.2375) < 0.001, "PlayerModel scaled to 0.2375 (got %f)" % pm.scale.y)
	check(absf(absf(pm.rotation.y) - PI) < 0.01, "PlayerModel rotated 180 deg to face -Z forward (got %f)" % pm.rotation.y)
	check(absf(pm.position.y - 0.0) < 0.001, "PlayerModel floor offset 0.0 (feet grounded, new Mixamo rig)")

	check(body.get_current_anim() == "Idle_Rifle", "Starts in Idle_Rifle anim")
	body.sync_movement(true, false, false, false)
	check(body.get_current_anim() == "Rifle_Run", "sync_movement(moving) -> Rifle_Run")
	body.sync_movement(false, true, false, false)
	check(body.get_current_anim() == "Idle_Rifle", "sync_movement(crouch, no clip) -> Idle_Rifle")
	body.sync_movement(false, false, true, false)
	check(body.get_current_anim() == "Rifle_Run", "sync_movement(slide) -> Rifle_Run")
	body.sync_movement(false, false, false, true)
	check(body.get_current_anim() == "Rifle_Run", "sync_movement(jump/airborne) -> Rifle_Run")
	body.sync_movement(false, false, false, false)
	check(body.get_current_anim() == "Idle_Rifle", "sync_movement(stop) -> Idle_Rifle")

	# Standby lobby clip exists + loops; Death exists (one-shot)
	check(body._anim_player.has_animation("Standby"), "Standby clip imported")
	check(body._anim_player.get_animation("Standby").loop_mode == Animation.LOOP_LINEAR, "Standby loops")
	check(body._anim_player.has_animation("Death"), "Death clip imported")
	check(body._anim_player.get_animation("Death").loop_mode != Animation.LOOP_LINEAR, "Death is one-shot")
	body.play_anim("Standby")
	check(body.get_current_anim() == "Standby", "play_anim(Standby) works")
	body.play_anim("Death")
	check(body.get_current_anim() == "Death", "play_anim(Death) works")

	# mixamo.com.002 ignored
	body.play_anim("mixamo_com_002")
	check(body.get_current_anim() == "Death", "mixamo_com_002 ignored")

	# Rig / Rig_001 ignored
	body.play_anim("Rig")
	check(body.get_current_anim() == "Death", "Rig authoring action ignored")
	body.play_anim("Rig_001")
	check(body.get_current_anim() == "Death", "Rig_001 authoring action ignored")

	# Death animation lock and clear_death
	body.play_anim("Death")
	check(body.get_current_anim() == "Death", "body in Death")
	body.sync_movement(true, false, false, false)
	check(body.get_current_anim() == "Death", "sync_movement does not override Death")
	body.clear_death()
	check(body.get_current_anim() == "Idle_Rifle", "clear_death resets to Idle_Rifle")
	body.sync_movement(true, false, false, false)
	check(body.get_current_anim() == "Rifle_Run", "sync_movement resumes after clear_death")

	# Weapon mount snaps to right wrist in standby/lobby display
	var sb = (load("res://scenes/ui/standby_character.tscn") as PackedScene).instantiate()
	root.add_child(sb)
	for i in 5: await process_frame
	var sb_hand = (sb.get_node("Body") as HumanBody).get_bone_world_pos("mixamorig_RightHand")
	var mount = sb.find_child("WeaponMount", true, false) as Node3D
	check(mount != null, "WeaponMount exists in standby character hierarchy")
	var mount_pos = mount.global_position if mount else Vector3.ZERO
	check(sb_hand != Vector3.ZERO, "RightHand bone resolves in standby scene")
	check(mount_pos.distance_to(sb_hand) < 0.3,
		"WeaponMount snapped near right wrist (dist %0.3f)" % mount_pos.distance_to(sb_hand))
	sb.queue_free()

	body.queue_free()
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
