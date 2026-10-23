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
const MAX_STEP_HEIGHT: float = 0.5
const CROUCH_SPEED: float = 8.0
const LEAN_POS: float = 0.6
const LEAN_ROT: float = deg_to_rad(15.0)
const LEAN_SPEED: float = 8.0

const BOB_FREQ: float = 2.4
const BOB_AMP: float = 0.12
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

# Vehicle piloting (see scripts/vehicles/aircraft_controller.gd)
var is_piloting: bool = false
var _pre_pilot_parent: Node = null
var _pre_pilot_layer: int = 1
var _pre_pilot_mask: int = 1

# Warzone-style skydive (freefall high above the ground)
const SKYDIVE_MIN_HEIGHT: float = 50.0  ## min height above ground to enter freefall
const SKYDIVE_FALL_GLIDE: float = 14.0  ## m/s descent while gliding (neutral)
const SKYDIVE_FALL_DIVE: float = 38.0   ## m/s descent while dive (Shift + move)
const SKYDIVE_MOVE_SPEED: float = 15.0  ## horizontal glide speed
const SKYDIVE_DIVE_SPEED: float = 28.0  ## horizontal speed while dive-diving
var is_skydiving: bool = false

# Weapon Loadout State
enum Slot { RIFLE, PISTOL, MELEE, THROWABLE, HEAVY }
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
var _reload_abort_requested: bool = false
const RELOAD_TIME: float = 1.5

const WEAPON_POS_HIP = Vector3(0.3, -0.3, -0.5)
const WEAPON_POS_ADS = Vector3(0.0, -0.22, -0.4)
const PITCH_LIMIT: float = deg_to_rad(87.0)  # keep off the ±90° euler pole (flip bug)
const WPN_SWAY_ROT: float = 0.0012  # rad per mouse pixel
const WPN_TILT_ROT: float = 0.035   # strafe tilt rad
const WPN_MOVE_POS: float = 0.035   # movement lag offset (m)
const WPN_BOB_AMT: float = 0.008    # viewmodel bob amplitude
const FOV_NORMAL = 75.0
const FOV_ADS = 55.0
var current_recoil := Vector3.ZERO
var camera_recoil := 0.0
var camera_yaw_recoil := 0.0
var mouse_input: Vector2 = Vector2.ZERO
var recoil_spread := 0.0
var _empty_click_cd := 0.0
var is_aiming := false
var melee_tween: Tween = null
var reload_tween: Tween = null
var melee_swing_offset := Vector3.ZERO
static var _tick_streams := {}

@onready var head: Node3D = $Head
@onready var flashlight = $Head/Flashlight
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var drag_position: Marker3D = $Head/Camera3D/DragPosition
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var hud = $HUD
@onready var pause_menu = get_node_or_null("PauseMenu")

## True while pause menu / in-game settings overlay is up — game input must not leak.
func _menu_open() -> bool:
	if pause_menu != null and pause_menu.visible:
		return true
	var mp_hud = get_tree().root.find_child("MultiplayerHUD", true, false)
	if mp_hud != null and mp_hud.get("side_picker") != null and mp_hud.side_picker.visible:
		return true
	return false

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
	# Steep map slopes (up to ~78°): treat them as walkable floor, not walls.
	floor_max_angle = deg_to_rad(78.0)
	floor_snap_length = 0.4
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_block_on_wall = false
	# Online match: a player node owned by ANOTHER peer is only a puppet (no input/camera/HUD)
	is_puppet = GlobalData.is_networked() and not is_multiplayer_authority()
	if is_puppet:
		_setup_puppet()
		return
	camera.make_current() # tscn current was stripped pre-add (puppet hijack fix); always reclaim the view
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Load Operator
	var op_script: Script = GlobalData.get_equipped_operator_script()
	if op_script != null:
		active_operator = op_script.new()
	else:
		active_operator = Node.new()
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
		GlobalData.get_equipped_throwable().duplicate(),
		GlobalData.get_equipped_heavy().duplicate()
	]
	weapons[Slot.THROWABLE]["amount"] = 1
	
	_push_hud_slot_names()
	switch_weapon(Slot.RIFLE)
	weapon_holder.position = WEAPON_POS_HIP
	weapon_holder.visible = true
	if sniper_scope_ui: sniper_scope_ui.hide()
	# Spawn protection (CS style): invulnerable for 5s or until movement
	if GlobalData.is_ffa_mode():
		spawn_protect_timer = 5.0
		_spawn_protect_origin = global_position
		if hud:
			hud.print_to_console("Spawn protection active (5s)")
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
	camera_recoil += 0.06 # small flinch so getting shot stays fightable (was 0.35)

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
	camera_recoil = 0.0
	camera_yaw_recoil = 0.0
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
var spawn_protect_timer: float = 0.0
var _spawn_protect_origin: Vector3 = Vector3.ZERO

# ---------------- Online play ----------------
var is_puppet: bool = false
var _net_target_pos: Vector3 = Vector3.ZERO
var _net_target_yaw: float = 0.0
var _net_target_pitch: float = 0.0
var _net_tick: int = 0
var _puppet_body: Node3D = null
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
	var body_scene := load("res://scenes/characters/human_body.tscn") as PackedScene
	_puppet_body = body_scene.instantiate() as Node3D
	var team_color := Color(0.3, 0.6, 1.0) if team == "attackers" else Color(1.0, 0.35, 0.3)
	(_puppet_body as HumanBody).set_tint(team_color)
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
	# Host-side state must match: without this the host still counts the dead
	# player as alive (S&D elimination never fires) and bots keep shooting the corpse.
	is_dead = true
	if is_instance_valid(_puppet_gun_holder):
		_puppet_gun_holder.visible = false
	if is_instance_valid(_puppet_body):
		var tween = create_tween().set_parallel(true)
		tween.tween_property(_puppet_body, "rotation:x", deg_to_rad(-90), 0.5).set_trans(Tween.TRANS_BOUNCE)
		tween.tween_property(_puppet_body, "position:y", 0.2, 0.5)

## Called by the MultiplayerManager with the owner's latest transform
func net_set_target(pos: Vector3, yaw: float, pitch: float) -> void:
	if not pos.is_finite() or not is_finite(yaw) or not is_finite(pitch):
		return
	_net_target_pos = pos
	_net_target_yaw = yaw
	_net_target_pitch = pitch

func _puppet_physics(delta: float) -> void:
	var t: float = min(1.0, delta * 15.0)
	var prev_pos := global_position
	if _net_target_pos.is_finite():
		global_position = global_position.lerp(_net_target_pos, t)
	rotation.y = lerp_angle(rotation.y, _net_target_yaw, t)
	if head:
		head.rotation.x = lerp_angle(head.rotation.x, _net_target_pitch, t)
	if is_instance_valid(_puppet_body) and _puppet_body.has_method("sync_movement"):
		var moved: bool = (Vector2(global_position.x - prev_pos.x, global_position.z - prev_pos.z).length() / maxf(delta, 0.001)) > 0.5
		_puppet_body.sync_movement(moved, false, false, not is_on_floor())

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
	# Spawn protection applies on the owning peer too
	if spawn_protect_timer > 0.0:
		return
	var mgr = get_tree().current_scene
	var my_faction: String = "Ally" if team == "attackers" else "Enemy"
	# FFA: everyone is hostile — skip the friendly-fire gate
	if attacker_faction != "" and attacker_faction == my_faction \
			and not GlobalData.is_ffa_mode():
		return # no friendly fire
	take_damage(amount, attacker_name, weapon_name, attacker_faction, attacker_pos)

