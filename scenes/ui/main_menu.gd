extends Control

const UI_ORANGE := Color(1.0, 0.44, 0.08)
const UI_PLATE := Color(0.115, 0.125, 0.15, 0.94)
const UI_PLATE_HOVER := Color(0.165, 0.18, 0.21, 0.97)
const UI_TEXT := Color(0.88, 0.9, 0.93)

@onready var btn_left_play = $LeftNav/VBoxContainer/BtnPlay
@onready var btn_giant_play = $RightPanel/VBoxContainer/GiantPlayBtn
@onready var btn_loadout = $LeftNav/VBoxContainer/BtnLoadout
@onready var btn_operator = $LeftNav/VBoxContainer/BtnOperator
@onready var btn_setting = $LeftNav/VBoxContainer/BtnSetting
@onready var btn_exit = $LeftNav/VBoxContainer/BtnExit
@onready var character_pivot = $"3DEnvironment"


# Play Overlay Nodes
@onready var play_overlay = $PlayOverlay
@onready var btn_close_play = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/Sidebar/BtnClosePlay
@onready var btn_campaign = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/Sidebar/BtnCampaign
@onready var btn_practice = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/Sidebar/BtnPractice
@onready var btn_multiplayer = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/Sidebar/BtnMultiplayer

@onready var map_list = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/MapArea/MapList
@onready var map_desc = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/MapArea/MapDesc
@onready var btn_start_game = $PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/MapArea/MarginStart/BtnStartGame

@onready var party_ui = $PartyUI
@onready var party_slots: Array = [$PartyUI/Slot1, $PartyUI/Slot2, $PartyUI/Slot3, $PartyUI/Slot4]
# standby slot 3D bodies removed: lobby keeps host pedestal; joined players show in-match only.
# ponytail: spawn in-match peer bodies from player_spawner on peer_connected / match join; add when netcode lands.

var selected_mode = "Practice"
var bots_toggle: CheckButton
var btn_update: Button
var maps = {
	"Campaign": [
		{"name": "Operation Sandstorm", "scene": "res://scenes/levels/campaign_map.tscn", "desc": "Infiltrate the trench, eliminate 5 hostiles, and reach the extraction zone."}
	],
	"Practice": [
		{"name": "Test Arena", "scene": "res://scenes/levels/test_arena.tscn", "desc": "A simple sandbox arena to practice movement and aim."}
	],
	"Multiplayer": [
		{"name": "Team Deathmatch", "scene": "res://scenes/levels/multiplayer_arena.tscn", "desc": "5v5 Arena. Pick a side, eliminate the enemy team."},
		{"name": "Ground War", "scene": "res://scenes/levels/ground_war.tscn", "desc": "10v10 King of the Hill. Capture the Flagpoint and hold it — first team to 300 points wins."},
		{"name": "Search & Destroy", "scene": "res://scenes/levels/search_and_destroy.tscn", "desc": "5v5 Round-based. Attackers plant the bomb at Site A or B; Defenders stop them. First to 5 rounds wins."},
		{"name": "Flying Scoutsman", "scene": "res://scenes/levels/flying_scoutsman.tscn", "desc": "Free-for-all sniper deathmatch. M700 only, low moon gravity. First to 40 kills wins."}
	]
}

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_apply_style()
	# Back in the menu = leave any online match (closes the peer; every return path ends here)
	var _ss = get_node_or_null("/root/SteamSync")
	if _ss and _ss.has_method("leave_steam_game"):
		_ss.leave_steam_game()
	# Root Control has no parent Control (child of Viewport Window):
	# anchors do not auto-size root, so pin to 0 and match window via deferred + resize signal.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	anchor_right = 0.0
	anchor_bottom = 0.0
	call_deferred("_apply_root_size")
	get_viewport().size_changed.connect(_apply_root_size)
	btn_left_play.pressed.connect(_on_play_pressed)
	btn_giant_play.pressed.connect(_on_play_pressed)
	btn_loadout.pressed.connect(_on_loadout_pressed)
	btn_operator.pressed.connect(_on_operator_pressed)
	btn_setting.pressed.connect(_on_setting_pressed)
	btn_exit.pressed.connect(_on_exit_pressed)

	play_overlay.hide()
	btn_close_play.pressed.connect(func():
		play_overlay.hide()
		party_ui.show()
	)
	
	btn_campaign.pressed.connect(func(): set_play_mode("Campaign"))
	btn_practice.pressed.connect(func(): set_play_mode("Practice"))
	btn_multiplayer.pressed.connect(func(): set_play_mode("Multiplayer"))
	
	map_list.item_selected.connect(_on_map_selected)
	btn_start_game.pressed.connect(_on_start_game_pressed)
	_init_update_button()
	_init_bots_toggle()
	
	set_play_mode("Practice")
	_init_party_system()
	_init_version_label()
	_init_profile_frame()
	_init_wallet_labels()

