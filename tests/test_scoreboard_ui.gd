# Verify scoreboard UI rendering in both Team and FFA modes
extends SceneTree

var fails: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var hud_sc = load("res://scripts/multiplayer/multiplayer_hud.gd")
	var hud = CanvasLayer.new()
	hud.set_script(hud_sc)
	root.add_child(hud)
	await process_frame

	check(hud.scoreboard != null, "Scoreboard node created")
	check(hud.scoreboard_list != null, "Scoreboard list container created")
	check(not hud.scoreboard.visible, "Scoreboard initially hidden")

	# Manager instance WITHOUT adding to tree: fields readable, no live sim
	var mgr = (load("res://scenes/levels/multiplayer_arena.tscn") as PackedScene).instantiate()
	mgr.set("mode_title", "TEST ARENA")
	mgr.set("team_scores", {"attackers": 12, "defenders": 8})
	mgr.set("ffa_target_kills", 0)
	mgr.set("match_stats", {
		"Player": {"kills": 5, "deaths": 2, "team": "attackers"},
		"Bravo": {"kills": 8, "deaths": 1, "team": "attackers"},
		"Charlie": {"kills": 3, "deaths": 4, "team": "defenders"},
		"Delta": {"kills": 7, "deaths": 3, "team": "defenders"},
		"World": {"kills": 0, "deaths": 0, "team": ""}
	})
	hud.manager = mgr

	hud.refresh_scoreboard()
	var cols = hud.scoreboard_list.get_children()
	check(cols.size() == 2, "Team mode rendered 2 team columns")
	# Attackers column: badge + column header + 2 rows (Player, Bravo)
	if cols.size() == 2:
		var atk_rows = cols[0].get_children()
		check(atk_rows.size() == 4, "Attackers column has badge + header + 2 stat rows")
	# FFA title updated
	check("12 : 8" in hud.scoreboard_title.text, "Team title shows score line")

	mgr.set("ffa_target_kills", 40)
	hud.refresh_scoreboard()
	await process_frame
	cols = hud.scoreboard_list.get_children()
	check(cols.size() == 1, "FFA mode rendered 1 single ranked column")
	if cols.size() == 1:
		var ffa_rows = cols[0].get_children()
		# header + 4 combatant rows (World filtered out)
		check(ffa_rows.size() == 5, "FFA column has header + 4 ranked rows (World filtered)")
	check("FIRST TO 40" in hud.scoreboard_title.text, "FFA title shows target")

	hud.queue_free()
	mgr.queue_free()
	await process_frame
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
