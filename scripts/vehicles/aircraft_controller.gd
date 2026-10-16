extends RigidBody3D
## Reusable piloted aircraft controller — arcade flight model + weapons.
## Scene contract (node paths must match): PilotSeat (Marker3D),
## ChasePivot/ChaseArm (SpringArm3D)/ChaseCamera (Camera3D), InteractArea (Area3D),
## Model/GAU8_Cannon (MeshInstance3D muzzle).
## The pilot node must implement enter_aircraft(seat) / exit_aircraft(pos, dir, eject_vel)
## and expose team/player_name/hud (the player CharacterBody3D does).
## Reuse for other aircraft by swapping the Model meshes and exporting different values.
## ponytail: no netcode / engine audio / collision-impact damage — hook via signals.

signal pilot_entered(pilot: Node3D)
signal pilot_exited
signal destroyed

# --- Flight tuning (exported so other aircraft can rebalance) ---
@export var aircraft_name: String = "A-10"
@export var max_thrust: float = 38.0    ## forward accel (m/s^2) at 100% throttle
@export var stall_speed: float = 18.0   ## forward speed at which lift fully cancels gravity
@export var lift_boost: float = 1.06    ## slight surplus so takeoff needs a long ground roll
@export var align_rate: float = 2.2     ## how fast velocity steers toward the nose
@export var drag_linear: float = 0.05   ## air resistance, proportional term
@export var drag_quad: float = 0.002    ## air resistance, quadratic term (low = fast top speed)
@export var pitch_rate: float = 1.6     ## rad/s cap from mouse
@export var yaw_rate: float = 0.8
@export var roll_rate: float = 2.4
@export var agility: float = 5.0        ## angular response speed
@export var mouse_sens: float = 0.006
@export var exit_max_speed: float = 3.0 ## walk-out threshold (m/s); faster = eject
@export var prompt_text: String = "Press F to Pilot"

# --- Loadout tuning ---
@export var max_hp: float = 500.0
const GATLING_DMG := 20.0
const GATLING_RATE := 0.125      ## 8 rounds/s
const GATLING_RANGE := 500.0
const GATLING_SPREAD := 0.004
const HEAT_PER_SHOT := 2.0       ## 8/s * 2 = ~6s hold to reach the peak
const HEAT_COOL_RATE := 25.0
const HEAT_OVERHEAT_RESUME := 35.0
const OVERHEAT_LOCK := 3.0
const MISSILE_CD := 4.0          ## per-wing cooldown, alternating fire
const BOMB_START := 8
const FLARE_START := 3
const FLARE_COUNT := 24          ## particles per burst

enum OrdnanceSlot { GATLING, MISSILE, BOMB, FLARE }

const GRAVITY := 9.8
const THROTTLE_RATE := 0.45     ## W / S throttle change per second
const THROTTLE_FAST := 1.2      ## Shift multiplier
const BRAKE_RATE := 1.5         ## Space: cut throttle fast
const GROUND_FRICTION := 0.4    ## rolling resistance
const GROUND_BRAKE := 2.5       ## Space while grounded
const GROUND_RAY := 2.4         ## ground proximity for "landed" state
const PILOTLESS_CUTOFF_DELAY := 0.8 ## seconds after eject before thrust dies
const ENGINE_SPOOL_DOWN := 1.5    ## throttle drain per sec (full 100%->0% in 0.67s)

var throttle: float = 0.0
var _pilotless_time: float = 0.0
var _is_ejected: bool = false
var _last_ejected_pilot: Node3D = null
var active_pilot: Node3D = null
var hp: float = 500.0
var is_destroyed: bool = false

# Weapon state
var selected_slot: int = OrdnanceSlot.GATLING
var heat: float = 0.0
var overheated := false
var overheat_left := 0.0
var gatling_cd := 0.0
var missile_cd: Array[float] = [0.0, 0.0] # [left wing (LMB), right wing (RMB)]
var bombs := BOMB_START
var flares := FLARE_START

