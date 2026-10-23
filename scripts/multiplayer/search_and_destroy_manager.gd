class_name SearchAndDestroyManager
extends MultiplayerManager

## Search & Destroy match manager.
## Host-authoritative round, elimination, and bomb plant/defuse logic.

signal round_ended(winner: String, reason: String)
signal bomb_state_synced(state: String, site_id: String, carrier_name: String, time_left: int)
signal bomb_action_progress(action_type: String, peer: int, progress: float)

enum BombState {
	CARRIED,
	DROPPED,
	PLANTING,
	PLANTED,
	DEFUSING,
	DEFUSED,
	DETONATED
}

# Configurable gameplay exports
@export_group("Search & Destroy Settings")
@export var round_duration: int = 120
@export var plant_duration: float = 4.0
@export var defuse_duration: float = 5.0
@export var bomb_countdown: int = 40
@export var rounds_to_win: int = 5
@export var halftime_round: int = 4
@export var plant_radius: float = 6.0
@export var defuse_radius: float = 3.5
@export var pickup_radius: float = 3.0

# Gameplay state
var disable_auto_respawn: bool = true
var is_search_and_destroy: bool = true
var current_bomb_state: BombState = BombState.CARRIED
var bomb_carrier_peer: int = 0
var bomb_carrier_name: String = ""
var planted_site_id: String = ""
var bomb_world_position: Vector3 = Vector3.ZERO
var bomb_timer: int = 0
var is_halftime_swapped: bool = false
var round_winner: String = ""
var round_win_reason: String = "" # "elimination", "defused", "detonated", "time"
var _wipe_announced: bool = false # post-plant attacker wipe notice printed once per round

# Action tracking (plant / defuse in progress)
var current_action_peer: int = 0
var current_action_type: String = "" # "PLANTING" or "DEFUSING"
var current_action_time: float = 0.0
var current_action_target_time: float = 0.0
var current_action_start_pos: Vector3 = Vector3.ZERO
var current_action_site: String = ""

# References to spawned bomb nodes in world
var _world_bomb_instance: Node3D = null
const BOMB_SCENE_PATH := "res://scenes/objects/bomb_item.tscn"

func _ready() -> void:
	mode_title = "SEARCH & DESTROY"
	score_limit = 0
	round_time = round_duration
	max_rounds = 999 # Rounds to win governs match termination
	is_search_and_destroy = true
	super._ready()
	add_to_group("multiplayer_manager")
	_validate_map_setup()

func _validate_map_setup() -> void:
	var sites := get_tree().get_nodes_in_group("bombsite")
	var site_ids: Array[String] = []
	for s in sites:
		if "site_id" in s:
			site_ids.append(str(s.site_id))
	print("[S&D] Validating map: found %d bomb sites (%s)" % [sites.size(), ", ".join(site_ids)])
	var spawns := get_tree().get_nodes_in_group("spawn_points")
	var att_spawns := 0
	var def_spawns := 0
	for sp in spawns:
		if sp.team == "attackers": att_spawns += 1
		elif sp.team == "defenders": def_spawns += 1
	print("[S&D] Spawns: Attackers=%d, Defenders=%d" % [att_spawns, def_spawns])

func _process(delta: float) -> void:
	super._process(delta)
	if is_multiplayer_authority():
		if current_state == MatchState.ACTIVE:
			_process_bomb_action(delta)
		_process_auto_pickup()

## S&D auto-pickup: any living attacker walking over a DROPPED bomb collects it immediately
func _process_auto_pickup() -> void:
	if current_state != MatchState.ACTIVE or current_bomb_state != BombState.DROPPED:
		return
	# Human attackers
	for pid in players_data.keys():
		if players_data[pid].get("team") != "attackers":
			continue
		var p_node := _get_player_node_by_peer(pid)
		if is_instance_valid(p_node) and not bool(p_node.get("is_dead")):
			if p_node.global_position.distance_to(bomb_world_position) <= pickup_radius:
				current_bomb_state = BombState.CARRIED
				bomb_carrier_peer = pid
				bomb_carrier_name = players_data[pid].get("name", str(pid))
				_clear_world_bomb()
				_sync_bomb_data_to_all()
				print("[S&D] Bomb auto-picked up by %s (peer %d)" % [bomb_carrier_name, pid])
				return
	# Attacker bots
	for b in team_bots.get("attackers", []):
		if is_instance_valid(b) and not bool(b.get("is_dead")) and not b.is_queued_for_deletion():
			if b.global_position.distance_to(bomb_world_position) <= pickup_radius:
				current_bomb_state = BombState.CARRIED
				bomb_carrier_peer = int(b.get("net_id")) if b.get("net_id") != null else 101
				bomb_carrier_name = str(b.get("bot_name"))
				_clear_world_bomb()
				_sync_bomb_data_to_all()
				print("[S&D] Bomb auto-picked up by bot %s" % bomb_carrier_name)
				return

