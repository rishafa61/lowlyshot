class_name GroundVehicleController
extends VehicleBody3D
## Reusable base for ground vehicles (cars, humvees, trucks, APCs).
## Handles multi-seat enter/exit, driving input, damage, HP, and destruction.
## Subclasses or scenes supply wheels, seats, and model.

signal pilot_entered(pilot: Node3D)
signal pilot_exited()
signal destroyed()

@export_group("Vehicle Stats")
@export var prompt_text: String = "Press F to Ride"
@export var max_hp: float = 500.0
@export var engine_power: float = 9000.0
@export var max_speed: float = 26.0 ## forward cap (~94 km/h)
@export var max_steer_deg: float = 34.0
@export var brake_power: float = 55.0
@export var vehicle_name: String = "Vehicle"

var hp: float
var is_destroyed := false
var seats: Array[Marker3D] = []
var occupants: Array = [] ## Node3D or null, index 0 is driver
var _prompt_player: Node3D = null
var _cam_yaw: float = 0.0
var _cam_pitch: float = -0.15
@export var mouse_sens: float = 0.004

@onready var interact_area: Area3D = get_node_or_null("InteractArea")
@onready var chase_pivot: Node3D = get_node_or_null("ChasePivot")
@onready var chase_arm: SpringArm3D = get_node_or_null("ChasePivot/ChaseArm")
@onready var chase_cam: Camera3D = get_node_or_null("ChasePivot/ChaseArm/ChaseCamera")

var _engine_sfx: AudioStreamPlayer3D = null

func _enter_tree() -> void:
	# Guard: wheels must enter the tree with identity basis — VehicleWheel3D
	# bakes its suspension axis from the transform at enter-tree time, and a
	# rotated basis points suspension sideways (no traction). Mesh children
	# keep their own rotation. Idempotent.
	for c in get_children():
		if c is VehicleWheel3D:
			(c as VehicleWheel3D).basis = Basis.IDENTITY

func _ready() -> void:
	hp = max_hp
	_setup_seats()
	if interact_area != null and (interact_area.collision_mask & 1) == 0:
		interact_area.collision_mask |= 1
	if interact_area != null:
		interact_area.body_entered.connect(_on_body_entered)
		interact_area.body_exited.connect(_on_body_exited)

func _setup_seats() -> void:
	var seats_node := get_node_or_null("Seats")
	if seats_node != null:
		for c in seats_node.get_children():
			if c is Marker3D:
				seats.append(c)
				occupants.append(null)
	if seats.is_empty():
		push_warning("%s: no Marker3D found under Seats node" % name)

func has_free_seat() -> bool:
	return occupants.has(null)

# --- Enter / exit ---

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or body.get("is_piloting") == true:
		return
	if not has_free_seat():
		return
	var hud = body.get("hud")
	if hud == null:
		return # remote puppet
	_prompt_player = body
	hud.show_hover_name(prompt_text, false)

func _on_body_exited(body: Node3D) -> void:
	if body == _prompt_player:
		_prompt_player = null
		if body.get("hud") != null:
			body.get("hud").hide_hover_name()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("vehicle_interact"):
		return
	# Enter if in trigger and not already piloting
	if _prompt_player != null and _prompt_player.get("is_piloting") != true and has_free_seat():
		_enter(_prompt_player)
		return
	# Any seated local player can exit with F
	for i in occupants.size():
		var occ = occupants[i]
		if occ != null and occ.get("hud") != null:
			_exit(i)
			return

func _input(event: InputEvent) -> void:
	# Local driver gets free-look camera while piloting
	var driver = occupants[0] if occupants.size() > 0 else null
	if driver == null or driver.get("hud") == null:
		return
	if event is InputEventMouseMotion:
		_cam_yaw -= event.relative.x * mouse_sens
		_cam_pitch = clampf(_cam_pitch - event.relative.y * mouse_sens, -0.6, 0.45)

func _enter(player: Node3D) -> void:
	var idx := occupants.find(null)
	if idx == -1 or is_destroyed:
		return
	occupants[idx] = player
	_prompt_player = null
	player.enter_aircraft(seats[idx])
	if chase_cam != null and idx == 0:
		chase_cam.current = true
		_cam_yaw = 0.0
		_cam_pitch = -0.15
		if chase_pivot != null:
			chase_pivot.rotation = Vector3.ZERO
		if chase_arm != null:
			chase_arm.rotation.x = -0.15
	pilot_entered.emit(player)
	_update_hud()

func _exit(idx: int) -> void:
	if idx < 0 or idx >= occupants.size() or occupants[idx] == null:
		return
	var player: Node3D = occupants[idx]
	occupants[idx] = null
	var side := 2.4 if seats[idx].position.x >= 0.0 else -2.4
	var exit_pos := seats[idx].global_position + global_basis * Vector3(side, 0.6, 0.0)
	var bail_vel := linear_velocity * 0.4
	player.exit_aircraft(exit_pos, -global_basis.z, bail_vel)
	pilot_exited.emit()
	if _prompt_player == null and interact_area != null and interact_area.get_overlapping_bodies().has(player):
		_on_body_entered(player)

# --- Driving (seat 0 only) ---

