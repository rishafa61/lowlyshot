extends Node3D

## Lobby standby character. Currently mirrors the player's first-person body
## (capsule + visor) because no third-person rig exists yet. Swap `Body` for
## a real player model when one is added.

const FALLBACK_SCENE := "res://scenes/weapons/main/ak47.tscn"
# Weapon-in-hand correction for the lobby standby pose:
# Rests the rifle across the torso in a natural low-ready sling carry
# (barrel pointing down-forward-left, grip resting in the right palm).
const GRIP_CORRECTION_M := Transform3D(
	Basis(
		Vector3(-0.0399, -0.0915, -0.9950),
		Vector3(0.9186, 0.3886, -0.0726),
		Vector3(0.3933, -0.9169, 0.0686)
	),
	Vector3(-0.0393, 0.0917, -0.0069)
)
const HAND_RAW_SCALE := 1.0 / (0.01 * 0.2375) # counter Armature x PlayerModel scale chain

@onready var weapon_mount: Node3D = $WeaponMount

func _ready() -> void:
	_attach_to_hand()
	_show_equipped_weapon()
	# Lobby standby pose: dedicated Mixamo clip, loops via human_body.gd
	var b := get_node_or_null("Body")
	if b and b.has_method("play_anim"):
		b.play_anim("Standby")

func refresh() -> void:
	_show_equipped_weapon()

## Parent the weapon mount to the right-hand BONE so it follows wrist
## position AND rotation through every animation.
func _attach_to_hand() -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return
	var skel := body.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or skel.find_bone("mixamorig_RightHand") < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = "mixamorig_RightHand"
	skel.add_child(att)
	weapon_mount.get_parent().remove_child(weapon_mount)
	att.add_child(weapon_mount)
	# Attachment inherits the raw skeleton scale; counter it and apply the grip offset.
	weapon_mount.transform = Transform3D(
		GRIP_CORRECTION_M.basis.scaled(Vector3.ONE * HAND_RAW_SCALE),
		GRIP_CORRECTION_M.origin * HAND_RAW_SCALE
	)

func set_tint(color: Color) -> void:
	var b := get_node_or_null("Body")
	if b and b.has_method("set_tint"):
		b.set_tint(color)

## Shows the weapon model matching the equipped primary loadout. Instantiates
## by scene_path so every catalogued primary (SMG, LMG, shotgun, sniper...)
## renders its own model instead of a hardcoded 3-model match.
func _show_equipped_weapon() -> void:
	var primary: Dictionary = GlobalData.get_equipped_primary()
	var path := str(primary.get("scene_path", FALLBACK_SCENE))
	if path == "" or not ResourceLoader.exists(path):
		path = FALLBACK_SCENE
	for child in weapon_mount.get_children():
		child.queue_free()
	var model := (load(path) as PackedScene).instantiate() as Node3D
	weapon_mount.add_child(model)
