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

func _center_check(dialog: Control, panel: Control, label: String) -> void:
	check(is_instance_valid(dialog) and dialog.size.x > 0.0 and dialog.size.y > 0.0,
		label + ": root sized to viewport (%s)" % dialog.size)
	if not is_instance_valid(panel):
		check(false, label + ": panel found")
		return
	var exp := (dialog.size - panel.size) * 0.5
	var diff := (panel.global_position - exp).length()
	check(diff < 4.0, label + ": panel centered (pos=%s, expected=%s)" % [panel.global_position, exp])

func _initialize() -> void:
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	canvas.layer = 120

	# Friend invite dialog
	var invite = load("res://scenes/ui/friend_invite_dialog.gd").new()
	canvas.add_child(invite)
	var browser = load("res://scenes/ui/lobby_browser_dialog.gd").new()
	canvas.add_child(browser)
	for i in 3:
		await process_frame

	var vp := root.get_viewport().get_visible_rect().size
	check(invite.size == vp, "Invite dialog root matches viewport size")
	var invite_panel: Control = null
	var browser_panel: Control = null
	for d in invite.get_children():
		if d is CenterContainer:
			for p in d.get_children():
				invite_panel = p
	for d in browser.get_children():
		if d is CenterContainer:
			for p in d.get_children():
				browser_panel = p
	_center_check(invite, invite_panel, "InviteFriend")
	_center_check(browser, browser_panel, "LobbyBrowser")

	# Resize keeps it centered
	root.get_viewport().size = Vector2(1280, 720)
	await process_frame
	await process_frame
	_center_check(invite, invite_panel, "InviteFriend-resized")
	_center_check(browser, browser_panel, "LobbyBrowser-resized")

	invite.queue_free()
	browser.queue_free()
	canvas.queue_free()

	print("RESULT: %s (%d fails / %d checks)" % ["OK" if fails == 0 else "FAIL", fails, checks])
	quit(1 if fails > 0 else 0)
