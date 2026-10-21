# Glock 17 model test suite
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
	var scn = load("res://scenes/weapons/secondary/Glock.tscn") as PackedScene
	check(scn != null, "Glock.tscn loads")
	var gun = scn.instantiate() as Node3D
	root.add_child(gun)
	await process_frame

	check(gun.find_child("Slide", true, false) != null, "Slide mesh exists")
	check(gun.find_child("Frame", true, false) != null, "Frame mesh exists")
	check(gun.find_child("Grip", true, false) != null, "Grip mesh exists")
	check(gun.find_child("TriggerGuardBottom", true, false) != null, "Trigger guard loop exists")
	check(gun.find_child("Trigger", true, false) != null, "Trigger exists")
	check(gun.find_child("FrontSight", true, false) != null, "Front sight exists")
	check(gun.find_child("RearSight", true, false) != null, "Rear sight exists")
	check(gun.find_child("MagBase", true, false) != null, "Magazine baseplate exists")
	check(gun.find_child("Muzzle", true, false) != null, "Muzzle Marker3D exists")
	check(gun.find_child("ShellPort", true, false) != null, "ShellPort Marker3D exists")

	var serr := 0
	for i in range(1, 4):
		if gun.find_child("SerrationRear%d" % i, true, false) != null:
			serr += 1
		if gun.find_child("SerrationFront%d" % i, true, false) != null:
			serr += 1
	check(serr == 6, "Slide serrations front+rear exist (got %d)" % serr)

	# Forward orientation: muzzle at -Z, grip raked behind frame
	var muzzle = gun.find_child("Muzzle", true, false) as Node3D
	var grip = gun.find_child("Grip", true, false) as Node3D
	check(muzzle.position.z < grip.position.z, "Muzzle forward of grip (-Z forward)")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
