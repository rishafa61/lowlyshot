extends Node3D
## Hunter Drone — Wraith operator skill (Recon).
## Chases the nearest valid enemy, hovers above them, then fires one EMP
## pulse that briefly locks the victim's controls (no damage).
## The owner peer runs the real stun; net replicas simulate the same chase
## visually only (same pattern as shockwave_pulse / auto_turret).

@export var acquire_radius: float = 15.0
@export var hover_height: float = 1.5 # above target origin (~head level)
@export var flight_time: float = 8.0  # hard expiry, never outlives this
@export var lock_delay: float = 1.0   # hover time before the pulse
@export var stun_duration: float = 1.2
@export var move_speed: float = 9.0

var owner_player: Node3D = null
var faction: String = "Ally"
var owner_name: String = "Player"
## Set by MultiplayerManager on non-owner peers: visual replica (applies no stun)
var is_net_replica: bool = false

var target: Node3D = null
var _state: String = "launch" # launch | hunt | chase | lock | zapped
var _life: float = 0.0
var _state_time: float = 0.0
var _scan_cd: float = 0.0
var _rotors: Array[Node] = []

@onready var status_light: OmniLight3D = $StatusLight
@onready var zap_light: OmniLight3D = $ZapLight
@onready var lock_beam: MeshInstance3D = $LockBeam

const COL_IDLE := Color(0.55, 1.0, 0.7)   # green: scanning
const COL_LOCK := Color(1.0, 0.25, 0.2)   # red: target acquired

func _ready() -> void:
	add_to_group("hunter_drones")
	for c in get_children():
		if String(c.name).begins_with("Rotor"):
			_rotors.append(c)
	status_light.light_color = COL_IDLE

func setup(player: Node3D) -> void:
	owner_player = player
	var p_team := _team_of(player)
	faction = "Ally" if p_team == "attackers" else "Enemy"
	owner_name = str(player.get("player_name")) if player.get("player_name") != null else "Player"
	# Immediately acquire nearest target if available
	call_deferred("_initial_acquire")

func _initial_acquire() -> void:
	if target != null or not is_instance_valid(owner_player):
		return
	target = _find_target()
	if target != null:
		status_light.light_color = COL_LOCK
		_set_state("chase")

func _process(delta: float) -> void:
	for r in _rotors:
		r.rotate_y(delta * 40.0)

func _physics_process(delta: float) -> void:
	_life += delta
	_state_time += delta
	if _life >= flight_time:
		queue_free() # flight budget spent — expires with or without a stun
		return
	match _state:
		"launch":
			# Rise and actively seek target
			_move_toward(_home_pos(), delta)
			target = _find_target()
			if target != null:
				status_light.light_color = COL_LOCK
				_set_state("chase")
			elif _state_time > 0.5:
				_set_state("hunt")
		"hunt":
			# No valid enemy yet: orbit the operator, rescan, never stun anyone
			_move_toward(_home_pos(), delta)
			_scan_cd -= delta
			if _scan_cd <= 0.0:
				_scan_cd = 0.25
				target = _find_target()
				if target != null:
					status_light.light_color = COL_LOCK
					_set_state("chase")
		"chase":
			if not _target_valid():
				queue_free() # target died/left — safe removal, no stun
				return
			_move_toward(_hover_point(), delta)
			_face_target(delta)
			if global_position.distance_to(_hover_point()) < 0.8:
				_set_state("lock")
		"lock":
			if not _target_valid():
				queue_free()
				return
			var dest := _hover_point()
			dest.y += sin(_life * 6.0) * 0.1 # hover bob while locking on
			_move_toward(dest, delta)
			_face_target(delta)
			_update_beam()
			if _state_time >= lock_delay:
				_zap()
		"zapped":
			pass # brief linger, freed below
	if _state == "zapped" and _state_time > 0.3:
		target = null
		queue_free()

func _set_state(s: String) -> void:
	_state = s
	_state_time = 0.0