## Top-left profile frame: tactical military ID badge opening the player card.
func _init_profile_frame() -> void:
	var frame := Button.new()
	frame.name = "ProfileFrame"
	frame.custom_minimum_size = Vector2(250, 64)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.94)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.border_width_left = 3
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.20, 0.26, 0.35)
	frame.add_theme_stylebox_override("normal", sb)

	var hover := sb.duplicate()
	hover.bg_color = Color(0.12, 0.16, 0.22, 0.98)
	hover.border_color = UI_ORANGE
	frame.add_theme_stylebox_override("hover", hover)
	var pressed := sb.duplicate()
	pressed.bg_color = Color(0.06, 0.08, 0.11, 0.98)
	frame.add_theme_stylebox_override("pressed", pressed)
	frame.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.offset_top = 8
	row.offset_bottom = -8
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(row)

	var ins := PanelContainer.new()
	ins.custom_minimum_size = Vector2(44, 44)
	var ins_sb := StyleBoxFlat.new()
	ins_sb.bg_color = Color(0.12, 0.15, 0.20)
	ins_sb.border_width_left = 1
	ins_sb.border_width_top = 1
	ins_sb.border_width_right = 1
	ins_sb.border_width_bottom = 2
	ins_sb.border_color = UI_ORANGE
	ins_sb.corner_radius_top_left = 3
	ins_sb.corner_radius_top_right = 3
	ins_sb.corner_radius_bottom_left = 3
	ins_sb.corner_radius_bottom_right = 3
	ins.add_theme_stylebox_override("panel", ins_sb)
	ins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ins)

	var ins_vb := VBoxContainer.new()
	ins_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	ins_vb.add_theme_constant_override("separation", -2)
	ins_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ins.add_child(ins_vb)

	var star := Label.new()
	star.text = "◆"
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star.add_theme_font_size_override("font_size", 14)
	star.modulate = UI_ORANGE
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ins_vb.add_child(star)

	var lvl_lbl := Label.new()
	var prof = _prof()
	var s: Dictionary = prof.stats if prof else {}
	var xp: int = int(s.get("kills", 0)) * 100 + int(s.get("headshots", 0)) * 50 + int(s.get("wins", 0)) * 500 + int(s.get("matches", 0)) * 100
	var lvl: int = 1 + int(xp / 1000)
	lvl_lbl.text = "L%d" % lvl
	lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_lbl.add_theme_font_size_override("font_size", 11)
	lvl_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ins_vb.add_child(lvl_lbl)

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 1)
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_box)

	var pname: String = "Player"
	var ss = get_node_or_null("/root/SteamSync")
	if ss and ss.get("persona_name") != null and str(ss.persona_name) != "":
		pname = str(ss.persona_name)

	var name_lbl := Label.new()
	name_lbl.text = pname.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_box.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "DOSSIER // VIEW STATS"
	sub_lbl.add_theme_font_size_override("font_size", 10)
	sub_lbl.modulate = Color(0.35, 0.75, 0.85, 0.8)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_box.add_child(sub_lbl)

	add_child(frame)
	frame.anchor_left = 0.0
	frame.anchor_top = 0.0
	frame.anchor_right = 0.0
	frame.anchor_bottom = 0.0
	frame.offset_left = 60
	frame.offset_top = 20
	frame.offset_right = 310
	frame.offset_bottom = 84
	frame.pressed.connect(_on_profile_pressed)

