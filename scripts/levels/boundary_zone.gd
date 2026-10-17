extends Node3D
class_name BoundaryZone

## Outer boundary & void-kill monitor.
## - Floor void (Y < kill_y): instant kill (player fell off).
## - Side area (outside inner_bounds): warning banner with countdown; if 10s expires,
##   destroys whatever touched the area (players, vehicles, aircraft).

const WARNING_TIME: float = 10.0

@export var kill_y: float = -30.0
@export var inner_half_x: float = 400.0
@export var inner_half_z: float = 400.0
@export var max_altitude: float = 400.0
@export var warning_time: float = 10.0

## Tracks Node -> time spent outside (seconds)
var _out_of_bounds: Dictionary = {}
var _check_timer: float = 0.0

func _physics_process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < 0.1: # 10 Hz is plenty for boundary checks
		return
	var dt := _check_timer
	_check_timer = 0.0

	var targets: Array[Node] = []
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and not p.get("is_dead"):
			targets.append(p)
	for v in get_tree().get_nodes_in_group("vehicles"):
		if is_instance_valid(v) and not v.get("is_destroyed"):
			targets.append(v)

	var currently_out: Dictionary = {}

	for t in targets:
		if not is_instance_valid(t):
			continue
		var pos: Vector3 = t.global_position

		# 1. Floor void-kill: instant
		if pos.y < kill_y:
			_instant_void_kill(t)
			continue

		# 2. Side / ceiling out-of-bounds check
		var outside: bool = absf(pos.x) > inner_half_x or absf(pos.z) > inner_half_z or pos.y > max_altitude
		if outside:
			var prev: float = _out_of_bounds.get(t, 0.0)
			var elapsed: float = prev + dt
			currently_out[t] = elapsed

			var remaining := maxf(0.0, warning_time - elapsed)
			_show_warning(t, remaining)

			if elapsed >= warning_time:
				_destroy_target(t)
		else:
			if _out_of_bounds.has(t):
				_hide_warning(t)

	# Clean up entities that came back inside or got deleted
	for old_t in _out_of_bounds.keys():
		if not currently_out.has(old_t):
			if is_instance_valid(old_t):
				_hide_warning(old_t)

	_out_of_bounds = currently_out

func _instant_void_kill(target: Node) -> void:
	if target.has_method("take_damage"):
		target.take_damage(99999.0, "Void", "Fall", "World", target.global_position)
	elif target.has_method("die"):
		target.die()
	elif target is Node:
		target.queue_free()

func _destroy_target(target: Node) -> void:
	_hide_warning(target)
	if target.has_method("take_damage"):
		target.take_damage(99999.0, "Boundary", "Desertion", "World", target.global_position)
	elif target.has_method("die"):
		target.die()
	elif target is Node:
		target.queue_free()

func _show_warning(target: Node, remaining_sec: float) -> void:
	var huds := _gather_target_huds(target)
	for hud in huds:
		if hud.has_method("show_boundary_warning"):
			hud.show_boundary_warning(remaining_sec)

func _hide_warning(target: Node) -> void:
	var huds := _gather_target_huds(target)
	for hud in huds:
		if hud.has_method("hide_boundary_warning"):
			hud.hide_boundary_warning()

func _gather_target_huds(target: Node) -> Array:
	var res: Array = []
	var h = target.get("hud")
	if h != null:
		res.append(h)
	# If target is a vehicle, forward warning to occupants
	var occ = target.get("occupants")
	if occ is Array:
		for p in occ:
			if p != null and p.get("hud") != null:
				res.append(p.get("hud"))
	var pilot = target.get("active_pilot")
	if pilot != null and pilot.get("hud") != null:
		res.append(pilot.get("hud"))
	return res