func _home_pos() -> Vector3:
	# Orbit point above the operator (or in place if the owner is gone)
	if owner_player and is_instance_valid(owner_player):
		return owner_player.global_position + Vector3.UP * 2.2
	return global_position

func _hover_point() -> Vector3:
	return target.global_position + Vector3.UP * hover_height

func _target_valid() -> bool:
	return target != null and is_instance_valid(target) \
		and target.get("is_dead") != true \
		and global_position.distance_to(target.global_position) < acquire_radius * 1.6

func _team_of(n: Node) -> String:
	if not n: return ""
	var t = n.get("snd_team")
	if t != null and str(t) != "":
		return str(t)
	var pt = n.get("team")
	if pt != null and str(pt) != "":
		return str(pt)
	return ""

func _faction_of(n: Node) -> String:
	if not n: return ""
	if n.is_in_group("ally"): return "Ally"
	if n.is_in_group("enemy"): return "Enemy"
	var t := _team_of(n)
	if t == "attackers": return "Ally"
	if t == "defenders": return "Enemy"
	return ""

func _find_target() -> Node3D:
	var origin: Vector3 = owner_player.global_position if (owner_player and is_instance_valid(owner_player)) else global_position
	var best: Node3D = null
	var best_d := acquire_radius
	var seen := {}
	for group in ["player", "enemy", "ally"]:
		for n in get_tree().get_nodes_in_group(group):
			if seen.has(n) or not (n is Node3D):
				continue
			seen[n] = true
			if not _is_valid_enemy(n):
				continue
			var d: float = origin.distance_to(n.global_position)
			if d < best_d:
				best_d = d
				best = n
	return best

func _is_valid_enemy(n: Node) -> bool:
	if n == null or not is_instance_valid(n) or n == owner_player:
		return false
	if n.get("is_dead") == true:
		return false
	if not (n.is_in_group("player") or n.is_in_group("enemy") or n.is_in_group("ally")):
		return false

	var gd = get_node_or_null("/root/GlobalData")
	if gd and gd.has_method("is_ffa_mode") and gd.is_ffa_mode():
		return true # FFA: everyone hostile to everyone

	var my_team := _team_of(owner_player)
	var target_team := _team_of(n)

	# FFA team prefix check ("ffa_1", "ffa_2")
	if my_team.begins_with("ffa") or target_team.begins_with("ffa"):
		return target_team != my_team

	# Explicit team match (Search & Destroy, Team Deathmatch, Ground War)
	if my_team != "" and target_team != "":
		return target_team != my_team

	# Faction fallback when teams are undefined (bots / test maps)
	var target_faction := _faction_of(n)
	if target_faction != "" and faction != "":
		return target_faction != faction

	# Legacy deathmatch / test arena fallback: enemy group vs player
	if n.is_in_group("enemy"):
		return owner_player == null or not owner_player.is_in_group("enemy")
	if n.is_in_group("ally"):
		return owner_player != null and owner_player.is_in_group("enemy")

	return false

## Flight with obstacle detour: rotate the desired heading sideways until the
## ray ahead is clear, climb forward as last resort (drone has no physics body).
var _detour_sign: float = 0.0

func _move_toward(dest: Vector3, delta: float) -> void:
	var step := dest - global_position
	var dist := step.length()
	if dist < 0.01:
		return
	var dir := step / dist
	var travel := minf(move_speed * delta, dist)
	dir = _detour(dir)
	global_position += dir * travel

