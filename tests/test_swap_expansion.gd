extends SceneTree

func _initialize() -> void:
	for name in ["GlobalData"]:
		if root.get_node_or_null("/root/" + name) == null:
			var n = Node.new()
			n.set_script(load("res://scripts/global_data.gd"))
			n.name = name
			root.add_child(n)
			await process_frame

	var menu = load("res://scenes/ui/loadout_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	# Simulate 10 swaps between overview and armory
	for i in 10:
		menu._open_armory("Primary")
		await process_frame
		menu._on_back_pressed()
		await process_frame

	var left_w = menu.left_panel.size.x
	var hints_count = menu.hint_container.get_child_count()
	print("TEST SWAP DONE: left_w=%f, hints_count=%d" % [left_w, hints_count])
	assert(hints_count <= 15, "Hints row duplicated")
	assert(menu.right_panel.visible == true, "Right preview panel visible")

	menu.queue_free()
	await process_frame
	print("SWAP TEST PASS")
	quit(0)
