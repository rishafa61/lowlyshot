class_name HelicopterController
extends RigidBody3D
## Chinook CH-47 tandem-rotor helicopter controller.
## 6 seats: seat 0 = pilot (controls flight + mouse camera),
## seats 1..5 = passengers (mouse camera only).
## Arcade flight physics: collective (W/S/Shift/Ctrl), yaw (A/D),
## pitch/roll (mouse), auto-leveling hover, ground-only exit.

signal pilot_entered(pilot: Node3D)
signal pilot_exited
signal destroyed

# --- Tuning ---
@export_group("Helicopter Stats")
@export var heli_name: String = "CH-47 Chinook"
@export var max_hp: float = 900.0
@export var prompt_text: String = "Press F to Board Heli"
@export var mouse_sens: float = 0.0035

@export_group("Flight Tuning")
@export var max_lift_accel: float = 24.0      ## m/s^2 at full collective + boost (~2.4 Gs)
@export var hover_lift_ratio: float = 0.42    ## collective value that cancels gravity (~9.8 / 24.0 = ~0.41)
@export var max_horiz_speed: float = 45.0     ## m/s top horizontal (~160 km/h)
@export var max_climb_speed: float = 14.0     ## m/s max vertical rate
@export var max_pitch_deg: float = 24.0       ## max nose down/up pitch
@export var max_roll_deg: float = 14.0        ## max bank angle — kept low so horizontal mouse doesn't flip heli
@export var pitch_sens: float = 0.004        ## mouse pitch -> tilt speed
@export var roll_sens: float = 0.004         ## mouse roll -> tilt speed (rate-based: reverses instantly)
@export var tilt_input_cap: float = 1.4      ## max tilt speed from mouse (rad/s of target change)
@export var tilt_vel_decay: float = 3.0      ## tilt input speed bleeds off when mouse stops
@export var level_pull: float = 1.0          ## rad/s spring pulling the bank/pitch back to level
@export var attitude_rate: float = 6.0       ## how fast airframe attitude follows targets (kinematic slerp)
@export var level_rate: float = 3.6           ## auto-leveling return rate (snaps back flat quickly)
@export var yaw_rate: float = 1.6             ## rad/s yaw speed (A/D)
@export var drag_horiz: float = 0.35          ## air resistance for stable hover
@export var drag_vert: float = 0.45
@export var tilt_thrust_accel: float = 35.0   ## m/s^2 horizontal push per rad of mouse tilt (arcade cyclic)
@export var alt_assist: float = 4.0           ## m/s^2 vertical compensation per rad of tilt (holds altitude in forward flight)
@export var exit_max_speed: float = 2.2       ## slower than this + grounded = walk out; faster/airborne = bail out
@export var bail_power_loss_delay: float = 3.0 ## seconds after the pilot bails before the engine dies

const GRAVITY := 9.8
const GROUND_RAY := 1.9 ## wheel contact sits ~1.67m below center; ray must be shorter so
						## "grounded" means the gear actually touches, not hovering nearby

# Door MGs (seat 2 = Model/MG left, seat 3 = Model/MG2 right) — same heat
# attributes as the tank's commander M2 cupola gun
const MG_DMG := 20.0
const MG_RATE := 0.125            ## 8 rounds/s
const MG_RANGE := 500.0
const MG_SPREAD := 0.004
const MG_HEAT_PER_SHOT := 2.0     ## ~6s hold to reach the peak
const MG_HEAT_COOL_RATE := 25.0
const MG_OVERHEAT_RESUME := 35.0
const MG_OVERHEAT_LOCK := 3.0
const MG_MAX_YAW := 1.1           ## traverse ±63° around the straight-out-the-door pose
const MG_PITCH_DOWN := 0.9        ## door gunners need steep depression from altitude
const MG_PITCH_UP := 0.35

var hp: float
var is_destroyed := false

# Engine / collective state
var engine_power: float = 0.0    ## 0..1 (spools up when pilot seated)
var collective: float = 0.0      ## 0..1
var rotor_rpm: float = 0.0       ## rad/s for visual spinning
var rotor_angle: float = 0.0

# Flight inputs from pilot
var _target_pitch: float = 0.0   ## rad
var _target_roll: float = 0.0    ## rad
var _tilt_vel := Vector2.ZERO    ## x = pitch input rate, y = roll input rate (rad/s)
var _yaw: float = 0.0            ## integrated heading — drives kinematic attitude

# Camera
var _cam_yaw: float = 0.0
var _cam_pitch: float = -0.2

