extends EnemyOperator

var sonar_scene = preload("res://scenes/weapons/skills/sonar_arrow.tscn")

func _init():
	op_name = "Ghost"
	max_health = 90
	speed_mult = 1.1
	skill_cooldown = 20.0
	skill_name = "Sonar Arrow"

func _execute_skill(target: Node3D):
	if not enemy_ref: return
	current_cooldown = skill_cooldown
	
	# Fire a sonar arrow towards the player
	var proj = sonar_scene.instantiate()
	proj.enemy_fired = true
	enemy_ref.get_parent().add_child(proj)
	proj.global_position = enemy_ref.global_position + Vector3(0, 1.5, 0)
	
	var dir = (get_aim_pos(target) - proj.global_position).normalized()
	if proj.has_method("set_start_direction"):
		proj.set_start_direction(dir)
	elif "direction" in proj:
		proj.direction = dir
		proj.look_at(proj.global_position + dir, Vector3.UP)