## Warzone-style freefall: above SKYDIVE_MIN_HEIGHT the fall speed is capped
## (gentle glide) and air steering is enabled; Shift + move dives faster.
func _apply_fall_physics(delta: float) -> void:
	if not _is_high_above_ground():
		is_skydiving = false
		velocity.y -= gravity * delta
		return
	is_skydiving = true
	var wants_dive := Input.is_action_pressed("sprint") and \
		Input.get_vector("move_left", "move_right", "move_forward", "move_backward").length() > 0.1
	var target_fall := -SKYDIVE_FALL_DIVE if wants_dive else -SKYDIVE_FALL_GLIDE
	# Accelerate toward the cap at 2x gravity for a weighty but controlled entry
	velocity.y = move_toward(velocity.y, target_fall, gravity * 2.0 * delta)

func _is_high_above_ground() -> bool:
	# Perf: terrain across maps is y < 20 m; under 50 m absolute altitude player can never be 50 m above ground
	if global_position.y < SKYDIVE_MIN_HEIGHT:
		return false
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * SKYDIVE_MIN_HEIGHT,
		collision_mask, [get_rid()])
	return space.intersect_ray(query).is_empty() # nothing within 50m below = high freefall

func take_damage(amount: float, attacker_name: String = "", weapon_name: String = "", attacker_faction: String = "", attacker_pos: Vector3 = Vector3.INF) -> float:
	if is_puppet:
		# Remote copy: the owning peer applies the damage to the real player
		_net_apply_damage.rpc_id(get_multiplayer_authority(), amount, attacker_name, weapon_name, attacker_faction, attacker_pos)
		return amount
	if is_dead: return 0.0
	# Spawn protection: invulnerable until the timer lapses or we move
	if spawn_protect_timer > 0.0:
		return 0.0
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

func _die():
	die()

func die():
	is_dead = true
	# Drop carried bomb if this player is the S&D carrier
	var mgr_scene = get_tree().current_scene
	if mgr_scene and mgr_scene.has_method("drop_bomb") and mgr_scene.get("bomb_carrier_peer") != null:
		var my_pid := multiplayer.get_unique_id() if GlobalData.is_networked() else 1
		if int(mgr_scene.get("bomb_carrier_peer")) == my_pid:
			if multiplayer.is_server() or not GlobalData.is_networked():
				mgr_scene.drop_bomb(global_position)
			elif mgr_scene.has_method("request_drop_bomb"):
				mgr_scene.request_drop_bomb.rpc_id(1, global_position)
	# Cancel any in-progress reload anim
	if reload_tween and reload_tween.is_valid():
		reload_tween.kill()
	if is_instance_valid(current_weapon_instance):
		current_weapon_instance.rotation = Vector3.ZERO
	Sfx.stop_loop(_sfx_move)
	_sfx_move = null
	_sfx_move_state = ""
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
	if weapons[Slot.HEAVY].has("max_mag"):
		weapons[Slot.HEAVY]["mag"] = weapons[Slot.HEAVY]["max_mag"]
		weapons[Slot.HEAVY]["res"] = weapons[Slot.HEAVY]["max_res"]
	weapons[Slot.THROWABLE]["amount"] = 1
	
	_push_hud_slot_names()
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
	# Re-armed spawn protection on respawn (FFA modes)
	if GlobalData.is_ffa_mode():
		spawn_protect_timer = 5.0
		_spawn_protect_origin = global_position
		if hud:
			hud.print_to_console("Spawn protection active (5s)")

func _unhandled_input(event: InputEvent) -> void:
	if is_puppet: return
	if hud and hud.console_visible: return
	if _menu_open(): return
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
		if event.is_action_pressed("interact"):
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
	if is_piloting: return # Aircraft owns all input while piloting
	if event is InputEventMouseMotion:
		var current_sens = MOUSE_SENSITIVITY * GlobalSettings.hip_sensitivity_mult
		if is_aiming:
			current_sens = MOUSE_SENSITIVITY * GlobalSettings.scope_sensitivity_mult
			if active_slot == Slot.RIFLE and weapons[Slot.RIFLE]["name"] == "M700": # Specific sniper reduction
				current_sens *= 0.3
		
		rotate_y(-event.relative.x * current_sens)
		# Direct euler write: rotate_x() basis-multiply near the pitch pole flips
		# yaw 180° once lean roll (head.rotation.z) is active — repro'd headless.
		# Clamping raw pitch below 90° removes the flip entirely.
		head.rotation.x = clampf(head.rotation.x - event.relative.y * current_sens, -PITCH_LIMIT, PITCH_LIMIT)
		mouse_input = event.relative
		
	if event.is_action_pressed("weapon_1"): switch_weapon(Slot.RIFLE)
	if event.is_action_pressed("weapon_2"): switch_weapon(Slot.PISTOL)
	if event.is_action_pressed("weapon_3"): switch_weapon(Slot.MELEE)
	if event.is_action_pressed("weapon_4"): switch_weapon(Slot.THROWABLE)
	if event.is_action_pressed("weapon_5"): switch_weapon(Slot.HEAVY)

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


	# Throwable Logic (Equipment 01 — key 4)
	if active_slot == Slot.THROWABLE:
		if event.is_action_pressed("fire") and not is_cooking and weapons[Slot.THROWABLE]["amount"] > 0:
			is_cooking = true
			cook_timer = 0.0
		if event.is_action_released("fire") and is_cooking:
			throw_grenade()

	if event.is_action_pressed("aim") and active_operator and active_operator.has_method("override_aim"):
		if active_operator.override_aim():
			return # Skip the rest of the inputs if aim is overridden

	# Melee Attack
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

	# In weapon-locked modes (Flying Scoutsman), force primary rifle only
	var forced = str(GlobalData.get("force_primary_id"))
	if forced != "" and slot != Slot.RIFLE:
		return
	
	if active_operator and active_operator.has_method("cancel_skill"):
		active_operator.cancel_skill()
	
	# Animation cancel: Abort reload if switching
	if is_reloading:
		is_reloading = false
		if reload_tween and reload_tween.is_valid():
			reload_tween.kill()
		hud.update_reload(-1.0)
		
	if melee_tween and melee_tween.is_valid():
		melee_tween.kill()
	melee_swing_offset = Vector3.ZERO
	if reload_tween and reload_tween.is_valid():
		reload_tween.kill()
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

	
	if active_slot != Slot.HEAVY or w.get("type", "") != "launcher":
		_update_launcher_lock_reset()

	if hud:
		hud.update_weapon_slot(slot)
		if w["type"] == "gun" or w.get("type", "") == "launcher":
			hud.update_ammo(w.get("mag", 1), w.get("res", 0))
		elif w["type"] in ["util", "throwable"]:
			hud.update_ammo(w.get("amount", 0), 0)
		else:
			hud.update_ammo(0, 0) # hide or show 0

func _push_hud_slot_names() -> void:
	if not hud or not hud.has_method("set_weapon_names"):
		return
	var names: Array[String] = []
	for item in weapons:
		names.append(str(item.get("name", "Slot")))
	hud.set_weapon_names(names)



func get_active_reload_duration() -> float:
	var w = weapons[active_slot] if weapons.size() > active_slot else null
	if not w: return RELOAD_TIME
	var rt = float(w.get("reload_time", 0.0))
	return rt if rt > 0.0 else RELOAD_TIME