# ----------------- Round State Flow -----------------

func set_state(new_state: MatchState) -> void:
	current_state = new_state
	match current_state:
		MatchState.WAITING:
			timer = 999
		MatchState.WARMUP:
			timer = warmup_time
			if is_multiplayer_authority():
				_prepare_new_round()
		MatchState.ACTIVE:
			timer = round_duration
			if is_multiplayer_authority():
				_start_active_round()
		MatchState.ROUND_END:
			timer = 5
			if is_multiplayer_authority():
				_on_round_end_state()
		MatchState.MATCH_END:
			timer = 10
			if is_multiplayer_authority():
				_on_match_end_state()
	# Only freeze players during pre-round warmup/intermission (not on round end)
	players_frozen = current_state == MatchState.WARMUP

	if multiplayer.has_multiplayer_peer():
		sync_state.rpc(current_state, current_round, timer)
	else:
		sync_state(current_state, current_round, timer)

func _on_tick() -> void:
	if not is_multiplayer_authority():
		return

	if timer > 0:
		timer -= 1
		if multiplayer.has_multiplayer_peer():
			sync_time.rpc(timer)
		else:
			sync_time(timer)

	# Bomb countdown ticks if planted
	if current_state == MatchState.ACTIVE and (current_bomb_state == BombState.PLANTED or current_bomb_state == BombState.DEFUSING):
		if bomb_timer > 0:
			bomb_timer -= 1
			# Bomb ticking audio: faster as time runs low (CS style)
			var tick_step: int = 1 if bomb_timer <= 5 else (2 if bomb_timer <= 15 else 4)
			if bomb_timer % tick_step == 0:
				_broadcast_bomb_tick()
			_sync_bomb_data_to_all()
			if bomb_timer <= 0:
				_detonate_bomb()
				return

	if timer <= 0:
		match current_state:
			MatchState.WARMUP:
				set_state(MatchState.ACTIVE)
			MatchState.ACTIVE:
				# If bomb is planted, round timer expiry does not end round; bomb countdown decides.
				if current_bomb_state == BombState.PLANTED or current_bomb_state == BombState.DEFUSING:
					pass # wait for defuse or detonation
				else:
					# Time expired before plant -> Defenders win
					end_round("defenders", "time")
			MatchState.ROUND_END:
				_advance_after_round_end()
			MatchState.MATCH_END:
				_advance_after_match_end()

func _advance_after_round_end() -> void:
	# Check if match win condition reached
	if team_scores["attackers"] >= rounds_to_win or team_scores["defenders"] >= rounds_to_win:
		set_state(MatchState.MATCH_END)
		return

	# Halftime check: after halftime_round rounds played and not yet swapped
	var total_rounds_played: int = int(team_scores.get("attackers", 0)) + int(team_scores.get("defenders", 0))
	if total_rounds_played == halftime_round and not is_halftime_swapped:
		swap_halftime_teams()
		is_halftime_swapped = true

	current_round += 1
	set_state(MatchState.WARMUP)

func _on_round_end_state() -> void:
	_cancel_bomb_action()
	print("[S&D] Round %d ended. Winner: %s (%s). Score: ATT %d - DEF %d" % [
		current_round, round_winner, round_win_reason, team_scores["attackers"], team_scores["defenders"]
	])
	_broadcast_round_end(round_winner, round_win_reason)

func _on_match_end_state() -> void:
	var final_winner := "attackers" if team_scores["attackers"] > team_scores["defenders"] else "defenders"
	if team_scores["attackers"] == team_scores["defenders"]:
		final_winner = "draw"
	print("[S&D] Match finished! Winner: %s (%d - %d)" % [final_winner, team_scores["attackers"], team_scores["defenders"]])

func _advance_after_match_end() -> void:
	# Everyone leaves the arena together: back to the main menu / lobby
	if GlobalData.is_networked():
		net_return_to_lobby.rpc()
	else:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

@rpc("authority", "call_local", "reliable")
func net_return_to_lobby() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

# ----------------- Round Setup & Reset -----------------

