extends CharacterBody3D

var speed_crouch: float = 2.5
var speed_normal: float = 5.0
var speed_sprint: float = 11.0
const SPEED_SLIDE: float = 14.0
const SLIDE_DURATION: float = 3.0

# Increased gravity logic
const GRAVITY_MULT = 2.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * GRAVITY_MULT
const JUMP_VELOCITY: float = 6.5

const MOUSE_SENSITIVITY: float = 0.002
const CROUCH_HEIGHT: float = 1.0
const STAND_HEIGHT: float = 2.0
const CROUCH_SPEED: float = 8.0
const LEAN_POS: float = 0.6
const LEAN_ROT: float = deg_to_rad(15.0)
const LEAN_SPEED: float = 8.0

const BOB_FREQ: float = 2.4
const BOB_AMP: float = 0.08
var t_bob: float = 0.0

var is_sliding: bool = false
var slide_timer: float = 0.0
var slide_vector: Vector2 = Vector2.ZERO

var health_component: HealthComponent
var max_hp: int:
	get: return int(health_component.max_health) if health_component else 100
	set(val):
		if health_component: health_component.max_health = float(val)
var hp: int:
	get: return int(health_component.health) if health_component else 100
	set(val):
		if health_component: health_component.health = float(val)
var max_armor: int:
	get: return int(health_component.max_armor) if health_component else 50
	set(val):
		if health_component: health_component.max_armor = float(val)
var armor: int:
	get: return int(health_component.armor) if health_component else 50
	set(val):
		if health_component: health_component.armor = float(val)

var max_stamina: float = 100.0
var stamina: float = 100.0
const STAMINA_DRAIN: float = 20.0
const STAMINA_REGEN: float = 15.0
var is_exhausted: bool = false
var is_dead: bool = false
var active_operator: Node = null
var spawn_point: Vector3 = Vector3.ZERO
var held_object: RigidBody3D = null
var respawn_timer: float = 0.0
const EXHAUST_RECOVERY: float = 30.0

# Weapon Loadout State
enum Slot { RIFLE, PISTOL, MELEE, GRENADE }
var active_slot = Slot.PISTOL
var weapons = [] # Will be populated in _ready()
var fire_cooldown: float = 0.0

# Grenade Logic
var is_cooking: bool = false
var cook_timer: float = 0.0
const MAX_COOK_TIME: float = 3.0
var grenade_projectile = load("res://scenes/weapons/utilities/grenade_projectile.tscn")

var is_reloading: bool = false
var reload_timer: float = 0.0
const RELOAD_TIME: float = 1.5

const WEAPON_POS_HIP = Vector3(0.3, -0.3, -0.5)
const WEAPON_POS_ADS = Vector3(0.0, -0.22, -0.4)
const FOV_NORMAL = 75.0
const FOV_ADS = 55.0
var current_recoil := Vector3.ZERO
var camera_recoil := 0.0
var recoil_spread := 0.0
var is_aiming := false
var melee_tween: Tween = null
var melee_swing_offset := Vector3.ZERO

@onready var head: Node3D = $Head
@onready var flashlight = $Head/Flashlight
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var drag_position: Marker3D = $Head/Camera3D/DragPosition
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var hud = $HUD

@onready var sniper_scope_ui = $SniperScope

var current_weapon_instance: Node3D = null

func update_weapon_model(slot: Slot) -> void:
	if is_instance_valid(current_weapon_instance):
		current_weapon_instance.queue_free()
		current_weapon_instance = null
	var w = weapons[slot]
	var path = str(w.get("scene_path", ""))
	if path == "":
		return
	var scene = load(path) as PackedScene
	if scene == null:
		return
	current_weapon_instance = scene.instantiate() as Node3D
	weapon_holder.add_child(current_weapon_instance)

func _ready() -> void:
	spawn_point = global_position
	_last_safe_pos = global_position
	# Steep map slopes (up to ~60°): treat them as walkable floor, not walls.
	# Without this, sliding down a >45° ramp leaves you unable to walk back up.
	floor_max_angle = deg_to_rad(60.0)
	floor_snap_length = 0.4
	floor_stop_on_slope = true
	floor_block_on_wall = false
	# Online match: a player node owned by ANOTHER peer is only a puppet (no input/camera/HUD)
	is_puppet = GlobalData.is_networked() and not is_multiplayer_authority()
	if is_puppet:
		_setup_puppet()
		return
	if GlobalData.is_networked():
		camera.make_current()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Load Operator
	var op_script = GlobalData.get_equipped_operator_script()
	active_operator = Node.new()
	active_operator.set_script(op_script)
	add_child(active_operator)
	
	# Wire health through the shared component
	health_component = $HealthComponent
	health_component.setup(float(active_operator.max_health), float(active_operator.max_armor))
	health_component.died.connect(die)
	health_component.damaged.connect(_on_health_damaged)
	speed_normal = 5.0 * active_operator.speed_mult
	speed_sprint = 11.0 * active_operator.speed_mult
	
	# Build player runtime loadout from GlobalData
	weapons = [
		GlobalData.get_equipped_primary().duplicate(),
		GlobalData.get_equipped_secondary().duplicate(),
		GlobalData.get_equipped_melee().duplicate(),
		GlobalData.get_equipped_utility().duplicate()
	]
	weapons[Slot.GRENADE]["amount"] = 1
	
	switch_weapon(Slot.RIFLE)
	weapon_holder.position = WEAPON_POS_HIP
	weapon_holder.visible = true
	if sniper_scope_ui: sniper_scope_ui.hide()
	if hud:
		hud.update_stats(hp, max_hp, armor, max_armor, stamina, max_stamina)
		hud.update_minimap(global_position, head.rotation.y)


