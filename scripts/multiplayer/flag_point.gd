class_name FlagPoint
extends Area3D
## King-of-the-Hill capture point. Stand inside uncontested to flip ownership
## to your team and tick points for it. Both teams inside = contested (neutral,
## nobody scores). Full team wipes out and it flips instantly (no gradual
## capture bar — ponytail: add one if capture time needs to be tunable later).
##
## Scoring is host-authoritative: only the server mutates team_scores, then
## pushes them through MultiplayerManager.sync_players_data so every client's
## HUD updates. Ownership colour is computed locally on every peer from the
## (replicated) bodies standing inside, so it reacts instantly without RPCs.

signal owner_changed(new_owner: String, contested: bool)

@export var flag_id: String = "A"
@export var points_per_tick: int = 1
@export var tick_rate: float = 1.0 ## points per second while owned & uncontested
@export var contested: bool = false
@export var owner_team: String = "" ## "", "attackers", "defenders"

var _tick_accum: float = 0.0

@onready var flag_pole: MeshInstance3D = $FlagPole
@onready var flag_cloth: MeshInstance3D = $FlagCloth
@onready var base_ring: MeshInstance3D = $BaseRing
@onready var status_label: Label3D = $StatusLabel

const TEAM_COLORS: Dictionary = {
	"": Color(0.8, 0.8, 0.8),          # neutral: white/gray
	"attackers": Color(0.3, 0.6, 1.0), # blue
	"defenders": Color(1.0, 0.35, 0.3) # red
}

func _ready() -> void:
	add_to_group("flagpoint")
	_refresh_visuals()

func _physics_process(delta: float) -> void:
	var attackers := _count_team("attackers")
	var defenders := _count_team("defenders")
	var now_contested := attackers > 0 and defenders > 0
	var new_owner := owner_team
	if now_contested:
		new_owner = "" # contested = neutral, nobody scores
	elif attackers > 0:
		new_owner = "attackers"
	elif defenders > 0:
		new_owner = "defenders"
	if new_owner != owner_team or now_contested != contested:
		owner_team = new_owner
		contested = now_contested
		_refresh_visuals()
		owner_changed.emit(owner_team, contested)
	# Scoring: only the multiplayer authority mutates scores
	_tick_accum += delta
	if _tick_accum >= tick_rate:
		_tick_accum = fmod(_tick_accum, tick_rate)
		if not contested and owner_team != "":
			_award_point(owner_team)

func _count_team(team: String) -> int:
	var count := 0
	for body in get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		var is_dead: bool = bool(body.get("is_dead")) if "is_dead" in body else false
		if is_dead:
			continue
		var body_team := _body_team(body)
		if body_team == team:
			count += 1
	return count

func _body_team(body: Node3D) -> String:
	if body.is_in_group("player") and "team" in body:
		return str(body.get("team"))
	if body.is_in_group("ally"):
		return "attackers"
	if body.is_in_group("enemy"):
		return "defenders"
	return ""

func _award_point(team: String) -> void:
	if not multiplayer.is_server():
		return # no peer (offline): is_server() is true; clients bail out
	var mgr: Node = get_tree().current_scene
	if mgr == null or not ("team_scores" in mgr):
		return
	var scores: Dictionary = mgr.team_scores
	if not scores.has(team):
		return
	scores[team] += points_per_tick
	var limit: int = int(mgr.get("score_limit")) if "score_limit" in mgr else 0
	if limit > 0 and scores[team] >= limit:
		if mgr.has_method("set_state"):
			mgr.set_state(4) # MatchState.MATCH_END
		return
	if mgr.has_method("_sync_match_data"):
		mgr._sync_match_data()

func _refresh_visuals() -> void:
	var col: Color = TEAM_COLORS.get(owner_team, TEAM_COLORS[""])
	if contested:
		col = Color(1.0, 0.9, 0.2) # yellow = fighting over it
	var cloth_mat := flag_cloth.get_surface_override_material(0)
	if cloth_mat == null:
		cloth_mat = StandardMaterial3D.new()
		flag_cloth.set_surface_override_material(0, cloth_mat)
	(cloth_mat as StandardMaterial3D).albedo_color = col
	(cloth_mat as StandardMaterial3D).emission_enabled = true
	(cloth_mat as StandardMaterial3D).emission = col
	(cloth_mat as StandardMaterial3D).emission_energy_multiplier = 0.6
	var ring_mat := base_ring.get_surface_override_material(0)
	if ring_mat == null:
		ring_mat = StandardMaterial3D.new()
		base_ring.set_surface_override_material(0, ring_mat)
	(ring_mat as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, 0.45)
	(ring_mat as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var label: String
	if contested:
		label = "CONTESTED"
	elif owner_team == "attackers":
		label = "ATTACKERS"
	elif owner_team == "defenders":
		label = "DEFENDERS"
	else:
		label = "NEUTRAL"
	status_label.text = "FLAG %s\n%s" % [flag_id, label]
	status_label.modulate = col
