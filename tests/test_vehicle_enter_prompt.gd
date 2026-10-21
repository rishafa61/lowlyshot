extends SceneTree

var fails: int = 0
var checks: int = 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FAIL: %s" % msg)
	else:
		print("  PASS: %s" % msg)

func _initialize() -> void:
	if root.get_node_or_null("GlobalData") == null:
		var gd := Node.new()
		gd.set_script(load("res://scripts/global_data.gd"))
		gd.name = "GlobalData"
		root.add_child(gd)
	if root.get_node_or_null("Sfx") == null:
		var sfx := Node.new()
		sfx.set_script(load("res://scripts/sfx.gd"))
		sfx.name = "Sfx"
		root.add_child(sfx)

	print("--- TEST 1: HUD Screen-Space Enter Prompt ---")
	var hud_scene = load("res://scenes/ui/hud.tscn")
	var hud = hud_scene.instantiate()
	root.add_child(hud)
	for i in 2: await process_frame

	check(hud.has_method("show_enter_prompt"), "HUD has show_enter_prompt")
	check(hud.has_method("hide_enter_prompt"), "HUD has hide_enter_prompt")
	hud.show_enter_prompt()
	check(hud.enter_prompt_ui != null, "enter_prompt_ui created on first show")
	check(hud.enter_prompt_ui.visible == true, "Prompt visible after show")
	hud.hide_enter_prompt()
	await create_timer(0.25).timeout
	check(hud.enter_prompt_ui.visible == false, "Prompt hidden after hide")

	var mock_player_script := GDScript.new()
	mock_player_script.source_code = "extends CharacterBody3D\nvar is_piloting := false\nvar hud: Node = null\nfunc _ready(): add_to_group('player')\nfunc enter_aircraft(_s): is_piloting = true\nfunc exit_aircraft(_p, _d, _v=Vector3.ZERO): is_piloting = false\nfunc take_damage(_a, _b, _c, _d, _e): pass\n"
	mock_player_script.reload()

	var player: CharacterBody3D = CharacterBody3D.new()
	player.set_script(mock_player_script)
	player.hud = hud
	root.add_child(player)
	player.add_to_group("player")
	for i in 2: await process_frame

	print("--- TEST 2: Helicopter Triggers Screen Prompt ---")
	var heli = load("res://scenes/vehicles/helicopter.tscn").instantiate()
	root.add_child(heli)
	for i in 2: await process_frame
	heli._on_body_entered(player)
	check(hud.enter_prompt_ui.visible == true, "Heli shows HUD prompt on approach")
	heli._on_body_exited(player)
	await create_timer(0.25).timeout
	check(hud.enter_prompt_ui.visible == false, "Heli hides HUD prompt on exit area")
	heli._on_body_entered(player)
	heli.net_sync_enter(player, 0)
	await create_timer(0.25).timeout
	check(hud.enter_prompt_ui.visible == false, "Heli hides HUD prompt when entered")
	heli.queue_free()

	print("--- TEST 3: Tank Triggers Screen Prompt ---")
	player.is_piloting = false
	var tank = load("res://scenes/vehicles/m1_abrams.tscn").instantiate()
	root.add_child(tank)
	for i in 2: await process_frame
	tank._on_body_entered(player)
	check(hud.enter_prompt_ui.visible == true, "Tank shows HUD prompt on approach")
	tank._on_body_exited(player)
	await create_timer(0.25).timeout
	check(hud.enter_prompt_ui.visible == false, "Tank hides HUD prompt on exit area")
	tank.queue_free()

	print("--- TEST 4: Humvee Triggers Screen Prompt ---")
	player.is_piloting = false
	var humvee = load("res://scenes/vehicles/humvee.tscn").instantiate()
	root.add_child(humvee)
	for i in 2: await process_frame
	humvee._on_body_entered(player)
	check(hud.enter_prompt_ui.visible == true, "Humvee shows HUD prompt on approach")
	humvee._on_body_exited(player)
	await create_timer(0.25).timeout
	check(hud.enter_prompt_ui.visible == false, "Humvee hides HUD prompt on exit area")
	humvee.queue_free()

	print("--- TEST 5: Jet Triggers Screen Prompt ---")
	player.is_piloting = false
	var jet = load("res://scenes/vehicles/aircraft.tscn").instantiate()
	root.add_child(jet)
	for i in 2: await process_frame
	jet._on_body_entered(player)
	check(hud.enter_prompt_ui.visible == true, "Jet shows HUD prompt on approach")
	jet.net_sync_enter(player, 0)
	await create_timer(0.25).timeout
	check(hud.enter_prompt_ui.visible == false, "Jet hides HUD prompt when entered")
	jet._on_body_exited(player)
	await create_timer(0.25).timeout
	check(hud.enter_prompt_ui.visible == false, "Jet hides HUD prompt on exit area")
	jet.queue_free()

	player.queue_free()
	hud.queue_free()

	print("RESULT: %s (%d fails / %d checks)" % ["OK" if fails == 0 else "FAIL", fails, checks])
	quit(0 if fails == 0 else 1)