# Door MG state (index 0 = left MG/seat 2, index 1 = right MG2/seat 3)
var mg_heat: Array[float] = [0.0, 0.0]
var mg_overheated: Array[bool] = [false, false]
var mg_overheat_left: Array[float] = [0.0, 0.0]
var mg_cd: Array[float] = [0.0, 0.0]
var mg_yaw: Array[float] = [0.0, 0.0]
var mg_pitch: Array[float] = [0.0, 0.0]
var _mg_yaw_target: Array[float] = [0.0, 0.0]
var _mg_pitch_target: Array[float] = [0.0, 0.0]
var _mg_base_yaw: Array[float] = [] ## scene-authored ±90° mount yaw, captured in _ready

# Seats & occupants (index 0 is pilot, 1..5 are passengers)
var seats: Array[Marker3D] = []
var occupants: Array = []
var _prompt_player: Node3D = null
var _is_abandoned := false        ## pilot bailed mid-air — engine dies after bail_power_loss_delay
var _pilotless_time := 0.0
var _last_bailed_pilot: Node3D = null
var _rotor_sfx: AudioStreamPlayer3D = null

# --- Network puppet: MultiplayerManager shuttles transforms of locally-driven vehicles ---
var _net_puppet := false
var _net_target_pos := Vector3.ZERO
var _net_target_quat := Quaternion.IDENTITY
var _net_target_vel := Vector3.ZERO
var _net_send_timer := 0.0
var _net_aim_timer := 0

## Streams this vehicle's transform to other machines while locally driven.
func _net_send_state(delta: float) -> void:
	_net_send_timer += delta
	if _net_send_timer < 0.05: # 20 Hz
		return
	_net_send_timer = 0.0
	var mgr = get_tree().current_scene
	if mgr and mgr.has_method("send_vehicle_state"):
		mgr.send_vehicle_state(String(get_path()), global_position, global_basis.get_euler(), linear_velocity, engine_power)

func _notify_release() -> void:
	var mgr = get_tree().current_scene
	if mgr and mgr.has_method("send_vehicle_release"):
		mgr.send_vehicle_release(String(get_path()))

@onready var interact_area: Area3D = get_node_or_null("InteractArea")
@onready var chase_pivot: Node3D = get_node_or_null("ChasePivot")
@onready var chase_arm: SpringArm3D = get_node_or_null("ChasePivot/ChaseArm")
@onready var chase_cam: Camera3D = get_node_or_null("ChasePivot/ChaseArm/ChaseCamera")
@onready var rotor_front: Node3D = get_node_or_null("Model/RotorFront")
@onready var rotor_rear: Node3D = get_node_or_null("Model/RotorRear")
@onready var mg_nodes: Array[Node3D] = [
	get_node_or_null("Model/MG") as Node3D,
	get_node_or_null("Model/MG2") as Node3D,
]
@onready var mg_cams: Array[Camera3D] = [
	get_node_or_null("Model/MG/GunnerCam") as Camera3D,
	get_node_or_null("Model/MG2/GunnerCam") as Camera3D,
]
@onready var mg_barrels: Array[Node3D] = [
	get_node_or_null("Model/MG/Barrel") as Node3D,
	get_node_or_null("Model/MG2/Barrel") as Node3D,
]

func _ready() -> void:
	gravity_scale = 0.0 ## applied manually in _apply_flight
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = false ## forces drive flight; a sleeping body would ignore them mid-hover
	body_entered.connect(_on_impact)
	hp = max_hp
	for mg in mg_nodes:
		_mg_base_yaw.append(mg.rotation.y if mg != null else 0.0)
	if chase_cam != null:
		chase_cam.current = false
	for cam in mg_cams:
		if cam != null:
			cam.current = false
	_yaw = global_transform.basis.get_euler(EULER_ORDER_YXZ).y # sync heading with scene-authored basis
	_setup_seats()
	if chase_arm != null:
		chase_arm.add_excluded_object(get_rid())
	if interact_area != null:
		interact_area.collision_mask |= 1
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

func get_driver() -> Node3D:
	return occupants[0] if occupants.size() > 0 else null

func is_grounded() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * GROUND_RAY,
		collision_mask,
		[get_rid()]
	)
	return not space.intersect_ray(query).is_empty()

func can_exit() -> bool:
	return true ## player can exit anytime — grounded walks out, airborne bails out

func can_walk_out() -> bool:
	return is_grounded() and linear_velocity.length() <= exit_max_speed

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
		# CTRL + 1..9: switch to that seat (if free)
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
	# Try enter
	if _prompt_player != null and _prompt_player.get("is_piloting") != true and has_free_seat():
		if net:
			mgr.request_vehicle_enter.rpc_id(1, String(get_path())) # host assigns the seat
		else:
			_enter(_prompt_player)
		return
	# Try exit: any seated local player with HUD can press F
	for i in occupants.size():
		var occ = occupants[i]
		if occ != null and occ.get("hud") != null:
			if net:
				mgr.request_vehicle_exit.rpc_id(1, String(get_path()), i)
			else:
				_exit(i)
			return

