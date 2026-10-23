# Flying Scoutsman game mode test — headless
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
	print("--- Running Flying Scoutsman System Tests ---")

	# Singletons required by MultiplayerManager / HUD
	for name in ["GlobalData", "GlobalSettings", "PlayerProfile"]:
		if not root.has_node(name):
			var file_name = "global_data"
			if name == "GlobalSettings": file_name = "global_settings"
			elif name == "PlayerProfile": file_name = "player_profile"
			var sc = load("res://scripts/%s.gd" % file_name)
			if sc:
				var node = Node.new()
				node.name = name
				node.set_script(sc)
				root.add_child(node)
	await process_frame

	var gd = root.get_node("GlobalData")

	# 1. Level scene loading & instantiation
	var scn := load("res://scenes/levels/flying_scoutsman.tscn") as PackedScene
	check(scn != null, "flying_scoutsman.tscn loads")
	var mgr = scn.instantiate()
	check(mgr != null, "instantiates Flying Scoutsman level scene")
	root.add_child(mgr)
	await process_frame

	# 2. Config & Rules
	check(mgr.mode_title == "FLYING SCOUTSMAN", "mode title is FLYING SCOUTSMAN")
	check(mgr.ffa_target_kills == 40, "win target is 40 kills")
	check(mgr.forced_weapon_id == "m700", "forced weapon is m700")

	# 3. Moon gravity & float check
	var current_grav: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	check(is_equal_approx(current_grav, 1.6), "ProjectSettings moon gravity ~1.6 (floaty ~16% base)")
	check(gd.get("force_primary_id") == "m700", "GlobalData.force_primary_id locked to m700")
	check(gd.get("force_operator") == "Vanguard", "GlobalData.force_operator locked to Vanguard (healer)")
	var op_sc: Script = gd.get_equipped_operator_script()
	var dummy_op = op_sc.new()
	check(dummy_op.op_name == "Vanguard", "forced operator script resolves to Vanguard")
	dummy_op.free()

	# 4. Spawners presence
	var spawns: Array = root.get_tree().get_nodes_in_group("spawn_points")
	check(spawns.size() >= 15, "at least 15 spawners scattered across arena (found %d)" % spawns.size())

	# 5. Side picker destroyed & local player auto-spawned in FFA
	var hud = mgr.get_node_or_null("MultiplayerHUD")
	check(hud != null, "HUD instanced")
	check(hud.get("side_picker") == null, "side_picker is destroyed in FFA")
	var local_p = mgr.get_node_or_null("1")
	check(local_p != null, "local player auto-spawned in FFA without manual side picking")
	if local_p:
		check(local_p.spawn_protect_timer > 0.0, "spawn protection timer armed on player spawn")
		var orig_hp = local_p.hp
		local_p.take_damage(50.0, "Bot", "m700", "Enemy")
		check(local_p.hp == orig_hp, "spawn protection prevents damage while active")

	# 6. Loadout lock: primary is forced to m700
	var primary_dict: Dictionary = gd.get_equipped_primary()
	check(primary_dict.get("id") == "m700", "get_equipped_primary() returns m700 regardless of loadout selection")

	# 6b. FFA Scoring check: 40 kills trigger MATCH_END
	mgr.match_stats["TestShooter"] = { "kills": 39, "deaths": 0, "team": "ffa_test" }
	gd.register_kill("TestShooter", "Enemy", "m700", "VictimBot", "Enemy")
	await process_frame
	check(mgr.match_stats["TestShooter"]["kills"] == 40, "killer kills incremented to 40")
	check(mgr.current_state == mgr.MatchState.MATCH_END, "reaching 40 kills triggers MATCH_END")
	check(mgr.ffa_winner_name == "TestShooter", "ffa_winner_name correctly recorded as TestShooter")

	# 7. Menu registration
	var menu_sc = load("res://scenes/ui/main_menu.gd")
	check(menu_sc != null, "main_menu.gd loads")
	var dummy_menu = Control.new()
	dummy_menu.set_script(menu_sc)
	var mp_maps = dummy_menu.maps.get("Multiplayer", [])
	var found_scoutsman: bool = false
	for m in mp_maps:
		if m.get("name") == "Flying Scoutsman":
			found_scoutsman = true
			check(m.get("scene") == "res://scenes/levels/flying_scoutsman.tscn", "Flying Scoutsman points to correct level scene")
			break
	check(found_scoutsman, "Flying Scoutsman registered under Multiplayer in main menu")
	dummy_menu.free()

	# 8. Clean up & reset gravity
	mgr.queue_free()
	await process_frame
	await process_frame
	check(gd.get("force_primary_id") == "", "GlobalData.force_primary_id reset on manager exit")
	check(gd.get("force_operator") == "", "GlobalData.force_operator reset on manager exit")
	var restored_grav: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	check(is_equal_approx(restored_grav, 9.8), "physics/3d/default_gravity restored to 9.8 on exit")

	if fails == 0:
		print("ALL FLYING SCOUTSMAN TESTS PASSED")
	else:
		printerr("FLYING SCOUTSMAN TESTS FAILED: %d errors" % fails)

	quit(0 if fails == 0 else 1)
