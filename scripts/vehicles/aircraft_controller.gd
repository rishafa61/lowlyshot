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
const GATLING_BLAST_RADIUS := 8.0 ## same burst area as an AGM-65 missile
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

# --- Network puppet ---
var _net_puppet := false
var _net_target_pos := Vector3.ZERO
var _net_target_quat := Quaternion.IDENTITY
var _net_target_vel := Vector3.ZERO
var _net_send_timer := 0.0

func _net_send_state(delta: float) -> void:
	_net_send_timer += delta
	if _net_send_timer < 0.05:
		return
	_net_send_timer = 0.0
	var mgr = get_tree().current_scene
	if mgr and mgr.has_method("send_vehicle_state"):
		mgr.send_vehicle_state(String(get_path()), global_position, global_basis.get_euler(), linear_velocity, throttle)

func _notify_release() -> void:
	var mgr = get_tree().current_scene
	if mgr and mgr.has_method("send_vehicle_release"):
		mgr.send_vehicle_release(String(get_path()))

func net_set_target(pos: Vector3, rot: Vector3, vel: Vector3, thr: float = 0.0) -> void:
	if not pos.is_finite() or not rot.is_finite() or not vel.is_finite():
		return
	_net_puppet = true
	freeze = true
	_net_target_pos = pos
	var b := Basis.from_euler(rot)
	if b.is_finite():
		_net_target_quat = b.get_rotation_quaternion().normalized()
	_net_target_vel = vel
	throttle = thr if is_finite(thr) else 0.0

func net_release_puppet() -> void:
	_net_puppet = false
	freeze = false

@onready var pilot_seat: Marker3D = $PilotSeat
@onready var chase_pivot: Node3D = $ChasePivot
@onready var chase_arm: SpringArm3D = $ChasePivot/ChaseArm
@onready var chase_cam: Camera3D = $ChasePivot/ChaseArm/ChaseCamera
@onready var interact_area: Area3D = $InteractArea
@onready var muzzle: Node3D = $Model/GAU8_Cannon

# --- Airframe animation states (Aircraft.glb clips) ---
# Loops: Idle (parked / post-landing hold) and Fly (airborne default).
# One-shots, edge-triggered on altitude crossings so holding an altitude never
# re-fires them:
#   Take Off — climbs past TAKEOFF_ALT -> plays once -> Fly
#   Landing  — descends past LAND_ALT  -> plays once -> Idle (holds until the
#              next Take Off, even if still airborne under LAND_ALT)
const TAKEOFF_ALT := 100.0    ## meters AGL that trigger the takeoff clip
const LAND_ALT := 50.0        ## meters AGL that trigger the landing clip
const ANIM_CROSSFADE := 0.3
var _anim: AnimationPlayer = null
var _current_anim := ""
var _oneshot := ""            # "Take Off" / "Landing" while its one-shot runs
var _was_takeoff_alt := false # altitude latch (rising-edge detector)
var _was_land_alt := false
var _post_landing := false    # after Landing finishes: hold Idle over Fly

func _setup_anim() -> void:
	var players := find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_anim = players[0] as AnimationPlayer
	# Idle/Fly loop (Fly/Idle are 1-frame pose clips that must keep playing —
	# a stopped player resets bones to rest); Take Off/Landing play once.
	# The imported library is shared between scene instances — rebuild per player.
	var lib := AnimationLibrary.new()
	for anim_name in ["Idle", "Fly", "Take Off", "Landing"]:
		if _anim.has_animation(anim_name):
			var a := (_anim.get_animation(anim_name) as Animation).duplicate()
			a.loop_mode = Animation.LOOP_NONE if (anim_name == "Take Off" or anim_name == "Landing") \
				else Animation.LOOP_LINEAR
			lib.add_animation(anim_name, a)
	if lib.get_animation_list().is_empty():
		_anim = null
		return
	if _anim.has_animation_library(""):
		_anim.remove_animation_library("")
	_anim.add_animation_library("", lib)
	_anim.animation_finished.connect(_on_anim_finished)
	# Seed the latches with the spawn altitude so a landing/takeoff doesn't
	# misfire on the first frame.
	var agl0 := _altitude_agl(true)
	_was_takeoff_alt = agl0 >= TAKEOFF_ALT
	_was_land_alt = agl0 <= LAND_ALT
	_current_anim = "Idle"
	_anim.play("Idle")

func _play_clip(target: String) -> void:
	if target == _current_anim:
		return
	_current_anim = target
	_anim.play(target, ANIM_CROSSFADE)

