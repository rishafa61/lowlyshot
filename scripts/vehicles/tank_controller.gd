class_name TankController
extends CharacterBody3D
## M1 Abrams Main Battle Tank controller.
## Supports 2 seats:
##  Seat 0 (Driver): Drives the tank, steers, handbrakes, aims & fires main 120mm cannon.
##  Seat 1 (Turret/Gunner): Operates the independent turret rotation/aiming & free-orbit hover camera.
## Rigid/arcade movement grounded on terrain, independent turret yaw/pitch, multiplayer replication.

signal pilot_entered(pilot: Node3D)
signal pilot_exited()
signal destroyed()

@export_group("Tank Stats")
@export var prompt_text: String = "Press F to Enter Tank"
@export var vehicle_name: String = "M1 Abrams"
@export var max_hp: float = 1200.0
@export var max_speed: float = 16.0       ## Forward top speed (~58 km/h)
@export var reverse_speed: float = 7.0    ## Reverse speed (~25 km/h)
@export var acceleration: float = 14.0    ## Forward m/s^2
@export var turn_speed: float = 1.35      ## Hull yaw rate rad/s
@export var brake_power: float = 24.0     ## Decel m/s^2
@export var gravity: float = 18.0

@export_group("Turret & Cannon")
@export var turret_turn_speed: float = 2.0  ## Max turret traverse rad/s
@export var cannon_pitch_speed: float = 1.5 ## Max elevation rad/s
@export var cannon_min_pitch: float = -0.16 ## ~ -9 deg elevation limit
@export var cannon_max_pitch: float = 0.35  ## ~ +20 deg elevation limit
@export var reload_time: float = 3.5        ## Reload delay between shots
@export var mouse_sens: float = 0.003

# Commander M2 cupola gun (seat 1) — same heat attributes as the aircraft GAU-8
const MG_DMG := 20.0
const MG_RATE := 0.125            ## 8 rounds/s
const MG_RANGE := 500.0
const MG_SPREAD := 0.004
const MG_HEAT_PER_SHOT := 2.0     ## ~6s hold to reach the peak
const MG_HEAT_COOL_RATE := 25.0
const MG_OVERHEAT_RESUME := 35.0
const MG_OVERHEAT_LOCK := 3.0

var hp: float
var is_destroyed := false
var seats: Array[Marker3D] = []
var occupants: Array = [] ## Index 0 = Driver, Index 1 = Turret Gunner
var _prompt_player: Node3D = null

# Aiming state (turret yaw is hull-relative rad, cannon pitch is rad)
var turret_yaw: float = 0.0
var cannon_pitch: float = 0.0
var _target_turret_yaw: float = 0.0
var _target_cannon_pitch: float = 0.0

# Commander cupola aiming state (seat 1 only — relative to turret)
var hatch_yaw: float = 0.0
var hatch_pitch: float = 0.0
var _target_hatch_yaw: float = 0.0
var _target_hatch_pitch: float = 0.0

# Cupola Gatling / Machine Gun heat state (seat 1)
var mg_heat: float = 0.0
var mg_overheated := false
var mg_overheat_left := 0.0
var mg_cd := 0.0

# Free-orbit camera angles for driver (seat 0)
var _cam_yaw: float = 0.0
var _cam_pitch: float = -0.18

# Weapon state
var reload_timer: float = 0.0

# Track animation simulation
var left_track_offset: float = 0.0
var right_track_offset: float = 0.0

# Network puppet state
var _net_puppet := false
var _net_target_pos := Vector3.ZERO
var _net_target_quat := Quaternion.IDENTITY
var _net_target_vel := Vector3.ZERO
var _net_target_turret_yaw: float = 0.0
var _net_target_cannon_pitch: float = 0.0
var _net_send_timer := 0.0
var _net_aim_timer := 0

var _last_hit_by: String = ""
var _last_hit_faction: String = ""
var _engine_sfx: AudioStreamPlayer3D = null