func _prepare_new_round() -> void:
	round_winner = ""
	round_win_reason = ""
	_wipe_announced = false
	current_bomb_state = BombState.CARRIED
	bomb_carrier_peer = 0
	bomb_carrier_name = ""
	planted_site_id = ""
	bomb_timer = bomb_countdown
	_cancel_bomb_action()
	_clear_world_bomb()

	# Despawn and respawn all living/dead players and bots to start afresh
	_respawn_all_participants()
	_sync_match_data()
	_sync_bomb_data_to_all()

func _respawn_all_participants() -> void:
	# Respawn human players
	for pid in players_data.keys():
		var p_team: String = players_data[pid].get("team", "attackers")
		spawner.despawn_player(pid)
		var p_node = spawner.spawn_player(pid, p_team)
		if is_instance_valid(p_node):
			p_node.set("snd_team", p_team)
			p_node.set("team", p_team)
			if p_team == "attackers":
				p_node.remove_from_group("enemy")
				p_node.add_to_group("ally")
			else:
				p_node.remove_from_group("ally")
				p_node.add_to_group("enemy")
			if p_node.has_method("exit_spectator_mode"):
				p_node.exit_spectator_mode()

	# Re-balance bots, revive the dead at their team spawn, and forbid
	# mid-round self-respawn (round-based lives).
	_fill_bots()
	for team_key in team_bots:
		for b in team_bots[team_key]:
			if not is_instance_valid(b) or b.is_queued_for_deletion():
				continue
			b.set("can_respawn", false)
			# EVERY bot repositions to its (possibly new after halftime) team
			# spawn — living bots included, otherwise a side swap leaves both
			# teams piled in the same base.
			var sp = spawner.get_spawn_point(team_key)
			if sp:
				b.start_pos = sp.global_position + Vector3(randf_range(-2, 2), 1.0, randf_range(-2, 2))
			if bool(b.get("is_dead")) and b.has_method("respawn"):
				b.respawn()
			elif not bool(b.get("is_dead")):
				b.global_position = b.start_pos
				b.velocity = Vector3.ZERO

func _start_active_round() -> void:
	_assign_bomb_carrier()
	_sync_bomb_data_to_all()

func _assign_bomb_carrier() -> void:
	# Prefer human attacker
	var attacker_peers: Array[int] = []
	for pid in players_data.keys():
		if players_data[pid].get("team", "") == "attackers":
			attacker_peers.append(pid)

	if not attacker_peers.is_empty():
		bomb_carrier_peer = attacker_peers[randi() % attacker_peers.size()]
		bomb_carrier_name = players_data[bomb_carrier_peer].get("name", str(bomb_carrier_peer))
	else:
		# Fallback to bot attacker
		var att_bots: Array = team_bots.get("attackers", [])
		if not att_bots.is_empty():
			var b = att_bots[0]
			if is_instance_valid(b):
				bomb_carrier_peer = int(b.get("net_id")) if b.get("net_id") != null else 101
				bomb_carrier_name = str(b.get("bot_name"))
			# ponytail: bot carriers never plant — round resolves by elimination/time.
		else:
			bomb_carrier_peer = 0
			bomb_carrier_name = ""

	current_bomb_state = BombState.CARRIED
	print("[S&D] Bomb assigned to carrier: %s (peer %d)" % [bomb_carrier_name, bomb_carrier_peer])

# ----------------- Elimination & Win Conditions -----------------

func _on_kill_occurred(killer: String, killer_faction: String, weapon: String, victim: String, victim_faction: String) -> void:
	if not is_multiplayer_authority():
		return

	# Stats tracking (kills and deaths on scoreboard)
	if match_stats.has(killer):
		match_stats[killer]["kills"] += 1
	if match_stats.has(victim):
		match_stats[victim]["deaths"] += 1

	for pid in players_data.keys():
		var p = players_data[pid]
		if p["name"] == killer or str(pid) == killer or (killer == "Player" and pid == 1):
			if match_stats.has(killer): p["kills"] = match_stats[killer]["kills"]
		if p["name"] == victim or str(pid) == victim or (victim == "Player" and pid == 1):
			if match_stats.has(victim): p["deaths"] = match_stats[victim]["deaths"]

	_sync_match_data()

	# Killfeed broadcast
	if GlobalData.is_networked():
		for p in ready_peers:
			net_kill_feed.rpc_id(p, killer, killer_faction, weapon, victim, victim_faction)

	if current_state != MatchState.ACTIVE:
		return

	# If bomb carrier died, drop the bomb
	_handle_carrier_death(victim)

	# If planter/defuser died, cancel action
	if current_action_peer != 0:
		var act_name = _get_peer_or_bot_name(current_action_peer)
		if act_name == victim:
			_cancel_bomb_action()

	# Mark victim player puppet dead immediately so elimination checks don't race
	# the separate report_player_death RPC arriving afterwards.
	for p_node in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p_node):
			var is_vic := false
			if p_node.name == victim or p_node.get("player_name") == victim:
				is_vic = true
			elif victim == "Player" and p_node.name == "1":
				is_vic = true
			else:
				var pid = int(str(p_node.name))
				if players_data.has(pid) and players_data[pid].get("name") == victim:
					is_vic = true
			if is_vic:
				p_node.set("is_dead", true)

	# Check elimination win conditions
	_check_elimination_win()