func _play_oneshot(target: String) -> void:
	_oneshot = target
	_play_clip(target)

func _on_anim_finished(anim_name: StringName) -> void:
	var sname := str(anim_name)
	if _oneshot == "Take Off" and sname.ends_with("Take Off"):
		_oneshot = ""
		_play_clip("Fly")
	elif _oneshot == "Landing" and sname.ends_with("Landing"):
		_oneshot = ""
		_play_clip("Idle")

## Never stop the player: with only one Mesh under a skeleton, stopping resets
## bones to the rest pose mid-flight.
func _update_anim(_delta: float) -> void:
	if _anim == null:
		return
	var agl := _altitude_agl(true)
	var grounded := _is_grounded()
	var high := agl >= TAKEOFF_ALT
	var low := agl <= LAND_ALT
	# Rising edge past TAKEOFF_ALT: one takeoff clip, then Fly.
	if high and not _was_takeoff_alt:
		_was_takeoff_alt = true
		_was_land_alt = low
		_post_landing = false
		_play_oneshot("Take Off")
		return
	_was_takeoff_alt = high
	# Falling edge past LAND_ALT (in the air): one landing clip, then Idle hold.
	if low and not _was_land_alt and not grounded and _oneshot != "Take Off":
		_was_land_alt = true
		_post_landing = true
		_play_oneshot("Landing")
		return
	_was_land_alt = low
	if _oneshot != "":
		return # one-shot owns the player until animation_finished swaps it
	if grounded:
		_play_clip("Idle")
	elif _post_landing:
		_play_clip("Idle")
	else:
		_play_clip("Fly")

# Camera roll lag for smooth, flowing bank feeling
var _cam_fwd: Vector3 = Vector3.FORWARD
var _cam_up: Vector3 = Vector3.UP
var _cam_look_back: bool = false
var _cam_pos: Vector3 = Vector3.ZERO
var _last_vel: Vector3 = Vector3.ZERO
var _accel_smooth: float = 0.0

# AGM-65 missile vehicle lock-on (same mechanism as AT4 launcher)
const LOCK_MAX_PIXEL_DIST: float = 240.0
const LOCK_HOLD_TIME: float = 1.4 ## seconds to acquire lock
var _current_lock_target: Node3D = null
var _lock_timer: float = 0.0
var _locked_target: Node3D = null

func _ready() -> void:
	gravity_scale = 0.0 # gravity is applied manually so lift can counteract it
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_impact)
	hp = max_hp
	if chase_cam != null:
		chase_cam.current = false
	if chase_pivot != null:
		chase_pivot.top_level = true
		_cam_fwd = -global_basis.z
		_cam_up = global_basis.y
	chase_arm.add_excluded_object(get_rid())
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)
	_setup_anim()

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
		var mgr = get_tree().current_scene
		if GlobalData.is_networked() and mgr is MultiplayerManager and active_pilot != null \
				and active_pilot.get_multiplayer_authority() == multiplayer.get_unique_id():
			mgr.request_vehicle_exit.rpc_id(1, String(get_path()), 0)
		else:
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
		# Engine audio for observers
		if throttle > 0.02 and _engine_sfx == null:
			_engine_sfx = Sfx.loop3d("jet", self, 15.0, 150.0, 2.0)
		elif throttle <= 0.02 and _engine_sfx != null:
			Sfx.stop_loop(_engine_sfx)
			_engine_sfx = null
		if _engine_sfx:
			_engine_sfx.volume_db = lerpf(-24.0, 2.0, throttle)
		_update_camera_lag(delta)
		_update_missile_lock(delta)
		return

	_flash_timer = maxf(0.0, _flash_timer - delta)
	if selected_slot == OrdnanceSlot.MISSILE and _locked_target != null and (not is_instance_valid(_locked_target) or _locked_target.get("is_destroyed") == true):
		_update_missile_lock_reset()
	if active_pilot == null and _prompt_player != null \
			and Input.is_action_just_pressed("vehicle_interact"):
		var mgr = get_tree().current_scene
		if GlobalData.is_networked() and mgr is MultiplayerManager:
			mgr.request_vehicle_enter.rpc_id(1, String(get_path()))
		else:
			_enter(_prompt_player)
	var grounded := _is_grounded()
	_update_camera_lag(delta)
	_update_missile_lock(delta)
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
		var local_pilot: bool = active_pilot.get("hud") != null
		if local_pilot:
			_net_send_state(delta)
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
	_update_anim(delta)
	_update_pilot_hud()

