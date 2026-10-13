extends Node
class_name MultiplayerManager

signal match_state_changed(state: int)
signal time_tick(time_left: int)
signal players_data_synced(data: Dictionary, scores: Dictionary, stats: Dictionary)

enum MatchState { WAITING, WARMUP, ACTIVE, ROUND_END, MATCH_END }

@export var max_rounds: int = 1
@export var warmup_time: int = 5
@export var round_time: int = 600 # 10 minute deathmatch
@export var target_kills: int = 30 # first to 30 kills wins
@export var team_size: int = 5 # 5v5 (players + bots)
## Bots backfill empty slots in online matches too.
@export var bots_in_online_matches: bool = false

# { "name": kills, "deaths" } — covers players AND bots
var match_stats: Dictionary = {}
var used_match_names: Array[String] = []

var current_state: MatchState = MatchState.WAITING
var current_round: int = 1
var timer: int = 0
var team_scores: Dictionary = {"attackers": 0, "defenders": 0}
var team_bots: Dictionary = {"attackers": [], "defenders": []}

@onready var spawner: PlayerSpawner = $PlayerSpawner
@onready var timer_node: Timer = $Timer

# Scoreboard data: { peer_id: { "name": String, "team": String, "kills": 0, "deaths": 0, "ping": 0 } }
var players_data: Dictionary = {}

# ---------------- Bot replication state ----------------
var _next_bot_net_id: int = 100
var _bots_kicked_by_admin: bool = false
# host: net_id -> bot instance | client: net_id -> puppet bot instance
var net_bots: Dictionary = {}
var _bot_sync_timer: float = 0.0
const BOT_SYNC_INTERVAL: float = 0.1 # 10 Hz

func _ready() -> void:
	GlobalData.reset_bot_names()
	GlobalData.kill_occurred.connect(_on_kill_occurred)
	if GlobalData.is_networked():
		_setup_networking()
	# Host's menu toggle decides bot backfill — read unconditionally so a
	# network flag race can never fall back to the on-by-default export value.
	bots_in_online_matches = GlobalSettings.online_bots_enabled
	if is_multiplayer_authority():
		timer_node.wait_time = 1.0
		timer_node.timeout.connect(_on_tick)
		timer_node.start()
		set_state(MatchState.WARMUP)
		call_deferred("_fill_bots")

func _process(delta: float) -> void:
	if not is_multiplayer_authority() or not GlobalData.is_networked():
		return
	if ready_peers.size() == 0:
		return
	_bot_sync_timer += delta
	if _bot_sync_timer >= BOT_SYNC_INTERVAL:
		_bot_sync_timer = 0.0
		_broadcast_bot_states()

func _fill_bots() -> void:
	if _bots_kicked_by_admin:
		return
	# Ensure each team has `team_size` total members (players + bots)
	_balance_team_bots("attackers")
	_balance_team_bots("defenders")

func _balance_team_bots(team: String) -> void:
	# Count human players on this team
	var human_count = 0
	for pid in players_data.keys():
		if players_data[pid].get("team", "") == team:
			human_count += 1

	var needed_bots = max(0, team_size - human_count)
	if not bots_in_online_matches:
		needed_bots = 0

	# Reconcile against the REAL host-side bots in the tree (team fill AND
	# console spawned) so a team can never exceed team_size total members.
	var group := "ally" if team == "attackers" else "enemy"
	var live_bots: Array = []
	for b in get_tree().get_nodes_in_group(group):
		if is_instance_valid(b) and not b.is_queued_for_deletion() \
				and b is CharacterBody3D and "bot_name" in b and not b.get("is_net_puppet"):
			live_bots.append(b)
	team_bots[team] = live_bots

	# Kick excess bots to make room for humans
	var kicked := false
	while team_bots[team].size() > needed_bots:
		var excess_bot = team_bots[team].pop_back()
		if is_instance_valid(excess_bot):
			match_stats.erase(excess_bot.bot_name)
			kicked = true
			_despawn_host_bot(excess_bot)

	# Spawn until the team is filled
	var ally_scene = "res://scenes/enemies/capsule_ally.tscn"
	var enemy_scene = "res://scenes/enemies/capsule_enemy.tscn"
	var scene_path = ally_scene if team == "attackers" else enemy_scene

	while team_bots[team].size() < needed_bots:
		var sp = spawner.get_spawn_point(team)
		var spawn_pos = Vector3.ZERO
		if sp:
			spawn_pos = sp.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		else:
			spawn_pos = Vector3(randf_range(-10, 10), 1, randf_range(-10, 10))
		var bot = host_spawn_bot(scene_path, spawn_pos, team)
		if bot:
			team_bots[team].append(bot)

	if kicked:
		_sync_match_data()