func _input(event: InputEvent) -> void:
	# Local driver / passenger mouse look
	var has_local := false
	for occ in occupants:
		if occ != null and occ.get("hud") != null:
			has_local = true
			break
	if not has_local:
		return
	if event is InputEventMouseMotion:
		var seat := _local_seat_idx()
		var freelook := Input.is_action_pressed("camera_freelook") # ALT held
		if seat == 0 and not freelook:
			# Rate-style tilt control: mouse sets a tilt SPEED, not a stored angle.
			# An opposite mouse flick reverses the bank instantly — no unwinding.
			_tilt_vel.x = clampf(_tilt_vel.x - event.relative.y * pitch_sens, -tilt_input_cap, tilt_input_cap)
			_tilt_vel.y = clampf(_tilt_vel.y + event.relative.x * roll_sens, -tilt_input_cap, tilt_input_cap)
		elif seat == 2 or seat == 3:
			# Door gunner: aims the mounted MG (gun + its camera rotate together).
			var g := seat - 2
			_mg_yaw_target[g] = clampf(_mg_yaw_target[g] - event.relative.x * mouse_sens, -MG_MAX_YAW, MG_MAX_YAW)
			# Same sign convention as the tank cupola: mouse down = aim down.
			_mg_pitch_target[g] = clampf(_mg_pitch_target[g] - event.relative.y * mouse_sens, -MG_PITCH_DOWN, MG_PITCH_UP)
			_send_aim(seat, _mg_yaw_target[g], _mg_pitch_target[g])
		else:
			# ALT held (driver) or passenger: camera orbits, heli keeps its tilt
			_cam_yaw -= event.relative.x * mouse_sens
			_cam_pitch = clampf(_cam_pitch - event.relative.y * mouse_sens, -0.7, 0.4)

func _local_seat_idx() -> int:
	for i in occupants.size():
		var occ = occupants[i]
		if occ != null and occ.get("hud") != null:
			return i
	return -1

func _request_seat_switch(target_idx: int) -> void:
	if target_idx < 0 or target_idx >= seats.size() or is_destroyed:
		return
	var my_idx := -1
	for i in occupants.size():
		if occupants[i] != null and occupants[i].get("hud") != null:
			my_idx = i
			break
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
		if not is_grounded():
			_is_abandoned = true
			_pilotless_time = 0.0
			_last_bailed_pilot = player_node
	if to_idx == 0:
		_is_abandoned = false
		_pilotless_time = 0.0
		_last_bailed_pilot = null
	if player_node.get("hud") != null:
		_update_active_camera(to_idx)
	_update_hud()

## Door-gunner seats (2 = left MG, 3 = right MG2) get the FPS camera mounted on
## the gun itself; every other seat orbits the chase cam.
func _update_active_camera(local_seat_idx: int) -> void:
	if local_seat_idx == 2 or local_seat_idx == 3:
		var cam: Camera3D = mg_cams[local_seat_idx - 2]
		if cam != null:
			cam.current = true
		if chase_cam != null:
			chase_cam.current = false
	else:
		for cam in mg_cams:
			if cam != null:
				cam.current = false
		if chase_cam != null:
			chase_cam.current = local_seat_idx >= 0

func net_sync_enter(player_node: Node3D, seat_idx: int) -> void:
	if seat_idx < 0 or seat_idx >= occupants.size() or is_destroyed:
		return
	occupants[seat_idx] = player_node
	_prompt_player = null
	var hud = player_node.get("hud")
	if hud != null and hud.has_method("hide_enter_prompt"):
		hud.hide_enter_prompt()
	if seat_idx == 0:
		_is_abandoned = false
		_pilotless_time = 0.0
		_last_bailed_pilot = null
	player_node.enter_aircraft(seats[seat_idx])
	# Any LOCAL occupant (pilot OR passenger) needs a view: enter_aircraft turned
	# off their first-person camera. Passengers orbit the chase cam (see _input);
	# door gunners (seats 2/3) look through the gun-mounted camera instead.
	if player_node.get("hud") != null:
		_cam_yaw = 0.0
		_cam_pitch = -0.2
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
	var exit_pos := seats[seat_idx].global_position + global_basis * Vector3(side, 0.4, 0.0)
	var bail_vel := linear_velocity * 0.5
	player.exit_aircraft(exit_pos, -global_basis.z, bail_vel)
	pilot_exited.emit()
	if seat_idx == 0:
		_notify_release()
		if not is_grounded():
			_is_abandoned = true
			_pilotless_time = 0.0
			_last_bailed_pilot = player
	_update_hud()

