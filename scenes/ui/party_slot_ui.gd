extends Control

## Single party slot frame. Empty = "+" invite button.
## Filled = ally standby marker. Steam64 invite hook lands in _on_invite_pressed().

signal invite_pressed(slot_index: int)
signal kick_pressed(slot_index: int)

var slot_index: int = -1
var player_name: String = ""
var is_filled: bool = false

@onready var btn_slot: Button = $VBox/BtnSlot
@onready var label_name: Label = $VBox/LabelName
@onready var status_dot: ColorRect = $VBox/BtnSlot/StatusDot

@export var style_empty: StyleBox
@export var style_empty_hover: StyleBox
@export var style_filled: StyleBox
@export var style_filled_hover: StyleBox

func _ready() -> void:
	btn_slot.pressed.connect(_on_slot_pressed)
	# Pop-out effect on hover
	btn_slot.pivot_offset = btn_slot.size / 2.0
	btn_slot.mouse_entered.connect(func():
		btn_slot.pivot_offset = btn_slot.size / 2.0
		var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(btn_slot, "scale", Vector2.ONE * 1.08, 0.1))
	btn_slot.mouse_exited.connect(func():
		var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(btn_slot, "scale", Vector2.ONE, 0.1))
	_refresh()

func setup(index: int) -> void:
	slot_index = index

func fill(player: String) -> void:
	player_name = player
	is_filled = true
	_refresh()

func clear() -> void:
	player_name = ""
	is_filled = false
	_refresh()

func _on_slot_pressed() -> void:
	if is_filled:
		kick_pressed.emit(slot_index)
	else:
		# ponytail: Steam invite hook — call Steam invite friend by SteamID64 here when Steam API lands.
		invite_pressed.emit(slot_index)

func _refresh() -> void:
	if is_filled:
		btn_slot.text = "👤"
		btn_slot.tooltip_text = "Click to kick " + player_name
		label_name.text = player_name
		label_name.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		status_dot.visible = true
		if style_filled:
			btn_slot.add_theme_stylebox_override("normal", style_filled)
			btn_slot.add_theme_stylebox_override("hover", style_filled_hover)
			btn_slot.add_theme_stylebox_override("pressed", style_filled_hover)
	else:
		btn_slot.text = "+"
		btn_slot.tooltip_text = "Invite friend (Steam)"
		label_name.text = "INVITE"
		label_name.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		status_dot.visible = false
		if style_empty:
			btn_slot.add_theme_stylebox_override("normal", style_empty)
			btn_slot.add_theme_stylebox_override("hover", style_empty_hover)
			btn_slot.add_theme_stylebox_override("pressed", style_empty_hover)
