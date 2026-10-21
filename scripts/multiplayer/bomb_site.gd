class_name BombSite
extends Area3D

## Search & Destroy bomb site target zone (Site A / Site B).

@export var site_id: String = "A" # "A" or "B"
@export var radius: float = 6.0

@onready var marker_label: Label3D = $MarkerLabel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("bombsite")
	if marker_label:
		marker_label.text = "SITE " + site_id
		marker_label.modulate = Color(1.0, 0.6, 0.2)
	_ensure_collision()

func _ensure_collision() -> void:
	if not collision_shape:
		var col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = 3.5
		col.shape = cyl
		col.position.y = 1.75
		add_child(col)
		collision_shape = col

func is_point_inside(pos: Vector3) -> bool:
	# Horizontal distance within radius, height within 4m
	var horiz_dist := Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
	var vert_dist := absf(pos.y - global_position.y)
	return horiz_dist <= radius and vert_dist <= 4.0
