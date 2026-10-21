extends Operator

# ponytail: dart instance is moved to world on fire; reparented back on cancel.
# Ceiling hit: rope VFX still unshaded line; swap to textured cylinder when needed.
var is_holding_skill: bool = false
var is_grappling: bool = false
var player_ref: CharacterBody3D = null

const MAX_RANGE: float = 35.0
const PULL_SPEED: float = 26.0
const RELEASE_DIST: float = 1.8

var target_point: Vector3 = Vector3.ZERO
var rope_instance: MeshInstance3D = null
var rope_mesh: ImmediateMesh = null
var dart_ref: Node3D = null
var dart_home_parent: Node = null
var dart_home_transform: Transform3D = Transform3D.IDENTITY
var world_dart: Node3D = null
var _miss_hint_cd: float = 0.0

func _ready() -> void:
	op_name = "Greppy"
	max_health = 100
	max_armor = 50
	speed_mult = 1.1
	skill_name = "Grappler"
	skill_cooldown = 12.0

func _exit_tree() -> void:
	_clear_rope()
	_restore_dart()

func _restore_dart() -> void:
	if world_dart and is_instance_valid(world_dart) and dart_home_parent and is_instance_valid(dart_home_parent):
		var p: Node = world_dart.get_parent()
		if p: p.remove_child(world_dart)
		dart_home_parent.add_child(world_dart)
		world_dart.transform = dart_home_transform
		world_dart.show()
	world_dart = null
	dart_ref = null
	dart_home_parent = null

func _physics_process(delta: float) -> void:
	_miss_hint_cd = maxf(_miss_hint_cd - delta, 0.0)
	if current_cooldown > 0.0:
		current_cooldown -= delta

	if not player_ref:
		return

	if is_grappling:
		_process_pull()
	elif is_holding_skill:
		_process_aim_preview()

func _execute_skill(player: CharacterBody3D) -> void:
	if is_holding_skill or is_grappling:
		cancel_skill()
		return

	player_ref = player
	is_holding_skill = true
	is_grappling = false

	# Hide weapons while aiming the grappler
	var holder: Node3D = player.get_node("Head/Camera3D/WeaponHolder") as Node3D
	for w in holder.get_children():
		(w as Node3D).hide()
	var grappler_model: Node3D = holder.get_node_or_null("Grappler")
	if grappler_model:
		grappler_model.show()
		var dart: Node3D = grappler_model.get_node_or_null("Dart")
		if dart:
			dart.show()
			dart_ref = dart
			dart_home_parent = dart.get_parent()
			dart_home_transform = dart.transform

func override_fire() -> bool:
	if is_holding_skill:
		_fire_hook()
		return true
	return false

func override_aim() -> bool:
	return false

func _get_crosshair_hit() -> Dictionary:
	var cam: Camera3D = player_ref.camera
	var space_state: PhysicsDirectSpaceState3D = player_ref.get_world_3d().direct_space_state
	var from: Vector3 = cam.global_position
	var to: Vector3 = from + (-cam.global_transform.basis.z * MAX_RANGE)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player_ref.get_rid()]
	return space_state.intersect_ray(query)

func _get_muzzle_position() -> Vector3:
	if not player_ref: return Vector3.ZERO
	var grappler: Node3D = player_ref.get_node_or_null("Head/Camera3D/WeaponHolder/Grappler")
	if grappler:
		var marker: Marker3D = grappler.get_node_or_null("MuzzleMarker")
		if marker: return marker.global_position
	return player_ref.camera.global_position

func _process_aim_preview() -> void:
	var hit: Dictionary = _get_crosshair_hit()
	if hit.is_empty():
		_clear_rope()
	else:
		_draw_rope(_get_muzzle_position(), hit.position as Vector3)

func _fire_hook() -> void:
	var hit: Dictionary = _get_crosshair_hit()
	if hit.is_empty():
		# No anchor within MAX_RANGE: keep the grappler equipped — the player
		# re-aims and clicks again. Only warn, never auto-cancel/swap weapon.
		if _miss_hint_cd <= 0.0 and player_ref and player_ref.get("hud"):
			_miss_hint_cd = 0.8
			player_ref.hud.show_center_hint("Need to be closer")
		return

	target_point = hit.position as Vector3
	is_grappling = true

	# Move dart from viewmodel to world at target point
	if dart_ref and is_instance_valid(dart_ref):
		var root: Node = player_ref.get_tree().root
		dart_home_parent.remove_child(dart_ref)
		root.add_child(dart_ref)
		dart_ref.global_position = target_point
		# Orient dart head (-Z) into the surface along the rope direction
		var muzzle_pos: Vector3 = _get_muzzle_position()
		var dir: Vector3 = (target_point - muzzle_pos).normalized()
		if dir != Vector3.ZERO:
			var look_target: Vector3 = target_point + dir
			var up: Vector3 = Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT
			dart_ref.look_at_from_position(target_point, look_target, up)
		world_dart = dart_ref
		dart_ref = null

func _process_pull() -> void:
	var center: Vector3 = player_ref.global_position + Vector3(0.0, 1.0, 0.0)
	var diff: Vector3 = target_point - center

	# Update hook line every physics tick
	_draw_rope(_get_muzzle_position(), target_point)

	if diff.length() < RELEASE_DIST:
		start_cooldown()
		cancel_skill()
		return

	# Physics pull, never teleport: move_and_slide still resolves walls
	player_ref.velocity = diff.normalized() * PULL_SPEED

func _draw_rope(from: Vector3, to: Vector3) -> void:
	if rope_instance == null or not is_instance_valid(rope_instance):
		rope_mesh = ImmediateMesh.new()
		rope_instance = MeshInstance3D.new()
		rope_instance.mesh = rope_mesh

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.25, 0.9, 0.3, 1.0)
		rope_instance.material_override = mat
		player_ref.get_tree().root.add_child(rope_instance)

	rope_mesh.clear_surfaces()
	rope_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	rope_mesh.surface_add_vertex(from)
	rope_mesh.surface_add_vertex(to)
	rope_mesh.surface_end()

func _clear_rope() -> void:
	if rope_instance != null and is_instance_valid(rope_instance):
		rope_instance.queue_free()
	rope_instance = null
	rope_mesh = null

func cancel_skill() -> void:
	# Guard: switch_weapon() calls this too, prevents recursion
	if not is_holding_skill and not is_grappling:
		return

	var was_active: bool = true
	is_grappling = false
	is_holding_skill = false
	_clear_rope()
	_restore_dart()

	# Hide grappler model so it never stays visible after cancel
	if player_ref and is_instance_valid(player_ref):
		var grappler_model: Node3D = player_ref.get_node_or_null("Head/Camera3D/WeaponHolder/Grappler")
		if grappler_model: grappler_model.hide()

	if player_ref and is_instance_valid(player_ref) and was_active:
		player_ref.switch_weapon(player_ref.active_slot)
