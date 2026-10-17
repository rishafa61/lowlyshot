extends Node3D

var target_y = 0.0
var fall_speed = 60.0
var exploded = false
var damage = 35.0
var radius = 5.0
var is_net_replica: bool = false
## Kill attribution: whoever called the strike
var attacker_name: String = ""
var attacker_faction: String = "Player"

func _physics_process(delta):
	if exploded: return
	
	global_position.y -= fall_speed * delta
	
	if global_position.y <= target_y:
		global_position.y = target_y
		explode()

func explode():
	exploded = true
	$MeshInstance3D.hide()
	$Explosion.show()
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.2, 0)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.5, 0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	$Explosion.material_override = mat
	
	# Deal damage
	if not is_net_replica:
		var targets = get_tree().get_nodes_in_group("enemy") + get_tree().get_nodes_in_group("player")
		for t in targets:
			if t.global_position.distance_to(global_position) <= radius:
				var att := attacker_name if attacker_name != "" else "Player"
				if t.has_method("receive_damage"):
					t.receive_damage(damage, "torso", att, "Airstrike", attacker_faction)
				elif t.has_method("take_damage"):
					t.take_damage(damage, att, "Airstrike", attacker_faction)
					
	var tween = create_tween()
	tween.tween_property($Explosion, "scale", Vector3(1.2, 1.2, 1.2), 0.2)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(queue_free)