@onready var interact_area: Area3D = get_node_or_null("InteractArea")
@onready var turret_node: Node3D = get_node_or_null("Model/Turret")
@onready var barrel_node: Node3D = get_node_or_null("Model/Turret/BarrelPivot")
@onready var muzzle_node: Node3D = get_node_or_null("Model/Turret/BarrelPivot/Muzzle")
@onready var muzzle_flash: OmniLight3D = get_node_or_null("Model/Turret/BarrelPivot/Muzzle/MuzzleFlash")
@onready var chase_pivot: Node3D = get_node_or_null("ChasePivot")
@onready var chase_arm: SpringArm3D = get_node_or_null("ChasePivot/ChaseArm")
@onready var chase_cam: Camera3D = get_node_or_null("ChasePivot/ChaseArm/ChaseCamera")
@onready var commander_hatch: Node3D = get_node_or_null("Model/Turret/CommanderHatch")
@onready var gunner_cam: Camera3D = get_node_or_null("Model/Turret/CommanderHatch/GunnerCam")
@onready var left_track_mesh: MeshInstance3D = get_node_or_null("Model/Hull/LeftTrack")
@onready var right_track_mesh: MeshInstance3D = get_node_or_null("Model/Hull/RightTrack")

func _ready() -> void:
	hp = max_hp
	_setup_seats()
	if chase_cam != null:
		chase_cam.current = false
	if gunner_cam != null:
		gunner_cam.current = false
	if chase_arm != null:
		chase_arm.add_excluded_object(get_rid())
	if interact_area != null:
		interact_area.collision_mask |= 1
		interact_area.body_entered.connect(_on_body_entered)
		interact_area.body_exited.connect(_on_body_exited)
	if muzzle_flash != null:
		muzzle_flash.visible = false

## Turret role (seat 1) uses its own FPS camera mounted on CommanderHatch —
## the view inherits Turret yaw so it rotates with the TURRET, not the hull.
func _update_active_camera(local_seat_idx: int) -> void:
	if local_seat_idx == 1:
		if chase_cam != null:
			chase_cam.current = false
		if gunner_cam != null:
			gunner_cam.current = true
	elif local_seat_idx == 0:
		if gunner_cam != null:
			gunner_cam.current = false
		if chase_cam != null:
			chase_cam.current = true
	else:
		if chase_cam != null:
			chase_cam.current = false
		if gunner_cam != null:
			gunner_cam.current = false

func _setup_seats() -> void:
	seats.clear()
	occupants.clear()
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

# --- Enter / Exit ---

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or body.get("is_piloting") == true:
		return
	if not has_free_seat():
		return
	var hud = body.get("hud")
	if hud == null:
		return
	_prompt_player = body
	_prompt_player = body
	if hud.has_method("show_enter_prompt"):
		hud.show_enter_prompt()
	elif hud.has_method("show_hover_name"):
		hud.show_hover_name(prompt_text, false)

func _on_body_exited(body: Node3D) -> void:
	if body == _prompt_player:
		_prompt_player = null
		var hud = body.get("hud")
		if hud != null:
			if hud.has_method("hide_enter_prompt"):
				hud.hide_enter_prompt()
			if hud.has_method("hide_hover_name"):
				hud.hide_hover_name()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var target := -1
		if (event.ctrl_pressed or Input.is_key_pressed(KEY_CTRL)) and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			target = event.keycode - KEY_1
		elif (event.ctrl_pressed or Input.is_key_pressed(KEY_CTRL)) and event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
			target = event.keycode - KEY_KP_1
		if target != -1:
			_request_seat_switch(target)
			return
	if not event.is_action_pressed("vehicle_interact"):
		return
	var mgr = get_tree().current_scene
	var net := GlobalData.is_networked() and mgr is MultiplayerManager
	# Enter if in trigger and free seat
	if _prompt_player != null and _prompt_player.get("is_piloting") != true and has_free_seat():
		if net:
			mgr.request_vehicle_enter.rpc_id(1, String(get_path()))
		else:
			_enter(_prompt_player)
		return
	# Exit if seated: player must be nearly stationary
	for i in occupants.size():
		var occ = occupants[i]
		if occ != null and occ.get("hud") != null:
			if velocity.length() > 2.5:
				var h = occ.get("hud")
				if h and h.has_method("show_hover_name"):
					h.show_hover_name("Slow down to exit tank!", false)
				return
			if net:
				mgr.request_vehicle_exit.rpc_id(1, String(get_path()), i)
			else:
				_exit(i)
			return