func _process(delta: float) -> void:
	if chase_pivot == null or chase_arm == null or chase_cam == null:
		return
	if not chase_cam.current:
		return
	# Q/E hold: snap camera to side views (Q = left side, E = right side)
	var target_yaw: float = _cam_yaw
	var target_pitch: float = _cam_pitch
	if Input.is_action_pressed("lean_left"): # Q
		target_yaw = -PI * 0.5
		target_pitch = -0.05
	elif Input.is_action_pressed("lean_right"): # E
		target_yaw = PI * 0.5
		target_pitch = -0.05
	var w: float = minf(delta * 8.0, 1.0)
	chase_pivot.rotation.y = lerp_angle(chase_pivot.rotation.y, target_yaw, w)
	chase_arm.rotation.x = lerp(chase_arm.rotation.x, target_pitch, w)

func _physics_process(delta: float) -> void:
	var driver = occupants[0] if occupants.size() > 0 else null
	var driving := driver != null and driver.get("is_dead") != true
	if driving:
		_drive_input(delta)
		if _engine_sfx == null:
			_engine_sfx = Sfx.loop3d("humvee", self, 8.0, 90.0, -4.0)
		if _engine_sfx:
			_engine_sfx.volume_db = lerpf(-14.0, 0.0, clampf(absf(engine_force) / engine_power, 0.0, 1.0))
	else:
		if _engine_sfx != null:
			Sfx.stop_loop(_engine_sfx)
			_engine_sfx = null
		engine_force = 0.0
		brake = brake_power if linear_velocity.length() > 0.3 else 0.0
		steering = move_toward(steering, 0.0, delta * 2.0)
	_update_hud()

func _drive_input(delta: float) -> void:
	var fwd_input := Input.get_axis("move_backward", "move_forward") # W / S
	var fwd_speed := linear_velocity.dot(-global_basis.z) # + = moving toward the front (-Z)
	if Input.is_action_pressed("jump"): # Space: handbrake
		engine_force = 0.0
		brake = brake_power
	elif fwd_input > 0.0:
		brake = 0.0
		var headroom := 1.0 - clampf(fwd_speed / max_speed, 0.0, 1.0)
		engine_force = -engine_power * fwd_input * headroom ## negative drives toward -Z (front)
	elif fwd_input < 0.0:
		if fwd_speed > 1.0:
			engine_force = 0.0
			brake = brake_power
		else:
			brake = 0.0
			engine_force = -engine_power * fwd_input * 0.5 ## S: reverse toward +Z
	else:
		engine_force = 0.0
		brake = 0.0
	var steer_input := Input.get_axis("move_left", "move_right") # A / D
	var steer_target := -steer_input * deg_to_rad(max_steer_deg)
	var steer_rate := 3.5 if absf(fwd_speed) < 8.0 else 1.8
	steering = move_toward(steering, steer_target, steer_rate * delta)

func _update_hud() -> void:
	var used := 0
	for o in occupants:
		if o != null: used += 1
	var free_seats := occupants.size() - used
	for occ in occupants:
		if occ == null:
			continue
		var hud = occ.get("hud")
		if hud != null and hud.has_method("update_aircraft_hud"):
			hud.update_aircraft_hud({
				"kind": "humvee",
				"name": vehicle_name,
				"speed": linear_velocity.length() * 3.6,
				"throttle": clampf(absf(engine_force) / maxf(engine_power, 1.0), 0.0, 1.0),
				"hp": hp,
				"max_hp": max_hp,
				"seats_free": free_seats,
				"seats_total": occupants.size(),
				"heat": 0.0,
				"overheated": false,
				"slot": -1,
				"missile_l": 0.0,
				"missile_r": 0.0,
				"bombs": 0,
				"flares": 0,
			})

# --- Damage / destruction ---

func take_damage(amount: float, _attacker_name: String = "", _weapon_name: String = "", _attacker_faction: String = "", _attacker_pos: Vector3 = Vector3.INF) -> float:
	if is_destroyed:
		return 0.0
	hp = maxf(hp - amount, 0.0)
	if hp <= 0.0:
		_explode()
	return amount

func _explode() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	if chase_cam != null:
		chase_cam.current = false
	for i in occupants.size():
		var occ = occupants[i]
		if occ == null:
			continue
		occupants[i] = null
		var side := 2.4 if seats[i].position.x >= 0.0 else -2.4
		var exit_pos := seats[i].global_position + global_basis * Vector3(side, 1.0, 0.0)
		occ.exit_aircraft(exit_pos, -global_basis.z, Vector3.UP * 6.0 + linear_velocity * 0.5)
		occ.take_damage(9999.0, vehicle_name, "Vehicle Explosion", "World", global_position)
	_blast_area(global_position, 12.0, 250.0, 60.0)
	destroyed.emit()
	queue_free()

func _blast_area(pos: Vector3, radius: float, center_dmg: float, outer_dmg: float) -> void:
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
		var dmg: float = AircraftOrdnance.compute_blast_damage(dist, radius, center_dmg, outer_dmg)
		if dmg > 0.0:
			collider.take_damage(dmg, vehicle_name, "Vehicle Explosion", "World", pos)
