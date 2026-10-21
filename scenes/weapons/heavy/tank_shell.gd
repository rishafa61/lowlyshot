extends Node3D
## Tank Cannon Shell (High Explosive / APFSDS projectile).
## Flies along forward vector, detonates on impact with fiery blast + screen shake + damage.

@export var speed: float = 120.0
@export var direct_damage: float = 650.0
@export var blast_damage: float = 400.0
@export var blast_radius: float = 11.0
@export var lifetime: float = 6.0
@export var gravity_drop: float = 9.8

var shooter_name: String = "Tank"
var shooter_faction: String = "Player"
var direction: Vector3 = Vector3.FORWARD:
	set(v):
		direction = v
		if is_inside_tree():
			velocity = direction.normalized() * speed # late set (post-_ready) still re-aims
var velocity: Vector3 = Vector3.ZERO
var is_net_replica: bool = false
var source_tank: Node = null

var _life: float = 0.0
var _exploded: bool = false

func _ready() -> void:
	if direction == Vector3.ZERO:
		direction = -global_transform.basis.z.normalized()
	velocity = direction.normalized() * speed

func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_life += delta
	if _life >= lifetime:
		explode(global_position)
		return

	# Apply slight gravity arc for realistic tank ballistics
	velocity.y -= gravity_drop * delta
	var step := velocity * delta
	var move_dist := step.length()
	if move_dist < 0.001:
		return

	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
	ray.collide_with_areas = true
	ray.collide_with_bodies = true
	var excludes: Array[RID] = []
	if source_tank and is_instance_valid(source_tank) and source_tank is CollisionObject3D:
		excludes.append(source_tank.get_rid())
	ray.exclude = excludes

	var hit := space.intersect_ray(ray)
	if hit:
		global_position = hit.position
		explode(hit.position, hit.collider)
	else:
		global_position += step
		if velocity.length_squared() > 1.0:
			look_at(global_position + velocity, Vector3.UP)

func explode(pos: Vector3, direct_hit: Object = null) -> void:
	if _exploded:
		return
	_exploded = true
	set_physics_process(false)

	if not is_net_replica:
		if direct_hit and is_instance_valid(direct_hit):
			var target = direct_hit
			if not target.has_method("take_damage") and target.get_parent() and target.get_parent().has_method("take_damage"):
				target = target.get_parent()
			if target.has_method("take_damage"):
				target.take_damage(direct_damage, shooter_name, "120mm Smoothbore", shooter_faction, pos)
		_blast_area(pos)

	_spawn_visuals(pos)
	queue_free()

func _blast_area(pos: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = blast_radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var results := space.intersect_shape(query, 32)
	var damaged: Array = []
	for res in results:
		var c = res.collider
		if not c or not is_instance_valid(c):
			continue
		var target = c
		if not target.has_method("take_damage") and target.get_parent() and target.get_parent().has_method("take_damage"):
			target = target.get_parent()
		if target in damaged or not target.has_method("take_damage"):
			continue
		damaged.append(target)
		var dist := pos.distance_to(target.global_position)
		var falloff := clampf(1.0 - (dist / blast_radius), 0.15, 1.0)
		target.take_damage(blast_damage * falloff, shooter_name, "120mm Smoothbore", shooter_faction, pos)

func _spawn_visuals(pos: Vector3) -> void:
	var root := get_tree().current_scene if get_tree().current_scene else get_tree().root
	var sfx_node := Node3D.new()
	root.add_child(sfx_node)
	sfx_node.global_position = pos
	Sfx.oneshot3d("bomb", sfx_node, 30.0, 240.0, 4.5)
	sfx_node.create_tween().tween_interval(3.0).finished.connect(sfx_node.queue_free)

	# Blast fireball
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.6
	sm.height = 3.2
	sphere.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.12)
	mat.emission_energy_multiplier = 4.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material_override = mat
	root.add_child(sphere)
	sphere.global_position = pos

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 6.0
	light.omni_range = blast_radius * 1.8
	sphere.add_child(light)

	var t := sphere.create_tween()
	t.set_parallel(true)
	t.tween_property(sphere, "scale", Vector3(blast_radius * 0.75, blast_radius * 0.75, blast_radius * 0.75), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.3).set_delay(0.08)
	t.tween_property(light, "light_energy", 0.0, 0.3)
	t.chain().tween_callback(sphere.queue_free)
