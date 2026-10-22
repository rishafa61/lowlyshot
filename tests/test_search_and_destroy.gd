# Search & Destroy system test — headless
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
	print("--- Running Search & Destroy System Tests ---")

	# Singletons required by MultiplayerManager._ready (GlobalData etc.)
	for name in ["GlobalData", "GlobalSettings"]:
		if not root.has_node(name):
			var sc = load("res://scripts/%s.gd" % ("global_data" if name == "GlobalData" else "global_settings"))
			if sc:
				var gd = Node.new()
				gd.name = name
				gd.set_script(sc)
				root.add_child(gd)
	await process_frame

	# 1. Test scene instantiation (full level scene: manager + sites + spawns)
	var snd_scene := load("res://scenes/levels/search_and_destroy.tscn") as PackedScene
	check(snd_scene != null, "search_and_destroy.tscn loads")
	var mgr = snd_scene.instantiate()
	check(mgr != null, "S&D level scene instantiates")
	root.add_child(mgr)
	await process_frame

	# 2. Check defaults
	check(mgr.round_duration == 120, "round_duration is 120")
	check(mgr.plant_duration == 4.0, "plant_duration is 4.0")
	check(mgr.defuse_duration == 5.0, "defuse_duration is 5.0")
	check(mgr.bomb_countdown == 40, "bomb_countdown is 40")
	check(mgr.rounds_to_win == 5, "rounds_to_win is 5")
	check(mgr.halftime_round == 4, "halftime_round is 4")
	check(mgr.disable_auto_respawn == true, "disable_auto_respawn is true")

	# 3. Check sites and spawns exist
	var sites: Array = mgr.get_tree().get_nodes_in_group("bombsite")
	check(sites.size() >= 2, "At least 2 bomb sites exist in level")
	var found_a := false
	var found_b := false
	for s in sites:
		if s.site_id == "A": found_a = true
		if s.site_id == "B": found_b = true
	check(found_a and found_b, "Both Site A and Site B exist")

	var spawns: Array = mgr.get_tree().get_nodes_in_group("spawn_points")
	var att_spawns := 0
	var def_spawns := 0
	for sp in spawns:
		if sp.team == "attackers": att_spawns += 1
		if sp.team == "defenders": def_spawns += 1
	check(att_spawns >= 5, "Attackers have at least 5 spawn points")
	check(def_spawns >= 5, "Defenders have at least 5 spawn points")

	# 4. Carrier assignment & drop logic
	mgr.current_state = mgr.MatchState.ACTIVE
	mgr.players_data[1] = {"name": "Player", "team": "attackers", "kills": 0, "deaths": 0, "ping": 0}
	mgr.players_data[2] = {"name": "Defender1", "team": "defenders", "kills": 0, "deaths": 0, "ping": 0}
	mgr.match_stats["Player"] = {"kills": 0, "deaths": 0, "team": "attackers"}
	mgr.match_stats["Defender1"] = {"kills": 0, "deaths": 0, "team": "defenders"}

	# Spawn a real player node for peer 1 so distance/position validation works
	var p1 = mgr.spawner.spawn_player(1, "attackers")
	check(p1 != null, "Spawned player node for peer 1")

	mgr._assign_bomb_carrier()
	check(mgr.bomb_carrier_peer == 1, "Player 1 assigned bomb carrier")
	check(mgr.current_bomb_state == mgr.BombState.CARRIED, "Bomb state is CARRIED")

	# Simulate carrier death -> bomb should drop at player position
	p1.global_position = Vector3(0, 0, 0)
	mgr._handle_carrier_death("Player")
	check(mgr.current_bomb_state == mgr.BombState.DROPPED, "Bomb dropped on carrier death")
	check(mgr._world_bomb_instance != null, "World bomb instance spawned")

	# 5. Attacker pickup validation
	# Player 1 is near bomb (0,0,0)
	p1.global_position = mgr.bomb_world_position
	mgr.request_pickup_bomb() # sender 1 (attacker)
	check(mgr.current_bomb_state == mgr.BombState.CARRIED, "Attacker picked up dropped bomb")

	# 6. Plant validation outside site vs inside site
	var site_a = null
	for s in sites:
		if s.site_id == "A": site_a = s
	check(site_a != null, "Site A found for plant test")

	# Outside site
	var p_node = mgr._get_player_node_by_peer(1)
	if p_node:
		p_node.global_position = Vector3(100, 0, 100) # Far outside
	mgr.request_start_plant("A")
	check(mgr.current_bomb_state == mgr.BombState.CARRIED, "Plant rejected outside bomb site")

	# Inside site
	if p_node and site_a:
		p_node.global_position = site_a.global_position
	mgr.request_start_plant("A")
	check(mgr.current_bomb_state == mgr.BombState.PLANTING, "Plant accepted inside Site A")

	# Finish plant
	mgr._plant_bomb_success()
	check(mgr.current_bomb_state == mgr.BombState.PLANTED, "Bomb state is PLANTED")
	check(mgr.planted_site_id == "A", "Planted site recorded as A")
	check(mgr.bomb_timer == 40, "Bomb timer initialized to countdown 40")

	# 7. Elimination win rule post-plant: all attackers dead does NOT end round
	mgr.current_state = mgr.MatchState.ACTIVE
	# A living defender is required, otherwise defenders=0 is a legit instant
	# "attackers win by elimination" and the planted-bomb branch never runs
	var p2 = mgr.spawner.spawn_player(2, "defenders")
	# Simulate 0 living attackers
	if p_node:
		p_node.is_dead = true
	mgr._check_elimination_win()
	check(mgr.current_state == mgr.MatchState.ACTIVE, "Post-plant attackers death does not end round")
	if p_node:
		p_node.is_dead = false

	# 8. Defuse validation
	# Attacker cannot defuse
	mgr.request_start_defuse() # sender is 1 (attacker) -> should reject
	check(mgr.current_bomb_state == mgr.BombState.PLANTED, "Attacker cannot defuse")

	# Defuse success -> Defenders win round
	mgr._defuse_bomb_success()
	check(mgr.current_bomb_state == mgr.BombState.DEFUSED, "Bomb state is DEFUSED")
	check(mgr.round_winner == "defenders", "Defenders won round by defusal")
	check(mgr.team_scores["defenders"] == 1, "Defenders score incremented to 1")

	# 9. Halftime swap test
	mgr.swap_halftime_teams()
	check(mgr.players_data[1]["team"] == "defenders", "Player 1 swapped to defenders at halftime")
	check(mgr.players_data[2]["team"] == "attackers", "Player 2 swapped to attackers at halftime")

	# 10. Match win condition check
	mgr.team_scores["defenders"] = 5 # rounds_to_win is 5
	mgr._advance_after_round_end()
	check(mgr.current_state == mgr.MatchState.MATCH_END, "Match transitions to MATCH_END when rounds_to_win reached")

	mgr.queue_free()

	print("--- S&D Tests Complete: %d fails ---" % fails)
	if fails > 0:
		quit(1)
	else:
		print("ALL S&D TESTS PASSED!")
		quit(0)
