extends Control

@onready var btn_back = $TopBar/BtnBack
@onready var tabs = {
	"Primary": $TopBar/TabPrimary,
	"Secondary": $TopBar/TabSecondary,
	"Melee": $TopBar/TabMelee,
	"Utility": $TopBar/TabUtility
}

@onready var item_name_label = $Content/LeftPanel/ItemName
@onready var bar_dmg = $Content/LeftPanel/Stats/StatDmg/ProgressBar
@onready var val_dmg = $Content/LeftPanel/Stats/StatDmg/Header/Value
@onready var bar_rng = $Content/LeftPanel/Stats/StatRng/ProgressBar
@onready var val_rng = $Content/LeftPanel/Stats/StatRng/Header/Value
@onready var bar_stab = $Content/LeftPanel/Stats/StatStab/ProgressBar
@onready var val_stab = $Content/LeftPanel/Stats/StatStab/Header/Value
@onready var bar_fr = $Content/LeftPanel/Stats/StatFr/ProgressBar
@onready var val_fr = $Content/LeftPanel/Stats/StatFr/Header/Value
@onready var btn_action = $Content/LeftPanel/BtnAction
@onready var grid = $Content/RightPanel/ScrollContainer/GridContainer
@onready var currency_label = $TopBar/Currency



var current_tab = "Primary"
var selected_item = null


func _ready():
	btn_back.pressed.connect(_on_back_pressed)
	tabs["Primary"].pressed.connect(func(): set_tab("Primary"))
	tabs["Secondary"].pressed.connect(func(): set_tab("Secondary"))
	tabs["Melee"].pressed.connect(func(): set_tab("Melee"))
	tabs["Utility"].pressed.connect(func(): set_tab("Utility"))
	btn_action.pressed.connect(_on_action_pressed)
	
	currency_label.visible = false
	set_tab("Primary")

func set_tab(tab_name: String):
	current_tab = tab_name
	for t in tabs.keys():
		if t == tab_name:
			tabs[t].add_theme_stylebox_override("normal", get_node("TopBar/TabPrimary").get_theme_stylebox("normal")) # Mock active style
		else:
			tabs[t].add_theme_stylebox_override("normal", get_node("TopBar/TabSecondary").get_theme_stylebox("normal")) # Mock inactive style
	
	# Refresh grid
	for c in grid.get_children():
		c.queue_free()
		
	for item in GlobalData.weapons[tab_name]:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(150, 150)
		btn.text = item["name"]
		if item.get("equipped", false):
			btn.text += "\n(Equipped)"
		if item == selected_item:
			btn.modulate = Color(1, 0.85, 0.4) # highlight current preview
		
		btn.pressed.connect(func(): select_item(item))
		grid.add_child(btn)
		
	# Keep the current preview when refreshing (e.g. after equipping);
	# only fall back to the first item when nothing valid is selected.
	if selected_item != null and selected_item in GlobalData.weapons[tab_name]:
		select_item(selected_item)
	elif GlobalData.weapons[tab_name].size() > 0:
		select_item(GlobalData.weapons[tab_name][0])

# ponytail: MAX_STAT only scales 0-100 bar fills; add per-category max tracking when adding high-tier gear.
const MAX_STAT := 100.0

func select_item(item):
	selected_item = item
	item_name_label.text = item["name"]
	
	# Raw numbers match the values combat actually uses.
	var dmg := float(item.get("dmg", 0.0))
	var rng := float(item.get("rng", 0.0))
	var stab := float(item.get("stab", 0.0))
	# fire_rate is seconds-per-shot in combat; show rounds-per-second.
	var rps := 0.0
	if float(item.get("fire_rate", 0.0)) > 0.0:
		rps = 1.0 / float(item["fire_rate"])
	# Normalize the bar fills so they stay comparable across tabs.
	var fr_fill := clampf(rps * 10.0, 0.0, MAX_STAT)
	
	val_dmg.text = str(int(dmg))
	val_rng.text = str(int(rng))
	val_stab.text = str(int(stab))
	val_fr.text = "%.1f" % rps
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(bar_dmg, "value", clampf(dmg, 0.0, MAX_STAT), 0.2)
	tween.tween_property(bar_rng, "value", clampf(rng, 0.0, MAX_STAT), 0.2)
	tween.tween_property(bar_stab, "value", clampf(stab, 0.0, MAX_STAT), 0.2)
	tween.tween_property(bar_fr, "value", fr_fill, 0.2)
	
	update_action_button()

func update_action_button():
	if not selected_item: return
	
	if selected_item.get("equipped", false):
		btn_action.text = "EQUIPPED"
		btn_action.modulate = Color(0.5, 0.5, 0.5, 1) # Gray out
	else:
		btn_action.text = "EQUIP"
		btn_action.modulate = Color(1, 0.5, 0, 1) # Orange

func _on_action_pressed():
	if not selected_item: return
	
	if not selected_item.get("equipped", false):
		# Unequip all others in this category
		for i in GlobalData.weapons[current_tab]:
			i["equipped"] = false
		selected_item["equipped"] = true
		update_action_button()
		set_tab(current_tab) # Refresh grid names

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
