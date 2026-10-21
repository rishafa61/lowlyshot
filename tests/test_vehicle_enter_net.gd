# Vehicle seat multiplayer regression tests
# Covers: host-side enter/exit (call_local fix), passenger chase camera,
# puppet-safe enter_aircraft, and despawn of seat-reparented players (ghost fix).
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

	var arena = (load("res://scenes/levels/ground_war.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await process_frame
	await process_frame

	var mgr = arena # root node has multiplayer_manager.gd
	check(mgr.get_script() != null and mgr.get_script().resource_path.contains("multiplayer_manager"), "Arena root has MultiplayerManager script")
	var spawner = mgr.get_node("PlayerSpawner")
	check(spawner != null, "PlayerSpawner exists")

	# --- RPC call_local config is exercised functionally by the host-call tests below ---

	# --- Host-side enter path: direct local call (sender == 0 fallback) ---
	var p1 = spawner.spawn_player(1, "attackers")
	check(p1 != null, "Host player spawned")
	var p2 = spawner.spawn_player(2, "defenders")
	check(p2 != null, "Second player spawned")

	# find a ground vehicle
	var vehicle = null
	for v in get_nodes_in_group("vehicles"):
		if v is VehicleBody3D:
			vehicle = v
			break
	check(vehicle != null, "Found a ground vehicle")

	if vehicle != null:
		var vpath := str(vehicle.get_path())
		mgr.request_vehicle_enter(vpath) # host calls locally (was a silent no-op via rpc_id(1))
		await process_frame
		var container = spawner._get_container()
		check(vehicle.occupants.size() > 0 and vehicle.occupants[0] == p1, "Host entered driver seat via local request")
		check(p1.is_piloting, "Host player is_piloting")
		check(vehicle.chase_cam != null and vehicle.chase_cam.current, "Driver chase camera active")

		# passenger camera fix: second player into passenger seat
		var seat_idx: int = vehicle.occupants.find(null)
		mgr.net_vehicle_enter(vpath, 2, seat_idx) # direct call (simulates RPC dispatch)
		await process_frame
		check(seat_idx > 0, "Passenger got a non-driver seat (%d)" % seat_idx)
		check(p2 != null and p2.is_piloting, "Passenger seated")
		check(vehicle.chase_cam != null and vehicle.chase_cam.current, "Passenger gets a camera (chase cam active)")

		# host exit via local request
		mgr.request_vehicle_exit(vpath, 0)
		await process_frame
		check(not p1.is_piloting, "Host exited driver seat via local request")
		check(p1.get_parent() == container, "Exited player restored to player container")

	# --- Ghost fix: despawn finds players reparented under a vehicle seat ---
	if vehicle != null and p2.is_piloting:
		# p2 is under the vehicle seat now; remove via spawner
		spawner._remove_local(2)
		await process_frame
		var still_there := false
		for n in get_nodes_in_group("player"):
			if is_instance_valid(n) and n.name == "2":
				still_there = true
		check(not still_there, "Despawn removes seat-reparented player (no ghost)")

	# --- Puppet-safe enter_aircraft: freed local-only nodes must not crash ---
	var puppet = spawner._build_player({"peer": 7, "team": "defenders"})
	if puppet != null:
		puppet.set_multiplayer_authority(7) # pretend remote
		puppet.hud = null
		var wh = puppet.get_node_or_null("Head/Camera3D/WeaponHolder")
		if wh:
			wh.free() # simulate _setup_puppet cleanup
		spawner._get_container().add_child(puppet) # must be in tree to reparent
		var heli = null
		for v in get_nodes_in_group("vehicles"):
			if v is RigidBody3D and v.get("seats") != null and v.seats.size() >= 2:
				heli = v
				break
		if heli != null:
			var seat: Marker3D = heli.seats[1]
			puppet.enter_aircraft(seat)
			check(puppet.is_piloting, "Puppet enter_aircraft survives freed nodes")
			check(puppet.get_parent() == seat, "Puppet reparented to seat")
		puppet.queue_free()

	arena.queue_free()
	await process_frame
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
