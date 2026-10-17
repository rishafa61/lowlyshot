extends RigidBody3D

var fuse: float = 3.0
var is_net_replica: bool = false
var owner_name: String = "Player"
var attacker_faction: String = "Player"

func _physics_process(delta):
	fuse -= delta
	if fuse <= 0.0:
		explode()

func explode():
	print("GRENADE EXPLODED!")
	var space_state = get_world_3d().direct_space_state
	
	var explosion = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 4.0
	sphere.height = 8.0
	explosion.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.0, 1.0) # Solid color, no transparency bugs
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # Just pure color
	explosion.material_override = mat
	
	get_tree().root.add_child(explosion)
	explosion.global_position = global_position
	
	# Create a timer to brutally delete the node. No tweens. No animation bugs.
	var timer = Timer.new()
	timer.wait_time = 0.2
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(explosion.queue_free)
	explosion.add_child(timer)
	
	if is_net_replica:
		queue_free()
		return

	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = SphereShape3D.new()
	query.shape.radius = 4.0
	query.transform = global_transform
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var results = space_state.intersect_shape(query)
	
	for res in results:
		var collider = res.collider
		if collider.has_method("take_damage"):
			var dist = global_position.distance_to(collider.global_position)
			var dmg = lerp(120.0, 20.0, dist / 4.0)
			collider.take_damage(dmg, owner_name, "Grenade", attacker_faction)
			
	queue_free()
