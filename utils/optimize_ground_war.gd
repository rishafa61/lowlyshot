# Offline optimizer: ground_war.tscn
# 1. CSGShape3D -> MeshInstance3D (unit mesh, geometry scale baked into basis)
#    + StaticBody3D/CollisionShape3D with primitive shapes. Visual + collision
#    identical, CSG generation cost at scene-enter gone.
# 2. All tree MeshInstance3D (trunk_mesh/pine_mesh) merged into a few
#    MultiMeshInstance3D buckets. Visual identical.
# Run: godot --headless --script utils/optimize_ground_war.gd
extends SceneTree

var _unit_box: BoxMesh
var _unit_cyl: CylinderMesh
var _unit_sphere: SphereMesh
var _shape_cache := {}
var _converted := 0
var _merged := 0
var _scene_root: Node = null

func _initialize() -> void:
	_unit_box = BoxMesh.new()
	_unit_cyl = CylinderMesh.new()
	_unit_cyl.top_radius = 0.5
	_unit_cyl.bottom_radius = 0.5
	_unit_cyl.height = 1.0
	_unit_cyl.radial_segments = 16
	_unit_sphere = SphereMesh.new()
	_unit_sphere.radius = 0.5
	_unit_sphere.height = 1.0
	_unit_sphere.radial_segments = 16
	_unit_sphere.rings = 8
	_run()

func _run() -> void:
	var ps = load("res://scenes/levels/ground_war.tscn") as PackedScene
	_scene_root = ps.instantiate()
	root.add_child(_scene_root)
	await process_frame

	_convert_csgs(_scene_root)
	_merge_trees(_scene_root)

	# attach level root script (invisible far walls at runtime)
	var lvl_script = load("res://scripts/levels/ground_war.gd")
	if lvl_script != null and _scene_root.get_script() == null:
		_scene_root.set_script(lvl_script)

	root.remove_child(_scene_root)
	var packed := PackedScene.new()
	packed.pack(_scene_root)
	var err := ResourceSaver.save(packed, "res://scenes/levels/ground_war.tscn")
	print("SAVE err=%s converted_csg=%d merged_tree_instances=%d" % [error_string(err), _converted, _merged])
	_scene_root.queue_free()
	quit(0 if err == OK else 1)

func _convert_csgs(top: Node) -> void:
	var stack: Array = [top]
	var targets: Array = []
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if c is CSGShape3D and c.owner == top:
				targets.append(c)
	for csg in targets:
		_convert_one(csg)

func _convert_one(csg: CSGShape3D) -> void:
	var parent := csg.get_parent()
	var index := csg.get_index()
	var xf := csg.transform
	var b := xf.basis
	var sx := b.x.length()
	var sy := b.y.length()
	var sz := b.z.length()

	var geom_scale := Vector3.ONE
	var shape: Shape3D = null
	if csg is CSGBox3D:
		var box := csg as CSGBox3D
		geom_scale = box.size
		var key := "b_%d_%d_%d" % [roundi(box.size.x * sx * 100.0), roundi(box.size.y * sy * 100.0), roundi(box.size.z * sz * 100.0)]
		shape = _shape_cache.get(key)
		if shape == null:
			var bs := BoxShape3D.new()
			bs.size = box.size * Vector3(sx, sy, sz)
			shape = bs
			_shape_cache[key] = shape
	elif csg is CSGCylinder3D:
		var cy := csg as CSGCylinder3D
		geom_scale = Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0)
		var key := "c_%d_%d" % [roundi(cy.radius * sx * 100.0), roundi(cy.height * sy * 100.0)]
		shape = _shape_cache.get(key)
		if shape == null:
			var cs := CylinderShape3D.new()
			cs.radius = cy.radius * maxf(sx, sz)
			cs.height = cy.height * sy
			shape = cs
			_shape_cache[key] = shape
	elif csg is CSGSphere3D:
		var sp := csg as CSGSphere3D
		geom_scale = Vector3.ONE * (sp.radius * 2.0)
		if absf(sx - sy) < 0.01 and absf(sy - sz) < 0.01:
			var key := "s_%d" % roundi(sp.radius * sx * 100.0)
			shape = _shape_cache.get(key)
			if shape == null:
				var ss := SphereShape3D.new()
				ss.radius = sp.radius * sx
				shape = ss
				_shape_cache[key] = shape
		else:
			var mk := "ell_%d_%d" % [roundi(sp.radius * 100.0), roundi(sy * 100.0)]
			shape = _shape_cache.get(mk)
			if shape == null:
				var sm := SphereMesh.new()
				sm.radius = sp.radius
				sm.height = sp.radius * 2.0 * sy
				sm.radial_segments = 24
				sm.rings = 12
				shape = sm.create_trimesh_shape()
				_shape_cache[mk] = shape

	# detach original FIRST: frees the name + slot (avoids auto-rename of mi)
	parent.remove_child(csg)

	var mi := MeshInstance3D.new()
	mi.name = csg.name
	mi.transform = Transform3D(b * Basis.from_scale(geom_scale), xf.origin)
	mi.material_override = csg.material_override
	if csg is CSGSphere3D:
		mi.mesh = _unit_sphere
	elif csg is CSGCylinder3D:
		mi.mesh = _unit_cyl
	else:
		mi.mesh = _unit_box
	parent.add_child(mi)
	parent.move_child(mi, index)
	mi.owner = _scene_root

	if csg.use_collision and shape != null:
		var body := StaticBody3D.new()
		body.name = csg.name + "_Body"
		var rb := Basis(b.x.normalized(), b.y.normalized(), b.z.normalized())
		body.transform = Transform3D(rb, xf.origin)
		var col := CollisionShape3D.new()
		col.name = "Shape"
		col.shape = shape
		body.add_child(col)
		parent.add_child(body)
		parent.move_child(body, index + 1)
		body.owner = _scene_root
		col.owner = _scene_root

	csg.queue_free()
	_converted += 1