func _input(event: InputEvent) -> void:
	# Local occupant aiming & camera control
	var local_seat := _get_local_seat_index()
	if local_seat == -1:
		return

	if event is InputEventMouseMotion:
		if local_seat == 0:
			# Driver (seat 1): aims the main turret & cannon, chase orbit camera
			_target_turret_yaw -= event.relative.x * mouse_sens
			# Same sign convention as the camera below: mouse down = look/aim down.
			# +X rotation lifts the -Z barrel UP, so pitch must SUBTRACT mouse Y —
			# adding it aimed the cannon opposite to the crosshair.
			_target_cannon_pitch = clampf(_target_cannon_pitch - event.relative.y * mouse_sens, cannon_min_pitch, cannon_max_pitch)
			_cam_yaw -= event.relative.x * mouse_sens
			_cam_pitch = clampf(_cam_pitch - event.relative.y * mouse_sens, -0.6, 0.4)
			_send_aim(0, _target_turret_yaw, _target_cannon_pitch)
		else:
			# Turret role (seat 2): rotates ONLY the CommanderHatch cupola.
			# Main turret & cannon stay under the driver's control.
			_target_hatch_yaw -= event.relative.x * mouse_sens
			_target_hatch_pitch = clampf(_target_hatch_pitch - event.relative.y * mouse_sens, -0.5, 0.35)
			_send_aim(1, _target_hatch_yaw, _target_hatch_pitch)

	# Driver only fires the 120mm (single shot per reload)
	if event.is_action_pressed("fire") and local_seat == 0:
		_try_fire_cannon()

func _get_local_seat_index() -> int:
	for i in occupants.size():
		var occ = occupants[i]
		if occ != null and occ.get("hud") != null:
			return i
	return -1

