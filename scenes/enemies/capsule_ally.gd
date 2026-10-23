extends CharacterBody3D

@onready var visuals = $Visuals
@onready var body: HumanBody = $Visuals/Body
@onready var mesh: Node3D = $Visuals/Body # Compatibility alias for skills/overlays
@onready var weapon_holder = $Visuals/WeaponHolder
@onready var nav_agent = $NavigationAgent3D
@onready var eyes = $Eyes
@onready var collision_shape = $CollisionShape3D

@onready var hitboxes = [
	$Hitboxes/HeadBox,
	$Hitboxes/UpperBox,
	$Hitboxes/LowerBox
]
@onready var hitbox_shapes = [
	$Hitboxes/HeadBox/CollisionShape3D,
	$Hitboxes/UpperBox/CollisionShape3D,
	$Hitboxes/LowerBox/CollisionShape3D
]

var health_component: HealthComponent
var max_health: float:
	get: return health_component.max_health if health_component else 100.0
	set(val):
		if health_component: health_component.max_health = val
var health: float:
	get: return health_component.health if health_component else 100.0
	set(val):
		if health_component: health_component.health = val
var current_speed_mult = 1.0

var active_operator: EnemyOperator = null
var bot_name: String = ""
var snd_team: String = "" # "attackers"/"defenders" — stamped by the match manager
var spawn_protect_timer: float = 0.0
var _spawn_protect_origin: Vector3 = Vector3.ZERO
var last_attacker: String = ""
var last_attacker_faction: String = ""
var last_weapon: String = ""
var last_hit_part: String = ""
var available_operators = [
	preload("res://scripts/enemy_operators/assault.gd"),
	preload("res://scripts/enemy_operators/breacher.gd"),
	preload("res://scripts/enemy_operators/recon.gd"),
	preload("res://scripts/enemy_operators/sentry.gd"),
	preload("res://scripts/enemy_operators/wingman.gd")
]
var is_dead = false
var start_pos: Vector3
var respawn_timer = 0.0
@export var can_respawn: bool = true

# ---------------- Bot Replication ----------------
var is_net_puppet: bool = false
var net_id: int = -1
var net_weapon_id: String = ""
var _net_target_pos: Vector3 = Vector3.ZERO
var _net_target_yaw: float = 0.0

func net_set_target(pos: Vector3, yaw: float) -> void:
	_net_target_pos = pos
	_net_target_yaw = yaw

func net_play_death() -> void:
	if not is_net_puppet or is_dead:
		return
	is_dead = true
	for box in hitbox_shapes:
		box.set_deferred("disabled", true)
	collision_shape.set_deferred("disabled", true)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(visuals, "rotation:x", deg_to_rad(-90), 0.5).set_trans(Tween.TRANS_BOUNCE)
	tween.tween_property(visuals, "position:y", -0.5, 0.5)

## Host bot respawned: restore this puppet's visuals/collision (Ground War etc.)
func net_play_respawn() -> void:
	if not is_net_puppet:
		return
	is_dead = false
	for box in hitbox_shapes:
		box.set_deferred("disabled", false)
	collision_shape.set_deferred("disabled", false)
	visuals.rotation.x = 0
	visuals.position.y = 0

# Weapon Stats
var ammo = 30
var max_ammo = 30
var fire_cooldown = 0.0
var is_reloading = false
var reload_timer = 0.0
var equipped_primary = null
var primary_weapons = [
	{"scene": preload("res://scenes/weapons/main/ak47.tscn"), "dmg": 35.0, "fire_rate": 0.2, "mag": 30},
	{"scene": preload("res://scenes/weapons/main/m4a4.tscn"), "dmg": 33.0, "fire_rate": 0.18, "mag": 30},
	{"scene": preload("res://scenes/weapons/main/m700.tscn"), "dmg": 95.0, "fire_rate": 1.2, "mag": 5}
]

# Movement Stats — base values; operator speed_mult applied at runtime
var _sfx_move: AudioStreamPlayer3D = null
var _sfx_move_state := ""
# Soft mover state: shapecast sweep + ray floor snap (no move_and_slide)
var _grounded: bool = false
var _blocked: bool = false
var _block_normal: Vector3 = Vector3.ZERO
var _move_accum: float = 0.0
var _move_query := PhysicsShapeQueryParameters3D.new()
var _move_ready := false
var _nav_goal: Vector3 = Vector3.INF
const WALK_SPEED = 2.5
const RUN_SPEED = 5.5
const SLIDE_SPEED = 9.0
const CROUCH_HEIGHT = 1.0
const STAND_HEIGHT = 2.0
const STEP_HEIGHT = 0.5 # walkable rise the sweep clears; walls taller than this block