func _on_profile_pressed() -> void:
	var existing = get_node_or_null("ProfileCardLayer")
	if existing != null:
		return
	var dialog_script = load("res://scenes/ui/player_card_dialog.gd")
	var layer := CanvasLayer.new()
	layer.name = "ProfileCardLayer"
	layer.set_script(dialog_script)
	add_child(layer)

## Live Cash / Gold pills in the right panel, fed by PlayerProfile.
func _prof() -> Node:
	return get_node_or_null("/root/PlayerProfile")

func _init_wallet_labels() -> void:
	var coin := get_node_or_null("RightPanel/VBoxContainer/CurrencyHBox/CoinPanel/Label") as Label
	var gem := get_node_or_null("RightPanel/VBoxContainer/CurrencyHBox/GemPanel/Label") as Label
	if coin == null or gem == null:
		return
	var prof := _prof()
	if prof == null:
		return
	var refresh := func():
		coin.text = "CASH: %d" % prof.cash
		gem.text = "GOLD: %d" % prof.gold
	refresh.call()
	prof.wallet_changed.connect(refresh)

func _init_version_label() -> void:
	var updater = get_node_or_null("/root/Updater")
	var v_str: String = updater.VERSION if updater and "VERSION" in updater else "1.0.2"
	var lbl_ver := Label.new()
	lbl_ver.text = "v%s" % v_str
	lbl_ver.add_theme_font_size_override("font_size", 13)
	lbl_ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	add_child(lbl_ver)
	lbl_ver.anchor_left = 0.0
	lbl_ver.anchor_top = 1.0
	lbl_ver.anchor_right = 0.0
	lbl_ver.anchor_bottom = 1.0
	lbl_ver.offset_left = 16
	lbl_ver.offset_bottom = -12
	lbl_ver.offset_top = -34
	lbl_ver.offset_right = 120

## 5v5 bot backfill toggle for online Team Deathmatch (host choice)
func _init_bots_toggle() -> void:
	bots_toggle = CheckButton.new()
	bots_toggle.text = "ADD BOTS (5v5 FILL)"
	bots_toggle.button_pressed = GlobalSettings.online_bots_enabled
	bots_toggle.toggled.connect(func(on):
		GlobalSettings.online_bots_enabled = on
		GlobalSettings.save_settings()
	)
	var map_area = map_list.get_parent()
	map_area.add_child(bots_toggle)
	map_area.move_child(bots_toggle, map_desc.get_index() + 1)

## In-game updater: silent check on menu load, button appears when outdated
func _init_update_button() -> void:
	var updater = get_node_or_null("/root/Updater")
	btn_update = Button.new()
	btn_update.text = "⬆ UPDATE GAME"
	btn_update.custom_minimum_size = Vector2(170, 42)
	btn_update.visible = false
	btn_update.pressed.connect(func():
		btn_update.disabled = true
		btn_update.text = "DOWNLOADING..."
		_toast("Downloading update, don't close the game...")
		if not updater.download_update():
			btn_update.disabled = false
			btn_update.text = "⬆ UPDATE GAME"
	)
	party_ui.add_child(btn_update)
	btn_update.anchor_left = 1.0
	btn_update.anchor_top = 0.0
	btn_update.anchor_right = 1.0
	btn_update.anchor_bottom = 0.0
	btn_update.offset_left = -200
	btn_update.offset_top = 16
	btn_update.offset_right = -30
	btn_update.offset_bottom = 58
	if updater == null:
		return
	updater.update_check_done.connect(func(available, latest):
		btn_update.visible = available
		btn_update.text = "⬆ UPDATE TO %s" % latest
		btn_update.disabled = false
		if not available:
			print("[MainMenu] Up to date (%s)" % latest)
	)
	updater.update_downloaded.connect(func():
		_toast("Update applied! Restarting...")
	)
	updater.update_failed.connect(func(reason): _toast(reason))
	updater.check_for_updates()

