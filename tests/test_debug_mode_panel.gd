extends SceneTree

# Debug Mode panel: Visual tab search bar + per-weapon ADS/Hipfire tuner rows.
# Covers: panel build, weapon-name titles, search filter, per-weapon offset
# storage with global fallback, tuner weapon wiring (standalone rig path).

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
	await process_frame # autoloads register on the first frame
	var gs = root.get_node("/root/GlobalSettings")
	var gd = root.get_node("/root/GlobalData")

	# --- Per-weapon offset helpers: fallback + round-trip isolation ---
	var def_off: Vector3 = Vector3(gs.ads_offset_x, gs.ads_offset_y, gs.ads_offset_z)
	check(gs.get_vm_off("m4a4", "ads") == def_off, "no per-weapon entry falls back to global ADS offset")
	check(gs.get_vm_rot("m4a4", "hip") == gs.hip_rot_y, "no per-weapon entry falls back to global hip rot")
	gs.set_vm_off("m4a4", "ads", Vector3(1, 2, 3))
	gs.set_vm_rot("m4a4", "ads", -7.0)
	check(gs.get_vm_off("m4a4", "ads") == Vector3(1, 2, 3), "set/get ADS offset round-trip")
	check(gs.get_vm_rot("m4a4", "ads") == -7.0, "set/get ADS rot round-trip")
	check(gs.get_vm_off("m4a4", "hip") == Vector3(gs.hip_offset_x, gs.hip_offset_y, gs.hip_offset_z), "ads write leaves hip fallback untouched")
	gs.vm_offsets.erase("m4a4") # cleanup: don't leak into other tests

	# --- Panel build ---
	var sc = load("res://scenes/ui/settings_menu.tscn") as PackedScene
	var menu = sc.instantiate()
	root.add_child(menu)
	for i in 3:
		await process_frame

	var vis_panel = menu.get_node("Content/TabVisualPanel")
	var title_lbl: Label = null
	var search: LineEdit = null
	for c in vis_panel.get_children():
		if c is Label and c.text == "DEBUG MODE":
			title_lbl = c
		elif c is LineEdit:
			search = c
	check(title_lbl != null, "Visual tab has DEBUG MODE title")
	check(search != null, "Debug Mode panel has search bar")

	# --- Weapon rows: catalog weapons, weapon name in button titles ---
	var expected: Array = []
	for category in gd.weapons:
		for w in gd.weapons[category]:
			expected.append(str(w.get("name", "")))
	var ads_titles := {}
	var hip_titles := {}
	for b in menu.find_children("*", "Button", true, false):
		if b.text.begins_with("Set ADS Offset ("):
			ads_titles[b.text] = b
		elif b.text.begins_with("Set Hipfire Offset ("):
			hip_titles[b.text] = b
	check(ads_titles.has("Set ADS Offset (AK-47)"), "AK-47 ADS button titled with weapon name")
	check(hip_titles.has("Set Hipfire Offset (AK-47)"), "AK-47 hipfire button titled with weapon name")
	check(ads_titles.size() == expected.size(), "one ADS row per catalog weapon (got %d, want %d)" % [ads_titles.size(), expected.size()])
	check(hip_titles.size() == expected.size(), "one hipfire row per catalog weapon")

	# --- Row wiring: button carries its weapon into the tuner ---
	var ak_btn: Button = ads_titles["Set ADS Offset (AK-47)"]
	ak_btn.pressed.emit()
	await process_frame
	var tuner = null
	for c in root.get_children():
		if c.get("weapon_id") != null and c.get("mode") != null:
			tuner = c
	check(tuner != null, "ADS button spawns viewmodel tuner")
	check(tuner.get("weapon_id") == "ak47" and tuner.get("weapon_name") == "AK-47",
		"tuner bound to pressed weapon (got %s)" % str(tuner.get("weapon_id")))
	tuner.queue_free()
	await process_frame
	menu.visible = true

	# --- Search filter ---
	search.text = "glock"
	search.text_changed.emit("glock")
	var visible_plates := 0
	for c in vis_panel.get_children():
		if c is ScrollContainer:
			for plate in c.get_child(0).get_children():
				if plate.visible:
					visible_plates += 1
	check(visible_plates == 1, "search 'glock' filters to 1 row (got %d)" % visible_plates)
	search.text = ""
	search.text_changed.emit("")
	visible_plates = 0
	for c in vis_panel.get_children():
		if c is ScrollContainer:
			for plate in c.get_child(0).get_children():
				if plate.visible:
					visible_plates += 1
	check(visible_plates == expected.size(), "empty search restores all rows (got %d)" % visible_plates)

	# --- Standalone tuner with a non-default weapon loads its rig ---
	var ed = (load("res://scenes/ui/viewmodel_offset.tscn") as PackedScene).instantiate()
	ed.weapon_id = "glock"
	ed.weapon_name = "Glock"
	root.add_child(ed)
	await process_frame
	check(ed.get_node("World/Holder").get_child_count() > 0, "standalone tuner instantiates a weapon rig")
	check(ed.get_node("World/Holder").get_child(0).name.begins_with("Glock"),
		"rig is the tuned weapon's model (got %s)" % ed.get_node("World/Holder").get_child(0).name)
	ed.queue_free()

	# --- Content must never overflow upward over the TopBar (tab blocking) ---
	# Regressed once: Debug scroll min-height forced Content min-size past the
	# window; grow_vertical=BOTH pushed its rect up over the tab buttons.
	# Headless Window size is fixed, so lay out inside a small SubViewport.
	var sv := SubViewport.new()
	sv.size = Vector2i(900, 600)
	root.add_child(sv)
	var small = sc.instantiate()
	sv.add_child(small)
	for i in 3:
		await process_frame
	var content_top: float = small.get_node("Content").get_global_rect().position.y
	var topbar_bottom: float = small.get_node("TopBar").get_global_rect().end.y
	check(content_top >= topbar_bottom - 1.0,
		"Content stays below TopBar at 900x600 (content_top %.0f vs topbar_bottom %.0f)" % [content_top, topbar_bottom])
	sv.queue_free()

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
