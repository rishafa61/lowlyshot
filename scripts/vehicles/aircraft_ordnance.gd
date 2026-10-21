class_name AircraftOrdnance
extends RigidBody3D
## Aircraft ordnance: straight-flying missile or loose ballistic bomb.
## Explodes on first contact once armed. Built fully in code — no scene file.
## ponytail: no smoke trail / guidance — add a Node3D trail emitter when needed.

enum Mode { MISSILE, BOMB }

const MISSILE_SPEED := 130.0
const MISSILE_LIFETIME := 8.0
const BOMB_ARM_TIME := 0.35
const BOMB_LIFETIME := 15.0

var mode: Mode = Mode.MISSILE
var blast_radius: float = 8.0
var center_damage: float = 200.0
var outer_damage: float = 120.0
var weapon_label: String = "AGM-65"
var attacker_name: String = "Pilot"
var attacker_faction: String = "Player"
var source_body: PhysicsBody3D = null
var target_vehicle: Node3D = null
var turn_rate: float = 5.5
## Network replica: visual-only — damage already runs on the shooter's machine.
var is_net_replica: bool = false

var _armed := false
var _dir := Vector3.FORWARD
var _arm_time := 0.0
var _life := MISSILE_LIFETIME

## Static blast damage curve: full center damage inside half the radius,
## falloff to outer damage at the rim, nothing beyond. A bomb passes
## center == outer for flat damage in a bigger radius.
static func compute_blast_damage(dist: float, radius: float, center_dmg: float, outer_dmg: float) -> float:
	if dist >= radius:
		return 0.0
	if dist <= radius * 0.5:
		return center_dmg
	var t := (dist - radius * 0.5) / (radius * 0.5)
	return lerpf(center_dmg, outer_dmg, t)

static func spawn_missile(pos: Vector3, dir: Vector3, attacker: String, faction: String, source: PhysicsBody3D, locked_target: Node3D = null) -> AircraftOrdnance:
	var o := AircraftOrdnance.new()
	o.mode = Mode.MISSILE
	o.blast_radius = 8.0
	o.center_damage = 200.0
	o.outer_damage = 120.0
	o.weapon_label = "AGM-65"
	o._life = MISSILE_LIFETIME
	o._dir = dir.normalized()
	o._arm_time = 0.05
	o.target_vehicle = locked_target
	o._armed_setup(pos, attacker, faction, source)
	o.gravity_scale = 0.0
	o.linear_velocity = o._dir * MISSILE_SPEED
	var up := Vector3.FORWARD if absf(o._dir.dot(Vector3.UP)) > 0.95 else Vector3.UP
	o.basis = Basis.looking_at(o._dir, up)
	return o

static func spawn_bomb(pos: Vector3, inherit_velocity: Vector3, attacker: String, faction: String, source: PhysicsBody3D) -> AircraftOrdnance:
	var o := AircraftOrdnance.new()
	o.mode = Mode.BOMB
	o.blast_radius = 16.0 # 2x the missile blast
	o.center_damage = 300.0
	o.outer_damage = 300.0 # flat 300 inside the whole blast
	o.weapon_label = "MK-82"
	o._life = BOMB_LIFETIME
	o._arm_time = BOMB_ARM_TIME
	o._armed_setup(pos, attacker, faction, source)
	o.linear_velocity = inherit_velocity
	return o

func _armed_setup(pos: Vector3, attacker: String, faction: String, source: PhysicsBody3D) -> void:
	attacker_name = attacker
	attacker_faction = faction
	source_body = source
	position = pos # node not in tree yet; caller adds it to a root-level scene

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	collision_layer = 1
	collision_mask = 1
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	col.shape = shape
	add_child(col)
	add_child(_build_mesh())
	if source_body is PhysicsBody3D:
		add_collision_exception_with(source_body)
	body_entered.connect(_on_body_entered)
	# Incoming-missile warning: vehicles poll this group
	if mode == Mode.MISSILE and target_vehicle != null:
		add_to_group("homing_missile")

func _build_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	if mode == Mode.MISSILE:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.14
		cyl.bottom_radius = 0.14
		cyl.height = 1.8
		mat.albedo_color = Color(0.85, 0.85, 0.88)
		cyl.material = mat
		mi.mesh = cyl
		mi.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3.ZERO)
	else:
		var body := BoxMesh.new()
		body.size = Vector3(0.45, 0.45, 1.1)
		mat.albedo_color = Color(0.25, 0.28, 0.3)
		body.material = mat
		mi.mesh = body
	return mi

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		explode()
		return
	if not _armed:
		_arm_time -= delta
		if _arm_time <= 0.0:
			_armed = true
		return
	# High-speed sweep: detect collisions between last and current frame positions
	# Missile lock homing: steer velocity toward the locked vehicle (same
	# mechanism as the AT4 rocket); no lock = straight flight as usual.
	if mode == Mode.MISSILE and target_vehicle and is_instance_valid(target_vehicle) and target_vehicle.is_inside_tree():
		var t_pos: Vector3 = target_vehicle.global_position + Vector3(0, 0.8, 0)
		var desired := (t_pos - global_position).normalized()
		var cur := linear_velocity.normalized()
		cur = cur.lerp(desired, clampf(turn_rate * delta, 0.0, 1.0)).normalized()
		linear_velocity = cur * MISSILE_SPEED
		look_at(global_position + cur, Vector3.UP)
	var step := linear_velocity * delta
	if step.length_squared() > 0.01:
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			global_position, global_position + step, collision_mask, [get_rid()] + ([source_body.get_rid()] if source_body else []))
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			global_position = hit.position
			explode()
			return

func _on_body_entered(body: Node) -> void:
	if not _armed:
		return
	if source_body != null and body == source_body:
		return
	explode()

func explode() -> void:
	if not is_inside_tree():
		return
	# Replicas are visual-only: blast visuals, no damage (shooter-authoritative)
	if not is_net_replica:
		_blast(global_position, blast_radius, center_damage, outer_damage, weapon_label)
	else:
		_spawn_blast_visual(global_position, blast_radius)
	queue_free()

func _blast(pos: Vector3, radius: float, center_dmg: float, outer_dmg: float, label: String) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform = Transform3D(Basis(), pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit: Array = []
	for res in space.intersect_shape(query, 32):
		var collider = res.collider
		if collider == null or not (collider as Object).has_method("take_damage"):
			continue
		if collider in hit:
			continue
		hit.append(collider)
		var dist: float = pos.distance_to(collider.global_position)
		var dmg := compute_blast_damage(dist, radius, center_dmg, outer_dmg)
		if dmg > 0.0:
			collider.take_damage(dmg, attacker_name, label, attacker_faction, pos)
	_spawn_blast_visual(pos, radius)

func _spawn_blast_visual(pos: Vector3, radius: float) -> void:
	spawn_blast_visual(pos, radius)

## Shared explosion flash sphere + boom — used by missiles and vehicle deaths.
static func spawn_blast_visual(pos: Vector3, radius: float) -> void:
	var explosion := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	explosion.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.0, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	explosion.material_override = mat
	var root = Engine.get_main_loop().root
	root.add_child(explosion)
	explosion.position = pos
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(explosion.queue_free)
	explosion.add_child(timer)
	var sfx = root.get_node_or_null("Sfx")
	if sfx:
		sfx.oneshot3d("bomb", explosion, 40.0, 300.0, 6.0)
