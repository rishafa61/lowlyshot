extends Node3D
## AT4 Guided / Unguided Rocket.
## Flies straight along forward vector if no lock; steers toward target_vehicle if locked.
## Explodes on impact with a fiery blast sphere and blast damage.

@export var speed: float = 65.0
@export var turn_rate: float = 4.5
@export var direct_damage: float = 450.0
@export var blast_damage: float = 300.0
@export var blast_radius: float = 10.0
@export var lifetime: float = 8.0

var target_vehicle: Node3D = null
var shooter_name: String = "Player"
var shooter_faction: String = "Player"
var direction: Vector3 = Vector3.FORWARD
var _life: float = 0.0
var _exploded: bool = false

func _ready() -> void:
	direction = -global_transform.basis.z.normalized()

func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_life += delta
	if _life >= lifetime:
		explode(global_position)
		return

	# Homing steering toward locked vehicle
	if target_vehicle and is_instance_valid(target_vehicle):
		var target_pos: Vector3 = target_vehicle.global_position
		# Aim at vehicle center (not ground wheels)
		target_pos.y += 0.8
		var desired := (target_pos - global_position).normalized()
		direction = direction.slerp(desired, clampf(turn_rate * delta, 0.0, 1.0)).normalized()
		look_at(global_position + direction, Vector3.UP)

	var move_dist := speed * delta
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(global_position, global_position + direction * (move_dist + 0.3))
	ray.collide_with_areas = true
	ray.collide_with_bodies = true
	var hit := space.intersect_ray(ray)
	if hit:
		global_position = hit.position
		explode(hit.position, hit.collider)
	else:
		global_position += direction * move_dist

func explode(pos: Vector3, direct_hit: Object = null) -> void:
	if _exploded:
		return
	_exploded = true
	set_physics_process(false)

	# Direct hit damage
	if direct_hit and is_instance_valid(direct_hit):
		var target = direct_hit
		if not target.has_method("take_damage") and target.get_parent() and target.get_parent().has_method("take_damage"):
			target = target.get_parent()
		if target.has_method("take_damage"):
			target.take_damage(direct_damage, shooter_name, "AT4 Rocket", shooter_faction, pos)

	# Blast area damage
	_blast_area(pos)

	# Visual quick explosive sphere
	_spawn_explosion_visual(pos)
	var sfx_node := Node3D.new()
	var root := get_tree().current_scene if get_tree().current_scene else get_tree().root
	root.add_child(sfx_node)
	sfx_node.global_position = pos
	Sfx.oneshot3d("bomb", sfx_node, 25.0, 200.0, 4.0)
	sfx_node.create_tween().tween_interval(3.0).finished.connect(sfx_node.queue_free)

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
		var falloff := clampf(1.0 - (dist / blast_radius), 0.1, 1.0)
		target.take_damage(blast_damage * falloff, shooter_name, "AT4 Rocket", shooter_faction, pos)

func _spawn_explosion_visual(pos: Vector3) -> void:
	var root := get_tree().current_scene if get_tree().current_scene else get_tree().root
	var sphere := MeshInstance3D.new()
	var s_mesh := SphereMesh.new()
	s_mesh.radius = 1.2
	s_mesh.height = 2.4
	sphere.mesh = s_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material_override = mat
	root.add_child(sphere)
	sphere.global_position = pos

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 5.0
	light.omni_range = blast_radius * 1.5
	sphere.add_child(light)

	var t := sphere.create_tween()
	t.set_parallel(true)
	t.tween_property(sphere, "scale", Vector3(blast_radius * 0.7, blast_radius * 0.7, blast_radius * 0.7), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.25).set_delay(0.08)
	t.tween_property(light, "light_energy", 0.0, 0.25)
	t.chain().tween_callback(sphere.queue_free)
