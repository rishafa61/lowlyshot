# Equipment slots & HUD weapon names test — headless
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

	# 1. Categories exist in GlobalData.weapons
	check(GlobalData.weapons.has("Throwable"), "GlobalData has 'Throwable' category")
	check(GlobalData.weapons.has("Heavy"), "GlobalData has 'Heavy' category")
	check(GlobalData.weapons["Throwable"].size() >= 2, "Throwable category has >= 2 items (grenade, flashbang)")
	check(GlobalData.weapons["Heavy"].size() >= 1, "Heavy category has >= 1 items (at4)")

	# 2. HUD has 5 slots and displays weapon names
	var hud_scene = load("res://scenes/ui/hud.tscn") as PackedScene
	var hud = hud_scene.instantiate()
	root.add_child(hud)
	await process_frame

	check(hud.slots.size() == 5, "HUD has 5 slot labels (got %d)" % hud.slots.size())
	hud.set_weapon_names(["AK-47", "Glock", "Combat Knife", "Frag Grenade", "AT4 Launcher"])
	hud.update_weapon_slot(0)
	check("> 1. AK-47 <" in hud.slots[0].text, "Active slot 1 formatted with weapon name: %s" % hud.slots[0].text)
	check("  2. Glock  " in hud.slots[1].text, "Inactive slot 2 formatted with weapon name: %s" % hud.slots[1].text)
	check("  4. Frag Grenade  " in hud.slots[3].text, "Slot 4 shows Throwable name: %s" % hud.slots[3].text)
	check("  5. AT4 Launcher  " in hud.slots[4].text, "Slot 5 shows Heavy name: %s" % hud.slots[4].text)
	hud.queue_free()
	await process_frame

	# 3. Loadout menu slots & group tabs layout
	var loadout_scene = load("res://scenes/ui/loadout_menu.tscn") as PackedScene
	var loadout = loadout_scene.instantiate()
	root.add_child(loadout)
	await process_frame
	await process_frame

	# SlotMelee card exists
	check(loadout.slot_cards.has("Melee"), "Loadout slot_cards has 'Melee'")
	check(loadout.slot_cards.has("Equip1"), "Loadout slot_cards has 'Equip1'")
	check(loadout.slot_cards.has("Equip2"), "Loadout slot_cards has 'Equip2'")

	# Equip1 category = Throwable
	loadout._set_slot("Equip1")
	await process_frame
	check(loadout.weapon_rows.has("grenade") and loadout.weapon_rows.has("flashbang"), "Equip1 shows throwables (grenade, flashbang)")

	# Equip2 category = Heavy
	loadout._set_slot("Equip2")
	await process_frame
	check(loadout.weapon_rows.has("at4"), "Equip2 shows heavy weapons (at4)")

	# GroupTabs is in Mid column above WeaponList
	check(loadout.group_list.get_parent().name == "Mid", "GroupTabs parent is Mid column")

	loadout.queue_free()
	await process_frame

	# 4. Player slot enum & binding
	var player_script = load("res://scenes/player/player.gd")
	check(player_script != null, "player.gd loads without parse errors")

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