func _handle_carrier_death(victim_name: String) -> void:
	var carrier_died := false
	if bomb_carrier_name == victim_name:
		carrier_died = true
	elif bomb_carrier_peer > 0:
		var p = players_data.get(bomb_carrier_peer)
		if p and p.get("name") == victim_name:
			carrier_died = true

	if carrier_died and current_bomb_state == BombState.CARRIED:
		var drop_pos := _get_combatant_position(victim_name)
		drop_bomb(drop_pos)

func _get_combatant_position(cname: String) -> Vector3:
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and (p.name == cname or p.get("player_name") == cname or (cname == "Player" and p.name == "1")):
			return p.global_position
	for b in get_tree().get_nodes_in_group("ally") + get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(b) and b.get("bot_name") == cname:
			return b.global_position
	return bomb_world_position

func _check_elimination_win() -> void:
	if current_state != MatchState.ACTIVE:
		return

	var living_att := _count_living_team("attackers")
	var living_def := _count_living_team("defenders")

	# Defenders wiped out -> Attackers win immediately
	if living_def <= 0:
		end_round("attackers", "elimination")
		return

	# Attackers wiped out
	if living_att <= 0:
		if current_bomb_state == BombState.PLANTED or current_bomb_state == BombState.DEFUSING:
			# Bomb is planted! Defenders must still defuse it or wait for detonation.
			if not _wipe_announced:
				_wipe_announced = true
				print("[S&D] All attackers eliminated, but bomb is planted! Defenders must defuse.")
		else:
			# Pre-plant elimination -> Defenders win
			end_round("defenders", "elimination")
			return

func _count_living_team(team: String) -> int:
	var count := 0
	# Human players
	var group := "ally" if team == "attackers" else "enemy"
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p):
			var on_team := p.is_in_group(group) or str(p.get("snd_team")) == team or str(p.get("team")) == team
			if on_team and not bool(p.get("is_dead")):
				count += 1
	# Bots
	for b in team_bots.get(team, []):
		if is_instance_valid(b) and not bool(b.get("is_dead")) and not b.is_queued_for_deletion():
			count += 1
	return count

func end_round(winner: String, reason: String) -> void:
	if not is_multiplayer_authority():
		return
	if current_state != MatchState.ACTIVE:
		return # Prevent duplicate endings

	round_winner = winner
	round_win_reason = reason
	if team_scores.has(winner):
		team_scores[winner] += 1

	round_ended.emit(winner, reason)
	set_state(MatchState.ROUND_END)

func _broadcast_round_end(winner: String, reason: String) -> void:
	if multiplayer.has_multiplayer_peer():
		net_round_ended.rpc(winner, reason, team_scores)
	else:
		net_round_ended(winner, reason, team_scores)

@rpc("authority", "call_local", "reliable")
func net_round_ended(winner: String, reason: String, scores: Dictionary) -> void:
	round_winner = winner
	round_win_reason = reason
	team_scores = scores
	round_ended.emit(winner, reason)
	_show_round_result_ui(winner, reason)
	_play_round_stinger(winner)

func _play_round_stinger(winner: String) -> void:
	# Non-positional 2D stinger so everyone hears the result at equal volume
	var my_team := ""
	var my_peer := multiplayer.get_unique_id() if GlobalData.is_networked() else 1
	if players_data.has(my_peer):
		my_team = players_data[my_peer].get("team", "")
	var key := "round_win" if winner == my_team else "round_loss"
	if Sfx.has_method("oneshot2d"):
		Sfx.oneshot2d(key, -4.0)
	elif Sfx.has_method("oneshot3d") and is_instance_valid(spawner):
		Sfx.oneshot3d(key, spawner, 50.0, 300.0, 0.0)

func _show_round_result_ui(winner: String, reason: String) -> void:
	var msg := "%s WIN THE ROUND\n(%s)" % [winner.to_upper(), reason.to_upper()]
	var hud_nodes := get_tree().get_nodes_in_group("hud")
	for h in hud_nodes:
		if h.has_method("show_center_hint"):
			var col := Color(0.3, 0.7, 1.0) if winner == "attackers" else Color(1.0, 0.4, 0.3)
			h.show_center_hint(msg, col)

