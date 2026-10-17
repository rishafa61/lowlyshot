extends Control
## BF4-style loadout screen: horizontal category tabs + slot cards (left),
## weapon list + details (middle), 3D inspectable weapon preview (right).
## Drag preview to rotate; release snaps back to left-facing side profile.

@onready var slot_cards := {
	"Primary": $Margin/VBox/Main/Left/SlotPrimary,
	"Secondary": $Margin/VBox/Main/Left/SlotSecondary,
	"Heavy": $Margin/VBox/Main/Left/SlotHeavy,
	"Equip1": $Margin/VBox/Main/Left/SlotEquip1,
	"Equip2": $Margin/VBox/Main/Left/SlotEquip2,
}
@onready var group_list: HBoxContainer = $Margin/VBox/Main/Left/GroupList
@onready var cat_header: Label = $Margin/VBox/Main/Mid/CatHeader/Label
@onready var item_name: Label = $Margin/VBox/Main/Mid/Detail/Panel/ItemName
@onready var item_desc: Label = $Margin/VBox/Main/Mid/Detail/Panel/ItemDesc
@onready var btn_equip: Button = $Margin/VBox/Main/Mid/Detail/Panel/BtnEquip
@onready var stats_box: VBoxContainer = $Margin/VBox/Main/Mid/Detail/Panel/StatsBox
@onready var weapon_list: VBoxContainer = $Margin/VBox/Main/Mid/WeaponList
@onready var preview_wp: Node3D = $Margin/VBox/Main/Right/Preview/SubViewport/WeaponPreview
@onready var preview_cont: SubViewportContainer = $Margin/VBox/Main/Right/Preview

const SLOT_DEFS := [
	{"key": "Primary", "cat": "Primary", "label": "Primary Weapon"},
	{"key": "Secondary", "cat": "Secondary", "label": "Secondary Weapon"},
	{"key": "Heavy", "cat": "Melee", "label": "Heavy Weapon"},
	{"key": "Equip1", "cat": "Utility", "label": "Equipment 01"},
	{"key": "Equip2", "cat": "Utility", "label": "Equipment 02"},
]

const WEAPON_GROUPS := {
	"Primary": {"Assault Rifles": ["ak47", "m4a4"], "Sniper Rifles": ["m700"]},
	"Secondary": {"Pistols": ["glock", "desert_hawk"]},
	"Melee": {"Melee": ["knife"], "Launchers": ["at4"]},
	"Utility": {"Equipment 01": ["grenade"], "Equipment 02": ["flashbang"]},
}

const COL_BG := Color("141a22")
const COL_PANEL := Color("1c232e")
const COL_BORDER := Color("313d4d")
const COL_ACCENT := Color("e8a33d")
const COL_TEXT_DIM := Color("9aa7b5")

var current_slot := "Primary"
var current_group := ""
var selected_item = null
var weapon_rows := {}
var preset_buttons: Array = []
var active_preset := 0
var _dragging := false

func _ready() -> void:
	_style_panels()
	btn_equip.pressed.connect(_on_equip_pressed)
	$Margin/VBox/BottomBar/BtnBack.pressed.connect(_on_back_pressed)
	preset_buttons = [
		$Margin/VBox/TopBar/Tab01, $Margin/VBox/TopBar/Tab02,
		$Margin/VBox/TopBar/Tab03, $Margin/VBox/TopBar/Tab04,
	]
	for b in preset_buttons:
		b.pressed.connect(func(): _on_preset_pressed(b))
	$Margin/VBox/TopBar/BtnLB.pressed.connect(func(): _cycle_preset(-1))
	$Margin/VBox/TopBar/BtnRB.pressed.connect(func(): _cycle_preset(1))
	_on_preset_pressed(preset_buttons[0])
	for def in SLOT_DEFS:
		var card: PanelContainer = slot_cards[def["key"]]
		card.gui_input.connect(func(ev): _on_card_clicked(def, ev))
	preview_cont.gui_input.connect(_on_preview_gui_input)
	_refresh_slots()
	_set_slot("Primary")

