extends Control

@onready var categories_box = $PanelContainer/HBoxContainer/Categories
@onready var op_name_label = $PanelContainer/HBoxContainer/Details/OpName
@onready var op_health = $PanelContainer/HBoxContainer/Details/OpHealth
@onready var op_armor = $PanelContainer/HBoxContainer/Details/OpArmor
@onready var op_speed = $PanelContainer/HBoxContainer/Details/OpSpeed
@onready var op_skill = $PanelContainer/HBoxContainer/Details/OpSkill
@onready var btn_equip = $PanelContainer/HBoxContainer/Details/BtnEquip
@onready var btn_back = $TopBar/BtnBack

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
var cat_buttons: Dictionary = {}

func _ready() -> void:
	btn_back.pressed.connect(_on_back_pressed)
	btn_equip.pressed.connect(_on_equip_pressed)
	_build_category_grid()
	_select(GlobalData.equipped_operator)

func _build_category_grid() -> void:
	for child in categories_box.get_children():
		child.queue_free()
	cat_buttons.clear()
	for cat in categories:
		var header := Label.new()
		header.text = cat.to_upper()
		header.add_theme_font_size_override("font_size", 22)
		header.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
		categories_box.add_child(header)

		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		categories_box.add_child(grid)

		for op in operators:
			if op["category"] != cat:
				continue
			var btn := Button.new()
			btn.text = op["name"]
			btn.custom_minimum_size = Vector2(140, 50)
			btn.add_theme_font_size_override("font_size", 20)
			btn.toggle_mode = true
			btn.pressed.connect(_on_op_button.bind(op["id"]))
			grid.add_child(btn)
			cat_buttons[op["id"]] = btn

func _on_op_button(id: String) -> void:
	_select(id)

func _select(id: String) -> void:
	selected_id = id
	for key in cat_buttons:
		(cat_buttons[key] as Button).button_pressed = (key == id)
	_refresh_details()

func _get_op(id: String) -> Dictionary:
	for op in operators:
		if op["id"] == id:
			return op
	return operators[0]

func _refresh_details() -> void:
	var op = _get_op(selected_id)
	op_name_label.text = op["name"]
	op_health.text = "Max Health: " + str(op["health"])
	op_armor.text = "Max Armor: " + str(op["armor"])
	op_speed.text = "Movement Speed: " + op["speed"]
	op_skill.text = "Unique Skill: " + op["skill"]

	if GlobalData.equipped_operator == op["id"]:
		btn_equip.text = "EQUIPPED"
		btn_equip.disabled = true
	else:
		btn_equip.text = "EQUIP OPERATOR"
		btn_equip.disabled = false

func _on_equip_pressed() -> void:
	GlobalData.equipped_operator = selected_id
	_refresh_details()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
