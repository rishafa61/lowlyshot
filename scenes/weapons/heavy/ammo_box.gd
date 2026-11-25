class_name AmmoSupplyBox
extends StaticBody3D

@export var max_active_per_player: int = 1
@export var resupply_radius: float = 3.0
@export var resupply_interval: float = 1.0
@export var lifetime: float = 60.0
@export var total_supply_capacity: int = 100
@export var resupply_cost: int = 20
@export var ammo_amount_per_resupply: int = 0 ## 0 = weapon max_mag (1 for launcher); >0 = custom fixed
@export var deploy_action: String = "fire"
@export var interact_action: String = "interact"
@export var deployments_per_life: int = 1

var supplies: int = 100
var is_depleted: bool = false
var owner_peer_id: int = 1
var owner_team: String = ""
var owner_name: String = "Player"
var is_net_replica: bool = false

var _life_timer: float = 0.0
var _local_auto_timer: float = 0.0
var _local_player_inside: Node = null
var _prompt_target: Node = null
var _despawn_timer: float = 0.0
const DEPLETED_DESPAWN_DELAY: float = 5.0

@onready var lid: Node3D = $Lid
@onready var status_led: MeshInstance3D = $Lid/StatusLED
@onready var supply_label: Label3D = $Lid/SupplyLabel
@onready var prox_area: Area3D = $ProximityArea
@onready var prox_shape: CollisionShape3D = $ProximityArea/CollisionShape3D

func _ready() -> void:
	add_to_group("ammo_supply_boxes")
	supplies = total_supply_capacity
	if prox_shape and prox_shape.shape is SphereShape3D:
		(prox_shape.shape as SphereShape3D).radius = resupply_radius

	if prox_area:
		prox_area.body_entered.connect(_on_body_entered)
		prox_area.body_exited.connect(_on_body_exited)

	_update_visuals()

func _exit_tree() -> void:
	_clear_local_prompt()

func _process(delta: float) -> void:
	_life_timer += delta
	if _life_timer >= lifetime:
		queue_free()
		return

	if is_depleted:
		_despawn_timer += delta
		if _despawn_timer >= DEPLETED_DESPAWN_DELAY:
			queue_free()
			return
		return

	# Distance-based check for local player (bulletproof against missing Area3D signals)
	var lp := _find_local_player()
	var in_range := false
	if lp and is_instance_valid(lp):
		var dist := global_position.distance_to(lp.global_position)
		if dist <= resupply_radius + 0.3:
			in_range = true
			if not _is_friendly_to(lp):
				_clear_local_prompt()
			else:
				_show_local_prompt(lp)
				_local_auto_timer += delta

				var wants_interact: bool = Input.is_action_just_pressed(interact_action) or Input.is_action_just_pressed("vehicle_interact")
				var auto_tick: bool = _local_auto_timer >= resupply_interval

				if wants_interact or auto_tick:
					_local_auto_timer = 0.0
					_try_resupply_player(lp, wants_interact)

	if not in_range and _prompt_target != null:
		_clear_local_prompt()

func _find_local_player() -> Node:
	if _local_player_inside and is_instance_valid(_local_player_inside) and not _local_player_inside.get("is_dead"):
		return _local_player_inside
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and _is_local_player(p) and not p.get("is_dead"):
			return p
	return null

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and _is_local_player(body):
		_local_player_inside = body
		_local_auto_timer = 0.0
		_show_local_prompt(body)

func _on_body_exited(body: Node3D) -> void:
	if body == _local_player_inside:
		_clear_local_prompt()
		_local_player_inside = null

func _is_local_player(p: Node) -> bool:
	if not p.is_in_group("player"):
		return false
	if p.get("is_puppet") == true:
		return false
	if p.has_method("is_multiplayer_authority"):
		return p.is_multiplayer_authority()
	return true

func _is_friendly_to(p: Node) -> bool:
	if not is_instance_valid(p) or p.get("is_dead") == true:
		return false
	# Team mode: match attackers / defenders
	var p_team: String = str(p.get("team"))
	if owner_team != "" and p_team != "":
		return owner_team == p_team
	if p.is_in_group("ally") and owner_team == "defenders":
		return false
	if p.is_in_group("enemy") and owner_team == "attackers":
		return false

	# Free-for-all mode: only owner player is friendly
	if GlobalData.is_ffa_mode():
		var p_peer = p.get_multiplayer_authority() if p.has_method("get_multiplayer_authority") else 1
		return p_peer == owner_peer_id or p.name == str(owner_peer_id) or p.get("player_name") == owner_name

	var peer = p.get_multiplayer_authority() if p.has_method("get_multiplayer_authority") else 1
	return peer == owner_peer_id or p.name == str(owner_peer_id) or p.get("player_name") == owner_name

