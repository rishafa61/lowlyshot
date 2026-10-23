extends Control
## BF4-style loadout screen: horizontal category tabs + slot cards (left),
## weapon list + details (middle), 3D inspectable weapon preview (right).
## Drag preview to rotate; release snaps back to left-facing side profile.

@onready var slot_cards := {
	"Primary": $Margin/VBox/Main/Left/SlotPrimary,
	"Secondary": $Margin/VBox/Main/Left/SlotSecondary,
	"Melee": $Margin/VBox/Main/Left/SlotMelee,
	"Equip1": $Margin/VBox/Main/Left/SlotEquip1,
	"Equip2": $Margin/VBox/Main/Left/SlotEquip2,
}
@onready var group_list: HBoxContainer = $Margin/VBox/Main/Mid/GroupTabs
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
	{"key": "Melee", "cat": "Melee", "label": "Melee Weapon"},
	{"key": "Equip1", "cat": "Throwable", "label": "Equipment 01"},
	{"key": "Equip2", "cat": "Heavy", "label": "Equipment 02"},
]

const WEAPON_GROUPS := {
	"Primary": {
		"Assault Rifles": ["ak47", "m4a4"],
		"Submachine Guns": ["mp5", "steyr_aug"],
		"Light Machine Guns": ["rpd"],
		"Shotguns": ["remington_870"],
		"Sniper Rifles": ["m700"]
	},
	"Secondary": {"Pistols": ["glock", "desert_hawk"]},
	"Melee": {"Melee": ["knife"]},
	"Throwable": {"Throwables": ["grenade", "flashbang"]},
	"Heavy": {"Heavy Weapons": ["at4"]},
}

const COL_BG := Color("101318")
const COL_PANEL := Color("1c232e")
const COL_BORDER := Color("313d4d")
const COL_ACCENT := Color(1.0, 0.44, 0.08) # UI_ORANGE
const COL_TEXT_DIM := Color("9aa7b5")
const COL_SEG_OFF := Color("262b33")

const UI_FONT_PATH := "res://addons/GD-Sync/UI/Fonts/Outfit-Regular.ttf"

var _font: FontFile = null
var _font_bold: FontVariation = null

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
		_style_preset_tab(x, x == b)

func _cycle_preset(dir: int) -> void:
	_on_preset_pressed(preset_buttons[(active_preset + dir + preset_buttons.size()) % preset_buttons.size()])

func _style_panels() -> void:
	_font = load(UI_FONT_PATH)
	if _font != null:
		_font_bold = FontVariation.new()
		_font_bold.base_font = _font
		_font_bold.variation_embolden = 0.7

	_setup_background()
	_add_vignette()
	_style_title()
	_style_preset_tabs()
	_style_slot_cards()
	_style_detail_panel()
	_style_weapon_buttons()
	_style_back_button()
	_style_hints()
	_warm_preview()

func _weapon_by_id(id: String) -> Dictionary:
	for cat in GlobalData.weapons:
		for w in GlobalData.weapons[cat]:
			if str(w.get("id", "")) == id:
				return w
	return {}

func _equipped_in(cat: String) -> Dictionary:
	var list: Array = GlobalData.weapons.get(cat, [])
	for w in list:
		if w.get("equipped", false):
			return w
	return list[0] if list.size() > 0 else {}

func _refresh_slots() -> void:
	for def in SLOT_DEFS:
		var card: PanelContainer = slot_cards[def["key"]]
		var vbox: VBoxContainer = card.get_child(0)
		var eq := _equipped_in(def["cat"])
		(vbox.get_node("NameLabel") as Label).text = str(eq.get("name", "—")) if not eq.is_empty() else "—"
		(vbox.get_node("SubLabel") as Label).text = def["label"]
	_update_slot_styles()

