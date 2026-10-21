# Steyr AUG Submachine Gun weapon implementation test suite
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
	var world := Node3D.new()
	root.add_child(world)

	# 1. Autoload GlobalData
	if root.get_node_or_null("/root/GlobalData") == null:
		var gd = Node.new()
		gd.set_script(load("res://scripts/global_data.gd"))
		gd.name = "GlobalData"
		root.add_child(gd)
		await process_frame

	var GlobalData = root.get_node("/root/GlobalData")

	# 2. Test Weapon Resource Data
	var aug_res = load("res://resources/weapons/steyr_aug.tres") as WeaponData
	check(aug_res != null, "steyr_aug.tres loads as WeaponData")
	check(aug_res.id == "steyr_aug", "AUG id is 'steyr_aug'")
	check(aug_res.display_name == "Steyr AUG", "AUG display name is 'Steyr AUG'")
	check(aug_res.auto == true, "AUG is fully automatic")
	check(aug_res.mag == 30 and aug_res.max_mag == 30, "AUG magazine capacity is 30 rounds")
	check(aug_res.res == 120 and aug_res.max_res == 120, "AUG reserve ammo is 120 rounds")
	check(is_equal_approx(aug_res.fire_rate, 0.0857), "AUG fire rate is ~0.0857s (700 RPM)")
	check(is_equal_approx(aug_res.reload_time, 2.2), "AUG reload duration is 2.2s")
	check(is_equal_approx(aug_res.dmg, 24.0) or is_equal_approx(aug_res.dmg, 15.0), "AUG damage is configured (24 or tuned 15)")
	check(aug_res.scene_path == "res://scenes/weapons/main/SteyrAUG.tscn", "AUG scene_path points to SteyrAUG.tscn")

	# 3. Test SteyrAUG 3D Model Scene & Components
	var aug_scene = load("res://scenes/weapons/main/SteyrAUG.tscn") as PackedScene
	check(aug_scene != null, "SteyrAUG.tscn loads as PackedScene")
	var aug_inst = aug_scene.instantiate() as Node3D
	check(aug_inst != null, "SteyrAUG.tscn instantiates as Node3D")
	world.add_child(aug_inst)
	await process_frame

	# Check script attachment
	check(aug_inst.get_script() != null, "SteyrAUG has script attached")
	check(is_equal_approx(aug_inst.get("body_damage"), 24.0), "Script exports body_damage = 24")
	check(is_equal_approx(aug_inst.get("reload_duration"), 2.2), "Script exports reload_duration = 2.2")
	check(aug_inst.get("mag_capacity") == 30, "Script exports mag_capacity = 30")

	# Check Reference Points
	var muzzle = aug_inst.find_child("Muzzle", true, false) as Marker3D
	check(muzzle != null, "SteyrAUG model has Muzzle Marker3D")
	var shell_port = aug_inst.find_child("ShellPort", true, false) as Marker3D
	check(shell_port != null, "SteyrAUG model has ShellPort Marker3D")
	var aim_point = aug_inst.find_child("AimPoint", true, false) as Marker3D
	check(aim_point != null, "SteyrAUG model has AimPoint Marker3D")
	var grip_point = aug_inst.find_child("GripPoint", true, false) as Marker3D
	check(grip_point != null, "SteyrAUG model has GripPoint Marker3D")

	# Check Bullpup Anatomy Components
	var stock_rear = aug_inst.find_child("StockRear", true, false)
	check(stock_rear != null, "SteyrAUG model has StockRear mesh")
	var butt_pad = aug_inst.find_child("StockButtPad", true, false)
	check(butt_pad != null, "SteyrAUG model has StockButtPad mesh")
	var magwell = aug_inst.find_child("MagwellAdapter", true, false)
	check(magwell != null, "SteyrAUG model has MagwellAdapter mesh")
	var mag_lower = aug_inst.find_child("MagLower", true, false)
	check(mag_lower != null, "SteyrAUG model has MagLower straight stick magazine")
	var grip = aug_inst.find_child("PistolGrip", true, false)
	check(grip != null, "SteyrAUG model has PistolGrip mesh")
	var guard_loop = aug_inst.find_child("TriggerGuardLoop", true, false)
	check(guard_loop != null, "SteyrAUG model has iconic large TriggerGuardLoop")
	var top_rail = aug_inst.find_child("TopRail", true, false)
	check(top_rail != null, "SteyrAUG model has TopRail mesh")
	var foregrip = aug_inst.find_child("Foregrip", true, false)
	check(foregrip != null, "SteyrAUG model has Foregrip mesh")
	var barrel = aug_inst.find_child("Barrel", true, false)
	check(barrel != null, "SteyrAUG model has Barrel mesh")
	var muzzle_brake = aug_inst.find_child("MuzzleBrake", true, false)
	check(muzzle_brake != null, "SteyrAUG model has MuzzleBrake mesh")
	var front_sight = aug_inst.find_child("FrontSightPost", true, false)
	check(front_sight != null, "SteyrAUG model has FrontSightPost")
	var rear_sight = aug_inst.find_child("RearSightAperture", true, false)
	check(rear_sight != null, "SteyrAUG model has RearSightAperture")

	# Check Bullpup Geometry: Magazine is behind PistolGrip (Z > Grip.Z in local space)
	check(magwell.position.z > grip.position.z, "Bullpup layout verified: magwell is behind pistol grip")

	# 4. Test GlobalData Catalog and Loadout Menu Integration
	var primary_list: Array = GlobalData.weapons.get("Primary", [])
	var found_aug := false
	for w in primary_list:
		if w.get("id") == "steyr_aug":
			found_aug = true
			break
	check(found_aug, "GlobalData weapons['Primary'] contains steyr_aug")

	var loadout_script = load("res://scenes/ui/loadout_menu.gd")
	check(loadout_script != null, "loadout_menu.gd loads")
	var groups = loadout_script.WEAPON_GROUPS
	check("steyr_aug" in groups["Primary"]["Submachine Guns"], "'Submachine Guns' category contains 'steyr_aug'")

	var preview_script = load("res://scenes/ui/weapon_preview.gd")
	check(preview_script != null, "weapon_preview.gd loads")
	check(preview_script.SCENES.has("steyr_aug"), "weapon_preview.gd SCENES dictionary has 'steyr_aug'")

	# 5. Test Player with Steyr AUG Equipped
	for w in GlobalData.weapons["Primary"]:
		w["equipped"] = (w.get("id") == "steyr_aug")

	var player_scene = load("res://scenes/player/player.tscn") as PackedScene
	check(player_scene != null, "player.tscn loads")
	var player = player_scene.instantiate()
	world.add_child(player)
	await process_frame

	check(player.weapons[player.Slot.RIFLE]["id"] == "steyr_aug", "Player Slot.RIFLE has Steyr AUG equipped")
	check(player.weapons[player.Slot.RIFLE]["mag"] == 30, "Player AUG initial mag is 30")
	check(player.weapons[player.Slot.RIFLE]["res"] == 120, "Player AUG initial res is 120")

	# 6. Test Reload duration helper
	var r_dur = player.get_active_reload_duration()
	check(is_equal_approx(r_dur, 2.2), "Player active reload duration is 2.2s for Steyr AUG")

	# 7. Test Shooting mechanics: ammo consumption and fire rate cooldown
	player.active_slot = player.Slot.RIFLE
	player.fire_cooldown = 0.0
	player.is_reloading = false
	player.shoot_gun()
	check(player.weapons[player.Slot.RIFLE]["mag"] == 29, "Shooting consumes 1 round (29 left)")
	check(is_equal_approx(player.fire_cooldown, 0.0857), "Fire cooldown set to AUG fire_rate (0.0857s / 700 RPM)")

	# 8. Test Reloading: mag transfer and duration
	player.start_reload()
	check(player.is_reloading == true, "Player enters reloading state")
	player.finish_reload()
	check(player.is_reloading == false, "Player completes reload")
	check(player.weapons[player.Slot.RIFLE]["mag"] == 30, "Mag restored to 30")
	check(player.weapons[player.Slot.RIFLE]["res"] == 119, "Reserve decremented to 119")

	# 9. Test Empty-magazine dry-fire click
	player.weapons[player.Slot.RIFLE]["mag"] = 0
	player.weapons[player.Slot.RIFLE]["res"] = 0
	player._empty_click_cd = 0.0
	player._play_empty_click()
	check(player._empty_click_cd > 0.0, "Empty click triggered cooldown")

	# 10. Test Damage and Headshot Multiplier via Hitbox
	var enemy_scene = load("res://scenes/enemies/capsule_enemy.tscn") as PackedScene
	check(enemy_scene != null, "capsule_enemy.tscn loads")
	var enemy = enemy_scene.instantiate()
	world.add_child(enemy)
	await process_frame

	var head_dmg = enemy.receive_damage(24.0, "head", "Player", "steyr_aug")
	check(is_equal_approx(head_dmg, 48.0), "Headshot deals 2x damage: 24.0 * 2 = 48.0 dmg")
	var body_dmg = enemy.receive_damage(24.0, "upper", "Player", "steyr_aug")
	check(is_equal_approx(body_dmg, 24.0), "Body hit deals 1x damage: 24.0 dmg")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
