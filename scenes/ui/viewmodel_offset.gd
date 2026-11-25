extends Control
## In-game viewmodel tuner, CS-style: spawned over the running game, local
## player frozen in the chosen pose (ads = scoped, hip = hipfire) while the
## world keeps rendering. mode is set by the settings menu before add_child.
## Falls back to a standalone rig when no player exists (main menu path).
## Save persists; Esc (pause action) restores the previous offset.

const AK_VIEWMODEL := "res://scenes/weapons/viewmodels/ak47_viewmodel.tscn"

@onready var world: Node3D = $World
@onready var holder: Node3D = $World/Holder
@onready var slider_x: HSlider = $SliderX
@onready var slider_z: VSlider = $SliderZ
@onready var slider_y: VSlider = $SliderY
@onready var slider_rot: HSlider = $SliderRot
@onready var btn_save: Button = $BtnSave
@onready var hint: Label = $Hint

## "ads" (scoped pose) or "hip" (hipfire pose); caller sets before add_child.
var mode := "ads"
## Weapon being tuned: offsets read/write GlobalSettings.vm_offsets[weapon_id].
var weapon_id := "ak47"
var weapon_name := "AK47"

var _start := Vector3.ZERO
var _start_rot := 0.0
var _player: Node = null
var _was_paused := false
var _hidden_nodes: Array[Node] = []

func _ready() -> void:
	_start = _get_off()
	_start_rot = _get_rot()
	_player = _find_local_player()
	_was_paused = get_tree().paused
	var wname := weapon_name
	if _player != null:
		world.visible = false # live game renders behind; rig not needed
		hint.text = ("Drag sliders to fit the scoped %s viewmodel under the crosshair" if mode == "ads" \
			else "Drag sliders to place the hipfire %s viewmodel") % wname + " — Save to keep, Esc to cancel"
		# SP: settings opened from pause froze the tree — unfreeze so the pose
		# can lerp in; restored on close. MP: already running.
		get_tree().paused = false
		_player.viewmodel_edit_mode = mode
		if _player.camera != null:
			_player.camera.current = true # reclaim view from any preview rig
		# Hide in-game HUD so it doesn't overlap the tuner.
		for n: Node in [_player.hud, get_tree().root.find_child("MultiplayerHUD", true, false)]:
			if n != null:
				n.visible = false
				_hidden_nodes.append(n)
		# Entering ads pose: snap idle to frame 0, same as pressing aim in-game.
		if mode == "ads":
			for ap: AnimationPlayer in [_player.weapon_anim, _player.gun_anim]:
				if ap != null and is_instance_valid(ap) and ap.has_animation_library("vm") \
						and ap.current_animation.ends_with("AK_Idle_Loop"):
					ap.seek(0.0, true)
	else:
		hint.text = "No game running — showing a preview rig (%s). Save to keep, Esc to cancel" % wname
		$World/Cam.current = true
		var wdict := GlobalData.get_weapon_by_id(weapon_id)
		var vm_path := str(wdict.get("viewmodel_scene", ""))
		if vm_path == "":
			vm_path = str(wdict.get("scene_path", ""))
		var vm_scene := AK_VIEWMODEL if vm_path == "" else vm_path
		var vm := (load(vm_scene) as PackedScene).instantiate()
		holder.add_child(vm)
		for ap: AnimationPlayer in vm.find_children("*", "AnimationPlayer"):
			if ap.has_animation_library("vm") and ap.has_animation("vm/AK_Idle_Loop"):
				ap.play("vm/AK_Idle_Loop")
				ap.seek(0.0, true)
				ap.pause()
	slider_x.value = _start.x
	slider_z.value = _start.z
	slider_y.value = _start.y
	slider_rot.value = _start_rot
	if _player == null:
		_apply()
	slider_x.value_changed.connect(_on_changed)
	slider_z.value_changed.connect(_on_changed)
	slider_y.value_changed.connect(_on_changed)
	slider_rot.value_changed.connect(_on_changed)
	btn_save.pressed.connect(_on_save)

func _process(_delta: float) -> void:
	# Player died or left mid-tune: bail out, restoring the start offset.
	if _player != null and (not is_instance_valid(_player) or not _player.is_inside_tree() or _player.is_dead):
		_cancel()

func _get_off() -> Vector3:
	return GlobalSettings.get_vm_off(weapon_id, mode)

func _get_rot() -> float:
	return GlobalSettings.get_vm_rot(weapon_id, mode)

func _set_off(v: Vector3) -> void:
	GlobalSettings.set_vm_off(weapon_id, mode, v)

func _set_rot(v: float) -> void:
	GlobalSettings.set_vm_rot(weapon_id, mode, v)

func _apply() -> void:
	# Live mode: the player script applies values every physics frame;
	# standalone: drive the preview rig here.
	if _player == null:
		holder.position = _get_off()
		holder.rotation.y = deg_to_rad(_get_rot())

func _on_changed(_v: float) -> void:
	_set_off(Vector3(slider_x.value, slider_y.value, slider_z.value))
	_set_rot(slider_rot.value)
	_apply()

func _on_save() -> void:
	GlobalSettings.save_settings()
	_close()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_cancel()
		get_viewport().set_input_as_handled() # keep pause menu from toggling too

func _cancel() -> void:
	_set_off(_start)
	_set_rot(_start_rot)
	_close()

func _close() -> void:
	for n in _hidden_nodes:
		if is_instance_valid(n):
			n.visible = true
	_hidden_nodes.clear()
	if _player != null and is_instance_valid(_player):
		_player.viewmodel_edit_mode = ""
	get_tree().paused = _was_paused
	queue_free()

func _find_local_player() -> Node:
	for n in get_tree().root.find_children("*", "CharacterBody3D", true, false):
		if n.get("viewmodel_edit_mode") != null and not n.get("is_puppet"):
			return n
	return null
