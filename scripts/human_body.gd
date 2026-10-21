@tool
class_name HumanBody
extends Node3D

## Humanoid rig wrapping Body.tscn with synced animations:
## - Idle: standby / standing still
## - Run: running, walking, jumping
## - Crouch: crouching
## - Slide: sliding
## Rig and Rig_001 are authoring actions and ignored.
## Surface 1 (Clothes) and Surface 2 (Pants) receive the team tint.

const DEFAULT_CLOTHES := Color(0.36, 0.40, 0.33)
const TINT_SURFACES: Array[int] = [1, 2]
const HUMAN_AABB := AABB(Vector3(-0.5, 0.0, -0.3), Vector3(1.0, 1.9, 0.6))

# Scaling: Body.tscn is ~7.99m in pose, feet at -5.434m.
# Scale 0.2375 + Y offset 1.2907 places feet at Y=0 and top of helmet at Y=1.9m,
# matching the 2.0m CapsuleShape3D collision exactly.
const MODEL_SCALE := Vector3(0.2375, 0.2375, 0.2375)
const MODEL_OFFSET := Vector3(0.0, 1.2907, 0.0)

@export var tint_color := DEFAULT_CLOTHES:
	set(c):
		tint_color = c
		_apply_tint()

var _tint_mat: StandardMaterial3D
var _mesh_inst: MeshInstance3D
var _flash_tween: Tween
var _anim_player: AnimationPlayer
var _current_anim: String = ""

func _ready() -> void:
	_resolve_nodes()
	_apply_tint()
	if not Engine.is_editor_hint():
		play_anim("Idle")

func _resolve_nodes() -> void:
	if _mesh_inst == null or not is_instance_valid(_mesh_inst):
		_mesh_inst = find_child("Player", true, false) as MeshInstance3D
		if _mesh_inst != null:
			_mesh_inst.custom_aabb = HUMAN_AABB
	if _anim_player == null or not is_instance_valid(_anim_player):
		_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _anim_player != null:
			# Configure looping for continuous motions
			for a in ["Idle", "Run"]:
				if _anim_player.has_animation(a):
					_anim_player.get_animation(a).loop_mode = Animation.LOOP_LINEAR

	# Ensure scaling and 180-deg Y-rotation are enforced at runtime (Godot forward is -Z)
	var model := get_node_or_null("PlayerModel") as Node3D
	if model != null:
		model.basis = Basis(Vector3.UP, PI).scaled(MODEL_SCALE)
		model.position = MODEL_OFFSET

func _apply_tint() -> void:
	_resolve_nodes()
	if _mesh_inst == null:
		return
	if _tint_mat == null:
		_tint_mat = StandardMaterial3D.new()
		_tint_mat.roughness = 0.85
	_tint_mat.albedo_color = tint_color
	for s in TINT_SURFACES:
		if s < _mesh_inst.mesh.get_surface_count():
			_mesh_inst.set_surface_override_material(s, _tint_mat)

func set_tint(c: Color) -> void:
	tint_color = c
	_apply_tint()

func get_tint() -> Color:
	return tint_color

func set_overlay(mat: Material) -> void:
	_resolve_nodes()
	if _mesh_inst:
		_mesh_inst.material_overlay = mat

func clear_overlay() -> void:
	set_overlay(null)

## Flash body red then fade back to `normal` color (hit feedback).
func flash_hit(normal: Color) -> void:
	if _flash_tween:
		_flash_tween.kill()
	set_tint(Color(1, 0, 0))
	_flash_tween = create_tween()
	_flash_tween.tween_method(set_tint, Color(1, 0, 0), normal, 0.2)

# ---------------- Animation Sync ----------------

## High-level movement state to model animation mapping.
## Ignores internal authoring actions (Rig, Rig_001).
func sync_movement(is_moving: bool, is_crouching: bool, is_sliding: bool, is_airborne: bool = false) -> void:
	if is_sliding:
		play_anim("Slide")
	elif is_crouching:
		play_anim("Crouch")
	elif is_airborne:
		play_anim("Run") # Jump re-uses run animation per design
	elif is_moving:
		play_anim("Run") # Both walk and run map to the run anim
	else:
		play_anim("Idle")

func play_anim(anim_name: String) -> void:
	if _anim_player == null:
		_resolve_nodes()
	if _anim_player == null:
		return
	# Ignore authoring actions
	if anim_name == "Rig" or anim_name == "Rig_001":
		return
	if _current_anim == anim_name and _anim_player.is_playing():
		return
	if _anim_player.has_animation(anim_name):
		_current_anim = anim_name
		_anim_player.play(anim_name)

func get_current_anim() -> String:
	return _current_anim
