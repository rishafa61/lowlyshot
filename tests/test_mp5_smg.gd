# MP5 Submachine Gun weapon implementation test suite
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
	var mp5_res = load("res://resources/weapons/mp5.tres") as WeaponData
	check(mp5_res != null, "mp5.tres loads as WeaponData")
	check(mp5_res.id == "mp5", "MP5 id is 'mp5'")
	check(mp5_res.display_name == "MP5", "MP5 display name is 'MP5'")
	check(mp5_res.auto == true, "MP5 is fully automatic")
	check(mp5_res.mag == 30 and mp5_res.max_mag == 30, "MP5 magazine capacity is 30 rounds")
	check(mp5_res.res == 120 and mp5_res.max_res == 120, "MP5 reserve ammo is 120 rounds")
	check(is_equal_approx(mp5_res.fire_rate, 0.075), "MP5 fire rate is 0.075s (800 RPM)")
	check(is_equal_approx(mp5_res.reload_time, 2.0), "MP5 reload duration is 2.0s")
	check(is_equal_approx(mp5_res.dmg, 20.0), "MP5 damage is 20 per body hit")

	# 3. Test MP5 3D Model Scene
	var mp5_scene = load("res://scenes/weapons/main/mp5.tscn") as PackedScene
	check(mp5_scene != null, "mp5.tscn loads as PackedScene")
	var mp5_inst = mp5_scene.instantiate() as Node3D
	check(mp5_inst != null, "mp5.tscn instantiates as Node3D")
	world.add_child(mp5_inst)
	await process_frame

	var muzzle = mp5_inst.find_child("Muzzle", true, false) as Marker3D
	check(muzzle != null, "MP5 model has Muzzle Marker3D")
	var shell_port = mp5_inst.find_child("ShellPort", true, false) as Marker3D
	check(shell_port != null, "MP5 model has ShellPort Marker3D")
	var receiver = mp5_inst.find_child("Receiver", true, false)
	check(receiver != null, "MP5 model has Receiver mesh")
	var handguard = mp5_inst.find_child("Handguard", true, false)
	check(handguard != null, "MP5 model has Handguard mesh")
	var barrel = mp5_inst.find_child("Barrel", true, false)
	check(barrel != null, "MP5 model has Barrel mesh")
	var sight_ring = mp5_inst.find_child("FrontSightRing", true, false)
	check(sight_ring != null, "MP5 model has FrontSightRing mesh")
	var rear_drum = mp5_inst.find_child("RearSightDrum", true, false)
	check(rear_drum != null, "MP5 model has RearSightDrum mesh")
	var mag_seg1 = mp5_inst.find_child("MagSeg1", true, false)
	check(mag_seg1 != null, "MP5 model has curved magazine segments")

	# 4. Test GlobalData Catalog and Loadout Menu Integration
	var primary_list: Array = GlobalData.weapons.get("Primary", [])
	var found_mp5 := false
	for w in primary_list:
		if w.get("id") == "mp5":
			found_mp5 = true
			break
	check(found_mp5, "GlobalData weapons['Primary'] contains mp5")

	var loadout_script = load("res://scenes/ui/loadout_menu.gd")
	check(loadout_script != null, "loadout_menu.gd loads")
	var groups = loadout_script.WEAPON_GROUPS
	check(groups.has("Primary"), "WEAPON_GROUPS has 'Primary'")
	check(groups["Primary"].has("Submachine Guns"), "WEAPON_GROUPS['Primary'] has 'Submachine Guns' category")
	check("mp5" in groups["Primary"]["Submachine Guns"], "'Submachine Guns' category contains 'mp5'")

	var preview_script = load("res://scenes/ui/weapon_preview.gd")
	check(preview_script != null, "weapon_preview.gd loads")
	check(preview_script.SCENES.has("mp5"), "weapon_preview.gd SCENES dictionary has 'mp5'")

	# 5. Test Player with MP5 Equipped
	# Set MP5 as equipped primary
	for w in GlobalData.weapons["Primary"]:
		w["equipped"] = (w.get("id") == "mp5")

	var player_scene = load("res://scenes/player/player.tscn") as PackedScene
	check(player_scene != null, "player.tscn loads")
	var player = player_scene.instantiate()
	world.add_child(player)
	await process_frame

	check(player.weapons[player.Slot.RIFLE]["id"] == "mp5", "Player Slot.RIFLE has MP5 equipped")
	check(player.weapons[player.Slot.RIFLE]["mag"] == 30, "Player MP5 initial mag is 30")
	check(player.weapons[player.Slot.RIFLE]["res"] == 120, "Player MP5 initial res is 120")

	# 6. Test Reload duration helper
	var r_dur = player.get_active_reload_duration()
	check(is_equal_approx(r_dur, 2.0), "Player active reload duration is 2.0s for MP5")

	# 7. Test Shooting mechanics: ammo consumption and tracer
	player.active_slot = player.Slot.RIFLE
	player.fire_cooldown = 0.0
	player.is_reloading = false
	player.shoot_gun()
	check(player.weapons[player.Slot.RIFLE]["mag"] == 29, "Shooting consumes 1 round (29 left)")
	check(is_equal_approx(player.fire_cooldown, 0.075), "Fire cooldown set to MP5 fire_rate (0.075s)")

	# 8. Test Reloading: mag transfer and duration
	player.start_reload()
	check(player.is_reloading == true, "Player enters reloading state")
	# Simulate reload completion
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

	var head_dmg = enemy.receive_damage(20.0, "head", "Player", "mp5")
	check(is_equal_approx(head_dmg, 40.0), "Headshot deals 2x damage (40.0 dmg)")
	var body_dmg = enemy.receive_damage(20.0, "upper", "Player", "mp5")
	check(is_equal_approx(body_dmg, 20.0), "Body hit deals 1x damage (20.0 dmg)")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
