extends Operator

var shockwave_scene = preload("res://scenes/weapons/skills/shockwave_pulse.tscn")
var is_holding_skill = false
var is_charging = false
var charge_level = 0.0
var max_charge_time = 1.5 # 1.5s to fully charge (10m -> 30m)
var player_ref: CharacterBody3D = null
var indicator_mesh: MeshInstance3D = null

func _ready():
	op_name = "Shock"
	max_health = 110
	max_armor = 50
	speed_mult = 0.95 # Slightly slower tank
	skill_name = "Shockwave"
	skill_cooldown = 30.0

func _process(delta):
	if current_cooldown > 0:
		current_cooldown -= delta
		
	if is_holding_skill and player_ref:
		update_indicator()
		
		if Input.is_action_pressed("fire"):
			is_charging = true
			charge_level += delta / max_charge_time
			if charge_level > 1.0: charge_level = 1.0
			
			# Update HUD to show charge percentage
			player_ref.hud.update_bow_ui(true, charge_level, 0)
			
		elif is_charging and Input.is_action_just_released("fire"):
			# Fire the shockwave!
			var proj = shockwave_scene.instantiate()
			
			# Calculate range based on charge: 10m to 30m
			proj.max_range = lerp(10.0, 30.0, charge_level)
			
			player_ref.get_parent().add_child(proj)
			
			# Spawn at ground level right at player's feet
			var ground_pos = player_ref.global_position
			ground_pos.y -= 0.8 # Roughly floor height relative to player center
			proj.global_position = ground_pos
			
			# Face the direction the camera is looking (horizontal only)
			var cam_dir = -player_ref.camera.global_transform.basis.z
			cam_dir.y = 0
			if cam_dir.length() < 0.01:
				cam_dir = -player_ref.global_transform.basis.z
			cam_dir = cam_dir.normalized()
			proj.direction = cam_dir
			proj.look_at(proj.global_position + cam_dir, Vector3.UP)
			
			# Replicate shockwave visual + effect ownership
			var mgr = player_ref.get_tree().current_scene
			if mgr is MultiplayerManager:
				mgr.spawn_utility_net("res://scenes/weapons/skills/shockwave_pulse.tscn", ground_pos, cam_dir, {
					"max_range": proj.max_range
				})
			
			start_cooldown()
			
			is_holding_skill = false
			is_charging = false
			charge_level = 0.0
			player_ref.hud.update_bow_ui(false)
			remove_indicator()
			player_ref.switch_weapon(player_ref.active_slot)

func _execute_skill(player: CharacterBody3D):
	if is_holding_skill and not is_charging:
		cancel_skill()
		return
		
	player_ref = player
	is_holding_skill = true
	is_charging = false
	charge_level = 0.0
	player_ref.hud.update_bow_ui(true, 0.0, 0)
	
	create_indicator()
	update_indicator()
	
	var holder = player.get_node("Head/Camera3D/WeaponHolder")
	for w in holder.get_children(): w.hide()

func override_fire() -> bool:
	if is_holding_skill: return true
	return false

func override_aim() -> bool:
	if is_holding_skill: return true
	return false

func cancel_skill():
	if is_holding_skill and player_ref:
		is_holding_skill = false
		is_charging = false
		charge_level = 0.0
		player_ref.hud.update_bow_ui(false)
		remove_indicator()
		player_ref.switch_weapon(player_ref.active_slot)

func create_indicator():
	if indicator_mesh == null:
		indicator_mesh = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(4.0, 1.0) # Width 4m, Length 1m initially
		indicator_mesh.mesh = plane
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.8, 0.0, 0.3)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.6, 0.0)
		mat.emission_energy_multiplier = 1.0
		mat.no_depth_test = true
		
		indicator_mesh.material_override = mat
		player_ref.get_parent().add_child(indicator_mesh)

func update_indicator():
	if indicator_mesh and player_ref:
		var current_range = lerp(10.0, 30.0, charge_level)
		indicator_mesh.mesh.size.y = current_range
		
		var ground_pos = player_ref.global_position
		ground_pos.y -= 0.8 # Ground level
		
		var cam_dir = -player_ref.camera.global_transform.basis.z
		cam_dir.y = 0
		if cam_dir.length() < 0.01:
			cam_dir = -player_ref.global_transform.basis.z
		cam_dir = cam_dir.normalized()
		
		# Center of the plane needs to be halfway along the path
		indicator_mesh.global_position = ground_pos + (cam_dir * (current_range / 2.0))
		
		# Look at target but adjust for PlaneMesh orientation (it's flat on XZ)
		var look_target = indicator_mesh.global_position + cam_dir
		indicator_mesh.look_at(look_target, Vector3.UP)
		# PlaneMesh lies on XZ, and its Y size extends along Z.
		# look_at points -Z at the target. Since plane length is on Y size (Z axis), it aligns perfectly.

func remove_indicator():
	if indicator_mesh:
		indicator_mesh.queue_free()
		indicator_mesh = null
