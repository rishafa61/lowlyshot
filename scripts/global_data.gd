extends Node

var money: int = 2500
var equipped_operator: String = "Vanguard"

# ponytail: single hardcoded catalog; upgrade to per-weapon .tres loading when adding mod support.
const WEAPON_CATALOG := {
	"Primary": [
		"res://resources/weapons/ak47.tres",
		"res://resources/weapons/m700.tres",
		"res://resources/weapons/m4a4.tres"
	],
	"Secondary": [
		"res://resources/weapons/glock.tres",
		"res://resources/weapons/desert_hawk.tres"
	],
	"Melee": [
		"res://resources/weapons/knife.tres"
	],
	"Utility": [
		"res://resources/weapons/grenade.tres",
		"res://resources/weapons/flashbang.tres"
	]
}

const BOT_NAMES: Array[String] = [
	"Gabe", "Minh", "Cliffe", "Dave", "Lepon", "Chris", "Prabroro",
	"Viper", "Ghost", "Apex", "Nova", "Cipher", "Rook", "Blaze",
	"Frost", "Reaper", "Echo", "Titan", "Shadow", "Raven", "Striker",
	"Havoc", "Phantom", "Pulse", "Jester", "Hunter", "Maverick", "Specter"
]

var _used_bot_names: Array[String] = []

signal kill_occurred(killer: String, killer_faction: String, weapon: String, victim: String, victim_faction: String)
signal combat_logged(msg: String)

func log_combat(msg: String) -> void:
	combat_logged.emit(msg)

func register_kill(killer: String, killer_faction: String, weapon: String, victim: String, victim_faction: String) -> void:
	kill_occurred.emit(killer, killer_faction, weapon, victim, victim_faction)
	combat_logged.emit("%s kill (%s) %s" % [killer, weapon, victim])

func reset_bot_names() -> void:
	_used_bot_names.clear()

func get_random_bot_name() -> String:
	var available: Array[String] = []
	for n in BOT_NAMES:
		if not _used_bot_names.has(n):
			available.append(n)
	var chosen: String = ""
	if available.is_empty():
		chosen = "Bot_%03d" % (randi() % 900 + 100)
	else:
		chosen = available.pick_random()
	_used_bot_names.append(chosen)
	return chosen

var weapons = {
	"Primary": [],
	"Secondary": [],
	"Melee": [],
	"Utility": []
}

func _ready() -> void:
	for category in WEAPON_CATALOG.keys():
		for path in WEAPON_CATALOG[category]:
			var res = load(path)
			if res is WeaponData:
				var d: Dictionary = res.to_dict()
				# ponytail: store monetization removed — everything owned.
				# Re-add price/owned checks here when the shop returns.
				d["owned"] = true
				weapons[category].append(d)

# Helpers to get the currently equipped item dictionary for the Player script
func get_equipped_primary() -> Dictionary:
	for w in weapons["Primary"]:
		if w["equipped"]: return w
	return weapons["Primary"][0]

func get_equipped_secondary() -> Dictionary:
	for w in weapons["Secondary"]:
		if w["equipped"]: return w
	return weapons["Secondary"][0]

func get_equipped_melee() -> Dictionary:
	for w in weapons["Melee"]:
		if w["equipped"]: return w
	return weapons["Melee"][0]

func get_equipped_utility() -> Dictionary:
	for w in weapons["Utility"]:
		if w["equipped"]: return w
	return weapons["Utility"][0]


func get_equipped_operator_script() -> Script:
	if equipped_operator == "Vanguard" or equipped_operator == "Assault":
		return load("res://scenes/operators/assault_operator.gd")
	elif equipped_operator == "Ghost" or equipped_operator == "Recon":
		return load("res://scenes/operators/recon_operator.gd")
	elif equipped_operator == "Shock" or equipped_operator == "Breacher":
		return load("res://scenes/operators/breacher_operator.gd")
	elif equipped_operator == "Wingman":
		return load("res://scenes/operators/wingman_operator.gd")
	elif equipped_operator == "Greppy":
		return load("res://scenes/operators/greppy_operator.gd")
	elif equipped_operator == "Sentry":
		return load("res://scenes/operators/sentry_operator.gd")
	return load("res://scenes/operators/assault_operator.gd")

## True only during a real online match. multiplayer.has_multiplayer_peer() is always true in Godot 4
## (default OfflineMultiplayerPeer), so never use it for this.
func is_networked() -> bool:
	var peer := get_tree().get_multiplayer().multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)
