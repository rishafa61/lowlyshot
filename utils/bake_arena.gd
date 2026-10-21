extends SceneTree
## One-off: bake arena_template.tscn navmesh and write it back into the scene
## file. Run: godot --headless -s utils/bake_arena.gd

func _initialize() -> void:
	var path := "res://scenes/levels/arena_template.tscn"
	var scene := load(path) as PackedScene
	if scene == null:
		printerr("template missing")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	# let colliders register with the physics server
	await process_frame
	await process_frame
	await process_frame

	var nr := inst.find_child("NavigationRegion3D", true, false) as NavigationRegion3D
	if nr == null:
		printerr("no NavigationRegion3D")
		quit(1)
		return

	# fresh mesh so re-runs don't append
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_height = 1.8
	nm.agent_radius = 0.35
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 60.0
	nr.navigation_mesh = nm

	nr.bake_navigation_mesh(false)
	print("baked: %d verts, %d polys" % [nm.get_vertices().size(), nm.get_polygon_count()])

	var verts := nm.get_vertices()
	var vparts: Array[String] = []
	for v in verts:
		vparts.append("%.6f" % v.x)
		vparts.append("%.6f" % v.y)
		vparts.append("%.6f" % v.z)
	var poly_parts: Array[String] = []
	for i in nm.get_polygon_count():
		var p := nm.get_polygon(i)
		var idx: Array[String] = []
		for vi in p:
			idx.append(str(vi))
		poly_parts.append("PackedInt32Array(" + ", ".join(idx) + ")")

	var txt := FileAccess.get_file_as_string(path)
	txt = txt.replace("vertices = PackedVector3Array()",
		"vertices = PackedVector3Array(" + ", ".join(vparts) + ")")
	txt = txt.replace("polygons = []", "polygons = [" + ", ".join(poly_parts) + "]")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	print("written back to ", path)
	inst.queue_free()
	quit(0)
