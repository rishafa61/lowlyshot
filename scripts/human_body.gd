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
const HUMAN_AABB := AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000)) # raw skel-space culling box (see _resolve_nodes)

# Scaling: New Mixamo export has feet grounded on the armature origin.
# Scale 0.2375 places feet at Y=0 with zero offset; head lands at ~1.79m,
# matching the 2.0m CapsuleShape3D collision exactly.
const MODEL_SCALE := Vector3(0.2375, 0.2375, 0.2375)
const MODEL_OFFSET := Vector3(0.0, 0.0, 0.0)

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
	# New Mixamo set: Idle_Rifle / Rifle_Run / Standby / Death
	if not Engine.is_editor_hint():
		play_anim("Idle_Rifle")

func _resolve_nodes() -> void:
	if _mesh_inst == null or not is_instance_valid(_mesh_inst):
		_mesh_inst = find_child("Player", true, false) as MeshInstance3D
		if _mesh_inst != null:
			# Skinned mesh needs an unscaled raw-space AABB to avoid frustum culling.
			# Player.glb armature is scaled 0.01 internally (units ~100x), pose spans
			# ~±800 raw units; a big box just disables culling for this single mesh.
			_mesh_inst.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	if _anim_player == null or not is_instance_valid(_anim_player):
		_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _anim_player != null:
			# Configure looping for continuous motions (Mixamo set: Idle_Rifle, Rifle_Run, Standby)
			for a in ["Idle_Rifle", "Rifle_Run", "Standby", "Idle", "Run"]:
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
## Uses Idle_Rifle for stationary aim/stand, Rifle_Run for movement,
## Standby for lobby idle, Death for knockdowns.
## mixamo_com_002 / authoring clips are ignored.
func sync_movement(is_moving: bool, _is_crouching: bool = false, is_sliding: bool = false, is_airborne: bool = false) -> void:
	if _current_anim == "Death":
		return # death owns the body until clear_death()/play_anim on respawn
	if is_moving or is_airborne or is_sliding:
		play_anim("Rifle_Run")
	else:
		play_anim("Idle_Rifle")

## Un-stick the Death pose (call on respawn so movement anims can play again).
func clear_death() -> void:
	if _current_anim == "Death":
		_current_anim = ""
		play_anim("Idle_Rifle")

func play_anim(anim_name: String) -> void:
	if _anim_player == null:
		_resolve_nodes()
	if _anim_player == null:
		return
	# Ignore authoring / unassigned actions
	if anim_name in ["Rig", "Rig_001", "mixamo.com.002", "mixamo_com_002"]:
		return
	if _current_anim == anim_name and _anim_player.is_playing():
		return
	if _anim_player.has_animation(anim_name):
		_current_anim = anim_name
		_anim_player.play(anim_name)

func get_current_anim() -> String:
	return _current_anim

## World transform of a bone (e.g. "mixamorig_RightHand") for prop attachment.
func get_bone_world_transform(bone_name: String) -> Transform3D:
	var skel := find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return Transform3D.IDENTITY
	var idx := skel.find_bone(bone_name)
	if idx < 0:
		return Transform3D.IDENTITY
	var pose: Transform3D = skel.global_transform * skel.get_bone_global_pose(idx)
	# Bone global pose includes the skeleton's scale (0.01 raw); normalize basis
	# so attached props don't inherit distorted scale.
	return Transform3D(pose.basis.orthonormalized(), pose.origin)

## World position of a bone (e.g. "mixamorig_RightHand") for prop attachment.
func get_bone_world_pos(bone_name: String) -> Vector3:
	return get_bone_world_transform(bone_name).origin
