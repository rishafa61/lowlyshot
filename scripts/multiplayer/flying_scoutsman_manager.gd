class_name FlyingScoutsmanManager
extends MultiplayerManager

## Flying Scoutsman: free-for-all sniper deathmatch in moon gravity.
## Everyone (player + bots) is forced onto the M700; first combatant to
## ffa_target_kills wins. Every combatant gets a unique team so nobody is
## "friendly" — bots target and shoot anyone who isn't themselves.

const FLOAT_GRAVITY := 2.94 # ~30% of default 9.8 — the "70% float" moon feel
const BASE_GRAVITY := 9.8

@export_group("Flying Scoutsman Settings")
@export var ffa_bot_count: int = 7 # bots on the field besides the local player
@export var forced_weapon_id: String = "m700"

var _original_gravity: float = BASE_GRAVITY

func _get_global_data() -> Node:
	return get_node_or_null("/root/GlobalData")

func _ready() -> void:
	mode_title = "FLYING SCOUTSMAN"
	target_kills = ffa_target_kills
	ffa_target_kills = 40
	var gd = _get_global_data()
	if gd:
		gd.set("force_primary_id", forced_weapon_id)
	_original_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	ProjectSettings.set_setting("physics/3d/default_gravity", FLOAT_GRAVITY)
	super()

func _exit_tree() -> void:
	# Restore world state so other modes keep normal gravity + loadouts
	var gd = _get_global_data()
	if gd:
		gd.set("force_primary_id", "")
	ProjectSettings.set_setting("physics/3d/default_gravity", _original_gravity)

func _fill_bots() -> void:
	if _bots_kicked_by_admin:
		return
	# FFA: stamp every human a unique team so no two combatants are friendly
	for pid in players_data.keys():
		players_data[pid]["team"] = "ffa_%d" % pid
		var pname := str(players_data[pid].get("name", str(pid)))
		if match_stats.has(pname):
			match_stats[pname]["team"] = players_data[pid]["team"]
		else:
			match_stats[pname] = { "kills": 0, "deaths": 0, "team": players_data[pid]["team"] }
	_sync_match_data()
	# Spawn the bot roster at random spawn points, each its own faction
	for i in ffa_bot_count:
		var bot_team := "ffa_bot_%d" % i
		var spawn_pos := _random_spawn_pos()
		var bot = host_spawn_bot("res://scenes/enemies/capsule_enemy.tscn", spawn_pos, bot_team)
		if bot:
			bot.set("snd_team", bot_team)
			match_stats[bot.bot_name]["team"] = bot_team
	_sync_match_data()

func _random_spawn_pos() -> Vector3:
	var sp = spawner.get_spawn_point("all")
	if sp == null:
		return Vector3(randf_range(-40, 40), 2.0, randf_range(-20, 20))
	# Ring spread so bots never intersect on frame 1, then drop to the floor
	var angle := randf() * TAU
	var dist := randf_range(1.0, 4.0)
	var pos: Vector3 = sp.global_position + Vector3(cos(angle) * dist, 2.0, sin(angle) * dist)
	var w3d: World3D = spawner.get_world_3d() if is_instance_valid(spawner) else null
	if w3d:
		var space: PhysicsDirectSpaceState3D = w3d.direct_space_state
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 10, pos + Vector3.DOWN * 60)
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			pos = hit["position"] + Vector3.UP * 0.3
	return pos
