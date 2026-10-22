extends SceneTree
## Regression test for S&D halftime AI team awareness + sentinel turret friendly fire

var fails: int = 0
var _mock_script: GDScript

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		printerr("FAIL: " + label)
		fails += 1

func _initialize() -> void:
	# Mock combatant with real team/snd_team vars (plain CharacterBody3D.set()
	# silently no-ops on missing properties)
	_mock_script = GDScript.new()
	_mock_script.source_code = "extends CharacterBody3D\nvar team: String = \"\"\nvar snd_team: String = \"\"\n"
	_mock_script.reload()

	var turret_scene = load("res://scenes/weapons/skills/auto_turret.tscn")
	var turret = turret_scene.instantiate()
	root.add_child(turret)
	turret.position = Vector3(100, 0, 100) # keep away from origin so proximity tests stay deterministic
	turret.snd_team = "attackers"

	var att_player: CharacterBody3D = _mock_script.new()
	att_player.add_to_group("player")
	att_player.team = "attackers"
	att_player.position = Vector3(10, 0, 0)
	root.add_child(att_player)

	var def_player: CharacterBody3D = _mock_script.new()
	def_player.add_to_group("player")
	def_player.team = "defenders"
	def_player.position = Vector3(20, 0, 0)
	root.add_child(def_player)

	var enemy_scene = load("res://scenes/enemies/capsule_enemy.tscn")
	var enemy_bot = enemy_scene.instantiate()
	root.add_child(enemy_bot)

	await process_frame

	# 1. Turret targeting in team mode
	check(not turret.is_valid_enemy(att_player), "Attacker turret ignores attacker player")
	check(turret.is_valid_enemy(def_player), "Attacker turret targets defender player")

	# Attacker shooting attacker turret -> 0 damage (friendly fire blocked)
	var dmg_same = turret.take_damage(50.0, "Teammate", "Gun", "Ally")
	check(dmg_same == 0.0, "Attacker player cannot damage ally turret (friendly fire = 0)")

	# Defender shooting attacker turret -> takes damage
	var dmg_enemy = turret.take_damage(50.0, "Defender", "Gun", "Enemy")
	check(dmg_enemy > 0.0, "Defender player damages attacker turret")

	# 2. Turret side swap at halftime
	turret.snd_team = "defenders"
	check(turret.is_valid_enemy(att_player), "Swapped turret now targets attacker")
	check(not turret.is_valid_enemy(def_player), "Swapped turret now ignores defender")

	# 3. Enemy bot targeting aware of snd_team
	enemy_bot.snd_team = "defenders"
	enemy_bot._find_nearest_target()
	check(enemy_bot.target == att_player, "Defender enemy bot targets attacker player, not defender")

	# Swap bot's team to attackers (halftime)
	enemy_bot.snd_team = "attackers"
	enemy_bot._find_nearest_target()
	check(enemy_bot.target == def_player, "Halftime-swapped enemy bot targets defender player")

	# 4. Ally bot targeting team-aware
	var ally_scene = load("res://scenes/enemies/capsule_ally.tscn")
	var ally_bot = ally_scene.instantiate()
	root.add_child(ally_bot)
	await process_frame
	ally_bot.snd_team = "attackers"
	ally_bot._find_nearest_enemy()
	check(ally_bot.target == def_player, "Attacker ally bot targets defender player, not teammate")

	turret.queue_free()
	att_player.queue_free()
	def_player.queue_free()
	enemy_bot.queue_free()
	ally_bot.queue_free()

	print("--- halftime team & turret tests done: %d fails ---" % fails)
	quit(1 if fails > 0 else 0)
