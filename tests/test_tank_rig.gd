extends SceneTree

# Tank.glb rig fixes: barrel axis sign (shell fired BACKWARD under the yaw-180
# wrapper), cannon pitch inversion, tread ribbons re-seated onto the track belts.

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
	var sc = load("res://scenes/vehicles/m1_abrams.tscn") as PackedScene
	var tank = sc.instantiate()
	root.add_child(tank)
	tank.global_position = Vector3(0, 1, 0)
	for i in 3:
		await physics_frame

	var barrel: Node3D = tank.barrel_node
	var muzzle: Node3D = tank.muzzle_node
	check(tank.turret_node != null and barrel != null and muzzle != null, "glb rig nodes resolve (Pivot/BarrelPivot/Muzzle)")

	# 1) Barrel axis forward at rest (the old -basis.z math pointed BACKWARD)
	var axis: Vector3 = (muzzle.global_position - barrel.global_position).normalized()
	check(axis.z < -0.9, "barrel axis points forward -Z at rest (got %s)" % axis)
	var neg_basis: Vector3 = -barrel.global_transform.basis.z.normalized()
	check(neg_basis.z > 0.9, "REGRESSION GUARD: -basis.z is backward under the 180 wrapper — must never be used as fire dir")

	# 2) Pitch: +pitch must lift the muzzle (old code dove the cannon)
	tank._target_cannon_pitch = 0.2
	for i in 30:
		tank._process(1.0 / 60.0)
	var axis_up: Vector3 = (muzzle.global_position - barrel.global_position).normalized()
	check(axis_up.y > 0.1, "+pitch aims the cannon UP (axis y %.2f)" % axis_up.y)

	# 3) Live fire: spawned shell must fly forward (was going behind the tank)
	tank.reload_timer = 0.0
	tank.chase_cam.current = true
	tank._try_fire_cannon(0)
	var shell: Node = null
	for n in root.get_children():
		if n.get("direction") != null and n.get("source_tank") == tank:
			shell = n
			break
	check(shell != null, "cannon shell spawned")
	if shell != null:
		var d: Vector3 = shell.get("direction")
		check(d.z < -0.5, "shell flies FORWARD (dir %s)" % d)
		check(spawn_matches(d, axis_up), "shell direction follows the barrel axis (dot %.2f)" % d.normalized().dot(axis_up))

	# 4) Tread ribbons sit on the animated track belts (were stacked over the hull)
	var lt := tank.get_node("Model/Tank/L_Tread") as MeshInstance3D
	var rt := tank.get_node("Model/Tank/R_Tread") as MeshInstance3D
	var ltk := tank.get_node("Model/Tank/L_Track") as MeshInstance3D
	var rtk := tank.get_node("Model/Tank/R_Track") as MeshInstance3D
	for pair in [[lt, ltk, "L"], [rt, rtk, "R"]]:
		var t: MeshInstance3D = pair[0]
		var b: MeshInstance3D = pair[1]
		if t == null or b == null:
			check(false, "%s tread/track nodes exist" % pair[2])
			continue
		var ta := t.global_transform * t.get_aabb()
		var ba := b.global_transform * b.get_aabb()
		var on_side := (ta.position.x < -0.4 and ta.size.x + ta.position.x < -0.4) if pair[2] == "L" \
			else (ta.position.x > 0.4 and ta.size.x + ta.position.x > 0.4)
		check(on_side, "%s tread ribbon on its own side (x %.2f..%.2f)" % [pair[2], ta.position.x, ta.position.x + ta.size.x])
		var y_lo := maxf(ta.position.y, ba.position.y)
		var y_hi := minf(ta.position.y + ta.size.y, ba.position.y + ba.size.y)
		check(y_hi > y_lo, "%s tread ribbon overlaps the belt vertically" % pair[2])

	print("RESULT: %s (%d checks, %d fails)" % ["OK" if fails == 0 else "FAILED", checks, fails])
	quit(1 if fails > 0 else 0)

func spawn_matches(d: Vector3, axis: Vector3) -> bool:
	return d.normalized().dot(axis) > 0.9
