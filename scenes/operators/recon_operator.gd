extends Operator

var arrow_scene = preload("res://scenes/weapons/skills/sonar_arrow.tscn")
var is_holding_bow = false
var is_charging = false
var charge_level = 0.0
var max_charge_time = 1.0 # 1 second to fully charge
var player_ref: CharacterBody3D = null
var bounce_count = 0
var is_firing_anim = false

func _ready():
	op_name = "Ghost"
	max_health = 100
	max_armor = 25
	speed_mult = 1.15
	skill_name = "Sonar Bow"
	skill_cooldown = 15.0

func _process(delta):
	# Handle cooldown manually since we override the base class _process
	if current_cooldown > 0:
		current_cooldown -= delta
		
	if is_holding_bow and player_ref and not is_firing_anim:
		var bow = player_ref.get_node("Head/Camera3D/WeaponHolder/SonarBow")
		var arrow = bow.get_node("BowBody/Arrow")
		
		if Input.is_action_pressed("fire"):
			is_charging = true
			charge_level += delta / max_charge_time
			if charge_level > 1.0: charge_level = 1.0
			
			# Pull back the string (animate arrow position local X from 0.0 to 0.4)
			arrow.position.x = lerp(0.0, 0.4, charge_level)
			
			# Update HUD to show charge percentage
			player_ref.hud.update_bow_ui(true, charge_level, bounce_count)
			
		elif is_charging and Input.is_action_just_released("fire"):
			is_firing_anim = true
			is_charging = false
			
			# Fire the arrow!
			arrow.hide()
			var proj = arrow_scene.instantiate()
			proj.bounces_left = bounce_count
			# Very low charge = heavy drop (15 speed), Max charge = laser flat (80 speed)
			proj.speed = 15.0 + (65.0 * charge_level) 
			
			player_ref.get_parent().add_child(proj)
			
			# Spawn it slightly in front of the camera so it doesn't collide with the player immediately
			var cam_dir = -player_ref.camera.global_transform.basis.z
			proj.global_position = player_ref.camera.global_position + (cam_dir * 1.0)
			proj.set_start_direction(cam_dir)
			
			# Replicate the sonar arrow so others see/hear it too
			var mgr = player_ref.get_tree().current_scene
			if mgr is MultiplayerManager:
				mgr.spawn_utility_net("res://scenes/weapons/skills/sonar_arrow.tscn", proj.global_position, cam_dir, {
					"bounces_left": proj.bounces_left,
					"speed": proj.speed
				})
			
			# Reset visual state
			bow.hide()
			arrow.position.x = 0.0
			arrow.show()
			
			start_cooldown() # Only consume cooldown on fire
			
			is_holding_bow = false
			is_firing_anim = false
			bounce_count = 0
			charge_level = 0.0
			player_ref.hud.update_bow_ui(false)
			player_ref.switch_weapon(player_ref.active_slot)

func _execute_skill(player: CharacterBody3D):
	if is_holding_bow and not is_charging and not is_firing_anim:
		cancel_skill()
		return
		
	if is_firing_anim:
		return
		
	player_ref = player
	is_holding_bow = true
	is_charging = false
	charge_level = 0.0
	bounce_count = 0
	player_ref.hud.update_bow_ui(true, 0.0, 0)
	
	var bow = player.get_node("Head/Camera3D/WeaponHolder/SonarBow")
	var holder = player.get_node("Head/Camera3D/WeaponHolder")
	
	# Hide all weapons, show bow
	for w in holder.get_children(): w.hide()
	bow.show()

func override_fire() -> bool:
	# Just return true to block the normal weapon script from shooting
	if is_holding_bow:
		return true
	return false

func override_aim() -> bool:
	if is_holding_bow and not is_firing_anim and player_ref:
		bounce_count = (bounce_count + 1) % 3
		# Keep showing the charge percentage if currently charging
		player_ref.hud.update_bow_ui(true, charge_level, bounce_count)
		return true
	return false

func cancel_skill():
	if is_holding_bow and not is_firing_anim and player_ref:
		is_holding_bow = false
		is_charging = false
		charge_level = 0.0
		bounce_count = 0
		
		var bow = player_ref.get_node("Head/Camera3D/WeaponHolder/SonarBow")
		var arrow = bow.get_node("BowBody/Arrow")
		arrow.position.x = 0.0
		bow.hide()
		
		player_ref.hud.update_bow_ui(false)
		player_ref.switch_weapon(player_ref.active_slot)
