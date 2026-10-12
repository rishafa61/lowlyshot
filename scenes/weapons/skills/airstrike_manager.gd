extends Node3D

var missile_scene = preload("res://scenes/weapons/skills/airstrike_missile.tscn")
var missiles_to_spawn = 3
var timer = 0.0
var spawn_delay = 0.4

func _process(delta):
	timer -= delta
	if timer <= 0 and missiles_to_spawn > 0:
		spawn_missile()
		missiles_to_spawn -= 1
		timer = spawn_delay
		
	if missiles_to_spawn <= 0 and timer <= -2.0:
		queue_free() # Clean up after explosions finish

func spawn_missile():
	var m = missile_scene.instantiate()
	var root = get_tree().current_scene if get_tree().current_scene else get_tree().root
	root.add_child(m)
	
	# Spread slightly around the target
	var offset = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
	
	m.target_y = global_position.y
	m.global_position = global_position + offset
	m.global_position.y += 40.0 # Drop from 40m up