func _init_party_system() -> void:
	for i in party_slots.size():
		var slot_ui = party_slots[i]
		slot_ui.setup(i)
		slot_ui.invite_pressed.connect(_on_party_invite)
		slot_ui.kick_pressed.connect(_on_party_kick)
	
	# Bottom squad action bar: guaranteed visible & clickable on any resolution
	var squad_bar := HBoxContainer.new()
	squad_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	squad_bar.add_theme_constant_override("separation", 16)
	squad_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	squad_bar.offset_top = -160
	squad_bar.offset_bottom = -104
	squad_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	party_ui.add_child(squad_bar)

	var btn_invite := Button.new()
	btn_invite.text = "➕ INVITE FRIENDS"
	btn_invite.custom_minimum_size = Vector2(160, 42)
	btn_invite.pressed.connect(func(): _on_party_invite(0))
	squad_bar.add_child(btn_invite)

	var btn_browse := Button.new()
	btn_browse.text = "🔍 BROWSE ROOMS"
	btn_browse.custom_minimum_size = Vector2(160, 42)
	btn_browse.pressed.connect(func():
		var sync = get_node_or_null("/root/SteamSync")
		if sync and sync.has_method("open_lobby_browser_dialog"):
			sync.open_lobby_browser_dialog()
		else:
			_toast("SteamSync failed to load - check steam_sync.log / the console window")
	)
	squad_bar.add_child(btn_browse)

	var btn_copy := Button.new()
	btn_copy.text = "📋 COPY LOBBY CODE"
	btn_copy.custom_minimum_size = Vector2(170, 42)
	btn_copy.pressed.connect(func():
		var sync = get_node_or_null("/root/SteamSync")
		if sync == null:
			_toast("SteamSync failed to load - check steam_sync.log / the console window")
			return
		var lid: int = sync.get_lobby_id()
		if lid != 0:
			DisplayServer.clipboard_set(str(lid))
			btn_copy.text = "✓ COPIED!"
			get_tree().create_timer(2.0).timeout.connect(func():
				if is_instance_valid(btn_copy):
					btn_copy.text = "📋 COPY LOBBY CODE"
			)
		elif sync.is_steam_running:
			_toast("Creating your Steam lobby... click again in a second")
		else:
			_toast(sync.last_status if sync.last_status != "" else "Steam is not connected")
	)
	squad_bar.add_child(btn_copy)

	# Leave party: only while actually joined in a (non-host) lobby
	var btn_leave := Button.new()
	btn_leave.text = "🚪 LEAVE PARTY"
	btn_leave.custom_minimum_size = Vector2(150, 42)
	btn_leave.visible = false
	btn_leave.pressed.connect(_on_party_leave)
	squad_bar.add_child(btn_leave)
	_btn_leave_party = btn_leave

	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync:
		steam_sync.party_member_joined.connect(_on_steam_friend_joined)
		steam_sync.party_member_left.connect(_on_steam_friend_left)
		steam_sync.lobby_joined.connect(_update_leave_party_visibility)
		steam_sync.lobby_left.connect(_update_leave_party_visibility)
		steam_sync.party_member_joined.connect(func(_id: int, _name: String): _update_leave_party_visibility())
		steam_sync.party_member_left.connect(func(_id: int): _update_leave_party_visibility())
		for member in steam_sync.party_members:
			_on_steam_friend_joined(member.get("id", 0), member.get("name", ""))
		_update_leave_party_visibility()

var _toast_label: Label
var _toast_token: int = 0
var _btn_leave_party: Button = null

