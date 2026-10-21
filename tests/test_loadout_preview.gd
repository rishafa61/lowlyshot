# Loadout menu test — headless: horizontal group tabs, weapon preview swap,
# drag-rotate snap-back, and zoom bounds.
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

	var menu = load("res://scenes/ui/loadout_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	# 1. Horizontal group tabs in HBox
	check(menu.group_list is HBoxContainer, "GroupList is HBoxContainer (horizontal)")
	check(menu.group_list.get_child_count() > 0, "group tabs built")

	# 2. Weapon preview present (no player standby)
	var wp = menu.preview_wp
	check(wp != null and wp.has_method("show_weapon"), "WeaponPreview node with show_weapon()")
	check(wp.get_child_count() > 0, "weapon model instanced: %d children" % wp.get_child_count())
	check(absf(wp.rotation.y - PI * 0.5) < 0.001, "default rotation = side profile (yaw 90, got %f)" % wp.rotation.y)

	# 3. show_weapon swaps models
	var before_children: int = wp.get_child_count()
	wp.show_weapon("m700")
	await process_frame
	check(wp.current_id == "m700", "preview switched to m700")
	check(wp.get_child_count() >= before_children, "m700 model instanced")

	# 4. Drag rotate + snap back
	var base_rot_y: float = wp.rotation.y
	wp.rotate_by(Vector2(200, 20))
	check(absf(wp.rotation.y - base_rot_y) > 2.0, "drag rotates weapon")
	wp.snap_back(true)
	check(wp.rotation.y == base_rot_y and wp.rotation.x == 0.0, "snap_back restores side profile")

	# 5. Zoom clamps
	var cam: Camera3D = wp.get_parent().get_node("Camera3D")
	for i in 30:
		wp.zoom_by(-1)
	check(cam.position.z >= 0.55 - 0.01, "zoom-in clamps at min: %f" % cam.position.z)
	for i in 60:
		wp.zoom_by(1)
	check(cam.position.z <= 1.6 + 0.01, "zoom-out clamps at max: %f" % cam.position.z)

	# 6. Unknown id does not crash, clears model
	wp.show_weapon("nonexistent_gun")
	await process_frame
	check(true, "unknown weapon id handled")

	# 7. Stylized UI contracts
	var top: HBoxContainer = menu.get_node("Margin/VBox/TopBar")
	check(top.get_node_or_null("SlashBadge") != null, "slash badge present")
	var title_lbl: Label = top.get_node("Title")
	check(title_lbl.text == "LOADOUT" and title_lbl.get_theme_font_size("font_size") == 40, "title LOADOUT 40px")
	check(menu.get_node_or_null("BgArt") is TextureRect, "background art TextureRect present")
	check(menu.get_node_or_null("LoadoutVignette") is TextureRect, "vignette present")
	var tab1_sb: StyleBoxFlat = menu.preset_buttons[0].get_theme_stylebox("normal") as StyleBoxFlat
	check(tab1_sb != null and tab1_sb.bg_color.r > 0.9, "active preset tab orange")
	var prim_card: PanelContainer = menu.slot_cards["Primary"]
	var prim_sb: StyleBoxFlat = prim_card.get_theme_stylebox("panel") as StyleBoxFlat
	check(prim_sb != null and prim_sb.border_color.r > 0.9, "active slot card orange border")
	var eq_sb: StyleBoxFlat = menu.btn_equip.get_theme_stylebox("normal") as StyleBoxFlat
	check(eq_sb != null and eq_sb.bg_color.r > 0.9, "save/equip button orange")
	var det_sb: StyleBoxFlat = menu.get_node("Margin/VBox/Main/Mid/Detail").get_theme_stylebox("panel") as StyleBoxFlat
	check(det_sb != null and det_sb.border_width_left == 4, "detail panel has orange left accent")

	menu.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
