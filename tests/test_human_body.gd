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

	var mesh_inst: MeshInstance3D = body._mesh_inst
	check(mesh_inst != null, "mesh instance created at runtime")
	if mesh_inst:
		check(mesh_inst.mesh.get_surface_count() >= 3, "surfaces present (got %d)" % mesh_inst.mesh.get_surface_count())
		check(mesh_inst.mesh.get_faces().size() > 0, "has triangles")
	var rig: Node3D = body.find_child("metarig", true, false)
	check(rig == null or rig.transform == Transform3D.IDENTITY, "rig transform normalized (no stale Blender armature offset)")

	body.set_tint(Color(1, 0, 0))
	await process_frame
	if mesh_inst:
		var mat: StandardMaterial3D = mesh_inst.get_surface_override_material(1)
		check(mat != null and mat.albedo_color == Color(1, 0, 0), "set_tint applies to surface 1")
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
