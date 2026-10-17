# Tests for reworked sniper (AWP) model
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
	# 1. Load m700.tscn
	var scene = load("res://scenes/weapons/main/m700.tscn") as PackedScene
	check(scene != null, "m700.tscn loads as PackedScene")
	var sniper = scene.instantiate() as Node3D
	check(sniper != null, "m700 instantiates")
	check(sniper.name == "Sniper", "Root name is 'Sniper'")
	root.add_child(sniper)
	await process_frame

	# 2. Key parts exist
	var muzzle = sniper.get_node_or_null("Muzzle") as Marker3D
	check(muzzle != null, "Muzzle Marker3D exists")
	if muzzle != null:
		check(muzzle.position.z < -0.9, "Muzzle is at the forward barrel tip (z=%f)" % muzzle.position.z)

	var barrel = sniper.get_node_or_null("Barrel") as MeshInstance3D
	check(barrel != null, "Barrel exists")

	var forestock = sniper.get_node_or_null("Forestock") as MeshInstance3D
	check(forestock != null, "Green Forestock exists")

	var grip = sniper.get_node_or_null("Grip") as MeshInstance3D
	check(grip != null, "Pistol grip exists")

	var buttpad = sniper.get_node_or_null("Buttpad") as MeshInstance3D
	check(buttpad != null, "Buttpad exists at rear")
	if buttpad != null:
		check(buttpad.position.z > 0.3, "Buttpad is at rear (z=%f)" % buttpad.position.z)

	var mag = sniper.get_node_or_null("Magazine") as MeshInstance3D
	check(mag != null, "Detachable magazine exists")

	var lens = sniper.get_node_or_null("ScopeLens") as MeshInstance3D
	check(lens != null, "Scope front lens exists")
	if lens != null:
		var mat = lens.get_surface_override_material(0) as StandardMaterial3D
		check(mat != null, "Lens has override material")
		if mat != null:
			check(mat.emission_enabled, "Lens has emissive glow (reference cyan)")
			check(mat.albedo_color.b > 0.8, "Lens is blue/cyan (b=%f)" % mat.albedo_color.b)

	var tube = sniper.get_node_or_null("ScopeTube") as MeshInstance3D
	check(tube != null, "Scope body tube exists")

	var cheek = sniper.get_node_or_null("CheekRest") as MeshInstance3D
	check(cheek != null, "Cheek rest exists on stock")

	# 3. Clean up test instance
	sniper.queue_free()
	await process_frame

	# 4. Standby character compatibility (checks weapon_mount.get_node("Sniper"))
	var standby_scene = load("res://scenes/ui/standby_character.tscn") as PackedScene
	check(standby_scene != null, "standby_character.tscn loads")
	var standby = standby_scene.instantiate()
	root.add_child(standby)
	await process_frame
	var mounted_sniper = standby.get_node_or_null("WeaponMount/Sniper")
	check(mounted_sniper != null, "Standby character has mounted Sniper")
	standby.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