## Spawns a bot on host and replicates to all ready clients
func host_spawn_bot(scene_path: String, pos: Vector3, team: String, custom_name: String = "") -> CharacterBody3D:
	if not is_multiplayer_authority():
		return null
	var scene = load(scene_path) as PackedScene
	if not scene:
		return null
	var bot = scene.instantiate() as CharacterBody3D
	var b_name = custom_name if custom_name != "" else GlobalData.get_random_bot_name()
	bot.bot_name = b_name
	bot.position = pos
	_next_bot_net_id += 1
	var bot_id = _next_bot_net_id
	bot.set("net_id", bot_id)
	bot.set("is_net_puppet", false)
	net_bots[bot_id] = bot
	if not match_stats.has(b_name):
		match_stats[b_name] = {"kills": 0, "deaths": 0, "team": team}
	add_child(bot)

	var weapon_id = ""
	if bot.get("equipped_primary") and bot.equipped_primary.has("id"):
		weapon_id = bot.equipped_primary["id"]

	if GlobalData.is_networked():
		for p in ready_peers:
			net_spawn_bot.rpc_id(p, bot_id, scene_path, pos, bot.rotation.y, team, b_name, weapon_id)
	return bot

func _despawn_host_bot(bot: CharacterBody3D) -> void:
	var b_id = bot.get("net_id")
	if b_id != null and net_bots.has(b_id):
		net_bots.erase(b_id)
		if GlobalData.is_networked():
			for p in ready_peers:
				net_despawn_bot.rpc_id(p, b_id)
	bot.queue_free()

## Despawn every tracked bot (team fill + console spawned) on host AND clients
func host_kick_bots() -> int:
	_bots_kicked_by_admin = true
	var removed := 0
	for b_id in net_bots.keys():
		var b = net_bots[b_id]
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			match_stats.erase(b.bot_name)
			_despawn_host_bot(b)
			removed += 1
	net_bots.clear()
	for team in team_bots:
		team_bots[team] = []
	if removed > 0:
		_sync_match_data()
	return removed

func _broadcast_bot_states() -> void:
	var ids: Array = []
	var positions: Array = []
	var yaws: Array = []
	for b_id in net_bots.keys():
		var b = net_bots[b_id]
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			ids.append(b_id)
			positions.append(b.global_position)
			yaws.append(b.rotation.y)
	if ids.size() > 0:
		for p in ready_peers:
			net_bots_state.rpc_id(p, ids, positions, yaws)

@rpc("authority", "call_remote", "reliable")
func net_spawn_bot(b_id: int, scene_path: String, pos: Vector3, yaw: float, team: String, b_name: String, weapon_id: String) -> void:
	if multiplayer.is_server():
		return
	if net_bots.has(b_id) and is_instance_valid(net_bots[b_id]):
		return
	var scene = load(scene_path) as PackedScene
	if not scene:
		return
	var bot = scene.instantiate() as CharacterBody3D
	bot.set("net_id", b_id)
	bot.set("is_net_puppet", true)
	bot.set("bot_name", b_name)
	bot.set("net_weapon_id", weapon_id)
	bot.position = pos
	bot.rotation.y = yaw
	if team == "attackers":
		bot.add_to_group("ally")
	else:
		bot.add_to_group("enemy")
	add_child(bot)
	net_bots[b_id] = bot

@rpc("authority", "call_remote", "reliable")
func net_despawn_bot(b_id: int) -> void:
	if net_bots.has(b_id):
		var b = net_bots[b_id]
		if is_instance_valid(b):
			b.queue_free()
		net_bots.erase(b_id)

@rpc("authority", "call_remote", "unreliable")
func net_bots_state(ids: Array, positions: Array, yaws: Array) -> void:
	for i in ids.size():
		var b_id = ids[i]
		if net_bots.has(b_id):
			var b = net_bots[b_id]
			if is_instance_valid(b) and b.has_method("net_set_target"):
				b.net_set_target(positions[i], yaws[i])

## Client routed bot damage to host authoritative bot
@rpc("any_peer", "call_remote", "reliable")
func report_bot_damage(b_id: int, dmg: float, part: String, attacker: String, weapon: String, faction: String) -> void:
	if not multiplayer.is_server():
		return
	if net_bots.has(b_id):
		var b = net_bots[b_id]
		if is_instance_valid(b) and b.has_method("receive_damage"):
			b.receive_damage(dmg, part, attacker, weapon, faction)