var is_crouching = false
var is_sliding = false
var slide_timer = 0.0
var roam_timer = 0.0
var skill_trigger_timer: float = 0.0 # Small delay before first skill use

var target: Node3D = null
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * 2.0

var stun_timer = 0.0
var is_stunned = false

func stun(duration: float):
	is_stunned = true
	stun_timer = duration
	
	# Solid unshaded white overlay for enemies when flashed
	var white_overlay = StandardMaterial3D.new()
	white_overlay.albedo_color = Color(1, 1, 1, 1)
	white_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body.set_overlay(white_overlay)

func reveal_silhouette():
	var outline = StandardMaterial3D.new()
	outline.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline.albedo_color = Color(1, 0, 0, 0.35)
	outline.emission_enabled = true
	outline.emission = Color(1, 0, 0, 1)
	outline.emission_energy_multiplier = 2.0
	outline.no_depth_test = true
	body.set_overlay(outline)
	var tween = create_tween()
	tween.tween_interval(5.0)
	tween.tween_callback(func(): body.clear_overlay())

func _ready():
	# Soft mover: body is script-driven only — invisible to other bodies' sweeps
	collision_layer = 0
	collision_mask = 0
	_hitbox_base_y.clear()
	for hb in hitboxes:
		_hitbox_base_y.append(hb.position.y)
	if bot_name == "":
		bot_name = GlobalData.get_random_bot_name()
	# Replicated puppets: visuals + collision only, no AI (host owns the sim)
	if is_net_puppet:
		_setup_puppet_bot()
		return
	# Assign an operator: manager-locked mode forces Vanguard (the healer)
	var forced_op := str(GlobalData.get("force_operator"))
	var op_script = null
	if forced_op != "":
		for cand in available_operators:
			if cand.new().op_name == forced_op:
				op_script = cand
				break
	if op_script == null:
		op_script = available_operators.pick_random()
	active_operator = op_script.new()
	add_child(active_operator)
	active_operator.setup(self)
	
	health_component = $HealthComponent
	health_component.setup(float(active_operator.max_health), 0.0)
	health_component.died.connect(die)
	current_speed_mult = active_operator.speed_mult
	
	start_pos = global_position
	floor_max_angle = deg_to_rad(78.0)
	floor_snap_length = 0.4
	_setup_nametag()
	
	# Tint ally mesh friendly cyan-blue
	body.set_tint(Color(0.2, 0.7, 0.9))
	
	# Target Enemies instead of Players
	_equip_random_primary()
	_find_nearest_enemy()
	_arm_spawn_protect()

func _setup_puppet_bot() -> void:
	health_component = $HealthComponent
	health_component.setup(100.0, 0.0) # host owns real health; visual only
	can_respawn = false
	start_pos = global_position
	_net_target_pos = global_position
	_net_target_yaw = rotation.y
	_setup_nametag()
	body.set_tint(Color(0.2, 0.7, 0.9))
	_equip_random_primary()

## Resolves a combatant's S&D team ("attackers"/"defenders"). Bots carry
## snd_team (stamped by the manager); players carry team. Returns "" outside
## team modes — callers fall back to legacy group logic then.
func _snd_side_of(n: Node) -> String:
	var t = n.get("snd_team")
	if t != null and str(t) != "":
		return str(t)
	var pt = n.get("team")
	if pt != null and str(pt) != "":
		return str(pt)
	return ""

func _find_nearest_enemy() -> void:
	var is_ffa: bool = GlobalData.is_ffa_mode()
	var my_team := str(get("snd_team"))
	var candidates: Array = get_tree().get_nodes_in_group("enemy")
	if my_team != "" or is_ffa:
		# Team modes / FFA: hostile = any live combatant (FFA skips same-team check below)
		candidates = get_tree().get_nodes_in_group("player") \
			+ get_tree().get_nodes_in_group("ally") + get_tree().get_nodes_in_group("enemy")
	var closest_dist = INF
	target = null
	for e in candidates:
		if e is Node3D and not e.get("is_dead") and e != self:
			if not is_ffa:
				if my_team != "":
					if _snd_side_of(e) == my_team:
						continue
				elif not e.is_in_group("enemy"):
					continue
			var d = global_position.distance_to(e.global_position)
			if d < closest_dist:
				closest_dist = d
				target = e

func _get_flagpoint() -> Node3D:
	var flags := get_tree().get_nodes_in_group("flagpoint")
	if flags.is_empty():
		return null
	return flags[0] as Node3D

