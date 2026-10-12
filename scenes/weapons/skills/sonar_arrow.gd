extends CharacterBody3D

var speed = 40.0
var active = true
var scan_radius = 20.0
var bounces_left = 0
var enemy_fired: bool = false
var direction: Vector3 = Vector3.ZERO
var velocity_vec: Vector3 = Vector3.ZERO
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var sonar_sphere = $SonarSphere

func set_start_direction(dir: Vector3):
	direction = dir.normalized()
	velocity_vec = direction * speed
	look_at(global_position + direction, Vector3.UP)

func _physics_process(delta):
	if not active: return
	
	# Apply gravity
	velocity_vec.y -= gravity * delta
	
	var collision = move_and_collide(velocity_vec * delta)
	if collision:
		if bounces_left > 0:
			bounces_left -= 1
			
			# Calculate bounce reflection using the actual velocity
			velocity_vec = velocity_vec.bounce(collision.get_normal())
			# Apply slight damping to simulate losing energy on bounce
			velocity_vec *= 0.8 
			
			# Reorient arrow to face the new velocity direction
			look_at(global_position + velocity_vec.normalized(), Vector3.UP)
		else:
			active = false
			# Move the arrow slightly back along the normal to prevent clipping into walls
			global_position = collision.get_position() + (collision.get_normal() * 0.1)
			detonate_sonar()
	else:
		# Continuously update rotation to arc downwards with gravity
		look_at(global_position + velocity_vec.normalized(), Vector3.UP)

func detonate_sonar():
	sonar_sphere.show()
	var mat = sonar_sphere.material.duplicate()
	sonar_sphere.material = mat
	
	var tween = create_tween()
	tween.tween_property(sonar_sphere, "radius", scan_radius, 1.0)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 1.0)
	
	if enemy_fired:
		# Enemy-fired arrow: the caster already knows the player's position, so just visual
		pass
	else:
		var enemies = get_tree().get_nodes_in_group("enemy")
		for e in enemies:
			if e.global_position.distance_to(global_position) <= scan_radius:
				if e.has_method("reveal_silhouette"):
					e.reveal_silhouette()
	
	tween.tween_callback(queue_free)