## Replicate bot death visual to all clients
func broadcast_bot_died(b_id: int) -> void:
	if GlobalData.is_networked():
		for p in ready_peers:
			net_bot_died.rpc_id(p, b_id)

@rpc("authority", "call_remote", "reliable")
func net_bot_died(b_id: int) -> void:
	if net_bots.has(b_id):
		var b = net_bots[b_id]
		if is_instance_valid(b) and b.has_method("net_play_death"):
			b.net_play_death()

func _on_kill_occurred(killer: String, killer_faction: String, weapon: String, victim: String, victim_faction: String) -> void:
	# Host is the authority on scores and stats
	if is_multiplayer_authority():
		# Determine killer team
		var killer_team = ""
		if match_stats.has(killer) and match_stats[killer].get("team", "") != "":
			killer_team = match_stats[killer]["team"]
		else:
			killer_team = "defenders" if killer_faction.to_lower() in ["enemy", "defenders"] else "attackers"

		# Record stats for killer (player or bot)
		if not match_stats.has(killer):
			match_stats[killer] = {"kills": 0, "deaths": 0, "team": killer_team}
		if killer != "" and killer != "World":
			match_stats[killer]["kills"] += 1

		# Determine victim team
		var victim_team = ""
		if match_stats.has(victim) and match_stats[victim].get("team", "") != "":
			victim_team = match_stats[victim]["team"]
		else:
			victim_team = "defenders" if victim_faction.to_lower() in ["enemy", "defenders"] else "attackers"

		# Record stats for victim (player or bot)
		if not match_stats.has(victim):
			match_stats[victim] = {"kills": 0, "deaths": 0, "team": victim_team}
		if victim != "" and victim != "World":
			match_stats[victim]["deaths"] += 1

		# Team scores: EVERY entity (bot, player, turret) awards a score to their team
		if killer != "" and killer != "World" and team_scores.has(killer_team):
			team_scores[killer_team] += 1
			if team_scores[killer_team] >= target_kills:
				set_state(MatchState.MATCH_END)

		# Update players_data mirror for backward-compat with RPC
		for peer_id in players_data.keys():
			var p = players_data[peer_id]
			if p["name"] == killer or str(peer_id) == killer or (killer == "Player" and peer_id == 1):
				p["kills"] = match_stats[killer]["kills"]
			if p["name"] == victim or str(peer_id) == victim or (victim == "Player" and peer_id == 1):
				p["deaths"] = match_stats[victim]["deaths"]
				# Respawn on death after delay
				get_tree().create_timer(3.0).timeout.connect(func():
					if is_instance_valid(spawner) and current_state == MatchState.ACTIVE:
						spawner.despawn_player(peer_id)
						spawner.spawn_player(peer_id, p["team"])
				)

		_sync_match_data()

		# Broadcast kill event to all ready clients so everyone sees the killfeed
		if GlobalData.is_networked():
			for p in ready_peers:
				net_kill_feed.rpc_id(p, killer, killer_faction, weapon, victim, victim_faction)

@rpc("authority", "call_remote", "reliable")
func net_kill_feed(killer: String, killer_faction: String, weapon: String, victim: String, victim_faction: String) -> void:
	GlobalData.kill_occurred.emit(killer, killer_faction, weapon, victim, victim_faction)

func _sync_match_data() -> void:
	if multiplayer.has_multiplayer_peer():
		sync_players_data.rpc(players_data, team_scores, match_stats)
	else:
		sync_players_data(players_data, team_scores, match_stats)

func set_state(new_state: MatchState) -> void:
	current_state = new_state
	match current_state:
		MatchState.WAITING: timer = 999
		MatchState.WARMUP: timer = warmup_time
		MatchState.ACTIVE: timer = round_time
		MatchState.ROUND_END: timer = 5
		MatchState.MATCH_END: timer = 10
	if multiplayer.has_multiplayer_peer():
		sync_state.rpc(current_state, current_round, timer)
	else:
		sync_state(current_state, current_round, timer)

@rpc("authority", "call_local", "reliable")
func sync_state(state: MatchState, round_num: int, time_left: int) -> void:
	current_state = state
	current_round = round_num
	timer = time_left
	match_state_changed.emit(current_state)
	time_tick.emit(timer)

