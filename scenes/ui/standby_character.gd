extends Node3D

## Lobby standby character. Currently mirrors the player's first-person body
## (capsule + visor) because no third-person rig exists yet. Swap `Body` for
## a real player model when one is added.

@onready var weapon_mount: Node3D = $WeaponMount

func _ready() -> void:
	_show_equipped_weapon()

## Shows the stand-in weapon that matches the equipped primary loadout.
func _show_equipped_weapon() -> void:
	var primary: Dictionary = GlobalData.get_equipped_primary()
	var id: String = str(primary.get("id", ""))
	for child in weapon_mount.get_children():
		child.visible = false
	match id:
		"m4a4":
			weapon_mount.get_node("M4A4").visible = true
		"m700":
			weapon_mount.get_node("Sniper").visible = true
		_:
			weapon_mount.get_node("AK47").visible = true
