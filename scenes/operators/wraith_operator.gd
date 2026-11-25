extends Operator
## Wraith — Recon Operator
## Skill: Hunter Drone (35s cooldown).
## Deploys a smart quadcopter that seeks and stuns the closest enemy.

var drone_scene: PackedScene = preload("res://scenes/weapons/skills/hunter_drone.tscn")
var active_drone: Node3D = null

func _ready() -> void:
	op_name = "Wraith"
	max_health = 100
	max_armor = 25
	speed_mult = 1.15
	skill_name = "Hunter Drone"
	skill_cooldown = 35.0

func _exit_tree() -> void:
	if active_drone and is_instance_valid(active_drone):
		active_drone.queue_free()
		active_drone = null

func _execute_skill(player: CharacterBody3D) -> void:
	if not player or not is_instance_valid(player):
		return
	if player.is_dead:
		return
	if player.get("is_drone_stunned") == true:
		return # Cannot launch while stunned
	# Only 1 active Hunter Drone per operator
	if active_drone and is_instance_valid(active_drone):
		return

	# Spawn slightly in front and above the player
	var cam = player.get("camera")
	var forward: Vector3 = Vector3.FORWARD
	if cam is Camera3D:
		forward = -cam.global_transform.basis.z
	else:
		forward = -player.global_transform.basis.z
	var spawn_pos: Vector3 = player.global_position + Vector3.UP * 1.8 + forward * 1.0

	var drone = drone_scene.instantiate()
	player.get_parent().add_child(drone)
	drone.global_position = spawn_pos
	drone.setup(player)
	active_drone = drone

	# Replicate the drone visual across the network
	var mgr = player.get_tree().current_scene
	if mgr and mgr.has_method("spawn_utility_net"):
		mgr.spawn_utility_net("res://scenes/weapons/skills/hunter_drone.tscn", spawn_pos, forward, {
			"faction": drone.faction,
			"owner_name": drone.owner_name
		})

	start_cooldown()
