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
var windowed: bool = false # fullscreen by default; true = windowed

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
		windowed = cfg.get_value("visual", "windowed", false)
		online_bots_enabled = cfg.get_value("multiplayer", "bots", online_bots_enabled)
	set_windowed(windowed)

func set_windowed(on: bool) -> void:
	windowed = on
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		# Size down to standard 1280x720 window and center on primary screen
		var screen = DisplayServer.window_get_current_screen()
		var scr_size = DisplayServer.screen_get_size(screen)
		var win_size = Vector2i(1280, 720)
		if scr_size.x > 0 and scr_size.y > 0 and (win_size.x >= scr_size.x or win_size.y >= scr_size.y):
			win_size = Vector2i(int(scr_size.x * 0.8), int(scr_size.y * 0.8))
		DisplayServer.window_set_size(win_size)
		var center_pos = Vector2i(int((scr_size.x - win_size.x) / 2.0), int((scr_size.y - win_size.y) / 2.0))
		DisplayServer.window_set_position(center_pos)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

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
