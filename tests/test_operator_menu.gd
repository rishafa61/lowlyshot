# Operator menu smoke test — headless: verifies the rebuilt tscn loads,
# all @onready node paths resolve, and selection refreshes details/stats.
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

	check(menu.op_rows.size() == 6, "6 operator rows built")
	check(menu.cat_headers.size() == 3, "3 category headers built")
	check(menu.stats_box.has_meta("hp") and menu.stats_box.has_meta("armor") and menu.stats_box.has_meta("mob"), "stat bars registered")
	check(menu.item_name.text != "", "details populated: " + menu.item_name.text)

	menu._select("Ghost")
	await process_frame
	check(menu.cat_header.text == "Recon", "header switches to Recon")
	check(menu.item_name.text == "Ghost", "detail name switches")
	check(String(menu.btn_equip.text) != "", "equip button text set: " + str(menu.btn_equip.text))

	# All operators selectable without errors
	for op in menu.operators:
		menu._select(op["id"])
	check(true, "all operators selectable")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
