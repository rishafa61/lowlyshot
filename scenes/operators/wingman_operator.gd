extends Operator

var airstrike_manager = preload("res://scenes/weapons/skills/airstrike_manager.tscn")

var is_holding_skill = false
var player_ref: CharacterBody3D = null
var target_indicator: MeshInstance3D = null
var laser_line: MeshInstance3D = null

func _ready():
	op_name = "Wingman"
	max_health = 100
	max_armor = 50
	speed_mult = 1.05
	skill_name = "Airstrike"
	skill_cooldown = 45.0

func _process(delta):
	if current_cooldown > 0:
		current_cooldown -= delta
		
	if is_holding_skill and player_ref:
		update_targeting()
		
		# If they click fire, confirm the target!
		if Input.is_action_just_pressed("fire"):
			if target_indicator and target_indicator.visible:
				var mgr_scene = airstrike_manager.instantiate()
				player_ref.get_parent().add_child(mgr_scene)
				var strike_pos = target_indicator.global_position
				mgr_scene.global_position = strike_pos
				mgr_scene.attacker_name = player_ref.player_name
				mgr_scene.attacker_faction = "Ally" if player_ref.team == "attackers" else "Enemy"
				
				# Replicate airstrike barrage to other peers
				var mp_mgr = player_ref.get_tree().current_scene
				if mp_mgr is MultiplayerManager:
					mp_mgr.spawn_utility_net("res://scenes/weapons/skills/airstrike_manager.tscn", strike_pos, Vector3.FORWARD, {
						"attacker_name": mgr_scene.attacker_name,
						"attacker_faction": mgr_scene.attacker_faction,
					})
				
				start_cooldown()
				cancel_skill()

func _execute_skill(player: CharacterBody3D):
	if is_holding_skill:
		cancel_skill()
		return
		
	player_ref = player
	is_holding_skill = true
	player_ref.hud.update_skill_ui(skill_name + " [LMB TO CONFIRM]", current_cooldown, skill_cooldown)
	
	var holder = player.get_node("Head/Camera3D/WeaponHolder")
	for w in holder.get_children(): w.hide()
	
	var locator = holder.get_node_or_null("AirstrikeLocator")
	if locator: locator.show()
	
	create_targeting_visuals()

func create_targeting_visuals():
	if not target_indicator:
		target_indicator = MeshInstance3D.new()
		var torus = TorusMesh.new()
		torus.inner_radius = 4.8
		torus.outer_radius = 5.0
		target_indicator.mesh = torus
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0, 0, 0.8)
		mat.emission_enabled = true
		mat.emission = Color(1, 0, 0)
		mat.no_depth_test = true
		target_indicator.material_override = mat
		
		player_ref.get_parent().add_child(target_indicator)
		
	if not laser_line:
		laser_line = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.02
		laser_line.mesh = cyl
		
		var l_mat = StandardMaterial3D.new()
		l_mat.albedo_color = Color(1, 0, 0, 0.5)
		l_mat.emission_enabled = true
		l_mat.emission = Color(1, 0, 0)
		l_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		laser_line.material_override = l_mat
		
		player_ref.get_parent().add_child(laser_line)

func update_targeting():
	var space_state = player_ref.get_world_3d().direct_space_state
	var cam = player_ref.camera
	var ray_start = cam.global_position
	var ray_end = ray_start + (-cam.global_transform.basis.z * 100.0)
	
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [player_ref.get_rid()]
	var result = space_state.intersect_ray(query)
	
	if result:
		target_indicator.show()
		laser_line.show()
		target_indicator.global_position = result.position
		
		# Draw laser from the locator device muzzle to the target
		var laser_start: Vector3 = player_ref.get_node("Head/Camera3D/WeaponHolder").global_position
		var locator: Node3D = player_ref.get_node_or_null("Head/Camera3D/WeaponHolder/AirstrikeLocator")
		if locator and locator.visible:
			var marker: Marker3D = locator.get_node_or_null("MuzzleMarker")
			if marker: laser_start = marker.global_position
		
		var dist: float = laser_start.distance_to(result.position)
		laser_line.mesh.height = dist
		laser_line.global_position = laser_start.lerp(result.position, 0.5)
		# Guard: look_at fails when target is straight up/down from laser_start
		if absf(laser_start.direction_to(result.position).y) < 0.999:
			laser_line.look_at(result.position, Vector3.UP)
		laser_line.rotate_x(PI/2) # Cylinder meshes are upright (Y), so rotate to aim along Z
	else:
		target_indicator.hide()
		laser_line.hide()

func override_fire() -> bool:
	return is_holding_skill

func override_aim() -> bool:
	return is_holding_skill

func cancel_skill():
	if is_holding_skill and player_ref:
		is_holding_skill = false
		
		if target_indicator: 
			target_indicator.queue_free()
			target_indicator = null
		if laser_line: 
			laser_line.queue_free()
			laser_line = null
		
		var locator = player_ref.get_node_or_null("Head/Camera3D/WeaponHolder/AirstrikeLocator")
		if locator: locator.hide()
		
		player_ref.switch_weapon(player_ref.active_slot)
