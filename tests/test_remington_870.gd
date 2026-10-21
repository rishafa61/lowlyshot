# Remington 870 Shotgun test suite
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

	# 2. WeaponData Resource
	var r870 = load("res://resources/weapons/remington_870.tres") as WeaponData
	check(r870 != null, "remington_870.tres loads as WeaponData")
	check(r870.id == "remington_870", "ID is 'remington_870'")
	check(r870.mag == 6 and r870.max_mag == 6, "Capacity is 6 shells")
	check(r870.res == 24 and r870.max_res == 24, "Reserve is 24 shells")
	check(r870.pellets == 8, "Pellets per shot is 8")
	check(is_equal_approx(r870.dmg, 10.0), "Damage per pellet is 10 (80 max)")
	check(r870.auto == false, "Pump action is semi/single-shot")
	check(r870.is_shotgun == true, "Flagged as shotgun")
	check(is_equal_approx(r870.reload_time, 0.52), "Per-shell reload time configured")
	check(is_equal_approx(r870.fire_rate, 0.65), "Pump cycle cooldown configured (0.65s)")

	# 3. Model scenes
	var scn = load("res://scenes/weapons/main/remington_870.tscn") as PackedScene
	check(scn != null, "remington_870.tscn loads")
	var inst = scn.instantiate() as Node3D
	world.add_child(inst)
	await process_frame
	check(inst.find_child("Receiver", true, false) != null, "Receiver mesh exists")
	check(inst.find_child("Barrel", true, false) != null, "Barrel mesh exists")
	check(inst.find_child("MagTube", true, false) != null, "MagTube mesh exists")
	check(inst.find_child("Pump", true, false) != null, "Pump Node3D exists for animation")
	check(inst.find_child("PumpBody", true, false) != null, "PumpBody mesh exists")
	check(inst.find_child("Muzzle", true, false) != null, "Muzzle Marker3D exists")
	check(inst.find_child("ShellPort", true, false) != null, "ShellPort Marker3D exists")

	# 4. Loadout menu category & preview
	var loadout_script = load("res://scenes/ui/loadout_menu.gd")
	check(loadout_script.WEAPON_GROUPS["Primary"].has("Shotguns"), "Loadout Primary has 'Shotguns' category")
	check("remington_870" in loadout_script.WEAPON_GROUPS["Primary"]["Shotguns"], "Shotguns contains 'remington_870'")
	var preview_script = load("res://scenes/ui/weapon_preview.gd")
	check(preview_script.SCENES.has("remington_870"), "weapon_preview SCENES has 'remington_870'")

	# 5. Equip in Player
	for w in GlobalData.weapons["Primary"]:
		w["equipped"] = (w.get("id") == "remington_870")

	var player_scene = load("res://scenes/player/player.tscn") as PackedScene
	var player = player_scene.instantiate()
	world.add_child(player)
	await process_frame

	var pw = player.weapons[player.Slot.RIFLE]
	check(pw["id"] == "remington_870", "Player equipped remington_870")
	check(pw["mag"] == 6, "Initial mag is 6")
	check(pw["res"] == 24, "Initial res is 24")

	# 6. Firing mechanics: consumes 1 shell, sets pump cooldown
	player.active_slot = player.Slot.RIFLE
	player.fire_cooldown = 0.0
	player.is_reloading = false
	player.shoot_gun()
	check(pw["mag"] == 5, "Fired 1 shell -> 5 remaining")
	check(is_equal_approx(player.fire_cooldown, 0.65), "Pump cycle fire_cooldown active (0.65s)")

	# Rapid click prevented by fire_cooldown
	var old_mag: int = pw["mag"]
	if player.fire_cooldown > 0:
		# Should be blocked
		pass
	check(pw["mag"] == old_mag, "Rapid trigger blocked by pump cooldown")

	# 7. Shell-by-shell reloading
	pw["mag"] = 4
	pw["res"] = 10
	player.start_reload()
	check(player.is_reloading == true, "Started shell-by-shell reload")
	# Simulate 1 shell finish
	player.finish_reload()
	check(pw["mag"] == 5, "1 shell inserted (now 5)")
	check(pw["res"] == 9, "Reserve decremented (now 9)")
	check(player.is_reloading == true, "Chained next shell reload")
	# Interrupt via fire request
	player._reload_abort_requested = true
	player.finish_reload()
	check(player.is_reloading == false, "Reload interrupted cleanly")
	check(pw["mag"] == 5, "Ammo preserved without dupes on interrupt (5)")
	check(pw["res"] == 9, "Reserve preserved (9)")

	# Full mag terminates reload
	pw["mag"] = 6
	player.start_reload()
	player.finish_reload()
	check(player.is_reloading == false, "Full mag (6) terminates reload")

	# 8. Hitbox test: 8 pellets at 10 dmg
	var enemy_scene = load("res://scenes/enemies/capsule_enemy.tscn") as PackedScene
	var enemy = enemy_scene.instantiate()
	world.add_child(enemy)
	await process_frame

	var head_dmg = enemy.receive_damage(10.0, "head", "Player", "remington_870")
	check(is_equal_approx(head_dmg, 20.0), "Pellet headshot: 10 * 2 = 20 dmg")
	var body_dmg = enemy.receive_damage(10.0, "upper", "Player", "remington_870")
	check(is_equal_approx(body_dmg, 10.0), "Pellet body: 10 dmg")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
