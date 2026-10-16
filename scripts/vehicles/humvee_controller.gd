class_name HumveeController
extends GroundVehicleController
## Humvee 4x4 military vehicle (inherits all movement, multi-seat logic,
## damage & destruction from GroundVehicleController).

func _init() -> void:
	max_hp = 600.0 ## Rugged armored military chassis
	engine_power = 9500.0
	max_speed = 28.0 ## ~100 km/h top speed
	max_steer_deg = 35.0
	vehicle_name = "Humvee"
	prompt_text = "Press F to Ride"
