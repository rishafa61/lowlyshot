extends StaticBody3D

@export var max_health: float = 100.0
@export var detection_range: float = 20.0
@export var fire_range: float = 15.0
@export var damage: float = 10.0
@export var fire_rate: float = 3.0 # bullets/sec
@export var lifetime: float = 15.0

var health_component: HealthComponent
var health: float:
	get: return health_component.health if health_component else 100.0

var fire_timer: float = 0.0
var current_target: Node3D = null
var is_dead: bool = false
var faction: String = "Player" # "Player", "Ally", "Enemy"
var owner_name: String = "Player"
var weapon_name: String = "Auto-Turret"
## Set by MultiplayerManager on non-owner peers: visual replica only (no AI, no damage)
var is_net_replica: bool = false

@onready var swivel: Node3D = $Swivel
@onready var pitch: Node3D = $Swivel/Pitch
@onready var muzzle_pos: Marker3D = $Swivel/Pitch/MuzzlePos
@onready var detection_area: Area3D = $DetectionArea

func _ready() -> void:
	health_component = $HealthComponent
	health_component.setup(max_health, 0.0)
	health_component.died.connect(destroy)
	fire_timer = 0.0

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		destroy()
		return
	if is_net_replica:
		return # Visual replica: host/owner simulates firing and health
		
	if fire_timer > 0.0:
		fire_timer -= delta
		
	find_best_target()
	
	if current_target and is_instance_valid(current_target):
		aim_at_target(delta)
		var dist = global_position.distance_to(current_target.global_position)
		if dist <= fire_range and can_see_target(current_target):
			if fire_timer <= 0.0:
				fire()
				fire_timer = 1.0 / fire_rate
	else:
		current_target = null

func find_best_target() -> void:
	var potential_targets: Array[Node3D] = []
	
	# 1. Look for enemies in detection area
	var bodies = detection_area.get_overlapping_bodies()
	for b in bodies:
		if is_valid_enemy(b):
			potential_targets.append(b)
			
	# Also query nodes in group "enemy" as a reliable fallback
	var fallback_groups: Array[String] = ["enemy"]
	if target_mode == "player":
		fallback_groups.append("player")
		
	for group_name in fallback_groups:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node3D and node not in potential_targets:
				if global_position.distance_to(node.global_position) <= detection_range:
					if is_valid_enemy(node):
						potential_targets.append(node)

	var closest_target: Node3D = null
	var min_dist: float = INF
	
	for t in potential_targets:
		var dist = global_position.distance_to(t.global_position)
		if dist < min_dist and can_see_target(t):
			min_dist = dist
			closest_target = t
			
	current_target = closest_target

var target_mode: String = "enemies" # "enemies" targets enemies, "player" targets player

func is_valid_enemy(node: Node) -> bool:
	if not node or not is_instance_valid(node):
		return false
	if target_mode == "player":
		if node.is_in_group("player") and node.get("is_dead") != true:
			return true
		return false
	
	if node.is_in_group("player"):
		return false
	if node.is_in_group("ally"):
		return false
	if node.get("is_dead") == true:
		return false
	if node.is_in_group("enemy"):
		return true
	if node.has_method("take_damage") and not node.is_in_group("player_turret") and not node.is_in_group("ally_turret"):
		return true
	return false

func get_target_center(target: Node3D) -> Vector3:
	if target is CharacterBody3D:
		return target.global_position + Vector3(0, 1.0, 0)
	return target.global_position

func can_see_target(target: Node3D) -> bool:
	var space_state = get_world_3d().direct_space_state
	var start = muzzle_pos.global_position
	var end = get_target_center(target)
	
	var query = PhysicsRayQueryParameters3D.create(start, end)
	query.exclude = [get_rid(), detection_area.get_rid()]
	query.collide_with_areas = true
	var result = space_state.intersect_ray(query)
	
	if result:
		var col = result.collider
		if col == target or col.get_parent() == target or (col.has_method("take_damage") and is_valid_enemy(col)):
			return true
		return false
	return false

