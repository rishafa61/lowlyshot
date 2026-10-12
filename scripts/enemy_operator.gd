extends Node
class_name EnemyOperator

@export var op_name: String = "Unknown"
@export var max_health: int = 100
@export var max_armor: int = 0
@export var speed_mult: float = 1.0
@export var skill_name: String = "None"
@export var skill_cooldown: float = 30.0
var current_cooldown: float = 0.0

# Reference to the enemy using this operator
var enemy_ref: CharacterBody3D = null

func _process(delta):
	if current_cooldown > 0:
		current_cooldown -= delta

func setup(enemy: CharacterBody3D):
	enemy_ref = enemy

func use_skill(target: Node3D) -> bool:
	if current_cooldown <= 0 and enemy_ref:
		_execute_skill(target)
		return true
	return false

func _execute_skill(_target: Node3D):
	pass

func cancel_skill():
	pass

# Utility for enemies to get aim direction toward target
func get_aim_dir(target: Node3D) -> Vector3:
	if not enemy_ref or not target:
		return Vector3.FORWARD
	var dir = (target.global_position - enemy_ref.global_position).normalized()
	dir.y = 0
	return dir.normalized()

func get_aim_pos(target: Node3D, height_offset: float = 1.0) -> Vector3:
	if not target:
		return enemy_ref.global_position
	return target.global_position + Vector3(0, height_offset, 0)