# ----------------- Halftime Team Swap -----------------

func swap_halftime_teams() -> void:
	print("[S&D] Halftime reached! Swapping teams.")
	# Scores follow the teams, not the roles (CS-style): swap the buckets so
	# each side keeps its round wins after switching sides. Without this the
	# match-win check (team_scores[role] >= rounds_to_win) counts a team's old
	# points toward the opposing role.
	var old_att_score: int = int(team_scores.get("attackers", 0))
	var old_def_score: int = int(team_scores.get("defenders", 0))
	team_scores["attackers"] = old_def_score
	team_scores["defenders"] = old_att_score
	for pid in players_data.keys():
		var old_t: String = players_data[pid].get("team", "attackers")
		var new_t := "defenders" if old_t == "attackers" else "attackers"
		players_data[pid]["team"] = new_t
		var p_name: String = players_data[pid].get("name", str(pid))
		if match_stats.has(p_name):
			match_stats[p_name]["team"] = new_t
		elif pid == 1 and match_stats.has("Player"):
			# Host's stats may live under the legacy "Player" key while
			# players_data name differs — flip it too or scoreboard shows 4v6
			match_stats["Player"]["team"] = new_t

	# Swap bot teams
	var old_att_bots = team_bots.get("attackers", []).duplicate()
	var old_def_bots = team_bots.get("defenders", []).duplicate()
	team_bots["attackers"] = old_def_bots
	team_bots["defenders"] = old_att_bots

	for b in team_bots["attackers"]:
		if is_instance_valid(b):
			b.set("snd_team", "attackers")
			b.remove_from_group("enemy")
			b.add_to_group("ally")
			if b.has_node("Body") and b.get_node("Body").has_method("set_tint"):
				b.get_node("Body").set_tint(Color(0.2, 0.7, 0.9)) # blue tint for attackers
			if match_stats.has(b.bot_name):
				match_stats[b.bot_name]["team"] = "attackers"
	for b in team_bots["defenders"]:
		if is_instance_valid(b):
			b.set("snd_team", "defenders")
			b.remove_from_group("ally")
			b.add_to_group("enemy")
			if b.has_node("Body") and b.get_node("Body").has_method("set_tint"):
				b.get_node("Body").set_tint(Color(0.9, 0.2, 0.2)) # red tint for defenders
			if match_stats.has(b.bot_name):
				match_stats[b.bot_name]["team"] = "defenders"

	_sync_match_data()
	if multiplayer.has_multiplayer_peer():
		net_halftime_announced.rpc()
		# Re-sync all bot puppets to clients with their post-swap team/tint/role
		for p in ready_peers:
			for b_id in net_bots.keys():
				var b = net_bots[b_id]
				if is_instance_valid(b):
					net_despawn_bot.rpc_id(p, b_id)
					var team = str(b.get("snd_team"))
					if team == "":
						team = "attackers" if b.is_in_group("ally") else "defenders"
					var scene_path = "res://scenes/enemies/capsule_ally.tscn" if team == "attackers" else "res://scenes/enemies/capsule_enemy.tscn"
					var weapon_id = ""
					if b.get("equipped_primary") and b.equipped_primary.has("id"):
						weapon_id = b.equipped_primary["id"]
					net_spawn_bot.rpc_id(p, b_id, scene_path, b.global_position, b.rotation.y, team, b.bot_name, weapon_id)
	else:
		net_halftime_announced()

@rpc("authority", "call_local", "reliable")
func net_halftime_announced() -> void:
	var hud_nodes := get_tree().get_nodes_in_group("hud")
	for h in hud_nodes:
		if h.has_method("show_center_hint"):
			h.show_center_hint("HALFTIME — TEAMS SWAPPED", Color(1.0, 0.85, 0.2))

# ----------------- Bomb State & World Spawns -----------------

