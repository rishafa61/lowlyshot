extends EnemyOperator

var airstrike_manager_scene = preload("res://scenes/weapons/skills/airstrike_manager.tscn")

func _init():
	op_name = "Wingman"
	max_health = 100
	speed_mult = 1.05
	skill_cooldown = 30.0
	skill_name = "Airstrike"

func _execute_skill(target: Node3D):
	if not enemy_ref or not target: return
	current_cooldown = skill_cooldown
	
	# Target the area around the player
	var target_pos = target.global_position
	
	var manager = airstrike_manager_scene.instantiate()
	manager.attacker_name = str(enemy_ref.get("bot_name")) if enemy_ref.get("bot_name") else "Enemy"
	manager.attacker_faction = "Ally" if enemy_ref.is_in_group("ally") else "Enemy"
	enemy_ref.get_parent().add_child(manager)
	manager.global_position = target_pos