func stun(duration: float):
	if is_puppet:
		_net_apply_stun.rpc_id(get_multiplayer_authority(), duration)
		return
	if is_dead: return
	var prev_speed = speed_normal
	var prev_sprint = speed_sprint
	speed_normal *= 0.4
	speed_sprint *= 0.4
	camera_recoil += 0.5
	if hud: hud.show_flash_vignette(duration)
	var tween = create_tween()
	tween.tween_interval(duration)
	tween.tween_callback(func():
		speed_normal = prev_speed
		speed_sprint = prev_sprint
	)

@rpc("any_peer", "call_remote", "reliable")
func _net_apply_stun(duration: float) -> void:
	if is_puppet or is_dead:
		return
	stun(duration)

func _on_health_damaged(_raw_amount: float, _absorbed: float) -> void:
	if hud:
		hud.update_stats(hp, max_hp, armor, max_armor, stamina, max_stamina)
		hud.update_minimap(global_position, head.rotation.y)
		hud.show_damage_vignette()
	camera_recoil += 0.35 # punchy feedback: you KNOW you got hit

var last_attacker: String = ""
var last_weapon: String = ""

var is_spectating: bool = false
var spectate_targets: Array = []
var spectate_index: int = 0
var spectate_yaw: float = 0.0
var spectate_pitch: float = deg_to_rad(20.0)
var spectate_dist: float = 3.2
var spectate_first_person: bool = false

func enter_spectator_mode() -> void:
	if is_spectating: return
	is_spectating = true
	weapon_holder.visible = false
	if hud:
		hud.hide_hover_name()
		hud.toggle_combat_hud(false)
	_refresh_spectate_targets()
	var t = get_current_spectate_target()
	if t:
		spectate_yaw = t.global_rotation.y + PI
		spectate_pitch = deg_to_rad(20.0)
	if hud: hud.show_damage_vignette()
	_update_spectate_hud()
	GlobalData.log_combat("Spectator mode ON (A/D to cycle, Mouse to orbit)")

func exit_spectator_mode() -> void:
	if not is_spectating: return
	is_spectating = false
	spectate_targets = []
	if hud:
		hud.hide_spectating()
		hud.toggle_combat_hud(true)
	# Restore own camera
	head.position.y = 1.8
	head.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.fov = FOV_NORMAL
	weapon_holder.visible = true
	if is_dead:
		respawn()
	else:
		global_position = spawn_point if spawn_point else global_position
	GlobalData.log_combat("Spectator mode OFF")

func _refresh_spectate_targets() -> void:
	spectate_targets = []
	for n in get_tree().get_nodes_in_group("ally"):
		if n is Node3D and not bool(n.get("is_dead")):
			spectate_targets.append(n)
	for n in get_tree().get_nodes_in_group("enemy"):
		if n is Node3D and not bool(n.get("is_dead")):
			spectate_targets.append(n)
	if spectate_index >= spectate_targets.size():
		spectate_index = 0

func get_current_spectate_target() -> Node3D:
	# Prune dead/freed targets each query
	_refresh_spectate_targets()
	if spectate_targets.is_empty():
		return null
	spectate_index = clampi(spectate_index, 0, spectate_targets.size() - 1)
	return spectate_targets[spectate_index]

func cycle_spectate(dir: int) -> void:
	_refresh_spectate_targets()
	if spectate_targets.is_empty():
		if hud: hud.show_spectating("No targets", "-")
		return
	spectate_index = (spectate_index + dir) % spectate_targets.size()
	if spectate_index < 0:
		spectate_index += spectate_targets.size()
	
	var t = get_current_spectate_target()
	if t:
		spectate_yaw = t.global_rotation.y + PI
		spectate_pitch = deg_to_rad(20.0)
	
	_update_spectate_hud()

func _update_spectate_hud() -> void:
	var t = get_current_spectate_target()
	if not hud: return
	if t == null:
		hud.show_spectating("No targets", "-", spectate_first_person)
		return
	var label_text = str(t.get("bot_name")) if t.get("bot_name") else t.name
	var faction = "ALLY" if t.is_in_group("ally") else "ENEMY"
	hud.show_spectating(label_text, faction, spectate_first_person)

func toggle_spectate_mode() -> void:
	spectate_first_person = not spectate_first_person
	_update_spectate_hud()

