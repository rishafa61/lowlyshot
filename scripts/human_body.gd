class_name HumanBody
extends Node3D

## Low-poly humanoid built from primitives (feet at y=0, ~1.9m tall).
## Clothes parts are tinted per-instance (team / operator color);
## skin and gear keep fixed materials.

const DEFAULT_CLOTHES := Color(0.36, 0.40, 0.33)

var _tint_mats: Array[StandardMaterial3D] = []
var _flash_tween: Tween

func _ready() -> void:
	_init_tint_parts(self)

func _init_tint_parts(root: Node) -> void:
	for n in root.get_children():
		if n is MeshInstance3D and n.get_meta("tint", false):
			var m := StandardMaterial3D.new()
			m.albedo_color = DEFAULT_CLOTHES
			m.roughness = 0.85
			n.set_surface_override_material(0, m)
			_tint_mats.append(m)
		if n.get_child_count() > 0:
			_init_tint_parts(n)

func set_tint(c: Color) -> void:
	for m in _tint_mats:
		m.albedo_color = c

func get_tint() -> Color:
	return _tint_mats[0].albedo_color if _tint_mats.size() > 0 else DEFAULT_CLOTHES

func set_overlay(mat: Material) -> void:
	_apply_overlay(self, mat)

func _apply_overlay(root: Node, mat: Material) -> void:
	for n in root.get_children():
		if n is MeshInstance3D:
			n.material_overlay = mat
		if n.get_child_count() > 0:
			_apply_overlay(n, mat)

func clear_overlay() -> void:
	set_overlay(null)

## Flash whole body red then fade back to `normal` color (hit feedback).
func flash_hit(normal: Color) -> void:
	if _flash_tween:
		_flash_tween.kill()
	set_tint(Color(1, 0, 0))
	_flash_tween = create_tween()
	_flash_tween.tween_method(set_tint, Color(1, 0, 0), normal, 0.2)
