# Verify standby character weapon model matches equipped primary + hover button FX
extends SceneTree

var fails: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	# Autoloads absent in -s mode: bootstrap GlobalData manually
	if not root.has_node("GlobalData"):
		var gd = Node.new()
		gd.name = "GlobalData"
		gd.set_script(load("res://scripts/global_data.gd"))
		root.add_child(gd)
	await process_frame

	# 1. Standby character instantiates the equipped primary's model
	var standby = (load("res://scenes/ui/standby_character.tscn") as PackedScene).instantiate()
	root.add_child(standby)
	await process_frame

	var gd_node = root.get_node("GlobalData")
	for wid in ["mp5", "rpd", "remington_870", "steyr_aug", "m4a4", "m700"]:
		for w in gd_node.weapons["Primary"]:
			w["equipped"] = str(w.get("id", "")) == wid
		standby.refresh()
		await process_frame
		var mount = standby.find_child("WeaponMount", true, false)
		var kids = mount.get_children()
		var ok: bool = kids.size() == 1 and (str(kids[0].scene_file_path).to_lower().ends_with("/%s.tscn" % wid.to_lower()) or (wid == "steyr_aug" and str(kids[0].scene_file_path).ends_with("/SteyrAUG.tscn")))
		check(ok, "standby shows %s model (got %s)" % [wid, ", ".join(kids.map(func(k): return k.scene_file_path))])

	# 2. Real main menu: button hover FX — orange fill + grey shade + pop
	var menu = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	var b: Button = menu.get_node("LeftNav/VBoxContainer/BtnLoadout")
	var hov = b.get_theme_stylebox("hover") as StyleBoxFlat
	check(hov != null, "hover stylebox overridden")
	if hov:
		check(hov.bg_color.is_equal_approx(Color(1.0, 0.44, 0.08)), "hover fill is orange")
		check(hov.shadow_size >= 8, "hover has grey shade behind (shadow_size=%d)" % hov.shadow_size)
		check(hov.shadow_color.v > 0.2 and hov.shadow_color.a > 0.3, "shade is visible grey")
	check(b.has_meta("hover_pop"), "button registered for pop-out tween")
	var nrm = b.get_theme_stylebox("normal") as StyleBoxFlat
	check(nrm != null and not nrm.bg_color.is_equal_approx(Color(1.0, 0.44, 0.08)), "normal state stays dark (hover-only orange)")
	b.mouse_entered.emit()
	await create_timer(0.15).timeout
	check(absf(b.scale.x - 1.05) < 0.01, "pop-out tween fires on hover (scale=%.2f)" % b.scale.x)
	b.mouse_exited.emit()
	await create_timer(0.15).timeout
	check(absf(b.scale.x - 1.0) < 0.01, "scale returns on exit (scale=%.2f)" % b.scale.x)

	# 3. Squad-bar buttons (invite/browse/copy) go through the same styling
	var squad: HBoxContainer = menu.get_node_or_null("PartyUI").get_children().filter(func(c): return c is HBoxContainer)[0]
	var found := 0
	for sb in squad.get_children():
		if sb is Button:
			var shov = sb.get_theme_stylebox("hover") as StyleBoxFlat
			if shov and shov.shadow_size >= 8 and shov.bg_color.is_equal_approx(Color(1.0, 0.44, 0.08)):
				found += 1
	check(found >= 3, "invite/browse/copy all get orange hover + shade (found %d)" % found)

	standby.queue_free()
	menu.queue_free()
	await process_frame
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