func _update_spectate_camera() -> void:
	var t = get_current_spectate_target()
	if t == null or not is_instance_valid(t):
		_update_spectate_hud()
		return
	
	if spectate_first_person:
		# First-person POV
		var eyes = t.get_node_or_null("Eyes")
		var eye_pos = eyes.global_position if eyes else t.global_position + Vector3(0, 1.6, 0)
		camera.global_position = eye_pos
		camera.global_rotation = Vector3(0.0, t.global_rotation.y, 0.0)
		return
	
	# Third-person orbit
	var target_center = t.global_position + Vector3(0, 1.5, 0)
	var cos_pitch = cos(spectate_pitch)
	var offset = Vector3(
		sin(spectate_yaw) * cos_pitch,
		sin(spectate_pitch),
		cos(spectate_yaw) * cos_pitch
	) * spectate_dist
	var cam_pos = target_center + offset
	
	# Wall clip check: pull camera in if geometry blocks the orbit path
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(target_center, cam_pos)
	query.exclude = [get_rid(), t.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var col = space_state.intersect_ray(query)
	if col:
		cam_pos = col.position + (target_center - col.position).normalized() * 0.25
	
	camera.global_position = cam_pos
	if cam_pos.distance_to(target_center) > 0.01:
		camera.look_at(target_center, Vector3.UP)

var team: String = "attackers"
var player_name: String = "Player"
var last_attacker_faction: String = ""

# ---------------- Online play ----------------
var is_puppet: bool = false
var _net_target_pos: Vector3 = Vector3.ZERO
var _net_target_yaw: float = 0.0
var _net_target_pitch: float = 0.0
var _net_tick: int = 0
var _puppet_body: MeshInstance3D = null
var _puppet_gun_holder: Node3D = null
var _net_weapon_path: String = ""
var _puppet_death_played: bool = false

func _setup_puppet() -> void:
	set_process_unhandled_input(false)
	_net_target_pos = global_position
	_net_target_yaw = rotation.y
	# Everything that reads local input / renders for the local player must go
	for n in [get_node_or_null("HUD"), get_node_or_null("PauseMenu"), get_node_or_null("SniperScope"), get_node_or_null("Head/Camera3D"), get_node_or_null("Head/Flashlight")]:
		if n:
			n.queue_free()
	hud = null
	sniper_scope_ui = null
	# Visible body so the other player can actually be seen
	_puppet_body = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.5
	cap.height = 2.0
	_puppet_body.mesh = cap
	_puppet_body.position = Vector3(0, 1, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 1.0) if team == "attackers" else Color(1.0, 0.35, 0.3)
	_puppet_body.material_override = mat
	add_child(_puppet_body)
	# Third-person gun holder so others can see the weapon this player holds
	_puppet_gun_holder = Node3D.new()
	_puppet_gun_holder.position = Vector3(0.3, 1.35, -0.35)
	add_child(_puppet_gun_holder)

## Syncs the visible gun model on remote puppets
func net_set_weapon(weapon_scene_path: String) -> void:
	if not is_puppet:
		return
	if weapon_scene_path == _net_weapon_path:
		return
	_net_weapon_path = weapon_scene_path
	for c in _puppet_gun_holder.get_children():
		c.queue_free()
	if weapon_scene_path == "" or not is_instance_valid(_puppet_gun_holder):
		return
	var sc = load(weapon_scene_path) as PackedScene
	if sc == null:
		return
	var gun = sc.instantiate() as Node3D
	_puppet_gun_holder.add_child(gun)

## Third-person death animation for remote puppets
func net_play_death() -> void:
	if not is_puppet or _puppet_death_played:
		return
	_puppet_death_played = true
	if is_instance_valid(_puppet_gun_holder):
		_puppet_gun_holder.visible = false
	if is_instance_valid(_puppet_body):
		var tween = create_tween().set_parallel(true)
		tween.tween_property(_puppet_body, "rotation:x", deg_to_rad(-90), 0.5).set_trans(Tween.TRANS_BOUNCE)
		tween.tween_property(_puppet_body, "position:y", 0.2, 0.5)

## Called by the MultiplayerManager with the owner's latest transform
func net_set_target(pos: Vector3, yaw: float, pitch: float) -> void:
	_net_target_pos = pos
	_net_target_yaw = yaw
	_net_target_pitch = pitch

func _puppet_physics(delta: float) -> void:
	var t: float = min(1.0, delta * 15.0)
	global_position = global_position.lerp(_net_target_pos, t)
	rotation.y = lerp_angle(rotation.y, _net_target_yaw, t)
	if head:
		head.rotation.x = lerp_angle(head.rotation.x, _net_target_pitch, t)

func _net_send_state() -> void:
	_net_tick += 1
	if _net_tick % 2 != 0:
		return # 30 Hz is plenty
	var weapon_path := ""
	if active_slot >= 0 and active_slot < weapons.size():
		weapon_path = str(weapons[active_slot].get("scene_path", ""))
	var mgr = get_tree().current_scene
	if mgr is MultiplayerManager:
		mgr.send_local_player_state(int(str(name)), global_position, rotation.y, head.rotation.x, weapon_path)
	elif mgr and mgr.has_method("net_state"):
		mgr.net_state.rpc(global_position, rotation.y, head.rotation.x, weapon_path)

## Runs on the OWNER of this player when someone else shot its puppet
@rpc("any_peer", "call_remote", "reliable")
func _net_apply_damage(amount: float, attacker_name: String, weapon_name: String, attacker_faction: String, attacker_pos: Vector3 = Vector3.INF) -> void:
	if is_puppet or is_dead:
		return
	var my_faction: String = "Ally" if team == "attackers" else "Enemy"
	if attacker_faction != "" and attacker_faction == my_faction:
		return # no friendly fire
	take_damage(amount, attacker_name, weapon_name, attacker_faction, attacker_pos)

func take_damage(amount: float, attacker_name: String = "", weapon_name: String = "", attacker_faction: String = "", attacker_pos: Vector3 = Vector3.INF) -> float:
	if is_puppet:
		# Remote copy: the owning peer applies the damage to the real player
		_net_apply_damage.rpc_id(get_multiplayer_authority(), amount, attacker_name, weapon_name, attacker_faction, attacker_pos)
		return amount
	if is_dead: return 0.0
	var final = health_component.apply_damage(amount)
	if attacker_name != "":
		last_attacker = attacker_name
		last_attacker_faction = attacker_faction if attacker_faction != "" else "Enemy"
	if weapon_name != "":
		last_weapon = weapon_name

	if hud and final > 0.0:
		var w = weapon_name if weapon_name != "" else "Unknown"
		var a = attacker_name if attacker_name != "" else "World"
		hud.print_to_console("Took %d damage from %s (%s)" % [int(final), a, w])
		# Directional hit indicator: arrow around crosshair points at shooter
		if attacker_pos != Vector3.INF:
			var local := global_transform.basis.inverse() * (attacker_pos - global_position)
			hud.show_damage_direction(atan2(local.x, -local.z))
	return final

func die():
	is_dead = true
	var killer = last_attacker if last_attacker != "" else "World"
	var k_faction = last_attacker_faction if last_attacker_faction != "" else "Enemy"
	var gun = last_weapon if last_weapon != "" else "Combat"
	var v_faction = "Ally" if team == "attackers" else ("Enemy" if team == "defenders" else "Player")
	# Host (or offline) registers the kill locally; clients report so the host
	# can broadcast one killfeed event to every peer (no duplicates).
	if not GlobalData.is_networked() or multiplayer.is_server():
		GlobalData.register_kill(killer, k_faction, gun, player_name, v_faction)
	# Client deaths must reach the host: it owns scores / stats
	if GlobalData.is_networked():
		var mgr = get_tree().current_scene
		if mgr is MultiplayerManager:
			if not multiplayer.is_server():
				mgr.report_kill.rpc_id(1, killer, k_faction, gun, player_name, v_faction)
			mgr.notify_player_death(int(str(name)))
	
	# Drop camera to floor
	var tween = create_tween()
	tween.tween_property(head, "position:y", 0.2, 0.5).set_trans(Tween.TRANS_BOUNCE)
	# Rotate camera sideways
	tween.parallel().tween_property(head, "rotation:z", deg_to_rad(75), 0.5)
	
	respawn_timer = 3.0 # Wait 3 seconds then respawn


func respawn():
	is_dead = false
	health_component.reset()
	last_attacker = ""
	last_weapon = ""
	stamina = max_stamina
	is_exhausted = false
	
	# Refill all weapons dynamically based on their specific max stats
	if weapons[Slot.RIFLE].has("max_mag"):
		weapons[Slot.RIFLE]["mag"] = weapons[Slot.RIFLE]["max_mag"]
		weapons[Slot.RIFLE]["res"] = weapons[Slot.RIFLE]["max_res"]
	if weapons[Slot.PISTOL].has("max_mag"):
		weapons[Slot.PISTOL]["mag"] = weapons[Slot.PISTOL]["max_mag"]
		weapons[Slot.PISTOL]["res"] = weapons[Slot.PISTOL]["max_res"]
	weapons[Slot.GRENADE]["amount"] = 1
	
	switch_weapon(Slot.RIFLE) # Reset to default sidearm
	
	if hud: 
		hud.update_stats(hp, max_hp, armor, max_armor, stamina, max_stamina)
		hud.update_minimap(global_position, head.rotation.y)

	
	# Reset camera
	head.position.y = 1.8
	head.rotation.z = 0.0
	camera.rotation.x = 0.0
	
	# Move back to initial spawn point
	global_position = spawn_point
	velocity = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if is_puppet: return
	if hud and hud.console_visible: return
	if is_spectating:
		if event is InputEventMouseMotion and not spectate_first_person:
			spectate_yaw -= event.relative.x * MOUSE_SENSITIVITY
			spectate_pitch += event.relative.y * MOUSE_SENSITIVITY
			spectate_pitch = clamp(spectate_pitch, deg_to_rad(-25.0), deg_to_rad(80.0))
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and not spectate_first_person:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				spectate_dist = clampf(spectate_dist - 0.4, 1.5, 7.0)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				spectate_dist = clampf(spectate_dist + 0.4, 1.5, 7.0)
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed("interact") or (event is InputEventKey and event.keycode == KEY_E and event.pressed and not event.echo):
			toggle_spectate_mode()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("move_left") or (event is InputEventKey and event.keycode == KEY_A and event.pressed and not event.echo):
			cycle_spectate(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_right") or (event is InputEventKey and event.keycode == KEY_D and event.pressed and not event.echo):
			cycle_spectate(1)
			get_viewport().set_input_as_handled()
		return
	if is_dead: return
	if event is InputEventMouseMotion:
		var current_sens = MOUSE_SENSITIVITY * GlobalSettings.hip_sensitivity_mult
		if is_aiming:
			current_sens = MOUSE_SENSITIVITY * GlobalSettings.scope_sensitivity_mult
			if active_slot == Slot.RIFLE and weapons[Slot.RIFLE]["name"] == "M700": # Specific sniper reduction
				current_sens *= 0.3
		
		rotate_y(-event.relative.x * current_sens)
		head.rotate_x(-event.relative.y * current_sens)
		head.rotation.x = clamp(head.rotation.x, -PI/2.0, PI/2.0)
		
	if event.is_action_pressed("weapon_1"): switch_weapon(Slot.RIFLE)
	if event.is_action_pressed("weapon_2"): switch_weapon(Slot.PISTOL)
	if event.is_action_pressed("weapon_3"): switch_weapon(Slot.MELEE)
	if event.is_action_pressed("weapon_4"): switch_weapon(Slot.GRENADE)

	# Operator Skill
	if event.is_action_pressed("use_skill"):
		active_operator.use_skill(self)


	# Door dragging toggle
	if event.is_action_pressed("interact"):
		if held_object == null:
			if interact_ray.is_colliding():
				var collider = interact_ray.get_collider()
				if collider is RigidBody3D and collider.is_in_group("door"):
					held_object = collider
		else:
			held_object = null


	if event.is_action_pressed("toggle_flashlight"):
		flashlight.visible = not flashlight.visible


	# Grenade Logic
	if active_slot == Slot.GRENADE:
		if event.is_action_pressed("fire") and not is_cooking and weapons[Slot.GRENADE]["amount"] > 0:
			is_cooking = true
			cook_timer = 0.0
		if event.is_action_released("fire") and is_cooking:
			throw_grenade()

	if event.is_action_pressed("aim") and active_operator and active_operator.has_method("override_aim"):
		if active_operator.override_aim():
			return # Skip the rest of the inputs if aim is overridden

	# Melee Heavy Attack
	if active_slot == Slot.MELEE:
		if event.is_action_pressed("aim") and fire_cooldown <= 0:
			melee_attack(true) # true = heavy right click
		if event.is_action_pressed("fire") and fire_cooldown <= 0:
			melee_attack(false)

	# Gun reload
	var w = weapons[active_slot]
	if w["type"] == "gun":
		if event.is_action_pressed("reload") and not is_reloading and w["mag"] < w.get("max_mag", 0) and w["res"] > 0:
			if not (active_operator and (active_operator.get("is_holding_bow") or active_operator.get("is_holding_skill"))):
				start_reload()

func switch_weapon(slot: Slot) -> void:
	if is_cooking: return # Don't allow cancelling a cooked grenade
	
	if active_operator and active_operator.has_method("cancel_skill"):
		active_operator.cancel_skill()
	
	# Animation cancel: Abort reload if switching
	if is_reloading:
		is_reloading = false
		hud.update_reload(-1.0)
		
	if melee_tween and melee_tween.is_valid():
		melee_tween.kill()
	melee_swing_offset = Vector3.ZERO
	if is_instance_valid(current_weapon_instance):
		current_weapon_instance.rotation = Vector3.ZERO
	
	active_slot = slot as Slot
	var w = weapons[slot]
	
	# Disable all skill meshes
	for c in weapon_holder.get_children():
		if c != current_weapon_instance:
			(c as Node3D).visible = false
	
	update_weapon_model(slot)
	
	# Always turn off scope when switching
	if sniper_scope_ui: sniper_scope_ui.hide()
	camera.fov = FOV_NORMAL

	
	if hud:
		hud.update_weapon_slot(slot)
		if w["type"] == "gun":
			hud.update_ammo(w["mag"], w["res"])
		elif w["type"] == "util":
			hud.update_ammo(w["amount"], 0)
		else:
			hud.update_ammo(0, 0) # hide or show 0



func start_reload():
	is_reloading = true
	reload_timer = 0.0

func finish_reload():
	is_reloading = false
	hud.update_reload(-1.0)
	var w = weapons[active_slot]
	var max_m = w.get("max_mag", 0)
	var needed = max_m - w["mag"]
	if w["res"] >= needed:
		w["res"] -= needed
		w["mag"] += needed
	else:
		w["mag"] += w["res"]
		w["res"] = 0
	hud.update_ammo(w["mag"], w["res"])

func shoot_gun() -> void:
	var w = weapons[active_slot]
	w["mag"] -= 1
	fire_cooldown = w["fire_rate"]
	hud.update_ammo(w["mag"], w["res"])
	
	current_recoil = Vector3(0, 0, 0.15)
	if w.get("id", "") == "desert_hawk":
		current_recoil = Vector3(0, 0, 0.35)
		camera_recoil += 0.12
	else:
		camera_recoil += 0.05
	
	var speed = Vector2(velocity.x, velocity.z).length()
	var current_spread = 0.0
	if speed > 0.5: current_spread += 0.08 * (speed / speed_sprint)
	current_spread += recoil_spread
	
	if w.get("is_sniper", false):
		if is_aiming: current_spread = 0.0 # 100% pixel perfect when scoped
		else: current_spread += 0.15 # Massive hipfire penalty
		recoil_spread += 0.1
	else:
		if is_aiming: current_spread *= 0.1
		if w.get("id", "") == "desert_hawk":
			recoil_spread += 0.08
		else:
			recoil_spread += 0.02
	
	var forward = -camera.global_transform.basis.z
	var right = camera.global_transform.basis.x
	var up = camera.global_transform.basis.y
	var shoot_dir = (forward + right * randf_range(-current_spread, current_spread) + up * randf_range(-current_spread, current_spread)).normalized()
	
	var ray_start = camera.global_position
	var end_pos = ray_start + (shoot_dir * 100.0)
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_start, end_pos)
	query.collide_with_areas = true
	query.exclude = [get_rid()] # EXCLUDE THE PLAYER FROM THEIR OWN BULLETS
	var result = space_state.intersect_ray(query)
	
	var visual_end = end_pos
	var hit_body := false
	if result:
		visual_end = result.position
		var target = result.collider
		if target.has_method("take_damage"):
			hit_body = true
			var w_name = str(w.get("id", w.get("name", "Gun")))
			var p_faction = "Ally" if team == "attackers" else ("Enemy" if team == "defenders" else "Player")
			var final_dmg = target.take_damage(w["dmg"], player_name, w_name, p_faction, global_position)
			if final_dmg == null: final_dmg = w["dmg"]
			if hud and final_dmg > 0.0: hud.show_hit_marker(final_dmg)
			# Victim identity for console log
			var victim_entity = target
			if not ("bot_name" in victim_entity) and victim_entity.get_parent():
				victim_entity = victim_entity.get_parent()
				if not ("bot_name" in victim_entity) and victim_entity.get_parent():
					victim_entity = victim_entity.get_parent()
			var victim_name = str(victim_entity.get("bot_name")) if victim_entity.get("bot_name") != null and victim_entity.get("bot_name") != "" else "Enemy"
			GlobalData.log_combat("You hit %s for %d (%s)" % [victim_name, int(final_dmg), w_name])
	
	var muzzle_pos = get_current_muzzle_position()
	create_tracer(muzzle_pos, visual_end)
	# Every other peer sees the shot: tracer + blood puff on impact
	if GlobalData.is_networked():
		net_shot.rpc(muzzle_pos, visual_end, hit_body)

func get_current_muzzle_position() -> Vector3:
	if is_instance_valid(weapon_holder):
		var m = weapon_holder.find_child("Muzzle", true, false)
		if m == null:
			m = weapon_holder.find_child("MuzzleBrake", true, false)
		if m is Node3D:
			return (m as Node3D).global_position
	return camera.global_position + (-camera.global_transform.basis.z * 0.6) + (camera.global_transform.basis.y * -0.1)

func melee_attack(is_heavy: bool):
	var w = weapons[active_slot]
	fire_cooldown = 1.2 if is_heavy else w["fire_rate"]
	
	if melee_tween and melee_tween.is_valid():
		melee_tween.kill()
	melee_tween = create_tween().set_parallel(true)
	
	if is_heavy:
		# Thrust Animation: Pull back, rotate to align knife, thrust forward, then reset
		weapon_holder.rotation = Vector3.ZERO
		melee_swing_offset = Vector3(0, 0, 0)
		
		# Rotate sideways like a stabbing grip (pitch/yaw adjustment)
		melee_tween.tween_property(weapon_holder, "rotation:z", deg_to_rad(45), 0.1)
		melee_tween.tween_property(weapon_holder, "rotation:y", deg_to_rad(20), 0.1)
		# Lunge forward
		melee_tween.tween_property(self, "melee_swing_offset", Vector3(0.05, 0.05, -0.4), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		# Retract back to normal
		melee_tween.tween_property(weapon_holder, "rotation", Vector3.ZERO, 0.3).set_delay(0.2)
		melee_tween.tween_property(self, "melee_swing_offset", Vector3.ZERO, 0.3).set_delay(0.2)
	else:
		# Slash Animation: Swipe from right to left
		weapon_holder.rotation = Vector3.ZERO
		melee_swing_offset = Vector3(0, 0, 0)
		
		# Arc leftwards and tilt
		melee_tween.tween_property(weapon_holder, "rotation:z", deg_to_rad(-60), 0.15)
		melee_tween.tween_property(weapon_holder, "rotation:y", deg_to_rad(-30), 0.15)
		melee_tween.tween_property(self, "melee_swing_offset", Vector3(-0.45, 0.1, -0.1), 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
		# Recover
		melee_tween.tween_property(weapon_holder, "rotation", Vector3.ZERO, 0.2).set_delay(0.18)
		melee_tween.tween_property(self, "melee_swing_offset", Vector3.ZERO, 0.2).set_delay(0.18)
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + (-camera.global_transform.basis.z * 2.5))
	query.collide_with_areas = true
	query.exclude = [get_rid()] # EXCLUDE THE PLAYER FROM THEIR OWN MELEE
	var result = space_state.intersect_ray(query)
	
	if result:
		var target = result.collider
		if target.has_method("take_percentage_damage"):
			# Check Backstab
			var is_backstab = false
			if target.get_parent() is Node3D:
				var enemy_forward = -target.get_parent().global_transform.basis.z
				var player_forward = -global_transform.basis.z
				if player_forward.dot(enemy_forward) > 0.5:
					is_backstab = true
			
			var dmg_percent = 0.5 if is_heavy else 0.25
			var w_name = str(w.get("id", w.get("name", "Knife")))
			var final_dmg = target.take_percentage_damage(dmg_percent, is_backstab, "Player", w_name, "Player")
			if final_dmg == null: final_dmg = 0.0
			if hud and final_dmg > 0.0: hud.show_hit_marker(final_dmg)

func throw_grenade():
	is_cooking = false
	hud.update_cook_bar(-1.0)
	weapons[Slot.GRENADE]["amount"] -= 1
	hud.update_ammo(weapons[Slot.GRENADE]["amount"], 0)
	
	var w = weapons[Slot.GRENADE]
	var proj_path = "res://scenes/weapons/utilities/grenade_projectile.tscn"
	if w.get("id", "") == "flashbang":
		proj_path = "res://scenes/weapons/utilities/flashbang_projectile.tscn"
	
	var proj = load(proj_path).instantiate()
	get_tree().root.add_child(proj)
	proj.global_position = camera.global_position + (-camera.global_transform.basis.z * 0.6)
	proj.fuse = MAX_COOK_TIME - cook_timer
	
	var throw_dir = -camera.global_transform.basis.z
	proj.apply_impulse(throw_dir * 12.0 + Vector3.UP * 2.0)
	# Add spin for better bouncing physics
	proj.apply_torque_impulse(Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)))
	
	# Replicate grenade throw to other peers
	var mgr = get_tree().current_scene
	if mgr is MultiplayerManager:
		var extra := {
			"fuse": proj.fuse,
			"impulse": throw_dir * 12.0 + Vector3.UP * 2.0,
			"owner_name": player_name,
			"faction": "Ally" if team == "attackers" else "Enemy"
		}
		mgr.spawn_utility_net(proj_path, proj.global_position, throw_dir, extra)