func _update_leave_party_visibility(_extra = null) -> void:
	if _btn_leave_party == null or not is_instance_valid(_btn_leave_party):
		return
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync == null:
		_btn_leave_party.visible = false
		return
	# Visible if we joined someone else's lobby (not host) OR if our lobby has members
	var in_foreign_lobby: bool = steam_sync.current_lobby_id != 0 and not steam_sync.is_lobby_host()
	var has_members: bool = steam_sync.party_members.size() > 0
	_btn_leave_party.visible = in_foreign_lobby or has_members

func _on_party_leave() -> void:
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync and steam_sync.has_method("leave_lobby"):
		steam_sync.leave_lobby()
		# Clear all party slot UIs
		for slot in party_slots:
			slot.clear()
		_toast("Left the party.")
		_update_leave_party_visibility()

## Small on-screen message so a failing button is never a silent no-op in exported builds.
func _toast(msg: String) -> void:
	print("[MainMenu] ", msg)
	if _toast_label == null or not is_instance_valid(_toast_label):
		_toast_label = Label.new()
		_toast_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_toast_label.offset_top = -112
		_toast_label.offset_bottom = -72
		_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_toast_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_toast_label.add_theme_constant_override("outline_size", 6)
		_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		party_ui.add_child(_toast_label)
	_toast_label.text = msg
	_toast_label.show()
	_toast_token += 1
	var token := _toast_token
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_instance_valid(_toast_label) and _toast_token == token:
			_toast_label.hide()
	)

# ---------------- Stylized UI theme (reference: dark tactical plates + orange accents) ----------------

var _ui_font: FontFile = null
var _ui_font_bold: FontVariation = null

func _ui_load_font() -> void:
	_ui_font = load("res://addons/GD-Sync/UI/Fonts/Outfit-Regular.ttf")
	if _ui_font != null:
		_ui_font_bold = FontVariation.new()
		_ui_font_bold.base_font = _ui_font
		_ui_font_bold.variation_embolden = 0.7

