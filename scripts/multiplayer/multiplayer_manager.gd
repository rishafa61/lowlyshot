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
@export var team_size: int = 5 # 5v5
## Bots only exist on the host (they are not replicated yet), so friends' matches are bot-free by default.
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

func _ready() -> void:
	GlobalData.reset_bot_names()
	GlobalData.kill_occurred.connect(_on_kill_occurred)
	if GlobalData.is_networked():
		_setup_networking()
	if is_multiplayer_authority():
		timer_node.wait_time = 1.0
		timer_node.timeout.connect(_on_tick)
		timer_node.start()
		set_state(MatchState.WARMUP)
		call_deferred("_fill_bots")

func _fill_bots() -> void:
	# Ensure each team has `team_size` total members (players + bots)
	_balance_team_bots("attackers")
	_balance_team_bots("defenders")

func _balance_team_bots(team: String) -> void:
	# Count human players on this team
	var human_count = 0
	for pid in players_data.keys():
		if players_data[pid]["team"] == team:
			human_count += 1

	var needed_bots = max(0, team_size - human_count)
	if GlobalData.is_networked() and not bots_in_online_matches:
		needed_bots = 0
	var current_bot_list: Array = team_bots[team]

	# Clean up any dead/invalid bots from list
	var valid_bots: Array = []
	for b in current_bot_list:
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			valid_bots.append(b)
	team_bots[team] = valid_bots

	# If human joined, kick excess bots to make room
	while team_bots[team].size() > needed_bots:
		var excess_bot = team_bots[team].pop_back()
		if is_instance_valid(excess_bot):
			excess_bot.queue_free()

	# If bots missing, spawn until filled
	var ally_scene = preload("res://scenes/enemies/capsule_ally.tscn")
	var enemy_scene = preload("res://scenes/enemies/capsule_enemy.tscn")
	var scene_to_spawn = ally_scene if team == "attackers" else enemy_scene

	while team_bots[team].size() < needed_bots:
		var bot = scene_to_spawn.instantiate()
		var unique_name = GlobalData.get_random_bot_name()
		bot.bot_name = unique_name
		if not match_stats.has(unique_name):
			match_stats[unique_name] = {"kills": 0, "deaths": 0, "team": team}
		var sp = spawner.get_spawn_point(team)
		if sp:
			bot.position = sp.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		else:
			bot.position = Vector3(randf_range(-10, 10), 1, randf_range(-10, 10))
		add_child(bot)
		team_bots[team].append(bot)

func _on_kill_occurred(killer: String, killer_faction: String, _weapon: String, victim: String, victim_faction: String) -> void:
	if not is_multiplayer_authority():
		return

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

@rpc("any_peer", "call_local", "reliable")
func request_join_team(team: String) -> void:
	if not is_multiplayer_authority():
		return
	var peer = multiplayer.get_remote_sender_id()
	if peer == 0: peer = 1 # local
	
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
# Players are replicated with plain RPCs through this node (it exists on every peer),
# so nothing is ever sent to a peer that has not finished loading the arena.
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
	for pid in spawner.spawned_data.keys():
		net_spawn_player.rpc_id(peer, spawner.spawned_data[pid])

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
func send_local_player_state(pid: int, pos: Vector3, yaw: float, pitch: float) -> void:
	if multiplayer.is_server():
		for p in ready_peers:
			net_player_state.rpc_id(p, pid, pos, yaw, pitch)
	else:
		net_player_state.rpc_id(1, pid, pos, yaw, pitch)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_player_state(pid: int, pos: Vector3, yaw: float, pitch: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		if sender != pid:
			return # a client may only move its own player
		for p in ready_peers:
			if p != sender:
				net_player_state.rpc_id(p, pid, pos, yaw, pitch)
	elif sender != 1:
		return
	spawner.apply_remote_state(pid, pos, yaw, pitch)

## Client player died: host owns the scoreboard
@rpc("any_peer", "call_remote", "reliable")
func report_kill(killer: String, killer_faction: String, weapon: String, victim: String, victim_faction: String) -> void:
	if not multiplayer.is_server():
		return
	GlobalData.register_kill(killer, killer_faction, weapon, victim, victim_faction)
