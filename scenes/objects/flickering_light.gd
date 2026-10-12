extends Node3D

@onready var light = $OmniLight3D
@onready var bulb = $Bulb
@onready var timer = $Timer

var default_energy = 2.0
var is_flickering = false

func _ready():
	default_energy = light.light_energy
	start_next_flicker()

func start_next_flicker():
	# Wait 5 to 10 seconds before flickering
	timer.wait_time = randf_range(5.0, 10.0)
	timer.start()

func _on_timer_timeout():
	if not is_flickering:
		# Do a rapid flicker sequence
		is_flickering = true
		var tween = create_tween()
		
		# Flicker off
		tween.tween_callback(set_light.bind(0.0))
		tween.tween_interval(randf_range(0.05, 0.2))
		# Flicker on
		tween.tween_callback(set_light.bind(default_energy))
		tween.tween_interval(randf_range(0.05, 0.1))
		# Flicker off
		tween.tween_callback(set_light.bind(0.0))
		tween.tween_interval(randf_range(0.1, 0.4))
		# Stay on and reset
		tween.tween_callback(set_light.bind(default_energy))
		tween.tween_callback(func(): is_flickering = false)
		
		start_next_flicker()

func set_light(energy: float):
	light.light_energy = energy
	# Update bulb material emission
	var mat = bulb.get_active_material(0)
	if mat:
		mat.emission_energy_multiplier = energy
