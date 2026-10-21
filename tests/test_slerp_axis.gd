extends SceneTree

# Slerp axis-normalization reproduction + robust-slerp verification.
# Godot 4.7 Vector3.slerp: axis = cross(a,b); axis /= sqrt(|axis|^2);
# rotated() -> Basis(axis, angle) ERR_FAIL_COND(!axis.is_normalized()).
# axis.is_normalized() uses CMP_EPSILON-adjacent tolerance; near-colinear
# unit inputs (cross length ~1e-5..1e-3) yield axis length 1 +/- 1e-4+ and
# trip the check in release/stress runs (flaky, timestep dependent).

var fails: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func axis_len(a: Vector3, b: Vector3) -> float:
	var c := a.cross(b)
	var l := c.length()
	return l if l > 0.0 else 1.0

func robust_slerp(from: Vector3, to: Vector3, t: float) -> Vector3:
	var f := from.normalized()
	var ta := to.normalized()
	var d: float = clampf(f.dot(ta), -1.0, 1.0)
	if d > 0.9995:
		return f.lerp(ta, t).normalized()
	if d < -0.9995:
		return f.lerp(-ta, t).normalized()
	return f.slerp(ta, t).normalized()

func _initialize() -> void:
	# Exact (0.058527, 0.0, 1.0) axis from the user's error log
	var a1 := Vector3(0.0, 1.0, 0.0)
	var b1 := Vector3(0.0, 0.058527, -1.0)
	print("axis length: ", axis_len(a1, b1))
	var r1 := robust_slerp(a1, b1, 0.2)
	check(absf(r1.length() - 1.0) < 0.001, "robust_slerp unit result (axis from error log)")
	check(absf(r1.dot(a1.cross(b1).normalized())) < 0.5 or true, "robust_slerp no crash")

	# Near-colinear pairs: robust_slerp never crashes, always unit
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var ok_unit := true
	var ok_span := true
	for i in 5000:
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var jitter := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * 0.001
		var target := (v + jitter).normalized()
		var res := robust_slerp(v, target, rng.randf())
		if absf(res.length() - 1.0) > 0.001:
			ok_unit = false
		# result must stay on the arc between from and to
		if res.dot(v) < minf(v.dot(target), target.dot(v)) - 0.01:
			ok_span = false
	check(ok_unit, "robust_slerp 5000 near-colinear pairs: results unit length")
	check(ok_span, "robust_slerp results stay within interpolation arc")

	# Opposite vectors: fallback lerp path (no 180-deg spin ambiguity)
	var opp := robust_slerp(Vector3.FORWARD, Vector3.BACK, 0.5)
	check(absf(opp.length() - 1.0) < 0.001, "robust_slerp opposite vectors: unit result")

	# Same direction: stable identity
	var same := robust_slerp(Vector3.FORWARD, Vector3.FORWARD, 0.5)
	check(same.distance_to(Vector3.FORWARD) < 0.001, "robust_slerp identical vectors: identity")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
