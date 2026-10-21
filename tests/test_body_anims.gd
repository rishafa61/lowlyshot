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
	check(absf(pm.position.y - 1.2907) < 0.001, "PlayerModel floor offset 1.2907 (got %f)" % pm.position.y)

	check(body.get_current_anim() == "Idle", "Starts in Idle anim")
	body.sync_movement(true, false, false, false)
	check(body.get_current_anim() == "Run", "sync_movement(moving) -> Run")
	body.sync_movement(false, true, false, false)
	check(body.get_current_anim() == "Crouch", "sync_movement(crouch) -> Crouch")
	body.sync_movement(false, false, true, false)
	check(body.get_current_anim() == "Slide", "sync_movement(slide) -> Slide")
	body.sync_movement(false, false, false, true)
	check(body.get_current_anim() == "Run", "sync_movement(jump/airborne) -> Run")
	body.sync_movement(false, false, false, false)
	check(body.get_current_anim() == "Idle", "sync_movement(stop) -> Idle")

	# Rig / Rig_001 ignored
	body.play_anim("Rig")
	check(body.get_current_anim() == "Idle", "Rig authoring action ignored")
	body.play_anim("Rig_001")
	check(body.get_current_anim() == "Idle", "Rig_001 authoring action ignored")

	body.queue_free()
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