func _on_tick() -> void:
	if timer > 0:
		timer -= 1
		if multiplayer.has_multiplayer_peer():
			sync_time.rpc(timer)
		else:
			sync_time(timer)
		
	if timer <= 0:
		match current_state:
			MatchState.WARMUP: set_state(MatchState.ACTIVE)
			MatchState.ACTIVE: set_state(MatchState.ROUND_END)
			MatchState.ROUND_END:
				if current_round >= max_rounds:
					current_round = max_rounds
					set_state(MatchState.MATCH_END)
				else:
					current_round += 1
					set_state(MatchState.WARMUP)
			MatchState.MATCH_END: pass

@rpc("authority", "call_local", "unreliable")
func sync_time(time_left: int) -> void:
	timer = time_left
	time_tick.emit(timer)

func request_join_team_local(team: String) -> void:
	request_join_team(team)

## Server truth: can this peer still fit on the team (5 humans max)?
func can_join_team(team: String) -> bool:
	var humans := 0
	for pid in players_data:
		if players_data[pid].get("team", "") == team:
			humans += 1
	return humans < team_size

@rpc("any_peer", "call_local", "reliable")
func request_join_team(team: String) -> void:
	if not is_multiplayer_authority():
		return
	var peer = multiplayer.get_remote_sender_id()
	if peer == 0: peer = 1 # local

	# Authority-side 5v5 human cap: spoofed/full team bounces to other side.
	# Re-picking same team counts self as occupied slot, not a new member.
	if players_data.has(peer) and players_data[peer].get("team", "") != team and not can_join_team(team):
		team = "defenders" if team == "attackers" else "attackers"
	
	if not players_data.has(peer):
		players_data[peer] = { "name": str(peer), "team": team, "kills": 0, "deaths": 0, "ping": 0 }
	else:
		players_data[peer]["team"] = team
	
	var p_name = "Player" if peer == 1 else str(peer)
	if not match_stats.has(p_name):
		match_stats[p_name] = {"kills": 0, "deaths": 0, "team": team}
	else:
		match_stats[p_name]["team"] = team

	_sync_match_data()
	
	if is_multiplayer_authority():
		spawner.despawn_player(peer)
		spawner.spawn_player(peer, team)
		_fill_bots()

@rpc("authority", "call_local", "reliable")
func sync_players_data(data: Dictionary, scores: Dictionary = {"attackers": 0, "defenders": 0}, stats: Dictionary = {}) -> void:
	players_data = data
	team_scores = scores
	match_stats = stats
	players_data_synced.emit(data, scores, stats)


# ---------------- Online play (host <-> clients) ----------------
var ready_peers: Array[int] = []

func _setup_networking() -> void:
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_left)
	else:
		multiplayer.server_disconnected.connect(_on_server_lost)
		if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			client_ready.rpc_id(1)
		else:
			multiplayer.connected_to_server.connect(func(): client_ready.rpc_id(1))

func _on_server_lost() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_peer_left(peer: int) -> void:
	ready_peers.erase(peer)
	spawner.despawn_player(peer)
	players_data.erase(peer)
	_sync_match_data()
	_fill_bots()

## Client -> host: "my arena is loaded, send me everything"
@rpc("any_peer", "call_remote", "reliable")
func client_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer in ready_peers:
		return
	ready_peers.append(peer)
	sync_state.rpc_id(peer, current_state, current_round, timer)
	sync_players_data.rpc_id(peer, players_data, team_scores, match_stats)
	# Replicate all active players
	for pid in spawner.spawned_data.keys():
		net_spawn_player.rpc_id(peer, spawner.spawned_data[pid])
	# Replicate all active bots
	for b_id in net_bots.keys():
		var b = net_bots[b_id]
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			var scene_path = "res://scenes/enemies/capsule_ally.tscn" if b.is_in_group("ally") else "res://scenes/enemies/capsule_enemy.tscn"
			var team = "attackers" if b.is_in_group("ally") else "defenders"
			var weapon_id = ""
			if b.get("equipped_primary") and b.equipped_primary.has("id"):
				weapon_id = b.equipped_primary["id"]
			net_spawn_bot.rpc_id(peer, b_id, scene_path, b.global_position, b.rotation.y, team, b.bot_name, weapon_id)
	# New peer may have been added to players_data just before readying:
	# rebalance so bot counts match humans (max 5v5 = 10 combatants).
	_fill_bots()

func replicate_spawn(data: Dictionary) -> void:
	for p in ready_peers:
		net_spawn_player.rpc_id(p, data)

func replicate_despawn(peer_id: int) -> void:
	for p in ready_peers:
		net_despawn_player.rpc_id(p, peer_id)

@rpc("authority", "call_remote", "reliable")
func net_spawn_player(data: Dictionary) -> void:
	spawner.build_replica(data)

