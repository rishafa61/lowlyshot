extends Node

# Audio
var bgm_vol = 80.0
var sfx_vol = 15.0
var mic_vol = 100.0

# Gameplay
var hip_sensitivity_mult = 1.0
var scope_sensitivity_mult = 0.5
var ads_offset_x = 0.03 # scoped viewmodel horizontal nudge (right+)
var ads_offset_y = 0.05 # scoped viewmodel vertical nudge (up+)
var ads_offset_z = 0.235 # scoped viewmodel depth nudge (far-)
var ads_rot_y = -3.5 # scoped viewmodel yaw (degrees)
var hip_offset_x = 0.0 # hipfire viewmodel horizontal nudge (right+)
var hip_offset_y = 0.0 # hipfire viewmodel vertical nudge (up+)
var hip_offset_z = 0.0 # hipfire viewmodel depth nudge (far-)
var hip_rot_y = 0.0 # hipfire viewmodel yaw (degrees)

# Per-weapon viewmodel offsets (Debug Mode tuner): weapon_id ->
# {ads_off: Vector3, ads_rot: float, hip_off: Vector3, hip_rot: float}.
# Weapons without an entry fall back to the global defaults above, so new
# weapons need no tuning before they look right.
var vm_offsets := {}

func get_vm_off(wid: String, mode: String) -> Vector3:
	var e: Dictionary = vm_offsets.get(wid, {})
	if e.has(mode + "_off"):
		return e[mode + "_off"]
	if mode == "ads":
		return Vector3(ads_offset_x, ads_offset_y, ads_offset_z)
	return Vector3(hip_offset_x, hip_offset_y, hip_offset_z)

func get_vm_rot(wid: String, mode: String) -> float:
	var e: Dictionary = vm_offsets.get(wid, {})
	if e.has(mode + "_rot"):
		return e[mode + "_rot"]
	return ads_rot_y if mode == "ads" else hip_rot_y

func set_vm_off(wid: String, mode: String, v: Vector3) -> void:
	var e: Dictionary = vm_offsets.get(wid, {})
	e[mode + "_off"] = v
	vm_offsets[wid] = e

func set_vm_rot(wid: String, mode: String, v: float) -> void:
	var e: Dictionary = vm_offsets.get(wid, {})
	e[mode + "_rot"] = v
	vm_offsets[wid] = e

# Visual
var graphics_quality = 2 # 0: Low, 1: Med, 2: High
var fps_limit = 0 # 0=60, 1=120, etc
var windowed: bool = false # fullscreen by default; true = windowed

# Navigation
var previous_scene: String = "res://scenes/ui/main_menu.tscn"

var current_minimap: String = ""

# Multiplayer match fill (host chooses in the Play menu)
var online_bots_enabled: bool = true

const SETTINGS_PATH := "user://settings.cfg"
const PROFILES_DIR := "user://profiles"

## Identity for per-user config. "default" = no known user (falls back to the
## legacy global settings.cfg); otherwise user://profiles/<name>/settings.cfg.
## Future per-user files (loadout/equipment) go in profile_dir() too.
var profile_key := "default"

func _ready() -> void:
	_load()
	_await_identity()

## SteamSync initialises after this autoload and async — once it reports a
## persona, switch to that user's profile and re-read their values.
func _await_identity() -> void:
	var ss := get_node_or_null("/root/SteamSync")
	if ss == null:
		return
	if ss.is_steam_running:
		_apply_identity(ss)
		return
	var got := [false]
	ss.steam_initialized_status.connect(func(_ok: bool) -> void:
		if got[0]:
			return
		got[0] = true
		_apply_identity(ss)
	, CONNECT_ONE_SHOT)
	for i in 300: # ~5s cap; failure also emits, so this only guards hangs
		await get_tree().process_frame
		if got[0]:
			return
	_apply_identity(ss)

func _apply_identity(ss: Node) -> void:
	if ss.is_steam_running and str(ss.persona_name) != "Player":
		var key := _safe_name(str(ss.persona_name))
		if key != profile_key:
			profile_key = key
			_load() # this user's values replace whatever "default" loaded
		return
	# No usable identity: stay on the default profile.

func _safe_name(s: String) -> String:
	var out := ""
	for ch in s:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch in ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "-", "_", " ", "."]:
			out += ch
	var trimmed := out.strip_edges()
	return trimmed if trimmed != "" else "default"

func _settings_path() -> String:
	if profile_key == "default":
		return SETTINGS_PATH
	return "%s/%s/settings.cfg" % [PROFILES_DIR, profile_key]

