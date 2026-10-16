# Operator menu smoke test — headless: verifies sidebar categories + mid operators
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
	for name in ["GlobalData"]:
		if root.get_node_or_null("/root/" + name) == null:
			var n = Node.new()
			n.set_script(load("res://scripts/global_data.gd"))
			n.name = name
			root.add_child(n)
			await process_frame
	var menu = load("res://scenes/ui/operator_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	check(menu.cat_buttons.size() == 3, "3 sidebar category buttons")
	check(menu.current_category == "Assault", "default category Assault")
	check(menu.op_rows.size() == 2, "Assault category has 2 operators")
	check(menu.stats_box.has_meta("hp"), "stats box registered")

	# Switch sidebar to Recon
	menu._set_category("Recon")
	await process_frame
	check(menu.cat_header.text == "Recon", "header is Recon")
	check(menu.op_rows.size() == 1, "Recon has 1 operator (Ghost)")
	check(menu.selected_id == "Ghost", "Ghost auto-selected")

	# Switch to Support
	menu._set_category("Support")
	await process_frame
	check(menu.op_rows.size() == 3, "Support has 3 operators")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
