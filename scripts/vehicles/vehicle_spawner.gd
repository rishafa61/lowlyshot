@tool
class_name VehicleSpawner
extends Node3D
## Drop-in vehicle spawner: instance this scene in any map, pick the vehicle
## in the inspector, done. Spawns at runtime in the playing game.
## ponytail: one vehicle type today — add enum entries + scene paths as new
## vehicles land; the dropdown grows automatically from the enum.

signal vehicle_spawned(vehicle: Node)

enum VehicleType { AIRCRAFT, HUMVEE, HELICOPTER }

const VEHICLE_SCENES: Dictionary = {
	VehicleType.AIRCRAFT: "res://scenes/vehicles/aircraft.tscn",
	VehicleType.HUMVEE: "res://scenes/vehicles/humvee.tscn",
	VehicleType.HELICOPTER: "res://scenes/vehicles/helicopter.tscn",
}

@export_group("Spawner")
@export var choose_vehicle: VehicleType = VehicleType.AIRCRAFT: set = _on_vehicle_changed
@export var auto_spawn: bool = true ## spawn on _ready; disable to spawn manually via spawn_vehicle()
@export var respawn_delay: float = 12.0 ## seconds after the vehicle is destroyed/freed; 0 = no respawn

var _current: Node = null
var _respawn_timer: SceneTreeTimer = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if auto_spawn:
		spawn_vehicle()

func _on_vehicle_changed(v: VehicleType) -> void:
	choose_vehicle = v

func spawn_vehicle() -> Node:
	if is_instance_valid(_current):
		return _current
	var path: String = VEHICLE_SCENES.get(choose_vehicle, "")
	if path == "":
		push_warning("VehicleSpawner: no scene mapped for vehicle type %s" % str(choose_vehicle))
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("VehicleSpawner: failed to load %s" % path)
		return null
	_current = packed.instantiate()
	add_child(_current)
	vehicle_spawned.emit(_current)
	if _current is Node and _current.has_signal("destroyed"):
		_current.destroyed.connect(_on_vehicle_destroyed)
	elif _current is Node and not _current.has_signal("destroyed"):
		# Vehicles without a destroyed signal: watch for tree exit (freed)
		_current.tree_exited.connect(_on_vehicle_gone)
	return _current

func despawn_vehicle() -> void:
	if is_instance_valid(_current):
		_current.queue_free()
	_current = null

func _on_vehicle_destroyed() -> void:
	_current = null
	_schedule_respawn()

func _on_vehicle_gone() -> void:
	# tree_exited also fires when the spawner's own subtree exits (scene change)
	# — only respawn while we're still inside the tree.
	if is_inside_tree():
		_current = null
		_schedule_respawn()

func _schedule_respawn() -> void:
	if respawn_delay <= 0.0 or not is_inside_tree():
		return
	_respawn_timer = get_tree().create_timer(respawn_delay)
	_respawn_timer.timeout.connect(func():
		if is_inside_tree() and not is_instance_valid(_current):
			spawn_vehicle()
	)
