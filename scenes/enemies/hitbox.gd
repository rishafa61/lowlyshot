extends Area3D
@export var body_part: String = "upper"

func take_damage(amount: float, attacker_name: String = "", weapon_name: String = "", attacker_faction: String = "") -> float:
	var root = get_parent().get_parent() # Hitboxes node -> CharacterBody3D
	if root.has_method("receive_damage"):
		return root.receive_damage(amount, body_part, attacker_name, weapon_name, attacker_faction)
	return amount

func take_percentage_damage(percent: float, is_backstab: bool, attacker_name: String = "", weapon_name: String = "", attacker_faction: String = "") -> float:
	var root = get_parent().get_parent()
	if root.has_method("receive_percentage_damage"):
		return root.receive_percentage_damage(percent, is_backstab, attacker_name, weapon_name, attacker_faction)
	return 0.0
