extends SceneTree
func _initialize() -> void:
	var path := "res://scenes/levels/multiplayer_arena.tscn"
	var scene := load(path) as PackedScene
	assert(scene != null, "arena scene load failed")
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	var atk_sp = inst.get_node_or_null("AttackersSpawn")
	var def_sp = inst.get_node_or_null("DefendersSpawn")
	assert(atk_sp != null and def_sp != null, "missing spawn markers")
	print("Atk spawn: ", atk_sp.global_position)
	print("Def spawn: ", def_sp.global_position)
	assert(atk_sp.global_position.x < -50.0)
	assert(def_sp.global_position.x > 50.0)
	print("Multiplayer arena smoke OK")
	inst.queue_free()
	quit(0)
