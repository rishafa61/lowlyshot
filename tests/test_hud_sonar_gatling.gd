# Headless HUD Sonar & Gatling Heat Bar UI Test
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
	# 1. GlobalData setup
	if root.get_node_or_null("/root/GlobalData") == null:
		var gd = Node.new()
		gd.set_script(load("res://scripts/global_data.gd"))
		gd.name = "GlobalData"
		root.add_child(gd)
		await process_frame

	var hud_scene = load("res://scenes/ui/hud.tscn") as PackedScene
	check(hud_scene != null, "hud.tscn loads")
	var hud = hud_scene.instantiate()
	root.add_child(hud)
	await process_frame

	# 1. Verify Sonar Bow UI and SkillDurationLabel are hidden by default
	check(hud.bow_ui.visible == false, "BowUI hidden initially")
	check(hud.skill_duration_label.visible == false, "SkillDurationLabel hidden initially")

	# 2. Verify toggle_combat_hud(true) does NOT reveal bow_ui or skill_duration_label
	hud.toggle_combat_hud(true)
	check(hud.bow_ui.visible == false, "BowUI remains hidden after toggle_combat_hud(true)")
	check(hud.skill_duration_label.visible == false, "SkillDurationLabel remains hidden after toggle_combat_hud(true)")

	# 3. Verify toggle_aircraft_hud(false) does NOT reveal them
	hud.toggle_aircraft_hud(true)
	check(hud.bow_ui.visible == false, "BowUI hidden in aircraft mode")
	hud.toggle_aircraft_hud(false)
	check(hud.bow_ui.visible == false, "BowUI remains hidden after exiting aircraft mode")
	check(hud.skill_duration_label.visible == false, "SkillDurationLabel remains hidden after exiting aircraft mode")

	# 4. Verify bow_ui and skill_duration_label only show on explicit update calls
	hud.update_bow_ui(true, 0.5, 1)
	check(hud.bow_ui.visible == true, "BowUI shows on explicit update_bow_ui(true)")
	hud.update_bow_ui(false)
	check(hud.bow_ui.visible == false, "BowUI hides on explicit update_bow_ui(false)")

	hud.update_skill_duration(4.5)
	check(hud.skill_duration_label.visible == true, "SkillDurationLabel shows on duration > 0")
	hud.update_skill_duration(0.0)
	check(hud.skill_duration_label.visible == false, "SkillDurationLabel hides on duration <= 0")

	# 5. Aircraft HUD - Gatling heat bar tests
	hud.toggle_aircraft_hud(true)

	# 5a. Helicopter: Gatling heat bar must NOT show
	hud.update_aircraft_hud({"kind": "helicopter", "hp": 100, "max_hp": 100, "speed": 0, "climb": 0})
	check(hud.heat_bar.visible == false, "Heat bar hidden in helicopter")

	# 5b. Humvee: Gatling heat bar must NOT show
	hud.update_aircraft_hud({"kind": "humvee", "hp": 100, "max_hp": 100, "speed": 0})
	check(hud.heat_bar.visible == false, "Heat bar hidden in humvee")

	# 5c. Jet: slot 1 (Missile) -> heat bar hidden
	hud.update_aircraft_hud({
		"kind": "aircraft",
		"slot": 1,
		"heat": 50.0,
		"overheated": false,
		"speed": 200,
		"throttle": 0.5,
		"hp": 250,
		"max_hp": 250,
		"missile_l": 0.0,
		"missile_r": 0.0,
		"bombs": 2,
		"flares": 4
	})
	check(hud.heat_bar.visible == false, "Heat bar hidden when missile (slot 1) selected")

	# 5d. Jet: slot 0 (Gatling) -> heat bar visible
	hud.update_aircraft_hud({
		"kind": "aircraft",
		"slot": 0,
		"heat": 10.0,
		"overheated": false,
		"speed": 200,
		"throttle": 0.5,
		"hp": 250,
		"max_hp": 250,
		"missile_l": 0.0,
		"missile_r": 0.0,
		"bombs": 2,
		"flares": 4
	})
	check(hud.heat_bar.visible == true, "Heat bar visible when Gatling (slot 0) selected")
	check(hud.heat_bar.fill_mode == ProgressBar.FILL_BOTTOM_TO_TOP, "Heat bar fill mode is vertical bottom-to-top (got %d)" % hud.heat_bar.fill_mode)
	check(hud.heat_bar.offset_left > 0, "Heat bar positioned right beside crosshair (offset_left=%f)" % hud.heat_bar.offset_left)

	# 5e. Gradation colors
	var col_low = hud._heat_color(0.0)
	var col_mid = hud._heat_color(40.0)
	var col_high = hud._heat_color(80.0)
	var col_max = hud._heat_color(100.0)

	check(col_low.is_equal_approx(Color.WHITE), "0%% heat is White (got %s)" % col_low)
	check(col_mid.r > 0.9 and col_mid.g > 0.8 and col_mid.b < 0.3, "40%% heat is Yellow (got %s)" % col_mid)
	check(col_high.r > 0.9 and col_high.g < 0.3 and col_high.b < 0.2, "80%% heat reaches Red (got %s)" % col_high)
	check(col_max.r > 0.9 and col_max.g < 0.3 and col_max.b < 0.2, "100%% heat is Red (got %s)" % col_max)

	# 5f. Overheat label: only when overheated
	check(hud.overheat_label.visible == false, "Overheat label hidden when not overheated")
	hud.update_aircraft_hud({
		"kind": "aircraft",
		"slot": 0,
		"heat": 100.0,
		"overheated": true,
		"speed": 200,
		"throttle": 0.5,
		"hp": 250,
		"max_hp": 250,
		"missile_l": 0.0,
		"missile_r": 0.0,
		"bombs": 2,
		"flares": 4
	})
	check(hud.overheat_label.visible == true, "Overheat label visible when overheated")

	# 6. Heat gauge thermometer chrome (bracket caps + ticks frame)
	check(hud.heat_gauge_chrome != null, "Heat gauge chrome built")
	check(hud.heat_gauge_chrome.overheated == true, "Gauge chrome overheated flag set at 100% heat")
	check(hud.heat_gauge_chrome.visible == hud.heat_bar.visible, "Gauge chrome visibility syncs with heat bar")
	hud._update_heat_gauge(50.0, false)
	check(hud.heat_gauge_chrome.overheated == false, "Gauge chrome overheated flag clears")
	check(hud.heat_bar.offset_left > 0 and hud.heat_gauge_chrome.offset_left < hud.heat_bar.offset_left,
		"Gauge chrome frames the fill column on its left side")
	check(absf((hud.heat_bar.offset_right - hud.heat_bar.offset_left) - 12.0) < 0.01,
		"Fill column is 12px wide, inset in the gauge frame (got %f)" % (hud.heat_bar.offset_right - hud.heat_bar.offset_left))
	var bar_cx: float = (hud.heat_bar.offset_left + hud.heat_bar.offset_right) * 0.5
	var chrome_cx: float = (hud.heat_gauge_chrome.offset_left + hud.heat_gauge_chrome.offset_right) * 0.5
	check(absf(bar_cx - chrome_cx) < 0.01, "Fill column centered in gauge chrome (bar %f vs chrome %f)" % [bar_cx, chrome_cx])
	var cap_found := false
	for c in hud.heat_gauge_chrome.get_children():
		if c is Label and c.text == "HEAT":
			cap_found = true
	check(cap_found, "HEAT caption present under gauge")

	hud.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
