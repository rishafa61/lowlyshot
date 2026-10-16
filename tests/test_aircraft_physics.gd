extends SceneTree
## Runnable self-check for aircraft controller math + ordnance curves.
## Run via Godot CLI: godot --headless --script res://tests/test_aircraft_physics.gd

const AircraftController = preload("res://scripts/vehicles/aircraft_controller.gd")
const AircraftOrdnance = preload("res://scripts/vehicles/aircraft_ordnance.gd")

func _init() -> void:
	print("--- Running AircraftController physics tests ---")
	test_lift_ratio()
	test_drag_scaling()
	test_heat_accumulation()
	test_missile_blast_damage()
	test_bomb_blast_damage()
	print("--- All aircraft tests passed! ---")
	quit(0)

func test_lift_ratio() -> void:
	var stall := 18.0
	assert(AircraftController.compute_lift_ratio(0.0, stall) == 0.0, "Lift at zero speed must be 0")
	var half := AircraftController.compute_lift_ratio(9.0, stall)
	assert(absf(half - 0.5) < 0.001, "Lift at half stall speed must be 0.5")
	assert(AircraftController.compute_lift_ratio(18.0, stall) == 1.0, "Lift at stall speed must be 1.0")
	assert(AircraftController.compute_lift_ratio(60.0, stall) == 1.0, "Lift above stall must clamp to 1.0")
	assert(AircraftController.compute_lift_ratio(-5.0, stall) == 0.0, "Backward velocity must produce 0 lift")

func test_drag_scaling() -> void:
	var lin := 0.05
	var quad := 0.002
	assert(AircraftController.compute_drag(lin, quad, 0.0) == 0.05, "Drag at rest must equal linear term")
	var drag_10 := AircraftController.compute_drag(lin, quad, 10.0)
	var drag_50 := AircraftController.compute_drag(lin, quad, 50.0)
	assert(drag_50 > drag_10, "Drag must grow with speed")
	assert(absf(drag_50 - 0.15) < 0.0001, "Drag at 50 m/s must be 0.05 + 0.002*50 = 0.15")

func test_heat_accumulation() -> void:
	# Starts at 0, per-shot 2.0 -> 50 rounds to 100%
	var h := 0.0
	for i in 50:
		h = AircraftController.compute_heat(h, 2.0)
	assert(h == 100.0, "50 rounds must reach 100% heat")
	# Clamped at 100
	h = AircraftController.compute_heat(h, 2.0)
	assert(h == 100.0, "Heat must not exceed 100")

func test_missile_blast_damage() -> void:
	# Missile: radius 8.0, center 200, outer 120
	var r := 8.0
	var c := 200.0
	var o := 120.0
	# Dead-center (<= 4m)
	assert(AircraftOrdnance.compute_blast_damage(0.0, r, c, o) == 200.0, "Direct hit must deal 200")
	assert(AircraftOrdnance.compute_blast_damage(3.5, r, c, o) == 200.0, "Inside inner radius must deal 200")
	# Rim (8m)
	assert(absf(AircraftOrdnance.compute_blast_damage(7.99, r, c, o) - 120.0) < 1.0, "Rim must approach 120")
	# Outside (> 8m)
	assert(AircraftOrdnance.compute_blast_damage(8.5, r, c, o) == 0.0, "Outside radius must deal 0")

func test_bomb_blast_damage() -> void:
	# Bomb: radius 16.0, flat 300
	var r := 16.0
	var c := 300.0
	var o := 300.0
	assert(AircraftOrdnance.compute_blast_damage(0.0, r, c, o) == 300.0, "Bomb center must deal 300")
	assert(AircraftOrdnance.compute_blast_damage(12.0, r, c, o) == 300.0, "Bomb mid must deal 300")
	assert(AircraftOrdnance.compute_blast_damage(17.0, r, c, o) == 0.0, "Bomb outside must deal 0")