var _prompt_player: Node3D = null
var _pitch_vel: float = 0.0
var _yaw_vel: float = 0.0
var _flash_text: String = ""
var _flash_timer: float = 0.0
var _engine_sfx: AudioStreamPlayer3D = null
var _pilot_name: String = "Pilot"
var _pilot_faction: String = "Player"

@onready var pilot_seat: Marker3D = $PilotSeat
@onready var chase_arm: SpringArm3D = $ChasePivot/ChaseArm
@onready var chase_cam: Camera3D = $ChasePivot/ChaseArm/ChaseCamera
@onready var interact_area: Area3D = $InteractArea
@onready var muzzle: Node3D = $Model/GAU8_Cannon

func _ready() -> void:
	gravity_scale = 0.0 # gravity is applied manually so lift can counteract it
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_impact)
	hp = max_hp
	chase_arm.add_excluded_object(get_rid())
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)

# --- Pure math (unit-tested in tests/test_aircraft_physics.gd) ---

static func compute_lift_ratio(fwd_speed: float, stall: float) -> float:
	return clampf(fwd_speed / maxf(stall, 0.1), 0.0, 1.0)

static func compute_drag(lin: float, quad: float, speed: float) -> float:
	return lin + quad * speed

static func compute_heat(current: float, per_shot: float) -> float:
	return clampf(current + per_shot, 0.0, 100.0)

func can_walk_out() -> bool:
	return linear_velocity.length() <= exit_max_speed and _is_grounded()

# --- Input (only processed while a pilot is seated) ---

func _unhandled_input(event: InputEvent) -> void:
	if active_pilot == null:
		return
	var hud = active_pilot.get("hud")
	if hud and hud.console_visible:
		return # developer console owns the keyboard
	if event is InputEventMouseMotion:
		_yaw_vel = clampf(_yaw_vel - event.relative.x * mouse_sens, -yaw_rate, yaw_rate)
		_pitch_vel = clampf(_pitch_vel + event.relative.y * mouse_sens, -pitch_rate, pitch_rate) # inverted: mouse up = nose down
	elif event.is_action_pressed("vehicle_interact"):
		_try_exit()
	elif event.is_action_pressed("weapon_1"):
		_select_slot(OrdnanceSlot.GATLING)
	elif event.is_action_pressed("weapon_2"):
		_select_slot(OrdnanceSlot.MISSILE)
	elif event.is_action_pressed("weapon_3"):
		_select_slot(OrdnanceSlot.BOMB)
	elif event.is_action_pressed("weapon_4"):
		_select_slot(OrdnanceSlot.FLARE)
		_launch_flare() # flares fire on the keypress, no click needed

func _select_slot(slot: int) -> void:
	selected_slot = slot

func _physics_process(delta: float) -> void:
	_flash_timer = maxf(0.0, _flash_timer - delta)
	if active_pilot == null and _prompt_player != null \
			and Input.is_action_just_pressed("vehicle_interact"):
		_enter(_prompt_player)
	var grounded := _is_grounded()
	# Engine audio: audible while spooled (pilot aboard or throttle winding down);
	# volume tracks throttle so distant/idle planes are quieter.
	if throttle > 0.02 or active_pilot != null:
		if _engine_sfx == null:
			_engine_sfx = Sfx.loop3d("jet", self, 15.0, 150.0, 2.0)
		if _engine_sfx:
			_engine_sfx.volume_db = lerpf(-24.0, 2.0, throttle)
	elif _engine_sfx != null:
		Sfx.stop_loop(_engine_sfx)
		_engine_sfx = null
	if active_pilot != null:
		_pilotless_time = 0.0
		_update_throttle(delta)
		_process_weapons(delta)
	elif _is_ejected:
		# Unmanned after eject: fast power drain, nose dive, explodes on impact
		_pilotless_time += delta
		if _pilotless_time > PILOTLESS_CUTOFF_DELAY:
			throttle = maxf(throttle - ENGINE_SPOOL_DOWN * delta, 0.0)
			if grounded:
				_explode()
				return
	_apply_forces(delta, grounded)
	_apply_rotation(delta, grounded)
	_update_pilot_hud()

