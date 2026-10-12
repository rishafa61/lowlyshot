extends Node3D
class_name PlayerSpawner

## Spawns player(s) at registered SpawnPoint markers.
## Offline: spawns directly. Online (host): spawns locally and tells the
## MultiplayerManager to replicate the spawn to every ready client.

@export var player_scene: PackedScene = null
@export var default_team: String = "all"
@export var player_container: NodePath = ^""

const PLAYER_PATH = "res://scenes/player/player.tscn"

## peer_id -> spawn data dictionary (host only), used to bring late joiners up to date
var spawned_data: Dictionary = {}

func _get_player_scene() -> PackedScene:
	if player_scene != null:
		return player_scene
	var loaded = load(PLAYER_PATH) as PackedScene
	return loaded

func _get_container() -> Node:
	if player_container != NodePath(""):
		return get_node(player_container)
	var cs := get_tree().current_scene
	return cs if cs != null else get_parent()

func get_spawn_point(team: String = "") -> SpawnPoint:
	var wanted = team if team != "" else default_team
	var candidates: Array = []
	for sp in get_tree().get_nodes_in_group("spawn_points"):
		if not sp.is_active:
			continue
		if sp.team == wanted or sp.team == "all" or wanted == "all":
			candidates.append(sp)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]

## Builds a player node from spawn data (identical on host and clients). Not yet in the tree.
func _build_player(data: Dictionary) -> Node3D:
	var scene: PackedScene = _get_player_scene()
	if scene == null:
		push_error("PlayerSpawner: player scene missing at " + PLAYER_PATH)
		return null
	var peer_id: int = int(data.get("peer", 1))
	var t: String = str(data.get("team", default_team))
	var player: Node3D = scene.instantiate()
	player.name = str(peer_id) # unique per peer for multiplayer sync
	player.position = data.get("pos", Vector3(0, 2, 0))
	player.rotation.y = float(data.get("yaw", 0.0))
	# Authority + team must be set BEFORE the node enters the tree (_ready reads them)
	player.set_multiplayer_authority(peer_id)
	if "team" in player:
		player.team = t
	if "player_name" in player and peer_id != 1:
		player.player_name = str(peer_id)
	if t == "attackers":
		player.add_to_group("ally")
	elif t == "defenders":
		player.add_to_group("enemy")
	return player

func spawn_player(peer_id: int = 1, team: String = "") -> Node3D:
	var sp: SpawnPoint = get_spawn_point(team)
	var t: String = team if team != "" else default_team
	var data := {
		"peer": peer_id,
		"team": t,
		"pos": sp.global_position if sp else Vector3(0, 2, 0),
		"yaw": sp.rotation.y if sp else 0.0,
	}
	var player := _build_player(data)
	if player == null:
		return null
	_get_container().add_child(player)
	if sp:
		player.global_position = sp.global_position
	spawned_data[peer_id] = data
	if GlobalData.is_networked() and multiplayer.is_server():
		var mgr = get_parent()
		if mgr is MultiplayerManager:
			mgr.replicate_spawn(data)
	return player

func despawn_player(peer_id: int = 1) -> void:
	_remove_local(peer_id)
	spawned_data.erase(peer_id)
	if GlobalData.is_networked() and multiplayer.is_server():
		var mgr = get_parent()
		if mgr is MultiplayerManager:
			mgr.replicate_despawn(peer_id)

## Client side: create the copy of a player that the host spawned
func build_replica(data: Dictionary) -> void:
	var peer_id: int = int(data.get("peer", 1))
	_remove_local(peer_id) # idempotent
	var player := _build_player(data)
	if player:
		_get_container().add_child(player)

func remove_replica(peer_id: int) -> void:
	_remove_local(peer_id)

func apply_remote_state(peer_id: int, pos: Vector3, yaw: float, pitch: float) -> void:
	var p = _get_container().get_node_or_null(str(peer_id))
	if p and p.has_method("net_set_target"):
		p.net_set_target(pos, yaw, pitch)

func _remove_local(peer_id: int) -> void:
	var container := _get_container()
	var player = container.get_node_or_null(str(peer_id))
	if player:
		# remove first so the name is free immediately when a respawn follows in the same frame
		container.remove_child(player)
		player.queue_free()
