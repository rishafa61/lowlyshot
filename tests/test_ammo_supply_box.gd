# Headless unit test for Ammo Supply Box
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
	# Autoload GlobalData
	if root.get_node_or_null("/root/GlobalData") == null:
		var gd = Node.new()
		gd.set_script(load("res://scripts/global_data.gd"))
		gd.name = "GlobalData"
		root.add_child(gd)
		await process_frame

	var GlobalData = root.get_node("/root/GlobalData")

	# 1. Resource and catalog registration
	var res = load("res://resources/weapons/ammo_box.tres") as WeaponData
	check(res != null, "ammo_box.tres loaded")
	check(res.id == "ammo_box", "ammo_box id matches")
	check(res.display_name == "Ammo Supply Box", "ammo_box display_name is 'Ammo Supply Box'")
	check(res.type == "deployable", "ammo_box type is 'deployable'")

	var found_in_cat: bool = false
	for path in GlobalData.WEAPON_CATALOG.get("Heavy", []):
		if "ammo_box.tres" in path:
			found_in_cat = true
			break
	check(found_in_cat, "ammo_box.tres registered in GlobalData.WEAPON_CATALOG['Heavy']")

	var found_in_weapons: bool = false
	for w in GlobalData.weapons.get("Heavy", []):
		if w.get("id") == "ammo_box":
			found_in_weapons = true
			break
	check(found_in_weapons, "ammo_box present in GlobalData.weapons['Heavy']")

	# 2. Loadout menu contains ammo_box
	var loadout_script = load("res://scenes/ui/loadout_menu.gd")
	var heavy_group = loadout_script.WEAPON_GROUPS.get("Heavy", {}).get("Heavy Weapons", [])
	check("ammo_box" in heavy_group, "loadout_menu WEAPON_GROUPS['Heavy'] contains 'ammo_box'")

	# 3. Ammo box scene instantiation & exported defaults
	var box_scene = load("res://scenes/weapons/heavy/ammo_box.tscn") as PackedScene
	check(box_scene != null, "ammo_box.tscn loaded")
	var box = box_scene.instantiate()
	root.add_child(box)
	await process_frame

	check(box.is_in_group("ammo_supply_boxes"), "ammo_box is in group 'ammo_supply_boxes'")
	check(box.max_active_per_player == 1, "max_active_per_player == 1")
	check(box.resupply_radius == 3.0, "resupply_radius == 3.0")
	check(box.resupply_interval == 1.0, "resupply_interval == 1.0")
	check(box.lifetime == 60.0, "lifetime == 60.0")
	check(box.total_supply_capacity == 100, "total_supply_capacity == 100")
	check(box.resupply_cost == 20, "resupply_cost == 20")
	check(box.supplies == 100, "initial supplies == 100")
	check(box.is_depleted == false, "initial is_depleted == false")
	check(box.deployments_per_life == 1, "deployments_per_life == 1")

	# 4. Mock Player and Resupply Mechanics
	var player_scene = load("res://scenes/player/player.tscn") as PackedScene
	var friendly_player = player_scene.instantiate()
	friendly_player.name = "FriendlyPlayer"
	friendly_player.team = "attackers"
	box.owner_team = "attackers"
	box.owner_peer_id = 1
	root.add_child(friendly_player)
	await process_frame

	# Simulate empty reserve ammo on primary rifle
	var rifle = friendly_player.weapons[friendly_player.Slot.RIFLE]
	rifle["mag"] = 15
	rifle["res"] = 10
	var orig_mag = rifle["mag"]
	var max_res = rifle["max_res"]

	check(friendly_player.can_receive_ammo(), "friendly_player can_receive_ammo() is true when reserve low")

	# Friendly resupply tick
	var granted = box.execute_resupply(friendly_player)
	check(granted, "execute_resupply returns true for low-ammo friendly")
	check(rifle["mag"] == orig_mag, "Magazine count unmodified by resupply (mag=%d)" % rifle["mag"])
	check(rifle["res"] > 10, "Reserve ammo replenished (res=%d)" % rifle["res"])
	check(box.supplies == 80, "Box supplies deducted by 20 (supplies=%d)" % box.supplies)

	# Test direct [F] interaction via interact_from_player and _handle_ammo_box_interact
	rifle["res"] = 10
	friendly_player.global_position = box.global_position + Vector3(0, 0, 1.5)
	check(friendly_player.has_method("_handle_ammo_box_interact"), "player has _handle_ammo_box_interact method")
	var f_handled = friendly_player._handle_ammo_box_interact()
	check(f_handled, "Player pressing [F] calls _handle_ammo_box_interact and returns true")
	check(rifle["res"] > 10, "Reserve ammo replenished on [F] interact (res=%d)" % rifle["res"])
	check(box.supplies == 60, "Box supplies deducted on [F] interact (supplies=%d)" % box.supplies)

	# Cap reserve ammo at max_res
	rifle["res"] = max_res
	var pistol = friendly_player.weapons[friendly_player.Slot.PISTOL]
	pistol["res"] = pistol["max_res"]
	var heavy_w = friendly_player.weapons[friendly_player.Slot.HEAVY]
	if heavy_w.has("max_res"): heavy_w["res"] = heavy_w["max_res"]

	check(not friendly_player.can_receive_ammo(), "can_receive_ammo() is false when all reserves full")
	var granted_full = box.execute_resupply(friendly_player)
	check(not granted_full, "execute_resupply rejected when reserves full")
	check(box.supplies == 60, "Box supplies not consumed when player full (supplies=%d)" % box.supplies)

	# Direct [F] press when full returns true (handled) and shows feedback without deducting box supplies
	var f_full = friendly_player._handle_ammo_box_interact()
	check(f_full, "[F] interact handled when ammo is full")
	check(box.supplies == 60, "Box supplies untouched when [F] pressed while full")

	# Enemy player check
	var enemy_player = player_scene.instantiate()
	enemy_player.name = "EnemyPlayer"
	enemy_player.team = "defenders"
	root.add_child(enemy_player)
	await process_frame

	var enemy_rifle = enemy_player.weapons[enemy_player.Slot.RIFLE]
	enemy_rifle["res"] = 0
	check(not box._is_friendly_to(enemy_player), "_is_friendly_to is false for enemy")
	var granted_enemy = box.execute_resupply(enemy_player)
	check(not granted_enemy, "execute_resupply rejected for enemy player")
	check(enemy_rifle["res"] == 0, "Enemy reserve ammo remains 0")
	check(box.supplies == 60, "Box supplies not consumed by enemy")

	# Capacity exhaustion & empty state
	rifle["res"] = 0
	box.execute_resupply(friendly_player) # 60 -> 40
	rifle["res"] = 0
	box.execute_resupply(friendly_player) # 40 -> 20
	rifle["res"] = 0
	box.execute_resupply(friendly_player) # 20 -> 0
	check(box.supplies == 0, "Box supplies reached 0")
	check(box.is_depleted == true, "Box is_depleted set to true when exhausted")

	# Subsequent resupply after depletion rejected
	rifle["res"] = 0
	var granted_depleted = box.execute_resupply(friendly_player)
	check(not granted_depleted, "Resupply refused when box is depleted")
	check(rifle["res"] == 0, "No ammo granted from depleted box")

	# Cleanup test (S&D round cleanup simulation)
	var boxes = root.get_tree().get_nodes_in_group("ammo_supply_boxes")
	check(boxes.size() >= 1, "ammo_supply_boxes group has >= 1 node before round cleanup")
	for b in boxes:
		b.queue_free()
	await process_frame
	await process_frame

	friendly_player.queue_free()
	enemy_player.queue_free()
	await process_frame

	if fails == 0:
		print("ALL AMMO SUPPLY BOX TESTS PASSED (0 fails)")
		quit(0)
	else:
		printerr("TESTS FAILED WITH %d FAILURES" % fails)
		quit(1)