func _console_open() -> bool:
	if active_pilot == null:
		return false
	var hud = active_pilot.get("hud")
	if hud != null and hud.console_visible:
		return true
	var pause = active_pilot.get_node_or_null("PauseMenu")
	return pause != null and pause.visible

# --- Enter / exit / eject ---

func _on_body_entered(body: Node3D) -> void:
	if active_pilot != null or not body.is_in_group("player") or body.get("is_piloting") == true:
		return
	var hud = body.get("hud")
	if hud == null:
		return # remote puppet
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
			if active_pilot == null and hud.has_method("hide_hover_name"):
				hud.hide_hover_name()

func has_free_seat() -> bool:
	return active_pilot == null and not is_destroyed

func net_sync_enter(pilot: Node3D, _seat_idx: int = 0) -> void:
	if active_pilot != null or is_destroyed:
		return
	active_pilot = pilot
	_is_ejected = false
	_pilotless_time = 0.0
	_last_ejected_pilot = null
	_prompt_player = null
	var hud = pilot.get("hud")
	if hud != null and hud.has_method("hide_enter_prompt"):
		hud.hide_enter_prompt()
	_pitch_vel = 0.0
	_yaw_vel = 0.0
	_pilot_name = str(pilot.get("player_name")) if pilot.get("player_name") != null else "Pilot"
	var team = str(pilot.get("team"))
	_pilot_faction = "Ally" if team == "attackers" else "Enemy"
	pilot.enter_aircraft(pilot_seat)
	var is_local := pilot.get("hud") != null
	if chase_cam != null and is_local:
		chase_cam.current = true
	pilot_entered.emit(pilot)

func net_sync_exit(_seat_idx: int = 0) -> void:
	if active_pilot == null:
		return
	_try_exit()

func net_sync_explode(attacker_name: String, attacker_faction: String) -> void:
	# Client copy: eject bodies + visuals only — host already registered the kills.
	if is_destroyed:
		return
	if attacker_name != "":
		_last_hit_by = attacker_name
		_last_hit_faction = attacker_faction
	_explode(false)

func _enter(pilot: Node3D) -> void:
	if active_pilot != null:
		return
	net_sync_enter(pilot, 0)

func _try_exit() -> void:
	var pilot := active_pilot
	active_pilot = null
	chase_cam.current = false # player.exit_aircraft restores the player camera
	_update_missile_lock_reset()
	_notify_release()
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
	# Reverse taxi: throttle idle + S backs the jet up on the ground
	if grounded and throttle <= 0.01 and active_pilot != null \
			and not _console_open() and Input.is_action_pressed("move_backward"):
		if fwd_speed > -8.0: # reverse speed cap (~29 km/h)
			apply_central_force(-forward * max_thrust * 0.35 * mass)
	# Gravity (gravity_scale = 0, applied manually) — natural 1.0G, no cartoon multiplier
	apply_central_force(Vector3.DOWN * GRAVITY * mass)
	# Lift along the airframe's up: climbs when the nose rises, bleeds in banks.
	# Dead-stick: lift smoothly decays over 2.5 seconds as energy bleeds.
	var lift_mult := 1.0
	if _is_ejected and _pilotless_time > PILOTLESS_CUTOFF_DELAY:
		lift_mult = maxf(0.0, 1.0 - (_pilotless_time - PILOTLESS_CUTOFF_DELAY) * 0.4)
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
			# Dead-stick: aerodynamic weather-vaning. The airframe gently aligns
			# with its ACTUAL flight path (velocity) instead of a fake pitch-down
			# torque — it keeps its momentum and glides into a stable dive along
			# its trajectory rather than tumbling nose-first like a cartoon anvil.
			var speed := linear_velocity.length()
			var vel_dir := linear_velocity / maxf(speed, 0.001)
			if speed > 4.0 and absf(vel_dir.dot(Vector3.UP)) < 0.98:
				# not vertical yet: settle toward the velocity vector (heading preserved)
				var target := Basis.looking_at(vel_dir, Vector3.UP)
				if target.is_finite() and global_transform.basis.is_finite():
					var nb := global_transform.basis.slerp(target, 1.0 - exp(-1.5 * delta))
					if nb.is_finite():
						global_transform.basis = nb.orthonormalized()
			angular_velocity = angular_velocity.lerp(Vector3.ZERO, 1.0 - exp(-4.0 * delta))
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
			if level.is_finite() and global_transform.basis.is_finite():
				var nb := global_transform.basis.slerp(level, 1.0 - exp(-4.0 * delta))
				if nb.is_finite():
					global_transform.basis = nb.orthonormalized()
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
		# HEI shells burst on impact: missile-sized blast AREA (8 m, AGM-65),
		# gatling-level damage falloff. Direct target already took its damage.
		_gatling_splash(hit_pos, target)
	_spawn_spark(hit_pos, hit.normal if hit else Vector3.UP, true)
	var start := muzzle.global_position + global_basis * Vector3(0, 0, -1.0)
	Sfx.pool_fire3d("rifle_single", self, 18.0, 160.0, 3.0)
	var mgr = get_tree().current_scene
	if GlobalData.is_networked() and mgr is MultiplayerManager:
		mgr.send_tracer(start, hit_pos, 0.14, false) # fat gatling tracer, all peers
	elif active_pilot != null and active_pilot.has_method("create_tracer"):
		active_pilot.create_tracer(start, hit_pos, 0.14) # fat tracer: visible at 100+ m/s

