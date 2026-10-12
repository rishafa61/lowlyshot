extends EnemyOperator

var shockwave_scene = preload("res://scenes/weapons/skills/shockwave_pulse.tscn")

func _init():
	op_name = "Shock"
	max_health = 110
	speed_mult = 0.95
	skill_cooldown = 20.0
	skill_name = "Shockwave"

func _execute_skill(target: Node3D):
	if not enemy_ref: return
	current_cooldown = skill_cooldown
	
	var proj = shockwave_scene.instantiate()
	proj.target_group = "player"
	proj.max_range = 15.0 # Fixed medium range for AI
	
	enemy_ref.get_parent().add_child(proj)
	var ground_pos = enemy_ref.global_position
	ground_pos.y -= 0.8
	proj.global_position = ground_pos
	
	var dir = get_aim_dir(target)
	proj.direction = dir
	if dir.length() > 0.01:
		proj.look_at(proj.global_position + dir, Vector3.UP)
