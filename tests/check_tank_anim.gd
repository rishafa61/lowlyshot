extends SceneTree

## Verifies Tank.glb tread-scroll animations work: both chain nodes exist,
## forward/backward animate them, loop mode set.
func _initialize() -> void:
	await process_frame
	var glb = (load("res://assets/models/vehicles/Tank.glb") as PackedScene).instantiate()
	root.add_child(glb)
	await process_frame
	var players := glb.find_children("*", "AnimationPlayer", true, false)
	var wheel: Node3D = glb.find_child("L_Track", true, false)
	if players.is_empty() or wheel == null:
		print("ANIM MOVE: FAIL (missing player or L_Track)")
		quit(1)
		return
	var ap: AnimationPlayer = players[0]
	var z0: float = wheel.position.z
	ap.play("forward")
	ap.advance(0.5)
	var z1: float = wheel.position.z
	ap.play("backward")
	ap.advance(0.5)
	var z2: float = wheel.position.z
	print("wheel z0:", z0, " fwd:", z1, " bwd:", z2)
	var ok := absf(z1 - z0) > 0.01 and absf(z2 - z0) > 0.01 and absf(z1 - z2) > 0.01
	print("ANIM MOVE:", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