func _gatling_splash(pos: Vector3, direct_hit: Object) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = GATLING_BLAST_RADIUS
	query.shape = sphere
	query.transform = Transform3D(Basis(), pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit: Array = []
	var gave_marker := false
	for res in space.intersect_shape(query, 24):
		var col = res.collider
		if col == null or col == self or col == direct_hit:
			continue
		if not (col as Object).has_method("take_damage") or col in hit:
			continue
		hit.append(col)
		var dist: float = pos.distance_to(col.global_position)
		var dmg: float = AircraftOrdnance.compute_blast_damage(
			dist, GATLING_BLAST_RADIUS, GATLING_DMG, GATLING_DMG * 0.4)
		if dmg > 0.0:
			col.take_damage(dmg, _pilot_name, "GAU-8 HEI", _pilot_faction, pos)
			if not gave_marker and active_pilot != null and col.is_in_group("enemy"):
				var hud = active_pilot.get("hud")
				if hud:
					hud.show_hit_marker(dmg)
					gave_marker = true

func _spawn_spark(pos: Vector3, normal: Vector3, explosive: bool = false) -> void:
	var p := CPUParticles3D.new()
	p.amount = 22 if explosive else 14
	p.lifetime = 0.35 if explosive else 0.25
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = normal if normal.length_squared() > 0.1 else Vector3.UP
	p.spread = 60.0 if explosive else 45.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 18.0
	p.gravity = Vector3(0, -18.0, 0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.18, 0.18, 0.18) if explosive else Vector3(0.08, 0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.1) if explosive else Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.05) if explosive else Color(1.0, 0.7, 0.1)
	mat.emission_energy_multiplier = 6.0
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
	# Locked onto a vehicle in the crosshair? Home in (AT4-style). No lock = fly straight.
	var locked := _locked_target if (_locked_target != null and is_instance_valid(_locked_target)) else null
	if locked != null:
		dir = (locked.global_position + Vector3(0, 0.8, 0) - pos).normalized()
	var missile := AircraftOrdnance.spawn_missile(pos, dir, _pilot_name, _pilot_faction, self, locked)
	get_tree().current_scene.add_child(missile)
	# Replicate visual missile to every peer (damage stays shooter-authoritative)
	var mgr = get_tree().current_scene
	if GlobalData.is_networked() and mgr is MultiplayerManager:
		mgr.send_ordnance("missile", pos, missile.linear_velocity,
			String(locked.get_path()) if locked != null and is_instance_valid(locked) else "",
			_pilot_name, _pilot_faction)
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
	# Replicate visual bomb to every peer
	var mgr = get_tree().current_scene
	if GlobalData.is_networked() and mgr is MultiplayerManager:
		mgr.send_ordnance("bomb", pos, bomb.linear_velocity, "", _pilot_name, _pilot_faction)
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

var _last_hit_by: String = ""
var _last_hit_faction: String = ""

