extends Control
## BF4-style operator screen — same visual language as the loadout menu:
## operator list (left), details with segmented stat bars (middle),
## live 3D character preview (right).

const COL_BG := Color("141a22")
const COL_PANEL := Color("1c232e")
const COL_BORDER := Color("313d4d")
const COL_ACCENT := Color("e8a33d")
const COL_TEXT_DIM := Color("9aa7b5")

const CAT_TINT := {
	"Assault": Color("c96a3b"),
	"Recon": Color("3b8ea9"),
	"Support": Color("6a7bc9"),
}

@onready var group_list: VBoxContainer = $Margin/VBox/Main/Left/GroupList
@onready var op_list: VBoxContainer = $Margin/VBox/Main/Left/OpList
@onready var cat_header: Label = $Margin/VBox/Main/Mid/CatHeader/Label
@onready var item_name: Label = $Margin/VBox/Main/Mid/Detail/Panel/ItemName
@onready var item_desc: Label = $Margin/VBox/Main/Mid/Detail/Panel/ItemDesc
@onready var btn_equip: Button = $Margin/VBox/Main/Mid/Detail/Panel/BtnEquip
@onready var stats_box: VBoxContainer = $Margin/VBox/Main/Mid/Detail/Panel/StatsBox
@onready var preview_char: Node3D = $Margin/VBox/Main/Right/Preview/SubViewport/Standby

var operators = [
	{"id": "Greppy", "name": "Greppy", "category": "Assault",
		"health": 100, "armor": 50, "speed": "Fast (+10%)",
		"skill": "Grappler (Zip to surfaces)"},
	{"id": "Vanguard", "name": "Vanguard", "category": "Assault",
		"health": 120, "armor": 50, "speed": "Normal",
		"skill": "Adrenaline (Heal 25, +25% speed 5s)"},
	{"id": "Ghost", "name": "Ghost", "category": "Recon",
		"health": 100, "armor": 25, "speed": "Fast (+15%)",
		"skill": "Sonar Pulse"},
	{"id": "Wingman", "name": "Wingman", "category": "Support",
		"health": 100, "armor": 50, "speed": "Fast (+5%)",
		"skill": "Airstrike (Calls 3 Missiles)"},
	{"id": "Shock", "name": "Shock", "category": "Support",
		"health": 110, "armor": 50, "speed": "Slow (-5%)",
		"skill": "Shockwave (Stuns through walls)"},
	{"id": "Sentry", "name": "Sentry", "category": "Support",
		"health": 100, "armor": 50, "speed": "Normal",
		"skill": "Sentinel (Deploy auto-turret)"},
]

var categories = ["Assault", "Recon", "Support"]
var selected_id: String = ""
var op_rows: Dictionary = {} # id -> Button
var cat_headers: Dictionary = {} # category -> Button (header row)

func _ready() -> void:
	_style_panels()
	btn_equip.pressed.connect(_on_equip_pressed)
	$Margin/VBox/BottomBar/BtnBack.pressed.connect(_on_back_pressed)
	_build_list()
	_select(GlobalData.equipped_operator)

func _style_panels() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	var detail: PanelContainer = $Margin/VBox/Main/Mid/Detail
	detail.add_theme_stylebox_override("panel", sb)
	var header_panel: PanelContainer = $Margin/VBox/Main/Mid/CatHeader
	header_panel.add_theme_stylebox_override("panel", sb)
	cat_header.add_theme_font_size_override("font_size", 24)
	item_name.add_theme_font_size_override("font_size", 30)
	item_desc.add_theme_color_override("font_color", COL_TEXT_DIM)
	item_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_equip.add_theme_font_size_override("font_size", 20)
	# Stat rows built once (segmented bars, same as loadout)
	for stat in [["Health", "hp"], ["Armor", "armor"], ["Mobility", "mob"]]:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = stat[0]
		lbl.custom_minimum_size = Vector2(150, 0)
		row.add_child(lbl)
		var segs: Array = []
		for i in 10:
			var seg := ColorRect.new()
			seg.custom_minimum_size = Vector2(22, 10)
			seg.color = Color("2a2a2a")
			row.add_child(seg)
			segs.append(seg)
		stats_box.add_child(row)
		stats_box.set_meta(stat[1], segs)
	$Background.color = COL_BG

func _build_list() -> void:
	for cat in categories:
		var hdr := Button.new()
		hdr.text = cat.to_upper()
		hdr.flat = true
		hdr.disabled = true
		hdr.custom_minimum_size = Vector2(0, 34)
		hdr.alignment = HORIZONTAL_ALIGNMENT_LEFT
		hdr.add_theme_font_size_override("font_size", 18)
		hdr.add_theme_color_override("font_color", COL_ACCENT)
		group_list.add_child(hdr)
		cat_headers[cat] = hdr
	for op in operators:
		var btn := Button.new()
		btn.text = op["name"]
		btn.custom_minimum_size = Vector2(0, 46)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_select.bind(op["id"]))
		op_list.add_child(btn)
		op_rows[op["id"]] = btn

func _select(id: String) -> void:
	selected_id = id
	_refresh_details()

func _get_op(id: String) -> Dictionary:
	for op in operators:
		if op["id"] == id:
			return op
	return operators[0]

func _mobility_fill(speed: String) -> float:
	if "+15" in speed:
		return 1.0
	elif "+10" in speed:
		return 0.9
	elif "+5" in speed:
		return 0.8
	elif "Slow" in speed:
		return 0.45
	return 0.65 # Normal

func _refresh_details() -> void:
	var op := _get_op(selected_id)
	var cat := str(op.get("category", ""))
	cat_header.text = cat
	item_name.text = str(op.get("name", ""))
	item_desc.text = "Skill: %s  ·  Speed: %s" % [op.get("skill", ""), op.get("speed", "")]
	var fills := {
		"hp": clampf(float(op.get("health", 100)) / 200.0, 0.0, 1.0),
		"armor": clampf(float(op.get("armor", 50)) / 100.0, 0.0, 1.0),
		"mob": _mobility_fill(str(op.get("speed", "Normal"))),
	}
	for key in fills:
		var segs: Array = stats_box.get_meta(key)
		var lit := int(round(fills[key] * 10.0))
		for i in segs.size():
			segs[i].color = COL_ACCENT if i < lit else Color("2a2a2a")
	# Row + header highlight
	for cid in op_rows:
		var row: Button = op_rows[cid]
		var sel: bool = str(cid) == selected_id
		row.modulate = Color(1, 0.85, 0.5) if sel else Color.WHITE
	if GlobalData.equipped_operator == op["id"]:
		btn_equip.text = "EQUIPPED"
		btn_equip.disabled = true
	else:
		btn_equip.text = "EQUIP"
		btn_equip.disabled = false
	for ccat in cat_headers:
		var hdr: Button = cat_headers[ccat]
		hdr.modulate = Color(1, 0.85, 0.4) if ccat == cat else Color(0.65, 0.65, 0.7)
	# Tint preview to class color
	if preview_char and preview_char.has_method("set_tint"):
		preview_char.set_tint(CAT_TINT.get(cat, COL_ACCENT))

func _on_equip_pressed() -> void:
	if GlobalData.equipped_operator == selected_id:
		return
	GlobalData.equipped_operator = selected_id
	_refresh_details()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_E:
		_on_equip_pressed()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
