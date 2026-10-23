extends Control
## BF4-style operator screen: category sidebar (left), category header +
## operator list + details (middle), live 3D preview (right).

const COL_BG := Color("101318")
const COL_PANEL := Color("1c232e")
const COL_BORDER := Color("313d4d")
const COL_ACCENT := Color(1.0, 0.44, 0.08) # match menu UI_ORANGE
const COL_TEXT_DIM := Color("9aa7b5")
const COL_SEG_OFF := Color("262b33")

const UI_FONT_PATH := "res://addons/GD-Sync/UI/Fonts/Outfit-Regular.ttf"

var _font: FontFile = null
var _font_bold: FontVariation = null

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
	_font = load(UI_FONT_PATH)
	if _font != null:
		_font_bold = FontVariation.new()
		_font_bold.base_font = _font
		_font_bold.variation_embolden = 0.7

	_setup_background()
	_add_vignette()
	_style_title()

	# Detail dossier panel: dark plate with orange bottom border
	var detail_sb := StyleBoxFlat.new()
	detail_sb.bg_color = Color(0.075, 0.085, 0.105, 0.97)
	detail_sb.set_corner_radius_all(10)
	detail_sb.content_margin_left = 24
	detail_sb.content_margin_right = 24
	detail_sb.content_margin_top = 20
	detail_sb.content_margin_bottom = 22
	detail_sb.border_width_bottom = 3
	detail_sb.border_color = COL_ACCENT
	var detail: PanelContainer = $Margin/VBox/Main/Mid/Detail
	detail.add_theme_stylebox_override("panel", detail_sb)
	var header_panel: PanelContainer = $Margin/VBox/Main/Mid/CatHeader
	var head_sb := detail_sb.duplicate()
	head_sb.border_width_bottom = 0
	head_sb.content_margin_top = 12
	head_sb.content_margin_bottom = 12
	header_panel.add_theme_stylebox_override("panel", head_sb)
	if _font_bold != null:
		cat_header.add_theme_font_override("font", _font_bold)
		item_name.add_theme_font_override("font", _font_bold)
	cat_header.add_theme_font_size_override("font_size", 22)
	cat_header.add_theme_color_override("font_color", COL_TEXT_DIM)
	item_name.add_theme_font_size_override("font_size", 32)
	item_desc.add_theme_color_override("font_color", COL_TEXT_DIM)
	item_desc.add_theme_font_size_override("font_size", 16)
	item_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_style_equip_button()
	_build_stat_rows()
	_style_back_button()
	_build_hints()
	_warm_preview()

func _style_title() -> void:
	# Slash badge + bold white title, orange underline (reference lockup)
	var top: HBoxContainer = $Margin/VBox/TopBar
	var badge := SlashBadge.new()
	badge.name = "SlashBadge"
	badge.custom_minimum_size = Vector2(44, 40)
	top.add_child(badge)
	top.move_child(badge, 0)
	var title: Label = top.get_node("Title")
	title.text = "OPERATOR SELECT"
	if _font_bold != null:
		title.add_theme_font_override("font", _font_bold)
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color.WHITE)
	var underline := ColorRect.new()
	underline.color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.7)
	underline.custom_minimum_size = Vector2(0, 3)
	var vbox: VBoxContainer = $Margin/VBox
	vbox.add_child(underline)
	vbox.move_child(underline, 1)

func _add_hover_pop(b: Button) -> void:
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

func _orange_hover_plate(radius: int = 8) -> StyleBoxFlat:
	var h := StyleBoxFlat.new()
	h.bg_color = COL_ACCENT
	h.set_corner_radius_all(radius)
	h.shadow_color = Color(0.32, 0.33, 0.36, 0.55)
	h.shadow_size = 10
	h.shadow_offset = Vector2(0, 5)
	return h

func _style_equip_button() -> void:
	if _font_bold != null:
		btn_equip.add_theme_font_override("font", _font_bold)
	btn_equip.add_theme_font_size_override("font_size", 22)
	btn_equip.custom_minimum_size = Vector2(0, 56)
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

