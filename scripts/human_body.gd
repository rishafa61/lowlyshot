@tool
class_name HumanBody
extends Node3D

## Humanoid rig with editor-friendly workflow:
## - EDITOR: human_body.tscn holds individual part meshes (torso, limbs...).
##   Edit them freely; the `tint_color` export live-previews the clothes color.
## - RUNTIME: parts are merged ONCE into a single shared ArrayMesh
##   (3 surfaces: 0=clothes/tintable, 1=skin, 2=gear) so every character
##   costs 3 draw calls instead of ~24 nodes — fixes stutter with many bots.
## Tag parts with metadata/surface = 0 (clothes), 1 (skin) or 2 (gear).

const DEFAULT_CLOTHES := Color(0.36, 0.40, 0.33)
const SKIN := Color(0.78, 0.62, 0.48)
const GEAR := Color(0.14, 0.14, 0.16)

static var _shared_mesh: ArrayMesh

@export var tint_color := DEFAULT_CLOTHES:
	set(c):
		tint_color = c
		_apply_editor_tint()

var _tint_mat: StandardMaterial3D
var _mesh_inst: MeshInstance3D
var _flash_tween: Tween

func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_editor_tint()
		return
	# Runtime: swap editable parts for the merged performance mesh.
	if _shared_mesh == null:
		_shared_mesh = _build_mesh_from_parts()
	var old_parts := _find_parts(self)
	for mi in old_parts:
		mi.queue_free()
	_tint_mat = StandardMaterial3D.new()
	_tint_mat.albedo_color = tint_color
	_tint_mat.roughness = 0.85
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "MergedMesh"
	_mesh_inst.mesh = _shared_mesh
	_mesh_inst.set_surface_override_material(0, _tint_mat)
	add_child(_mesh_inst)

func _apply_editor_tint() -> void:
	if not Engine.is_editor_hint():
		return
	if _tint_mat == null:
		_tint_mat = StandardMaterial3D.new()
		_tint_mat.roughness = 0.85
	_tint_mat.albedo_color = tint_color
	for mi in _find_parts(self):
		if int(mi.get_meta("surface", 0)) == 0:
			mi.set_surface_override_material(0, _tint_mat)

func set_tint(c: Color) -> void:
	tint_color = c
	if _tint_mat:
		_tint_mat.albedo_color = c

func get_tint() -> Color:
	return tint_color

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

func _find_parts(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.get_children():
		if n is MeshInstance3D:
			out.append(n)
		if n.get_child_count() > 0:
			out.append_array(_find_parts(n))
	return out

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

func _build_mesh_from_parts() -> ArrayMesh:
	var inv := global_transform.affine_inverse()
	var groups: Array = [[], [], []]
	for mi in _find_parts(self):
		var pm := mi.mesh as PrimitiveMesh
		if pm == null:
			continue
		var xf := inv * mi.global_transform
		var arrays: Array = pm.get_mesh_arrays()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in v.size():
			v[i] = xf * v[i]
			n[i] = xf.basis * n[i]
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		_merge_surface(groups[clampi(int(mi.get_meta("surface", 0)), 0, 2)], arrays)
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, groups[0])
	out.surface_set_material(0, _make_mat(DEFAULT_CLOTHES, 0.85))
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, groups[1])
	out.surface_set_material(1, _make_mat(SKIN, 0.8))
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, groups[2])
	out.surface_set_material(2, _make_mat(GEAR, 0.65))
	return out
