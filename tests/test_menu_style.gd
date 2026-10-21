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
	var sc = load("res://scenes/ui/main_menu.tscn") as PackedScene
	check(sc != null, "main_menu.tscn loads")
	var menu = sc.instantiate()
	root.add_child(menu)
	for i in 3:
		await process_frame

	# Title
	var poly: Label = menu.get_node_or_null("LeftNav/VBoxContainer/TitleContainer/TitleRow/TitleStack/TitleLine/Poly")
	check(poly != null and poly.get_theme_font("font") != null and poly.get_theme_font_size("font_size") == 48, "Title bold font + 48px override")

	# Left nav styles
	var play: Button = menu.get_node("LeftNav/VBoxContainer/BtnPlay")
	var loadout: Button = menu.get_node("LeftNav/VBoxContainer/BtnLoadout")
	var exitb: Button = menu.get_node("LeftNav/VBoxContainer/BtnExit")
	var pn: StyleBoxFlat = play.get_theme_stylebox("normal") as StyleBoxFlat
	check(pn != null and pn.bg_color.r > 0.9 and pn.bg_color.g < 0.6, "PLAY primary orange plate")
	check(play.get_theme_stylebox("hover") != play.get_theme_stylebox("normal"), "PLAY distinct hover style")
	var ln: StyleBoxFlat = loadout.get_theme_stylebox("normal") as StyleBoxFlat
	check(ln != null and ln.bg_color.v < 0.3, "Nav dark plate normal")
	var lh: StyleBoxFlat = loadout.get_theme_stylebox("hover") as StyleBoxFlat
	check(lh != null and lh.border_width_left == 3, "Nav hover has orange left accent")
	check(loadout.get_theme_stylebox("focus") is StyleBoxEmpty, "No ugly focus outline")

	# Right panel
	var giant: Button = menu.get_node("RightPanel/VBoxContainer/GiantPlayBtn")
	check((giant.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.r > 0.9, "Giant PLAY orange")
	check(giant.get_theme_stylebox("hover") != giant.get_theme_stylebox("normal"), "Giant PLAY distinct hover")
	var daily: PanelContainer = menu.get_node("RightPanel/VBoxContainer/DailyRewardPanel")
	check((daily.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_left == 8, "Daily panel rounded plate")

	# Play overlay
	var camp: Button = menu.get_node("PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/Sidebar/BtnCampaign")
	check(camp.get_theme_stylebox("hover") is StyleBoxFlat, "Overlay mode buttons styled")
	var start: Button = menu.get_node("PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/MapArea/MarginStart/BtnStartGame")
	check((start.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.r > 0.9, "Start game button orange primary")

	# Environment
	var we: WorldEnvironment = menu.get_node("3DEnvironment/WorldEnvironment")
	check(we.environment.fog_enabled, "Menu environment fog on")
	check(we.environment.tonemap_mode == Environment.TONE_MAPPER_FILMIC, "Filmic tonemap")
	check(we.environment.glow_enabled, "Soft glow on")
	var sun: DirectionalLight3D = menu.get_node("3DEnvironment/DirectionalLight3D")
	check(sun.light_color.r > 0.95 and sun.light_color.b < 0.8, "Warm key light")

	# Vignette
	check(menu.get_node_or_null("Vignette") is TextureRect, "Vignette overlay present")

	# Squad bar buttons styled (deferred one frame)
	await process_frame
	await process_frame
	var styled := 0
	var party := menu.get_node("PartyUI")
	for c in party.get_children():
		if c is HBoxContainer:
			for b in c.get_children():
				if b is Button and b.get_theme_stylebox("hover") is StyleBoxFlat:
					styled += 1
	check(styled >= 3, "Squad bar buttons styled (got %d)" % styled)

	menu.queue_free()
	print("RESULT: %s (%d fails / %d checks)" % ["OK" if fails == 0 else "FAIL", fails, checks])
	quit(1 if fails > 0 else 0)