func _merge_trees(top: Node) -> void:
	var nav: Node = top.get_node_or_null("NavigationRegion3D")
	if nav == null:
		printerr("No NavigationRegion3D")
		return

	# collect MeshInstances owned by the scene (skip my unit meshes)
	var all_mi: Array = []
	var stack: Array = [top]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if c is MeshInstance3D and c.owner == top:
				var m: Mesh = (c as MeshInstance3D).mesh
				if m != null and m != _unit_box and m != _unit_cyl and m != _unit_sphere:
					all_mi.append(c)

	# discover shared trunk/pine meshes
	var trunk_mesh: Mesh = null
	var pine_mesh: Mesh = null
	for mi in all_mi:
		if mi.mesh is CylinderMesh:
			var cm := mi.mesh as CylinderMesh
			if cm.top_radius == 0.0:
				pine_mesh = mi.mesh
			elif cm.bottom_radius < 1.0 and cm.height < 5.0:
				trunk_mesh = mi.mesh
	if trunk_mesh == null or pine_mesh == null:
		printerr("trunk/pine mesh not found: %s / %s" % [trunk_mesh, pine_mesh])
		return

	# count buckets
	var counts := {}
	for mi in all_mi:
		var k := _bucket_key(mi, trunk_mesh, pine_mesh)
		if k == "":
			continue
		counts[k] = counts.get(k, 0) + 1
	if counts.is_empty():
		return

	# allocate + fill
	var mms := {}
	var fills := {}
	var samples := {}
	for k in counts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = counts[k]
		mms[k] = mm
		fills[k] = 0
	var nav_inv: Transform3D = nav.global_transform.affine_inverse()
	for mi in all_mi:
		var k := _bucket_key(mi, trunk_mesh, pine_mesh)
		if k == "":
			continue
		var mm: MultiMesh = mms[k]
		if mm.mesh == null:
			mm.mesh = mi.mesh
			samples[k] = mi
		mm.set_instance_transform(fills[k], nav_inv * mi.global_transform)
		fills[k] = int(fills[k]) + 1

	# build MultiMeshInstance3D nodes
	var i := 0
	for k in mms:
		var mm: MultiMesh = mms[k]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "TreesMM%d" % i
		mmi.multimesh = mm
		var sample: MeshInstance3D = samples[k]
		if sample != null:
			mmi.material_override = sample.get_surface_override_material(0)
		nav.add_child(mmi)
		mmi.owner = top
		i += 1
		_merged += int(counts[k])

	# remove originals
	for mi in all_mi:
		if _bucket_key(mi, trunk_mesh, pine_mesh) != "":
			mi.get_parent().remove_child(mi)
			mi.queue_free()

func _bucket_key(mi: MeshInstance3D, trunk_mesh: Mesh, pine_mesh: Mesh) -> String:
	var m := mi.mesh
	var kind := ""
	if m == trunk_mesh:
		kind = "t"
	elif m == pine_mesh:
		kind = "p"
	else:
		return ""
	var mat := mi.get_surface_override_material(0)
	var mat_id := 0 if mat == null else mat.get_instance_id()
	return "%s_%d" % [kind, mat_id]