static var _click_stream: AudioStreamWAV = null

func _play_synth_tick(freq: float, dur: float, vol_db: float) -> void:
	# ponytail: synthesized mechanical tick (pump cycle / shell insert) — swap for real foley wavs when recorded
	var key := str(int(freq))
	if not _tick_streams.has(key):
		var n := maxi(int(22050.0 * dur), 2)
		var half := maxi(int(11025.0 / freq), 1)
		var b := PackedByteArray()
		b.resize(n)
		for i in n:
			var env: float = 1.0 - (float(i) / float(n))
			var hi: bool = (i % (half * 2)) < half
			b[i] = clampi(128 + int(70.0 * env * (1.0 if hi else -1.0)), 0, 255)
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_8_BITS
		s.mix_rate = 22050
		s.data = b
		_tick_streams[key] = s
	var p := AudioStreamPlayer.new()
	p.stream = _tick_streams[key]
	p.bus = "SFX"
	p.volume_db = vol_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func _play_empty_click() -> void:
	if _empty_click_cd > 0.0:
		return
	_empty_click_cd = 0.25
	fire_cooldown = 0.2
	if _click_stream == null:
		_click_stream = AudioStreamWAV.new()
		_click_stream.format = AudioStreamWAV.FORMAT_8_BITS
		_click_stream.mix_rate = 22050
		var b := PackedByteArray()
		b.resize(180)
		for i in 180:
			var env: float = 1.0 - (float(i) / 180.0)
			var sig: int = int(55.0 * env * (1.0 if (i % 8) < 4 else -1.0))
			b[i] = clampi(128 + sig, 0, 255)
		_click_stream.data = b
	var p := AudioStreamPlayer.new()
	p.stream = _click_stream
	p.bus = "SFX"
	p.volume_db = -4.0
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func _kill_reload_anim() -> void:
	if reload_tween and reload_tween.is_valid():
		reload_tween.kill()
	if is_instance_valid(current_weapon_instance):
		current_weapon_instance.rotation = Vector3.ZERO
		current_weapon_instance.position = Vector3.ZERO

func _start_reload_dip(dur: float, looping: bool) -> void:
	if not is_instance_valid(current_weapon_instance):
		return
	if reload_tween and reload_tween.is_valid():
		reload_tween.kill()
	current_weapon_instance.rotation = Vector3.ZERO
	current_weapon_instance.position = Vector3.ZERO
	reload_tween = create_tween()
	if looping:
		reload_tween.set_loops()
	reload_tween.tween_property(current_weapon_instance, "rotation:x", deg_to_rad(45), dur * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reload_tween.parallel().tween_property(current_weapon_instance, "position:y", -0.15, dur * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if not looping:
		reload_tween.tween_interval(dur * 0.2)
	reload_tween.tween_property(current_weapon_instance, "rotation:x", 0.0, dur * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	reload_tween.parallel().tween_property(current_weapon_instance, "position:y", 0.0, dur * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func start_reload():
	is_reloading = true
	reload_timer = 0.0
	_reload_abort_requested = false
	var w = weapons[active_slot]
	# Shotgun: per-shell dip; each finish_reload inserts 1 and chains next
	if w.get("is_shotgun", false):
		var per := float(w.get("reload_time", 0.52))
		_start_reload_dip(per, true)
		return
	# Reload sound for rifles/smgs
	var wid := str(w.get("id", ""))
	if wid in ["ak47", "m4a4", "mp5", "steyr_aug", "rpd"]:
		Sfx.oneshot3d("rifle_reload", self, 6.0, 40.0, 0.0)
	_start_reload_dip(get_active_reload_duration(), false)

func finish_reload():
	var w = weapons[active_slot]
	# Shell-by-shell for shotguns
	if w.get("is_shotgun", false):
		if _reload_abort_requested:
			_reload_abort_requested = false
			is_reloading = false
			_kill_reload_anim()
			hud.update_reload(-1.0)
			return
		if w["mag"] < w.get("max_mag", 0) and w["res"] > 0:
			w["mag"] += 1
			w["res"] -= 1
			_play_synth_tick(150.0, 0.05, -10.0)
			hud.update_ammo(w["mag"], w["res"])
			if w["mag"] >= w.get("max_mag", 0) or w["res"] <= 0:
				is_reloading = false
				_kill_reload_anim()
				hud.update_reload(-1.0)
			else:
				# Next shell
				reload_timer = 0.0
		else:
			is_reloading = false
			_kill_reload_anim()
			hud.update_reload(-1.0)
		return
	is_reloading = false
	_kill_reload_anim()
	hud.update_reload(-1.0)
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
		# Per-weapon recoil: vertical punch + horizontal wander + viewmodel kick
		var rv := float(w.get("recoil_v", 0.05))
		var rh := float(w.get("recoil_h", 0.0))
		var kv := float(w.get("kick_vm", 0.15))
		current_recoil = Vector3(randf_range(-rh, rh), 0, kv)
		camera_recoil += rv
		camera_yaw_recoil += randf_range(-rh, rh)
	
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
			recoil_spread += float(w.get("spread_per_shot", 0.02))
	
	var forward = -camera.global_transform.basis.z
	var right = camera.global_transform.basis.x
	var up = camera.global_transform.basis.y

	var ray_start = camera.global_position
	var space_state = get_world_3d().direct_space_state

	# Hitscan: 1 ray for rifles, N pellets in a cone for shotguns. Each pellet
	# raycasts independently so solid walls stop pellets (no through-cover hits).
	var pellet_count := maxi(int(w.get("pellets", 1)), 1)
	var pellet_cone := float(w.get("spread_base", 0.0))
	var w_name = str(w.get("id", w.get("name", "Gun")))
	var p_faction = "Ally" if team == "attackers" else ("Enemy" if team == "defenders" else "Player")
	var visual_end = ray_start + (forward * 100.0)
	var hit_body := false
	var logged_victim := false
	for pi in pellet_count:
		var spread_i: float = current_spread + (pellet_cone if pellet_count > 1 else 0.0)
		var shoot_dir = (forward + right * randf_range(-spread_i, spread_i) + up * randf_range(-spread_i, spread_i)).normalized()
		var end_pos = ray_start + (shoot_dir * 100.0)
		var query = PhysicsRayQueryParameters3D.create(ray_start, end_pos)
		query.collide_with_areas = true
		query.exclude = [get_rid()] # EXCLUDE THE PLAYER FROM THEIR OWN BULLETS
		var result = space_state.intersect_ray(query)

		if result:
			visual_end = result.position
			var target = result.collider
			if target.has_method("take_damage"):
				hit_body = true
				var final_dmg = target.take_damage(w["dmg"], player_name, w_name, p_faction, global_position)
				if final_dmg == null: final_dmg = w["dmg"]
				if hud and final_dmg > 0.0 and not logged_victim:
					hud.show_hit_marker(final_dmg)
				# Victim identity for console log (once per trigger pull)
				if not logged_victim:
					logged_victim = true
					var victim_entity = target
					if not ("bot_name" in victim_entity) and victim_entity.get_parent():
						victim_entity = victim_entity.get_parent()
						if not ("bot_name" in victim_entity) and victim_entity.get_parent():
							victim_entity = victim_entity.get_parent()
					var victim_name = str(victim_entity.get("bot_name")) if victim_entity.get("bot_name") != null and victim_entity.get("bot_name") != "" else "Enemy"
					GlobalData.log_combat("You hit %s for %d (%s)" % [victim_name, int(final_dmg), w_name])
			else:
				if pi == 0 or pellet_count == 1:
					_spawn_impact_puff(visual_end)
		# One thin tracer per pellet, thicker for the first
		var muzzle_pos0 = get_current_muzzle_position()
		create_tracer(muzzle_pos0, visual_end, 0.04 if pi == 0 else 0.014)
	
	var muzzle_pos = get_current_muzzle_position()
	_spawn_muzzle_effects(muzzle_pos)
	# Fire sound: one single-shot per bullet — holding trigger just repeats fast
	var wid := str(w.get("id", ""))
	if wid == "m700":
		Sfx.oneshot3d("sniper_shot", self, 18.0, 160.0, 2.0)
		# Bolt-action cycle: sound + viewmodel animation, timed after the report
		get_tree().create_timer(0.45).timeout.connect(_play_sniper_bolt_cycle)
	elif w.get("is_shotgun", false):
		# ponytail: no shotgun wav yet — heavier rifle report + synth pump foley
		Sfx.oneshot3d("rifle_single", self, 17.0, 150.0, 2.5)
		_play_pump_cycle()
	else:
		# ponytail: glock / desert_hawk have no dedicated assets yet — reuse rifle
		Sfx.oneshot3d("rifle_single", self, 14.0, 120.0, 1.0)
	# Every other peer sees the shot: tracer + blood puff on impact
	if GlobalData.is_networked():
		var mgr = get_tree().current_scene
		if mgr and mgr.has_method("send_tracer"):
			var snd := "sniper_shot" if wid == "m700" else "rifle_single"
			mgr.send_tracer(muzzle_pos, visual_end, 0.04, hit_body, snd)
		else:
			net_shot.rpc(muzzle_pos, visual_end, hit_body)

func _play_pump_cycle() -> void:
	# Pump-action: fore-end slides back then forward; blocked until done via fire_rate
	if not is_instance_valid(current_weapon_instance):
		return
	var pump := current_weapon_instance.find_child("Pump", true, false) as Node3D
	if pump == null:
		return
	var tz := pump.position.z
	var tw := create_tween()
	tw.tween_interval(0.1)
	tw.tween_property(pump, "position:z", tz + 0.085, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _play_synth_tick(90.0, 0.05, -6.0))
	tw.tween_interval(0.1)
	tw.tween_property(pump, "position:z", tz, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _play_synth_tick(120.0, 0.04, -8.0))

func _spawn_muzzle_effects(pos: Vector3) -> void:
	# Brief muzzle light flash
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.45)
	light.light_energy = 2.0
	light.omni_range = 3.5
	get_tree().root.add_child(light)
	light.global_position = pos
	var t := get_tree().create_timer(0.04)
	t.timeout.connect(light.queue_free)
	# Brief smoke wisp drifting up from the muzzle
	var smoke := CPUParticles3D.new()
	smoke.emitting = true
	smoke.one_shot = true
	smoke.explosiveness = 1.0
	smoke.amount = 4
	smoke.lifetime = 0.55
	smoke.direction = Vector3.UP
	smoke.spread = 15.0
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 1.2
	smoke.gravity = Vector3(0, 0.6, 0) # smoke rises
	smoke.scale_amount_min = 0.5
	smoke.scale_amount_max = 1.0
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.65, 0.65, 0.65, 0.35)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.05, 0.05)
	mesh.material = sm
	smoke.mesh = mesh
	get_tree().root.add_child(smoke)
	smoke.global_position = pos
	var t2 := get_tree().create_timer(0.7)
	t2.timeout.connect(smoke.queue_free)

func _spawn_impact_puff(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 8
	p.lifetime = 0.3
	p.direction = Vector3.UP
	p.spread = 120.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, -9.8, 0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.75, 0.7, 0.65)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.04, 0.04)
	mesh.material = sm
	p.mesh = mesh
	get_tree().root.add_child(p)
	p.global_position = pos
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(p.queue_free)

