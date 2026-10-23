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
var windowed: bool = false # false = fullscreen (default), true = windowed

# Navigation
var previous_scene: String = "res://scenes/ui/main_menu.tscn"

var current_minimap: String = ""

# Multiplayer match fill (host chooses in the Play menu, off by default)
var online_bots_enabled: bool = false

const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		bgm_vol = cfg.get_value("audio", "bgm", bgm_vol)
		sfx_vol = cfg.get_value("audio", "sfx", sfx_vol)
		mic_vol = cfg.get_value("audio", "mic", mic_vol)
		hip_sensitivity_mult = cfg.get_value("gameplay", "hip", hip_sensitivity_mult)
		scope_sensitivity_mult = cfg.get_value("gameplay", "scope", scope_sensitivity_mult)
		graphics_quality = cfg.get_value("visual", "quality", graphics_quality)
		fps_limit = cfg.get_value("visual", "fps", fps_limit)
		if cfg.has_section_key("visual", "fullscreen"):
			windowed = not cfg.get_value("visual", "fullscreen", not windowed) # migrate old key
		else:
			windowed = cfg.get_value("visual", "windowed", windowed)
		online_bots_enabled = cfg.get_value("multiplayer", "bots", online_bots_enabled)
	set_windowed(windowed)

func set_windowed(on: bool) -> void:
	windowed = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED if on else DisplayServer.WINDOW_MODE_FULLSCREEN)

var fullscreen: bool:
	get: return not windowed
	set(val): set_windowed(not val)

func set_fullscreen(on: bool) -> void:
	set_windowed(not on)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "bgm", bgm_vol)
	cfg.set_value("audio", "sfx", sfx_vol)
	cfg.set_value("audio", "mic", mic_vol)
	cfg.set_value("gameplay", "hip", hip_sensitivity_mult)
	cfg.set_value("gameplay", "scope", scope_sensitivity_mult)
	cfg.set_value("visual", "quality", graphics_quality)
	cfg.set_value("visual", "fps", fps_limit)
	cfg.set_value("visual", "windowed", windowed)
	cfg.set_value("multiplayer", "bots", online_bots_enabled)
	cfg.save(SETTINGS_PATH)
