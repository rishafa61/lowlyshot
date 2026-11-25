# Empirical: does the drone acquire the NEAREST enemy with REAL game objects?
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
	# Offline player: team "attackers" default, NO ally/enemy group
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "1"
	player.position = Vector3(0, 1, 0)
	root.add_child(player)
	await process_frame
	await physics_frame

	# Real bots from real scenes: ally bot at 3m (nearest, must be ignored),
	# enemy bots at 5m and 8m
	var ally_bot = (load("res://scenes/enemies/capsule_ally.tscn") as PackedScene).instantiate()
	ally_bot.position = Vector3(3, 1, 0)
	root.add_child(ally_bot)
	var near_bot = (load("res://scenes/enemies/capsule_enemy.tscn") as PackedScene).instantiate()
	near_bot.position = Vector3(5, 1, 0)
	root.add_child(near_bot)
	var far_bot = (load("res://scenes/enemies/capsule_enemy.tscn") as PackedScene).instantiate()
	far_bot.position = Vector3(8, 1, 0)
	root.add_child(far_bot)
	# Freeze bot AI so the bots don't shoot each other mid-test
	ally_bot.set_physics_process(false)
	near_bot.set_physics_process(false)
	far_bot.set_physics_process(false)
	await process_frame
	await physics_frame

	print("groups: player=", player.is_in_group("player"), " ally_bot_ally=", ally_bot.is_in_group("ally"),
		" near_bot_enemy=", near_bot.is_in_group("enemy"), " far_bot_enemy=", far_bot.is_in_group("enemy"))
	print("near_bot is_dead=", near_bot.get("is_dead"), " ally is_dead=", ally_bot.get("is_dead"))

	var drone = (load("res://scenes/weapons/skills/hunter_drone.tscn") as PackedScene).instantiate()
	root.add_child(drone)
	drone.position = Vector3(0, 3.2, 0)
	drone.setup(player)
	await physics_frame

	print("drone faction=", drone.faction)
	print("valid(near_enemy)=", drone._is_valid_enemy(near_bot))
	print("valid(far_enemy)=", drone._is_valid_enemy(far_bot))
	print("valid(ally_bot)=", drone._is_valid_enemy(ally_bot))

	var t = drone._find_target()
	print("find_target() = ", t, " expected ", near_bot)
	check(t == near_bot, "drone picks nearest ENEMY bot (5m), ignores ally bot (3m)")

	# Alive sim: let the drone actually fly to and lock the target
	var stunned := false
	var drone_state := "none"
	for i in 600:
		await physics_frame
		if not is_instance_valid(drone):
			print("DEBUG drone gone at frame ", i, " state=", drone_state, " stunned=", stunned)
			break
		drone_state = drone.get("_state")
		if is_instance_valid(near_bot) and near_bot.get("is_stunned"):
			stunned = true
			break
	check(stunned, "drone flew to nearest enemy bot and delivered EMP in-game objects")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
