extends SceneTree
## Regression test for killfeed viewer-relative coloring:
## self = yellow, same team = blue, other team = red

var fails: int = 0
func check(cond: bool, label: String) -> void:
	if cond: print("PASS: " + label)
	else:
		printerr("FAIL: " + label)
		fails += 1

func _initialize() -> void:
	var hud_scene = load("res://scenes/ui/hud.tscn")
	var hud = hud_scene.instantiate()

	# Mock local player (viewer) — peer 1, attackers, name "Player"
	var MockPlayer = GDScript.new()
	MockPlayer.source_code = "extends Node\nvar player_name: String = \"Player\"\n"
	MockPlayer.reload()
	var mock_player = MockPlayer.new()
	mock_player.add_child(hud)
	root.add_child(mock_player)
	await process_frame

	# Mock manager with team data, registered in the group HUD scans
	var MockMgr = GDScript.new()
	MockMgr.source_code = """
extends Node
var match_stats: Dictionary = {
	"Player": {"team": "attackers"},
	"Friend": {"team": "defenders"},
	"AllyBot": {"team": "attackers"},
	"EnemyBot": {"team": "defenders"}
}
var players_data: Dictionary = { 1: {"team": "attackers"} }
"""
	MockMgr.reload()
	var mgr = MockMgr.new()
	mgr.add_to_group("multiplayer_manager")
	root.add_child(mgr)
	await process_frame

	# 1. Self kill: killer "Player" -> yellow even though faction string says "Ally"
	hud.add_killfeed_entry("Player", "Ally", "ak47", "EnemyBot", "Enemy")
	var entries = hud.killfeed_container.get_children()
	var lbl: RichTextLabel = entries[0].get_child(0)
	check(lbl.text.contains("#ffeb3b]Player"), "Self is yellow on own killfeed")
	check(lbl.text.contains("#ef4444]EnemyBot"), "Enemy-team victim is red")

	# 2. Same-team bot kill: faction says "Enemy" but team says attackers -> blue
	hud.add_killfeed_entry("AllyBot", "Enemy", "m700", "EnemyBot", "Enemy")
	entries = hud.killfeed_container.get_children()
	lbl = entries[1].get_child(0)
	check(lbl.text.contains("#38bdf8]AllyBot"), "Same-team killer is blue regardless of faction string")

	# 3. Other-team human: faction says "Ally" but team says defenders -> red
	hud.add_killfeed_entry("Friend", "Ally", "glock", "AllyBot", "Ally")
	entries = hud.killfeed_container.get_children()
	lbl = entries[2].get_child(0)
	check(lbl.text.contains("#ef4444]Friend"), "Enemy-team killer is red regardless of faction string")
	check(lbl.text.contains("#38bdf8]AllyBot"), "Same-team victim is blue")

	# 4. Unknown name (not in match_stats): falls back to faction colors
	hud.add_killfeed_entry("StrayTurret", "Ally", "turret", "RandomGuy", "Enemy")
	entries = hud.killfeed_container.get_children()
	lbl = entries[3].get_child(0)
	check(lbl.text.contains("#38bdf8]StrayTurret"), "Unknown killer falls back to faction color")

	mock_player.queue_free()
	mgr.queue_free()
	await process_frame
	print("--- killfeed color tests done: %d fails ---" % fails)
	quit(1 if fails > 0 else 0)
