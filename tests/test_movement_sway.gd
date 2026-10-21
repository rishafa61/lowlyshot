extends SceneTree

func _initialize() -> void:
	for name in ["GlobalData", "GlobalSettings"]:
		if root.get_node_or_null("/root/" + name) == null:
			var sc = load("res://scripts/%s.gd" % ("global_data" if name == "GlobalData" else "global_settings"))
			var n = Node.new()
			n.set_script(sc)
			n.name = name
			root.add_child(n)

	# Static floor so is_on_floor() resolves true
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

	# Wait for physics fall to ground and _ready to fire
	for i in 45:
		await process_frame

	assert(p.BOB_AMP == 0.12, "BOB_AMP raised for sway")
	var cam: Camera3D = p.camera
	assert(cam != null, "camera exists")

	assert(p.is_on_floor(), "player grounded on floor")

	# Mock walking input by setting velocity in physics loop
	for i in 30:
		p.velocity.x = 4.0
		await process_frame

	assert(p.t_bob > 0.0, "t_bob accumulating on movement")
	var walk_disp := Vector2(cam.position.x, cam.position.y).length()
	assert(walk_disp > 0.005, "camera swayed while walking")

	# Stop: returns toward rest
	for i in 60:
		p.velocity = Vector3.ZERO
		await process_frame

	assert(is_equal_approx(p.t_bob, 0.0), "t_bob reset on stop")
	assert(cam.position.length() < 0.06, "camera returned toward rest")

	print("RESULT: OK (sway + shake verified)")
	quit(0)
