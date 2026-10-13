extends Node3D
## Training ground networking: party members follow the host into the sandbox.
## Each peer keeps authority over its own player body; replicas of the other
## peers are spawned here and driven by transform sync.
## ponytail: presence + transform sync only — sandbox targets stay per-peer,
## no shared bots/score/death relay. Route through MultiplayerManager when
## co-op objectives land.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"

func _ready() -> void:
	if not GlobalData.is_networked():
		return
	multiplayer.peer_connected.connect(_spawn_replica)
	multiplayer.peer_disconnected.connect(_remove_replica)
	multiplayer.server_disconnected.connect(_on_server_lost)
	# Peers that connected before this scene loaded (client case)
	for id in multiplayer.get_peers():
		_spawn_replica(id)

func _spawn_replica(id: int) -> void:
	if get_node_or_null(str(id)):
		return
	var scene = load(PLAYER_SCENE) as PackedScene
	if scene == null:
		return
	var p = scene.instantiate()
	p.name = str(id)
	p.set_multiplayer_authority(id)
	add_child(p)

func _remove_replica(id: int) -> void:
	var p = get_node_or_null(str(id))
	if p:
		p.queue_free()

func _on_server_lost() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file(MAIN_MENU)

## Owner -> everyone transform + held weapon sync. Server relays client
## states to the other clients (star topology).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_state(pos: Vector3, yaw: float, pitch: float, weapon_path: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and sender != 0:
		for p_id in multiplayer.get_peers():
			if p_id != sender:
				net_state.rpc_id(p_id, pos, yaw, pitch, weapon_path)
	var p = get_node_or_null(str(sender))
	if p and p.has_method("net_set_target"):
		p.net_set_target(pos, yaw, pitch)
	if p and p.has_method("net_set_weapon"):
		p.net_set_weapon(weapon_path)
