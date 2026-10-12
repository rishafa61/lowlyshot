extends Operator

var turret_scene = preload("res://scenes/weapons/skills/auto_turret.tscn")
var active_turret: Node3D = null

func _ready() -> void:
	op_name = "Sentry"
	max_health = 100
	max_armor = 50
	speed_mult = 1.0
	skill_name = "Sentinel"
	skill_cooldown = 15.0

func _exit_tree() -> void:
	if active_turret and is_instance_valid(active_turret):
		active_turret.queue_free()
		active_turret = null

func _execute_skill(player: CharacterBody3D) -> void:
	var space_state = player.get_world_3d().direct_space_state
	var cam = player.camera
	var ray_start = cam.global_position
	var ray_end = ray_start + (-cam.global_transform.basis.z * 5.0)
	
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [player.get_rid()]
	var result = space_state.intersect_ray(query)
	
	var spawn_pos := Vector3.ZERO
	if result and result.normal.dot(Vector3.UP) > 0.7:
		spawn_pos = result.position
	else:
		# Fallback to raycast down from front position
		var drop_start = player.global_position + (-player.global_transform.basis.z * 2.0) + Vector3(0, 1.0, 0)
		var drop_end = drop_start + Vector3(0, -3.0, 0)
		var drop_query = PhysicsRayQueryParameters3D.create(drop_start, drop_end)
		drop_query.exclude = [player.get_rid()]
		var drop_result = space_state.intersect_ray(drop_query)
		if drop_result and drop_result.normal.dot(Vector3.UP) > 0.7:
			spawn_pos = drop_result.position
		else:
			return # Invalid placement

	if active_turret and is_instance_valid(active_turret):
		active_turret.queue_free()
	
	active_turret = turret_scene.instantiate()
	player.get_parent().add_child(active_turret)
	active_turret.global_position = spawn_pos
	active_turret.faction = "Player"
	active_turret.target_mode = "enemies"
	active_turret.owner_name = "Player"
	active_turret.weapon_name = "Auto-Turret"
	active_turret.add_to_group("ally")
	
	var flat_forward = -player.global_transform.basis.z
	flat_forward.y = 0
	if flat_forward.length_squared() > 0.001:
		active_turret.look_at(spawn_pos + flat_forward, Vector3.UP)
	
	# Replicate turret to other peers (visual replica only there)
	var mgr = player.get_tree().current_scene
	if mgr is MultiplayerManager:
		mgr.spawn_utility_net("res://scenes/weapons/skills/auto_turret.tscn", spawn_pos, flat_forward, {
			"faction": "Player",
			"owner_name": "Player"
		})
	
	start_cooldown()
