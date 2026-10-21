class_name SteyrAUG
extends Node3D

## Steyr AUG 9mm SMG weapon script
## Exposes weapon statistics in the Inspector and provides model reference points.

@export_group("Weapon Statistics")
@export var fire_mode: String = "auto"
@export var fire_rate: float = 60.0 / 700.0 ## 700 RPM (~0.0857s per shot)
@export var mag_capacity: int = 30
@export var reserve_ammo: int = 120
@export var reload_duration: float = 2.2 ## Seconds
@export var body_damage: float = 24.0
@export var headshot_multiplier: float = 2.0
@export var effective_range: float = 55.0

@export_group("Recoil & Handling")
@export var recoil_vertical: float = 0.022
@export var recoil_horizontal: float = 0.008
@export var kick_viewmodel: float = 0.06
@export var spread_per_shot: float = 0.014

@export_group("Reference Points")
var muzzle: Marker3D
var shell_port: Marker3D
var aim_point: Marker3D
var grip_point: Marker3D

func _ready() -> void:
	muzzle = get_node_or_null("Muzzle") as Marker3D
	shell_port = get_node_or_null("ShellPort") as Marker3D
	aim_point = get_node_or_null("AimPoint") as Marker3D
	grip_point = get_node_or_null("GripPoint") as Marker3D

func get_muzzle_position() -> Vector3:
	return muzzle.global_position if is_instance_valid(muzzle) else global_position

func get_shell_port_position() -> Vector3:
	return shell_port.global_position if is_instance_valid(shell_port) else global_position

func get_aim_point_position() -> Vector3:
	return aim_point.global_position if is_instance_valid(aim_point) else global_position