func aim_at_target(delta: float) -> void:
	var target_center = get_target_center(current_target)
	
	# Horizontal swivel (Y-axis only)
	var swivel_target = target_center
	swivel_target.y = swivel.global_position.y
	var swivel_dir = (swivel_target - swivel.global_position).normalized()
	if swivel_dir.length_squared() > 0.001:
		var target_yaw = atan2(-swivel_dir.x, -swivel_dir.z)
		swivel.rotation.y = rotate_toward(swivel.rotation.y, target_yaw, delta * 8.0)
		
	# Vertical pitch (X-axis relative to swivel)
	var local_target = swivel.to_local(target_center)
	var target_pitch = atan2(local_target.y, -local_target.z)
	pitch.rotation.x = rotate_toward(pitch.rotation.x, target_pitch, delta * 8.0)

func fire() -> void:
	if not current_target:
		return
		
	var space_state = get_world_3d().direct_space_state
	var start = muzzle_pos.global_position
	var target_center = get_target_center(current_target)
	var dir = (target_center - start).normalized()
	var end = start + dir * fire_range
	
	var query = PhysicsRayQueryParameters3D.create(start, end)
	query.exclude = [get_rid(), detection_area.get_rid()]
	query.collide_with_areas = true
	var result = space_state.intersect_ray(query)
	
	var hit_pos = end
	if result:
		hit_pos = result.position
		var hit_collider = result.collider
		var target_obj = hit_collider
		if not target_obj.has_method("take_damage") and target_obj.get_parent() and target_obj.get_parent().has_method("take_damage"):
			target_obj = target_obj.get_parent()
		if target_obj.has_method("take_damage"):
			target_obj.take_damage(damage, owner_name, weapon_name, faction)
			
	create_tracer(start, hit_pos)
	create_muzzle_flash()

func create_muzzle_flash() -> void:
	var flash = OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.3)
	flash.light_energy = 3.0
	flash.omni_range = 2.5
	muzzle_pos.add_child(flash)
	
	var tween = create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.05)
	tween.tween_callback(flash.queue_free)

func create_tracer(start: Vector3, end: Vector3) -> void:
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = start.distance_to(end)
	mesh_inst.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.7, 0.2, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.material_override = mat
	
	get_tree().root.add_child(mesh_inst)
	mesh_inst.global_position = (start + end) / 2.0
	
	var dir = (end - start).normalized()
	var up = Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT
	mesh_inst.look_at_from_position(mesh_inst.global_position, end, up)
	mesh_inst.rotation.x += PI / 2.0
	
	var tween = mesh_inst.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tween.tween_callback(mesh_inst.queue_free)
	get_tree().create_timer(0.2).timeout.connect(func():
		if is_instance_valid(mesh_inst): mesh_inst.queue_free)

var last_attacker: String = ""
var last_attacker_faction: String = ""
var last_weapon: String = ""

func take_damage(amount: float, attacker_name: String = "", w_name: String = "", attacker_faction: String = "", _attacker_pos: Vector3 = Vector3.INF) -> float:
	# Friendly/ally turrets are invulnerable: no friendly fire, no enemy destruction
	if faction != "Enemy" or is_dead:
		return 0.0
	if attacker_faction == "Enemy":
		return 0.0
	if attacker_name != "":
		last_attacker = attacker_name
		last_attacker_faction = attacker_faction if attacker_faction != "" else "Player"
	if w_name != "":
		last_weapon = w_name
	return health_component.apply_damage(amount)

func destroy() -> void:
	if is_dead:
		return
	is_dead = true
	if faction == "Enemy" and last_attacker != "":
		var killer = last_attacker
		var k_fac = last_attacker_faction if last_attacker_faction != "" else "Player"
		var gun = last_weapon if last_weapon != "" else "Weapon"
		GlobalData.register_kill(killer, k_fac, gun, "Sentry Turret", "Enemy")
	
	var parent_node = get_parent()
	if parent_node:
		var flash = OmniLight3D.new()
		flash.light_color = Color(1.0, 0.4, 0.1)
		flash.light_energy = 5.0
		flash.omni_range = 4.0
		parent_node.add_child(flash)
		flash.global_position = global_position + Vector3(0, 0.5, 0)
		var tween = get_tree().create_tween()
		tween.tween_property(flash, "light_energy", 0.0, 0.2)
		tween.tween_callback(flash.queue_free)
	
	queue_free()
