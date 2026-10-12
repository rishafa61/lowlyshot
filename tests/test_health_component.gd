extends SceneTree

func _init():
	print("--- Running HealthComponent tests ---")
	test_basic_damage()
	test_armor_mitigation()
	test_heal()
	test_percentage_damage()
	print("--- All tests passed! ---")
	quit(0)

func test_basic_damage():
	var h = HealthComponent.new()
	h.setup(100.0, 0.0)
	var final = h.apply_damage(30.0)
	assert(final == 30.0, "Basic damage returned wrong amount")
	assert(h.health == 70.0, "Health was not decremented correctly")
	assert(!h.is_dead, "Should not be dead")

	final = h.apply_damage(80.0)
	assert(h.health == 0.0, "Health should clamp to 0")
	assert(h.is_dead, "Should be dead")
	h.free()

func test_armor_mitigation():
	var h = HealthComponent.new()
	h.setup(100.0, 50.0)
	# 50 damage -> 25 absorbed by armor, 25 to hp
	var final = h.apply_damage(50.0)
	assert(final == 50.0, "Incoming raw damage should match")
	assert(h.armor == 25.0, "Armor was not reduced properly")
	assert(h.health == 75.0, "Health was not reduced properly")

	# Absorb remaining armor (25) -> requires 50 damage
	# But 100 damage: absorbed = min(100*0.5, 25) = 25
	# hp takes 100 - 25 = 75 damage -> hp reaches 0
	h.apply_damage(100.0)
	assert(h.armor == 0.0, "Armor should be 0")
	assert(h.health == 0.0, "Health should be 0")
	assert(h.is_dead, "Should be dead")
	h.free()

func test_heal():
	var h = HealthComponent.new()
	h.setup(100.0, 0.0)
	h.apply_damage(50.0)
	var healed = h.heal(20.0)
	assert(healed == 20.0, "Should heal 20")
	assert(h.health == 70.0, "Health should be 70")
	healed = h.heal(50.0)
	assert(healed == 30.0, "Should clamp heal to max_health")
	assert(h.health == 100.0, "Health should be 100")
	h.free()

func test_percentage_damage():
	var h = HealthComponent.new()
	h.setup(100.0, 0.0)
	h.apply_percentage_damage(0.25)
	assert(h.health == 75.0, "Should be 75 after 25% damage")
	h.apply_percentage_damage(0.5, true)
	assert(h.health == 0.0, "Insta-kill should set health to 0")
	assert(h.is_dead, "Should be dead")
	h.free()
