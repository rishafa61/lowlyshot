extends Node
class_name Operator

@export var op_name: String = "Unknown"
@export var max_health: int = 100
@export var max_armor: int = 50
@export var speed_mult: float = 1.0

# Active Skill
@export var skill_name: String = "None"
@export var skill_cooldown: float = 30.0
var current_cooldown: float = 0.0

func _process(delta):
	if current_cooldown > 0:
		current_cooldown -= delta

func use_skill(player_node: CharacterBody3D):
	if current_cooldown <= 0:
		_execute_skill(player_node)

func start_cooldown():
	current_cooldown = skill_cooldown

func _execute_skill(_player: CharacterBody3D):
	pass

func override_fire() -> bool:
	return false

func override_aim() -> bool:
	return false

func cancel_skill():
	pass
