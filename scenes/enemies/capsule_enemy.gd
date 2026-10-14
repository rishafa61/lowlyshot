extends CharacterBody3D

@onready var visuals = $Visuals
@onready var mesh = $Visuals/MeshInstance3D
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
var last_attacker: String = ""
var last_attacker_faction: String = ""
var last_weapon: String = ""

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
const WALK_SPEED = 2.5
const RUN_SPEED = 5.5
const SLIDE_SPEED = 9.0
const CROUCH_HEIGHT = 1.0
const STAND_HEIGHT = 2.0

var is_crouching = false
var is_sliding = false
var slide_timer = 0.0
var roam_timer = 0.0
var skill_trigger_timer: float = 0.0 # Small delay before first skill use

var target: Node3D = null
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * 2.0
var flash_tween: Tween

var stun_timer = 0.0
var is_stunned = false

func stun(duration: float):
	is_stunned = true
	stun_timer = duration
	
	# Solid unshaded white overlay for enemies when flashed
	var white_overlay = StandardMaterial3D.new()
	white_overlay.albedo_color = Color(1, 1, 1, 1)
	white_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_overlay = white_overlay

func reveal_silhouette():
	var outline = StandardMaterial3D.new()
	outline.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline.albedo_color = Color(1, 0, 0, 0.35)
	outline.emission_enabled = true
	outline.emission = Color(1, 0, 0, 1)
	outline.emission_energy_multiplier = 2.0
	outline.no_depth_test = true
	mesh.material_overlay = outline
	var tween = create_tween()
	tween.tween_interval(5.0)
	tween.tween_callback(func(): mesh.material_overlay = null)

func _ready():
	if bot_name == "":
		bot_name = GlobalData.get_random_bot_name()
	# Replicated puppets: visuals + collision only, no AI (host owns the sim)
	if is_net_puppet:
		_setup_puppet_bot()
		return
	# Assign a random operator to this enemy
	var op_script = available_operators.pick_random()
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
	
	# Tint enemy mesh by operator type
	var mat = StandardMaterial3D.new()
	mat.albedo_color = _get_operator_color(active_operator.op_name)
	mesh.set_surface_override_material(0, mat)
	
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target = players[0]
	
	_equip_random_primary()

func _setup_puppet_bot() -> void:
	health_component = $HealthComponent
	health_component.setup(100.0, 0.0)
	can_respawn = false
	start_pos = global_position
	_net_target_pos = global_position
	_net_target_yaw = rotation.y
	_setup_nametag()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.2, 0.2)
	mesh.set_surface_override_material(0, mat)
	_equip_random_primary()

func _find_nearest_target() -> void:
	var potential_targets = get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("ally")
	var closest_dist = INF
	target = null
	for pt in potential_targets:
		if pt is Node3D and not pt.get("is_dead"):
			# A player who joined the defenders is on OUR side — skip them
			if pt.is_in_group("enemy"):
				continue
			var d = global_position.distance_to(pt.global_position)
			if d < closest_dist:
				closest_dist = d
				target = pt

func _equip_random_primary() -> void:
	# Clear any existing weapons
	for c in weapon_holder.get_children():
		c.queue_free()
	
	# Pick a random primary weapon from GlobalData
	var primaries = GlobalData.weapons["Primary"]
	var w = null
	if net_weapon_id != "":
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
		"m700": "res://scenes/weapons/main/m700.tscn"
	}
	
	var scene_path = scene_map.get(w["id"], "res://scenes/weapons/main/ak47.tscn")
	var scene = load(scene_path) as PackedScene
	if scene:
		var inst = scene.instantiate() as Node3D
		inst.name = w["id"]
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
	nametag.modulate = Color(1.0, 0.35, 0.35)
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
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	if is_dead:
		if can_respawn:
			respawn_timer -= delta
			if respawn_timer <= 0.0:
				respawn()
				return # Don't do physics on the exact frame we respawn
		
		# Only apply gravity if collision is still somehow active, otherwise just wait
		velocity.x = move_toward(velocity.x, 0, delta * 10.0)
		velocity.z = move_toward(velocity.z, 0, delta * 10.0)
		if not collision_shape.disabled:
			move_and_slide()
			
		return
		
	# Process stun
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0:
			is_stunned = false
			mesh.material_overlay = null
		
		# Keep applying gravity and simple friction while stunned, but no AI logic
		velocity.x = move_toward(velocity.x, 0, delta * 15.0)
		velocity.z = move_toward(velocity.z, 0, delta * 15.0)
		move_and_slide()
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

	process_ai(delta)
	process_stance(delta)

	# Push away from overlapping bots so they never clip through each other
	_apply_bot_separation()

	move_and_slide()

	# Step-up assist over map seams / lips (up to 0.6 m)
	if is_on_floor() and is_on_wall():
		var space := get_world_3d().direct_space_state
		var fwd := -global_transform.basis.z
		var step_target := global_position + Vector3.UP * 0.6 + fwd * 0.3
		var down_ray := PhysicsRayQueryParameters3D.create(
			step_target, step_target + Vector3.DOWN * 0.7,
			collision_mask, [get_rid()]
		)
		var hit := space.intersect_ray(down_ray)
		if not hit.is_empty():
			global_position = hit.position + Vector3.UP * 0.05