func _console_open() -> bool:
	var hud = active_pilot.get("hud") if active_pilot != null else null
	return hud != null and hud.console_visible

# --- Enter / exit / eject ---

func _on_body_entered(body: Node3D) -> void:
	if active_pilot != null or not body.is_in_group("player") or bool(body.get("is_piloting")):
		return
	var hud = body.get("hud")
	if hud == null:
		return # remote puppet
	_prompt_player = body
	hud.show_hover_name(prompt_text, false)

func _on_body_exited(body: Node3D) -> void:
	if body == _prompt_player:
		_prompt_player = null
		if active_pilot == null:
			body.get("hud").hide_hover_name()

func _enter(pilot: Node3D) -> void:
	if active_pilot != null:
		return
	active_pilot = pilot
	_is_ejected = false
	_pilotless_time = 0.0
	_last_ejected_pilot = null
	_prompt_player = null
	_pitch_vel = 0.0
	_yaw_vel = 0.0
	_pilot_name = str(pilot.get("player_name")) if pilot.get("player_name") != null else "Pilot"
	var team = str(pilot.get("team"))
	_pilot_faction = "Ally" if team == "attackers" else "Enemy"
	pilot.enter_aircraft(pilot_seat)
	chase_cam.current = true
	pilot_entered.emit(pilot)

func _try_exit() -> void:
	var pilot := active_pilot
	active_pilot = null
	chase_cam.current = false # player.exit_aircraft restores the player camera
	if can_walk_out():
		_is_ejected = false
		var dir := -global_basis.z
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
		pilot.exit_aircraft(_exit_position(), dir)
		pilot_exited.emit()
		# Pilot often steps out still inside the trigger: re-arm the prompt.
		if interact_area.get_overlapping_bodies().has(pilot):
			_on_body_entered(pilot)
	else:
		# Airborne / too fast: eject. Fling the pilot clear; the plane loses
		# power rapidly and dives into the ground until destroyed.
		_is_ejected = true
		_last_ejected_pilot = pilot
		_pilotless_time = 0.0
		var exit_pos := global_position + global_basis * Vector3(0.0, 3.5, 0.0)
		var eject_vel := linear_velocity * 0.5 + Vector3.UP * 8.0
		pilot.exit_aircraft(exit_pos, -global_basis.z, eject_vel)
		pilot_exited.emit()

func _exit_position() -> Vector3:
	return global_position + global_basis * Vector3(-3.5, 1.0, 0.0)

# --- Flight model ---

func _update_throttle(delta: float) -> void:
	var rate := THROTTLE_RATE
	if Input.is_action_pressed("sprint"): # Shift: throttle up fast
		rate = THROTTLE_FAST
	if Input.is_action_pressed("move_forward"): # W
		throttle += rate * delta
	elif Input.is_action_pressed("move_backward"): # S
		throttle -= rate * delta
	if Input.is_action_pressed("jump"): # Space: brake / cut power
		throttle -= BRAKE_RATE * delta
	throttle = clampf(throttle, 0.0, 1.0)

