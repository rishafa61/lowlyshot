extends SceneTree

var fails := 0

func check(cond: bool, msg: String) -> void:
	print(("PASS: " if cond else "FAIL: ") + msg)
	if not cond:
		fails += 1

func _initialize() -> void:
	await process_frame # autoloads register after -s script compile
	var gs = root.get_node("/root/GlobalSettings")
	check(gs.get("profile_key") != null, "GlobalSettings exposes profile_key")
	check(gs._safe_name("Striker <3") == "Striker 3", "_safe_name strips filesystem-unsafe chars")
	var orig: String = gs.profile_key

	# Per-user roundtrip in a scratch profile
	gs.profile_key = "test_user.1"
	gs.ads_offset_x = 0.123
	gs.ads_rot_y = 12.5
	gs.save_settings()
	check(FileAccess.file_exists("user://profiles/test_user.1/settings.cfg"), "per-user cfg written under profiles/<name>/")
	gs.ads_offset_x = 0.0
	gs.ads_rot_y = 0.0
	gs._load()
	check(absf(gs.ads_offset_x - 0.123) < 0.0001 and absf(gs.ads_rot_y - 12.5) < 0.01, "per-user load roundtrips values")

	# Legacy global cfg untouched by the scratch profile save
	if FileAccess.file_exists("user://settings.cfg"):
		var def := ConfigFile.new()
		def.load("user://settings.cfg")
		check(absf(float(def.get_value("gameplay", "ads_x", 0.0)) - 0.123) > 0.0001, "legacy settings.cfg not overwritten")

	# Cleanup scratch profile + restore
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://profiles/test_user.1/settings.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://profiles/test_user.1"))
	gs.profile_key = orig
	gs._load()

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