func _play_sniper_bolt_cycle() -> void:
	if not is_instance_valid(self) or is_dead or active_slot != Slot.RIFLE or is_reloading:
		return
	var w = weapons[active_slot] if weapons.size() > active_slot else null
	if not w or w.get("id") != "m700":
		return
	Sfx.oneshot3d("sniper_bolt", self, 14.0, 90.0, 1.0)
	# Animate the bolt handle and knob sliding back and returning on the 3D model
	if is_instance_valid(weapon_holder):
		var handle: Node3D = weapon_holder.find_child("BoltHandle", true, false)
		var knob: Node3D = weapon_holder.find_child("BoltKnob", true, false)
		if handle and knob:
			var orig_hz := handle.position.z
			var orig_kz := knob.position.z
			var tw := create_tween()
			tw.tween_property(handle, "position:z", orig_hz + 0.07, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(knob, "position:z", orig_kz + 0.07, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(handle, "position:z", orig_hz, 0.24).set_delay(0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(knob, "position:z", orig_kz, 0.24).set_delay(0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func get_current_muzzle_position() -> Vector3:
	if is_instance_valid(weapon_holder):
		var m = weapon_holder.find_child("Muzzle", true, false)
		if m == null:
			m = weapon_holder.find_child("MuzzleBrake", true, false)
		if m is Node3D:
			return (m as Node3D).global_position
	return camera.global_position + (-camera.global_transform.basis.z * 0.6) + (camera.global_transform.basis.y * -0.1)

# ---------------- AT4 Launcher Lock & Firing ----------------
const LOCK_MAX_PIXEL_DIST: float = 240.0 # wider vehicle scan cone (~240px from crosshair)
const LOCK_HOLD_TIME: float = 2.0 # 2 seconds to acquire lock
var _current_lock_target: Node3D = null
var _lock_timer: float = 0.0
var _locked_target: Node3D = null

func _update_launcher_lock(delta: float) -> void:
	if not hud or is_puppet or is_dead:
		_update_launcher_lock_reset()
		return

	var vp_size := get_viewport().get_visible_rect().size
	var crosshair_center := vp_size * 0.5
	var best_target: Node3D = null
	var best_dist := LOCK_MAX_PIXEL_DIST

	# Sticky tracking: keep latching the current target while it stays in range
	if _current_lock_target and is_instance_valid(_current_lock_target) and _current_lock_target.get("is_destroyed") != true:
		var cur_pos: Vector3 = _current_lock_target.global_position + Vector3(0, 0.8, 0)
		var cur_to := cur_pos - camera.global_position
		if cur_to.dot(-camera.global_transform.basis.z) > 0.0 and not camera.is_position_behind(cur_pos):
			var cur_dist := camera.unproject_position(cur_pos).distance_to(crosshair_center)
			if cur_dist <= LOCK_MAX_PIXEL_DIST:
				best_target = _current_lock_target
				best_dist = cur_dist

	var vehicles := get_tree().get_nodes_in_group("vehicles")
	for v in vehicles:
		if not is_instance_valid(v) or not (v is Node3D):
			continue
		if v.get("is_destroyed") == true:
			continue
		if v == _current_lock_target:
			continue # sticky path above already evaluated it
		# Must be in front of the camera
		var v_pos: Vector3 = v.global_position + Vector3(0, 0.8, 0)
		var to_v := v_pos - camera.global_position
		if to_v.dot(-camera.global_transform.basis.z) <= 0.0:
			continue
		if camera.is_position_behind(v_pos):
			continue
		var screen_pos := camera.unproject_position(v_pos)
		var dist := screen_pos.distance_to(crosshair_center)
		if dist <= best_dist:
			# Line of sight check
			var space := get_world_3d().direct_space_state
			var ray := PhysicsRayQueryParameters3D.create(camera.global_position, v_pos)
			ray.exclude = [get_rid()]
			var hit := space.intersect_ray(ray)
			if hit and (hit.collider == v or (hit.collider is Node and (hit.collider as Node).get_parent() == v)):
				best_dist = dist
				best_target = v

	if best_target != null:
		if _current_lock_target == best_target:
			_lock_timer = minf(_lock_timer + delta, LOCK_HOLD_TIME)
		else:
			_current_lock_target = best_target
			_lock_timer = 0.0
		var is_locked: bool = _lock_timer >= LOCK_HOLD_TIME
		_locked_target = best_target if is_locked else null
		var target_screen_pos := camera.unproject_position(best_target.global_position + Vector3(0, 0.8, 0))
		hud.show_lock_indicator(_lock_timer / LOCK_HOLD_TIME, is_locked, target_screen_pos)
	else:
		_update_launcher_lock_reset()

func _update_launcher_lock_reset() -> void:
	_current_lock_target = null
	_locked_target = null
	_lock_timer = 0.0
	if hud and hud.has_method("hide_lock_indicator"):
		hud.hide_lock_indicator()

func fire_launcher() -> void:
	var w = weapons[active_slot]
	w["mag"] -= 1
	fire_cooldown = w.get("fire_rate", 1.8)
	hud.update_ammo(w["mag"], w["res"])
	current_recoil = Vector3(0, 0, 0.45)
	camera_recoil += 0.22

	var rocket_scene = load("res://scenes/weapons/heavy/at4_rocket.tscn") as PackedScene
	if rocket_scene == null:
		return
	var rocket = rocket_scene.instantiate()
	var spawn_pos := get_current_muzzle_position()
	rocket.shooter_name = player_name
	rocket.shooter_faction = "Ally" if team == "attackers" else "Enemy"

	var aim_dir := -camera.global_transform.basis.z.normalized()
	# Straight to crosshair ray if not locked
	if _locked_target and is_instance_valid(_locked_target):
		rocket.target_vehicle = _locked_target
		rocket.direction = (rocket.target_vehicle.global_position + Vector3(0, 0.8, 0) - spawn_pos).normalized()
	else:
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + aim_dir * 300.0)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit:
			rocket.direction = (hit.position - spawn_pos).normalized()
		else:
			rocket.direction = aim_dir

	get_tree().root.add_child(rocket)
	rocket.global_position = spawn_pos
	var up := Vector3.UP if absf(rocket.direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	rocket.look_at(spawn_pos + rocket.direction, up)

	# Replicate to other peers (visual rocket; damage is shooter-authoritative)
	var mgr = get_tree().current_scene
	if mgr is MultiplayerManager:
		mgr.spawn_utility_net("res://scenes/weapons/heavy/at4_rocket.tscn", spawn_pos, rocket.direction, {
			"owner_name": player_name,
			"faction": "Ally" if team == "attackers" else "Enemy",
			# Re-lock the replica onto the same vehicle (deterministic tree path)
			"target_path": String(_locked_target.get_path()) if _locked_target != null and is_instance_valid(_locked_target) else "",
		})

	# Sound & muzzle flash
	Sfx.oneshot3d("missile", self, 20.0, 180.0, 3.0)
	_spawn_launcher_muzzle_flash(spawn_pos)
	_update_launcher_lock_reset()

func _spawn_launcher_muzzle_flash(pos: Vector3) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.3)
	flash.light_energy = 5.0
	flash.omni_range = 6.0
	get_tree().root.add_child(flash)
	flash.global_position = pos
	var t := create_tween()
	t.tween_property(flash, "light_energy", 0.0, 0.1)
	t.tween_callback(flash.queue_free)

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
	weapons[Slot.THROWABLE]["amount"] -= 1
	hud.update_ammo(weapons[Slot.THROWABLE]["amount"], 0)
	
	var w = weapons[Slot.THROWABLE]
	var proj_path = "res://scenes/weapons/utilities/grenade_projectile.tscn"
	if w.get("id", "") == "flashbang":
		proj_path = "res://scenes/weapons/utilities/flashbang_projectile.tscn"
	
	var proj = load(proj_path).instantiate()
	proj.owner_name = player_name
	proj.attacker_faction = "Ally" if team == "attackers" else "Enemy"
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
	_spawn_muzzle_effects(start)
	if hit_body:
		_spawn_blood_splatter(end)
	else:
		_spawn_impact_puff(end)
	# Peers hear the remote shooter's gun quietly through 3D attenuation
	if is_puppet:
		var curr_w = weapons[active_slot] if weapons.size() > active_slot else null
		var is_snp: bool = curr_w != null and (curr_w.get("id") == "m700" or bool(curr_w.get("is_sniper", false)))
		if is_snp:
			Sfx.oneshot3d("sniper_shot", self, 18.0, 160.0, 1.0)
			get_tree().create_timer(0.45).timeout.connect(func():
				if is_instance_valid(self) and not is_dead and is_puppet:
					Sfx.oneshot3d("sniper_bolt", self, 12.0, 80.0, 0.5)
			)
		else:
			Sfx.oneshot3d("rifle_single", self, 14.0, 120.0, 0.0)

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
	p.mesh = mesh
	get_tree().root.add_child(p)
	p.global_position = pos
	var t := get_tree().create_timer(0.6)
	t.timeout.connect(p.queue_free)

func create_tracer(start: Vector3, end: Vector3, radius: float = 0.04):
	if not start.is_finite() or not end.is_finite() or start.distance_squared_to(end) < 0.04:
		return
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	# Thick, bright tracer visible across map
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = start.distance_to(end)
	mesh_inst.mesh = cyl

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.15)
	mat.emission_energy_multiplier = 4.0 if radius > 0.05 else 3.0
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
	var fade_time: float = 0.4 if radius > 0.05 else 0.22
	tween.tween_property(mat, "albedo_color:a", 0.0, fade_time)
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
var _sfx_move: AudioStreamPlayer3D = null
var _sfx_move_state := ""

func _physics_process(delta: float) -> void:
	if is_puppet:
		_puppet_physics(delta)
		return
	if GlobalData.is_networked():
		_net_send_state()
	# Spawn protection countdown: cancelled on movement (CS rule)
	if spawn_protect_timer > 0.0:
		spawn_protect_timer -= delta
		var moved_dist := global_position.distance_to(_spawn_protect_origin)
		var wants_move := Input.get_vector("move_left", "move_right", "move_forward", "move_backward").length() > 0.1
		if moved_dist > 0.5 or wants_move or Input.is_action_pressed("jump"):
			spawn_protect_timer = 0.0
	# Aircraft has control: suspend all character simulation / input
	if is_piloting:
		return
	# Spectator camera drives everything; skip normal player sim
	if is_spectating:
		velocity = Vector3.ZERO
		_update_spectate_camera()
		return
	# Perf: hover-name ray at 20 Hz — nametag lag imperceptible
	if Engine.get_physics_frames() % 3 == 0:
		_check_crosshair_target()
	# Block all gameplay input while console or pause/settings menu is open
	if (hud and hud.console_visible) or _menu_open():
		if not is_on_floor():
			velocity.y -= gravity * delta
		velocity.x = move_toward(velocity.x, 0, speed_normal)
		velocity.z = move_toward(velocity.z, 0, speed_normal)
		move_and_slide()
		return

	# Intermission freeze: spawn-locked until the round countdown ends
	var mgr_node = get_tree().current_scene
	if mgr_node and mgr_node.get("players_frozen") == true:
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
		# S&D: no auto-respawn mid-round; drop into spectator after death cam
		var mgr = get_tree().current_scene
		if mgr and mgr.get("disable_auto_respawn") == true:
			respawn_timer = 0.0
			if not is_spectating:
				call_deferred("enter_spectator_mode")
		else:
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

	_snd_process_interactions()

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
					else: _play_empty_click()
			else:
				if Input.is_action_just_pressed("fire") and fire_cooldown <= 0:
					# Pump-action: firing interrupts a shell-by-shell reload
					if is_reloading and w.get("is_shotgun", false):
						_reload_abort_requested = true
						finish_reload() # abort pending insertion cleanly
					if not is_reloading:
						if w["mag"] > 0: shoot_gun()
						elif w["res"] > 0: start_reload()
						else: _play_empty_click()
		elif w["type"] == "launcher":
			_update_launcher_lock(delta)
			# Tube reload: after cooldown, chamber next rocket from reserve
			if w["mag"] <= 0 and w["res"] > 0 and fire_cooldown <= 0:
				w["res"] -= 1
				w["mag"] = 1
				hud.update_ammo(w["mag"], w["res"])
			if Input.is_action_just_pressed("fire") and fire_cooldown <= 0 and w["mag"] > 0:
				fire_launcher()
		else:
			_update_launcher_lock_reset()

	# Process cooking Grenade
	if is_cooking:
		cook_timer += delta
		hud.update_cook_bar(cook_timer / MAX_COOK_TIME)
		if cook_timer >= MAX_COOK_TIME:
			throw_grenade() # Explodes instantly in hand!

	if not is_on_floor():
		_apply_fall_physics(delta)
	else:
		is_skydiving = false

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		
	if _empty_click_cd > 0.0: _empty_click_cd -= delta

	if is_reloading:
		reload_timer += delta
		var cur_w = weapons[active_slot]
		var cur_dur := float(cur_w.get("reload_time", 0.52)) if cur_w.get("is_shotgun", false) else get_active_reload_duration()
		hud.update_reload(reload_timer / cur_dur)
		if reload_timer >= cur_dur:
			finish_reload()

	# Handle Scoping (w is declared above, in the weapon logic block)
	is_aiming = Input.is_action_pressed("aim") and not is_reloading and w["type"] == "gun"
	if active_operator and active_operator.has_method("override_aim") and active_operator.get("is_holding_bow"):
		is_aiming = false # Don't ADS while holding bow

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	# Movement lag: drifts opposite strafe, pulls back on S / pushes on W
	var move_off := Vector3(input_dir.x * WPN_MOVE_POS, 0.0, input_dir.y * WPN_MOVE_POS) * (0.2 if is_aiming else 1.0)

	if is_aiming:
		if w.get("is_sniper", false):
			# Sniper logic
			camera.fov = lerp(camera.fov, 15.0, delta * 20.0) # Extreme zoom
			weapon_holder.visible = false # Hide 3D gun while looking through scope
			if sniper_scope_ui and camera.fov < 25.0: sniper_scope_ui.show()
		else:
			# Standard rifle ADS
			weapon_holder.position = weapon_holder.position.lerp(WEAPON_POS_ADS + move_off, delta * 15.0)
			camera.fov = lerp(camera.fov, FOV_ADS, delta * 15.0)
	else:
		# Hipfire
		weapon_holder.position = weapon_holder.position.lerp(WEAPON_POS_HIP + move_off, delta * 10.0)
		camera.fov = lerp(camera.fov, FOV_NORMAL, delta * 10.0)
		weapon_holder.visible = true
		if sniper_scope_ui: sniper_scope_ui.hide()

	# Skydive FOV: extra wind-speed sensation; strongest while dive-diving
	if is_skydiving and not is_aiming:
		var sky_fov := FOV_NORMAL + (12.0 if Input.is_action_pressed("sprint") else 5.0)
		camera.fov = lerp(camera.fov, sky_fov, delta * 4.0)
		
	# --- Weapon sway: mouse look + movement lag (strafe L/R, walk F/B) ---
	# Melee tween owns holder rotation while a swing is playing.
	if not (melee_tween and melee_tween.is_valid()):
		var sway_scale: float = 0.15 if is_aiming else 1.0
		weapon_holder.rotation.x = lerp(weapon_holder.rotation.x, (mouse_input.y * WPN_SWAY_ROT + input_dir.y * WPN_TILT_ROT * 0.6) * sway_scale, 10.0 * delta)
		weapon_holder.rotation.y = lerp(weapon_holder.rotation.y, -mouse_input.x * WPN_SWAY_ROT * sway_scale, 10.0 * delta)
		weapon_holder.rotation.z = lerp(weapon_holder.rotation.z, input_dir.x * WPN_TILT_ROT * sway_scale, 10.0 * delta)
	mouse_input = mouse_input.lerp(Vector2.ZERO, 10.0 * delta)

	var bob_off := Vector3.ZERO
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 1.0:
		var bob_amt: float = WPN_BOB_AMT * (0.25 if is_aiming else 1.0)
		var t_ms := float(Time.get_ticks_msec())
		bob_off = Vector3(sin(t_ms * 0.005) * bob_amt, sin(t_ms * 0.01) * bob_amt, 0.0)

	weapon_holder.position += current_recoil + melee_swing_offset + bob_off
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
	# Heavy weapon mobility penalty (e.g. RPD LMG speed_mult 0.85)
	if weapons.size() > active_slot:
		current_speed *= float(weapons[active_slot].get("speed_mult", 1.0))

	# Footstep / slide loops: state-based, positional (quieter with distance)
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var move_state := ""
	if is_sliding:
		move_state = "slide"
	elif is_on_floor() and hspeed > 1.0:
		move_state = "run" if (is_sprinting or hspeed > speed_normal * 1.3) else "walk"
	if move_state != _sfx_move_state:
		_sfx_move_state = move_state
		Sfx.stop_loop(_sfx_move)
		_sfx_move = null
		if move_state != "":
			_sfx_move = Sfx.loop3d(move_state, self, 3.0, 28.0, -8.0)

	if is_on_floor() and not is_sliding:
		var speed_factor = Vector2(velocity.x, velocity.z).length()
		if speed_factor > 1.0:
			var bob_mult_y: float = 3.0 if is_sprinting else 1.0
			var bob_mult_x: float = 2.2 if is_sprinting else 0.6
			t_bob += delta * speed_factor * (1.25 if is_sprinting else 1.0) * 0.15
			# Deeper figure-8 sway; sprinting layers a fast camera shake.
			# Shake skipped while ADS so scopes stay steady.
			var shake: float = 0.0
			if is_sprinting and not is_aiming:
				shake = 0.03
			var target_y := sin(t_bob * BOB_FREQ) * BOB_AMP * bob_mult_y \
				+ sin(t_bob * BOB_FREQ * 2.7) * shake
			var target_x := cos(t_bob * BOB_FREQ * 0.5) * BOB_AMP * bob_mult_x \
				+ sin(t_bob * BOB_FREQ * 3.1 + 1.3) * shake * 0.6
			camera.position.y = lerp(camera.position.y, target_y, delta * 12.0)
			camera.position.x = lerp(camera.position.x, target_x, delta * 12.0)
			# Sway roll: strafe lean + bob wobble (recoil only owns rotation x/y)
			camera.rotation.z = lerp(camera.rotation.z,
				-input_dir.x * 0.022 + sin(t_bob * BOB_FREQ * 0.5) * 0.014 * bob_mult_x,
				delta * 8.0)
		else:
			t_bob = 0.0
			camera.position.y = lerp(camera.position.y, 0.0, delta * 5.0)
			camera.position.x = lerp(camera.position.x, 0.0, delta * 5.0)
			camera.rotation.z = lerp(camera.rotation.z, 0.0, delta * 8.0)
	else:
		t_bob = 0.0
		camera.position.y = lerp(camera.position.y, 0.0, delta * 5.0)
		camera.position.x = lerp(camera.position.x, 0.0, delta * 5.0)
		camera.rotation.z = lerp(camera.rotation.z, 0.0, delta * 8.0)
		
	camera.rotation.x = lerp(camera.rotation.x, camera_recoil, delta * 12.0)
	camera.rotation.y = lerp(camera.rotation.y, camera_yaw_recoil, delta * 10.0)
	camera_recoil = lerp(camera_recoil, 0.0, delta * 8.0)
	camera_yaw_recoil = lerp(camera_yaw_recoil, 0.0, delta * 8.0)
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
		if is_skydiving:
			# Warzone-style Skydive Air Steering: smooth aerodynamic glide in facing direction
			var wants_dive := Input.is_action_pressed("sprint") and input_dir.length() > 0.1
			var target_hspeed := SKYDIVE_DIVE_SPEED if wants_dive else SKYDIVE_MOVE_SPEED
			var target_hvel: Vector3 = direction * target_hspeed if direction.length() > 0.1 else Vector3.ZERO
			var blend_rate := 4.5 if wants_dive else 3.0
			var cur_hvel := Vector3(velocity.x, 0.0, velocity.z)
			var new_hvel := cur_hvel.lerp(target_hvel, 1.0 - exp(-blend_rate * delta))
			velocity.x = new_hvel.x
			velocity.z = new_hvel.z
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
	# instead of sticking). Grounded/falling, slides up to ~76° count as floor
	# so the spawn ramps are climbable.
	if velocity.y > 0.5:
		floor_max_angle = deg_to_rad(45.0)
		floor_snap_length = 0.0
	else:
		floor_max_angle = deg_to_rad(78.0)
		floor_snap_length = 0.4

	# Smooth stair climb: detect a riser in our path and glide onto its tread.
	# Runs BEFORE move_and_slide so the lift counts for this frame's motion.
	# ponytail: ray-based; replace with ramp meshes if stairs get curved.
	if is_on_floor() and input_dir.length() > 0.1:
		var space := get_world_3d().direct_space_state
		var probe_dist: float = clamp(velocity.length() * delta * 2.0, 0.4, 0.7)
		var feet := global_position
		var low_ray := PhysicsRayQueryParameters3D.create(
			feet + Vector3.UP * 0.08, feet + Vector3.UP * 0.08 + direction * probe_dist,
			collision_mask, [get_rid()])
		var low := space.intersect_ray(low_ray)
		if not low.is_empty():
			var high_from := feet + Vector3.UP * (MAX_STEP_HEIGHT + 0.06)
			var high_ray := PhysicsRayQueryParameters3D.create(
				high_from, high_from + direction * (probe_dist + 0.15),
				collision_mask, [get_rid()])
			if space.intersect_ray(high_ray).is_empty():
				var tread_from: Vector3 = low.position + direction * 0.15 + Vector3.UP * (MAX_STEP_HEIGHT + 0.06)
				var tread_ray := PhysicsRayQueryParameters3D.create(
					tread_from, tread_from + Vector3.DOWN * (MAX_STEP_HEIGHT + 0.1),
					collision_mask, [get_rid()])
				var tread := space.intersect_ray(tread_ray)
				if not tread.is_empty() and tread.normal.dot(Vector3.UP) > 0.6:
					var rise: float = tread.position.y - feet.y
					if rise > 0.03 and rise <= MAX_STEP_HEIGHT:
						global_position.y = tread.position.y + 0.02

	move_and_slide()

	# Mantle assist: spawn platform top is 1.18m ABOVE the slide ramp — taller
	# than any step, so jump/push into it to vault up ledges up to 1.35m.
	const MANTLE_HEIGHT := 1.35
	var wants_climb := input_dir.length() > 0.1 or Input.is_action_pressed("jump")
	if is_on_wall() and wants_climb:
		var space := get_world_3d().direct_space_state
		var wish := direction if direction.length() > 0.1 else -global_transform.basis.z
		var body_h: float = collision_shape.shape.height if collision_shape.shape is CapsuleShape3D else 2.0
		var mantle_target := global_position + Vector3.UP * MANTLE_HEIGHT + wish * 0.4
		var body_test := PhysicsShapeQueryParameters3D.new()
		body_test.shape = collision_shape.shape
		# CapsuleShape3D origin is its CENTER, not its feet — offset by half height
		body_test.transform = Transform3D(Basis(), mantle_target + Vector3.UP * (body_h / 2.0))
		body_test.exclude = [get_rid()]
		body_test.collision_mask = collision_mask
		# Downward probe from above ledge: must find solid ground within reach
		var down_ray := PhysicsRayQueryParameters3D.create(
			mantle_target, mantle_target + Vector3.DOWN * (MANTLE_HEIGHT + 0.2),
			collision_mask, [get_rid()]
		)
		var hit := space.intersect_ray(down_ray)
		if not hit.is_empty() and space.intersect_shape(body_test, 1).is_empty():
			global_position = hit.position + Vector3.UP * 0.08
			velocity.y = max(velocity.y, 0.0)

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


# ---------------- Vehicle piloting ----------------

## Called by an aircraft controller: suspend character control, take the seat.
func enter_aircraft(seat: Node3D) -> void:
	if is_piloting or is_dead:
		return
	is_piloting = true
	velocity = Vector3.ZERO
	set_physics_process(false)
	_pre_pilot_parent = get_parent()
	_pre_pilot_layer = collision_layer
	_pre_pilot_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		col.set_deferred("disabled", true)
	reparent(seat, false)
	transform = Transform3D.IDENTITY
	# Local-only nodes are freed on remote puppets — always guard (a crash here
	# used to abort before _puppet_body was hidden, leaving ghost bodies).
	if is_instance_valid(weapon_holder):
		weapon_holder.visible = false
	if is_instance_valid(flashlight):
		flashlight.visible = false
	if is_instance_valid(camera):
		camera.current = false
	_apply_seated_pose(seat)
	if is_instance_valid(_puppet_gun_holder):
		_puppet_gun_holder.visible = false
	if hud:
		hud.hide_hover_name()
		hud.toggle_aircraft_hud(true)


## Seat 3-6 (markers Pass2..Pass5) show the
## third-person body seated on the bench; cockpit seats keep it hidden
## (it would clip the glass).
## Body-local offset from each heli cabin seat marker to the bench cushion
## (from helicopter.tscn bench meshes; marker row 2 sits behind bench row 2,
## so the Z shift differs per row). Crouch holds its final frame = seated pose.
const SEAT_BODY_OFFSETS := {
	"Pass2": Vector3(-0.8, -0.263, -0.126),
	"Pass3": Vector3(0.8, -0.263, -0.126),
	"Pass4": Vector3(-0.8, -0.263, -0.372),
	"Pass5": Vector3(0.8, -0.263, -0.372),
}


func _apply_seated_pose(seat: Node3D) -> void:
	var offset: Vector3 = SEAT_BODY_OFFSETS.get(String(seat.name), Vector3.ZERO)
	if offset == Vector3.ZERO:
		if is_instance_valid(_puppet_body):
			_puppet_body.visible = false
			_puppet_body.position = Vector3.ZERO
		return
	if not is_instance_valid(_puppet_body):
		var body_scene := load("res://scenes/characters/human_body.tscn") as PackedScene
		if body_scene:
			_puppet_body = body_scene.instantiate() as Node3D
			var team_color := Color(0.3, 0.6, 1.0) if team == "attackers" else Color(1.0, 0.35, 0.3)
			if _puppet_body is HumanBody:
				(_puppet_body as HumanBody).set_tint(team_color)
			add_child(_puppet_body)
	if is_instance_valid(_puppet_body):
		_puppet_body.visible = true
		_puppet_body.position = offset
		_puppet_body.rotation = Vector3.ZERO
		var hb := _puppet_body as HumanBody
		if hb:
			hb.play_anim("Crouch")


## Called by a vehicle controller when the occupant moves between seats
## (CTRL + number). Player stays piloting — only re-parents to the new seat.
func switch_aircraft_seat(seat: Node3D) -> void:
	if not is_piloting or is_dead:
		return
	reparent(seat, false)
	transform = Transform3D.IDENTITY
	_apply_seated_pose(seat)


## Called by the aircraft controller: leave the seat, restore character control.
## eject_vel != ZERO flings the player airborne (ejection seat).
func exit_aircraft(exit_pos: Vector3, face_dir: Vector3, eject_vel: Vector3 = Vector3.ZERO) -> void:
	if not is_piloting:
		return
	is_piloting = false
	set_physics_process(true)
	if _pre_pilot_parent and is_instance_valid(_pre_pilot_parent):
		reparent(_pre_pilot_parent, false)
	global_position = exit_pos
	rotation = Vector3(0.0, atan2(-face_dir.x, -face_dir.z), 0.0)
	velocity = eject_vel
	collision_layer = _pre_pilot_layer
	collision_mask = _pre_pilot_mask
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		col.set_deferred("disabled", false)
	if is_instance_valid(weapon_holder):
		weapon_holder.visible = true
	if is_instance_valid(camera):
		camera.current = true
	if is_instance_valid(_puppet_body):
		_puppet_body.visible = is_puppet
		_puppet_body.rotation = Vector3.ZERO
		_puppet_body.position = Vector3.ZERO
		var hb := _puppet_body as HumanBody
		if hb:
			hb.play_anim("Idle")
	if is_instance_valid(_puppet_gun_holder):
		_puppet_gun_holder.visible = true
	if hud:
		hud.hide_hover_name()
		hud.toggle_aircraft_hud(false)


# ---------------- Search & Destroy: bomb interactions ----------------
## Uses the existing "interact" action (F key) / E key as hold-to-act input.
## Clients only REQUEST the host; all validation + timing is host-side
## (see SearchAndDestroyManager). Nothing here decides success locally.

var _snd_interact_held: bool = false
var _snd_active_request: String = "" # "", "PLANT", "DEFUSE", "PICKUP"
var _snd_site_in_range: String = ""

func _snd_process_interactions() -> void:
	var mgr = get_tree().current_scene
	if mgr == null or mgr.get("is_search_and_destroy") != true:
		return

	# Which interact key is held? "interact" action OR E key.
	var held := Input.is_action_pressed("interact")
	var just_released := _snd_interact_held and not held
	_snd_interact_held = held

	# Find what's in range (bomb state arrives as int enum: 0 CARRIED, 1 DROPPED,
	# 2 PLANTING, 3 PLANTED, 4 DEFUSING — same pattern as multiplayer_hud _on_time_tick)
	var bomb_state := int(mgr.get("current_bomb_state") if mgr.get("current_bomb_state") != null else 0)
	var dropped: bool = bomb_state == 1
	var planted: bool = bomb_state == 3 or bomb_state == 4
	var carried_by_me: bool = mgr.get("bomb_carrier_peer") == multiplayer.get_unique_id() \
		or (multiplayer.is_server() and mgr.get("bomb_carrier_peer") == 1)
	var in_site: String = _snd_get_site_in_range()
	_snd_site_in_range = in_site

	var my_team: String = team
	var prompt := ""
	var requested := ""

	if not is_dead:
		# PLANTING (2) must keep the request latched: host sets it locally the
		# same frame the start lands — strict CARRIED check would cancel-restart
		# the plant every physics frame and progress would never accumulate.
		# requested is gated on `held`: entering range alone must NOT trigger.
		if carried_by_me and in_site != "" and (bomb_state == 0 or bomb_state == 2):
			prompt = "HOLD [F] TO PLANT BOMB AT SITE %s" % in_site
			if held:
				requested = "PLANT"
		elif my_team == "defenders" and planted:
			var bpos: Vector3 = mgr.get("bomb_world_position")
			if global_position.distance_to(bpos) <= 4.0:
				prompt = "HOLD [F] TO DEFUSE BOMB"
				if held:
					requested = "DEFUSE"
		elif my_team == "attackers" and dropped:
			var bpos2: Vector3 = mgr.get("bomb_world_position")
			if global_position.distance_to(bpos2) <= 4.0:
				prompt = "WALK OVER BOMB TO PICK UP"

	# Send request transitions to the host
	if requested != "" and _snd_active_request != requested:
		_snd_send_request(requested, true)
		_snd_active_request = requested
	elif requested == "" and _snd_active_request != "":
		_snd_send_request(_snd_active_request, false)
		_snd_active_request = ""
	elif just_released and _snd_active_request != "":
		_snd_send_request(_snd_active_request, false)
		_snd_active_request = ""

	# HUD prompt
	if hud:
		if prompt != "":
			hud.show_hover_name(prompt)
		else:
			hud.hide_hover_name()

func _snd_send_request(action: String, start: bool) -> void:
	var mgr = get_tree().current_scene
	if mgr == null: return
	if GlobalData.is_networked() and not multiplayer.is_server():
		match action:
			"PLANT":
				if start: mgr.request_start_plant.rpc_id(1, _snd_site_in_range)
				else: mgr.request_stop_plant.rpc_id(1)
			"DEFUSE":
				if start: mgr.request_start_defuse.rpc_id(1)
				else: mgr.request_stop_defuse.rpc_id(1)
			"PICKUP":
				if start: mgr.request_pickup_bomb.rpc_id(1)
	else:
		match action:
			"PLANT":
				if start: mgr.request_start_plant(_snd_site_in_range)
				else: mgr.request_stop_plant()
			"DEFUSE":
				if start: mgr.request_start_defuse()
				else: mgr.request_stop_defuse()
			"PICKUP":
				if start: mgr.request_pickup_bomb()
			_:
				pass

func _snd_get_site_in_range() -> String:
	for site in get_tree().get_nodes_in_group("bombsite"):
		if site.has_method("is_point_inside") and site.is_point_inside(global_position):
			return str(site.get("site_id"))
	return ""