func _apply_forces(delta: float, grounded: bool) -> void:
	var forward := -global_basis.z
	var speed := linear_velocity.length()
	var fwd_speed := linear_velocity.dot(forward)
	# Thrust
	apply_central_force(forward * max_thrust * throttle * mass)
	# Gravity (gravity_scale = 0, applied manually)
	var grav_mult := 1.8 if (_is_ejected and _pilotless_time > PILOTLESS_CUTOFF_DELAY) else 1.0
	apply_central_force(Vector3.DOWN * GRAVITY * grav_mult * mass)
	# Lift along the airframe's up: climbs when the nose rises, bleeds in banks
	var lift_mult := 1.0
	if _is_ejected and _pilotless_time > PILOTLESS_CUTOFF_DELAY:
		lift_mult = maxf(0.0, 1.0 - (_pilotless_time - PILOTLESS_CUTOFF_DELAY) * 2.5)
	var lift := compute_lift_ratio(fwd_speed, stall_speed) * lift_boost * lift_mult
	apply_central_force(global_basis.y * GRAVITY * lift * mass)
	# Drag / air resistance
	apply_central_force(-linear_velocity * compute_drag(drag_linear, drag_quad, speed) * mass)
	# Steer velocity toward the nose: smooth arcs, no instant direction snaps.
	# Authority grows with airspeed — a slow plane can't yank itself around.
	if not grounded and speed > 1.0:
		var authority := compute_lift_ratio(speed, stall_speed * 1.5)
		linear_velocity = linear_velocity.lerp(forward * speed, 1.0 - exp(-align_rate * authority * delta))
	# Ground rolling friction / wheel brakes
	if grounded:
		var braking := active_pilot != null and Input.is_action_pressed("jump")
		var f := GROUND_BRAKE if braking else GROUND_FRICTION
		var horiz := Vector3(linear_velocity.x, 0.0, linear_velocity.z) * exp(-f * delta)
		linear_velocity.x = horiz.x
		linear_velocity.z = horiz.z

func _apply_rotation(delta: float, grounded: bool) -> void:
	if active_pilot == null:
		if _is_ejected and _pilotless_time > PILOTLESS_CUTOFF_DELAY:
			# Lost power: heavy engine nose pitches down into a dive
			var dive_torque := -global_basis.x * (pitch_rate * 1.5)
			angular_velocity = angular_velocity.lerp(dive_torque, 1.0 - exp(-3.0 * delta))
		else:
			angular_velocity = angular_velocity.lerp(Vector3.ZERO, 1.0 - exp(-2.0 * delta))
		return
	var local_target: Vector3
	var ground_taxi := grounded and linear_velocity.length() < stall_speed * 0.6
	if ground_taxi:
		# Slow taxi: nose-wheel steering + keep the airframe level.
		# Above taxi speed the pitch path takes over so the pilot can
		# rotate the nose and lift off.
		local_target = Vector3(0.0, _yaw_vel * 0.6, 0.0)
		var fwd := -global_basis.z
		fwd.y = 0.0
		if fwd.length() > 0.2:
			var level := Basis.looking_at(fwd.normalized(), Vector3.UP)
			global_transform.basis = global_transform.basis.slerp(level, 1.0 - exp(-4.0 * delta)).orthonormalized()
	else:
		# Mouse rates decay toward zero for smooth stops (no snapping)
		_pitch_vel = move_toward(_pitch_vel, 0.0, pitch_rate * 2.5 * delta)
		_yaw_vel = move_toward(_yaw_vel, 0.0, yaw_rate * 2.5 * delta)
		var roll_input := Input.get_axis("move_left", "move_right") # A / D roll
		local_target = Vector3(_pitch_vel, _yaw_vel, -roll_input * roll_rate)
	angular_velocity = angular_velocity.lerp(global_basis * local_target, 1.0 - exp(-agility * delta))

func _is_grounded() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * GROUND_RAY, collision_mask, [get_rid()])
	return not space.intersect_ray(query).is_empty()

# --- Weapons ---

