extends SceneTree

func _initialize() -> void:
	print("--- Running test_vehicle_aim_net ---")
	
	# 1. Test Tank Aim Sync
	var tank_scene = load("res://scenes/vehicles/m1_abrams.tscn")
	assert(tank_scene != null, "tank scene exists")
	var tank = tank_scene.instantiate()
	root.add_child(tank)
	
	# Seat 0 (driver): main turret and cannon
	tank.net_set_aim(0, 1.25, -0.12)
	assert(is_equal_approx(tank._net_target_turret_yaw, 1.25), "tank turret yaw synced")
	assert(is_equal_approx(tank._net_target_cannon_pitch, -0.12), "tank cannon pitch synced")
	
	# Seat 1 (gunner): commander hatch cupola
	tank.net_set_aim(1, -0.75, 0.22)
	assert(is_equal_approx(tank._target_hatch_yaw, -0.75), "tank hatch yaw synced")
	assert(is_equal_approx(tank._target_hatch_pitch, 0.22), "tank hatch pitch synced")
	
	# NaN rejection
	tank.net_set_aim(0, NAN, 0.0)
	assert(is_equal_approx(tank._net_target_turret_yaw, 1.25), "NaN yaw rejected")
	
	tank.queue_free()
	
	# 2. Test Helicopter Aim Sync
	var heli_scene = load("res://scenes/vehicles/helicopter.tscn")
	assert(heli_scene != null, "heli scene exists")
	var heli = heli_scene.instantiate()
	root.add_child(heli)
	
	# Seat 2 (left door gunner, gun 0)
	heli.net_set_aim(2, 0.65, -0.45)
	assert(is_equal_approx(heli._mg_yaw_target[0], 0.65), "heli left MG yaw synced")
	assert(is_equal_approx(heli._mg_pitch_target[0], -0.45), "heli left MG pitch synced")
	
	# Seat 3 (right door gunner, gun 1)
	heli.net_set_aim(3, -0.85, 0.15)
	assert(is_equal_approx(heli._mg_yaw_target[1], -0.85), "heli right MG yaw synced")
	assert(is_equal_approx(heli._mg_pitch_target[1], 0.15), "heli right MG pitch synced")
	
	# NaN rejection
	heli.net_set_aim(2, 0.0, NAN)
	assert(is_equal_approx(heli._mg_pitch_target[0], -0.45), "heli NaN pitch rejected")
	
	heli.queue_free()
	
	print("RESULT: OK (vehicle aim sync verified)")
	quit(0)
