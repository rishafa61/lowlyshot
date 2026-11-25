# Targeting sweep: many enemies at mixed distances/angles — is nearest always picked?
extends SceneTree

func _initialize() -> void:
	_run()

func _run() -> void:
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 1, 0)
	root.add_child(player)

	var positions := {
		"A": Vector3(3, 1, 3),      # ~4.2m nearest
		"B": Vector3(-7, 1, 2),     # ~7.3m
		"C": Vector3(0, 1, -9),     # 10m
		"D": Vector3(12, 1, 0),     # 12m
		"E": Vector3(-3, 1, 13),    # ~13.3m
		"F": Vector3(9, 1, 9),      # ~12.7m
	}
	var bots := {}
	for key in positions:
		var b = (load("res://scenes/enemies/capsule_enemy.tscn") as PackedScene).instantiate()
		b.position = positions[key]
		root.add_child(b)
		b.set_physics_process(false)
		bots[key] = b
	await process_frame
	await physics_frame

	# 5 trials with the drone spawned at varied offsets around the player
	var spawn_offsets := [
		Vector3(0, 3.2, 0), Vector3(4, 3.2, 4), Vector3(-6, 3.2, -2),
		Vector3(10, 3.2, 2), Vector3(2, 3.2, -8),
	]
	var fails := 0
	for trial in spawn_offsets.size():
		var d = (load("res://scenes/weapons/skills/hunter_drone.tscn") as PackedScene).instantiate()
		root.add_child(d)
		d.position = spawn_offsets[trial]
		d.setup(player)
		await physics_frame
		var t = d._find_target()
		var pick := "?"
		for key in bots:
			if bots[key] == t:
				pick = key
		var ok: bool = t == bots["A"]
		if not ok: fails += 1
		print("trial ", trial, " drone@", spawn_offsets[trial], " pick=", pick, " distA=",
			"%0.2f" % d._home_pos().distance_to(bots["A"].global_position),
			" -> ", "OK" if ok else "WRONG")
		d.queue_free()
		await process_frame

	print("RESULT: %s (%d wrong)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