func take_damage(amount: float, attacker_name: String = "", _weapon_name: String = "", attacker_faction: String = "", _attacker_pos: Vector3 = Vector3.INF) -> float:
	# Server-authoritative damage: clients forward to the host, which owns
	# the single canonical hp and broadcasts the destruction event.
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
	Sfx.stop_loop(_engine_sfx)
	_engine_sfx = null
	_update_missile_lock_reset()
	if is_destroyed:
		return
	is_destroyed = true
	var mgr = get_tree().current_scene
	if GlobalData.is_networked() and multiplayer.is_server() and mgr is MultiplayerManager:
		var crash_killer := _last_hit_by if _last_hit_by != "" else "Aircraft"
		var crash_fac := _last_hit_faction if _last_hit_faction != "" else "World"
		mgr.net_vehicle_explode.rpc(String(get_path()), crash_killer, crash_fac)
	_notify_release()
	var pilot := active_pilot
	active_pilot = null
	if chase_cam != null:
		chase_cam.current = false
	if pilot != null:
		# Pilot still seated: thrown from the wreck and killed by the blast.
		# Ejected pilots are already clear and take none of this.
		var fwd := -global_basis.z
		pilot.exit_aircraft(global_position + Vector3.UP * 2.0, fwd)
		if kill_occupants:
			var crash_killer := _last_hit_by if _last_hit_by != "" else "Aircraft"
			var crash_fac := _last_hit_faction if _last_hit_faction != "" else "World"
			pilot.take_damage(9999.0, crash_killer, "Aircraft Crash", crash_fac, global_position)
	if kill_occupants:
		_blast_area(global_position, 18.0, 300.0, 60.0)
	_spawn_blast_visual(global_position, 18.0)
	destroyed.emit()
	queue_free()

func _on_impact(body: Node) -> void:
	if is_destroyed:
		return
	# Infantry touching the airframe must never explode the jet
	if body == null or body is CharacterBody3D:
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

## Chase camera: position hard-follows the plane, but orientation eases in —
## forward/pitch track quickly, roll lags so banking feels like the plane is
## flowing through the turn instead of rigidly welded to the airframe.
func _update_camera_lag(delta: float) -> void:
	if chase_pivot == null:
		return
	var pos_target := global_position + global_basis * Vector3(0.0, 5.2, 0.0)
	if not chase_cam.current:
		# Camera not driven: snap to the airframe so the next occupant starts clean
		_cam_fwd = -global_basis.z
		_cam_up = global_basis.y
		_cam_look_back = false
		_cam_pos = pos_target
		_last_vel = linear_velocity
		chase_pivot.global_position = _cam_pos
		chase_pivot.global_basis = global_basis
		return
	# V: snap-look behind the tail (instant flip, no lag on the switch)
	var look_back: bool = active_pilot != null and not _console_open() \
			and Input.is_action_pressed("camera_look_back")
	if look_back != _cam_look_back:
		_cam_look_back = look_back
		_cam_fwd = (global_basis.z if look_back else -global_basis.z).normalized()
		_cam_up = global_basis.y.normalized()
	var target_fwd := (global_basis.z if look_back else -global_basis.z).normalized()
	var target_up := global_basis.y.normalized()

	# POSITION: ease after the plane instead of welding to it. Steady flight
	# follows tight; hard acceleration deepens the lag so the airframe visibly
	# pulls ahead and the camera chases it down (accel feel).
	var accel := (linear_velocity - _last_vel) / maxf(delta, 0.001)
	_last_vel = linear_velocity
	var accel_mag := accel.length()
	_accel_smooth = lerpf(_accel_smooth, accel_mag, 1.0 - exp(-6.0 * delta))
	var accel_t := clampf(_accel_smooth / 30.0, 0.0, 1.0) # ~full lag at 30 m/s^2
	var w_pos := 1.0 - exp(-lerpf(14.0, 4.0, accel_t) * delta)
	_cam_pos = _cam_pos.lerp(pos_target, w_pos)
	chase_pivot.global_position = _cam_pos

	# ORIENTATION: pitch/yaw track fast, roll is the "flow"; both lag deeper
	# while the plane is turning over (roll rate) so swings read as fluid.
	var turn_t := clampf(angular_velocity.length() / 2.5, 0.0, 1.0)
	var w_track := 1.0 - exp(-lerpf(8.0, 3.0, turn_t) * delta)
	var w_roll := 1.0 - exp(-lerpf(3.5, 1.3, turn_t) * delta)
	_cam_fwd = _cam_fwd.lerp(target_fwd, w_track).normalized()
	_cam_up = _cam_up.lerp(target_up, w_roll).normalized()
	# Re-orthogonalize so the basis stays valid while roll lags
	var right := _cam_fwd.cross(_cam_up).normalized()
	if right.length_squared() < 0.01:
		right = global_basis.x.normalized()
	var up := right.cross(_cam_fwd).normalized()
	chase_pivot.global_basis = Basis(right, up, -_cam_fwd)