func net_sync_explode(attacker_name: String, attacker_faction: String) -> void:
	# Client copy: eject bodies + visuals only — the host's canonical copy
	# already registered the crash kills; killing here would double-report.
	if is_destroyed:
		return
	_explode(attacker_name, attacker_faction, false)

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
	var exit_pos := seats[idx].global_position + global_basis * Vector3(side, 0.4, 0.0)
	if can_walk_out():
		# Walk out on the ground
		player.exit_aircraft(exit_pos, -global_basis.z, linear_velocity * 0.3)
		pilot_exited.emit()
		if idx == 0:
			_notify_release()
		# Pilot often steps out still inside the trigger: re-arm the prompt.
		if _prompt_player == null and interact_area != null and interact_area.get_overlapping_bodies().has(player):
			_on_body_entered(player)
	else:
		# Bail out mid-air: fling the player clear. If the pilot left, the heli
		# loses power after bail_power_loss_delay, dives, and explodes on impact.
		exit_pos += global_basis * Vector3(0.0, 1.2, 0.0)
		player.exit_aircraft(exit_pos, -global_basis.z, linear_velocity * 0.5 + Vector3.UP * 9.0)
		pilot_exited.emit()
		if idx == 0:
			_notify_release()
		if idx == 0:
			_is_abandoned = true
			_pilotless_time = 0.0
			_last_bailed_pilot = player

# --- Process & Physics ---

func _process(delta: float) -> void:
	_animate_rotors(delta)
	_update_camera(delta)
	_process_door_mgs(delta)
	_update_hud()

func _process_door_mgs(delta: float) -> void:
	var local_seat := _local_seat_idx()
	for g in 2:
		# Smooth yaw/pitch toward gunner targets
		mg_yaw[g] = lerp_angle(mg_yaw[g], _mg_yaw_target[g], minf(delta * 14.0, 1.0))
		mg_pitch[g] = lerpf(mg_pitch[g], _mg_pitch_target[g], minf(delta * 14.0, 1.0))
		var mg_node: Node3D = mg_nodes[g]
		if mg_node != null and g < _mg_base_yaw.size():
			mg_node.rotation = Vector3(mg_pitch[g], _mg_base_yaw[g] + mg_yaw[g], 0.0)

		# Fire & heat tick
		mg_cd[g] = maxf(mg_cd[g] - delta, 0.0)
		var is_this_gunner := (local_seat == (g + 2))
		if is_this_gunner:
			if mg_overheated[g]:
				mg_overheat_left[g] -= delta
				if mg_overheat_left[g] <= 0.0:
					mg_overheated[g] = false
					mg_heat[g] = MG_OVERHEAT_RESUME
			else:
				var firing := Input.is_action_pressed("fire")
				if firing and mg_cd[g] <= 0.0:
					_fire_door_mg(g)
					mg_cd[g] = MG_RATE
				if not firing:
					mg_heat[g] = maxf(mg_heat[g] - MG_HEAT_COOL_RATE * delta, 0.0)
		else:
			mg_heat[g] = maxf(mg_heat[g] - MG_HEAT_COOL_RATE * delta, 0.0)

func _fire_door_mg(gun_idx: int) -> void:
	if mg_overheated[gun_idx]:
		return
	var cam: Camera3D = mg_cams[gun_idx]
	if cam == null:
		return
	mg_heat[gun_idx] = minf(mg_heat[gun_idx] + MG_HEAT_PER_SHOT, 100.0)
	if mg_heat[gun_idx] >= 100.0:
		mg_overheated[gun_idx] = true
		mg_overheat_left[gun_idx] = MG_OVERHEAT_LOCK

	var seat_idx := gun_idx + 2
	var shooter: Node3D = occupants[seat_idx] if seat_idx < occupants.size() else null
	var s_name := str(shooter.get("player_name")) if shooter and shooter.get("player_name") else "Door Gunner"
	var s_fac := str(shooter.get("team")) if shooter and shooter.get("team") else "Player"

	var cam_xf := cam.global_transform
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
			target.take_damage(MG_DMG, s_name, "Door MG", s_fac, hit_pos)
			var hud = shooter.get("hud") if shooter else null
			if hud and target.is_in_group("enemy"):
				hud.show_hit_marker(MG_DMG)
		_mg_splash(hit_pos, target, s_name, s_fac)

	# Bullet tracer exits directly from the barrel's tip
	var barrel: Node3D = mg_barrels[gun_idx]
	var muzzle_pos: Vector3
	if barrel != null:
		# Barrel extends along its -Z; boxmesh half-length ~0.9m
		muzzle_pos = barrel.global_position + (-barrel.global_transform.basis.z * 0.9)
	else:
		muzzle_pos = cam_xf.origin
	Sfx.pool_fire3d("rifle_single", self, 18.0, 160.0, 3.0)
	var mgr = get_tree().current_scene
	if GlobalData.is_networked() and mgr is MultiplayerManager:
		mgr.send_tracer(muzzle_pos, hit_pos, 0.14, false) # fat door MG tracer, all peers
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
			col.take_damage(dmg, s_name, "Door MG Splash", s_fac, pos)

