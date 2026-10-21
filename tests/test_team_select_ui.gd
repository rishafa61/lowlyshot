extends SceneTree

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- Running test_team_select_ui ---")
	
	if root.get_node_or_null("/root/GlobalData") == null:
		var gd = Node.new()
		gd.set_script(load("res://scripts/global_data.gd"))
		gd.name = "GlobalData"
		root.add_child(gd)
		await process_frame
	
	var hud_scene = load("res://scenes/ui/multiplayer_hud.tscn")
	var hud = hud_scene.instantiate()
	root.add_child(hud)
	
	for i in 5:
		await process_frame
		
	assert(hud.side_picker != null, "side_picker exists")
	assert(hud.side_picker.visible, "side_picker starts visible")
	assert(hud.btn_attackers != null, "btn_attackers exists")
	assert(hud.btn_defenders != null, "btn_defenders exists")
	assert(hud.lbl_team_full != null, "lbl_team_full exists")
	
	assert(hud.btn_attackers.text == "SELECT", "btn_attackers text is SELECT")
	assert(hud.btn_defenders.text == "SELECT", "btn_defenders text is SELECT")
	
	# Verify title
	var title: Label = null
	for child in hud.side_picker.get_children():
		if child is Label and child.text == "SELECT TEAM":
			title = child
			break
	assert(title != null, "SELECT TEAM title found")
	
	print("RESULT: OK (team select UI verified)")
	quit(0)