## Dark rounded plate StyleBoxFlat with optional orange left accent bar.
func _ui_plate(bg: Color, accent: bool = false, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 18.0 if accent else 16.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	if accent:
		sb.border_width_left = 3
		sb.border_color = UI_ORANGE
	return sb

func _ui_style_button(b: Button, primary: bool = false) -> void:
	if b == null:
		return
	if _ui_font != null:
		var f: Font = _ui_font
		if primary:
			f = _ui_font_bold
		b.add_theme_font_override("font", f)
	b.add_theme_color_override("font_color", Color.WHITE if primary else UI_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if primary:
		b.add_theme_color_override("font_pressed_color", Color(0.98, 0.9, 0.8))
		var n := _ui_plate(UI_ORANGE, false, 8)
		n.shadow_color = Color(0, 0, 0, 0.35)
		n.shadow_size = 6
		n.shadow_offset = Vector2(0, 3)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", _ui_plate(UI_ORANGE.lightened(0.1), false, 8))
		b.add_theme_stylebox_override("pressed", _ui_plate(UI_ORANGE.darkened(0.18), false, 8))
	else:
		b.add_theme_stylebox_override("normal", _ui_plate(UI_PLATE))
		b.add_theme_stylebox_override("hover", _ui_plate(UI_PLATE_HOVER, true))
		b.add_theme_stylebox_override("pressed", _ui_plate(UI_PLATE.darkened(0.2), true))

func _apply_style() -> void:
	_ui_load_font()

	# Title lockup: bold Outfit
	if _ui_font_bold != null:
		for l in [$LeftNav/VBoxContainer/TitleContainer/TitleRow/TitleStack/TitleLine/Poly,
				$LeftNav/VBoxContainer/TitleContainer/TitleRow/TitleStack/TitleLine/Shot]:
			if l != null:
				l.add_theme_font_override("font", _ui_font_bold)
				l.add_theme_font_size_override("font_size", 48)
		var sub: Label = $LeftNav/VBoxContainer/TitleContainer/TitleRow/TitleStack/SubTitle
		if sub != null and _ui_font != null:
			sub.add_theme_font_override("font", _ui_font)

	# Left nav: PLAY primary orange, rest dark plates with hover accent
	_ui_style_button(btn_left_play, true)
	for n in ["BtnLoadout", "BtnOperator", "BtnShop", "BtnDaily", "BtnSetting", "BtnExit"]:
		_ui_style_button(get_node_or_null("LeftNav/VBoxContainer/" + n) as Button, false)

	# Right panel: currency pills + daily reward plate
	for panel_path in ["RightPanel/VBoxContainer/CurrencyHBox/CoinPanel",
			"RightPanel/VBoxContainer/CurrencyHBox/GemPanel",
			"RightPanel/VBoxContainer/DailyRewardPanel"]:
		var p := get_node_or_null(panel_path) as PanelContainer
		if p != null:
			p.add_theme_stylebox_override("panel", _ui_plate(UI_PLATE, false, 8))
	var claim := get_node_or_null("RightPanel/VBoxContainer/DailyRewardPanel/VBox/ClaimBtn") as Button
	_ui_style_button(claim, false)

	# Giant PLAY: orange with shadow, distinct hover/pressed
	var giant := get_node_or_null("RightPanel/VBoxContainer/GiantPlayBtn") as Button
	if giant != null:
		if _ui_font_bold != null:
			giant.add_theme_font_override("font", _ui_font_bold)
		giant.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var gn := _ui_plate(UI_ORANGE, false, 10)
		gn.shadow_color = Color(0, 0, 0, 0.4)
		gn.shadow_size = 10
		gn.shadow_offset = Vector2(0, 4)
		giant.add_theme_stylebox_override("normal", gn)
		giant.add_theme_stylebox_override("hover", _ui_plate(UI_ORANGE.lightened(0.1), false, 10))
		giant.add_theme_stylebox_override("pressed", _ui_plate(UI_ORANGE.darkened(0.18), false, 10))

	# Play overlay: dark plate + mode buttons + orange start
	var overlay_panel := get_node_or_null("PlayOverlay/CenterContainer/PanelContainer") as PanelContainer
	if overlay_panel != null:
		var op := _ui_plate(Color(0.09, 0.095, 0.115, 0.98), false, 10)
		op.border_width_bottom = 2
		op.border_color = UI_ORANGE
		overlay_panel.add_theme_stylebox_override("panel", op)
	for n in ["BtnCampaign", "BtnPractice", "BtnMultiplayer"]:
		_ui_style_button(get_node_or_null("PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/Sidebar/" + n) as Button, false)
	var start := get_node_or_null("PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/MapArea/MarginStart/BtnStartGame") as Button
	_ui_style_button(start, true)
	var close := get_node_or_null("PlayOverlay/CenterContainer/PanelContainer/HBoxContainer/Sidebar/BtnClosePlay") as Button
	_ui_style_button(close, false)

	# Squad bar buttons (created in _init_party_system after this — style deferred)
	call_deferred("_style_squad_bar")

	_style_environment()
	_add_vignette()

func _style_squad_bar() -> void:
	await get_tree().process_frame
	var party := get_node_or_null("PartyUI")
	if party == null:
		return
	for c in party.get_children():
		if c is HBoxContainer:
			for b in c.get_children():
				if b is Button:
					_ui_style_button(b, false)

func _style_environment() -> void:
	var we := get_node_or_null("3DEnvironment/WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.ambient_light_color = Color(0.55, 0.58, 0.64)
		env.ambient_light_energy = 0.75
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 1.05
		env.fog_enabled = true
		env.fog_light_color = Color(0.09, 0.095, 0.115)
		env.fog_density = 0.012
		env.fog_sky_affect = 0.0
		env.glow_enabled = true
		env.glow_intensity = 0.5
		env.glow_bloom = 0.02
	var sun := get_node_or_null("3DEnvironment/DirectionalLight3D") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color(1.0, 0.87, 0.7)
		sun.light_energy = 1.25
	var spot := get_node_or_null("3DEnvironment/SpotLight3D") as SpotLight3D
	if spot != null:
		spot.light_color = Color(1.0, 0.72, 0.45)

func _add_vignette() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.55, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.42)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, -0.5)
	gt.width = 512
	gt.height = 512
	var vignette := TextureRect.new()
	vignette.name = "Vignette"
	vignette.texture = gt
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	move_child(vignette, 0)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _on_party_invite(_slot_idx: int) -> void:
	# Always open the in-game dialog directly — never a silent no-op.
	print("[INVITE] slot clicked, opening dialog")
	var steam_sync = get_node_or_null("/root/SteamSync")
	if steam_sync and steam_sync.has_method("open_friend_invite_dialog"):
		steam_sync.open_friend_invite_dialog()
		return
	_toast("SteamSync failed to load - check steam_sync.log / the console window")
	# ponytail: lobby slot fills only from real join (_on_steam_friend_joined); add fallback backfill when offline co-op lands.

func _on_steam_friend_joined(steam_id: int, member_name: String) -> void:
	if member_name.is_empty():
		return
	print("Steam friend joined party: %s (ID: %d)" % [member_name, steam_id])
	for i in party_slots.size():
		if not party_slots[i].is_filled:
			party_slots[i].fill(member_name)
			return

func _on_steam_friend_left(steam_id: int) -> void:
	print("Steam friend left party (ID: %d)" % steam_id)
	var steam = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	var target_name = steam.getFriendPersonaName(steam_id) if steam else str(steam_id)
	for i in party_slots.size():
		if party_slots[i].is_filled and (party_slots[i].player_name == target_name or party_slots[i].player_name == str(steam_id)):
			_on_party_kick(i)
			return

func _on_party_kick(slot_idx: int) -> void:
	party_slots[slot_idx].clear()


func _process(delta):
	# Slowly rotate the character pedestal for visual flair
	character_pivot.rotation.y += 0.2 * delta

func _on_play_pressed():
	play_overlay.show()
	party_ui.hide()

func set_play_mode(mode: String):
	selected_mode = mode
	if is_instance_valid(bots_toggle):
		bots_toggle.visible = (mode == "Multiplayer")
	
	# Highlight sidebar
	btn_campaign.modulate = Color(1, 1, 1, 1)
	btn_practice.modulate = Color(1, 1, 1, 1)
	btn_multiplayer.modulate = Color(1, 1, 1, 1)
	
	if mode == "Campaign": btn_campaign.modulate = Color(1, 0.8, 0.2, 1)
	if mode == "Practice": btn_practice.modulate = Color(1, 0.8, 0.2, 1)
	if mode == "Multiplayer": btn_multiplayer.modulate = Color(1, 0.8, 0.2, 1)
	
	# Populate map list
	map_list.clear()
	for m in maps[mode]:
		map_list.add_item(m["name"])
	
	# Select first by default
	if map_list.item_count > 0:
		map_list.select(0)
		_on_map_selected(0)

func _on_map_selected(index: int):
	var map_data = maps[selected_mode][index]
	map_desc.text = map_data["desc"]
	
	# Disable start button if scene is empty (Coming Soon)
	btn_start_game.disabled = (map_data["scene"] == "")

func _on_start_game_pressed():
	var items = map_list.get_selected_items()
	if items.size() > 0:
		var map_data = maps[selected_mode][items[0]]
		if map_data["scene"] != "":
			if selected_mode == "Campaign":
				GlobalSettings.current_minimap = "res://assets/textures/minimap.png"
			else:
				GlobalSettings.current_minimap = ""
			
			var steam_sync = get_node_or_null("/root/SteamSync")
			# Guard: if in a Steam party lobby and not the host, block match start
			if steam_sync and steam_sync.current_lobby_id != 0 and not steam_sync.is_lobby_host():
				btn_start_game.text = "ONLY HOST CAN START"
				var t = get_tree().create_timer(2.0)
				t.timeout.connect(func(): if is_instance_valid(btn_start_game): btn_start_game.text = "START GAME")
				return

			# Multiplayer AND Practice (training ground): party follows the host in
			var should_host_steam = steam_sync and selected_mode in ["Multiplayer", "Practice"] and steam_sync.party_members.size() > 0
			if should_host_steam and steam_sync.is_steam_running and ClassDB.class_exists("SteamMultiplayerPeer"):
				if selected_mode == "Multiplayer":
					steam_sync.set_lobby_open(true) # started match = room joinable
				steam_sync.start_steam_host(map_data["scene"])
				get_tree().change_scene_to_file(map_data["scene"])
				return
			get_tree().change_scene_to_file(map_data["scene"])


func _on_loadout_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/loadout_menu.tscn")

func _on_setting_pressed():
	GlobalSettings.previous_scene = "res://scenes/ui/main_menu.tscn"
	get_tree().change_scene_to_file("res://scenes/ui/settings_menu.tscn")

func _on_exit_pressed():
	_show_exit_confirm()

## Centered "ARE YOU SURE?" modal: YES quits, NO/ESC dismisses.
func _show_exit_confirm() -> void:
	if get_node_or_null("ExitConfirmLayer") != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "ExitConfirmLayer"
	layer.layer = 130
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.anchor_right = 0.0
	root.anchor_bottom = 0.0
	layer.add_child(root)
	root.set_deferred("size", get_viewport_rect().size)
	get_viewport().size_changed.connect(func():
		if is_instance_valid(root):
			root.set_deferred("size", get_viewport_rect().size))

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.085, 0.105, 0.98)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	sb.border_width_bottom = 3
	sb.border_color = Color(1.0, 0.44, 0.08)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 22)
	panel.add_child(vbox)

	var msg := Label.new()
	msg.text = "ARE YOU SURE?"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 30)
	msg.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(msg)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 18)
	vbox.add_child(btns)

	var press := func(quit_game: bool):
		if quit_game:
			var _ss = get_node_or_null("/root/SteamSync")
			if _ss and _ss.has_method("leave_steam_game"):
				_ss.leave_steam_game()
			get_tree().quit()
		else:
			layer.queue_free()

	for opt in [["YES", true, Color(1.0, 0.44, 0.08)], ["NO", false, Color(0.09, 0.1, 0.12)]]:
		var b := Button.new()
		b.text = opt[0]
		b.custom_minimum_size = Vector2(150, 52)
		b.focus_mode = Control.FOCUS_NONE
		var pl := func(c: Color) -> StyleBoxFlat:
			var bs := StyleBoxFlat.new()
			bs.bg_color = c
			bs.set_corner_radius_all(8)
			return bs
		var n: StyleBoxFlat = pl.call(opt[2])
		if opt[1]:
			n.shadow_color = Color(0, 0, 0, 0.4)
			n.shadow_size = 8
			n.shadow_offset = Vector2(0, 3)
		else:
			n.border_width_bottom = 2
			n.border_color = Color(0.18, 0.2, 0.24)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", pl.call(opt[2].lightened(0.1) if opt[1] else Color(0.13, 0.145, 0.17)))
		b.add_theme_stylebox_override("pressed", pl.call(opt[2].darkened(0.18) if opt[1] else Color(0.06, 0.07, 0.09)))
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_color_override("font_color", Color.WHITE if opt[1] else Color(0.9, 0.92, 0.95))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.pressed.connect(press.bind(opt[1]))
		btns.add_child(b)

func _on_operator_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/operator_menu.tscn")

func _apply_root_size() -> void:
	# Run after layout pass so nothing overrides size back to 64x64.
	await get_tree().process_frame
	var vp_size = get_viewport_rect().size
	size = vp_size
	# party_ui uses PRESET_FULL_RECT anchors to match parent; setting size manually triggers engine warning.
