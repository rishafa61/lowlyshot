extends CanvasLayer

func _ready():
	hide()

func _input(event):
	if event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause():
	var is_mp = multiplayer.has_multiplayer_peer() or get_tree().current_scene is MultiplayerManager
	
	if is_mp:
		# Multiplayer mode: do NOT freeze game tree, just overlay the menu
		visible = not visible
		if visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		# Singleplayer mode: freeze tree as normal
		var is_paused = get_tree().paused
		get_tree().paused = not is_paused
		if get_tree().paused:
			show()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			hide()
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_resume_pressed():
	toggle_pause()

func _on_main_menu_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


var settings_instance = null

func _on_settings_pressed():
	# Instead of changing scenes and destroying the game state, we spawn the UI on top!
	if settings_instance == null:
		var settings_scene = load("res://scenes/ui/settings_menu.tscn")
		settings_instance = settings_scene.instantiate()
		add_child(settings_instance)
		
		# Override the Back button behavior so it just deletes the UI instead of changing scenes
		settings_instance.btn_back.pressed.disconnect(settings_instance._on_back_pressed)
		settings_instance.btn_back.pressed.connect(_close_settings)
		
	$CenterContainer.hide() # Hide pause menu buttons
	$Background.hide()
	settings_instance.show()

func _close_settings():
	if settings_instance:
		settings_instance.hide()
	$Background.show()
	$CenterContainer.show()

