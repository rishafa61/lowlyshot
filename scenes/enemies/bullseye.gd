extends StaticBody3D

var is_dead: bool = false

func take_damage(amount: float, _attacker_name: String = "", _weapon_name: String = "", _attacker_faction: String = "", _attacker_pos: Vector3 = Vector3.INF) -> float:
	print("Bullseye hit for ", amount, " damage!")
	var tween = create_tween()
	scale = Vector3(1.3, 1.3, 1.3)
	tween.tween_property(self, "scale", Vector3.ONE, 0.15)
	return amount