## Where this user's other persistent files live (loadout/equipment later).
func profile_dir() -> String:
	if profile_key == "default":
		return "user://"
	return "%s/%s" % [PROFILES_DIR, profile_key]

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_settings_path()) != OK and profile_key != "default":
		# First run for this user: inherit the old global config.
		cfg.load(SETTINGS_PATH)
	if cfg.get_sections().size() > 0:
		bgm_vol = cfg.get_value("audio", "bgm", bgm_vol)
		sfx_vol = cfg.get_value("audio", "sfx", sfx_vol)
		mic_vol = cfg.get_value("audio", "mic", mic_vol)
		hip_sensitivity_mult = cfg.get_value("gameplay", "hip", hip_sensitivity_mult)
		scope_sensitivity_mult = cfg.get_value("gameplay", "scope", scope_sensitivity_mult)
		ads_offset_x = cfg.get_value("gameplay", "ads_x", ads_offset_x)
		ads_offset_y = cfg.get_value("gameplay", "ads_y", ads_offset_y)
		ads_offset_z = cfg.get_value("gameplay", "ads_z", ads_offset_z)
		ads_rot_y = cfg.get_value("gameplay", "ads_rot", ads_rot_y)
		hip_offset_x = cfg.get_value("gameplay", "hip_x", hip_offset_x)
		hip_offset_y = cfg.get_value("gameplay", "hip_y", hip_offset_y)
		hip_offset_z = cfg.get_value("gameplay", "hip_z", hip_offset_z)
		hip_rot_y = cfg.get_value("gameplay", "hip_rot", hip_rot_y)
		graphics_quality = cfg.get_value("visual", "quality", graphics_quality)
		fps_limit = cfg.get_value("visual", "fps", fps_limit)
		windowed = cfg.get_value("visual", "windowed", false)
		online_bots_enabled = cfg.get_value("multiplayer", "bots", online_bots_enabled)
		# Per-weapon viewmodel offsets saved by the Debug Mode tuner ("vm_<wid>" sections)
		for sec in cfg.get_sections():
			var s := str(sec)
			if not s.begins_with("vm_"):
				continue
			var e: Dictionary = {}
			if cfg.has_section_key(sec, "ads_off"): e["ads_off"] = cfg.get_value(sec, "ads_off")
			if cfg.has_section_key(sec, "ads_rot"): e["ads_rot"] = cfg.get_value(sec, "ads_rot")
			if cfg.has_section_key(sec, "hip_off"): e["hip_off"] = cfg.get_value(sec, "hip_off")
			if cfg.has_section_key(sec, "hip_rot"): e["hip_rot"] = cfg.get_value(sec, "hip_rot")
			if not e.is_empty():
				vm_offsets[s.substr(3)] = e
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
	if profile_key != "default":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile_dir()))
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "bgm", bgm_vol)
	cfg.set_value("audio", "sfx", sfx_vol)
	cfg.set_value("audio", "mic", mic_vol)
	cfg.set_value("gameplay", "hip", hip_sensitivity_mult)
	cfg.set_value("gameplay", "scope", scope_sensitivity_mult)
	cfg.set_value("gameplay", "ads_x", ads_offset_x)
	cfg.set_value("gameplay", "ads_y", ads_offset_y)
	cfg.set_value("gameplay", "ads_z", ads_offset_z)
	cfg.set_value("gameplay", "ads_rot", ads_rot_y)
	cfg.set_value("gameplay", "hip_x", hip_offset_x)
	cfg.set_value("gameplay", "hip_y", hip_offset_y)
	cfg.set_value("gameplay", "hip_z", hip_offset_z)
	cfg.set_value("gameplay", "hip_rot", hip_rot_y)
	cfg.set_value("visual", "quality", graphics_quality)
	cfg.set_value("visual", "fps", fps_limit)
	cfg.set_value("visual", "windowed", windowed)
	cfg.set_value("multiplayer", "bots", online_bots_enabled)
	for wid: String in vm_offsets:
		var e: Dictionary = vm_offsets[wid]
		if e.has("ads_off"): cfg.set_value("vm_" + wid, "ads_off", e["ads_off"])
		if e.has("ads_rot"): cfg.set_value("vm_" + wid, "ads_rot", e["ads_rot"])
		if e.has("hip_off"): cfg.set_value("vm_" + wid, "hip_off", e["hip_off"])
		if e.has("hip_rot"): cfg.set_value("vm_" + wid, "hip_rot", e["hip_rot"])
	cfg.save(_settings_path())