func _detour(dir: Vector3) -> Vector3:
	var excludes: Array[RID] = []
	if owner_player:
		excludes.append(owner_player.get_rid())
	if target and target is CollisionObject3D:
		excludes.append(target.get_rid())

	# Direct path clear? Reset bias, go straight
	var q_direct := PhysicsRayQueryParameters3D.create(global_position, global_position + dir * 1.5)
	q_direct.exclude = excludes
	if get_world_3d().direct_space_state.intersect_ray(q_direct).is_empty():
		return dir

	# 1. Slide along the wall surface (tangent to normal) in the chosen detour direction
	var q_hit := PhysicsRayQueryParameters3D.create(global_position, global_position + dir * 2.0)
	q_hit.exclude = excludes
	var h := get_world_3d().direct_space_state.intersect_ray(q_hit)
	if h:
		var n: Vector3 = h.normal
		# Wall tangent perpendicular to both normal and UP
		var wall_tan := n.cross(Vector3.UP).normalized()
		# Determine sign that moves toward dest projected on tangent
		var to_dest := (target.global_position - global_position).normalized() if target else dir
		if _detour_sign == 0.0:
			_detour_sign = 1.0 if to_dest.dot(wall_tan) >= 0.0 else -1.0
		var chosen_tan := wall_tan * _detour_sign
		# Cast slightly away from wall along tangent
		var side_step := (chosen_tan * 0.95 + n * 0.1).normalized()
		var q_tan := PhysicsRayQueryParameters3D.create(global_position, global_position + side_step * 1.5)
		q_tan.exclude = excludes
		if get_world_3d().direct_space_state.intersect_ray(q_tan).is_empty():
			return side_step
		# Blocked this way: try opposite tangent once
		var opp_step := -side_step
		var q_opp := PhysicsRayQueryParameters3D.create(global_position, global_position + opp_step * 1.5)
		q_opp.exclude = excludes
		if get_world_3d().direct_space_state.intersect_ray(q_opp).is_empty():
			_detour_sign *= -1.0
			return opp_step

	# 2. Sweep angles biased by detour sign
	for deg in [60, 90, 120, 150]:
		for s in [_detour_sign, -_detour_sign]:
			var d: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(deg * s)).normalized()
			var q := PhysicsRayQueryParameters3D.create(global_position, global_position + d * 1.5)
			q.exclude = excludes
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				return d
	return Vector3.UP # fully enclosed: rise

func _face_target(delta: float) -> void:
	var d := target.global_position - global_position
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), delta * 6.0)

func _update_beam() -> void:
	if target == null or not is_instance_valid(target):
		lock_beam.visible = false
		return
	var to: Vector3 = target.global_position + Vector3.UP * 1.4
	var dist := global_position.distance_to(to)
	if dist < 0.25:
		lock_beam.visible = false
		return
	lock_beam.visible = true
	lock_beam.global_position = global_position.lerp(to, 0.5)
	lock_beam.look_at(to, Vector3.UP)
	lock_beam.rotate_object_local(Vector3.RIGHT, -PI / 2.0) # cylinder Y axis onto the beam line
	lock_beam.scale.y = dist

func _zap() -> void:
	_set_state("zapped")
	lock_beam.visible = false
	# Electric pulse: cyan light flash + spark burst (every peer's drone plays this)
	zap_light.light_energy = 6.0
	var tw := create_tween()
	tw.tween_property(zap_light, "light_energy", 0.0, 0.25)
	_spawn_sparks()
	if is_net_replica:
		return # visual replica: the owning peer applies the real stun
	if target and is_instance_valid(target):
		if target.has_method("drone_stun"):
			target.drone_stun(stun_duration) # players: full control lock
		elif target.has_method("stun"):
			target.stun(stun_duration) # bots: classic stun
	target = null # one pulse per drone; refs cleared immediately

func _spawn_sparks() -> void:
	if target == null or not is_instance_valid(target):
		return
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 12
	p.lifetime = 0.35
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -9.8, 0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.4, 0.9, 1.0)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.emission_enabled = true
	sm.emission = Color(0.4, 0.9, 1.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.03, 0.03)
	mesh.material = sm
	p.mesh = mesh
	get_tree().root.add_child(p)
	p.global_position = target.global_position + Vector3.UP * 1.2
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(p.queue_free)
