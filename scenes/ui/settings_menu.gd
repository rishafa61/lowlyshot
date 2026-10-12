extends Control

@onready var btn_back = $TopBar/BtnBack
@onready var tabs = {
	"Visual": $TopBar/TabVisual,
	"Audio": $TopBar/TabAudio,
	"Gameplay": $TopBar/TabGameplay,
	"Controls": $TopBar/TabControls
}

@onready var panels = {
	"Visual": $Content/TabVisualPanel,
	"Audio": $Content/TabAudioPanel,
	"Gameplay": $Content/TabGameplayPanel,
	"Controls": $Content/TabControlsPanel
}

# Sliders
@onready var slider_hip = $Content/TabGameplayPanel/HBoxHipSens/SliderHipSens
@onready var slider_scope = $Content/TabGameplayPanel/HBoxScopeSens/SliderScopeSens
@onready var spin_hip = $Content/TabGameplayPanel/HBoxHipSens/SpinBoxHip
@onready var spin_scope = $Content/TabGameplayPanel/HBoxScopeSens/SpinBoxScope

func _ready():
	btn_back.pressed.connect(_on_back_pressed)
	
	tabs["Visual"].pressed.connect(func(): set_tab("Visual"))
	tabs["Audio"].pressed.connect(func(): set_tab("Audio"))
	tabs["Gameplay"].pressed.connect(func(): set_tab("Gameplay"))
	tabs["Controls"].pressed.connect(func(): set_tab("Controls"))
	
	# Connect sliders to GlobalSettings
	slider_hip.value = GlobalSettings.hip_sensitivity_mult
	spin_hip.value = GlobalSettings.hip_sensitivity_mult
	slider_hip.value_changed.connect(_on_hip_changed)
	spin_hip.value_changed.connect(_on_hip_changed_from_spin)
	
	slider_scope.value = GlobalSettings.scope_sensitivity_mult
	spin_scope.value = GlobalSettings.scope_sensitivity_mult
	slider_scope.value_changed.connect(_on_scope_changed)
	spin_scope.value_changed.connect(_on_scope_changed_from_spin)
	
	set_tab("Visual")

func set_tab(tab_name: String):
	for k in panels.keys():
		panels[k].visible = (k == tab_name)
		
		if k == tab_name:
			tabs[k].modulate = Color(1, 0.8, 0, 1) # Yellow active
		else:
			tabs[k].modulate = Color(1, 1, 1, 1)


func _on_hip_changed(val: float):
	GlobalSettings.hip_sensitivity_mult = val
	spin_hip.value = val

func _on_hip_changed_from_spin(val: float):
	GlobalSettings.hip_sensitivity_mult = val
	slider_hip.value = val

func _on_scope_changed(val: float):
	GlobalSettings.scope_sensitivity_mult = val
	spin_scope.value = val

func _on_scope_changed_from_spin(val: float):
	GlobalSettings.scope_sensitivity_mult = val
	slider_scope.value = val


func _on_back_pressed():
	get_tree().change_scene_to_file(GlobalSettings.previous_scene)
