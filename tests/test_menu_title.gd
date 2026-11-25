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

	var poly: Label = menu.get_node_or_null("LeftNav/VBoxContainer/TitleContainer/TitleRow/TitleStack/TitleLine/Poly")
	var shot: Label = menu.get_node_or_null("LeftNav/VBoxContainer/TitleContainer/TitleRow/TitleStack/TitleLine/Shot")
	var sub: Label = menu.get_node_or_null("LeftNav/VBoxContainer/TitleContainer/TitleRow/TitleStack/SubTitle")
	var badge: Control = menu.get_node_or_null("LeftNav/VBoxContainer/TitleContainer/TitleRow/Badge")
	check(poly != null and poly.text == "LOWLY", "LOWLY label present")
	check(shot != null and shot.text == "SHOT", "SHOT label present")
	check(poly != null and poly.label_settings != null and poly.label_settings.font_size == 46, "LOWLY large 46px stylized")
	check(shot != null and shot.label_settings != null and shot.label_settings.font_color.r > 0.9 and shot.label_settings.font_color.g < 0.7, "SHOT accent orange")
	check(sub != null and sub.label_settings.font_size == 13, "Sub-title small spaced")
	check(badge != null and badge.has_method("_draw"), "Tactical 4-stripe badge present")
	check(badge.custom_minimum_size.y == 50.0, "Badge 50px tall")

	# Buttons still wired after restructure
	check(menu.get_node_or_null("LeftNav/VBoxContainer/BtnPlay") != null, "BtnPlay intact")
	check(menu.get_node_or_null("LeftNav/VBoxContainer/BtnLoadout") != null, "BtnLoadout intact")
	check(menu.get_node_or_null("LeftNav/VBoxContainer/BtnExit") != null, "BtnExit intact")
	menu.queue_free()

	print("RESULT: %s (%d fails / %d checks)" % ["OK" if fails == 0 else "FAIL", fails, checks])
	quit(1 if fails > 0 else 0)