func _equip_random_primary() -> void:
	# Clear any existing weapons
	for c in weapon_holder.get_children():
		c.queue_free()
	
	# Pick a primary weapon: obey manager / GlobalData forced_weapon_id first
	var primaries = GlobalData.weapons["Primary"]
	var w = null
	var forced_id: String = str(GlobalData.get("force_primary_id"))
	if forced_id != "":
		for cand in primaries:
			if cand["id"] == forced_id:
				w = cand
				break
	if w == null and net_weapon_id != "":
		for cand in primaries:
			if cand["id"] == net_weapon_id:
				w = cand
				break
	if w == null:
		w = primaries.pick_random()
	
	# Map weapon ID to scene path
	var scene_map = {
		"ak47": "res://scenes/weapons/main/ak47.tscn",
		"m4a4": "res://scenes/weapons/main/m4a4.tscn",
		"m700": "res://scenes/weapons/main/m700.tscn",
		"mp5": "res://scenes/weapons/main/mp5.tscn",
		"steyr_aug": "res://scenes/weapons/main/SteyrAUG.tscn",
		"rpd": "res://scenes/weapons/main/RPD.tscn",
		"remington_870": "res://scenes/weapons/main/remington_870.tscn"
	}
	
	var scene_path = scene_map.get(w["id"], "res://scenes/weapons/main/ak47.tscn")
	var scene = load(scene_path) as PackedScene
	if scene:
		var inst = scene.instantiate() as Node3D
		inst.name = w["id"]
		# Perf: weapon detail meshes fade out beyond 120 m — bots keep body silhouette
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			mi.visibility_range_end = 120.0
			mi.visibility_range_end_margin = 15.0
		weapon_holder.add_child(inst)
	
	equipped_primary = w
	max_ammo = w["mag"]
	ammo = max_ammo
	fire_cooldown = 0.0

func _get_operator_color(op: String) -> Color:
	match op:
		"Vanguard": return Color(0.4, 0.6, 1.0)   # Blue — healer
		"Shock":    return Color(1.0, 0.6, 0.1)   # Orange — shock
		"Ghost":    return Color(0.6, 1.0, 0.6)   # Green — recon
		"Sentry":   return Color(0.7, 0.7, 0.7)   # Gray — turret
		"Wingman":  return Color(1.0, 0.3, 0.3)   # Red — airstrike
	return Color(0.8, 0.8, 0.8)

var nametag: Label3D = null
var nametag_timer: float = 0.0

func _setup_nametag() -> void:
	nametag = Label3D.new()
	nametag.text = bot_name
	nametag.position = Vector3(0, 2.25, 0)
	nametag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nametag.no_depth_test = true
	nametag.modulate = Color(0.35, 0.85, 1.0)
	nametag.font_size = 28
	nametag.outline_size = 6
	nametag.visible = false
	add_child(nametag)

func show_nametag_briefly() -> void:
	if nametag:
		nametag.visible = true
		nametag_timer = 0.15