## AGM-65 lock-on: nearest vehicle inside the crosshair cone (screen-space,
## same mechanism as the AT4 launcher). No target = straight-flying missile.
func _update_missile_lock(delta: float) -> void:
	var hud = active_pilot.get("hud") if active_pilot != null else null
	if hud == null or selected_slot != OrdnanceSlot.MISSILE or chase_cam == null:
		_update_missile_lock_reset()
		return
	var vp_size := get_viewport().get_visible_rect().size
	var crosshair_center := vp_size * 0.5
	var best_target: Node3D = null
	var best_dist := LOCK_MAX_PIXEL_DIST
	# Sticky tracking: keep latching the current target while it stays in range
	if _current_lock_target and is_instance_valid(_current_lock_target) and _current_lock_target.get("is_destroyed") != true:
		var cur_pos: Vector3 = _current_lock_target.global_position + Vector3(0, 0.8, 0)
		var cam_pos := chase_cam.global_position
		var to_cur := cur_pos - cam_pos
		if to_cur.dot(-chase_cam.global_basis.z) > 0.0:
			var cur_dist := chase_cam.unproject_position(cur_pos).distance_to(crosshair_center)
			if cur_dist <= LOCK_MAX_PIXEL_DIST:
				best_target = _current_lock_target
				best_dist = cur_dist
	for v in get_tree().get_nodes_in_group("vehicles"):
		if not is_instance_valid(v) or not (v is Node3D):
			continue
		if v.get("is_destroyed") == true:
			continue
		if v == self or v == _current_lock_target:
			continue
		var v_pos: Vector3 = v.global_position + Vector3(0, 0.8, 0)
		var to_v := v_pos - chase_cam.global_position
		if to_v.dot(-chase_cam.global_basis.z) <= 0.0:
			continue
		var screen_pos := chase_cam.unproject_position(v_pos)
		var dist := screen_pos.distance_to(crosshair_center)
		if dist <= best_dist:
			# Line of sight check
			var space := get_world_3d().direct_space_state
			var ray := PhysicsRayQueryParameters3D.create(chase_cam.global_position, v_pos)
			ray.exclude = [get_rid()]
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or hit.collider == v or (hit.collider is Node and (hit.collider as Node).get_parent() == v):
				best_dist = dist
				best_target = v
	if best_target != null:
		if _current_lock_target == best_target:
			_lock_timer = minf(_lock_timer + delta, LOCK_HOLD_TIME)
		else:
			_current_lock_target = best_target
			_lock_timer = 0.0
		_locked_target = best_target if _lock_timer >= LOCK_HOLD_TIME else null
		if hud.has_method("show_lock_indicator"):
			var target_screen_pos: Vector2 = chase_cam.unproject_position(best_target.global_position + Vector3(0, 0.8, 0))
			hud.show_lock_indicator(_lock_timer / LOCK_HOLD_TIME, _locked_target != null, target_screen_pos)
	else:
		_update_missile_lock_reset()

func _update_missile_lock_reset() -> void:
	_current_lock_target = null
	_locked_target = null
	_lock_timer = 0.0
	var hud = active_pilot.get("hud") if active_pilot != null else null
	if hud and hud.has_method("hide_lock_indicator"):
		hud.hide_lock_indicator()

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
	AircraftOrdnance.spawn_blast_visual(pos, radius)

# --- HUD ---

func _update_pilot_hud() -> void:
	if active_pilot == null:
		return
	var hud = active_pilot.get("hud")
	if hud == null:
		return
	# Incoming homing missile (AT4 / AGM-65 locked onto us): warning + beeps
	if hud.has_method("set_missile_warning"):
		var mgr = get_tree().current_scene
		var inbound: bool = mgr != null and mgr.has_method("is_missile_inbound") \
			and mgr.is_missile_inbound(self)
		hud.set_missile_warning(inbound)
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
		"alt": _altitude_agl(),
	})

var _alt_cache: float = 0.0
var _alt_timer: float = 0.0

## Height above ground (AGL): downward ray to terrain/rooftops, 800 m max.
## Perf: cached at 10 Hz — HUD text doesn't need a fresh 800 m ray every physics
## tick. Pass force=true when the value gates a state change (anim states).
func _altitude_agl(force: bool = false) -> float:
	_alt_timer -= get_physics_process_delta_time()
	if not force and _alt_timer > 0.0:
		return _alt_cache
	_alt_timer = 0.1
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * 800.0, ~0, [get_rid()])
	var hit := space.intersect_ray(query)
	_alt_cache = global_position.y if hit.is_empty() else global_position.y - hit.position.y
	return _alt_cache