## Remote shot broadcast: renders tracer and impact on every client
@rpc("any_peer", "call_remote", "unreliable")
func net_shot(start: Vector3, end: Vector3, hit_body: bool) -> void:
	create_tracer(start, end)
	if hit_body:
		_spawn_blood_splatter(end)

func _spawn_blood_splatter(pos: Vector3) -> void:
	# Visible 3D red blood burst at hit point
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 16
	p.lifetime = 0.45
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9.8, 0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.8, 0.05, 0.05)
	sm.emission_enabled = true
	sm.emission = Color(0.9, 0.0, 0.0)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.08)
	mesh.material = sm
	p.draw_pass_1 = mesh
	get_tree().root.add_child(p)
	p.global_position = pos
	var t := get_tree().create_timer(0.6)
	t.timeout.connect(p.queue_free)

func create_tracer(start: Vector3, end: Vector3):
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	# Thick, bright tracer visible across map
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = start.distance_to(end)
	mesh_inst.mesh = cyl

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.15)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = mat
	get_tree().root.add_child(mesh_inst)
	mesh_inst.position = (start + end) / 2.0

	var dir = (end - start).normalized()
	var up = Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT
	mesh_inst.look_at_from_position(mesh_inst.position, end, up)
	mesh_inst.rotation.x += PI / 2.0

	# Tween bound to the MESH: if the shooter is freed mid-fade (bot kicked,
	# player left), the fade still runs and the tracer can't orphan on the map
	var tween = mesh_inst.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	tween.tween_callback(mesh_inst.queue_free)

