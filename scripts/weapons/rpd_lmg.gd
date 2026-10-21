class_name RPDLmg
extends Node3D

## RPD 7.62x39 light machine gun
## Exposes weapon statistics in the Inspector and provides model reference points.

@export_group("Weapon Statistics")
@export var fire_mode: String = "auto"
@export var fire_rate: float = 60.0 / 650.0 ## 650 RPM (~0.0923s per shot)
@export var mag_capacity: int = 100
@export var reserve_ammo: int = 200
@export var reload_duration: float = 5.0 ## Seconds — drum swap is slow
@export var body_damage: float = 25.0
@export var headshot_multiplier: float = 2.0
@export var effective_range: float = 70.0

@export_group("Recoil & Handling")
@export var recoil_vertical: float = 0.045 ## High sustained-fire climb
@export var recoil_horizontal: float = 0.018
@export var kick_viewmodel: float = 0.1
@export var spread_per_shot: float = 0.02
@export var movement_speed_mult: float = 0.85 ## Heavier gun, slower walk

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

# ponytail: bipod deploy + prone restriction skipped — needs prone state system;
# add as deploy-on-surface toggle when prone movement ships.