func _process_weapons(delta: float) -> void:
	gatling_cd = maxf(gatling_cd - delta, 0.0)
	missile_cd[0] = maxf(missile_cd[0] - delta, 0.0)
	missile_cd[1] = maxf(missile_cd[1] - delta, 0.0)
	if _console_open():
		return
	if overheated:
		overheat_left -= delta
		if overheat_left <= 0.0:
			overheated = false
			heat = HEAT_OVERHEAT_RESUME
	else:
		var firing := selected_slot == OrdnanceSlot.GATLING and Input.is_action_pressed("fire")
		if firing and gatling_cd <= 0.0:
			_fire_gatling()
			gatling_cd = GATLING_RATE
		if not firing:
			heat = maxf(heat - HEAT_COOL_RATE * delta, 0.0)
	if selected_slot == OrdnanceSlot.MISSILE:
		if Input.is_action_just_pressed("fire"): # LMB = Left missile
			_fire_missile(0)
		if Input.is_action_just_pressed("aim"): # RMB = Right missile
			_fire_missile(1)
	elif selected_slot == OrdnanceSlot.BOMB and Input.is_action_just_pressed("fire"):
		_drop_bomb()

func _fire_gatling() -> void:
	if overheated or chase_cam == null:
		return
	heat = compute_heat(heat, HEAT_PER_SHOT)
	if heat >= 100.0:
		overheated = true
		overheat_left = OVERHEAT_LOCK
	var cam_xf := chase_cam.global_transform
	var dir := (-cam_xf.basis.z + cam_xf.basis.x * randf_range(-GATLING_SPREAD, GATLING_SPREAD) \
			+ cam_xf.basis.y * randf_range(-GATLING_SPREAD, GATLING_SPREAD)).normalized()
	var end := cam_xf.origin + dir * GATLING_RANGE
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(cam_xf.origin, end, ~0, [get_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	var hit_pos := end
	if hit:
		hit_pos = hit.position
		var target = hit.collider
		if target != self and (target as Object).has_method("take_damage"):
			target.take_damage(GATLING_DMG, _pilot_name, "GAU-8", _pilot_faction, hit_pos)
			var hud = active_pilot.get("hud")
			if hud and target.is_in_group("enemy"):
				hud.show_hit_marker(GATLING_DMG)
		_spawn_spark(hit_pos, hit.normal)
	var start := muzzle.global_position + global_basis * Vector3(0, 0, -1.0)
	Sfx.pool_fire3d("rifle_single", self, 18.0, 160.0, 3.0)
	if active_pilot != null and active_pilot.has_method("create_tracer"):
		active_pilot.create_tracer(start, hit_pos, 0.14) # fat tracer: visible at 100+ m/s

func _spawn_spark(pos: Vector3, normal: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.25
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = normal if normal.length_squared() > 0.1 else Vector3.UP
	p.spread = 45.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 14.0
	p.gravity = Vector3(0, -18.0, 0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.1)
	mat.emission_energy_multiplier = 5.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(p.queue_free)

func _fire_missile(side: int) -> void:
	# side 0 = left wing (LMB), 1 = right wing (RMB); independent cooldowns
	if missile_cd[side] > 0.0:
		_flash_text = "AGM %s RELOADING" % ("LEFT" if side == 0 else "RIGHT")
		_flash_timer = 1.0
		return
	missile_cd[side] = MISSILE_CD
	var local := Vector3(-5.0 if side == 0 else 5.0, 0.35, -0.3)
	var pos := global_position + global_basis * local
	var target := chase_cam.global_position - chase_cam.global_basis.z * 300.0
	var dir := (target - pos).normalized()
	var missile := AircraftOrdnance.spawn_missile(pos, dir, _pilot_name, _pilot_faction, self)
	get_tree().current_scene.add_child(missile)
	Sfx.oneshot3d("missile", self, 20.0, 180.0, 3.0)

func _drop_bomb() -> void:
	if bombs <= 0:
		_flash_text = "NO BOMBS"
		_flash_timer = 1.0
		return
	bombs -= 1
	var pos := global_position + global_basis * Vector3(0.0, -1.4, 0.0)
	var bomb := AircraftOrdnance.spawn_bomb(pos, linear_velocity * 0.9, _pilot_name, _pilot_faction, self)
	get_tree().current_scene.add_child(bomb)
	Sfx.oneshot3d("bomb", self, 20.0, 160.0, 3.0)

func _launch_flare() -> void:
	if flares <= 0:
		_flash_text = "NO FLARES"
		_flash_timer = 1.0
		return
	flares -= 1
	var back := global_basis * Vector3(0.0, 1.0, 6.0)
	var p := CPUParticles3D.new()
	p.amount = FLARE_COUNT
	p.lifetime = 2.4
	p.explosiveness = 0.95
	p.one_shot = true
	p.direction = global_basis * Vector3(0, 0, 1) # out the tail
	p.spread = 30.0
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 40.0
	p.gravity = Vector3(0, -12.0, 0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.25, 0.25, 0.25)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.15)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh # CPUParticles3D uses `mesh` (draw_pass_1 is GPUParticles3D only)
	get_tree().current_scene.add_child(p)
	p.global_position = global_position + back
	p.emitting = true
	var t := get_tree().create_timer(3.0)
	t.timeout.connect(p.queue_free)

# --- Damage / destruction ---

func take_damage(amount: float, _attacker_name: String = "", _weapon_name: String = "", _attacker_faction: String = "", _attacker_pos: Vector3 = Vector3.INF) -> float:
	if is_destroyed:
		return 0.0
	hp = maxf(hp - amount, 0.0)
	if hp <= 0.0:
		_explode()
	return amount

func _explode() -> void:
	Sfx.stop_loop(_engine_sfx)
	_engine_sfx = null
	if is_destroyed:
		return
	is_destroyed = true
	var pilot := active_pilot
	active_pilot = null
	chase_cam.current = false
	if pilot != null:
		# Pilot still seated: thrown from the wreck and killed by the blast.
		# Ejected pilots are already clear and take none of this.
		var fwd := -global_basis.z
		pilot.exit_aircraft(global_position + Vector3.UP * 2.0, fwd)
		pilot.take_damage(9999.0, "Aircraft", "Crash", "World", global_position)
	_blast_area(global_position, 18.0, 300.0, 60.0)
	_spawn_blast_visual(global_position, 18.0)
	destroyed.emit()
	queue_free()

func _on_impact(body: Node) -> void:
	if is_destroyed:
		return
	if body == active_pilot or body == _last_ejected_pilot:
		return
	if _is_ejected and _pilotless_time > 0.3:
		_explode()
		return
	if active_pilot != null:
		var speed := linear_velocity.length()
		var forward := -global_basis.z
		if (speed > 18.0 and forward.dot(Vector3.DOWN) > 0.35) or speed > 35.0:
			_explode()

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
		if collider in hit or collider == _last_ejected_pilot:
			continue
		hit.append(collider)
		var dist: float = pos.distance_to(collider.global_position)
		var dmg := AircraftOrdnance.compute_blast_damage(dist, radius, center_dmg, outer_dmg)
		if dmg > 0.0:
			collider.take_damage(dmg, _pilot_name, "Aircraft Explosion", _pilot_faction, pos)

func _spawn_blast_visual(pos: Vector3, radius: float) -> void:
	var explosion := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	explosion.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.0, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	explosion.material_override = mat
	get_tree().root.add_child(explosion)
	explosion.global_position = pos
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(explosion.queue_free)
	explosion.add_child(timer)

# --- HUD ---

func _update_pilot_hud() -> void:
	if active_pilot == null:
		return
	var hud = active_pilot.get("hud")
	if hud == null:
		return
	if _flash_timer > 0.0:
		hud.show_hover_name(_flash_text, false)
	elif not overheated:
		hud.hide_hover_name()
	hud.update_aircraft_hud({
		"throttle": throttle,
		"speed": linear_velocity.length(),
		"hp": hp,
		"max_hp": max_hp,
		"slot": selected_slot,
		"heat": heat,
		"overheated": overheated,
		"missile_l": missile_cd[0],
		"missile_r": missile_cd[1],
		"bombs": bombs,
		"flares": flares,
	})
