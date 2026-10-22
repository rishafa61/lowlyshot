extends EnemyOperator

var turret_scene = preload("res://scenes/weapons/skills/auto_turret.tscn")

func _init():
	op_name = "Sentry"
	max_health = 100
	speed_mult = 1.0
	skill_cooldown = 25.0
	skill_name = "Auto-Turret"

func _execute_skill(_target: Node3D):
	if not enemy_ref: return
	current_cooldown = skill_cooldown
	
	# Spawn turret slightly in front of the enemy
	var turret = turret_scene.instantiate()
	var spawn_pos = enemy_ref.global_position + (-enemy_ref.global_transform.basis.z * 2.0)
	
	# Add to tree BEFORE setting global transform
	enemy_ref.get_parent().add_child(turret)
	turret.global_position = spawn_pos
	
	# Ensure turret targets the correct faction and inherits team/owner
	var bot_name = enemy_ref.get("bot_name")
	if not bot_name or bot_name == "":
		bot_name = "Ally" if enemy_ref.is_in_group("ally") else "Enemy"
	turret.owner_name = str(bot_name)
	turret.weapon_name = "Auto-Turret"

	if enemy_ref.is_in_group("ally"):
		turret.faction = "Ally"
		turret.target_mode = "enemies"
		turret.add_to_group("ally_turret")
		turret.add_to_group("ally")
	else:
		turret.faction = "Enemy"
		turret.target_mode = "player"
		turret.remove_from_group("player_turret")
		turret.add_to_group("enemy_turret")
		turret.add_to_group("enemy")
	# S&D / team modes: relations follow the summoner's team, not groups
	var bot_team = enemy_ref.get("snd_team")
	if bot_team != null and str(bot_team) != "":
		turret.snd_team = str(bot_team)