@rpc("any_peer", "call_remote", "reliable")
func request_drop_bomb(pos: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0: sender = 1
	if int(bomb_carrier_peer) != sender: return
	if current_bomb_state != BombState.CARRIED: return
	drop_bomb(pos)

func drop_bomb(pos: Vector3) -> void:
	current_bomb_state = BombState.DROPPED
	bomb_carrier_peer = 0
	bomb_carrier_name = ""
	bomb_world_position = pos
	# World bomb visual spawns on every peer via sync_bomb_data below
	_sync_bomb_data_to_all()
	print("[S&D] Bomb dropped at %v" % pos)

func _spawn_world_bomb(pos: Vector3, is_planted: bool) -> void:
	_clear_world_bomb()
	var scene = load(BOMB_SCENE_PATH) as PackedScene
	if scene:
		_world_bomb_instance = scene.instantiate() as Node3D
		_world_bomb_instance.position = pos
		_world_bomb_instance.add_to_group("bomb_item")
		if _world_bomb_instance.has_method("setup"):
			_world_bomb_instance.setup(is_planted, planted_site_id)
		add_child(_world_bomb_instance)

func _clear_world_bomb() -> void:
	if is_instance_valid(_world_bomb_instance):
		_world_bomb_instance.queue_free()
		_world_bomb_instance = null
	# Also clear any lingering bomb items from the scene tree (handles edge-case desync)
	for b in get_tree().get_nodes_in_group("bomb_item"):
		if is_instance_valid(b) and b != _world_bomb_instance:
			b.queue_free()

func _detonate_bomb() -> void:
	current_bomb_state = BombState.DETONATED
	# Stop any in-progress defuse: bomb beat the clock. State check inside
	# _cancel_bomb_action prevents overwriting DETONATED with PLANTED.
	_cancel_bomb_action()
	_sync_bomb_data_to_all()
	if multiplayer.has_multiplayer_peer():
		net_bomb_detonated.rpc(bomb_world_position)
	else:
		net_bomb_detonated(bomb_world_position)
	end_round("attackers", "detonated")

@rpc("authority", "call_local", "reliable")
func net_bomb_detonated(_pos: Vector3) -> void:
	Sfx.oneshot3d("bomb", spawner, 35.0, 260.0, 5.0)
	var hud_nodes := get_tree().get_nodes_in_group("hud")
	for h in hud_nodes:
		if h.has_method("show_center_hint"):
			h.show_center_hint("BOMB DETONATED!", Color(1.0, 0.2, 0.2))

func _defuse_bomb_success() -> void:
	current_bomb_state = BombState.DEFUSED
	_cancel_bomb_action()
	_sync_bomb_data_to_all()
	if multiplayer.has_multiplayer_peer():
		net_bomb_defused.rpc(bomb_world_position)
	else:
		net_bomb_defused(bomb_world_position)
	end_round("defenders", "defused")

@rpc("authority", "call_local", "reliable")
func net_bomb_defused(_pos: Vector3) -> void:
	Sfx.oneshot3d("rifle_reload", spawner, 10.0, 60.0, 2.0)
	var hud_nodes := get_tree().get_nodes_in_group("hud")
	for h in hud_nodes:
		if h.has_method("show_center_hint"):
			h.show_center_hint("BOMB DEFUSED!", Color(0.2, 0.8, 1.0))

func _plant_bomb_success() -> void:
	current_bomb_state = BombState.PLANTED
	bomb_timer = bomb_countdown
	planted_site_id = current_action_site
	bomb_world_position = current_action_start_pos
	bomb_carrier_peer = 0
	bomb_carrier_name = ""
	_cancel_bomb_action()
	# World bomb visual spawns on every peer via sync_bomb_data below
	_sync_bomb_data_to_all()
	if multiplayer.has_multiplayer_peer():
		net_bomb_planted.rpc(planted_site_id, bomb_world_position)
	else:
		net_bomb_planted(planted_site_id, bomb_world_position)

@rpc("authority", "call_local", "reliable")
func net_bomb_planted(site_id: String, _pos: Vector3) -> void:
	Sfx.oneshot3d("rifle_reload", spawner, 10.0, 60.0, 2.0)
	var hud_nodes := get_tree().get_nodes_in_group("hud")
	for h in hud_nodes:
		if h.has_method("show_center_hint"):
			h.show_center_hint("BOMB PLANTED AT SITE %s!" % site_id, Color(1.0, 0.5, 0.1))

func _broadcast_bomb_tick() -> void:
	if multiplayer.has_multiplayer_peer():
		net_bomb_tick.rpc(bomb_world_position)
	else:
		net_bomb_tick(bomb_world_position)

@rpc("authority", "call_local", "reliable")
func net_bomb_tick(_pos: Vector3) -> void:
	Sfx.oneshot3d("bomb_tick", spawner, 45.0, 220.0, 4.0)

# ----------------- Client-to-Host Interaction Requests -----------------

@rpc("any_peer", "call_remote", "reliable")
func request_pickup_bomb() -> void:
	if not is_multiplayer_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0: sender = 1

	if current_state != MatchState.ACTIVE: return
	if current_bomb_state != BombState.DROPPED: return

	# Validate sender is living attacker
	var p_data = players_data.get(sender)
	if not p_data or p_data.get("team") != "attackers": return

	var p_node := _get_player_node_by_peer(sender)
	if not p_node or bool(p_node.get("is_dead")): return
	if p_node.global_position.distance_to(bomb_world_position) > pickup_radius: return

	# Succeeded
	current_bomb_state = BombState.CARRIED
	bomb_carrier_peer = sender
	bomb_carrier_name = p_data.get("name", str(sender))
	_clear_world_bomb()
	_sync_bomb_data_to_all()
	print("[S&D] Bomb picked up by %s (peer %d)" % [bomb_carrier_name, bomb_carrier_peer])

@rpc("any_peer", "call_remote", "reliable")
func request_start_plant(site_id: String) -> void:
	if not is_multiplayer_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0: sender = 1

	if current_state != MatchState.ACTIVE: return
	if current_bomb_state != BombState.CARRIED: return
	if sender != bomb_carrier_peer: return

	# Validate player in site
	var p_node := _get_player_node_by_peer(sender)
	if not p_node or bool(p_node.get("is_dead")): return
	if not _is_player_in_site(p_node, site_id): return

	# Start planting
	current_bomb_state = BombState.PLANTING
	current_action_peer = sender
	current_action_type = "PLANTING"
	current_action_time = 0.0
	current_action_target_time = plant_duration
	current_action_start_pos = p_node.global_position
	current_action_site = site_id
	_broadcast_action_progress("PLANTING", sender, 0.0)
	print("[S&D] Peer %d started planting at Site %s" % [sender, site_id])

@rpc("any_peer", "call_remote", "reliable")
func request_stop_plant() -> void:
	if not is_multiplayer_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0: sender = 1
	if current_action_peer == sender and current_action_type == "PLANTING":
		_cancel_bomb_action()

@rpc("any_peer", "call_remote", "reliable")
func request_start_defuse() -> void:
	if not is_multiplayer_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0: sender = 1

	if current_state != MatchState.ACTIVE: return
	if current_bomb_state != BombState.PLANTED: return

	# Validate sender is living defender
	var p_data = players_data.get(sender)
	if not p_data or p_data.get("team") != "defenders": return

	var p_node := _get_player_node_by_peer(sender)
	if not p_node or bool(p_node.get("is_dead")): return
	if p_node.global_position.distance_to(bomb_world_position) > defuse_radius: return

	# Start defusing
	current_bomb_state = BombState.DEFUSING
	current_action_peer = sender
	current_action_type = "DEFUSING"
	current_action_time = 0.0
	current_action_target_time = defuse_duration
	current_action_start_pos = p_node.global_position
	_broadcast_action_progress("DEFUSING", sender, 0.0)
	print("[S&D] Peer %d started defusing bomb" % sender)

@rpc("any_peer", "call_remote", "reliable")
func request_stop_defuse() -> void:
	if not is_multiplayer_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0: sender = 1
	if current_action_peer == sender and current_action_type == "DEFUSING":
		_cancel_bomb_action()

func _process_bomb_action(delta: float) -> void:
	if current_action_peer == 0 or current_action_target_time <= 0.0:
		return

	var p_node := _get_player_node_by_peer(current_action_peer)
	if not p_node or bool(p_node.get("is_dead")):
		_cancel_bomb_action()
		return

	# Movement check (player cannot move away from action spot)
	if p_node.global_position.distance_to(current_action_start_pos) > 2.5:
		_cancel_bomb_action()
		return

	current_action_time += delta
	var progress := clampf(current_action_time / current_action_target_time, 0.0, 1.0)
	_broadcast_action_progress(current_action_type, current_action_peer, progress)

	if current_action_time >= current_action_target_time:
		# State re-check: bomb may have detonated / round ended mid-action
		if current_action_type == "PLANTING" and current_bomb_state == BombState.PLANTING:
			_plant_bomb_success()
		elif current_action_type == "DEFUSING" and current_bomb_state == BombState.DEFUSING:
			_defuse_bomb_success()

func _cancel_bomb_action() -> void:
	if current_action_peer == 0:
		return
	var old_action = current_action_type
	var old_peer = current_action_peer
	current_action_peer = 0
	current_action_type = ""
	current_action_time = 0.0
	current_action_target_time = 0.0

	if current_bomb_state == BombState.PLANTING:
		current_bomb_state = BombState.CARRIED
	elif current_bomb_state == BombState.DEFUSING:
		current_bomb_state = BombState.PLANTED

	_broadcast_action_progress(old_action, old_peer, -1.0)
	_sync_bomb_data_to_all()
	print("[S&D] Action %s cancelled for peer %d" % [old_action, old_peer])

func _broadcast_action_progress(act: String, peer: int, prog: float) -> void:
	if multiplayer.has_multiplayer_peer():
		net_sync_action_progress.rpc(act, peer, prog)
	else:
		net_sync_action_progress(act, peer, prog)

@rpc("authority", "call_local", "unreliable")
func net_sync_action_progress(act: String, peer: int, prog: float) -> void:
	bomb_action_progress.emit(act, peer, prog)

# ----------------- Bomb State Sync -----------------

func _sync_bomb_data_to_all() -> void:
	var b_state_str := _bomb_state_to_str(current_bomb_state)
	if multiplayer.has_multiplayer_peer():
		sync_bomb_data.rpc(b_state_str, planted_site_id, bomb_carrier_name, bomb_timer, bomb_carrier_peer, bomb_world_position)
	else:
		sync_bomb_data(b_state_str, planted_site_id, bomb_carrier_name, bomb_timer, bomb_carrier_peer, bomb_world_position)

@rpc("authority", "call_local", "reliable")
func sync_bomb_data(b_state: String, site_id: String, carrier_name: String, b_timer: int, carrier_peer: int, b_pos: Vector3) -> void:
	current_bomb_state = _str_to_bomb_state(b_state)
	planted_site_id = site_id
	bomb_carrier_name = carrier_name
	bomb_timer = b_timer
	bomb_carrier_peer = carrier_peer
	bomb_world_position = b_pos
	# Synchronize physical bomb item in the world across host and all clients
	if current_bomb_state == BombState.DROPPED:
		_spawn_world_bomb(b_pos, false)
	elif current_bomb_state == BombState.PLANTED or current_bomb_state == BombState.DEFUSING:
		_spawn_world_bomb(b_pos, true)
	else:
		_clear_world_bomb()
	bomb_state_synced.emit(b_state, site_id, carrier_name, b_timer)

func _bomb_state_to_str(s: BombState) -> String:
	match s:
		BombState.CARRIED: return "CARRIED"
		BombState.DROPPED: return "DROPPED"
		BombState.PLANTING: return "PLANTING"
		BombState.PLANTED: return "PLANTED"
		BombState.DEFUSING: return "DEFUSING"
		BombState.DEFUSED: return "DEFUSED"
		BombState.DETONATED: return "DETONATED"
	return "CARRIED"

func _str_to_bomb_state(s: String) -> BombState:
	match s:
		"CARRIED": return BombState.CARRIED
		"DROPPED": return BombState.DROPPED
		"PLANTING": return BombState.PLANTING
		"PLANTED": return BombState.PLANTED
		"DEFUSING": return BombState.DEFUSING
		"DEFUSED": return BombState.DEFUSED
		"DETONATED": return BombState.DETONATED
	return BombState.CARRIED

# ----------------- Helpers & Validation -----------------

func _is_player_in_site(p_node: Node3D, site_id: String) -> bool:
	for site in get_tree().get_nodes_in_group("bombsite"):
		if str(site.get("site_id")) == site_id:
			if site.has_method("is_point_inside"):
				if site.is_point_inside(p_node.global_position):
					return true
			elif p_node.global_position.distance_to(site.global_position) <= plant_radius:
				return true
	return false

func _get_player_node_by_peer(peer_id: int) -> Node3D:
	var container = spawner._get_container() if is_instance_valid(spawner) else get_tree().current_scene
	if container:
		var p = container.get_node_or_null(str(peer_id))
		if p: return p
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and (p.name == str(peer_id) or (peer_id == 1 and p.name == "Player")):
			return p
	return null

func _get_peer_or_bot_name(peer_id: int) -> String:
	if players_data.has(peer_id):
		return players_data[peer_id].get("name", str(peer_id))
	for b_id in net_bots:
		if b_id == peer_id:
			return net_bots[b_id].get("bot_name")
	return str(peer_id)

func _on_peer_left(peer: int) -> void:
	# Capture carrier / action state before super despawns player node
	var carrier_disconnect := (bomb_carrier_peer == peer and current_bomb_state == BombState.CARRIED)
	var drop_pos := _get_combatant_position(str(peer)) if carrier_disconnect else Vector3.ZERO
	if current_action_peer == peer:
		_cancel_bomb_action()
	super._on_peer_left(peer)
	if is_multiplayer_authority():
		if carrier_disconnect:
			drop_bomb(drop_pos)
		# Any bots backfilled by base must not self-respawn mid-round
		for t_k in team_bots:
			for b in team_bots[t_k]:
				if is_instance_valid(b):
					b.set("can_respawn", false)
		_check_elimination_win()
