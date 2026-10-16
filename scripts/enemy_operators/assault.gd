extends EnemyOperator

var duration: float = 0.0
const MAX_DURATION: float = 5.0
const SPEED_BONUS: float = 0.25

func _init():
	op_name = "Vanguard"
	max_health = 120
	speed_mult = 1.0
	skill_cooldown = 15.0 # enemies use it more often
	skill_name = "Adrenaline"

func _process(delta):
	super._process(delta)
	if duration > 0.0:
		duration -= delta
		if duration <= 0.0:
			duration = 0.0
			_reset_speed()
		else:
			_apply_decaying_speed()

func _execute_skill(_target: Node3D):
	if not enemy_ref: return
	current_cooldown = skill_cooldown
	
	# Heal
	enemy_ref.health_component.heal(25.0)
	
	# Apply speed boost
	duration = MAX_DURATION
	_apply_decaying_speed()
	
	# Show healing visual effect (green outline)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0, 1, 0, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0, 1, 0, 1)
	if "body" in enemy_ref and enemy_ref.body and enemy_ref.body.has_method("set_overlay"):
		enemy_ref.body.set_overlay(mat)
	elif "mesh" in enemy_ref and enemy_ref.mesh and "material_overlay" in enemy_ref.mesh:
		enemy_ref.mesh.material_overlay = mat
	
	var tween = create_tween()
	tween.tween_interval(1.0)
	tween.tween_callback(func():
		if not is_instance_valid(enemy_ref): return
		if "body" in enemy_ref and enemy_ref.body and enemy_ref.body.has_method("clear_overlay"):
			enemy_ref.body.clear_overlay()
		elif "mesh" in enemy_ref and enemy_ref.mesh and "material_overlay" in enemy_ref.mesh:
			enemy_ref.mesh.material_overlay = null
	)

func _apply_decaying_speed():
	if not enemy_ref: return
	var progress = duration / MAX_DURATION
	var bonus = SPEED_BONUS * progress
	enemy_ref.current_speed_mult = speed_mult * (1.0 + bonus)

func _reset_speed():
	if not enemy_ref: return
	enemy_ref.current_speed_mult = speed_mult