func _request_seat_switch(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= seats.size() or is_destroyed:
		return
	var my_idx := _get_local_seat_index()
	if my_idx == -1 or my_idx == target_idx:
		return
	if occupants[target_idx] != null:
		var hud = occupants[my_idx].get("hud")
		if hud and hud.has_method("show_hover_name"):
			hud.show_hover_name("Seat %d is occupied!" % (target_idx + 1), false)
		return
	var mgr = get_tree().current_scene
	var net := GlobalData.is_networked() and mgr is MultiplayerManager
	if net:
		mgr.request_vehicle_switch_seat.rpc_id(1, String(get_path()), my_idx, target_idx)
	else:
		net_sync_switch_seat(occupants[my_idx], my_idx, target_idx)

func net_sync_switch_seat(player_node: Node3D, from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or from_idx >= occupants.size() or to_idx < 0 or to_idx >= occupants.size():
		return
	if occupants[from_idx] != player_node or occupants[to_idx] != null:
		return
	occupants[from_idx] = null
	occupants[to_idx] = player_node
	if player_node.has_method("switch_aircraft_seat"):
		player_node.switch_aircraft_seat(seats[to_idx])
	else:
		player_node.enter_aircraft(seats[to_idx])
	if from_idx == 0:
		_notify_release()
	if player_node.get("hud") != null:
		_update_active_camera(to_idx)
	_update_hud()

func net_sync_enter(player_node: Node3D, seat_idx: int) -> void:
	if seat_idx < 0 or seat_idx >= occupants.size() or is_destroyed:
		return
	occupants[seat_idx] = player_node
	_prompt_player = null
	var hud = player_node.get("hud")
	if hud != null and hud.has_method("hide_enter_prompt"):
		hud.hide_enter_prompt()
	player_node.enter_aircraft(seats[seat_idx])
	if player_node.get("hud") != null:
		_update_active_camera(seat_idx)
	pilot_entered.emit(player_node)
	_update_hud()

func net_sync_exit(seat_idx: int) -> void:
	if seat_idx < 0 or seat_idx >= occupants.size() or occupants[seat_idx] == null:
		return
	var player: Node3D = occupants[seat_idx]
	occupants[seat_idx] = null
	if player.get("hud") != null:
		_update_active_camera(-1)
	var side := 3.2 if seats[seat_idx].position.x >= 0.0 else -3.2
	var exit_pos := seats[seat_idx].global_position + global_basis * Vector3(side, 0.6, 0.0)
	var bail_vel := velocity * 0.3
	player.exit_aircraft(exit_pos, -global_basis.z, bail_vel)
	pilot_exited.emit()
	if seat_idx == 0:
		_notify_release()
	_update_hud()

func _enter(player: Node3D) -> void:
	var idx := occupants.find(null)
	if idx == -1 or is_destroyed:
		return
	net_sync_enter(player, idx)

func _exit(idx: int) -> void:
	if idx < 0 or idx >= occupants.size() or occupants[idx] == null:
		return
	var player: Node3D = occupants[idx]
	occupants[idx] = null
	if player.get("hud") != null:
		_update_active_camera(-1)
	var side := 3.2 if seats[idx].position.x >= 0.0 else -3.2
	var exit_pos := seats[idx].global_position + global_basis * Vector3(side, 0.6, 0.0)
	var bail_vel := velocity * 0.3
	player.exit_aircraft(exit_pos, -global_basis.z, bail_vel)
	pilot_exited.emit()
	if idx == 0:
		_notify_release()
	if _prompt_player == null and interact_area != null and interact_area.get_overlapping_bodies().has(player):
		_on_body_entered(player)

# --- Process & Camera ---

func _process(delta: float) -> void:
	if reload_timer > 0.0:
		reload_timer = maxf(reload_timer - delta, 0.0)

	# Smooth turret & barrel rotation toward target angles
	var w_yaw := minf(delta * turret_turn_speed * 4.0, 1.0)
	var w_pitch := minf(delta * cannon_pitch_speed * 4.0, 1.0)
	turret_yaw = lerp_angle(turret_yaw, _target_turret_yaw, w_yaw)
	cannon_pitch = lerp(cannon_pitch, _target_cannon_pitch, w_pitch)

	if turret_node != null:
		turret_node.rotation.y = turret_yaw
	if barrel_node != null:
		barrel_node.rotation.x = cannon_pitch
	if commander_hatch != null:
		# Gunner rotates ONLY the cupola (yaw + pitch); main turret untouched.
		hatch_yaw = lerp_angle(hatch_yaw, _target_hatch_yaw, minf(delta * 12.0, 1.0))
		hatch_pitch = lerpf(hatch_pitch, _target_hatch_pitch, minf(delta * 12.0, 1.0))
		commander_hatch.rotation = Vector3(hatch_pitch, hatch_yaw, 0.0)

	# Commander M2 (seat 1): hold LMB, gatling-style heat
	mg_cd = maxf(mg_cd - delta, 0.0)
	if _get_local_seat_index() == 1:
		if mg_overheated:
			mg_overheat_left -= delta
			if mg_overheat_left <= 0.0:
				mg_overheated = false
				mg_heat = MG_OVERHEAT_RESUME
		else:
			var mg_firing := Input.is_action_pressed("fire")
			if mg_firing and mg_cd <= 0.0:
				_fire_commander_mg()
				mg_cd = MG_RATE
			if not mg_firing:
				mg_heat = maxf(mg_heat - MG_HEAT_COOL_RATE * delta, 0.0)
	else:
		mg_heat = maxf(mg_heat - MG_HEAT_COOL_RATE * delta, 0.0)

	# Camera follow
	if chase_pivot != null and chase_arm != null and chase_cam != null and chase_cam.current:
		var w_cam := minf(delta * 9.0, 1.0)
		chase_pivot.rotation.y = lerp_angle(chase_pivot.rotation.y, _cam_yaw, w_cam)
		chase_arm.rotation.x = lerp(chase_arm.rotation.x, _cam_pitch, w_cam)

# --- Physics & Driving ---

func _physics_process(delta: float) -> void:
	if _net_puppet:
		var t := minf(1.0, delta * 15.0)
		if _net_target_pos.is_finite():
			global_position = global_position.lerp(_net_target_pos, t)
		if _net_target_quat.is_finite() and global_basis.is_finite():
			var cur_q := global_basis.get_rotation_quaternion()
			if cur_q.is_finite():
				var q := cur_q.slerp(_net_target_quat, t)
				if q.is_finite():
					global_basis = Basis(q).orthonormalized()
		if _net_target_vel.is_finite():
			velocity = _net_target_vel
		_target_turret_yaw = _net_target_turret_yaw
		_target_cannon_pitch = _net_target_cannon_pitch
		_update_hud()
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var driver = occupants[0] if occupants.size() > 0 else null
	var driving: bool = driver != null and driver.get("is_dead") != true

	if driving:
		_drive_input(delta)
		var local_driver: bool = driver.get("hud") != null
		if local_driver:
			_net_send_state(delta)
		if _engine_sfx == null:
			_engine_sfx = Sfx.loop3d("humvee", self, 10.0, 120.0, -2.0)
		if _engine_sfx:
			var spd_ratio := clampf(velocity.length() / max_speed, 0.0, 1.0)
			_engine_sfx.volume_db = lerpf(-12.0, 2.0, spd_ratio)
	else:
		if _engine_sfx != null:
			Sfx.stop_loop(_engine_sfx)
			_engine_sfx = null
		# Decelerate to stop
		var horiz := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, brake_power * delta)
		velocity.x = horiz.x
		velocity.z = horiz.z

	move_and_slide()
	_update_hud()

func _drive_input(delta: float) -> void:
	var fwd_input := Input.get_axis("move_backward", "move_forward") # W / S
	var steer_input := Input.get_axis("move_right", "move_left")     # A = steer left (+yaw), D = steer right (-yaw)
	var forward := -global_basis.z
	var fwd_speed := velocity.dot(forward)

	# Steer / pivot turning: tracked tank can pivot in place!
	if absf(steer_input) > 0.05:
		var turn_rate := turn_speed
		# Slightly faster pivot turn when stationary
		if absf(fwd_speed) < 1.0:
			turn_rate *= 1.15
		rotate_y(steer_input * turn_rate * delta)

	# Acceleration / Braking
	if Input.is_action_pressed("jump"): # Space handbrake
		var horiz := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, brake_power * 1.5 * delta)
		velocity.x = horiz.x
		velocity.z = horiz.z
	elif fwd_input > 0.0:
		# Forward
		var target_spd := max_speed
		if Input.is_action_pressed("sprint"):
			target_spd *= 1.25 # Turbo boost
		var target_vel := forward * target_spd
		var accel := acceleration * (1.25 if Input.is_action_pressed("sprint") else 1.0)
		var h_vel := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3(target_vel.x, 0.0, target_vel.z), accel * delta)
		velocity.x = h_vel.x
		velocity.z = h_vel.z
	elif fwd_input < 0.0:
		# Reverse or brake
		if fwd_speed > 1.0:
			var h_vel := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, brake_power * delta)
			velocity.x = h_vel.x
			velocity.z = h_vel.z
		else:
			var target_vel := -forward * reverse_speed
			var h_vel := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3(target_vel.x, 0.0, target_vel.z), acceleration * delta)
			velocity.x = h_vel.x
			velocity.z = h_vel.z
	else:
		# Coasting drag
		var h_vel := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 6.0 * delta)
		velocity.x = h_vel.x
		velocity.z = h_vel.z