func _show_local_prompt(p: Node = null) -> void:
	var target = p if p != null else _local_player_inside
	if not target or not is_instance_valid(target):
		return
	var hud = target.get("hud")
	if not hud:
		return
	_prompt_target = target
	if is_depleted:
		if hud.has_method("show_interact_prompt"):
			hud.show_interact_prompt("—", "SUPPLIES DEPLETED")
	else:
		if hud.has_method("show_interact_prompt"):
			hud.show_interact_prompt("F", "RESUPPLY AMMO")

func _clear_local_prompt() -> void:
	if _prompt_target and is_instance_valid(_prompt_target):
		var hud = _prompt_target.get("hud")
		if hud and hud.has_method("hide_interact_prompt"):
			hud.hide_interact_prompt()
	_prompt_target = null

## Direct interaction from player (e.g. aimed at or pressed F)
func interact_from_player(player: Node) -> bool:
	if is_depleted or supplies <= 0:
		var hud = player.get("hud")
		if hud and hud.has_method("show_center_hint"):
			hud.show_center_hint("SUPPLIES DEPLETED", Color(1.0, 0.35, 0.35))
		return false
	if not _is_friendly_to(player):
		return false
	_try_resupply_player(player, true)
	return true

func _try_resupply_player(player: Node, manual_press: bool) -> void:
	if is_depleted or supplies <= 0:
		if manual_press:
			var hud = player.get("hud")
			if hud and hud.has_method("show_center_hint"):
				hud.show_center_hint("SUPPLIES DEPLETED", Color(1.0, 0.35, 0.35))
		return
	if not _is_friendly_to(player):
		return

	# Check if player needs ammo
	if player.has_method("can_receive_ammo"):
		if not player.can_receive_ammo():
			if manual_press:
				var hud = player.get("hud")
				if hud and hud.has_method("show_center_hint"):
					hud.show_center_hint("AMMO ALREADY FULL", Color(1.0, 0.75, 0.2))
				Sfx.oneshot3d("rifle_reload", self, 6.0, 20.0, 0.8)
			return

	# Network routing
	if GlobalData.is_networked():
		var mgr = get_tree().current_scene
		if mgr and mgr.has_method("request_box_resupply"):
			mgr.request_box_resupply(name)
			return

	# Local / offline execution
	execute_resupply(player)

## Called on server or offline to deduct supply and grant ammo
func execute_resupply(player: Node) -> bool:
	if is_depleted or supplies <= 0:
		return false
	if not _is_friendly_to(player):
		return false

	var granted := false
	if player.has_method("receive_resupply"):
		granted = player.receive_resupply(ammo_amount_per_resupply)

	if granted:
		supplies = maxi(0, supplies - resupply_cost)
		if supplies <= 0:
			set_depleted()
		else:
			_update_visuals()
		return true
	return false

func set_depleted() -> void:
	if is_depleted:
		return
	is_depleted = true
	supplies = 0
	_update_visuals()
	_clear_local_prompt()
	var lp := _find_local_player()
	var hud = lp.get("hud") if lp and is_instance_valid(lp) else null
	if hud and hud.has_method("show_center_hint"):
		hud.show_center_hint("SUPPLIES DEPLETED", Color(1.0, 0.35, 0.35))

	# Pop open lid
	if lid:
		var tw := create_tween()
		tw.tween_property(lid, "rotation:x", -deg_to_rad(45.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func sync_state(new_supplies: int, depleted: bool) -> void:
	supplies = new_supplies
	if depleted and not is_depleted:
		set_depleted()
	else:
		_update_visuals()

func _update_visuals() -> void:
	var pct: int = int((float(supplies) / float(maxi(1, total_supply_capacity))) * 100.0)
	if supply_label:
		if is_depleted or supplies <= 0:
			supply_label.text = "DEPLETED"
			supply_label.modulate = Color(1.0, 0.25, 0.25)
		else:
			supply_label.text = "AMMO SUPPLY %d%%" % pct
			supply_label.modulate = Color(1.0, 0.78, 0.15) if pct < 50 else Color(0.2, 0.9, 0.35)

	if status_led:
		var mat := status_led.get_active_material(0)
		if mat is StandardMaterial3D:
			mat = mat.duplicate()
			status_led.set_surface_override_material(0, mat)
		if mat is StandardMaterial3D:
			if is_depleted or supplies <= 0:
				mat.albedo_color = Color(0.9, 0.15, 0.15)
				mat.emission = Color(0.9, 0.15, 0.15)
			elif pct < 50:
				mat.albedo_color = Color(1.0, 0.6, 0.1)
				mat.emission = Color(1.0, 0.6, 0.1)
			else:
				mat.albedo_color = Color(0.2, 0.9, 0.35)
				mat.emission = Color(0.2, 0.9, 0.35)