func _apply_bot_separation() -> void:
	# Repel every other bot within 1.2 m
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
	
	# AI pushes doors open
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			c.get_collider().apply_central_impulse(-c.get_normal() * 1.5)
			if c.get_collider().get_parent().has_method("register_interaction"):
					c.get_collider().get_parent().register_interaction()


func process_ai(delta):
	# Periodically find nearest hostile (player or ally bot)
	if randf() < 0.05 or not target or target.get("is_dead"):
		_find_nearest_target()

	var sees_target = can_see_target()
	
	if not target or target.get("is_dead") or not sees_target:
		# ROAM STATE
		is_crouching = false
		roam_timer -= delta
		if roam_timer <= 0 or nav_agent.is_navigation_finished():
			var random_pos = start_pos + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
			nav_agent.target_position = random_pos
			roam_timer = randf_range(3.0, 6.0)
		move_along_path(WALK_SPEED * current_speed_mult, true)
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
			# Shoot anytime within effective firing range (25m)
			if dist <= 25.0 and fire_cooldown <= 0:
				shoot()

			if dist > 12.0:
				# CHASE - close the distance to optimal range
				is_crouching = false
				nav_agent.target_position = target.global_position
				
				# Randomly slide to close distance
				if randf() < 0.02 and not is_sliding and is_on_floor():
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

func move_along_path(speed: float, rotate_to_path: bool):
	var goal_dist: float = nav_agent.target_position.distance_to(global_position)
	if nav_agent.is_navigation_finished():
		if goal_dist < 1.5:
			# Genuinely arrived
			velocity.x = move_toward(velocity.x, 0, 0.5)
			velocity.z = move_toward(velocity.z, 0, 0.5)
			return
		# ponytail: navmesh broken/unbaked (agent can't path) — steer straight at
		# the goal so bots keep moving; rebake the navmesh in-editor for real paths.
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
		
		# Also scale down the Hitboxes node so the head hitbox physically drops down
		$Hitboxes.scale.y = current_scale
		$Hitboxes.position.y = 0.0

func can_see_target() -> bool:
	if not target or target.get("is_dead"): return false
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
	if result and result.collider == target:
		return true
	return false

func shoot():
	ammo -= 1
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
		var dmg = 10.0
		var w_name = "Gun"
		if equipped_primary and equipped_primary.has("dmg"):
			dmg = equipped_primary["dmg"]
		if equipped_primary and equipped_primary.has("id"):
			w_name = equipped_primary["id"]
		# Hostile check: enemy bots consider anyone in group "enemy" as friendly teammate
		var body = hit.get_parent() if hit is Area3D else hit
		var friendly = hit.is_in_group("enemy") or (body and body != hit and body.is_in_group("enemy"))
		if not friendly:
			if hit.has_method("take_damage"):
				hit.take_damage(dmg, bot_name, w_name, "Enemy")
			elif body and body != hit and body.has_method("take_damage"):
				body.take_damage(dmg, bot_name, w_name, "Enemy")

	create_tracer(ray_start, visual_end)

func create_tracer(start: Vector3, end: Vector3):
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	cyl.height = start.distance_to(end)
	mesh_inst.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.2, 0.2, 0.8) # Red tracers for enemy
	mat.emission_enabled = true
	mat.emission = Color(1, 0.2, 0.2)
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

	var multi = 1.0
	if part == "head":
		multi = 2.0
	elif part == "lower":
		multi = 0.7

	var final_dmg = health_component.apply_damage(base_dmg, multi)

	if flash_tween:
		flash_tween.kill()
	flash_tween = create_tween()
	var mat = mesh.get_surface_override_material(0)
	mat.albedo_color = Color(1, 0, 0)
	var normal_color = _get_operator_color(active_operator.op_name) if active_operator else Color(0.8, 0.8, 0.8)
	flash_tween.tween_property(mat, "albedo_color", normal_color, 0.2)

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
	var victim = bot_name if bot_name != "" else "Enemy"
	# Puppets never self-register: only the host owns kill scoring
	if not is_net_puppet:
		GlobalData.register_kill(killer, k_faction, gun, victim, "Enemy")
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
	
	for box in hitbox_shapes:
		box.set_deferred("disabled", false)
	collision_shape.set_deferred("disabled", false)
	
	visuals.rotation.x = 0
	visuals.position.y = 0
	visuals.scale.y = 1.0
	is_crouching = false
	is_sliding = false
	
	print("Enemy Respawned!")
