extends SceneTree
## Regression checks for the intermission freeze + match-end flow.
func _initialize() -> void:
	var fails := 0
	var check := func(cond: bool, label: String) -> void:
		if cond:
			print("PASS: " + label)
		else:
			printerr("FAIL: " + label)
			fails += 1

	var mgr_script := load("res://scripts/multiplayer/search_and_destroy_manager.gd")
	var mgr = mgr_script.new()
	root.add_child(mgr)
	mgr._ready()

	# 1. Freeze flag follows state — freeze ONLY during warmup intermission
	mgr.set_state(mgr.MatchState.WARMUP)
	check.call(mgr.players_frozen == true, "WARMUP freezes players")
	mgr.set_state(mgr.MatchState.ACTIVE)
	check.call(mgr.players_frozen == false, "ACTIVE unfreezes players")
	mgr.set_state(mgr.MatchState.ROUND_END)
	check.call(mgr.players_frozen == false, "ROUND_END unfreezes players")
	mgr.set_state(mgr.MatchState.MATCH_END)
	check.call(mgr.players_frozen == false, "MATCH_END unfreezes players")

	# 2. sync_state (client path) also updates the freeze flag
	mgr.sync_state(mgr.MatchState.WARMUP, 1, 5)
	check.call(mgr.players_frozen == true, "sync_state(WARMUP) freezes")
	mgr.sync_state(mgr.MatchState.ACTIVE, 1, 120)
	check.call(mgr.players_frozen == false, "sync_state(ACTIVE) unfreezes")

	# 3. Bomb carrier death drop RPC exists (client path)
	check.call(mgr.has_method("request_drop_bomb"), "request_drop_bomb RPC exists")
	check.call(mgr.has_method("drop_bomb"), "drop_bomb exists")

	# 4. Match end returns to lobby via RPC
	check.call(mgr.has_method("net_return_to_lobby"), "net_return_to_lobby RPC exists")
	check.call(mgr.has_method("_advance_after_match_end"), "_advance_after_match_end exists")

	# 5. Bomb tick RPC exists
	check.call(mgr.has_method("net_bomb_tick"), "net_bomb_tick RPC exists")

	# 6. Synthesized SFX cues registered
	var sfx = root.get_node_or_null("/root/Sfx")
	if sfx:
		check.call(sfx.has("bomb_tick"), "bomb_tick cue exists")
		check.call(sfx.has("round_win"), "round_win cue exists")
		check.call(sfx.has("round_loss"), "round_loss cue exists")
		check.call(sfx.has_method("oneshot2d"), "oneshot2d exists")
	else:
		check.call(false, "Sfx autoload present")

	mgr.free()
	print("--- freeze/match-end checks done: %d fails ---" % fails)
	quit(1 if fails > 0 else 0)
