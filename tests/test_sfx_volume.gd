# SFX volume bus test — headless: verifies Sfx creates the SFX/Music buses,
# routes new players onto the SFX bus, and apply_volumes maps slider 0-100
# to bus gain (so the settings slider controls every game sound).
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
	var sfx = root.get_node_or_null("/root/Sfx")
	# Autoloads may not exist under --script; load manually.
	if sfx == null:
		var script = load("res://scripts/sfx.gd")
		sfx = Node.new()
		sfx.set_script(script)
		sfx.name = "Sfx"
		root.add_child(sfx)
		await process_frame

	check(AudioServer.get_bus_index("SFX") != -1, "SFX bus exists")
	check(AudioServer.get_bus_index("Music") != -1, "Music bus exists")
	var idx := AudioServer.get_bus_index("SFX")
	check(AudioServer.get_bus_send(idx) == "Master", "SFX bus sends to Master")

	# Slider at 50% -> roughly -6 dB
	var gs = root.get_node_or_null("/root/GlobalSettings")
	if gs == null:
		gs = Node.new()
		gs.set_script(load("res://scripts/global_settings.gd"))
		gs.name = "GlobalSettings"
		root.add_child(gs)
		await process_frame
	gs.sfx_vol = 50.0
	sfx.apply_volumes()
	var db := AudioServer.get_bus_volume_db(idx)
	check(absf(db - linear_to_db(0.5)) < 0.1, "50%% slider -> %f dB" % db)

	gs.sfx_vol = 0.0
	sfx.apply_volumes()
	db = AudioServer.get_bus_volume_db(idx)
	check(db < -60.0, "0%% slider -> near silent (%f dB)" % db)

	gs.sfx_vol = 100.0
	sfx.apply_volumes()
	check(absf(AudioServer.get_bus_volume_db(idx)) < 0.01, "100%% slider -> 0 dB")

	# New players route to the SFX bus
	var target := Node3D.new()
	root.add_child(target)
	sfx.oneshot3d("rifle_single", target, 10.0, 80.0, 0.0)
	await process_frame
	var found := false
	for cc in target.get_children():
		if cc is AudioStreamPlayer3D and cc.bus == "SFX":
			found = true
	check(found, "spawned player routed to SFX bus")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
