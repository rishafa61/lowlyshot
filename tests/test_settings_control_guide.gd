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
	var sc = load("res://scenes/ui/settings_menu.tscn") as PackedScene
	check(sc != null, "settings_menu.tscn loads")
	var menu = sc.instantiate()
	root.add_child(menu)
	for i in 3:
		await process_frame

	# Switch to Controls tab
	menu.set_tab("Controls")
	var panel: VBoxContainer = menu.get_node("Content/TabControlsPanel")
	check(panel.visible, "TabControlsPanel visible on set_tab('Controls')")

	# Check Sub-tab buttons
	check(menu._cg_tab_btns.has("Player") and menu._cg_tab_btns.has("Vehicle"), "Player and Vehicle sub-tab buttons registered")
	var btn_player: Button = menu._cg_tab_btns["Player"]
	var btn_vehicle: Button = menu._cg_tab_btns["Vehicle"]

	# Default should be Player
	check(menu._cg_pages["Player"].visible == true, "Player page visible by default")
	check(menu._cg_pages["Vehicle"].visible == false, "Vehicle page hidden by default")

	# Check Player page has categories
	var player_box: VBoxContainer = menu._cg_pages["Player"]
	check(player_box.get_child_count() >= 3, "Player page has multiple categories (%d)" % player_box.get_child_count())

	# Switch to Vehicle tab
	btn_vehicle.emit_signal("pressed")
	await process_frame
	check(menu._cg_pages["Player"].visible == false, "Player page hidden after switching")
	check(menu._cg_pages["Vehicle"].visible == true, "Vehicle page visible after switching")

	# Check Vehicle page categories
	var vehicle_box: VBoxContainer = menu._cg_pages["Vehicle"]
	check(vehicle_box.get_child_count() >= 3, "Vehicle page has multiple categories (%d)" % vehicle_box.get_child_count())

	# Check active button style has orange accent
	var active_sb: StyleBoxFlat = btn_vehicle.get_theme_stylebox("normal") as StyleBoxFlat
	check(active_sb != null and active_sb.bg_color.r > 0.9, "Active sub-tab has orange accent")

	# Switch back to Player
	btn_player.emit_signal("pressed")
	await process_frame
	check(menu._cg_pages["Player"].visible == true, "Switched back to Player page")
	check(menu._cg_pages["Vehicle"].visible == false, "Vehicle page hidden again")

	# Top-level tab styling: active orange, inactive dark plate
	var top_active: StyleBoxFlat = menu.tabs["Controls"].get_theme_stylebox("normal") as StyleBoxFlat
	check(top_active != null and top_active.bg_color.r > 0.9, "Top tab active orange plate")
	var top_idle: StyleBoxFlat = menu.tabs["Visual"].get_theme_stylebox("normal") as StyleBoxFlat
	check(top_idle != null and top_idle.bg_color.v < 0.3, "Top tab idle dark plate")
	check(menu.btn_back.get_theme_font("font") != null, "Back button uses Outfit font")

	# Keycaps: bold font, key stylebox with bottom border
	var first_cat: PanelContainer = player_box.get_child(0)
	var cat_sb: StyleBoxFlat = first_cat.get_theme_stylebox("panel") as StyleBoxFlat
	check(cat_sb != null and cat_sb.border_width_left == 3, "Category plate has orange left accent")
	var caps := 0
	var cap_stack: Array = player_box.get_children()
	while not cap_stack.is_empty():
		var n: Node = cap_stack.pop_back()
		if n is PanelContainer and n.get_parent() != player_box:
			var ksb: StyleBoxFlat = n.get_theme_stylebox("panel") as StyleBoxFlat
			if ksb != null and ksb.border_width_bottom == 3:
				caps += 1
		for c in n.get_children():
			cap_stack.append(c)
	check(caps >= 14, "Player page keycaps present (%d)" % caps)

	menu.queue_free()
	print("RESULT: %s (%d fails / %d checks)" % ["OK" if fails == 0 else "FAIL", fails, checks])
	quit(1 if fails > 0 else 0)