func _update_slot_styles() -> void:
	# Card states: active slot = orange border, equipped = dim orange edge, idle = dark
	for def in SLOT_DEFS:
		var card: PanelContainer = slot_cards[def["key"]]
		var eq := _equipped_in(def["cat"])
		var is_eq: bool = eq.get("equipped", false)
		var state := "active" if def["key"] == current_slot else ("equipped" if is_eq else "idle")
		card.add_theme_stylebox_override("panel", _slot_card_sb(state))

func _set_slot(key: String) -> void:
	current_slot = key
	_update_slot_styles()
	var cat := ""
	for def in SLOT_DEFS:
		if def["key"] == key:
			cat = def["cat"]
	# Horizontal category buttons above the weapon list
	for c in group_list.get_children():
		c.queue_free()
	var first_group := ""
	var groups = WEAPON_GROUPS.get(cat, {})
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
			_style_group_tab(gb, gb.text == group)

	var cat := ""
	for def in SLOT_DEFS:
		if def["key"] == current_slot:
			cat = def["cat"]
	var ids: Array = WEAPON_GROUPS.get(cat, {}).get(group, [])

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
		btn.custom_minimum_size = Vector2(0, 52)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if _font_bold != null:
			btn.add_theme_font_override("font", _font_bold)
		btn.add_theme_font_size_override("font_size", 18)
		btn.focus_mode = Control.FOCUS_NONE
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
	# Subtitle & stat formatting matching reference dossier card
	var sub := current_group if current_group != "" else "Weapon"
	item_desc.text = "%s  ·  %d damage  ·  %d m range  ·  %d round mag" % [
		sub, int(item.get("dmg", 0)), int(item.get("rng", 0)), int(item.get("max_mag", 0))
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
			segs[i].color = COL_ACCENT if i < lit else COL_SEG_OFF
	for row_id in weapon_rows:
		var btn: Button = weapon_rows[row_id]
		_style_weapon_row(btn, row_id == id)
	if item.get("equipped", false):
		btn_equip.text = "EQUIPPED"
		btn_equip.disabled = true
	else:
		btn_equip.text = "SAVE LOADOUT >"
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
	for w in GlobalData.weapons.get(cat, []):
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

# ---------------- Loadout UI theme (reference: tactical plates + orange accents) ----------------

func _style_title() -> void:
	var top: HBoxContainer = $Margin/VBox/TopBar
	var badge := SlashBadge.new()
	badge.name = "SlashBadge"
	badge.custom_minimum_size = Vector2(44, 40)
	top.add_child(badge)
	top.move_child(badge, 0)
	var title := Label.new()
	title.name = "Title"
	title.text = "LOADOUT"
	if _font_bold != null:
		title.add_theme_font_override("font", _font_bold)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color.WHITE)
	top.add_child(title)
	top.move_child(title, 1)

	# Currency / squad pill on the top-right
	var pill := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.08, 0.09, 0.11, 0.95)
	psb.set_corner_radius_all(14)
	psb.content_margin_left = 14
	psb.content_margin_right = 14
	psb.content_margin_top = 6
	psb.content_margin_bottom = 6
	psb.border_width_bottom = 2
	psb.border_color = Color(0.18, 0.2, 0.24)
	pill.add_theme_stylebox_override("panel", psb)
	var pill_lbl := Label.new()
	pill_lbl.text = "C: %d  |  G: 0" % GlobalData.money
	if _font != null:
		pill_lbl.add_theme_font_override("font", _font)
	pill_lbl.add_theme_font_size_override("font_size", 14)
	pill_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	pill.add_child(pill_lbl)
	top.add_child(pill)

	# Underline orange accent
	var underline := ColorRect.new()
	underline.color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.7)
	underline.custom_minimum_size = Vector2(0, 3)
	var vbox: VBoxContainer = $Margin/VBox
	vbox.add_child(underline)
	vbox.move_child(underline, 1)