func _build_stat_rows() -> void:
	for c in stats_box.get_children():
		c.queue_free()
	for stat in [["HEALTH", "hp"], ["ARMOR", "armor"], ["MOBILITY", "mob"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		var lbl := Label.new()
		lbl.text = stat[0]
		lbl.custom_minimum_size = Vector2(130, 0)
		if _font_bold != null:
			lbl.add_theme_font_override("font", _font_bold)
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(0.8, 0.84, 0.9))
		row.add_child(lbl)
		var segs: Array = []
		for i in 10:
			var seg := ColorRect.new()
			seg.custom_minimum_size = Vector2(26, 12)
			seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			seg.color = COL_SEG_OFF
			row.add_child(seg)
			segs.append(seg)
		stats_box.add_child(row)
		stats_box.set_meta(stat[1], segs)

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

func _build_hints() -> void:
	# Bottom-right keycap hints: [A]/[D] Change · [ENTER] Equip · [ESC] Back
	var bar: HBoxContainer = $Margin/VBox/BottomBar
	bar.alignment = BoxContainer.ALIGNMENT_END
	var old: Label = bar.get_node_or_null("HintEquip")
	if old != null:
		old.queue_free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	for hint in [["A / D", "Change Operator"], ["ENTER", "Equip"], ["ESC", "Back"]]:
		row.add_child(_keycap(hint[0]))
		var lbl := Label.new()
		lbl.text = hint[1]
		if _font != null:
			lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 15)
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
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color.WHITE)
	cap.add_child(l)
	return cap

func _warm_preview() -> void:
	var we := get_node_or_null("Margin/VBox/Main/Right/Preview/SubViewport/WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		we.environment.glow_enabled = true
		we.environment.glow_intensity = 0.4
	var key := get_node_or_null("Margin/VBox/Main/Right/Preview/SubViewport/KeyLight") as DirectionalLight3D
	if key != null:
		key.light_color = Color(1.0, 0.9, 0.78)
	var rim := get_node_or_null("Margin/VBox/Main/Right/Preview/SubViewport/RimLight") as DirectionalLight3D
	if rim != null:
		rim.light_color = Color(1.0, 0.75, 0.5)
		rim.light_energy = 0.9

func _setup_background() -> void:
	# Hangar backdrop art; dark veil on top keeps UI readable.
	var bg := get_node_or_null("Background") as ColorRect
	if bg == null:
		return
	var tex := load("res://assets/bg/Operator Background.png")
	if tex != null:
		var art := TextureRect.new()
		art.name = "BgArt"
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		move_child(art, 0)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.color = Color(0.063, 0.075, 0.09, 0.45)
	else:
		bg.color = COL_BG

func _add_vignette() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.55, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.5)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, -0.5)
	gt.width = 512
	gt.height = 512
	var vignette := TextureRect.new()
	vignette.name = "OpVignette"
	vignette.texture = gt
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	move_child(vignette, 1)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Orange triple-slash badge (reference: operator select logo)
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

func _build_sidebar() -> void:
	for c in group_list.get_children():
		c.queue_free()
	cat_buttons.clear()
	var side_sb := func(active: bool) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 18
		sb.content_margin_right = 14
		sb.content_margin_top = 14
		sb.content_margin_bottom = 14
		if active:
			sb.bg_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.16)
			sb.set_border_width_all(2)
			sb.border_color = COL_ACCENT
		else:
			sb.bg_color = Color(0.075, 0.085, 0.105, 0.95)
			sb.set_border_width_all(2)
			sb.border_color = Color(0.19, 0.22, 0.27)
		return sb
	for cat in categories:
		var btn := Button.new()
		btn.text = cat.to_upper()
		btn.custom_minimum_size = Vector2(0, 64)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if _font_bold != null:
			btn.add_theme_font_override("font", _font_bold)
		btn.add_theme_font_size_override("font_size", 19)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_stylebox_override("normal", side_sb.call(false))
		btn.add_theme_stylebox_override("hover", side_sb.call(true))
		btn.add_theme_stylebox_override("pressed", side_sb.call(true))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
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
	# Sidebar highlight: active card gets orange border + tint (styles swapped via re-style)
	for c in cat_buttons:
		var btn: Button = cat_buttons[c]
		var active: bool = (c == cat)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 18
		sb.content_margin_right = 14
		sb.content_margin_top = 14
		sb.content_margin_bottom = 14
		sb.set_border_width_all(2)
		if active:
			sb.bg_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.16)
			sb.border_color = COL_ACCENT
		else:
			sb.bg_color = Color(0.075, 0.085, 0.105, 0.95)
			sb.border_color = Color(0.19, 0.22, 0.27)
		for state in ["normal", "pressed", "focus"]:
			btn.add_theme_stylebox_override(state, sb)
		btn.add_theme_stylebox_override("hover", _orange_hover_plate(8))
		btn.add_theme_color_override("font_color", Color.WHITE if active else Color(0.82, 0.86, 0.92))
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		_add_hover_pop(btn)
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
			btn.custom_minimum_size = Vector2(0, 56)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if _font_bold != null:
				btn.add_theme_font_override("font", _font_bold)
			btn.add_theme_font_size_override("font_size", 19)
			btn.focus_mode = Control.FOCUS_NONE
			btn.add_theme_stylebox_override("normal", _op_card_sb(false))
			btn.add_theme_stylebox_override("hover", _orange_hover_plate(8))
			btn.add_theme_stylebox_override("pressed", _op_card_sb(true))
			btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			btn.add_theme_color_override("font_color", Color(0.85, 0.89, 0.94))
			btn.add_theme_color_override("font_hover_color", Color.WHITE)
			btn.add_theme_color_override("font_pressed_color", Color.WHITE)
			btn.pressed.connect(_select.bind(op["id"]))
			_add_hover_pop(btn)
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