# --- Cannon & MG Firing ---

func _try_fire_cannon(seat_idx: int = 0) -> void:
	if reload_timer > 0.0 or is_destroyed:
		return
	if seat_idx != 0:
		return # ONLY driver (seat 0) fires the 120mm main cannon

	reload_timer = reload_time

	# Determine shooter info
	var shooter: Node3D = occupants[0]
	var s_name := "Tank"
	var s_fac := "Player"
	if shooter != null:
		s_name = str(shooter.get("player_name")) if shooter.get("player_name") else "Tanker"
		s_fac = str(shooter.get("team")) if shooter.get("team") else "Player"

	var spawn_pos := muzzle_node.global_position if muzzle_node else global_position + Vector3(0, 2.2, -3.0)

	# Crosshair-converged fire direction:
	# Raycast from chase camera straight along crosshair into the 3D scene.
	# The shell fires directly toward the point the crosshair is aiming at.
	var fire_dir := -barrel_node.global_transform.basis.z.normalized() if barrel_node else -global_basis.z
	if chase_cam != null and chase_cam.current:
		var space := get_world_3d().direct_space_state
		var cam_pos := chase_cam.global_position
		var cam_fwd := -chase_cam.global_transform.basis.z.normalized()
		var ray_end := cam_pos + cam_fwd * 1000.0
		var q := PhysicsRayQueryParameters3D.create(cam_pos, ray_end, ~0, [get_rid()])
		q.collide_with_areas = true
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		var aim_point: Vector3 = hit.position if hit else (cam_pos + cam_fwd * 500.0)
		var converged := (aim_point - spawn_pos).normalized()
		# Only use converged if not pointing backwards relative to the barrel
		if converged.dot(-barrel_node.global_transform.basis.z) > 0.3:
			fire_dir = converged
		else:
			fire_dir = -barrel_node.global_transform.basis.z.normalized()

	# Spawn projectile locally
	_spawn_cannon_shell(spawn_pos, fire_dir, s_name, s_fac)

	# Replicate projectile to multiplayer peers
	var mgr = get_tree().current_scene
	if GlobalData.is_networked() and mgr is MultiplayerManager:
		mgr.spawn_utility_net("res://scenes/weapons/heavy/tank_shell.tscn", spawn_pos, fire_dir, {
			"owner_name": s_name,
			"faction": s_fac,
		})

	# Muzzle flash and audio
	if muzzle_flash != null:
		muzzle_flash.visible = true
		get_tree().create_timer(0.08).timeout.connect(func():
			if is_instance_valid(muzzle_flash):
				muzzle_flash.visible = false
		)
	Sfx.oneshot3d("bomb", self, 35.0, 260.0, 5.0)

