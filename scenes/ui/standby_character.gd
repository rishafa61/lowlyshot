extends Node3D

## Lobby standby character. Currently mirrors the player's first-person body
## (capsule + visor) because no third-person rig exists yet. Swap `Body` for
## a real player model when one is added.

const FALLBACK_SCENE := "res://scenes/weapons/main/ak47.tscn"

@onready var weapon_mount: Node3D = $WeaponMount

func _ready() -> void:
	_show_equipped_weapon()

func refresh() -> void:
	_show_equipped_weapon()

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
