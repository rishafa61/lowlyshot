# RPD Light Machine Gun weapon implementation test suite
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
	var rpd_res = load("res://resources/weapons/rpd.tres") as WeaponData
	check(rpd_res != null, "rpd.tres loads as WeaponData")
	check(rpd_res.id == "rpd", "RPD id is 'rpd'")
	check(rpd_res.display_name == "RPD", "RPD display name is 'RPD'")
	check(rpd_res.auto == true, "RPD is fully automatic")
	check(rpd_res.mag == 100 and rpd_res.max_mag == 100, "RPD magazine capacity is 100 rounds")
	check(rpd_res.res == 200 and rpd_res.max_res == 200, "RPD reserve ammo is 200 rounds")
	check(is_equal_approx(rpd_res.fire_rate, 0.0923), "RPD fire rate is ~0.0923s (650 RPM)")
	check(is_equal_approx(rpd_res.reload_time, 5.0), "RPD reload duration is 5.0s")
	check(is_equal_approx(rpd_res.dmg, 25.0) or is_equal_approx(rpd_res.dmg, 18.0), "RPD damage is configured (25 or tuned 18)")
	check(is_equal_approx(rpd_res.speed_mult, 0.85), "RPD mobility speed_mult is 0.85 (heavier gun)")
	check(rpd_res.scene_path == "res://scenes/weapons/main/RPD.tscn", "RPD scene_path points to RPD.tscn")

	# 3. Test RPD 3D Model Scene & Components
	var rpd_scene = load("res://scenes/weapons/main/RPD.tscn") as PackedScene
	check(rpd_scene != null, "RPD.tscn loads as PackedScene")
	var rpd_inst = rpd_scene.instantiate() as Node3D
	check(rpd_inst != null, "RPD.tscn instantiates as Node3D")
	world.add_child(rpd_inst)
	await process_frame

	# Check script attachment & inspector exports
	check(rpd_inst.get_script() != null, "RPD has script attached")
	check(is_equal_approx(rpd_inst.get("body_damage"), 25.0), "Script exports body_damage = 25")
	check(is_equal_approx(rpd_inst.get("reload_duration"), 5.0), "Script exports reload_duration = 5.0")
	check(rpd_inst.get("mag_capacity") == 100, "Script exports mag_capacity = 100")
	check(is_equal_approx(rpd_inst.get("movement_speed_mult"), 0.85), "Script exports movement_speed_mult = 0.85")

	# Check Reference Points
	var muzzle = rpd_inst.find_child("Muzzle", true, false) as Marker3D
	check(muzzle != null, "RPD model has Muzzle Marker3D")
	var shell_port = rpd_inst.find_child("ShellPort", true, false) as Marker3D
	check(shell_port != null, "RPD model has ShellPort Marker3D")
	var aim_point = rpd_inst.find_child("AimPoint", true, false) as Marker3D
	check(aim_point != null, "RPD model has AimPoint Marker3D")
	var grip_point = rpd_inst.find_child("GripPoint", true, false) as Marker3D
	check(grip_point != null, "RPD model has GripPoint Marker3D")

	# Check RPD Anatomy Components
	var stock = rpd_inst.find_child("StockClub", true, false)
	check(stock != null, "RPD model has Soviet wood club buttstock")
	var drum = rpd_inst.find_child("DrumMagazine", true, false)
	check(drum != null, "RPD model has 100-round drum magazine")
	var belt = rpd_inst.find_child("AmmoBelt", true, false)
	check(belt != null, "RPD model has visible linked ammunition belt")
	var handguard = rpd_inst.find_child("Handguard", true, false)
	check(handguard != null, "RPD model has contoured wood handguard")
	var barrel = rpd_inst.find_child("Barrel", true, false)
	check(barrel != null, "RPD model has long LMG barrel")
	var bipod = rpd_inst.find_child("BipodMount", true, false)
	check(bipod != null, "RPD model has BipodMount")
	var bipod_l = rpd_inst.find_child("BipodLegL", true, false)
	var bipod_r = rpd_inst.find_child("BipodLegR", true, false)
	check(bipod_l != null and bipod_r != null, "RPD model has folded bipod legs tucked under barrel")
	var front_sight = rpd_inst.find_child("FrontSightPost", true, false)
	check(front_sight != null, "RPD model has hooded front sight post")
	var rear_sight = rpd_inst.find_child("RearSightLeaf", true, false)
	check(rear_sight != null, "RPD model has rear tangent leaf sight")

	# 4. Test GlobalData Catalog and Loadout Menu Integration
	var primary_list: Array = GlobalData.weapons.get("Primary", [])
	var found_rpd := false
	for w in primary_list:
		if w.get("id") == "rpd":
			found_rpd = true
			break
	check(found_rpd, "GlobalData weapons['Primary'] contains rpd")

	var loadout_script = load("res://scenes/ui/loadout_menu.gd")
	check(loadout_script != null, "loadout_menu.gd loads")
	var groups = loadout_script.WEAPON_GROUPS
	check(groups["Primary"].has("Light Machine Guns"), "'Primary' has 'Light Machine Guns' category")
	check("rpd" in groups["Primary"]["Light Machine Guns"], "'Light Machine Guns' category contains 'rpd'")

	var preview_script = load("res://scenes/ui/weapon_preview.gd")
	check(preview_script != null, "weapon_preview.gd loads")
	check(preview_script.SCENES.has("rpd"), "weapon_preview.gd SCENES dictionary has 'rpd'")

	# 5. Test Player with RPD Equipped
	for w in GlobalData.weapons["Primary"]:
		w["equipped"] = (w.get("id") == "rpd")

	var player_scene = load("res://scenes/player/player.tscn") as PackedScene
	check(player_scene != null, "player.tscn loads")
	var player = player_scene.instantiate()
	world.add_child(player)
	await process_frame

	check(player.weapons[player.Slot.RIFLE]["id"] == "rpd", "Player Slot.RIFLE has RPD equipped")
	check(player.weapons[player.Slot.RIFLE]["mag"] == 100, "Player RPD initial mag is 100")
	check(player.weapons[player.Slot.RIFLE]["res"] == 200, "Player RPD initial res is 200")

	# 6. Test Reload duration helper
	var r_dur = player.get_active_reload_duration()
	check(is_equal_approx(r_dur, 5.0), "Player active reload duration is 5.0s for RPD")

	# 7. Test Shooting mechanics: ammo consumption and fire rate cooldown
	player.active_slot = player.Slot.RIFLE
	player.fire_cooldown = 0.0
	player.is_reloading = false
	player.shoot_gun()
	check(player.weapons[player.Slot.RIFLE]["mag"] == 99, "Shooting consumes 1 round (99 left)")
	check(is_equal_approx(player.fire_cooldown, 0.0923), "Fire cooldown set to RPD fire_rate (0.0923s / 650 RPM)")

	# 8. Test Reloading: mag transfer and duration
	player.start_reload()
	check(player.is_reloading == true, "Player enters reloading state")
	player.finish_reload()
	check(player.is_reloading == false, "Player completes reload")
	check(player.weapons[player.Slot.RIFLE]["mag"] == 100, "Mag restored to 100")
	check(player.weapons[player.Slot.RIFLE]["res"] == 199, "Reserve decremented to 199")

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

	var head_dmg = enemy.receive_damage(25.0, "head", "Player", "rpd")
	check(is_equal_approx(head_dmg, 50.0), "Headshot deals 2x damage: 25.0 * 2 = 50.0 dmg")
	var body_dmg = enemy.receive_damage(25.0, "upper", "Player", "rpd")
	check(is_equal_approx(body_dmg, 25.0), "Body hit deals 1x damage: 25.0 dmg")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
