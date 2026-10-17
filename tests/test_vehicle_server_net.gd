# Server-Authoritative Vehicle Multiplayer Test — headless
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

	# 2. Helicopter test instance
	var heli_scene = load("res://scenes/vehicles/helicopter.tscn") as PackedScene
	check(heli_scene != null, "helicopter.tscn loads")
	var heli = heli_scene.instantiate()
	root.add_child(heli)
	await process_frame

	check(heli.occupants.size() >= 2, "Helicopter has >= 2 seats (got %d)" % heli.occupants.size())
	check(heli.has_free_seat(), "Helicopter initially has free seats")

	# 3. Simulate first player (Pilot) entering
	var player_scene = load("res://scenes/player/player.tscn") as PackedScene
	var p1 = player_scene.instantiate()
	p1.name = "1"
	root.add_child(p1)
	await process_frame

	heli.net_sync_enter(p1, 0)
	check(heli.occupants[0] == p1, "Player 1 occupies seat 0 (Pilot)")
	check(p1.get_parent() == heli.seats[0], "Player 1 reparented to seat 0")
	check(p1.is_piloting == true, "Player 1 is_piloting is true")

	# 4. Simulate second player (Friend) entering: must take SEAT 1, NOT seat 0!
	var p2 = player_scene.instantiate()
	p2.name = "2"
	root.add_child(p2)
	await process_frame

	var next_seat: int = heli.occupants.find(null)
	check(next_seat == 1, "Next available seat for Player 2 is seat 1 (got %d)" % next_seat)
	heli.net_sync_enter(p2, next_seat)
	check(heli.occupants[1] == p2, "Player 2 occupies seat 1 (Passenger)")
	check(heli.occupants[0] == p1, "Player 1 STILL occupies seat 0 (Pilot un-stolen)")
	check(p2.get_parent() == heli.seats[1], "Player 2 reparented to seat 1")

	# 5. Remote puppet model hiding in seat
	check(p1.collision_layer == 0, "Seated player 1 collision disabled")
	check(p2.collision_layer == 0, "Seated player 2 collision disabled")

	# 6. Exit vehicle test
	heli.net_sync_exit(1)
	check(heli.occupants[1] == null, "Player 2 exited seat 1")
	check(p2.is_piloting == false, "Player 2 restored is_piloting=false")

	# 7. Authoritative damage & explosion test
	var initial_hp: float = heli.hp
	# Host takes damage
	heli.take_damage(initial_hp + 50.0, "Shooter_Friend", "AT4 Rocket", "Ally", heli.global_position)
	check(heli.is_destroyed == true, "Helicopter destroyed on lethal damage")
	check(p1.is_dead == true, "Pilot player 1 killed in helicopter crash")

	p2.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