func _physics_process(delta):
	if nametag and nametag.visible:
		nametag_timer -= delta
		if nametag_timer <= 0.0:
			nametag.visible = false
	# Replicated puppet: just lerp toward host state, no AI
	if is_net_puppet:
		var t: float = min(1.0, delta * 10.0)
		global_position = global_position.lerp(_net_target_pos, t)
		rotation.y = lerp_angle(rotation.y, _net_target_yaw, t)
		return
		
	# Spawn protection countdown: cancelled once the bot actually moves
	if spawn_protect_timer > 0.0:
		spawn_protect_timer -= delta
		if global_position.distance_to(_spawn_protect_origin) > 0.5:
			spawn_protect_timer = 0.0

	if is_dead:
		if can_respawn:
			respawn_timer -= delta
			if respawn_timer <= 0.0:
				respawn()
				return # Don't do physics on the exact frame we respawn
		
		velocity.x = move_toward(velocity.x, 0, delta * 10.0)
		velocity.z = move_toward(velocity.z, 0, delta * 10.0)
		if not collision_shape.disabled:
			_soft_move(delta)
			
		return
		
	# Process stun
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0:
			is_stunned = false
			body.clear_overlay()
		
		# Keep applying gravity and simple friction while stunned, but no AI logic
		velocity.x = move_toward(velocity.x, 0, delta * 15.0)
		velocity.z = move_toward(velocity.z, 0, delta * 15.0)
		_soft_move(delta)
		return # Stops all AI pathfinding, targeting, and shooting!

	# Weapon Cooldowns
	if fire_cooldown > 0: 
		fire_cooldown -= delta
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0:
			ammo = max_ammo
			is_reloading = false
			print("Enemy reloaded!")
			
	# Slide Timer
	if is_sliding:
		slide_timer -= delta
		if slide_timer <= 0:
			is_sliding = false

	# Perf: stagger think + move — half the bots run ALL physics queries per tick
	# (AI, separation, sweep, floor ray). Accumulated delta keeps timers real-time.
	_move_accum += delta
	if (Engine.get_physics_frames() + int(get_instance_id() % 2)) % 2 == 0:
		var step := _move_accum
		_move_accum = 0.0
		process_ai(step)
		process_stance(step)
		# Push away from overlapping bots so they never clip through each other
		_apply_bot_separation()
		_soft_move(step)
		_step_up_if_needed()

	# Footstep / slide loops (positional, quieter with distance)
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var move_state := ""
	if is_sliding:
		move_state = "slide"
	elif _grounded and hspeed > 1.0:
		move_state = "run" if hspeed > WALK_SPEED * 1.4 else "walk"
	# Animation sync: idle / run / crouch / slide
	body.sync_movement(move_state != "", is_crouching and move_state == "", is_sliding, not _grounded)
	if move_state != _sfx_move_state:
		_sfx_move_state = move_state
		Sfx.stop_loop(_sfx_move)
		_sfx_move = null
		if move_state != "":
			_sfx_move = Sfx.loop3d(move_state, self, 3.0, 28.0, -8.0)

func _apply_bot_separation() -> void:
	for group_name in ["enemy", "ally"]:
		for b in get_tree().get_nodes_in_group(group_name):
			if b == self or not (b is CharacterBody3D) or not is_instance_valid(b):
				continue
			var diff: Vector3 = global_position - b.global_position
			diff.y = 0.0
			var d: float = diff.length()
			if d > 0.001 and d < 1.2:
				var push: float = (1.2 - d) * 3.5
				velocity += diff.normalized() * push

## Soft mover: capsule sweep (shapecast) + ray floor snap.
## No move_and_slide, no hard body contacts — bots pass through each other and
## players, slide along walls via the hit normal, and shove doors aside.
## Mask 1 = world geometry only; runs at half rate with the full accumulated dt.
func _soft_move(dt: float) -> void:
	if dt <= 0.0:
		return
	var space := get_world_3d().direct_space_state
	if not _move_ready:
		_move_ready = true
		_move_query.shape = collision_shape.shape
		_move_query.collision_mask = 1
		_move_query.exclude = [get_rid()]
	velocity.y -= gravity * dt
	var shape: Shape3D = collision_shape.shape
	var half_h: float = shape.height * 0.5 if shape is CapsuleShape3D else 0.9
	# Horizontal sweep lifted by STEP_HEIGHT: walkable rises (ramps, kerbs, lips
	# up to 0.5 m) pass under the query; the floor snap below re-lands the bot.
	# Walls taller than STEP_HEIGHT still block and slide as before.
	var remaining := Vector3(velocity.x, 0.0, velocity.z) * dt
	_blocked = false
	_block_normal = Vector3.ZERO
	for i in 2:
		if remaining.length_squared() < 1e-8:
			break
		_move_query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (half_h + STEP_HEIGHT))
		_move_query.motion = remaining
		var res = space.cast_motion(_move_query)
		var safe: float = res.x if res is Vector2 else res[0]
		global_position += remaining * safe
		if safe >= 0.9999:
			break
		var rest := space.get_rest_info(_move_query)
		if rest.is_empty():
			break
		var n: Vector3 = rest["normal"]
		# Doors / physics props: soft shove, keep going
		var col = instance_from_id(rest["collider_id"])
		if col is RigidBody3D:
			col.apply_central_impulse(-n * 1.5)
			if col.get_parent() and col.get_parent().has_method("register_interaction"):
				col.get_parent().register_interaction()
			global_position += remaining * 0.25
			break
		_blocked = true
		_block_normal = n
		var into := remaining.dot(n)
		if into < 0.0:
			remaining = (remaining - n * into) * 0.98
		else:
			break
	# Vertical: snap to floor when falling, free rise otherwise
	if velocity.y <= 0.0:
		var drop := -velocity.y * dt + STEP_HEIGHT + 0.05
		var fq := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 0.6, global_position + Vector3.DOWN * (0.6 + drop), 1, [get_rid()])
		var fh := space.intersect_ray(fq)
		if not fh.is_empty():
			global_position.y = fh.position.y
			velocity.y = 0.0
			_grounded = true
		else:
			_grounded = false
	else:
		global_position.y += velocity.y * dt
		_grounded = false