func _spawn_cannon_shell(pos: Vector3, dir: Vector3, att_name: String, att_fac: String) -> void:
	var shell_scene = load("res://scenes/weapons/heavy/tank_shell.tscn") as PackedScene
	if shell_scene == null:
		return
	var shell = shell_scene.instantiate()
	shell.shooter_name = att_name
	shell.shooter_faction = att_fac
	shell.direction = dir
	shell.source_tank = self
	var root := get_tree().current_scene if get_tree().current_scene else get_tree().root
	root.add_child(shell)
	shell.global_position = pos

func _fire_commander_mg() -> void:
	if mg_overheated or gunner_cam == null:
		return
	mg_heat = minf(mg_heat + MG_HEAT_PER_SHOT, 100.0)
	if mg_heat >= 100.0:
		mg_overheated = true
		mg_overheat_left = MG_OVERHEAT_LOCK

	var shooter: Node3D = occupants[1] if occupants.size() > 1 else null
	var s_name := str(shooter.get("player_name")) if shooter and shooter.get("player_name") else "Commander"
	var s_fac := str(shooter.get("team")) if shooter and shooter.get("team") else "Player"

	var cam_xf := gunner_cam.global_transform
	var dir := (-cam_xf.basis.z + cam_xf.basis.x * randf_range(-MG_SPREAD, MG_SPREAD) \
			+ cam_xf.basis.y * randf_range(-MG_SPREAD, MG_SPREAD)).normalized()
	var end := cam_xf.origin + dir * MG_RANGE
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam_xf.origin, end, ~0, [get_rid()])
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	var hit_pos := end
	if hit:
		hit_pos = hit.position
		var target = hit.collider
		if target != self and (target as Object).has_method("take_damage"):
			target.take_damage(MG_DMG, s_name, "M2 Browning", s_fac, hit_pos)
			var hud = shooter.get("hud") if shooter else null
			if hud and target.is_in_group("enemy"):
				hud.show_hit_marker(MG_DMG)
		_mg_splash(hit_pos, target, s_name, s_fac)

	var muzzle_pos := commander_hatch.global_position + (-commander_hatch.global_transform.basis.z * 1.0) if commander_hatch else cam_xf.origin
	Sfx.pool_fire3d("rifle_single", self, 18.0, 160.0, 3.0)
	var mgr = get_tree().current_scene
	if GlobalData.is_networked() and mgr is MultiplayerManager:
		mgr.send_tracer(muzzle_pos, hit_pos, 0.14, false) # fat M2 tracer, all peers
	elif shooter != null and shooter.has_method("create_tracer"):
		shooter.create_tracer(muzzle_pos, hit_pos, 0.14)