func _on_preset_pressed(b: Button) -> void:
	active_preset = preset_buttons.find(b)
	for x in preset_buttons:
		x.modulate = Color(1, 0.85, 0.5) if x == b else Color(0.55, 0.55, 0.6)

func _cycle_preset(dir: int) -> void:
	_on_preset_pressed(preset_buttons[(active_preset + dir + preset_buttons.size()) % preset_buttons.size()])

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
	for def in SLOT_DEFS:
		var card: PanelContainer = slot_cards[def["key"]]
		card.add_theme_stylebox_override("panel", sb)
		var vbox: VBoxContainer = card.get_child(0)
		vbox.get_node("NameLabel").add_theme_font_size_override("font_size", 24)
		vbox.get_node("SubLabel").add_theme_color_override("font_color", COL_TEXT_DIM)
	$Margin/VBox/Main/Mid/Detail.add_theme_stylebox_override("panel", sb)
	$Margin/VBox/Main/Mid/CatHeader.add_theme_stylebox_override("panel", sb)
	cat_header.add_theme_font_size_override("font_size", 24)
	item_name.add_theme_font_size_override("font_size", 30)
	item_desc.add_theme_color_override("font_color", COL_TEXT_DIM)
	item_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn_equip.add_theme_font_size_override("font_size", 20)
	for stat in [["Damage", "dmg"], ["Accuracy", "stab"], ["Range", "rng"], ["Rate of Fire", "rof"]]:
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

func _weapon_by_id(id: String) -> Dictionary:
	for cat in GlobalData.weapons:
		for w in GlobalData.weapons[cat]:
			if str(w.get("id", "")) == id:
				return w
	return {}

func _equipped_in(cat: String) -> Dictionary:
	for w in GlobalData.weapons[cat]:
		if w.get("equipped", false):
			return w
	return GlobalData.weapons[cat][0] if GlobalData.weapons[cat].size() > 0 else {}

func _refresh_slots() -> void:
	for def in SLOT_DEFS:
		var card: PanelContainer = slot_cards[def["key"]]
		var vbox: VBoxContainer = card.get_child(0)
		var eq: Dictionary
		if def["key"] in ["Equip1", "Equip2"]:
			var own_id := "grenade" if def["key"] == "Equip1" else "flashbang"
			eq = _weapon_by_id(own_id)
		else:
			eq = _equipped_in(def["cat"])
		(vbox.get_node("NameLabel") as Label).text = str(eq.get("name", "—")) if not eq.is_empty() else "—"
		(vbox.get_node("SubLabel") as Label).text = def["label"]
		var is_eq: bool = eq.get("equipped", false)
		card.modulate = Color(1, 0.92, 0.75) if is_eq else Color.WHITE

func _set_slot(key: String) -> void:
	current_slot = key
	for def in SLOT_DEFS:
		var card: PanelContainer = slot_cards[def["key"]]
		card.modulate = Color(1, 0.92, 0.5) if def["key"] == key else Color(0.85, 0.85, 0.9)
	var cat := ""
	for def in SLOT_DEFS:
		if def["key"] == key:
			cat = def["cat"]
	# Horizontal category buttons above slot cards
	for c in group_list.get_children():
		c.queue_free()
	var first_group := ""
	var groups = WEAPON_GROUPS.get(cat, {})
	if key == "Equip1":
		groups = {"Equipment 01": WEAPON_GROUPS["Utility"].get("Equipment 01", [])}
	elif key == "Equip2":
		groups = {"Equipment 02": WEAPON_GROUPS["Utility"].get("Equipment 02", [])}

	for group in groups:
		var gb := Button.new()
		gb.text = group
		gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gb.custom_minimum_size = Vector2(0, 36)
		gb.add_theme_font_size_override("font_size", 14)
		gb.pressed.connect(func(): _set_group(group))
		group_list.add_child(gb)
		if first_group == "":
			first_group = group
	_set_group(first_group)

