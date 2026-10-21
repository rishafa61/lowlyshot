extends SceneTree
func _initialize() -> void:
	var fails := 0
	for path in ["res://scenes/levels/search_and_destroy.tscn", "res://scenes/levels/multiplayer_arena.tscn"]:
		var scene := load(path) as PackedScene
		if scene == null:
			printerr("FAIL: load " + path)
			fails += 1
			continue
		var inst := scene.instantiate()
		root.add_child(inst)
		await process_frame
		var wenvs := inst.find_children("*", "WorldEnvironment", true, false)
		print(path, ": WorldEnvironment count = ", wenvs.size())
		if wenvs.size() != 1:
			printerr("FAIL: expected exactly 1 WorldEnvironment in " + path)
			fails += 1
		else:
			var env: Environment = wenvs[0].environment
			var mode_ok: bool = env != null and env.background_mode == Environment.BG_SKY
			var mat = env.sky.sky_material if env != null and env.sky != null else null
			var shader_ok: bool = mat is ShaderMaterial and (mat as ShaderMaterial).shader != null \
				and (mat as ShaderMaterial).shader.resource_path.ends_with("moving_sky.gdshader")
			print("  background_mode=SKY: ", mode_ok, " | moving_sky shader: ", shader_ok)
			if not mode_ok: printerr("FAIL: background_mode not SKY in " + path); fails += 1
			if not shader_ok: printerr("FAIL: moving_sky shader not assigned in " + path); fails += 1
		inst.queue_free()
	print("--- sky check done: %d fails ---" % fails)
	quit(1 if fails > 0 else 0)