@rpc("authority", "call_remote", "reliable")
func net_despawn_player(peer_id: int) -> void:
	spawner.remove_replica(peer_id)

## Called every few physics frames by the LOCAL player of this peer
func send_local_player_state(pid: int, pos: Vector3, yaw: float, pitch: float, weapon_path: String = "") -> void:
	if multiplayer.is_server():
		for p in ready_peers:
			net_player_state.rpc_id(p, pid, pos, yaw, pitch, weapon_path)
	else:
		net_player_state.rpc_id(1, pid, pos, yaw, pitch, weapon_path)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_player_state(pid: int, pos: Vector3, yaw: float, pitch: float, weapon_path: String = "") -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		if sender != pid:
			return # a client may only move its own player
		for p in ready_peers:
			if p != sender:
				net_player_state.rpc_id(p, pid, pos, yaw, pitch, weapon_path)
	elif sender != 1:
		return
	spawner.apply_remote_state(pid, pos, yaw, pitch)
	var container = spawner._get_container()
	var p = container.get_node_or_null(str(pid))
	if p and p.has_method("net_set_weapon"):
		p.net_set_weapon(weapon_path)

## Player death animation broadcast
func notify_player_death(pid: int) -> void:
	if multiplayer.is_server():
		_broadcast_player_death(pid)
	else:
		report_player_death.rpc_id(1, pid)

@rpc("any_peer", "call_remote", "reliable")
func report_player_death(pid: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != pid:
		return
	_broadcast_player_death(pid)

func _broadcast_player_death(pid: int) -> void:
	net_player_died(pid)
	for p in ready_peers:
		net_player_died.rpc_id(p, pid)

@rpc("authority", "call_remote", "reliable")
func net_player_died(pid: int) -> void:
	var container = spawner._get_container()
	var p = container.get_node_or_null(str(pid))
	if p and p.has_method("net_play_death"):
		p.net_play_death()

## Client player died: host owns the scoreboard
@rpc("any_peer", "call_remote", "reliable")
func report_kill(killer: String, killer_faction: String, weapon: String, victim: String, victim_faction: String) -> void:
	if not multiplayer.is_server():
		return
	GlobalData.register_kill(killer, killer_faction, weapon, victim, victim_faction)

# ---------------- Utility / Skill Replication ----------------
## Called by whichever peer spawned a utility (sentry, flashbang, grenade, airstrike, shockwave, sonar)
func spawn_utility_net(scene_path: String, pos: Vector3, dir: Vector3 = Vector3.FORWARD, extra_data: Dictionary = {}) -> void:
	if not GlobalData.is_networked():
		return
	var owner_peer = multiplayer.get_unique_id()
	if multiplayer.is_server():
		for p in ready_peers:
			net_spawn_utility.rpc_id(p, scene_path, pos, dir, extra_data, owner_peer)
	else:
		relay_utility_to_host.rpc_id(1, scene_path, pos, dir, extra_data)

@rpc("any_peer", "call_remote", "reliable")
func relay_utility_to_host(scene_path: String, pos: Vector3, dir: Vector3, extra_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	# Spawn replica locally on host
	_instantiate_utility_replica(scene_path, pos, dir, extra_data, sender)
	# Relay to other clients
	for p in ready_peers:
		if p != sender:
			net_spawn_utility.rpc_id(p, scene_path, pos, dir, extra_data, sender)

@rpc("authority", "call_remote", "reliable")
func net_spawn_utility(scene_path: String, pos: Vector3, dir: Vector3, extra_data: Dictionary, owner_peer: int) -> void:
	if owner_peer == multiplayer.get_unique_id():
		return
	_instantiate_utility_replica(scene_path, pos, dir, extra_data, owner_peer)

func _instantiate_utility_replica(scene_path: String, pos: Vector3, dir: Vector3, extra_data: Dictionary, _owner_peer: int) -> void:
	var sc = load(scene_path) as PackedScene
	if not sc:
		return
	var node = sc.instantiate()
	node.set("is_net_replica", true)
	if extra_data.has("fuse") and "fuse" in node:
		node.fuse = float(extra_data["fuse"])
	if extra_data.has("faction") and "faction" in node:
		node.faction = extra_data["faction"]
	if extra_data.has("owner_name") and "owner_name" in node:
		node.owner_name = extra_data["owner_name"]
	get_tree().root.add_child(node)
	node.global_position = pos
	if "direction" in node:
		node.direction = dir
	if node is RigidBody3D and extra_data.has("impulse"):
		node.apply_impulse(extra_data["impulse"])