func _style_preset_tabs() -> void:
	var lb: Button = $Margin/VBox/TopBar/BtnLB
	var rb: Button = $Margin/VBox/TopBar/BtnRB
	for b in [lb, rb]:
		b.custom_minimum_size = Vector2(44, 38)
		if _font_bold != null:
			b.add_theme_font_override("font", _font_bold)
		b.add_theme_font_size_override("font_size", 14)
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.11, 0.13, 0.95)
		sb.set_corner_radius_all(6)
		sb.border_width_bottom = 2
		sb.border_color = COL_BORDER
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb.duplicate())
		b.add_theme_stylebox_override("pressed", sb.duplicate())
		b.add_theme_color_override("font_color", COL_TEXT_DIM)

func _style_preset_tab(b: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if active:
		sb.bg_color = COL_ACCENT
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 6
	else:
		sb.bg_color = Color(0.08, 0.09, 0.11, 0.95)
		sb.border_width_bottom = 2
		sb.border_color = COL_BORDER
	for s in ["normal", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, sb)
	b.add_theme_stylebox_override("hover", sb.duplicate())
	if _font_bold != null:
		b.add_theme_font_override("font", _font_bold)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color.WHITE if active else COL_TEXT_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)

func _style_slot_cards() -> void:
	for def in SLOT_DEFS:
		var card: PanelContainer = slot_cards[def["key"]]
		card.custom_minimum_size = Vector2(0, 92)
		var vbox: VBoxContainer = card.get_child(0)
		var name_lbl: Label = vbox.get_node("NameLabel")
		var sub_lbl: Label = vbox.get_node("SubLabel")
		if _font_bold != null:
			name_lbl.add_theme_font_override("font", _font_bold)
		name_lbl.add_theme_font_size_override("font_size", 20)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		if _font != null:
			sub_lbl.add_theme_font_override("font", _font)
		sub_lbl.add_theme_font_size_override("font_size", 13)
		sub_lbl.add_theme_color_override("font_color", COL_ACCENT)
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

func _slot_card_sb(state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	if state == "active":
		sb.bg_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.16)
		sb.set_border_width_all(2)
		sb.border_color = COL_ACCENT
	elif state == "equipped":
		sb.bg_color = Color(0.08, 0.09, 0.115, 0.96)
		sb.border_width_left = 3
		sb.border_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.6)
		sb.border_width_bottom = 2
		sb.border_color = Color(0.18, 0.2, 0.24)
	else:
		sb.bg_color = Color(0.07, 0.08, 0.1, 0.95)
		sb.border_width_bottom = 2
		sb.border_color = Color(0.16, 0.18, 0.22)
	return sb

func _add_hover_pop(b: Button) -> void:
	# Pop-out: scale the button slightly toward the cursor; grey drop shadow
	# lives on the hover StyleBoxFlat.
	if b == null or b.has_meta("hover_pop"):
		return
	b.set_meta("hover_pop", true)
	b.pivot_offset = b.size / 2.0
	b.mouse_entered.connect(func():
		b.pivot_offset = b.size / 2.0
		var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "scale", Vector2.ONE * 1.03, 0.1))
	b.mouse_exited.connect(func():
		var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "scale", Vector2.ONE, 0.1))

## Hover look shared by every button here: orange fill with a soft grey shade
## behind it, so the plate reads as lifted off the screen.
func _orange_hover_plate(radius: int = 8) -> StyleBoxFlat:
	var h := StyleBoxFlat.new()
	h.bg_color = COL_ACCENT
	h.set_corner_radius_all(radius)
	h.shadow_color = Color(0.32, 0.33, 0.36, 0.55)
	h.shadow_size = 10
	h.shadow_offset = Vector2(0, 5)
	return h