func _step_up_if_needed() -> void:
	# Mantle assist over spawn cliff (1.18 m) when blocked by a high ledge
	if not _blocked:
		return
	var fwd := -global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var step_target := global_position + Vector3.UP * 1.35 + fwd * 0.4
	var down_ray := PhysicsRayQueryParameters3D.create(
		step_target, step_target + Vector3.DOWN * 1.5,
		1, [get_rid()]
	)
	var hit := space.intersect_ray(down_ray)
	if not hit.is_empty() and hit.position.y > global_position.y:
		global_position = hit.position + Vector3.UP * 0.08


# Perf: line-of-sight cache — raycast at ~6.7 Hz instead of every think tick
var _los_timer: float = 0.0
var _los_cache: bool = false
# Hitbox Y positions at rest — crouch moves boxes instead of non-uniform scaling (Jolt rejects)
var _hitbox_base_y: Array[float] = []

func process_ai(delta):
	if not is_inside_tree():
		return
	# Periodically update target in case current target dies or gets out of range
	if randf() < 0.05:
		_find_nearest_enemy()

	# Cached line-of-sight: refresh at ~6.7 Hz, humans don't react faster anyway
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.15
		_los_cache = can_see_target()
	var sees_target = _los_cache
	
	if not target or target.get("is_dead") == true or not sees_target:
		# ROAM STATE
		is_crouching = false
		var flag := _get_flagpoint()
		roam_timer -= delta
		if roam_timer <= 0 or nav_agent.is_navigation_finished():
			var random_pos: Vector3
			if flag != null:
				# Objective play: rush the flag via the south ramp and fight over it
				random_pos = flag.global_position + Vector3(randf_range(-3.0, 3.0), 0.0, -randf_range(5.0, 15.0))
			else:
				if GlobalData.is_ffa_mode():
					# FFA: hunt a random live combatant so fights actually happen
					var cands := get_tree().get_nodes_in_group("player") \
						+ get_tree().get_nodes_in_group("enemy") \
						+ get_tree().get_nodes_in_group("ally")
					var alive: Array = []
					for c in cands:
						if c != self and c is Node3D and not c.get("is_dead"):
							alive.append(c)
					if not alive.is_empty():
						random_pos = (alive.pick_random() as Node3D).global_position
					else:
						random_pos = start_pos + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
				else:
					random_pos = start_pos + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
			_set_nav_goal(random_pos)
			roam_timer = randf_range(3.0, 6.0)
		# Sprint to the objective, walk once on it
		var spd := RUN_SPEED if (flag != null and global_position.distance_to(flag.global_position) > 15.0) else WALK_SPEED
		# Occasional slide while sprinting: burst of speed
		if spd > WALK_SPEED and _grounded and not is_sliding and randf() < 0.004:
			is_sliding = true
			slide_timer = 0.9
		if is_sliding:
			spd = SLIDE_SPEED
		move_along_path(spd * current_speed_mult, true)
	else:
		# COMBAT STATE
		var dist = global_position.distance_to(target.global_position)
		
		# Operator Skill AI Decision with initial delay for reliability
		skill_trigger_timer -= delta
		if active_operator and active_operator.current_cooldown <= 0 and skill_trigger_timer <= 0:
			# Vanguard heals when low on HP (< 70)
			# Shock uses pulse on nearby targets (dist < 15)
			# Sentry deploys turret at long-mid range (dist < 30)
			# Wingman calls airstrike from far/medium range (dist > 8)
			# Ghost fires sonar when not yet close (dist > 5)
			var should_use = false
			match active_operator.op_name:
				"Vanguard":
					if health < max_health * 0.7: should_use = true
				"Shock":
					if dist < 15.0: should_use = true
				"Sentry":
					if dist < 30.0: should_use = true
				"Wingman":
					if dist > 8.0: should_use = true
				"Ghost":
					if dist > 5.0: should_use = true
				_:
					should_use = randf() < 0.05
			
			if should_use:
				if active_operator.use_skill(target):
					# Add a small cooldown buffer so it doesn't double-fire
					skill_trigger_timer = 2.0
					print("Enemy %s used %s skill!" % [name, active_operator.skill_name])
		
		# Face Target
		var look_pos = target.global_position
		look_pos.y = global_position.y
		if global_position.distance_to(look_pos) > 0.1:
			look_at(look_pos, Vector3.UP)
		
		if ammo <= 0 and not is_reloading:
			is_reloading = true
			reload_timer = 2.0
			print("Enemy is reloading!")
		
		if is_reloading:
			is_crouching = true # Take cover/crouch while reloading
			move_along_path(WALK_SPEED * current_speed_mult, false)
		else:
			# Shoot within effective range — snipers engage far out in FFA modes
			var shoot_range := 25.0
			if GlobalData.is_ffa_mode() and equipped_primary:
				shoot_range = clampf(float(equipped_primary.get("rng", 25.0)), 25.0, 150.0)
			if dist <= shoot_range and fire_cooldown <= 0:
				shoot()

			if dist > 12.0:
				# CHASE - close the distance to optimal range
				is_crouching = false
				_set_nav_goal(target.global_position)
				
				# Randomly slide to close distance
				if randf() < 0.02 and not is_sliding and _grounded:
					is_sliding = true
					slide_timer = 1.2
					
				var base_spd = SLIDE_SPEED if is_sliding else RUN_SPEED
				move_along_path(base_spd * current_speed_mult, false)
			elif dist < 5.0:
				# RETREAT - step back slightly if player crowds
				is_crouching = false
				var retreat_dir = (global_position - target.global_position).normalized()
				retreat_dir.y = 0
				velocity.x = retreat_dir.x * (WALK_SPEED * current_speed_mult)
				velocity.z = retreat_dir.z * (WALK_SPEED * current_speed_mult)
			else:
				# OPTIMAL COMBAT RANGE (5-12m) - hold position, strafe or crouch
				velocity.x = move_toward(velocity.x, 0, delta * 20.0)
				velocity.z = move_toward(velocity.z, 0, delta * 20.0)
				
				# Randomly crouch for evasion
				if randf() < 0.02: is_crouching = !is_crouching

