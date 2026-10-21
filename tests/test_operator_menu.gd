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

	# Reference restyle contracts
	var title: Label = menu.get_node("Margin/VBox/TopBar/Title")
	check(title.text == "OPERATOR SELECT", "title is OPERATOR SELECT")
	check(title.get_theme_font_size("font_size") == 40, "title 40px")
	check(menu.get_node_or_null("BgArt") is TextureRect, "background art TextureRect present")
	check(menu.get_node_or_null("OpVignette") is TextureRect, "vignette present")
	var badge: Node = menu.get_node("Margin/VBox/TopBar").get_child(0)
	check(badge is Control and badge.name == "SlashBadge", "slash badge present")
	var equip_sb: StyleBoxFlat = menu.btn_equip.get_theme_stylebox("normal") as StyleBoxFlat
	check(equip_sb != null and equip_sb.bg_color.r > 0.9, "equip button orange")
	check(menu.btn_equip.custom_minimum_size.y == 56, "equip button 56px tall")
	var segs: Array = menu.stats_box.get_meta("hp")
	check(segs[0] is ColorRect, "stat segments are ColorRects")
	segs[0].color = Color(1.0, 0.44, 0.08)
	check(segs[0].color.r > 0.9, "segment color settable")
	var hint_caps := 0
	var bar: HBoxContainer = menu.get_node("Margin/VBox/BottomBar")
	for c in bar.get_children():
		if c is HBoxContainer:
			for k in c.get_children():
				if k is PanelContainer:
					hint_caps += 1
	check(hint_caps == 3, "keycap hints present (got %d)" % hint_caps)
	var recon_btn: Button = menu.cat_buttons["Recon"]
	check(recon_btn.custom_minimum_size.y == 64, "category cards 64px tall")

	# Selected operator card + ability format (Recon: Ghost)
	menu._set_category("Recon")
	await process_frame
	var ghost: Button = menu.op_rows["Ghost"]
	var ghost_sb: StyleBoxFlat = ghost.get_theme_stylebox("normal") as StyleBoxFlat
	check(ghost_sb != null and ghost_sb.border_color.r > 0.9, "selected operator card has orange border")
	check(menu.item_desc.text.begins_with("»  Sonar Pulse"), "ability line formatted")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
