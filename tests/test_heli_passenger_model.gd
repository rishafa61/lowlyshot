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

	var hscene: PackedScene = load("res://scenes/vehicles/helicopter.tscn")
	var heli = hscene.instantiate()
	root.add_child(heli)

	var pscene: PackedScene = load("res://scenes/player/player.tscn")
	var player = pscene.instantiate()
	root.add_child(player)
	for i in 2:
		await process_frame

	print("--- TEST 1: Enter Pilot Seat (Seat 1) -> Body Hidden ---")
	heli.net_sync_enter(player, 0)
	check(player.is_piloting, "Player is piloting")
	check(player.get_parent() == heli.seats[0], "Parented to Pilot seat")
	check(player._puppet_body == null or not player._puppet_body.visible, "Model hidden in cockpit pilot seat")

	print("--- TEST 2: Switch to Seat 3 (Pass2) -> Model Attached in Crouch ---")
	player.switch_aircraft_seat(heli.seats[2])
	check(player.get_parent() == heli.seats[2], "Parented to Pass2")
	check(player._puppet_body != null and player._puppet_body.visible, "Model visible in Seat 3")
	check(player._puppet_body.position.is_equal_approx(player.SEAT_BODY_OFFSETS["Pass2"]),
		"Model shifted to bench cushion: %s" % player._puppet_body.position)
	var hb: HumanBody = player._puppet_body as HumanBody
	check(hb != null and hb.get_current_anim() == "Idle_Rifle", "Model playing Idle_Rifle seated animation")

	print("--- TEST 3: Switch through Seats 4, 5, 6 -> Model Tracks Each Bench ---")
	# Seat 4 (Pass3)
	player.switch_aircraft_seat(heli.seats[3])
	check(player._puppet_body.visible, "Model visible in Seat 4")
	check(player._puppet_body.position.is_equal_approx(player.SEAT_BODY_OFFSETS["Pass3"]),
		"Model shifted to Pass3 bench: %s" % player._puppet_body.position)

	# Seat 5 (Pass4)
	player.switch_aircraft_seat(heli.seats[4])
	check(player._puppet_body.visible, "Model visible in Seat 5")
	check(player._puppet_body.position.is_equal_approx(player.SEAT_BODY_OFFSETS["Pass4"]),
		"Model shifted to Pass4 bench: %s" % player._puppet_body.position)

	# Seat 6 (Pass5)
	player.switch_aircraft_seat(heli.seats[5])
	check(player._puppet_body.visible, "Model visible in Seat 6")
	check(player._puppet_body.position.is_equal_approx(player.SEAT_BODY_OFFSETS["Pass5"]),
		"Model shifted to Pass5 bench: %s" % player._puppet_body.position)

	print("--- TEST 4: Switch Back to Pilot (Seat 1) -> Model Hides ---")
	player.switch_aircraft_seat(heli.seats[0])
	check(not player._puppet_body.visible, "Model hidden after returning to Pilot seat")

	print("--- TEST 5: Switch to Seat 3 then Exit -> Clean Teardown ---")
	player.switch_aircraft_seat(heli.seats[2])
	check(player._puppet_body.visible, "Model visible in Seat 3")
	player.exit_aircraft(Vector3(10, 0, 10), Vector3.FORWARD)
	check(not player.is_piloting, "Player left aircraft")
	check(not player._puppet_body.visible, "Local player model hidden on foot (first-person)")
	check(player._puppet_body.position == Vector3.ZERO, "Body position reset to origin")

	print("--- TEST 6: Remote Puppet Enters Seat 3 -> Model Visible & Crouch ---")
	var puppet = pscene.instantiate()
	puppet.name = "RemotePlayer"
	root.add_child(puppet)
	puppet.is_puppet = true
	puppet._setup_puppet()
	check(puppet._puppet_body != null and puppet._puppet_body.visible, "Puppet body visible on foot")

	puppet.enter_aircraft(heli.seats[2])
	check(puppet._puppet_body.visible, "Puppet body visible in Seat 3")
	check(puppet._puppet_body.position.is_equal_approx(puppet.SEAT_BODY_OFFSETS["Pass2"]),
		"Puppet body attached to bench")
	var phb: HumanBody = puppet._puppet_body as HumanBody
	check(phb != null and phb.get_current_anim() == "Idle_Rifle", "Puppet playing Idle_Rifle seated pose")

	puppet.exit_aircraft(Vector3(-10, 0, 10), Vector3.FORWARD)
	check(puppet._puppet_body.visible, "Puppet body visible on foot after exit")
	check(phb.get_current_anim() == "Idle_Rifle", "Puppet back to Idle_Rifle on foot")

	heli.queue_free()
	player.queue_free()
	puppet.queue_free()

	print("RESULT: %s (%d fails / %d checks)" % ["OK" if fails == 0 else "FAIL", fails, checks])
	quit(1 if fails > 0 else 0)
