# Launcher test — headless: AT4 weapon data, 3D model, rocket homing/unguided flight,
# blast damage, lock indicator HUD, and loadout preview integration.
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
	# 1. GlobalData setup
	if root.get_node_or_null("/root/GlobalData") == null:
		var gd = Node.new()
		gd.set_script(load("res://scripts/global_data.gd"))
		gd.name = "GlobalData"
		root.add_child(gd)
		await process_frame

	# 2. AT4 Weapon Resource check
	var at4_res = load("res://resources/weapons/at4.tres")
	check(at4_res is WeaponData, "AT4 resource is WeaponData")
	check(at4_res.id == "at4", "AT4 id == 'at4'")
	check(at4_res.type == "launcher", "AT4 type == 'launcher'")
	check(at4_res.dmg >= 400.0, "AT4 direct damage >= 400 (%f)" % at4_res.dmg)

	# 3. AT4 3D Viewmodel Scene check
	var at4_scene = load("res://scenes/weapons/heavy/at4.tscn") as PackedScene
	check(at4_scene != null, "at4.tscn loads successfully")
	var at4_inst = at4_scene.instantiate()
	root.add_child(at4_inst)
	check(at4_inst.find_child("Muzzle", true, false) != null, "at4.tscn has Muzzle marker")
	check(at4_inst.find_child("MainTube", true, false) != null, "at4.tscn has MainTube")
	at4_inst.queue_free()
	await process_frame

	# 4. AT4 Rocket Unguided flight check
	var rocket_scene = load("res://scenes/weapons/heavy/at4_rocket.tscn") as PackedScene
	check(rocket_scene != null, "at4_rocket.tscn loads successfully")
	var r_unguided = rocket_scene.instantiate()
	root.add_child(r_unguided)
	r_unguided.global_position = Vector3(0, 5, 0)
	r_unguided.direction = Vector3(0, 0, -1)
	r_unguided._physics_process(0.1)
	check(r_unguided.global_position.z < 0.0, "unguided rocket flies straight along forward vector")
	r_unguided.queue_free()
	await process_frame

	# 5. AT4 Rocket Locked Homing flight check
	var dummy_vehicle = RigidBody3D.new()
	dummy_vehicle.add_to_group("vehicles")
	dummy_vehicle.global_position = Vector3(50, 5, -50)
	dummy_vehicle.set_script(load("res://scripts/vehicles/helicopter_controller.gd"))
	root.add_child(dummy_vehicle)

	var r_guided = rocket_scene.instantiate()
	root.add_child(r_guided)
	r_guided.global_position = Vector3(0, 5, 0)
	r_guided.direction = Vector3(0, 0, -1)
	r_guided.target_vehicle = dummy_vehicle
	r_guided._physics_process(0.2)
	# Homing steering should turn direction toward +X
	check(r_guided.direction.x > 0.05, "guided rocket turns toward target vehicle (%f)" % r_guided.direction.x)

	# 6. Rocket explosion damage on vehicle
	var initial_hp: float = dummy_vehicle.hp
	r_guided.explode(dummy_vehicle.global_position, dummy_vehicle)
	check(dummy_vehicle.hp < initial_hp, "rocket blast deals damage to vehicle (hp: %f -> %f)" % [initial_hp, dummy_vehicle.hp])
	dummy_vehicle.queue_free()
	await process_frame

	# 7. HUD Lock Indicator check
	var hud_scene = load("res://scenes/ui/hud.tscn") as PackedScene
	var hud = hud_scene.instantiate()
	root.add_child(hud)
	await process_frame
	check(hud.has_method("show_lock_indicator"), "HUD has show_lock_indicator")
	hud.show_lock_indicator(0.5, false) # acquiring ring
	check(hud.lock_ui.visible == true, "HUD lock_ui visible on acquire")
	check(hud.lock_ring.visible == true and hud.lock_box.visible == false, "HUD shows ring when acquiring")
	hud.show_lock_indicator(1.0, true) # locked box
	check(hud.lock_box.visible == true and hud.lock_ring.visible == false, "HUD shows box when locked")
	hud.hide_lock_indicator()
	check(hud.lock_ui.visible == false, "HUD hides lock UI")
	hud.queue_free()
	await process_frame

	# 8. Loadout Menu preview for AT4
	var loadout = load("res://scenes/ui/loadout_menu.tscn").instantiate()
	root.add_child(loadout)
	await process_frame
	await process_frame
	loadout.preview_wp.show_weapon("at4")
	await process_frame
	check(loadout.preview_wp.current_id == "at4", "loadout preview switches to at4")
	check(loadout.preview_wp.get_child_count() > 0, "loadout preview instances at4 model")
	loadout.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
