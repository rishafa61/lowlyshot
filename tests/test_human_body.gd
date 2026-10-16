# HumanBody merge test — headless: instantiates scene, verifies runtime merge
# into 3-surface ArrayMesh, tint, overlay, and hit flash behavior.
extends SceneTree

var fails: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	_run()

func _run() -> void:
	var scene: PackedScene = load("res://scenes/characters/human_body.tscn")
	check(scene != null, "scene loads")
	var body = scene.instantiate()
	root.add_child(body)
	for i in 3:
		await process_frame

	var mesh_inst: MeshInstance3D = body.get_node_or_null("MergedMesh")
	check(mesh_inst != null, "merged mesh created at runtime")
	if mesh_inst:
		check(mesh_inst.mesh.get_surface_count() == 3, "3 surfaces")
		check(mesh_inst.mesh.get_faces().size() > 0, "has triangles")
		var aabb := mesh_inst.mesh.get_aabb()
		check(aabb.position.y > -0.1 and aabb.end.y < 2.2, "AABB sane: %s" % aabb)
	var leftovers: Array = body._find_parts(body).filter(func(m): return m.name != "MergedMesh")
	check(leftovers.is_empty(), "editable parts freed after merge")

	body.set_tint(Color(1, 0, 0))
	await process_frame
	if mesh_inst:
		var mat: StandardMaterial3D = mesh_inst.get_surface_override_material(0)
		check(mat != null and mat.albedo_color == Color(1, 0, 0), "set_tint applies")
	check(body.get_tint() == Color(1, 0, 0), "get_tint reads back")

	if mesh_inst:
		body.set_overlay(StandardMaterial3D.new())
		check(mesh_inst.material_overlay != null, "set_overlay")
		body.clear_overlay()
		check(mesh_inst.material_overlay == null, "clear_overlay")
	body.flash_hit(Color(0.3, 0.6, 1.0))
	check(body._flash_tween != null and body._flash_tween.is_running(), "flash tween running")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