func _check_crosshair_target() -> void:
	if not hud: return
	if is_dead:
		hud.hide_hover_name()
		return
		
	var space_state = get_world_3d().direct_space_state
	var start = camera.global_position
	var end = start + (-camera.global_transform.basis.z * 100.0)
	var query = PhysicsRayQueryParameters3D.create(start, end)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var res = space_state.intersect_ray(query)
	
	if res:
		var target = res.collider
		var bot = target
		if not ("bot_name" in bot) and bot.get_parent():
			bot = bot.get_parent()
			if not ("bot_name" in bot) and bot.get_parent():
				bot = bot.get_parent()
		
		if "bot_name" in bot and bot.bot_name != "" and not bot.get("is_dead"):
			if bot.has_method("show_nametag_briefly"):
				bot.show_nametag_briefly()
			var is_enemy = bot.is_in_group("enemy")
			hud.show_hover_name(bot.bot_name, is_enemy)
			return
			
	hud.hide_hover_name()

func _process(_delta: float) -> void:
	pass

var _stuck_time: float = 0.0
var _last_safe_pos: Vector3 = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if is_puppet:
		_puppet_physics(delta)
		return
	if GlobalData.is_networked():
		_net_send_state()
	# Spectator camera drives everything; skip normal player sim
	if is_spectating:
		velocity = Vector3.ZERO
		_update_spectate_camera()
		return
	_check_crosshair_target()
	# Block all gameplay input while console is open
	if hud and hud.console_visible:
		if not is_on_floor():
			velocity.y -= gravity * delta
		velocity.x = move_toward(velocity.x, 0, speed_normal)
		velocity.z = move_toward(velocity.z, 0, speed_normal)
		move_and_slide()
		return

	# Drag held door
	if held_object != null:
		var dir = drag_position.global_position - held_object.global_position
		held_object.linear_velocity = dir * 10.0
		if held_object.global_position.distance_to(global_position) > 4.0:
			held_object = null

	if is_dead:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			respawn()
		# Still apply gravity but no input
		if not is_on_floor():
			velocity.y -= gravity * delta
		velocity.x = move_toward(velocity.x, 0, speed_normal)
		velocity.z = move_toward(velocity.z, 0, speed_normal)

		move_and_slide()
		return

	if fire_cooldown > 0: fire_cooldown -= delta

	if active_operator and hud:
		hud.update_skill_ui(active_operator.skill_name, active_operator.current_cooldown, active_operator.skill_cooldown)

	# --- NORMAL WEAPON LOGIC ---
	var w = weapons[active_slot]
	# --- OPERATOR SKILL BLOCK ---
	if active_operator and (active_operator.get("is_holding_bow") or active_operator.get("is_holding_skill")):
		if Input.is_action_just_pressed("fire") and active_operator.has_method("override_fire"):
			active_operator.override_fire()
		# Block ALL other weapon logic while holding an active ability device
		pass
	else:
		if w["type"] == "gun":
			if w["auto"]:
				if Input.is_action_pressed("fire") and fire_cooldown <= 0 and not is_reloading:
					if w["mag"] > 0: shoot_gun()
					elif w["res"] > 0: start_reload()
			else:
				if Input.is_action_just_pressed("fire") and fire_cooldown <= 0 and not is_reloading:
					if w["mag"] > 0: shoot_gun()
					elif w["res"] > 0: start_reload()
	
	# Process cooking Grenade
	if is_cooking:
		cook_timer += delta
		hud.update_cook_bar(cook_timer / MAX_COOK_TIME)
		if cook_timer >= MAX_COOK_TIME:
			throw_grenade() # Explodes instantly in hand!

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		
	if is_reloading:
		reload_timer += delta
		hud.update_reload(reload_timer / RELOAD_TIME)
		if reload_timer >= RELOAD_TIME:
			finish_reload()

	# Handle Scoping (w is declared above, in the weapon logic block)
	is_aiming = Input.is_action_pressed("aim") and not is_reloading and w["type"] == "gun"
	if active_operator and active_operator.has_method("override_aim") and active_operator.get("is_holding_bow"):
		is_aiming = false # Don't ADS while holding bow

	if is_aiming:
		if w.get("is_sniper", false):
			# Sniper logic
			camera.fov = lerp(camera.fov, 15.0, delta * 20.0) # Extreme zoom
			weapon_holder.visible = false # Hide 3D gun while looking through scope
			if sniper_scope_ui and camera.fov < 25.0: sniper_scope_ui.show()
		else:
			# Standard rifle ADS
			weapon_holder.position = weapon_holder.position.lerp(WEAPON_POS_ADS, delta * 15.0)
			camera.fov = lerp(camera.fov, FOV_ADS, delta * 15.0)
	else:
		# Hipfire
		weapon_holder.position = weapon_holder.position.lerp(WEAPON_POS_HIP, delta * 10.0)
		camera.fov = lerp(camera.fov, FOV_NORMAL, delta * 10.0)
		weapon_holder.visible = true
		if sniper_scope_ui: sniper_scope_ui.hide()
		
	weapon_holder.position += current_recoil + melee_swing_offset
	current_recoil = current_recoil.lerp(Vector3.ZERO, delta * 15.0)

	var target_lean_pos := 0.0
	var target_lean_rot := 0.0
	if Input.is_action_pressed("lean_left"):
		target_lean_pos = -LEAN_POS
		target_lean_rot = LEAN_ROT
	elif Input.is_action_pressed("lean_right"):
		target_lean_pos = LEAN_POS
		target_lean_rot = -LEAN_ROT
	head.position.x = lerp(head.position.x, target_lean_pos, delta * LEAN_SPEED)
	head.rotation.z = lerp(head.rotation.z, target_lean_rot, delta * LEAN_SPEED)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var holding_sprint_key = Input.is_action_pressed("sprint") and not is_exhausted and input_dir != Vector2.ZERO and not is_aiming and not is_reloading
	var wants_to_sprint = holding_sprint_key and not Input.is_action_pressed("crouch")

	# Slide requires you to be holding the sprint key BEFORE you hit crouch
	if Input.is_action_just_pressed("crouch") and holding_sprint_key and not is_sliding and is_on_floor():
		is_sliding = true
		slide_timer = SLIDE_DURATION
		slide_vector = input_dir

	var target_height := STAND_HEIGHT
	var current_speed := speed_normal
	var is_sprinting := false

	if is_sliding:
		target_height = CROUCH_HEIGHT
		slide_timer -= delta
		if slide_timer <= 0 or not Input.is_action_pressed("crouch") or not is_on_floor():
			is_sliding = false
		current_speed = lerp(speed_crouch, SPEED_SLIDE, slide_timer / SLIDE_DURATION)
		input_dir = slide_vector
	else:
		if Input.is_action_pressed("crouch"):
			target_height = CROUCH_HEIGHT
			current_speed = speed_crouch
			stamina += STAMINA_REGEN * delta
		elif wants_to_sprint:
			current_speed = speed_sprint
			is_sprinting = true
			stamina -= STAMINA_DRAIN * delta
		else:
			stamina += STAMINA_REGEN * delta
			
	stamina = clamp(stamina, 0.0, max_stamina)
	if stamina <= 0.0: is_exhausted = true
	elif stamina >= EXHAUST_RECOVERY: is_exhausted = false

	if is_on_floor() and not is_sliding:
		var speed_factor = Vector2(velocity.x, velocity.z).length()
		if speed_factor > 1.0:
			var bob_mult_y = 2.8 if is_sprinting else 1.0
			var bob_mult_x = 1.8 if is_sprinting else 0.5
			t_bob += delta * speed_factor * (1.2 if is_sprinting else 1.0) * 0.15
			camera.position.y = lerp(camera.position.y, sin(t_bob * BOB_FREQ) * BOB_AMP * bob_mult_y, delta * 12.0)
			camera.position.x = lerp(camera.position.x, cos(t_bob * BOB_FREQ * 0.5) * BOB_AMP * bob_mult_x, delta * 12.0)
		else:
			t_bob = 0.0
			camera.position.y = lerp(camera.position.y, 0.0, delta * 5.0)
			camera.position.x = lerp(camera.position.x, 0.0, delta * 5.0)
	else:
		t_bob = 0.0
		camera.position.y = lerp(camera.position.y, 0.0, delta * 5.0)
		camera.position.x = lerp(camera.position.x, 0.0, delta * 5.0)
		
	camera.rotation.x = lerp(camera.rotation.x, camera_recoil, delta * 12.0)
	camera_recoil = lerp(camera_recoil, 0.0, delta * 8.0)
	recoil_spread = lerp(recoil_spread, 0.0, delta * 5.0)

	if hud:
		hud.update_debug(velocity)
		hud.update_stats(hp, max_hp, armor, max_armor, stamina, max_stamina)
		hud.update_minimap(global_position, head.rotation.y)

	if collision_shape.shape is CapsuleShape3D:
		var shape = collision_shape.shape as CapsuleShape3D
		shape.height = lerp(shape.height, target_height, delta * CROUCH_SPEED)
		collision_shape.position.y = shape.height / 2.0
		head.position.y = lerp(head.position.y, target_height - 0.2, delta * CROUCH_SPEED)

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Bunny Hop Physics Constants
	var ACCEL = 10.0
	var AIR_ACCEL = 50.0
	var FRICTION = 6.0
	var MAX_AIR_SPEED = 1.5 # The max speed you can GAIN from holding a key in the air (caps pure air strafing)
	
	if is_on_floor():
		# Apply friction
		var speed = Vector2(velocity.x, velocity.z).length()
		if speed > 0:
			var drop = speed * FRICTION * delta
			var multiplier = max(speed - drop, 0) / speed
			velocity.x *= multiplier
			velocity.z *= multiplier
		
		# Apply Ground Acceleration
		var current_speed_dot = Vector2(velocity.x, velocity.z).dot(Vector2(direction.x, direction.z))
		var add_speed = current_speed - current_speed_dot
		if add_speed > 0:
			var accel_speed = min(ACCEL * delta * current_speed, add_speed)
			velocity.x += accel_speed * direction.x
			velocity.z += accel_speed * direction.z
	else:
		# Apply Air Acceleration (Bunny Hop)
		# To allow continuous speed gain, we project current velocity onto our input direction
		var current_air_speed = Vector2(velocity.x, velocity.z).dot(Vector2(direction.x, direction.z))
		# We cap the air speed gain to MAX_AIR_SPEED, which forces the player to turn their mouse (strafing) to keep gaining speed!
		var add_speed = MAX_AIR_SPEED - current_air_speed
		if add_speed > 0:
			var accel_speed = min(AIR_ACCEL * delta * MAX_AIR_SPEED, add_speed)
			velocity.x += accel_speed * direction.x
			velocity.z += accel_speed * direction.z

	# Anti-velcro: while moving UP, steep slopes act as walls (slide past them
	# instead of sticking); grounded/falling, they act as walkable 60° floor.
	if velocity.y > 0.5:
		floor_max_angle = deg_to_rad(45.0)
		floor_snap_length = 0.0
	else:
		floor_max_angle = deg_to_rad(60.0)
		floor_snap_length = 0.4

	move_and_slide()

	# Unstuck escape: input held but body not moving for 2.5s (wedged in map
	# seams / under overhangs) -> teleport back to last safe grounded spot.
	# ponytail: swap for sealed level geometry once ramp gaps are closed.
	var wants_move: bool = input_dir.length() > 0.1 or Input.is_action_pressed("jump")
	if wants_move and get_real_velocity().length() < 0.3:
		_stuck_time += delta
		if _stuck_time > 2.5:
			global_position = _last_safe_pos + Vector3.UP * 0.3
			velocity = Vector3.ZERO
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0
	# Remember last spot where we stood on solid ground and actually moved
	if is_on_floor() and not is_on_ceiling() and get_real_velocity().length() > 1.0:
		_last_safe_pos = global_position

	# Push rigid bodies like the physics door
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			c.get_collider().sleeping = false
			c.get_collider().apply_central_impulse(-c.get_normal() * 2.0)
			if c.get_collider().get_parent().has_method("register_interaction"):
					c.get_collider().get_parent().register_interaction()
