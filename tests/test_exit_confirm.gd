extends SceneTree

var fails: int = 0
var checks: int = 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FAIL: %s" % msg)
	else:
		print("  PASS: %s" % msg)

func _initialize() -> void:
	for name in ["GlobalData", "GlobalSettings"]:
		if root.get_node_or_null("/root/" + name) == null:
			var sc = load("res://scripts/%s.gd" % ("global_data" if name == "GlobalData" else "global_settings"))
			var n = Node.new()
			n.set_script(sc)
			n.name = name
			root.add_child(n)

	var sc = load("res://scenes/ui/main_menu.tscn")
	var menu = sc.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	# Trigger exit button
	var btn_exit: Button = menu.btn_exit
	check(is_instance_valid(btn_exit), "btn_exit valid")
	btn_exit.emit_signal("pressed")
	await process_frame

	var layer: CanvasLayer = menu.get_node_or_null("ExitConfirmLayer")
	check(is_instance_valid(layer), "ExitConfirmLayer opened on exit press")

	var lbl: Label = null
	var yes_btn: Button = null
	var no_btn: Button = null

	var stack: Array = [layer]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Label and cur.text == "ARE YOU SURE?":
			lbl = cur
		elif cur is Button:
			if cur.text == "YES":
				yes_btn = cur
			elif cur.text == "NO":
				no_btn = cur
		for child in cur.get_children():
			stack.append(child)

	check(is_instance_valid(lbl), "ARE YOU SURE? title present")
	check(is_instance_valid(yes_btn), "YES button present")
	check(is_instance_valid(no_btn), "NO button present")

	# Clicking NO should dismiss modal without quitting
	if is_instance_valid(no_btn):
		no_btn.emit_signal("pressed")
		await process_frame
		await process_frame
		check(menu.get_node_or_null("ExitConfirmLayer") == null, "NO button dismisses confirm modal")

	if fails == 0:
		print("RESULT: OK (%d checks)" % checks)
	else:
		print("RESULT: %d FAILS / %d checks" % [fails, checks])
	quit(0)
