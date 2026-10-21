extends SceneTree

func _initialize() -> void:
	for name in ["GlobalData", "GlobalSettings"]:
		if root.get_node_or_null("/root/" + name) == null:
			var sc = load("res://scripts/%s.gd" % ("global_data" if name == "GlobalData" else "global_settings"))
			var n = Node.new()
			n.set_script(sc)
			n.name = name
			root.add_child(n)

	var p = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(p)
	for i in 5:
		await process_frame

	# 1. Pitch clamp & zero-flip test
	p.head.rotation.z = 0.3
	p.head.rotation.x = deg_to_rad(86.0)
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(0, 100000)
	p._unhandled_input(ev)
	assert(abs(p.head.rotation.y) < 0.001, "yaw must NOT flip on look-down")
	assert(p.head.rotation.x <= p.PITCH_LIMIT + 0.001, "pitch clamped at PITCH_LIMIT")

	p.head.rotation.x = deg_to_rad(-86.0)
	var ev2 := InputEventMouseMotion.new()
	ev2.relative = Vector2(0, -100000)
	p._unhandled_input(ev2)
	assert(abs(p.head.rotation.y) < 0.001, "yaw must NOT flip on look-up")
	assert(p.head.rotation.x >= -p.PITCH_LIMIT - 0.001, "pitch clamped at -PITCH_LIMIT")

	# 2. Weapon sway on mouse motion
	p.mouse_input = Vector2(120.0, 80.0)
	var wh: Node3D = p.weapon_holder
	var prev_rot := wh.rotation
	# Run one physics frame to process sway
	p._physics_process(0.016)
	assert(wh.rotation.y < prev_rot.y, "weapon yaw sways with mouse_x (lag)")
	assert(wh.rotation.x > prev_rot.x, "weapon pitch sways with mouse_y")

	# 3. Sway decays to zero when mouse stops
	for i in 30:
		p._physics_process(0.016)
	assert(wh.rotation.length() < 0.05, "weapon sway decays to rest")

	print("RESULT: OK (pitch clamp + weapon sway verified)")
	quit(0)
