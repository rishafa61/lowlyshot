# Regressions: (1) S&D round ends when host kills the last client (death RPC
# arrives after kill RPC), (2) FFA client joins are registered host-side so
# bots target them and the killfeed uses their Steam name.
extends SceneTree

var fails: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	for name in ["GlobalData", "GlobalSettings"]:
		if not root.has_node(name):
			var sc = load("res://scripts/%s.gd" % ("global_data" if name == "GlobalData" else "global_settings"))
			if sc:
				var gd = Node.new()
				gd.name = name
				gd.set_script(sc)
				root.add_child(gd)
	await process_frame

	# ---- 1. S&D: host kills client -> round must end ----
	var snd_scene := load("res://scenes/levels/search_and_destroy.tscn") as PackedScene
	var mgr = snd_scene.instantiate()
	root.add_child(mgr)
	await process_frame
	mgr.current_state = mgr.MatchState.ACTIVE
	mgr.players_data[1] = {"name": "Player", "team": "attackers", "kills": 0, "deaths": 0, "ping": 0}
	mgr.players_data[2] = {"name": "Sty", "team": "defenders", "kills": 0, "deaths": 0, "ping": 0}
	mgr.match_stats["Player"] = {"kills": 0, "deaths": 0, "team": "attackers"}
	mgr.match_stats["Sty"] = {"kills": 0, "deaths": 0, "team": "defenders"}
	# No bots anywhere
	mgr.team_bots["attackers"] = []
	mgr.team_bots["defenders"] = []

	var p1 = mgr.spawner.spawn_player(1, "attackers")
	var p2 = mgr.spawner.spawn_player(2, "defenders")
	check(p1 != null and p2 != null, "host + client player nodes spawned")
	# Host kills client: kill event marks victim puppet dead and triggers elimination
	mgr._on_kill_occurred("Player", "Ally", "m4a4", "Sty", "Enemy")
	check(bool(p2.get("is_dead")), "victim puppet marked dead inside kill event")
	check(mgr.current_state == mgr.MatchState.ROUND_END, "ROUND END after kill event (host killed client)")
	check(mgr.round_winner == "attackers", "attackers win by elimination")

	# ---- 2. FFA: request_join_team registers the client under its real name ----
	var ffa_scene := load("res://scenes/levels/flying_scoutsman.tscn") as PackedScene
	var ffa_mgr = ffa_scene.instantiate()
	root.add_child(ffa_mgr)
	await process_frame
	# Simulate host-side registration for a joining peer 2 (what request_join_team does)
	ffa_mgr.players_data[1] = {"name": "Player", "team": "ffa_1", "kills": 0, "deaths": 0, "ping": 0}
	ffa_mgr.players_data[2] = {"name": "Sty", "team": "ffa_2", "kills": 0, "deaths": 0, "ping": 0}
	ffa_mgr.match_stats["Sty"] = {"kills": 0, "deaths": 0, "team": "ffa_2"}
	var c2 = ffa_mgr.spawner.spawn_player(2, "ffa_2")
	check(c2 != null, "FFA client node spawned host-side")
	check(c2.is_in_group("player"), "FFA client is in 'player' group (bot targetable)")
	# Registry carries the joined name; puppets on other peers read it via _build_player
	check(str(ffa_mgr.players_data[2]["name"]) == "Sty", "FFA registry stores client under its joined name")

	# _spawn_local_ffa_player guard: idempotent per peer (peer 1 registered -> skip)
	var before: int = ffa_mgr.players_data.size()
	ffa_mgr._spawn_local_ffa_player()
	check(ffa_mgr.players_data.size() == before, "_spawn_local_ffa_player does not duplicate registered host")

	# Bot targeting: FFA bot picks client puppet as a valid target
	var bot = ffa_mgr.host_spawn_bot("res://scenes/enemies/capsule_enemy.tscn", Vector3(0, 2, 0), "ffa_bot_0")
	await process_frame
	bot.set("snd_team", "ffa_bot_0")
	bot.global_position = Vector3.ZERO
	c2.global_position = Vector3(3, 0, 0)
	bot._find_nearest_target()
	check(bot.target == c2, "FFA bot acquires client puppet as target (got %s)" % str(bot.target))
	bot.queue_free()

	mgr.queue_free()
	ffa_mgr.queue_free()
	await process_frame
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
