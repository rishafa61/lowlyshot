extends Node3D

@onready var nav_region = $NavRegion
@onready var objective_label = $UI/ObjectiveMargin/Panel/ObjectiveLabel
@onready var exit_area = $ExitArea
@onready var exit_visual = $ExitArea/Visual
@onready var victory_overlay = $UI/VictoryOverlay
@onready var btn_main_menu = $UI/VictoryOverlay/Center/VBox/BtnMainMenu

var total_enemies = 0
var is_exit_open = false
var match_over = false

func _ready():
	# Navigation mesh should be baked in the Editor by clicking 'Bake NavigationMesh' on the NavRegion node.
	
	var enemies = get_tree().get_nodes_in_group("enemy")
	total_enemies = enemies.size()
	
	# Disconnect old signals if any (to prevent double connections)
	exit_area.body_entered.connect(_on_exit_entered)
	btn_main_menu.pressed.connect(_on_main_menu_pressed)
	
	# Set exit visual to red (locked) initially
	exit_visual.material.albedo_color = Color(1, 0, 0, 0.2)
	exit_visual.material.emission = Color(1, 0, 0, 1)

func _process(_delta):
	if match_over: return
	
	var enemies = get_tree().get_nodes_in_group("enemy")
	var alive = 0
	for e in enemies:
		if not e.get("is_dead"):
			alive += 1
	
	if alive > 0:
		objective_label.text = "Eliminate all hostiles: " + str(alive) + " remaining"
	else:
		if not is_exit_open:
			open_exit()

func open_exit():
	is_exit_open = true
	objective_label.text = "OBJECTIVE COMPLETE: PROCEED TO EXTRACTION (GREEN ZONE)"
	objective_label.add_theme_color_override("font_color", Color(0, 1, 0.2, 1))
	
	# Turn exit visual green
	exit_visual.material.albedo_color = Color(0, 1, 0.2, 0.4)
	exit_visual.material.emission = Color(0, 1, 0.2, 1)

func _on_exit_entered(body):
	if body.name == "Player" and is_exit_open and not match_over:
		match_over = true
		victory_overlay.show()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_main_menu_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
