extends SceneTree

# Aircraft.glb swap: mesh instanced + wrapper transform + anim state wiring.

var fails: int = 0
var checks: int = 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FAIL: %s" % msg)
	else:
		print("  PASS: %s" % msg)

func _initialize() -> void:
	await process_frame
	var sc = load("res://scenes/vehicles/aircraft.tscn") as PackedScene
	check(sc != null, "aircraft.tscn loads (tscn valid)")
	# Floor so _is_grounded() ray hits: grounded-state clips need a surface
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 10, 200)
	floor_shape.shape = box
	floor_shape.position.y = -5.0
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	var jet = sc.instantiate()
	root.add_child(jet)
	for i in 3:
		await physics_frame

	# Old box meshes gone (old names; the new glb coincidentally has its own
	# "Fuselage" mesh, so probe uniquely-named old parts instead)
	check(jet.get_node("Model").find_children("WingMain*", "MeshInstance3D", true, false).is_empty(),
		"old procedural WingMain box meshes removed")
	var glb_meshes: Array = jet.get_node("Model").find_children("*", "MeshInstance3D", true, false)
	check(glb_meshes.size() > 0, "new Aircraft.glb mesh instanced under Model")

	# Muzzle contract kept for the gatling
	check(jet.get_node_or_null("Model/GAU8_Cannon") != null, "Model/GAU8_Cannon muzzle kept")

	# Wingspan axis exists in mesh space (JSON: ~26.4 units before armature scale)
	var mi := glb_meshes[0] as MeshInstance3D
	check(mi.get_aabb().size.x > 20.0, "airframe mesh spans wing-scale (x %.1f)" % mi.get_aabb().size.x)
	# USER-TUNED wrapper (editor, 2026-11-08): pos (0, 0.87, 0), rotY 180, scale
	# 0.8 — verified visually and at runtime (nose -Z, level, wheels down).
	# Pin the exact matrix so neither editor tweaks nor code clobbers it.
	var wrap := (jet.get_node("Model/AircraftMesh") as Node3D).transform
	check(absf(wrap.basis.x.x + 0.8) < 0.01 and absf(wrap.basis.y.y - 0.8) < 0.01 and absf(wrap.basis.z.z + 0.8) < 0.01,
		"AircraftMesh wrapper keeps user scale 0.8 (got %s)" % wrap.basis.get_scale())
	check(wrap.basis.x.x < -0.7 and wrap.basis.z.z < -0.7,
		"AircraftMesh wrapper keeps user rotY 180 (x.x %.2f, z.z %.2f)" % [wrap.basis.x.x, wrap.basis.z.z])
	check(absf(wrap.origin.y - 0.87) < 0.01, "AircraftMesh wrapper keeps user pos y 0.87")

	# Orientation via skinned-mesh ground truth: wheel BONE world positions.
	# (MeshInstance node transforms don't reflect skinned rendering.)
	var skel := jet.get_node("Model/AircraftMesh/Armature/Skeleton3D") as Skeleton3D
	var wheel_world := {}
	for i in skel.get_bone_count():
		var bp: Transform3D = skel.global_transform * skel.get_bone_global_pose(i)
		wheel_world[skel.get_bone_name(i)] = bp.origin
	var fz: float = wheel_world["f.wheel"].z
	var lz: float = wheel_world["l.wheel"].z
	var rz: float = wheel_world["r.wheel"].z
	check(fz < minf(lz, rz) - 3.0, "front gear forward of mains -> nose is -Z (fz %.1f vs %.1f)" % [fz, minf(lz, rz)])
	check(absf(wheel_world["l.wheel"].x + wheel_world["r.wheel"].x) < 0.1,
		"main gear symmetric about X (level roll)")
	check(wheel_world["l.wheel"].y < skel.global_transform.origin.y,
		"wheels hang below the body (level pitch, not nose/tail-standing)")

	# Animation wiring
	var anim: AnimationPlayer = jet.get("_anim")
	check(anim != null, "AnimationPlayer wired")
	if anim != null:
		for clip in ["Idle", "Fly", "Take Off", "Landing"]:
			check(anim.has_animation(clip), "clip '%s' available" % clip)
		check(anim.current_animation == "Idle", "starts in Idle on ground")
		check(anim.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR, "Idle loops")
		check(anim.get_animation("Fly").loop_mode == Animation.LOOP_LINEAR, "Fly loops")
		check(anim.get_animation("Take Off").loop_mode == Animation.LOOP_NONE, "Take Off is a one-shot")
		check(anim.get_animation("Landing").loop_mode == Animation.LOOP_NONE, "Landing is a one-shot")

	# --- One-shot state machine spec ---
	# Grounded: Idle. Rising past 100m AGL: Take Off ONCE -> Fly. Falling past
	# 50m AGL (airborne): Landing ONCE -> Idle, and Idle holds (no re-trigger)
	# until the next Take Off. Holding any altitude never loops the one-shots.

	# Ground roll does NOT trigger Take Off (it only fires past 100m)
	jet.linear_velocity = Vector3(0, 0, 30.0)
	jet._update_anim(0.016)
	check(anim.current_animation == "Idle", "ground roll stays Idle (no Take Off on the ground)")

	# Climb past 100m: Take Off fires once (fresh AGL ray from real position)
	jet.global_position = Vector3(0, 120, 0)
	jet._update_anim(0.016)
	check(anim.current_animation == "Take Off", "reaching 100m+ fires Take Off")
	check(jet.get("_oneshot") == "Take Off", "Take Off latched as the running one-shot")
	jet._update_anim(0.016) # holding 120m: no re-fire, clip still owns the player
	check(anim.current_animation == "Take Off", "holding altitude does not re-fire Take Off")

	# Take Off ends -> Fly
	jet._on_anim_finished("Take Off")
	check(jet.get("_oneshot") == "", "one-shot cleared when Take Off ends")
	check(anim.current_animation == "Fly", "after Take Off ends -> Fly")

	# Cruise at 60m (between thresholds): stays Fly, nothing re-triggers
	jet.global_position = Vector3(0, 60, 0)
	jet._update_anim(0.016)
	check(anim.current_animation == "Fly", "cruising at 60m stays Fly")

	# Descend past 50m: Landing fires once
	jet.global_position = Vector3(0, 35, 0)
	jet._update_anim(0.016)
	check(anim.current_animation == "Landing", "descending below 50m fires Landing")
	jet._update_anim(0.016) # holding 35m: no re-fire
	check(anim.current_animation == "Landing", "holding low altitude does not loop Landing")

	# Landing ends -> Idle, and Idle holds even though still airborne at 35m
	jet._on_anim_finished("Landing")
	check(anim.current_animation == "Idle", "after Landing ends -> Idle")
	for i in 3:
		jet._update_anim(0.016)
	check(anim.current_animation == "Idle", "staying below 50m keeps Idle (no landing loop)")

	# Climb past 100m again: Take Off fires once more -> Fly
	jet.global_position = Vector3(0, 120, 0)
	jet._update_anim(0.016)
	check(anim.current_animation == "Take Off", "climbing past 100m again fires Take Off again")
	jet._on_anim_finished("Take Off")
	check(anim.current_animation == "Fly", "second Take Off also ends -> Fly")

	# Touchdown: grounded -> Idle
	jet.global_position = Vector3(0, 1.4755468, 3.346283)
	jet._update_anim(0.016)
	check(anim.current_animation == "Idle", "touchdown -> Idle")

	# Controller state untouched by the swap
	check(not jet.get("is_destroyed"), "controller intact")
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
