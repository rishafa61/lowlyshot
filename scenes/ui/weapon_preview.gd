extends Node3D
## Weapon inspect preview: shows the selected weapon model. Drag to rotate,
## release snaps back to the side profile (muzzle facing left), scroll zooms.

const SCENES := {
	"ak47": "res://scenes/weapons/main/ak47.tscn",
	"m4a4": "res://scenes/weapons/main/m4a4.tscn",
	"m700": "res://scenes/weapons/main/m700.tscn",
	"knife": "res://scenes/weapons/melee/Knife.tscn",
	"at4": "res://scenes/weapons/heavy/at4.tscn",
	"glock": "res://scenes/weapons/secondary/Glock.tscn",
	"desert_hawk": "res://scenes/weapons/secondary/desert_hawk.tscn",
	"grenade": "res://scenes/weapons/utilities/grenade_hand.tscn",
	"flashbang": "res://scenes/weapons/utilities/flashbang_hand.tscn",
}
const DEFAULT_ROT := Vector3(0.0, PI * 0.5, 0.0) # side profile, muzzle to the left
const CAM_MIN := 0.55
const CAM_MAX := 1.6
const ZOOM_STEP := 0.12

var current_id := ""
var _model: Node3D = null
var _pitch := 0.0
var _snap_tween: Tween = null

@onready var _cam: Camera3D = get_parent().get_node("Camera3D")

func _ready() -> void:
	rotation = DEFAULT_ROT

func show_weapon(id: String) -> void:
	if id == current_id:
		return
	current_id = id
	if _model:
		_model.queue_free()
		_model = null
	var path: String = SCENES.get(id, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	_model = (load(path) as PackedScene).instantiate()
	add_child(_model)
	snap_back(true)

func rotate_by(rel: Vector2) -> void:
	if _snap_tween:
		_snap_tween.kill()
		_snap_tween = null
	rotation.y += rel.x * 0.01
	_pitch = clampf(_pitch + rel.y * 0.008, deg_to_rad(-35.0), deg_to_rad(35.0))
	rotation.x = _pitch

func snap_back(instant: bool = false) -> void:
	_pitch = 0.0
	if instant:
		rotation = DEFAULT_ROT
		return
	if _snap_tween:
		_snap_tween.kill()
	_snap_tween = create_tween()
	_snap_tween.tween_property(self, "rotation", DEFAULT_ROT, 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func zoom_by(dir: int) -> void:
	var p := _cam.position
	p.z = clampf(p.z - dir * ZOOM_STEP, CAM_MIN, CAM_MAX)
	_cam.position = p