func _animate_rotors(delta: float) -> void:
	var target_rpm: float = engine_power * 32.0 ## rad/s
	rotor_rpm = move_toward(rotor_rpm, target_rpm, delta * 12.0)
	rotor_angle += rotor_rpm * delta
	# Chinook tandem counter-rotation: front rotates CCW (+Y), rear CW (-Y)
	if rotor_front != null:
		rotor_front.rotation.y = rotor_angle
	if rotor_rear != null:
		rotor_rear.rotation.y = -rotor_angle

func _update_camera(delta: float) -> void:
	if chase_pivot == null or chase_arm == null or chase_cam == null:
		return
	if not chase_cam.current:
		return
	# ALT released: ease camera back behind the heli so the pilot faces forward
	if not Input.is_action_pressed("camera_freelook"):
		_cam_yaw = lerp_angle(_cam_yaw, 0.0, minf(delta * 3.0, 1.0))
		_cam_pitch = lerp(_cam_pitch, -0.2, minf(delta * 3.0, 1.0))
	var target_yaw: float = _cam_yaw
	var target_pitch: float = _cam_pitch
	if Input.is_action_pressed("lean_left"): # Q
		target_yaw = -PI * 0.5
		target_pitch = -0.1
	elif Input.is_action_pressed("lean_right"): # E
		target_yaw = PI * 0.5
		target_pitch = -0.1
	var w: float = minf(delta * 9.0, 1.0)
	chase_pivot.rotation.y = lerp_angle(chase_pivot.rotation.y, target_yaw, w)
	chase_arm.rotation.x = lerp(chase_arm.rotation.x, target_pitch, w)

func net_set_target(pos: Vector3, rot: Vector3, vel: Vector3, eng: float) -> void:
	if not pos.is_finite() or not rot.is_finite() or not vel.is_finite():
		return
	_net_puppet = true
	freeze = true # stop local physics fighting network position
	_net_target_pos = pos
	var b := Basis.from_euler(rot)
	if b.is_finite():
		_net_target_quat = b.get_rotation_quaternion().normalized()
	_net_target_vel = vel
	engine_power = eng if is_finite(eng) else 0.0