func _style_group_tab(b: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if active:
		sb.bg_color = COL_ACCENT
	else:
		sb.bg_color = Color(0.09, 0.1, 0.12, 0.95)
		sb.border_width_bottom = 2
		sb.border_color = Color(0.18, 0.2, 0.24)
	for s in ["normal", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, sb)
	b.add_theme_stylebox_override("hover", _orange_hover_plate(6))
	if _font_bold != null:
		b.add_theme_font_override("font", _font_bold)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color.WHITE if active else COL_TEXT_DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	_add_hover_pop(b)

func _style_weapon_row(b: Button, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 18
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if selected:
		sb.bg_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.15)
		sb.set_border_width_all(2)
		sb.border_color = COL_ACCENT
	else:
		sb.bg_color = Color(0.075, 0.085, 0.105, 0.95)
		sb.border_width_bottom = 2
		sb.border_color = Color(0.18, 0.2, 0.24)
	for s in ["normal", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, sb)
	b.add_theme_stylebox_override("hover", _orange_hover_plate(7))
	b.add_theme_color_override("font_color", Color.WHITE if selected else Color(0.85, 0.88, 0.92))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	_add_hover_pop(b)

func _style_detail_panel() -> void:
	var detail_sb := StyleBoxFlat.new()
	detail_sb.bg_color = Color(0.075, 0.085, 0.105, 0.97)
	detail_sb.set_corner_radius_all(10)
	detail_sb.content_margin_left = 24
	detail_sb.content_margin_right = 24
	detail_sb.content_margin_top = 20
	detail_sb.content_margin_bottom = 22
	detail_sb.border_width_left = 4
	detail_sb.border_color = COL_ACCENT
	detail_sb.border_width_bottom = 2
	detail_sb.border_color = Color(0.2, 0.22, 0.26)
	var detail: PanelContainer = $Margin/VBox/Main/Mid/Detail
	detail.add_theme_stylebox_override("panel", detail_sb)
	if _font_bold != null:
		item_name.add_theme_font_override("font", _font_bold)
	item_name.add_theme_font_size_override("font_size", 32)
	item_name.add_theme_color_override("font_color", Color.WHITE)
	if _font != null:
		item_desc.add_theme_font_override("font", _font)
	item_desc.add_theme_font_size_override("font_size", 15)
	item_desc.add_theme_color_override("font_color", COL_TEXT_DIM)

	# Stats block
	for c in stats_box.get_children():
		c.queue_free()
	for stat in [["DAMAGE", "dmg"], ["ACCURACY", "stab"], ["RANGE", "rng"], ["FIRE RATE", "rof"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		var lbl := Label.new()
		lbl.text = stat[0]
		lbl.custom_minimum_size = Vector2(120, 0)
		if _font_bold != null:
			lbl.add_theme_font_override("font", _font_bold)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.8, 0.84, 0.9))
		row.add_child(lbl)
		var segs: Array = []
		for i in 10:
			var seg := ColorRect.new()
			seg.custom_minimum_size = Vector2(22, 10)
			seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			seg.color = COL_SEG_OFF
			row.add_child(seg)
			segs.append(seg)
		stats_box.add_child(row)
		stats_box.set_meta(stat[1], segs)

func _style_weapon_buttons() -> void:
	if _font_bold != null:
		btn_equip.add_theme_font_override("font", _font_bold)
	btn_equip.add_theme_font_size_override("font_size", 20)
	btn_equip.custom_minimum_size = Vector2(0, 52)
	btn_equip.focus_mode = Control.FOCUS_NONE
	var plate := func(c: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(8)
		return sb
	var n: StyleBoxFlat = plate.call(COL_ACCENT)
	n.shadow_color = Color(0, 0, 0, 0.4)
	n.shadow_size = 8
	n.shadow_offset = Vector2(0, 3)
	btn_equip.add_theme_stylebox_override("normal", n)
	btn_equip.add_theme_stylebox_override("hover", _orange_hover_plate(8))
	btn_equip.add_theme_stylebox_override("pressed", plate.call(COL_ACCENT.darkened(0.18)))
	var dis: StyleBoxFlat = plate.call(Color(0.16, 0.175, 0.2))
	dis.border_width_bottom = 2
	dis.border_color = COL_SEG_OFF
	btn_equip.add_theme_stylebox_override("disabled", dis)
	btn_equip.add_theme_color_override("font_color", Color.WHITE)
	btn_equip.add_theme_color_override("font_hover_color", Color.WHITE)
	btn_equip.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn_equip.add_theme_color_override("font_disabled_color", COL_TEXT_DIM)
	_add_hover_pop(btn_equip)

func _style_back_button() -> void:
	var back: Button = $Margin/VBox/BottomBar/BtnBack
	if _font_bold != null:
		back.add_theme_font_override("font", _font_bold)
	back.add_theme_font_size_override("font_size", 18)
	back.custom_minimum_size = Vector2(150, 48)
	back.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.12, 0.95)
	sb.set_corner_radius_all(8)
	sb.border_width_bottom = 2
	sb.border_color = COL_BORDER
	back.add_theme_stylebox_override("normal", sb)
	back.add_theme_stylebox_override("hover", _orange_hover_plate(8))
	back.add_theme_stylebox_override("pressed", sb.duplicate())
	back.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	back.add_theme_color_override("font_hover_color", Color.WHITE)
	_add_hover_pop(back)

func _style_hints() -> void:
	var bar: HBoxContainer = $Margin/VBox/BottomBar
	bar.alignment = BoxContainer.ALIGNMENT_END
	var old: Label = bar.get_node_or_null("HintEquip")
	if old != null:
		old.queue_free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	for hint in [["E / ENTER", "Equip Weapon"], ["LMB DRAG", "Rotate Preview"], ["SCROLL", "Zoom"]]:
		row.add_child(_keycap(hint[0]))
		var lbl := Label.new()
		lbl.text = hint[1]
		if _font != null:
			lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", COL_TEXT_DIM)
		row.add_child(lbl)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(14, 0)
		row.add_child(pad)

func _keycap(text: String) -> Control:
	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.19, 0.205, 0.24)
	sb.set_corner_radius_all(5)
	sb.border_width_bottom = 3
	sb.border_color = Color(0.09, 0.095, 0.115)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	cap.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	if _font_bold != null:
		l.add_theme_font_override("font", _font_bold)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color.WHITE)
	cap.add_child(l)
	return cap

