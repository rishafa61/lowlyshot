# Scoreboard & kill attribution test — headless
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
	# 1. Test hud _is_combatant_name filter
	var hud_script = load("res://scripts/multiplayer/multiplayer_hud.gd")
	var hud = CanvasLayer.new()
	hud.set_script(hud_script)
	check(hud._is_combatant_name("Player"), "Player is combatant")
	check(hud._is_combatant_name("Bravo"), "Bot Bravo is combatant")
	check(not hud._is_combatant_name("World"), "World rejected")
	check(not hud._is_combatant_name("Sentry Turret"), "Sentry Turret rejected")
	check(not hud._is_combatant_name("Auto-Turret"), "Auto-Turret rejected")
	check(not hud._is_combatant_name("CH-47 Chinook"), "Chinook rejected")
	check(not hud._is_combatant_name("Humvee"), "Humvee rejected")
	check(not hud._is_combatant_name(""), "Empty string rejected")
	hud.queue_free()

	# 2. Test manager _on_kill_occurred ignores non-tracked combatants in match_stats
	var mgr_scene = load("res://scenes/levels/multiplayer_arena.tscn")
	var mgr = mgr_scene.instantiate()
	root.add_child(mgr)
	await process_frame

	mgr.match_stats.clear()
	mgr.match_stats["Player"] = {"kills": 0, "deaths": 0, "team": "attackers"}
	mgr.match_stats["Alpha"] = {"kills": 0, "deaths": 0, "team": "defenders"}

	# Kill by World -> must NOT create a "World" entry in match_stats
	mgr._on_kill_occurred("World", "World", "Fall", "Alpha", "Enemy")
	check(not mgr.match_stats.has("World"), "World never inserted into match_stats")
	check(mgr.match_stats["Alpha"]["deaths"] == 1, "Alpha death counted")

	# Kill of a Sentry Turret -> must NOT create a "Sentry Turret" entry
	mgr._on_kill_occurred("Player", "Ally", "M4A4", "Sentry Turret", "Enemy")
	check(not mgr.match_stats.has("Sentry Turret"), "Sentry Turret never inserted into match_stats")
	check(mgr.match_stats["Player"]["kills"] == 1, "Player credited with kill")

	# 3. Test airstrike missile assigns attribution
	var missile = load("res://scenes/weapons/skills/airstrike_missile.tscn").instantiate()
	missile.attacker_name = "Player"
	missile.attacker_faction = "Ally"
	check(missile.attacker_name == "Player", "Missile carries attacker_name")
	missile.queue_free()

	# 4. Test grenade carries owner_name
	var grenade = load("res://scenes/weapons/utilities/grenade_projectile.tscn").instantiate()
	grenade.owner_name = "Player"
	grenade.attacker_faction = "Ally"
	check(grenade.owner_name == "Player", "Grenade carries owner_name")
	grenade.queue_free()

	# 5. Respawn keeps registry name — player._ready() re-resolves the name
	# from SteamSync ("RioTest"), which silently dropped all post-respawn
	# kills: killer string never matched match_stats keys ("Player").
	var ss_stub = GDScript.new()
	ss_stub.source_code = "extends Node\nvar persona_name: String = \"RioTest\"\n"
	ss_stub.reload()
	var ss_node = Node.new()
	ss_node.name = "SteamSync"
	ss_node.set_script(ss_stub)
	root.add_child(ss_node)
	mgr.players_data[1] = {"name": "Player", "team": "attackers", "kills": 0, "deaths": 0, "ping": 0}
	var respawnee = mgr.spawner.spawn_player(1, "attackers")
	check(respawnee != null and str(respawnee.get("player_name")) == "Player",
		"respawned player keeps registry name (not Steam persona)")
	if respawnee:
		respawnee.queue_free()
	ss_node.queue_free()

	mgr.queue_free()
	await process_frame

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