func _op_card_sb(hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	if hover:
		sb.bg_color = Color(0.12, 0.135, 0.16, 0.97)
		sb.border_width_left = 3
		sb.border_color = COL_ACCENT
	else:
		sb.bg_color = Color(0.075, 0.085, 0.105, 0.95)
		sb.border_width_bottom = 2
		sb.border_color = Color(0.19, 0.22, 0.27)
	return sb

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
	# Ability line: skill name + description (reference dossier)
	var skill := str(op.get("skill", ""))
	var paren := skill.find("(")
	if paren > 0:
		var skill_name := skill.substr(0, paren).strip_edges()
		var skill_desc := skill.substr(paren).trim_prefix("(").trim_suffix(")")
		item_desc.text = "»  %s\n%s   ·   Speed: %s" % [skill_name, skill_desc, op.get("speed", "")]
	else:
		item_desc.text = "»  %s   ·   Speed: %s" % [skill, op.get("speed", "")]
	var fills := {
		"hp": clampf(float(op.get("health", 100)) / 200.0, 0.0, 1.0),
		"armor": clampf(float(op.get("armor", 50)) / 100.0, 0.0, 1.0),
		"mob": _mobility_fill(str(op.get("speed", "Normal"))),
	}
	for key in fills:
		var segs: Array = stats_box.get_meta(key)
		var lit := int(round(fills[key] * 10.0))
		for i in segs.size():
			segs[i].color = COL_ACCENT if i < lit else COL_SEG_OFF
	# Row highlight: selected card gets orange border
	for cid in op_rows:
		var row: Button = op_rows[cid]
		var sel: bool = str(cid) == selected_id
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 18
		sb.content_margin_right = 14
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		if sel:
			sb.bg_color = Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 0.13)
			sb.set_border_width_all(2)
			sb.border_color = COL_ACCENT
		else:
			sb.bg_color = Color(0.075, 0.085, 0.105, 0.95)
			sb.border_width_bottom = 2
			sb.border_color = Color(0.19, 0.22, 0.27)
		for state in ["normal", "pressed", "focus"]:
			row.add_theme_stylebox_override(state, sb)
		row.add_theme_color_override("font_color", Color.WHITE if sel else Color(0.85, 0.89, 0.94))
	if GlobalData.equipped_operator == op["id"]:
		btn_equip.text = "EQUIPPED"
		btn_equip.disabled = true
	else:
		btn_equip.text = "EQUIP OPERATOR"
		btn_equip.disabled = false
	if preview_char and preview_char.has_method("set_tint"):
		preview_char.set_tint(CAT_TINT.get(current_category, COL_ACCENT))

func _cycle_operator(dir: int) -> void:
	var ids := op_rows.keys()
	if ids.is_empty():
		return
	var idx := ids.find(selected_id)
	if idx < 0:
		idx = 0
	idx = wrapi(idx + dir, 0, ids.size())
	_select(ids[idx])

func _on_equip_pressed() -> void:
	if GlobalData.equipped_operator == selected_id:
		return
	GlobalData.equipped_operator = selected_id
	_set_category(current_category, selected_id)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				_on_equip_pressed()
			KEY_A, KEY_LEFT:
				_cycle_operator(-1)
			KEY_D, KEY_RIGHT:
				_cycle_operator(1)
			KEY_ENTER:
				_on_equip_pressed()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
