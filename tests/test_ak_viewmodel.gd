# AK47 world model + anim viewmodel wiring: pullout -> idle loop -> reload -> hit.
# Also covers: re-equip after respawn (shared-library bug), arms/gun idle sync,
# and reload restoring the authored weapon transform.
extends SceneTree

var fails: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	_run()

func _run() -> void:
	var player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.position = Vector3(0, 1, 0)
	root.add_child(player)
	await process_frame
	await physics_frame

	check(player.current_weapon_instance != null, "weapon instance exists")
	check(player.current_weapon_instance.name == "AK47Viewmodel",
		"local player holds VIEWMODEL (got %s)" % player.current_weapon_instance.name)
	check(player.weapon_anim != null, "AnimationPlayer found on viewmodel")
	var va: AnimationPlayer = player.weapon_anim
	check(va != null and va.has_animation("vm/AK_Idle_Loop"), "looped idle duplicate created")
	check(va.current_animation.ends_with("AK_Pullout"), "pullout plays on equip (got %s)" % va.current_animation)

	# Wait past pullout (0.96s) -> finished handler -> idle loop
	for i in 80:
		await physics_frame
	check(va.current_animation.ends_with("AK_Idle_Loop"), "auto-returns to idle loop after pullout (got %s)" % va.current_animation)
	check(va.get_animation("vm/AK_Idle_Loop").loop_mode == Animation.LOOP_LINEAR, "idle loop is LOOP_LINEAR")

	# Arms and gun idle loops must share one length to stay phase-locked
	var vg: AnimationPlayer = player.gun_anim
	check(vg != null, "gun AnimationPlayer found")
	if vg != null:
		check(absf(vg.get_animation("vm/AK_Idle_Loop").length - va.get_animation("vm/AK_Idle_Loop").length) < 0.001,
			"arms/gun idle loops share one length (%0.3f vs %0.3f)" % [
				vg.get_animation("vm/AK_Idle_Loop").length, va.get_animation("vm/AK_Idle_Loop").length])

	# Reload
	player.start_reload()
	check(va.current_animation.ends_with("AK_Reload"), "reload plays AK_Reload")
	check(absf(va.speed_scale - va.get_animation("vm/AK_Reload").length / player.get_active_reload_duration()) < 0.01,
		"reload speed scaled to weapon reload duration")
	await physics_frame
	await physics_frame
	player.finish_reload()
	check(va.current_animation.ends_with("AK_Idle_Loop"), "returns to idle after reload")

	# Fire
	player.shoot_gun()
	check(vg.current_animation.ends_with("AK_Hit"), "hit plays AK_Hit on shot (gun)")
	check(va.current_animation.ends_with("AK_Idle_Loop"), "arms keep idle hold on shot (no AK_Hit_001 yet)")

	# Reload must restore the authored weapon transform (user offsets root in editor)
	player.start_reload()
	var base: Transform3D = player.weapon_base_transform
	player.finish_reload()
	var now: Transform3D = player.current_weapon_instance.transform
	check(now.origin.distance_to(base.origin) < 0.001 and now.basis.is_equal_approx(base.basis),
		"reload restores authored weapon transform (got %s)" % now.origin)

	# Inspect: Y-bound one-shot, returns to idle loop on finish
	player.inspect_weapon()
	check(va.current_animation.ends_with("AK_Inspect"), "inspect plays AK_Inspect (got %s)" % va.current_animation)
	check(vg.current_animation.ends_with("AK_Inspect"), "gun plays inspect in sync (got %s)" % vg.current_animation)
	check(player._inspecting, "inspect flag set while inspecting")
	check(InputMap.has_action("inspect"), "inspect action exists in InputMap")
	var y_bound := false
	for ev in InputMap.action_get_events("inspect"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_Y:
			y_bound = true
	check(y_bound, "inspect bound to physical Y key")
	player.inspect_weapon() # re-press mid-inspect must not error
	check(player._inspecting, "inspect flag survives re-press")
	player._on_weapon_anim_finished("vm/AK_Inspect")
	check(va.current_animation.ends_with("AK_Idle_Loop"), "inspect returns to idle loop (got %s)" % va.current_animation)
	check(not player._inspecting, "inspect flag cleared on finish")
	player.inspect_weapon()
	player.start_reload()
	check(not player._inspecting, "reload cancels inspect pullback")
	player.finish_reload()

	# Scope: no scope clips anywhere; scoped shot = plain AK_Hit
	check(not va.has_animation("vm/AK_Scope"), "arms has no vm/AK_Scope")
	check(not vg.has_animation("vm/AK_Scope"), "gun has no vm/AK_Scope")
	check(not va.has_animation("vm/AK_Scope_Hit"), "arms has no vm/AK_Scope_Hit")
	check(not vg.has_animation("vm/AK_Scope_Hit"), "gun has no vm/AK_Scope_Hit")
	player.is_aiming = true
	player.shoot_gun()
	check(vg.current_animation.ends_with("AK_Hit"), "scoped shot plays plain AK_Hit on gun")
	check(va.current_animation.ends_with("AK_Idle_Loop"), "arms keep idle grip on scoped shot")
	player._on_weapon_anim_finished("vm/AK_Hit")
	check(vg.current_animation.ends_with("AK_Idle_Loop"), "shot returns to idle loop")
	player.is_aiming = false

	# Coded ADS: real input path — holder converges to WEAPON_POS_ADS
	player.rotation = Vector3.ZERO
	Input.action_press("aim")
	for i in 120: await physics_frame
	var holder: Node3D = player.get("weapon_holder")
	check(player.get("is_aiming"), "aim input sets is_aiming")
	var gs := root.get_node("/root/GlobalSettings")
	var holder_err: Vector3 = holder.position - (player.WEAPON_POS_ADS + Vector3(gs.ads_offset_x, 0.0, gs.ads_offset_z))
	check(holder_err.length() < 0.05, "scoped holder reaches WEAPON_POS_ADS + user offset (err %.3fm)" % holder_err.length())
	check(va.current_animation.ends_with("AK_Idle_Loop"), "scoped keeps idle grip playing")
	check(va.speed_scale == 1.0 and vg.speed_scale == 1.0, "scoped idle keeps swaying on arms and gun")
	Input.action_release("aim")
	for i in 30: await physics_frame
	check(va.speed_scale == 1.0 and vg.speed_scale == 1.0, "un-scoping keeps idle playback running")
	for i in 30: await physics_frame
	var gs2 := root.get_node("/root/GlobalSettings")
	var hip_err: Vector3 = holder.position - (player.WEAPON_POS_HIP + Vector3(gs2.hip_offset_x, gs2.hip_offset_y, gs2.hip_offset_z))
	check(hip_err.length() < 0.05, "un-scoping returns holder to WEAPON_POS_HIP + user offset (err %.3fm)" % hip_err.length())

	# Re-equip (simulates respawn): fresh instance must still wire arms+gun anims
	player.update_weapon_model(player.Slot.RIFLE)
	await process_frame
	await physics_frame
	check(player.weapon_anim != null, "re-equip still wires arms AnimationPlayer (respawn bug)")
	check(player.gun_anim != null and player.gun_anim != player.weapon_anim, "re-equip still wires gun AnimationPlayer")
	check(player.weapon_anim.current_animation.ends_with("AK_Pullout"), "re-equip replays pullout")
	# Pullout gates scope/shoot until the equip anim ends
	var mag_pre: int = player.weapons[player.get("active_slot")]["mag"]
	player.shoot_gun()
	check(player.weapons[player.get("active_slot")]["mag"] == mag_pre, "pullout blocks shooting")
	Input.action_press("aim")
	for i in 5: await physics_frame
	check(not player.get("is_aiming"), "pullout blocks scoping")
	Input.action_release("aim")
	for i in 90: await physics_frame # pullout finishes (~0.96s)
	player.shoot_gun()
	check(player.weapons[player.get("active_slot")]["mag"] == mag_pre - 1, "shooting works after pullout ends")
	player.start_reload()
	check(player.weapon_anim.current_animation.ends_with("AK_Reload"), "re-equip reload plays Blender clip (not Godot dip)")
	check(player.reload_tween == null or not player.reload_tween.is_valid(), "no Godot reload dip when Blender anim present")

	# Puppet sees the WORLD model, not the viewmodel
	var puppet = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	puppet.position = Vector3(3, 1, 0)
	root.add_child(puppet)
	await process_frame
	await physics_frame
	puppet.is_puppet = true
	puppet.update_weapon_model(player.Slot.RIFLE)
	await process_frame
	await physics_frame
	check(puppet.current_weapon_instance.name == "Ak47",
		"puppet holds world model (got %s)" % puppet.current_weapon_instance.name)
	check(puppet.weapon_anim == null or not puppet.weapon_anim.has_animation("vm/AK_Idle_Loop"),
		"puppet has no viewmodel anim wiring")

	# Shadow / client-side isolation checks
	check(player._shadow_body != null, "local player has _shadow_body")
	var vm_shadow_count := 0
	for gi in player.current_weapon_instance.find_children("*", "GeometryInstance3D", true, false):
		if (gi as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			vm_shadow_count += 1
	check(vm_shadow_count == 0, "all viewmodel meshes have cast_shadow = OFF (got %d on)" % vm_shadow_count)
	var shadow_body_flags := 0
	if player._shadow_body != null:
		for gi in player._shadow_body.find_children("*", "GeometryInstance3D", true, false):
			if (gi as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				shadow_body_flags += 1
	check(shadow_body_flags == 0, "all local shadow body meshes have cast_shadow = SHADOWS_ONLY")
	player.die()
	check(player._shadow_body != null and (player._shadow_body as HumanBody).get_current_anim() == "Death",
		"die plays Death anim on shadow body")
	player.respawn()
	check(player._shadow_body != null and (player._shadow_body as HumanBody).get_current_anim() == "Idle_Rifle",
		"respawn resets shadow body anim to Idle_Rifle")
	var puppet_shadow_on := 0
	for gi in puppet.current_weapon_instance.find_children("*", "GeometryInstance3D", true, false):
		if (gi as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			puppet_shadow_on += 1
	check(puppet_shadow_on == 0, "puppet world model keeps normal shadow casting")

	# World model size sanity (manual compose; skinned mesh global_transform is unreliable)
	var world = (load("res://scenes/weapons/main/ak47.tscn") as PackedScene).instantiate()
	root.add_child(world)
	var wrapper = world.get_node("Model")
	var raw := AABB(Vector3(-3.167784, -2.586007, 2.969146), Vector3(0.779196, 2.604459, 7.676233))
	var world_aabb: AABB = wrapper.transform * raw
	check(absf(world_aabb.size.z - 0.87) < 0.02, "world AK length ~0.87m (got %0.3f)" % world_aabb.size.z)
	check(absf(world_aabb.position.z + world_aabb.size.z / 2.0) < 0.02, "world AK centered on origin")

	# Viewmodel offset tuner — LIVE mode over the player: scoped edit mode forced
	var va2: AnimationPlayer = player.get("weapon_anim")
	var vg2: AnimationPlayer = player.get("gun_anim")
	va2.play("vm/AK_Idle_Loop") # ensure idle is the current action (prior sections may leave reload/hit playing)
	vg2.play("vm/AK_Idle_Loop")
	var ed = (load("res://scenes/ui/viewmodel_offset.tscn") as PackedScene).instantiate()
	root.add_child(ed)
	for i in 30: await physics_frame
	check(player.get("viewmodel_edit_mode") == "ads", "ads tuner forces viewmodel_edit_mode")
	check(ed.get_node("World").visible == false, "offset tuner hides standalone rig in live mode")
	check(va2.speed_scale == 0.0 and vg2.speed_scale == 0.0, "offset tuner freezes idle on arms and gun")
	var tune_err: Vector3 = holder.position - (player.WEAPON_POS_ADS + Vector3(gs.ads_offset_x, gs.ads_offset_y, gs.ads_offset_z))
	check(tune_err.length() < 0.05, "offset tuner holds holder at scoped offset (err %.3fm)" % tune_err.length())
	ed._close()
	await physics_frame
	check(player.get("viewmodel_edit_mode") == "", "closing tuner clears viewmodel_edit_mode")

	# Hip tuner: hip pose, idle keeps swaying, holder at WEAPON_POS_HIP + hip offset
	var edh = (load("res://scenes/ui/viewmodel_offset.tscn") as PackedScene).instantiate()
	edh.mode = "hip"
	root.add_child(edh)
	for i in 30: await physics_frame
	check(player.get("viewmodel_edit_mode") == "hip", "hip tuner forces hip mode")
	check(va2.speed_scale == 1.0, "hip tuner keeps idle sway playing (got %.2f)" % va2.speed_scale)
	var hip_tune_err: Vector3 = holder.position - (player.WEAPON_POS_HIP + Vector3(gs.hip_offset_x, gs.hip_offset_y, gs.hip_offset_z))
	check(hip_tune_err.length() < 0.05, "hip tuner holds holder at hip offset (err %.3fm)" % hip_tune_err.length())
	edh._close()

	# Standalone fallback (no player in tree): preview rig at user offset
	player.queue_free()
	await physics_frame
	var ed2 = (load("res://scenes/ui/viewmodel_offset.tscn") as PackedScene).instantiate()
	root.add_child(ed2)
	await process_frame
	var eh: Node3D = ed2.get_node("World/Holder")
	check(eh.position.is_equal_approx(Vector3(gs.ads_offset_x, gs.ads_offset_y, gs.ads_offset_z)), "offset tuner standalone rig at user offset (got %s)" % eh.position)
	var paused2 := true
	for ap: AnimationPlayer in eh.get_child(0).find_children("*", "AnimationPlayer"):
		if ap.has_animation("vm/AK_Idle_Loop") and not ap.current_animation.ends_with("AK_Idle_Loop"):
			paused2 = false
	check(paused2, "offset tuner standalone plays frozen idle on both rigs")
	ed2.queue_free()

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
