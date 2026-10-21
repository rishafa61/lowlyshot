extends SceneTree
func _initialize():
	var p = load("res://assets/models/Player.glb") as PackedScene
	var n = p.instantiate()
	var mi: MeshInstance3D = n.find_child("Player", true, false)
	var skel: Skeleton3D = mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var skin := mi.skin
	var bind_by_bone := {}
	for i in skin.get_bind_count():
		var b := skin.get_bind_bone(i)
		if b < 0:
			b = skel.find_bone(skin.get_bind_name(i))
		if b >= 0:
			bind_by_bone[b] = skin.get_bind_pose(i)
	var xfs := {}
	for b in skel.get_bone_count():
		var bind: Transform3D = bind_by_bone.get(b, Transform3D.IDENTITY)
		xfs[b] = skel.get_bone_global_rest(b) * bind  # no inverse
	var mn: Vector3 = Vector3(1e9, 1e9, 1e9)
	var mx: Vector3 = Vector3(-1e9, -1e9, -1e9)
	var mesh := mi.mesh
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vi in verts.size():
			var pos := Vector3.ZERO
			var wsum := 0.0
			for k in 4:
				var w := weights[vi * 4 + k]
				if w <= 0.0: continue
				wsum += w
				var t: Transform3D = xfs.get(bones[vi * 4 + k], Transform3D.IDENTITY)
				pos += (t * verts[vi]) * w
			pos /= wsum
			mn = mn.min(pos)
			mx = mx.max(pos)
	print("BAKED_MIN: ", mn)
	print("BAKED_MAX: ", mx)
	print("BAKED_SIZE: ", mx - mn)
	n.queue_free()
	quit(0)