func _set_group(group: String) -> void:
	current_group = group
	cat_header.text = group
	for gb in group_list.get_children():
		if gb is Button:
			gb.modulate = Color(1, 0.85, 0.4) if gb.text == group else Color(0.65, 0.65, 0.7)

	var ids: Array = []
	if current_slot == "Equip1":
		ids = WEAPON_GROUPS["Utility"].get("Equipment 01", [])
	elif current_slot == "Equip2":
		ids = WEAPON_GROUPS["Utility"].get("Equipment 02", [])
	else:
		var cat := ""
		for def in SLOT_DEFS:
			if def["key"] == current_slot:
				cat = def["cat"]
		ids = WEAPON_GROUPS.get(cat, {}).get(group, [])

	for c in weapon_list.get_children():
		c.queue_free()
	weapon_rows.clear()
	for id in ids:
		var w := _weapon_by_id(id)
		if w.is_empty():
			continue
		var btn := Button.new()
		btn.text = str(w.get("name", id))
		if w.get("equipped", false):
			btn.text += "   ✓"
		btn.custom_minimum_size = Vector2(0, 46)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(func(): select_item(w))
		weapon_list.add_child(btn)
		weapon_rows[id] = btn

	if selected_item != null and str(selected_item.get("id", "")) in ids:
		select_item(selected_item)
	elif not ids.is_empty():
		select_item(_weapon_by_id(ids[0]))

func select_item(item: Dictionary) -> void:
	selected_item = item
	var id: String = str(item.get("id", ""))
	item_name.text = str(item.get("name", ""))
	item_desc.text = "%d damage  ·  %d m range  ·  %d round mag  ·  %s" % [
		int(item.get("dmg", 0)), int(item.get("rng", 0)), int(item.get("max_mag", 0)),
		"full-auto" if item.get("auto", false) else "semi-auto"
	]
	var rps: float = 0.0
	if float(item.get("fire_rate", 0.0)) > 0.0:
		rps = 1.0 / float(item["fire_rate"])
	var fills := {
		"dmg": clampf(float(item.get("dmg", 0.0)) / 120.0, 0.0, 1.0),
		"stab": clampf(float(item.get("stab", 0.0)) / 100.0, 0.0, 1.0),
		"rng": clampf(float(item.get("rng", 0.0)) / 150.0, 0.0, 1.0),
		"rof": clampf(rps / 12.0, 0.0, 1.0),
	}
	for key in fills:
		var segs: Array = stats_box.get_meta(key)
		var lit := int(round(fills[key] * 10.0))
		for i in segs.size():
			segs[i].color = COL_ACCENT if i < lit else Color("2a2a2a")
	for row_id in weapon_rows:
		var btn: Button = weapon_rows[row_id]
		btn.modulate = Color(1, 0.85, 0.5) if row_id == id else Color.WHITE
	if item.get("equipped", false):
		btn_equip.text = "EQUIPPED"
		btn_equip.disabled = true
	else:
		btn_equip.text = "EQUIP"
		btn_equip.disabled = false
	if preview_wp and preview_wp.has_method("show_weapon"):
		preview_wp.show_weapon(id)

func _on_equip_pressed() -> void:
	if selected_item == null or selected_item.get("equipped", false):
		return
	var cat := ""
	for def in SLOT_DEFS:
		if def["key"] == current_slot:
			cat = def["cat"]
	for w in GlobalData.weapons[cat]:
		w["equipped"] = false
	selected_item["equipped"] = true
	_refresh_slots()
	_set_group(current_group)

func _on_card_clicked(def: Dictionary, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_set_slot(def["key"])

func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
			else:
				_dragging = false
				if preview_wp and preview_wp.has_method("snap_back"):
					preview_wp.snap_back(false)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if preview_wp and preview_wp.has_method("zoom_by"):
				preview_wp.zoom_by(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if preview_wp and preview_wp.has_method("zoom_by"):
				preview_wp.zoom_by(-1)
	elif event is InputEventMouseMotion and _dragging:
		if preview_wp and preview_wp.has_method("rotate_by"):
			preview_wp.rotate_by(event.relative)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_E:
		_on_equip_pressed()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _dragging:
		_dragging = false
		if preview_wp and preview_wp.has_method("snap_back"):
			preview_wp.snap_back(false)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
