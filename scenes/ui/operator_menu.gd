extends Control
## BF4-style operator screen: category sidebar (left), category header +
## operator list + details (middle), live 3D preview (right).

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
@onready var cat_header: Label = $Margin/VBox/Main/Mid/CatHeader/Label
@onready var weapon_list: VBoxContainer = $Margin/VBox/Main/Mid/WeaponList
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
var current_category := "Assault"
var selected_id: String = ""
var op_rows: Dictionary = {} # id -> Button
var cat_buttons: Dictionary = {} # category -> Button

func _ready() -> void:
	_style_panels()
	btn_equip.pressed.connect(_on_equip_pressed)
	$Margin/VBox/BottomBar/BtnBack.pressed.connect(_on_back_pressed)
	_build_sidebar()
	var initial_cat := _category_of(GlobalData.equipped_operator)
	_set_category(initial_cat if initial_cat != "" else "Assault", GlobalData.equipped_operator)

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

func _build_sidebar() -> void:
	for c in group_list.get_children():
		c.queue_free()
	cat_buttons.clear()
	for cat in categories:
		var btn := Button.new()
		btn.text = cat.to_upper()
		btn.custom_minimum_size = Vector2(0, 44)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 18)
		btn.pressed.connect(_set_category.bind(cat, ""))
		group_list.add_child(btn)
		cat_buttons[cat] = btn

func _category_of(id: String) -> String:
	for op in operators:
		if op["id"] == id:
			return op["category"]
	return ""

func _set_category(cat: String, prefer_id: String = "") -> void:
	current_category = cat
	cat_header.text = cat
	# Sidebar highlight (loadout style: active category gold, rest muted)
	for c in cat_buttons:
		var btn: Button = cat_buttons[c]
		btn.modulate = Color(1, 0.85, 0.4) if c == cat else Color(0.65, 0.65, 0.7)
	# Rebuild operators in Mid column
	for c in weapon_list.get_children():
		c.queue_free()
	op_rows.clear()
	var cat_ops: Array = []
	for op in operators:
		if op["category"] == cat:
			cat_ops.append(op)
			var btn := Button.new()
			btn.text = op["name"]
			if GlobalData.equipped_operator == op["id"]:
				btn.text += "   ✓"
			btn.custom_minimum_size = Vector2(0, 46)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_font_size_override("font_size", 20)
			btn.pressed.connect(_select.bind(op["id"]))
			weapon_list.add_child(btn)
			op_rows[op["id"]] = btn
	# Pick operator: prefer_id if in this category, else keep selected if in cat, else first
	var target_id := ""
	if prefer_id != "" and _category_of(prefer_id) == cat:
		target_id = prefer_id
	elif selected_id != "" and _category_of(selected_id) == cat:
		target_id = selected_id
	elif not cat_ops.is_empty():
		target_id = cat_ops[0]["id"]
	if target_id != "":
		_select(target_id)

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
	return 0.65

func _refresh_details() -> void:
	var op := _get_op(selected_id)
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
	# Row highlight
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
	if preview_char and preview_char.has_method("set_tint"):
		preview_char.set_tint(CAT_TINT.get(current_category, COL_ACCENT))

func _on_equip_pressed() -> void:
	if GlobalData.equipped_operator == selected_id:
		return
	GlobalData.equipped_operator = selected_id
	_set_category(current_category, selected_id)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_E:
		_on_equip_pressed()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
