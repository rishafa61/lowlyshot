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

	# 1. Test player _menu_open() helper
	var player_sc = load("res://scenes/player/player.tscn")
	check(player_sc != null, "player.tscn loads")
	var p = player_sc.instantiate()
	root.add_child(p)
	await process_frame
	await process_frame

	check(p.has_method("_menu_open"), "player has _menu_open method")
	check(not p._menu_open(), "_menu_open is false initially")

	var pm = p.get_node_or_null("PauseMenu")
	check(pm != null, "PauseMenu found on player")
	if pm:
		pm.visible = true
		check(p._menu_open(), "_menu_open is true when PauseMenu is visible")
		pm.visible = false
		check(not p._menu_open(), "_menu_open is false when PauseMenu is hidden")

	# 2. Test greppy miss does not cancel skill and shows "Need to be closer"
	var greppy_sc = load("res://scenes/operators/greppy_operator.gd")
	check(greppy_sc != null, "greppy_operator.gd loads")
	var greppy = greppy_sc.new()
	p.add_child(greppy)

	# Execute skill (equip grappler)
	greppy._execute_skill(p)
	check(greppy.is_holding_skill, "greppy is holding skill after execute")

	# Hook fire in open air (no wall within MAX_RANGE)
	greppy._fire_hook()

	check(greppy.is_holding_skill, "greppy KEEPS holding skill when hook misses (no swap)")

	var hud = p.get_node_or_null("HUD")
	check(hud != null, "HUD found on player")
	if hud:
		var spawn = hud.get_node_or_null("DamageTextSpawn")
		check(spawn != null and spawn.get_child_count() > 0, "DamageTextSpawn has floating child")
		if spawn and spawn.get_child_count() > 0:
			var hint_lbl = spawn.get_child(0) as Label
			check(hint_lbl != null and hint_lbl.text == "Need to be closer", "hint text is 'Need to be closer' (got '%s')" % (hint_lbl.text if hint_lbl else "null"))

	if fails == 0:
		print("RESULT: OK (%d checks)" % checks)
	else:
		print("RESULT: %d FAILS / %d checks" % [fails, checks])
	quit(0)
