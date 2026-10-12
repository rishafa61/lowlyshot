extends "res://scenes/enemies/bullseye.gd"

var time_passed: float = 0.0
var start_x: float = 0.0

func _ready():
	start_x = global_position.x

func _physics_process(delta):
	time_passed += delta
	global_position.x = start_x + sin(time_passed * 2.0) * 4.0
