extends Operator

var duration: float = 0.0
const MAX_DURATION: float = 5.0
const SPEED_BONUS: float = 0.25 # +25% base movement speed
var player_ref: CharacterBody3D = null

func _init():
	op_name = "Vanguard"
	max_health = 120
	max_armor = 50
	speed_mult = 1.0
	skill_name = "Adrenaline"
	skill_cooldown = 30.0

func _ready():
	pass

func _process(delta):
	# Handle base cooldown
	super._process(delta)
	
	if duration > 0.0:
		duration -= delta
		if duration <= 0.0:
			duration = 0.0
			_reset_speed()
		else:
			_apply_decaying_speed()
			
		if player_ref and player_ref.hud:
			player_ref.hud.update_skill_duration(duration)

func _execute_skill(player: CharacterBody3D):
	player_ref = player
	var injector = player.get_node("Head/Camera3D/WeaponHolder/Injector")
	var holder = player.get_node("Head/Camera3D/WeaponHolder")
	
	# Hide current weapon, show injector
	for w in holder.get_children(): w.hide()
	injector.show()
	start_cooldown()
	
	# Animate stabbing motion
	var tween = create_tween()
	tween.tween_property(injector, "position:y", 0.1, 0.2).as_relative()
	tween.tween_property(injector, "position:y", -0.3, 0.1).as_relative() # Stab down!
	
	tween.tween_callback(func():
		# +heal 25
		player.health_component.heal(25.0)
		if player.hud:
			player.hud.update_stats(player.hp, player.max_hp, player.armor, player.max_armor, player.stamina, player.max_stamina)
			player.hud.show_damage_vignette() # Green screen flash
			player.hud.blood_vignette.color = Color(0, 1, 0, 0.3)
		
		# Start 5s decaying movement speed (+25%)
		duration = MAX_DURATION
		_apply_decaying_speed()
	)
	
	# Pull back up and swap back to weapon
	tween.tween_property(injector, "position:y", 0.2, 0.2).as_relative()
	tween.tween_callback(func():
		injector.hide()
		player.switch_weapon(player.active_slot)
	)

func _apply_decaying_speed():
	if not player_ref: return
	var progress = duration / MAX_DURATION # 1.0 -> 0.0
	var bonus = SPEED_BONUS * progress # 0.25 -> 0.0
	player_ref.speed_normal = 5.0 * (1.0 + bonus)
	player_ref.speed_sprint = 11.0 * (1.0 + bonus)

func _reset_speed():
	if not player_ref: return
	player_ref.speed_normal = 5.0 * speed_mult
	player_ref.speed_sprint = 11.0 * speed_mult
	if player_ref.hud:
		player_ref.hud.update_skill_duration(0.0)

## Triggered when an enemy dies to reduce Vanguard's cooldown by 5 seconds
func on_enemy_killed():
	if current_cooldown > 0:
		current_cooldown = max(0.0, current_cooldown - 5.0)