# Snap any goal onto the navmesh — off-mesh targets (crate/roof/air) make the
# path corridor query fail with "not find the most reachable polygons" spam.
# Re-path only when the goal moved > 1 m: one corridor query per leg, not per tick.
func _set_nav_goal(p: Vector3) -> void:
	var map: RID = nav_agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return # map not synced yet this session — skip, next tick will retry
	# Targets standing on roofs, crates, or parachuting would snap to isolated
	# navmesh polygons, producing "not find the most reachable polygons" corridor
	# breaks. Clamp the probe height near the bot's elevation before snapping.
	var probe := Vector3(p.x, clampf(p.y, global_position.y - 1.5, global_position.y + 2.5), p.z)
	var goal := NavigationServer3D.map_get_closest_point(map, probe)
	if goal.distance_to(_nav_goal) > 1.0:
		_nav_goal = goal
		nav_agent.target_position = goal

func move_along_path(speed: float, rotate_to_path: bool):
	var goal_dist: float = nav_agent.target_position.distance_to(global_position)
	if nav_agent.is_navigation_finished():
		if goal_dist < 1.5:
			velocity.x = move_toward(velocity.x, 0, 0.5)
			velocity.z = move_toward(velocity.z, 0, 0.5)
			return
		var fdir := global_position.direction_to(nav_agent.target_position)
		fdir.y = 0
		fdir = fdir.normalized()
		if rotate_to_path and fdir.length() > 0.1:
			look_at(global_position + fdir, Vector3.UP)
		velocity.x = fdir.x * speed
		velocity.z = fdir.z * speed
		return

	var next_pos = nav_agent.get_next_path_position()
	var dir = global_position.direction_to(next_pos)
	dir.y = 0
	dir = dir.normalized()

	if rotate_to_path and dir.length() > 0.1:
		var look_target = global_position + dir
		look_at(look_target, Vector3.UP)

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

func process_stance(delta):
	var target_height = STAND_HEIGHT
	var _target_scale = 1.0
	if is_crouching or is_sliding:
		target_height = CROUCH_HEIGHT
		_target_scale = 0.5
		
	if collision_shape.shape is CapsuleShape3D:
		var shape = collision_shape.shape as CapsuleShape3D
		shape.height = lerp(shape.height, target_height, delta * 8.0)
		collision_shape.position.y = shape.height / 2.0
		
		# Visually scale down the entire Visuals node to simulate crouching
		var current_scale = shape.height / STAND_HEIGHT
		visuals.scale.y = current_scale
		visuals.position.y = 0.0
		
		# Crouch drops hitboxes by moving them down — non-uniform scale is rejected by Jolt
		$Hitboxes.position.y = 0.0
		for i in hitboxes.size():
			hitboxes[i].position.y = _hitbox_base_y[i] * current_scale