func _mg_splash(pos: Vector3, direct_hit: Object, s_name: String, s_fac: String) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 4.0
	query.shape = sphere
	query.transform = Transform3D(Basis(), pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit: Array = []
	for res in space.intersect_shape(query, 16):
		var col = res.collider
		if col == null or col == self or col == direct_hit:
			continue
		if not (col as Object).has_method("take_damage") or col in hit:
			continue
		hit.append(col)
		var dist: float = pos.distance_to(col.global_position)
		var dmg: float = AircraftOrdnance.compute_blast_damage(dist, 4.0, MG_DMG * 0.7, MG_DMG * 0.2)
		if dmg > 0.0:
			col.take_damage(dmg, s_name, "M2 Splash", s_fac, pos)

# --- HUD ---

func _update_hud() -> void:
	var used := 0
	for o in occupants:
		if o != null: used += 1
	var free_seats := occupants.size() - used
	var seats_map: Array = []
	for o in occupants:
		seats_map.append(o != null)
	var my_seat := -1
	for idx in occupants.size():
		if occupants[idx] != null and occupants[idx].get("hud") != null:
			my_seat = idx
			break
	for idx in occupants.size():
		var occ = occupants[idx]
		if occ == null:
			continue
		var hud = occ.get("hud")
		if hud != null and hud.has_method("update_aircraft_hud"):
			hud.update_aircraft_hud({
				"kind": "tank",
				"name": vehicle_name,
				"seat_role": "DRIVER & CANNON" if idx == 0 else "TURRET GUNNER",
				"speed": velocity.length() * 3.6,
				"reload": reload_timer,
				"reload_max": reload_time,
				"heat": mg_heat,
				"overheated": mg_overheated,
				"hp": hp,
				"max_hp": max_hp,
				"seats_free": free_seats,
				"seats_total": occupants.size(),
				"seats_map": seats_map,
				"my_seat": my_seat,
			})

# --- Damage & Destruction ---

func take_damage(amount: float, attacker_name: String = "", _weapon_name: String = "", attacker_faction: String = "", _attacker_pos: Vector3 = Vector3.INF) -> float:
	var mgr = get_tree().current_scene
	if GlobalData.is_networked() and not multiplayer.is_server():
		if mgr is MultiplayerManager:
			mgr.request_vehicle_damage.rpc_id(1, String(get_path()), amount, attacker_name, _weapon_name, attacker_faction, _attacker_pos)
		return 0.0
	if is_destroyed:
		return 0.0
	hp = maxf(hp - amount, 0.0)
	if attacker_name != "":
		_last_hit_by = attacker_name
		_last_hit_faction = attacker_faction
	if mgr is MultiplayerManager and GlobalData.is_networked():
		mgr.net_vehicle_hp.rpc(String(get_path()), hp)
	if hp <= 0.0:
		_explode()
	return amount

func _explode(kill_occupants: bool = true) -> void:
	if is_destroyed:
		return
	is_destroyed = true
	var crash_killer := _last_hit_by if _last_hit_by != "" else vehicle_name
	var crash_fac := _last_hit_faction if _last_hit_faction != "" else "World"
	var mgr = get_tree().current_scene
	if GlobalData.is_networked() and multiplayer.is_server() and mgr is MultiplayerManager:
		mgr.net_vehicle_explode.rpc(String(get_path()), crash_killer, crash_fac)
	_notify_release()
	_update_active_camera(-1)
	if kill_occupants:
		for i in occupants.size():
			var occ = occupants[i]
			if occ != null and occ.has_method("take_damage"):
				occ.take_damage(9999.0, crash_killer, "Tank Destruction", crash_fac, global_position)
		_blast_area(global_position, 14.0, 350.0, 100.0)
	AircraftOrdnance.spawn_blast_visual(global_position, 14.0)
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
			collider.take_damage(dmg, _last_hit_by if _last_hit_by != "" else vehicle_name, "Tank Blast", _last_hit_faction, pos)

func net_sync_explode(attacker_name: String, attacker_faction: String) -> void:
	if is_destroyed:
		return
	if attacker_name != "":
		_last_hit_by = attacker_name
		_last_hit_faction = attacker_faction
	_explode(false)

# --- Network Sync ---

func _net_send_state(delta: float) -> void:
	_net_send_timer += delta
	if _net_send_timer < 0.05:
		return
	_net_send_timer = 0.0
	var mgr = get_tree().current_scene
	if mgr and mgr.has_method("send_vehicle_state"):
		mgr.send_vehicle_state(String(get_path()), global_position, global_basis.get_euler(), velocity, 1.0)

func _notify_release() -> void:
	var mgr = get_tree().current_scene
	if mgr and mgr.has_method("send_vehicle_release"):
		mgr.send_vehicle_release(String(get_path()))

func net_set_target(pos: Vector3, rot: Vector3, vel: Vector3, _eng: float = 0.0) -> void:
	if not pos.is_finite() or not rot.is_finite() or not vel.is_finite():
		return
	_net_puppet = true
	_net_target_pos = pos
	var b := Basis.from_euler(rot)
	if b.is_finite():
		_net_target_quat = b.get_rotation_quaternion().normalized()
	_net_target_vel = vel

func net_release_puppet() -> void:
	_net_puppet = false

## Local occupant streams their seat's aim targets to the other peers (20 Hz cap).
func _send_aim(seat_idx: int, yaw: float, pitch: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _net_aim_timer < 50: # mouse events fire far faster than the 20 Hz net budget
		return
	_net_aim_timer = now
	var mgr = get_tree().current_scene
	if mgr and mgr.has_method("send_vehicle_aim"):
		mgr.send_vehicle_aim(String(get_path()), seat_idx, yaw, pitch)

## Remote seat holder applied their aim: seat 0 = main turret/cannon, seat 1 = cupola.
func net_set_aim(seat_idx: int, yaw: float, pitch: float) -> void:
	if not is_finite(yaw) or not is_finite(pitch):
		return
	if seat_idx == 0:
		_net_target_turret_yaw = yaw
		_net_target_cannon_pitch = pitch
	elif seat_idx == 1:
		_target_hatch_yaw = yaw
		_target_hatch_pitch = pitch
