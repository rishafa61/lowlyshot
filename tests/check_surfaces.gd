extends SceneTree

func _initialize() -> void:
	await process_frame
	var glb = (load("res://assets/models/vehicles/Tank.glb") as PackedScene).instantiate()
	root.add_child(glb)
	await process_frame
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var names := PackedStringArray()
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			names.append(mat.resource_name if mat else "?")
		print(m.name, " surfaces:", m.mesh.get_surface_count(), " mats:", names)
	quit(0)
