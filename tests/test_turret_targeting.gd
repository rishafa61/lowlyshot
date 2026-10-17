# Turret targeting test — headless: verifies a Defender-allied turret does NOT target
# a Defender player, but DOES target an Attacker player / ally.
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
	var turret_scene: PackedScene = load("res://scenes/weapons/skills/auto_turret.tscn")
	var turret = turret_scene.instantiate()
	turret.faction = "Enemy" # Defender ally sentry
	root.add_child(turret)
	await physics_frame

	# 1. Defender player (same team as this turret) -> must NOT be targeted
	var defender_player = CharacterBody3D.new()
	defender_player.set("team", "defenders")
	defender_player.add_to_group("player")
	defender_player.add_to_group("enemy")
	root.add_child(defender_player)
	check(not turret.is_valid_enemy(defender_player), "defender sentry ignores defender player (no friendly fire)")

	# 2. Attacker player (enemy to this turret) -> MUST be targeted
	var attacker_player = CharacterBody3D.new()
	attacker_player.set("team", "attackers")
	attacker_player.add_to_group("player")
	attacker_player.add_to_group("ally")
	root.add_child(attacker_player)
	check(turret.is_valid_enemy(attacker_player), "defender sentry targets attacker player")

	# 3. Attacker bot -> MUST be targeted
	var attacker_bot = CharacterBody3D.new()
	attacker_bot.add_to_group("ally")
	root.add_child(attacker_bot)
	check(turret.is_valid_enemy(attacker_bot), "defender sentry targets attacker bot")

	# 4. Defender bot -> must NOT be targeted
	var defender_bot = CharacterBody3D.new()
	defender_bot.add_to_group("enemy")
	root.add_child(defender_bot)
	check(not turret.is_valid_enemy(defender_bot), "defender sentry ignores defender bot")

	# 5. Flip turret to Attacker ("Ally") faction:
	turret.faction = "Ally"
	check(turret.is_valid_enemy(defender_player), "attacker sentry targets defender player")
	check(not turret.is_valid_enemy(attacker_player), "attacker sentry ignores attacker player")

	turret.queue_free()
	defender_player.queue_free()
	attacker_player.queue_free()
	attacker_bot.queue_free()
	defender_bot.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
