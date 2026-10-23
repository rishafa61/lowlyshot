extends SceneTree

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
	var sc = load("res://scenes/ui/settings_menu.tscn") as PackedScene
	check(sc != null, "settings_menu.tscn loads")
	var menu = sc.instantiate()
	root.add_child(menu)
	for i in 3:
		await process_frame

	# Check vignette
	var vig = menu.get_node_or_null("SettingsVignette")
	check(vig is TextureRect, "Settings vignette exists")

	# Windowed toggle (inverted fullscreen): label + semantics
	var fs_check = menu.get("check_fullscreen") as CheckButton
	check(fs_check != null, "Windowed CheckButton exists")
	var fs_label: Label = null
	for lbl in menu.find_children("*", "Label", true, false):
		if lbl.text == "Windowed":
			fs_label = lbl
			break
	check(fs_label != null and fs_label.text == "Windowed", "Visual tab shows Windowed toggle")
	var gs = root.get_node("GlobalSettings")
	gs.set_windowed(false)
	check(not gs.windowed and gs.fullscreen, "Default launches fullscreen (windowed=false)")
	# Drive through the toggle itself (set_pressed emits toggled -> _on_fullscreen_toggled)
	fs_check.set_pressed_no_signal(false)
	fs_check.button_pressed = true # ON = windowed
	check(gs.windowed and not gs.fullscreen, "Toggle ON flips to windowed")
	check(fs_check.text == "On", "Toggle label reads On in windowed mode")
	fs_check.button_pressed = false # OFF = fullscreen
	check(not gs.windowed and gs.fullscreen, "Toggle OFF flips back to fullscreen")
	check(fs_check.text == "Off", "Toggle label reads Off in fullscreen mode")

	# Check Visual tab row plates
	var vis_panel = menu.get_node("Content/TabVisualPanel")
	var vis_plates := 0
	for c in vis_panel.get_children():
		if c is PanelContainer:
			vis_plates += 1
	check(vis_plates >= 5, "Visual tab rows wrapped in plate cards (got %d)" % vis_plates)

	# Check Audio tab row plates
	var aud_panel = menu.get_node("Content/TabAudioPanel")
	var aud_plates := 0
	for c in aud_panel.get_children():
		if c is PanelContainer:
			aud_plates += 1
	check(aud_plates >= 3, "Audio tab rows wrapped in plate cards (got %d)" % aud_plates)

	# Check Gameplay tab row plates
	var gp_panel = menu.get_node("Content/TabGameplayPanel")
	var gp_plates := 0
	for c in gp_panel.get_children():
		if c is PanelContainer:
			gp_plates += 1
	check(gp_plates >= 2, "Gameplay tab rows wrapped in plate cards (got %d)" % gp_plates)

	# Check slider style: grabber_area override
	var slider: HSlider = menu.slider_bgm
	var grab_sb: StyleBoxFlat = slider.get_theme_stylebox("grabber_area") as StyleBoxFlat
	check(grab_sb != null and grab_sb.bg_color.r > 0.9, "Slider has orange fill area override")

	# Check option button style
	var opt: OptionButton = menu.get_node("Content/TabVisualPanel").find_child("OptGraphics", true, false)
	check(opt != null, "OptGraphics found")
	if opt != null:
		check(opt.get_theme_font_size("font_size") >= 18, "OptionButton font scaled up to >= 18px")

	menu.queue_free()
	print("RESULT: %s (%d fails / %d checks)" % ["OK" if fails == 0 else "FAIL", fails, checks])
	quit(1 if fails > 0 else 0)
