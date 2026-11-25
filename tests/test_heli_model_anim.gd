extends SceneTree

# Helicopter.glb swap: mesh instanced at root, wrapper transform, anim state
# machine (Idle/Idle_Rotor/Fly/OD_Idle loops, Start/End_Rotor + O/C_Door
# one-shots), X-key door toggle, MG nodes kept at the new door.

var fails: int = 0
var checks: int = 0

func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FAIL: %s" % msg)
	else:
		print("  PASS: %s" % msg)

func _initialize() -> void:
	await process_frame
	var sc = load("res://scenes/vehicles/helicopter.tscn") as PackedScene
	check(sc != null, "helicopter.tscn loads (tscn valid)")
	# Floor so is_grounded() ray hits
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 10, 200)
	floor_shape.shape = box
	floor_shape.position.y = -5.0
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	var heli = sc.instantiate()
	root.add_child(heli)
	for i in 3:
		await physics_frame
	# Headless quirk: node _process doesn't auto-run in -s scripts — drive the
	# same entry point the game's _process drives, then assert the parked state.
	heli._update_anim()

	# --- Old procedural mesh gone, new glb instanced ---
	var model := heli.get_node("Model")
	check(model.find_children("RotorFront", "Node3D", true, false).is_empty(),
		"old RotorFront spinner removed")
	check(model.find_children("Fuselage*", "MeshInstance3D", true, false).is_empty()
		and model.find_children("Nose*", "MeshInstance3D", true, false).is_empty()
		and model.find_children("Glass*", "MeshInstance3D", true, false).is_empty()
		and model.find_children("PassengerSeat*", "MeshInstance3D", true, false).is_empty(),
		"old box fuselage/nose/glass/bench meshes removed")
	var heli_mesh := heli.get_node_or_null("HeliMesh")
	check(heli_mesh != null, "HeliMesh (glb instance) present")
	check(model.find_children("MG", "MeshInstance3D", true, false).size() == 1,
		"Model/MG kept (door gun gameplay node)")

	# --- Wrapper: USER-TUNED in editor (2026-11-09, verified correct) — pin it ---
	var wrap: Transform3D = heli_mesh.transform
	check(absf(wrap.basis.x.x + 1.2) < 0.01 and absf(wrap.basis.y.y - 1.2) < 0.01
		and absf(wrap.basis.z.z + 1.2) < 0.01,
		"wrapper keeps user scale 1.2 (got %s)" % wrap.basis.get_scale())
	check(wrap.basis.x.x < -0.7 and wrap.basis.z.z < -0.7,
		"wrapper keeps user yaw 180 (nose -Z)")
	check(absf(wrap.origin.y - 3.1232576) < 0.01 and absf(wrap.origin.x - 0.0051202774) < 0.01,
		"wrapper keeps user pos (0.0051, 3.1233, 0)")
	var model_node := heli.get_node("Model") as Node3D
	var mt: Transform3D = model_node.transform
	check(absf(mt.basis.x.x - 1.1) < 0.01 and absf(mt.basis.y.y - 1.288) < 0.01
		and absf(mt.basis.z.z - 1.003) < 0.01,
		"Model keeps user MG-frame scale (1.1, 1.288, 1.003)")
	check(absf(mt.origin.z + 6.729251) < 0.01 and absf(mt.origin.y + 0.21690226) < 0.01,
		"Model keeps user MG-frame origin")

	# Orientation via skinned-mesh ground truth: rotor/door BONE world positions
	var skel := heli.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bones := {}
	for i in skel.get_bone_count():
		var bp: Transform3D = skel.global_transform * skel.get_bone_global_pose(i)
		bones[skel.get_bone_name(i)] = bp.origin
	var fz: float = bones["f.rotor"].z
	var rz: float = bones["r.rotor"].z
	check(fz < rz - 3.0, "front rotor forward of rear -> nose -Z (%.1f vs %.1f)" % [fz, rz])
	var sep: float = absf(fz - rz)
	check(sep > 10.0 and sep < 18.0, "rotor separation in tandem-rotor range (%.2f)" % sep)
	check(bones["f.rotor"].y < bones["r.rotor"].y, "front pylon lower than rear (CH-47 profile)")
	check(bones["door"].y < bones["f.rotor"].y and absf(bones["door"].z - rz) < 2.0,
		"door sits low, beside the rear pylon (%.1f, %.1f)" % [bones["door"].y, bones["door"].z])

	# Door MGs: existence + cams only — placement is user-tuned in the editor
	# (guns intentionally sit wherever the user mounts them, not necessarily at
	# the glb's door bone).
	var mg := heli.get_node("Model/MG") as Node3D
	var mg2 := heli.get_node("Model/MG2") as Node3D
	check(mg != null and mg2 != null
		and heli.get_node_or_null("Model/MG/GunnerCam") != null
		and heli.get_node_or_null("Model/MG2/GunnerCam") != null,
		"door MGs + GunnerCams kept (user-placed)")
	check(heli.get_node_or_null("Model/MG/GunnerCam") != null
		and heli.get_node_or_null("Model/MG2/GunnerCam") != null, "door GunnerCams kept")

	# --- Animation wiring ---
	var anim: AnimationPlayer = heli.get("_anim")
	check(anim != null, "AnimationPlayer wired")
	print("DBG grounded=", heli.is_grounded(), " pos=", heli.global_position, " current=", anim.current_animation if anim else "nil")
	if anim != null:
		for clip in ["Idle", "Idle_Rotor", "Fly", "OD_Idle", "Start_Rotor", "End_Rotor", "O_Door", "C_Door"]:
			check(anim.has_animation(clip), "clip '%s' available" % clip)
		check(anim.current_animation == "Idle", "starts in Idle (parked, engine off)")
		for clip in ["Idle", "Idle_Rotor", "Fly", "OD_Idle"]:
			check(anim.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, "'%s' loops" % clip)
		for clip in ["Start_Rotor", "End_Rotor", "O_Door", "C_Door"]:
			check(anim.get_animation(clip).loop_mode == Animation.LOOP_NONE, "'%s' is a one-shot" % clip)

	# --- State machine spec ---
	# Engine start (pilot seated) -> Start_Rotor one-shot -> Idle_Rotor.
	heli.engine_power = 0.5
	heli._update_anim()
	check(anim.current_animation == "Start_Rotor", "engine spool-up fires Start_Rotor")
	check(heli.get("_anim_oneshot") == "Start_Rotor", "Start_Rotor latched")
	heli._update_anim() # still spooling: no re-fire
	check(anim.current_animation == "Start_Rotor", "Start_Rotor does not re-fire while playing")
	heli._on_anim_finished("Start_Rotor")
	check(anim.current_animation == "Idle_Rotor", "Start_Rotor ends -> Idle_Rotor (grounded)")

	# Takeoff -> Fly. Landing -> Idle_Rotor.
	heli.global_position = Vector3(0, 30, 0)
	heli._update_anim()
	check(anim.current_animation == "Fly", "airborne -> Fly")
	heli.global_position = Vector3(0, 0.36, 0) # settled rest height; exact floor level makes the ray degenerate
	heli._update_anim()
	check(anim.current_animation == "Idle_Rotor", "touchdown -> Idle_Rotor")

	# Engine off -> End_Rotor one-shot -> Idle.
	heli.engine_power = 0.0
	heli._update_anim()
	check(anim.current_animation == "End_Rotor", "power loss fires End_Rotor")
	heli._on_anim_finished("End_Rotor")
	check(anim.current_animation == "Idle", "End_Rotor ends -> Idle")

	# --- X-key door toggle ---
	var door_col := heli.get_node("DoorCollision") as CollisionShape3D
	check(door_col != null and heli.get("_door_collision") == door_col, "DoorCollision wired")
	check(door_col.disabled, "door collision off while closed")
	# Blocked while a one-shot plays: Start_Rotor running, toggle must no-op.
	heli.engine_power = 0.5
	heli._update_anim() # Start_Rotor again
	var ev_block := InputEventKey.new()
	ev_block.keycode = KEY_X
	ev_block.pressed = true
	heli._unhandled_input(ev_block)
	check(heli.get("_door_open") == false, "X ignored while a one-shot plays")
	heli._on_anim_finished("Start_Rotor") # settle to Idle_Rotor

	# No occupant: X must do nothing (no door without a player aboard)
	var ev_none := InputEventKey.new()
	ev_none.keycode = KEY_X
	ev_none.pressed = true
	heli._unhandled_input(ev_none)
	check(heli.get("_door_open") == false, "X ignored with nobody aboard")

	# Seat a dummy player, toggle open
	var mock := GDScript.new()
	mock.source_code = "extends Node3D\nvar hud: Node = null\nfunc _ready(): hud = Node.new()\nfunc enter_aircraft(_s): pass\nfunc switch_aircraft_seat(_s): pass\nfunc exit_aircraft(_p, _d, _v=Vector3.ZERO): pass\n"
	mock.reload()
	var player := Node3D.new()
	player.set_script(mock)
	root.add_child(player)
	await process_frame
	heli.net_sync_enter(player, 1)
	var ev_open := InputEventKey.new()
	ev_open.keycode = KEY_X
	ev_open.pressed = true
	heli._unhandled_input(ev_open)
	check(heli.get("_door_open") == true, "X opens the door with a player aboard")
	var door_anim: AnimationPlayer = heli.get("_door_anim")
	check(door_anim != null, "door swing player wired")
	check(door_anim.current_animation == "O_Door", "opening plays O_Door on the door player")
	check(anim.current_animation == "Idle_Rotor", "rotors keep spinning during the swing")
	heli._unhandled_input(ev_open) # mid-swing press must not interrupt
	check(heli.get("_door_open") == true, "X ignored mid-swing")
	await process_frame # flush set_deferred on the hitbox
	check(not door_col.disabled, "door collision on while open")
	heli._on_door_anim_finished("O_Door")
	check(anim.current_animation == "OD_Idle", "O_Door ends -> OD_Idle holds")
	heli._update_anim()
	check(anim.current_animation == "OD_Idle", "OD_Idle holds (door-open idle)")

	# Door open + flying: OD_Idle is a GROUNDED pose; airborne keeps Fly. Main
	# clips carry NO door tracks — the door bone is owned by the swing player,
	# so the last swing pose persists instead of snapping shut.
	var door_tracks_main := 0
	for clip in ["Idle", "Idle_Rotor", "Fly", "OD_Idle"]:
		for i in anim.get_animation(clip).get_track_count():
			if String(anim.get_animation(clip).track_get_path(i)).contains("door"):
				door_tracks_main += 1
	check(door_tracks_main == 0, "main clips carry no door tracks (swing player owns the door)")
	var rotor_tracks_cut := 0
	for i in door_anim.get_animation("O_Door").get_track_count():
		if String(door_anim.get_animation("O_Door").track_get_path(i)).contains("rotor"):
			rotor_tracks_cut += 1
	check(rotor_tracks_cut == 0, "door swing cut has no rotor tracks (rotors keep spinning)")
	check(door_anim.get_animation("O_Door").get_track_count() > 0, "door swing cut keeps the door bone")
	heli.global_position = Vector3(0, 30, 0)
	heli._update_anim()
	check(anim.current_animation == "Fly", "flying with door open keeps Fly (door pose persists)")
	heli.global_position = Vector3(0, 0.36, 0)
	heli._update_anim()
	check(anim.current_animation == "OD_Idle", "grounded again restores OD_Idle")

	# Toggle closed: C_Door -> back to base
	heli._unhandled_input(ev_open)
	check(heli.get("_door_open") == false, "X closes the door again")
	check(door_anim.current_animation == "C_Door", "closing plays C_Door on the door player")
	heli._on_door_anim_finished("C_Door")
	check(anim.current_animation == "Idle_Rotor", "C_Door ends -> back to base state")
	await process_frame
	check(door_col.disabled, "door collision off after closing")

	# Engine-off door cycle: OD_Idle -> C_Door -> Idle (engine-off base)
	heli.engine_power = 0.0
	heli._update_anim()
	check(anim.current_animation == "End_Rotor", "shutdown fires End_Rotor")
	heli._on_anim_finished("End_Rotor")
	heli._unhandled_input(ev_open)
	heli._on_door_anim_finished("O_Door")
	check(anim.current_animation == "OD_Idle", "door open while parked engineless -> OD_Idle")
	heli._unhandled_input(ev_open)
	heli._on_door_anim_finished("C_Door")
	check(anim.current_animation == "Idle", "door closed engineless -> Idle")

	# --- Camera: top-level pivot + hover lag state + physics interpolation ---
	check(heli.get_node("ChasePivot").top_level, "ChasePivot is top_level (world-space lag)")
	check(heli.physics_interpolation_mode == 1,
		"body physics interpolation ON (no 60 Hz pose judder while tilting)")
	heli.chase_cam.current = true
	heli.linear_velocity = Vector3.ZERO
	var tgt: Vector3 = heli.global_position + heli.global_basis * Vector3(0, 8.4176, 4.4891)
	heli._cam_pos = tgt + heli.global_basis * Vector3(0, 0, 10)
	heli.chase_pivot.global_position = heli._cam_pos
	heli._update_camera(1.0 / 60.0)
	var gap_steady: float = heli._cam_pos.distance_to(tgt)
	heli._cam_pos = tgt + heli.global_basis * Vector3(0, 0, 10)
	heli.chase_pivot.global_position = heli._cam_pos
	heli.linear_velocity = Vector3(0, 0, 24) # full-speed drift: deeper lag
	heli._update_camera(1.0 / 60.0)
	var gap_moving: float = heli._cam_pos.distance_to(tgt)
	check(gap_moving > gap_steady + 0.5,
		"camera trails harder while moving (%.2f vs %.2f)" % [gap_moving, gap_steady])

	# --- Mouse wheel chase-cam zoom ---
	heli.chase_cam.current = true
	heli.chase_arm.spring_length = 14.0
	var ev_zoom_in := InputEventMouseButton.new()
	ev_zoom_in.button_index = MOUSE_BUTTON_WHEEL_UP
	ev_zoom_in.pressed = true
	heli._unhandled_input(ev_zoom_in)
	check(heli.chase_arm.spring_length < 14.0, "wheel up zooms chase cam in")
	var ev_zoom_out := InputEventMouseButton.new()
	ev_zoom_out.button_index = MOUSE_BUTTON_WHEEL_DOWN
	ev_zoom_out.pressed = true
	for i in 40:
		heli._unhandled_input(ev_zoom_out)
	check(heli.chase_arm.spring_length == 30.0,
		"wheel down zooms out to the clamp (%.1f)" % heli.chase_arm.spring_length)
	heli.chase_cam.current = false
	heli.chase_arm.spring_length = 14.0
	heli._unhandled_input(ev_zoom_out)
	check(heli.chase_arm.spring_length == 14.0, "wheel ignored when chase cam not active")
	heli.chase_cam.current = true

	check(not heli.get("is_destroyed"), "controller intact")
	print("RESULT: %s (%d checks, %d fails)" % ["OK" if fails == 0 else "FAILED", checks, fails])
	quit(1 if fails > 0 else 0)
