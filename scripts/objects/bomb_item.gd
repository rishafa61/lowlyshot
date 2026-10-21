class_name BombItem
extends Node3D

## World bomb object. Spawns in dropped or planted form. Purely visual +
## proximity beacon — all logic and authority is in SearchAndDestroyManager.

@onready var blink_light: OmniLight3D = $BlinkLight
@onready var body_mesh: MeshInstance3D = $Body

var blink_speed: float = 2.0
var _t: float = 0.0

func setup(is_planted: bool, site_id: String = "") -> void:
	blink_speed = 4.0 if is_planted else 1.5

func _process(delta: float) -> void:
	_t += delta * blink_speed
	var s := (sin(_t * PI) + 1.0) * 0.5
	if blink_light:
		blink_light.light_energy = 0.3 + s * 1.7
	if body_mesh:
		var mat := body_mesh.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			mat.emission_energy_multiplier = 0.2 + s * 2.0