func can_see_target() -> bool:
	if not is_inside_tree() or not is_instance_valid(target) or not target.is_inside_tree() or target.get("is_dead"): return false
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(eyes.global_position, target.global_position + Vector3(0, 1.0, 0))
	
	# Exclude the enemy's own body AND its own hitboxes so the ray doesn't hit itself!
	var excludes = [get_rid()]
	for b in hitboxes:
		excludes.append(b.get_rid())
	query.exclude = excludes
	
	query.collide_with_areas = false # Player is a body, not an area. Prevents hitting enemy's own areas.
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result:
		var c = result.collider
		if c == target:
			return true
		if c is Node:
			var p = c.get_parent()
			if p == target:
				return true
			if p != null and p.get_parent() == target:
				return true
	return false

func shoot():
	ammo -= 1
	var is_snp: bool = equipped_primary != null and equipped_primary.get("id") == "m700"
	if is_snp:
		Sfx.oneshot3d("sniper_shot", self, 18.0, 160.0, 1.0)
		get_tree().create_timer(0.45).timeout.connect(func():
			if is_instance_valid(self) and not is_dead:
				Sfx.oneshot3d("sniper_bolt", self, 12.0, 80.0, 0.5)
		)
	else:
		Sfx.oneshot3d("rifle_single", self, 14.0, 120.0, 0.0)
	# Use equipped primary fire rate if available
	if equipped_primary and equipped_primary.has("fire_rate"):
		fire_cooldown = equipped_primary["fire_rate"]
	else:
		fire_cooldown = 0.2 # Fallback fire rate
	
	var ray_start = weapon_holder.global_position
	# Cone spread: random angle within ±3 degrees
	var spread_angle = deg_to_rad(3.0)
	var dir = (target.global_position + Vector3(0, 1.0, 0) - ray_start).normalized()
	var x_axis = dir.cross(Vector3.UP).normalized()
	if x_axis.length() < 0.01:
		x_axis = Vector3.RIGHT
	var y_axis = dir.cross(x_axis).normalized()
	
	var pitch = randf_range(-spread_angle, spread_angle)
	var yaw = randf_range(-spread_angle, spread_angle)
	dir = (dir + x_axis * sin(yaw) + y_axis * sin(pitch)).normalized()
	
	var end_pos = ray_start + dir * 100.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_start, end_pos)
	var excludes = [get_rid()]
	for b in hitboxes:
		excludes.append(b.get_rid())
	query.exclude = excludes
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result = space_state.intersect_ray(query)
	
	var visual_end = end_pos
	if result:
		visual_end = result.position
		var hit = result.collider
		if hit:
			var hit_body = hit.get_parent() if hit is Area3D else hit
			var is_ffa: bool = GlobalData.is_ffa_mode()
			var my_team := str(get("snd_team"))
			var is_friendly: bool = false
			if not is_ffa:
				if my_team != "":
					# Team modes: same team = friendly (covers halftime side swaps)
					is_friendly = _snd_side_of(hit) == my_team \
						or (hit_body and hit_body != hit and _snd_side_of(hit_body) == my_team)
				else:
					is_friendly = hit.is_in_group("ally") or (hit.is_in_group("player") and not hit.is_in_group("enemy")) \
						or (hit_body and hit_body != hit and (hit_body.is_in_group("ally") or (hit_body.is_in_group("player") and not hit_body.is_in_group("enemy"))))
			if not is_friendly:
				var dmg = 10.0
				var w_name = "Gun"
				if equipped_primary and equipped_primary.has("dmg"):
					dmg = equipped_primary["dmg"]
				if equipped_primary and equipped_primary.has("id"):
					w_name = equipped_primary["id"]
				var my_faction := "Ally" if my_team == "attackers" else "Enemy"
				if hit.has_method("take_damage"):
					hit.take_damage(dmg, bot_name, w_name, my_faction)
				elif hit_body and hit_body != hit and hit_body.has_method("take_damage"):
					hit_body.take_damage(dmg, bot_name, w_name, my_faction)
			
	create_tracer(ray_start, visual_end)

func create_tracer(start: Vector3, end: Vector3):
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	cyl.height = start.distance_to(end)
	mesh_inst.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.8) # Blue tracers for ally
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.6, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl.material = mat
	
	get_tree().root.add_child(mesh_inst)
	mesh_inst.position = (start + end) / 2.0
	
	var dir = (end - start).normalized()
	var up = Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT
	mesh_inst.look_at_from_position(mesh_inst.position, end, up)
	mesh_inst.rotation.x += PI / 2.0
	
	# Tween bound to the MESH so a freed bot can't orphan the tracer
	var tween = mesh_inst.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.1)
	tween.tween_callback(mesh_inst.queue_free)

