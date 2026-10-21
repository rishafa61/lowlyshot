# M9 bayonet knife model test suite
extends SceneTree

var fails := 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	_run()

func _run() -> void:
	var scn = load("res://scenes/weapons/melee/Knife.tscn") as PackedScene
	check(scn != null, "Knife.tscn loads")
	var knife = scn.instantiate() as Node3D
	root.add_child(knife)
	await process_frame

	check(knife.find_child("Blade", true, false) != null, "Blade mesh exists")
	check(knife.find_child("BladeTip", true, false) != null, "Clip-point BladeTip mesh exists")
	check(knife.find_child("BladeHole", true, false) != null, "BladeHole exists")
	check(knife.find_child("Guard", true, false) != null, "Guard exists")
	check(knife.find_child("MuzzleRing", true, false) != null, "MuzzleRing exists")
	check(knife.find_child("Handle", true, false) != null, "Handle exists")
	check(knife.find_child("Pommel", true, false) != null, "Pommel exists")
	var saw_count := 0
	for i in range(1, 7):
		if knife.find_child("SawTooth%d" % i, true, false) != null:
			saw_count += 1
	check(saw_count == 6, "6 sawback teeth exist (got %d)" % saw_count)
	var rib_count := 0
	for i in range(1, 7):
		if knife.find_child("HandleRib%d" % i, true, false) != null:
			rib_count += 1
	check(rib_count == 6, "6 handle ribs exist (got %d)" % rib_count)

	# Orientation sanity: tip forward of guard along -Z in LOCAL space
	var tip = knife.find_child("BladeTip", true, false) as Node3D
	var guard = knife.find_child("Guard", true, false) as Node3D
	var handle = knife.find_child("Handle", true, false) as Node3D
	check(tip.position.z < guard.position.z, "Tip is in front of guard (-Z forward)")
	check(handle.position.z > guard.position.z, "Handle is behind guard")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
