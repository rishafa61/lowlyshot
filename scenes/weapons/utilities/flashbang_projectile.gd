extends RigidBody3D

var fuse: float = 2.0

func _physics_process(delta):
	fuse -= delta
	if fuse <= 0.0:
		explode()

func explode():
	print("FLASHBANG EXPLODED!")
	var space_state = get_world_3d().direct_space_state
	
	# Visual flash sphere
	var flash_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 6.0
	sphere.height = 12.0
	flash_mesh.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mesh.material_override = mat
	
	get_tree().root.add_child(flash_mesh)
	flash_mesh.global_position = global_position
	
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(flash_mesh.queue_free)
	flash_mesh.add_child(timer)
	
	# Blast radius stun
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = SphereShape3D.new()
	query.shape.radius = 12.0
	query.transform = global_transform
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var results = space_state.intersect_shape(query)
	
	for res in results:
		var collider = res.collider
		if collider.has_method("stun"):
			collider.stun(4.0)
		elif collider.has_method("take_damage"):
			collider.take_damage(5.0)
			
	queue_free()
