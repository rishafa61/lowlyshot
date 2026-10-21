extends Node3D
## Ground War level root.
## Adds invisible perimeter walls (generated at runtime) so the out-of-bounds
## warning in BoundaryZone never triggers for ground units. Static colliders
## are created identically on every peer - no networking required.

func _ready() -> void:
	_build_far_walls()

func _build_far_walls() -> void:
	var walls := Node3D.new()
	walls.name = "FarWalls"
	add_child(walls)
	var specs := [
		[Vector3(0, 20, -400.5), Vector3(803, 40, 1)],
		[Vector3(0, 20, 400.5), Vector3(803, 40, 1)],
		[Vector3(-400.5, 20, 0), Vector3(1, 40, 803)],
		[Vector3(400.5, 20, 0), Vector3(1, 40, 803)],
	]
	for s in specs:
		var body := StaticBody3D.new()
		body.name = "FarWall"
		body.transform = Transform3D(Basis.IDENTITY, s[0])
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = s[1]
		col.shape = box
		body.add_child(col)
		walls.add_child(body)
