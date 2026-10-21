extends SceneTree

func _initialize() -> void:
	for name in ["GlobalData", "GlobalSettings"]:
		if root.get_node_or_null("/root/" + name) == null:
			var sc = load("res://scripts/%s.gd" % ("global_data" if name == "GlobalData" else "global_settings"))
			var n = Node.new()
			n.set_script(sc)
			n.name = name
			root.add_child(n)

	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50.0, 1.0, 50.0)
	col.shape = box
	floor_body.add_child(col)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)

	var p = load("res://scenes/player/player.tscn").instantiate()
	p.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(p)
	for i in 45:
		await process_frame

	assert(p.is_on_floor(), "player grounded on floor")
	var wh: Node3D = p.weapon_holder
	var rest_pos: Vector3 = wh.position

	# Backpedal (S): gun pulls back (z increases) and tilts down slightly
	Input.action_press("move_backward")
	for i in 25:
		await process_frame
	Input.action_release("move_backward")
	assert(wh.position.z > rest_pos.z + 0.005, "backpedal pulls weapon back (z %s vs %s)" % [wh.position.z, rest_pos.z])

	# Strafe left (A): gun drifts left (x decreases) and banks into the strafe
	Input.action_press("move_left")
	for i in 25:
		await process_frame
	Input.action_release("move_left")
	assert(wh.position.x < rest_pos.x - 0.005, "strafe left drifts weapon left (x %s vs %s)" % [wh.position.x, rest_pos.x])
	assert(wh.rotation.z < -0.005, "strafe left tilts weapon (rot.z %s)" % wh.rotation.z)

	# Rest: offsets decay back to hipfire default once motion settles
	for i in 60:
		p.velocity = Vector3.ZERO
		await process_frame
	assert(abs(wh.position.x - rest_pos.x) < 0.015, "weapon returns to rest x (was %s, got %s)" % [rest_pos.x, wh.position.x])

	print("RESULT: OK (movement sway verified)")
	quit(0)
