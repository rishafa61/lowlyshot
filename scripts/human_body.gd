class_name HumanBody
extends Node3D

## Low-poly humanoid merged into ONE shared ArrayMesh (3 surfaces:
## 0=clothes/tintable, 1=skin, 2=gear). Each character costs 3 draw calls
## instead of ~24 MeshInstance3D nodes — big win with many bots + shadows.
## Feet at y=0, ~1.88m tall.

const DEFAULT_CLOTHES := Color(0.36, 0.40, 0.33)

static var _shared_mesh: ArrayMesh

var _tint_mat: StandardMaterial3D
var _mesh_inst: MeshInstance3D
var _flash_tween: Tween
var _pending_tint := DEFAULT_CLOTHES
var _has_tint := false

func _ready() -> void:
	if _shared_mesh == null:
		_shared_mesh = _build_mesh()
	_tint_mat = StandardMaterial3D.new()
	_tint_mat.albedo_color = _pending_tint
	_tint_mat.roughness = 0.85
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "Mesh"
	_mesh_inst.mesh = _shared_mesh
	_mesh_inst.set_surface_override_material(0, _tint_mat)
	add_child(_mesh_inst)

func set_tint(c: Color) -> void:
	_pending_tint = c
	_has_tint = true
	if _tint_mat:
		_tint_mat.albedo_color = c

func get_tint() -> Color:
	return _tint_mat.albedo_color if _tint_mat else _pending_tint

func set_overlay(mat: Material) -> void:
	if _mesh_inst:
		_mesh_inst.material_overlay = mat

func clear_overlay() -> void:
	set_overlay(null)

## Flash whole body red then fade back to `normal` color (hit feedback).
func flash_hit(normal: Color) -> void:
	if _flash_tween:
		_flash_tween.kill()
	set_tint(Color(1, 0, 0))
	_flash_tween = create_tween()
	_flash_tween.tween_method(set_tint, Color(1, 0, 0), normal, 0.2)

static func _make_mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

static func _merge_surface(dst: Array, src: Array) -> void:
	if dst.is_empty():
		for e in src:
			dst.append(e)
		return
	var off: int = dst[Mesh.ARRAY_VERTEX].size()
	# Packed arrays pass by value — mutate local copies, reassign back.
	for key in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV]:
		if dst[key] != null and src[key] != null:
			var d = dst[key]
			d.append_array(src[key])
			dst[key] = d
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	for i in idx.size():
		idx[i] += off
	var di: PackedInt32Array = dst[Mesh.ARRAY_INDEX]
	di.append_array(idx)
	dst[Mesh.ARRAY_INDEX] = di

static func _build_mesh() -> ArrayMesh:
	var chest := BoxMesh.new(); chest.size = Vector3(0.42, 0.46, 0.26)
	var vest := BoxMesh.new(); vest.size = Vector3(0.44, 0.42, 0.30)
	var pelvis := BoxMesh.new(); pelvis.size = Vector3(0.36, 0.22, 0.24)
	var neck := CylinderMesh.new(); neck.top_radius = 0.05; neck.bottom_radius = 0.06; neck.height = 0.10
	var head := BoxMesh.new(); head.size = Vector3(0.20, 0.24, 0.22)
	var face := BoxMesh.new(); face.size = Vector3(0.16, 0.12, 0.08)
	var joint_m := SphereMesh.new(); joint_m.radius = 0.08; joint_m.height = 0.16
	var joint_s := SphereMesh.new(); joint_s.radius = 0.06; joint_s.height = 0.12
	var uarm := CapsuleMesh.new(); uarm.radius = 0.055; uarm.height = 0.32
	var farm := CapsuleMesh.new(); farm.radius = 0.05; farm.height = 0.28
	var hand := BoxMesh.new(); hand.size = Vector3(0.08, 0.11, 0.05)
	var thigh := CapsuleMesh.new(); thigh.radius = 0.08; thigh.height = 0.44
	var shin := CapsuleMesh.new(); shin.radius = 0.07; shin.height = 0.42
	var boot := BoxMesh.new(); boot.size = Vector3(0.11, 0.10, 0.25)

	# [surface, mesh, position] — 0 clothes, 1 skin, 2 gear
	var groups: Array = [[], [], []]
	for d in [
		[0, chest, Vector3(0, 1.35, 0)],
		[0, pelvis, Vector3(0, 0.96, 0)],
		[0, uarm, Vector3(-0.29, 1.34, 0)], [0, uarm, Vector3(0.29, 1.34, 0)],
		[0, thigh, Vector3(-0.12, 0.68, 0)], [0, thigh, Vector3(0.12, 0.68, 0)],
		[0, shin, Vector3(-0.12, 0.26, 0)], [0, shin, Vector3(0.12, 0.26, 0)],
		[1, neck, Vector3(0, 1.62, 0)],
		[1, head, Vector3(0, 1.76, 0)],
		[1, farm, Vector3(-0.30, 1.00, -0.02)], [1, farm, Vector3(0.30, 1.00, -0.02)],
		[2, vest, Vector3(0, 1.37, 0)],
		[2, joint_m, Vector3(0, 1.10, 0)],
		[2, face, Vector3(0, 1.74, -0.10)],
		[2, joint_s, Vector3(-0.27, 1.50, 0)], [2, joint_s, Vector3(0.27, 1.50, 0)],
		[2, joint_s, Vector3(-0.30, 1.16, 0)], [2, joint_s, Vector3(0.30, 1.16, 0)],
		[2, hand, Vector3(-0.30, 0.84, -0.04)], [2, hand, Vector3(0.30, 0.84, -0.04)],
		[2, joint_s, Vector3(-0.12, 0.88, 0)], [2, joint_s, Vector3(0.12, 0.88, 0)],
		[2, joint_s, Vector3(-0.12, 0.46, 0)], [2, joint_s, Vector3(0.12, 0.46, 0)],
		[2, boot, Vector3(-0.12, 0.05, -0.04)], [2, boot, Vector3(0.12, 0.05, -0.04)],
	]:
		var arrays: Array = d[1].get_mesh_arrays()
		var xf := Transform3D(Basis(), d[2])
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in v.size():
			v[i] = xf * v[i]
			n[i] = xf.basis * n[i]
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		_merge_surface(groups[d[0]], arrays)

	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, groups[0])
	out.surface_set_material(0, _make_mat(DEFAULT_CLOTHES, 0.85))
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, groups[1])
	out.surface_set_material(1, _make_mat(Color(0.78, 0.62, 0.48), 0.8))
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, groups[2])
	out.surface_set_material(2, _make_mat(Color(0.14, 0.14, 0.16), 0.65))
	return out
