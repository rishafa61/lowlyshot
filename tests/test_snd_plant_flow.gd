# S&D plant-over-time flow test — headless
# Reproduces: carrier stands in site, holds F, request_start_plant fires,
# host _process must tick _process_bomb_action to PLANTED in 4 s.
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
	for name in ["GlobalData", "GlobalSettings"]:
		if not root.has_node(name):
			var sc = load("res://scripts/%s.gd" % ("global_data" if name == "GlobalData" else "global_settings"))
			if sc:
				var gd = Node.new()
				gd.name = name
				gd.set_script(sc)
				root.add_child(gd)
	await process_frame

	var snd_scene := load("res://scenes/levels/search_and_destroy.tscn") as PackedScene
	var mgr = snd_scene.instantiate()
	root.add_child(mgr)
	await process_frame

	mgr.current_state = mgr.MatchState.ACTIVE
	mgr.players_data[1] = {"name": "Player", "team": "attackers", "kills": 0, "deaths": 0, "ping": 0}
	mgr.match_stats["Player"] = {"kills": 0, "deaths": 0, "team": "attackers"}

	var p1 = mgr.spawner.spawn_player(1, "attackers")
	check(p1 != null, "player node spawned")

	# Put player inside Site B with the bomb
	var site_b = null
	for s in mgr.get_tree().get_nodes_in_group("bombsite"):
		if s.site_id == "B": site_b = s
	p1.global_position = site_b.global_position + Vector3(2, 1, 0)
	mgr.bomb_carrier_peer = 1
	mgr.bomb_carrier_name = "Player"
	mgr.current_bomb_state = mgr.BombState.CARRIED

	mgr.request_start_plant("B")
	check(mgr.current_bomb_state == mgr.BombState.PLANTING, "plant accepted, state PLANTING")
	check(mgr.current_action_peer == 1, "action peer = 1")
	check(mgr.current_action_target_time == 4.0, "target time = 4.0")

	# Player-side hold latch: replicate _snd_process_interactions request logic.
	# Regression: strict `bomb_state == 0` made requested flip to "" the frame
	# after start (host state = PLANTING=2), sending stop -> start/cancel loop.
	var active_request := "PLANT" # sent on the frame F was first held
	var stops_sent := 0
	var planted_seen := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		await process_frame
		if mgr.current_bomb_state == mgr.BombState.PLANTED:
			planted_seen = true
			break
		var poll_state := int(mgr.current_bomb_state)
		var requested := ""
		# host-latched condition from player.gd: CARRIED(0) or PLANTING(2)
		if mgr.bomb_carrier_peer == 1 and site_b.is_point_inside(p1.global_position) \
				and (poll_state == 0 or poll_state == 2):
			requested = "PLANT"
		if requested != "" and active_request != requested:
			active_request = requested
		elif requested == "" and active_request != "":
			mgr.request_stop_plant()
			stops_sent += 1
			active_request = ""

	check(stops_sent == 0, "no cancel sent while holding F through the plant (stops=%d)" % stops_sent)
	check(planted_seen, "plant completed within hold window")
	check(mgr.current_bomb_state == mgr.BombState.PLANTED,
		"bomb PLANTED after real-time hold (state=%d, action_time=%.2f, peer=%d)"
		% [mgr.current_bomb_state, mgr.current_action_time, mgr.current_action_peer])

	# 8. Halftime score swap check
	# Suppose attackers won 3 rounds, defenders won 1 before halftime (total 4)
	mgr.team_scores["attackers"] = 3
	mgr.team_scores["defenders"] = 1
	mgr.swap_halftime_teams()
	check(mgr.team_scores["attackers"] == 1, "halftime swapped scores: attackers now 1 (was defenders' 1)")
	check(mgr.team_scores["defenders"] == 3, "halftime swapped scores: defenders now 3 (was attackers' 3)")
	check(mgr.players_data[1]["team"] == "defenders", "player 1 flipped to defenders")

	print("--- plant flow test done: %d fails ---" % fails)
	quit(1 if fails > 0 else 0)