func _warm_preview() -> void:
	var we := get_node_or_null("Margin/VBox/Main/Right/Preview/SubViewport/WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		we.environment.glow_enabled = true
		we.environment.glow_intensity = 0.35
	var key := get_node_or_null("Margin/VBox/Main/Right/Preview/SubViewport/KeyLight") as DirectionalLight3D
	if key != null:
		key.light_color = Color(1.0, 0.92, 0.8)
	var rim := get_node_or_null("Margin/VBox/Main/Right/Preview/SubViewport/RimLight") as DirectionalLight3D
	if rim != null:
		rim.light_color = Color(1.0, 0.75, 0.5)

func _setup_background() -> void:
	# Replace flat color with the hangar backdrop art; keep dark plate behind
	# content for readability. Texture stretch-covers the viewport.
	var bg := get_node_or_null("Background") as ColorRect
	if bg == null:
		return
	var tex := load("res://assets/bg/Loadout Background.png")
	if tex != null:
		var art := TextureRect.new()
		art.name = "BgArt"
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		move_child(art, 0)  # behind the ColorRect tint
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.color = Color(0.063, 0.075, 0.09, 0.45)  # dim veil so UI stays readable

func _add_vignette() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.55, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.45)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, -0.5)
	gt.width = 512
	gt.height = 512
	var vignette := TextureRect.new()
	vignette.name = "LoadoutVignette"
	vignette.texture = gt
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	move_child(vignette, 1)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

class SlashBadge extends Control:
	func _draw() -> void:
		var orange := Color(1.0, 0.44, 0.08)
		var h := size.y
		var w := size.x
		var slash_w := w * 0.22
		var gap := w * 0.16
		var lean := h * 0.28
		for i in 3:
			var x := i * (slash_w + gap)
			var pts := PackedVector2Array([
				Vector2(x + lean, 0),
				Vector2(x + slash_w + lean, 0),
				Vector2(x + slash_w, h),
				Vector2(x, h),
			])
			draw_colored_polygon(pts, orange)