func take_damage(amount: float, attacker_name: String = "", weapon_name: String = "", attacker_faction: String = "", _attacker_pos: Vector3 = Vector3.INF) -> float:
	return receive_damage(amount, "torso", attacker_name, weapon_name, attacker_faction)

func receive_damage(base_dmg: float, part: String = "upper", attacker_name: String = "", weapon_name: String = "", attacker_faction: String = "") -> float:
	if is_dead:
		return 0.0
	# Spawn protection (CS style): invulnerable until timer lapses or we move
	if spawn_protect_timer > 0.0:
		return 0.0
	# Replicated puppet: route the hit to the host's authoritative bot
	if is_net_puppet:
		var mgr = get_tree().current_scene
		if mgr is MultiplayerManager:
			mgr.report_bot_damage.rpc_id(1, net_id, base_dmg, part, attacker_name, weapon_name, attacker_faction)
		return base_dmg

	if attacker_name != "":
		last_attacker = attacker_name
		last_attacker_faction = attacker_faction if attacker_faction != "" else "Enemy"
	if weapon_name != "":
		last_weapon = weapon_name
	last_hit_part = part

	var multi = 1.0
	if part == "head":
		multi = 2.0
	elif part == "lower":
		multi = 0.7

	var final_dmg = health_component.apply_damage(base_dmg, multi)

	var normal_color = _get_operator_color(active_operator.op_name) if active_operator else Color(0.8, 0.8, 0.8)
	body.flash_hit(normal_color)

	return final_dmg

func receive_percentage_damage(percent: float, is_backstab: bool, attacker_name: String = "", weapon_name: String = "", attacker_faction: String = "") -> float:
	if is_dead:
		return 0.0
	var dmg = max_health * percent
	if is_backstab:
		dmg = max_health
	return receive_damage(dmg, "torso", attacker_name, weapon_name, attacker_faction)

func die():
	is_dead = true
	respawn_timer = 5.0
	
	var killer = last_attacker if last_attacker != "" else "World"
	var k_faction = last_attacker_faction if last_attacker_faction != "" else "Enemy"
	var gun = last_weapon if last_weapon != "" else "Combat"
	var victim = bot_name if bot_name != "" else "Ally"
	# Puppets never self-register: only the host owns kill scoring
	if not is_net_puppet:
		GlobalData.register_kill(killer, k_faction, gun, victim, "Ally", last_hit_part == "head")
		# Replicate death visual to clients
		var mgr = get_tree().current_scene
		if mgr is MultiplayerManager and net_id >= 0:
			mgr.broadcast_bot_died(net_id)
	
	# Notify player/active operator of kill
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.active_operator and p.active_operator.has_method("on_enemy_killed"):
			p.active_operator.on_enemy_killed()
	
	for box in hitbox_shapes:
		box.set_deferred("disabled", true)
	collision_shape.set_deferred("disabled", true)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(visuals, "rotation:x", deg_to_rad(-90), 0.5).set_trans(Tween.TRANS_BOUNCE)
	tween.tween_property(visuals, "position:y", -0.5, 0.5)

## CS-style spawn protection: 5s or until we move (FFA modes only)
func _arm_spawn_protect() -> void:
	if not GlobalData.is_ffa_mode():
		return
	spawn_protect_timer = 5.0
	_spawn_protect_origin = global_position

func respawn():
	is_dead = false
	health_component.reset()
	last_attacker = ""
	last_weapon = ""
	ammo = max_ammo
	is_reloading = false
	current_speed_mult = active_operator.speed_mult if active_operator else 1.0
	
	# Force position immediately
	global_position = start_pos
	velocity = Vector3.ZERO
	_arm_spawn_protect()
	
	for box in hitbox_shapes:
		box.set_deferred("disabled", false)
	collision_shape.set_deferred("disabled", false)
	
	visuals.rotation.x = 0
	visuals.position.y = 0
	visuals.scale.y = 1.0
	is_crouching = false
	is_sliding = false
	
	# Replicate respawn to clients so puppets resurrect visually
	if not is_net_puppet:
		var mgr = get_tree().current_scene
		if mgr is MultiplayerManager and net_id >= 0 and mgr.has_method("broadcast_bot_respawned"):
			mgr.broadcast_bot_respawned(net_id)
	
	print("Enemy Respawned!")