## Local door gunner streams their MG aim targets to the other peers (20 Hz cap).
func _send_aim(seat_idx: int, yaw: float, pitch: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _net_aim_timer < 50: # mouse events fire far faster than the 20 Hz net budget
		return
	_net_aim_timer = now
	var mgr = get_tree().current_scene
	if mgr and mgr.has_method("send_vehicle_aim"):
		mgr.send_vehicle_aim(String(get_path()), seat_idx, yaw, pitch)

## Remote door gunner applied their aim: seat 2 = left MG (gun 0), seat 3 = right MG (gun 1).
func net_set_aim(seat_idx: int, yaw: float, pitch: float) -> void:
	if not is_finite(yaw) or not is_finite(pitch):
		return
	if seat_idx >= 2 and seat_idx <= 3:
		var g := seat_idx - 2
		_mg_yaw_target[g] = yaw
		_mg_pitch_target[g] = pitch

func net_release_puppet() -> void:
	_net_puppet = false
	freeze = false

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
			linear_velocity = _net_target_vel
		# Rotor audio for observers
		if engine_power > 0.05 and _rotor_sfx == null:
			_rotor_sfx = Sfx.loop3d("heli", self, 10.0, 120.0, 0.0)
		elif engine_power <= 0.05 and _rotor_sfx != null:
			Sfx.stop_loop(_rotor_sfx)
			_rotor_sfx = null
		return

	var driver := get_driver()
	var has_driver: bool = driver != null and driver.get("is_dead") != true
	var grounded := is_grounded()

	# Rotor audio: spins while a pilot is aboard; fades out on power loss/exit.
	var rotor_wanted: bool = has_driver or engine_power > 0.05
	if rotor_wanted and _rotor_sfx == null:
		_rotor_sfx = Sfx.loop3d("heli", self, 10.0, 120.0, 0.0)
	if _rotor_sfx:
		_rotor_sfx.volume_db = lerpf(-20.0, 0.0, engine_power)
	if not rotor_wanted and _rotor_sfx != null:
		Sfx.stop_loop(_rotor_sfx)
		_rotor_sfx = null

	if has_driver:
		_process_pilot_input(delta)
		var is_local_pilot: bool = driver.get("hud") != null
		if is_local_pilot:
			_net_send_state(delta)
	else:
		if _is_abandoned:
			_pilotless_time += delta
		if _is_abandoned and _pilotless_time >= bail_power_loss_delay:
			# Total power loss: rotors stop, nose drops, heli falls — explodes on touchdown
			engine_power = 0.0
			collective = 0.0
			_target_pitch = deg_to_rad(max_pitch_deg)
			_target_roll = 0.0
			if grounded:
				_explode()
				return
		elif _is_abandoned:
			# Dying phase: hovers on fading power until the countdown ends
			engine_power = move_toward(engine_power, 1.0, delta * 1.0)
			collective = move_toward(collective, hover_lift_ratio, delta * 0.5)
			_target_pitch = move_toward(_target_pitch, 0.0, delta * 2.0)
			_target_roll = move_toward(_target_roll, 0.0, delta * 2.0)
		else:
			# Pilotless but not abandoned (parked / walk-out): settle gently
			engine_power = move_toward(engine_power, 0.0, delta * 1.0)
			collective = move_toward(collective, 0.0, delta * 1.2)
			_target_pitch = move_toward(_target_pitch, 0.0, delta * 2.0)
			_target_roll = move_toward(_target_roll, 0.0, delta * 2.0)

	_apply_flight(delta, grounded, Input.is_action_pressed("crouch") and has_driver)

func _process_pilot_input(delta: float) -> void:
	# Engine spool up to full power
	var target_eng := 1.0
	if Input.is_action_pressed("sprint"): # Shift: increase engine boost
		target_eng = 1.2
	engine_power = move_toward(engine_power, target_eng, delta * 1.2)

	# Collective: W = climb, S = descend, CTRL = landing cut
	var coll_rate := 0.95
	var cutting_landing := Input.is_action_pressed("crouch")
	if Input.is_action_pressed("move_forward"): # W: collective up
		collective = move_toward(collective, 1.0, coll_rate * delta)
	elif Input.is_action_pressed("move_backward"): # S: collective down
		collective = move_toward(collective, 0.0, coll_rate * delta)
	if cutting_landing: # CTRL: reduce collective for landing + auto-level airframe
		collective = move_toward(collective, 0.0, coll_rate * 1.8 * delta)
		_target_pitch = move_toward(_target_pitch, 0.0, delta * level_rate * 2.0)
		_target_roll = move_toward(_target_roll, 0.0, delta * level_rate * 2.0)

	# Auto-center collective to hover if neither W nor S pressed
	if not Input.is_action_pressed("move_forward") and not Input.is_action_pressed("move_backward") and not cutting_landing:
		# Hover bias: gently pull collective toward the gravity-canceling sweet spot
		collective = move_toward(collective, hover_lift_ratio, delta * 0.25)

	# Yaw: A = left (positive Y rot), D = right (negative Y rot)
	_yaw = wrapf(_yaw - Input.get_axis("move_left", "move_right") * yaw_rate * delta, -PI, PI)

	# Integrate rate-style tilt into target angles + clamp strictly to limits
	_target_pitch = clampf(_target_pitch + _tilt_vel.x * delta, -deg_to_rad(max_pitch_deg), deg_to_rad(max_pitch_deg))
	_target_roll = clampf(_target_roll + _tilt_vel.y * delta, -deg_to_rad(max_roll_deg), deg_to_rad(max_roll_deg))

	# Decay mouse velocity so when mouse stops, tilt stops growing
	_tilt_vel.x = move_toward(_tilt_vel.x, 0.0, delta * tilt_vel_decay)
	_tilt_vel.y = move_toward(_tilt_vel.y, 0.0, delta * tilt_vel_decay)

	# Auto-level: when not actively tilting, pull the bank and pitch back to zero
	if absf(_tilt_vel.x) < 0.05:
		_target_pitch = move_toward(_target_pitch, 0.0, delta * level_pull)
	if absf(_tilt_vel.y) < 0.05:
		_target_roll = move_toward(_target_roll, 0.0, delta * level_pull)

func _apply_flight(delta: float, grounded: bool, landing_cut: bool = false) -> void:
	# 1. Total lift force along airframe's UP axis
	var lift_magnitude := max_lift_accel * collective * engine_power * mass
	var lift_force := global_basis.y * lift_magnitude
	apply_central_force(lift_force)

	# 2. Gravity (always straight down) — heavier fall once power drops
	var grav_mult := 1.8 if (_is_abandoned and _pilotless_time >= bail_power_loss_delay) else 1.0
	apply_central_force(Vector3.DOWN * GRAVITY * grav_mult * mass)

	# 2.5 Tilt thrust: mouse tilt is the cyclic — leaning the nose forward
	#     actively accelerates the heli that direction (arcade model).
	#     pitch tilts +, thrust toward the nose direction.
	var nose_fwd := -global_basis.z
	nose_fwd.y = 0.0
	if nose_fwd.length_squared() > 0.001:
		nose_fwd = nose_fwd.normalized()
		apply_central_force(nose_fwd * _target_pitch * tilt_thrust_accel * mass)
	# 2.6 roll tilts +, thrust toward the right-side direction.
	var right_dir := global_basis.x
	right_dir.y = 0.0
	if right_dir.length_squared() > 0.001:
		right_dir = right_dir.normalized()
		apply_central_force(right_dir * _target_roll * tilt_thrust_accel * mass)
	# 2.7 Altitude assist: pitched/banked body loses vertical lift — compensate
	#     so leaning forward doesn't sink the heli into the ground.
	var tilt_up := global_basis.y.dot(Vector3.UP)
	if tilt_up > 0.01:
		apply_central_force(Vector3.UP * (1.0 - tilt_up) * alt_assist * mass)

	# 3. Horizontal and vertical aerodynamic drag
	var local_vel := global_basis.inverse() * linear_velocity
	var horiz_drag := Vector3(local_vel.x, 0.0, local_vel.z) * drag_horiz * mass
	var vert_drag := Vector3(0.0, local_vel.y, 0.0) * drag_vert * mass
	var drag_vec: Vector3 = global_basis * (horiz_drag + vert_drag)
	apply_central_force(-drag_vec)

	# 3.5 Horizontal speed cap (max_horiz_speed ~160 km/h)
	var horiz_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if horiz_vel.length() > max_horiz_speed:
		horiz_vel = horiz_vel.normalized() * max_horiz_speed
		linear_velocity.x = horiz_vel.x
		linear_velocity.z = horiz_vel.z

	# 4. Attitude: fully kinematic. Orientation slerps toward an upright target
	#    built from heading + mouse tilt; physics is never allowed to rotate the
	#    body (angular_velocity zeroed). Flipping, spinning out, and corner-wedging
	#    are impossible by construction — collisions only affect position.
	#    Sign convention: +_target_pitch (mouse fwd) = nose down,
	#                    +_target_roll  (mouse right) = bank right.
	if landing_cut or (grounded and collective < 0.3):
		_target_pitch = 0.0
		_target_roll = 0.0
	if not global_transform.basis.is_finite():
		global_transform.basis = Basis.IDENTITY
	var target_basis := Basis(Vector3.UP, _yaw) \
			* Basis(Vector3.RIGHT, -_target_pitch) \
			* Basis(Vector3.BACK, -_target_roll)
	if target_basis.is_finite():
		var next_basis := global_transform.basis.slerp(target_basis, 1.0 - exp(-attitude_rate * delta))
		if next_basis.is_finite():
			global_transform.basis = next_basis.orthonormalized()
	angular_velocity = Vector3.ZERO
	# Wedge recovery: if a collision (blast/hard touchdown) left the airframe
	# sideways against the terrain, gently pop it upward so it unwedges cleanly.
	if is_grounded() and global_basis.y.dot(Vector3.UP) < 0.85:
		apply_central_force(Vector3.UP * 2.2 * GRAVITY * mass)

	# 5. Ground friction when landed
	if grounded and collective < 0.35:
		linear_velocity.x = move_toward(linear_velocity.x, 0.0, delta * 8.0)
		linear_velocity.z = move_toward(linear_velocity.z, 0.0, delta * 8.0)
		if linear_velocity.y < 0.0:
			linear_velocity.y = 0.0

# --- HUD ---

func _update_hud() -> void:
	var used := 0
	for o in occupants:
		if o != null: used += 1
	var free_seats := occupants.size() - used
	var seats_map: Array = []
	for o in occupants:
		seats_map.append(o != null)
	var my_seat := _local_seat_idx()
	# Incoming homing missile (AT4 locked onto us): warning + beeps for local crew
	var mgr = get_tree().current_scene
	var inbound: bool = mgr != null and mgr.has_method("is_missile_inbound") \
		and mgr.is_missile_inbound(self)
	if inbound and my_seat != -1:
		var lhud = occupants[my_seat].get("hud")
		if lhud != null and lhud.has_method("set_missile_warning"):
			lhud.set_missile_warning(true)
	for idx in occupants.size():
		var occ = occupants[idx]
		if occ == null:
			continue
		var hud = occ.get("hud")
		if hud != null and hud.has_method("update_aircraft_hud"):
			var is_pilot: bool = (idx == 0)
			var is_gunner: bool = (idx == 2 or idx == 3)
			var gun_idx := idx - 2 if is_gunner else -1
			hud.update_aircraft_hud({
				"kind": "helicopter",
				"name": heli_name,
				"seat_role": ("DOOR GUNNER (L)" if idx == 2 else ("DOOR GUNNER (R)" if idx == 3 else ("PILOT" if is_pilot else "PASSENGER"))),
				"speed": linear_velocity.length() * 3.6,
				"climb": linear_velocity.y,
				"alt": global_position.y,
				"throttle": collective,
				"engine": engine_power,
				"hp": hp,
				"max_hp": max_hp,
				"seats_free": free_seats,
				"seats_total": occupants.size(),
				"seats_map": seats_map,
				"my_seat": my_seat,
				"is_pilot": is_pilot,
				"is_gunner": is_gunner,
				"heat": mg_heat[gun_idx] if is_gunner else 0.0,
				"overheated": mg_overheated[gun_idx] if is_gunner else false,
				"grounded": is_grounded(),
				"can_walk_out": can_walk_out(),
			})

# --- Damage & destruction ---

var _last_hit_by: String = ""
var _last_hit_faction: String = ""

func take_damage(amount: float, attacker_name: String = "", _weapon_name: String = "", attacker_faction: String = "", _pos: Vector3 = Vector3.INF) -> float:
	# Server-authoritative damage: clients forward to the host, which owns
	# the single canonical hp and broadcasts the destruction event.
	var mgr = get_tree().current_scene
	if GlobalData.is_networked() and not multiplayer.is_server():
		if mgr is MultiplayerManager:
			mgr.request_vehicle_damage.rpc_id(1, String(get_path()), amount, attacker_name, _weapon_name, attacker_faction, _pos)
		return 0.0
	if is_destroyed:
		return 0.0
	hp = maxf(hp - amount, 0.0)
	if attacker_name != "":
		_last_hit_by = attacker_name
		_last_hit_faction = attacker_faction
	if mgr is MultiplayerManager and GlobalData.is_networked():
		mgr.net_vehicle_hp.rpc(String(get_path()), hp) # keep pilot HUD honest on every peer
	if hp <= 0.0:
		_explode(_last_hit_by, _last_hit_faction)
	return amount

func _explode(attacker_name: String = "", attacker_faction: String = "", kill_occupants: bool = true) -> void:
	if is_destroyed:
		return
	is_destroyed = true
	var mgr = get_tree().current_scene
	if GlobalData.is_networked() and multiplayer.is_server() and mgr is MultiplayerManager:
		mgr.net_vehicle_explode.rpc(String(get_path()), attacker_name, attacker_faction)
	_notify_release()
	_update_active_camera(-1)
	# Crash kills credit whoever shot the heli down (fall back to the vehicle name)
	var crash_killer := _last_hit_by if _last_hit_by != "" else attacker_name
	var crash_fac := _last_hit_faction if _last_hit_faction != "" else attacker_faction
	for i in occupants.size():
		var occ = occupants[i]
		if occ == null:
			continue
		occupants[i] = null
		var side := 3.0 if seats[i].position.x >= 0.0 else -3.0
		var exit_pos := seats[i].global_position + global_basis * Vector3(side, 1.2, 0.0)
		occ.exit_aircraft(exit_pos, -global_basis.z, Vector3.UP * 8.0 + linear_velocity * 0.5)
		if kill_occupants:
			occ.take_damage(9999.0, crash_killer, "Helicopter Crash", crash_fac if crash_fac != "" else "World", global_position)
	if kill_occupants:
		_blast_area(global_position, 16.0, 320.0, 80.0, attacker_name, attacker_faction)
	AircraftOrdnance.spawn_blast_visual(global_position, 16.0)
	destroyed.emit()
	queue_free()

func _on_impact(body: Node) -> void:
	if is_destroyed:
		return
	# Passengers or infantry touching the airframe must never explode it
	if body == null or body.is_in_group("player") or body is CharacterBody3D:
		return
	if body == _last_bailed_pilot:
		return
	for occ in occupants:
		if body == occ: return
	if _is_abandoned and _pilotless_time >= bail_power_loss_delay:
		_explode()
		return
	var speed := linear_velocity.length()
	# Parked / engineless heli: contact bumps and solver spikes are not crashes
	if engine_power <= 0.01 and not _is_abandoned:
		return
	# Hard crash: excessive vertical speed or inverted impact
	if (speed > 16.0 and global_basis.y.dot(Vector3.UP) < 0.3) or speed > 32.0:
		_explode()

func _blast_area(pos: Vector3, radius: float, center_dmg: float, outer_dmg: float, att_name: String, att_fac: String) -> void:
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
		if collider in hit or collider == _last_bailed_pilot:
			continue
		hit.append(collider)
		var dist: float = pos.distance_to(collider.global_position)
		var dmg: float = AircraftOrdnance.compute_blast_damage(dist, radius, center_dmg, outer_dmg)
		if dmg > 0.0:
			collider.take_damage(dmg, att_name if att_name != "" else heli_name, "Helicopter Explosion", att_fac if att_fac != "" else "World", pos)
