# FlagPoint capture logic test — headless: builds a flag + bodies, simulates
# capture / contest / flip scenarios over real physics frames.
extends SceneTree

var fails: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func _make_body(group: String, pos: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.add_to_group(group)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 1.8
	shape.shape = cap
	body.add_child(shape)
	body.position = pos
	return body

func _initialize() -> void:
	_run()

func _run() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	var flag: FlagPoint = (load("res://scenes/multiplayer/flag_point.tscn") as PackedScene).instantiate()
	root_node.add_child(flag)

	var ally := _make_body("ally", Vector3(0, 1, 0))
	var enemy := _make_body("enemy", Vector3(0, 1, 40)) # outside radius 12
	root_node.add_child(ally)
	root_node.add_child(enemy)

	for i in 30:
		await physics_frame

	check(flag.owner_team == "attackers", "uncontested ally presence -> attackers own flag")
	check(not flag.contested, "not contested with single team inside")

	# Enemy walks in -> contested -> neutral, nobody scores
	enemy.position = Vector3(0, 1, 0)
	for i in 30:
		await physics_frame
	check(flag.contested, "both teams inside -> contested")
	check(flag.owner_team == "", "contested -> ownership neutralized")

	# Enemy leaves -> attackers re-capture instantly
	enemy.position = Vector3(0, 1, 40)
	for i in 30:
		await physics_frame
	check(not flag.contested, "enemy left -> not contested")
	check(flag.owner_team == "attackers", "attackers re-capture after contest clears")

	# Ally leaves, enemy alone -> defenders own it
	ally.position = Vector3(0, 1, 40)
	enemy.position = Vector3(0, 1, 0)
	for i in 30:
		await physics_frame
	check(flag.owner_team == "defenders", "enemy alone -> defenders own flag")

	# Everyone leaves -> ownership holds (no decay — ponytail: add decay timer if hold-vs-neutral matters)
	enemy.position = Vector3(0, 1, 40)
	for i in 30:
		await physics_frame
	check(flag.owner_team == "defenders", "empty point keeps last owner (no decay)")

	if fails == 0:
		print("--- All flagpoint tests passed! ---")
		quit(0)
	else:
		printerr("--- %d flagpoint test(s) FAILED ---" % fails)
		quit(1)
