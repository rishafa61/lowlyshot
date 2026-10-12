extends Area3D

var speed = 25.0
var max_range = 10.0
var distance_traveled = 0.0
var direction: Vector3 = Vector3.ZERO
var hit_enemies = []

func _ready():
	# Link area_entered signal to detect enemies
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	var move_step = speed * delta
	global_position += direction * move_step
	distance_traveled += move_step
	
	# Fade out slightly based on distance
	var alpha = 1.0 - (distance_traveled / max_range)
	if has_node("MeshInstance3D"):
		$MeshInstance3D.material_override.albedo_color.a = alpha * 0.5
	
	if distance_traveled >= max_range:
		queue_free()

var target_group: String = "enemy" # "enemy" for player-fired, "player" for enemy-fired

func _on_body_entered(body):
	# We use body_entered because CharacterBody3D is a PhysicsBody, not an Area
	if body.is_in_group(target_group) and body not in hit_enemies:
		hit_enemies.append(body)
		if body.has_method("stun"):
			body.stun(2.5)
