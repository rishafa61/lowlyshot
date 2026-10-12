extends Marker3D
class_name SpawnPoint

@export var team: String = "all" # "all", "attackers", "defenders", "ally", "enemy"
@export var is_active: bool = true

func _ready() -> void:
	add_to_group("spawn_points")