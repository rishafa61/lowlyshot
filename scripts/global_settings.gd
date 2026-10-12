extends Node

# Audio
var bgm_vol = 80.0
var sfx_vol = 100.0
var mic_vol = 100.0

# Gameplay
var hip_sensitivity_mult = 1.0
var scope_sensitivity_mult = 0.5

# Visual
var graphics_quality = 2 # 0: Low, 1: Med, 2: High
var fps_limit = 0 # 0=60, 1=120, etc

# Navigation
var previous_scene: String = "res://scenes/ui/main_menu.tscn"

var current_minimap: String = ""
