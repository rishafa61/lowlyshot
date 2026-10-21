extends SceneTree

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- Running test_hud_rework ---")
	
	for name in ["GlobalData", "GlobalSettings"]:
		if root.get_node_or_null("/root/" + name) == null:
			var sc = load("res://scripts/%s.gd" % ("global_data" if name == "GlobalData" else "global_settings"))
			if sc:
				var gd = Node.new()
				gd.name = name
				gd.set_script(sc)
				root.add_child(gd)
	await process_frame
	
	# 1. Test HUD instantiate & elements
	var hud_scene = load("res://scenes/ui/hud.tscn")
	assert(hud_scene != null, "hud.tscn exists")
	var hud = hud_scene.instantiate()
	root.add_child(hud)
	await process_frame
	
	# Stats
	assert(hud.hp_label != null, "hp_label exists")
	assert(hud.armor_label != null, "armor_label exists")
	hud.update_stats(120, 120, 50, 100, 100.0, 100.0)
	assert(hud.hp_label.text == "120", "hp updated")
	assert(hud.armor_label.text == "50", "armor updated")
	
	# Weapon slots
	hud.set_weapon_names(["AK-47", "Glock", "Default Knife", "Frag Grenade", "AT4 Launcher"])
	hud.update_weapon_slot(0)
	assert("AK-47" in hud.slots[0].text, "slot 0 has AK-47")
	assert("›" in hud.slots[0].text, "slot 0 active has chevron indicator")
	assert("Glock" in hud.slots[1].text, "slot 1 has Glock")
	assert(not ("›" in hud.slots[1].text), "slot 1 inactive has no chevron")
	
	# Ammo counter
	hud.update_ammo(30, 90)
	assert(hud.ammo_mag_label != null and hud.ammo_mag_label.text == "30", "ammo mag is 30")
	assert(hud.ammo_reserve_label != null and hud.ammo_reserve_label.text == "90", "ammo reserve is 90")
	
	# Skill UI
	hud.update_skill_ui("Adrenaline", 0.0, 10.0)
	assert("READY" in hud.skill_label.text, "skill ready shows READY")
	
	# Minimap compass
	var mm = hud.get_node("MinimapMargin/MinimapBG")
	var has_n := false
	for child in mm.get_children():
		if child is Label and child.text == "N":
			has_n = true
			break
	assert(has_n, "Minimap has N compass marker")
	
	hud.queue_free()
	await process_frame
	
	# 2. Test MultiplayerHUD & M-key team toggle
	var mp_hud_scene = load("res://scenes/ui/multiplayer_hud.tscn")
	assert(mp_hud_scene != null, "multiplayer_hud.tscn exists")
	var mp_hud = mp_hud_scene.instantiate()
	root.add_child(mp_hud)
	await process_frame
	
	assert(mp_hud.att_score_label != null, "att_score_label exists")
	assert(mp_hud.def_score_label != null, "def_score_label exists")
	assert(mp_hud.objective_label != null, "objective_label exists")
	assert(mp_hud.round_label != null, "round_label exists")
	assert(mp_hud.timer_label != null, "timer_label exists")
	
	# Side picker starts visible
	assert(mp_hud.side_picker.visible, "side_picker initially visible")
	
	# Simulate initial pick (no manager in test env — emulate joined state)
	mp_hud.has_joined_match = true
	mp_hud.toggle_side_picker()
	assert(not mp_hud.side_picker.visible, "picker closes after pick")
	assert(mp_hud.has_joined_match, "has_joined_match is true")
	
	# Simulate pressing M key to toggle team selection
	var ev_m := InputEventKey.new()
	ev_m.keycode = KEY_M
	ev_m.pressed = true
	mp_hud._input(ev_m)
	assert(mp_hud.side_picker.visible, "M key opens side_picker")
	
	# Press M key again to close
	mp_hud._input(ev_m)
	assert(not mp_hud.side_picker.visible, "M key toggles side_picker closed")
	
	# Press M key to open, then ESC to close
	mp_hud._input(ev_m)
	assert(mp_hud.side_picker.visible, "M key reopened side_picker")
	var ev_esc := InputEventKey.new()
	ev_esc.keycode = KEY_ESCAPE
	ev_esc.pressed = true
	mp_hud._input(ev_esc)
	assert(not mp_hud.side_picker.visible, "ESC key closes side_picker when in match")
	
	mp_hud.queue_free()
	
	print("RESULT: OK (HUD rework verified)")
	quit(0)
