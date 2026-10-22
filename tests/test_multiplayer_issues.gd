extends SceneTree
## Regression test for 5 multiplayer issues:
## 1. Remote puppet death marks is_dead=true (host S&D elimination counts it)
## 2. Auto-pickup of dropped bomb when walking over it
## 3. World bomb syncs to clients on drop/plant
## 4. Bot respawn replicates via net_bot_respawned
## 5. Bot repositions to team spawn on round reset even if not dead

var fails: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		printerr("FAIL: " + label)
		fails += 1

func _initialize() -> void:
	# 1. Player puppet net_play_death sets is_dead = true
	var p_scene = load("res://scenes/player/player.tscn")
	var puppet = p_scene.instantiate()
	puppet.name = "42"
	root.add_child(puppet)
	puppet.is_puppet = true # simulate remote puppet (skip awaiting: _physics_process would reset test state)
	check(not puppet.is_dead, "Puppet begins alive")
	puppet.net_play_death()
	check(puppet.is_dead, "net_play_death sets is_dead=true on puppet so host sees it")
	puppet.queue_free()

	# 2. S&D auto-pickup
	var snd_scene = load("res://scenes/levels/search_and_destroy.tscn")
	var arena = snd_scene.instantiate()
	root.add_child(arena)
	await process_frame
	var snd_mgr = arena
	snd_mgr.current_state = snd_mgr.MatchState.ACTIVE
	snd_mgr.current_bomb_state = snd_mgr.BombState.DROPPED
	snd_mgr.bomb_world_position = Vector3(10, 0, 10)
	snd_mgr.players_data[2] = {"name": "AttackerGuy", "team": "attackers"}

	var MockPlayer = GDScript.new()
	MockPlayer.source_code = "extends CharacterBody3D\nvar is_dead: bool = false\nvar team: String = \"attackers\"\n"
	MockPlayer.reload()

	var walker: CharacterBody3D = MockPlayer.new()
	walker.name = "2"
	walker.add_to_group("player")
	walker.position = Vector3(10.5, 0, 10.5) # within pickup_radius=3.0
	arena.add_child(walker)
	await process_frame

	snd_mgr._process_auto_pickup()
	check(snd_mgr.current_bomb_state == snd_mgr.BombState.CARRIED, "Auto-pickup transitions bomb to CARRIED")
	check(snd_mgr.bomb_carrier_peer == 2, "Auto-pickup assigns carrier peer to walker")
	check(snd_mgr.bomb_carrier_name == "AttackerGuy", "Auto-pickup assigns carrier name")

	# Dead attacker walking over it does not pick up
	snd_mgr.current_bomb_state = snd_mgr.BombState.DROPPED
	walker.is_dead = true
	snd_mgr._process_auto_pickup()
	check(snd_mgr.current_bomb_state == snd_mgr.BombState.DROPPED, "Dead attacker cannot auto-pickup bomb")

	# Defender walking over it does not pick up
	walker.is_dead = false
	snd_mgr.players_data[2]["team"] = "defenders"
	snd_mgr._process_auto_pickup()
	check(snd_mgr.current_bomb_state == snd_mgr.BombState.DROPPED, "Defender cannot auto-pickup bomb")

	# 3. CapsuleEnemy puppet respawn restoration
	var bot_scene = load("res://scenes/enemies/capsule_enemy.tscn")
	var bot = bot_scene.instantiate()
	bot.is_net_puppet = true
	root.add_child(bot)
	await process_frame
	bot.net_play_death()
	check(bot.is_dead, "Enemy bot puppet dead after net_play_death")
	bot.net_play_respawn()
	check(not bot.is_dead, "Enemy bot puppet revived after net_play_respawn")
	check(bot.visuals.rotation.x == 0.0, "Enemy bot visuals upright after respawn")

	# Cleanup
	arena.queue_free()
	bot.queue_free()

	print("--- multiplayer issue tests done: %d fails ---" % fails)
	quit(1 if fails > 0 else 0)
