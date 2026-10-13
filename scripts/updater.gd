extends Node

## In-game updater: friend presses UPDATE, downloads the latest zip, swaps the
## game files and relaunches. No manual Google Drive round-trips.
##
## Host side (you): after exporting, upload TWO files:
##   1. CallOfDiddy_Steam_Multiplayer.zip  (Drive -> replace file keeps the ID)
##   2. update.txt containing one line:    <version>|<direct zip url>
##      e.g. 1.0.3|https://drive.google.com/uc?export=download&id=FILE_ID
## Point MANIFEST_URL at update.txt's direct link and bump VERSION here before
## exporting. A friend can override the manifest without a re-export by putting
## a URL into user://update_url.txt.
## ponytail: no signature/hash check on the zip; add SHA-256 verification when
## builds ship beyond the friend group.

signal update_check_done(available: bool, latest_version: String)
signal update_downloaded()
signal update_failed(reason: String)

const VERSION := "1.0.2"
const DEFAULT_MANIFEST_URL := "https://drive.google.com/uc?export=download&id=PUT_UPDATE_TXT_FILE_ID_HERE"

var latest_version := ""

var _http: HTTPRequest
var _zip_url := ""
var _downloading := false

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 0 # zip can be big; no whole-request timeout
	_http.follow_redirects = true # Drive uc?export=download links 302 first
	_http.accept_gzip = true
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func _manifest_url() -> String:
	var f := FileAccess.open("user://update_url.txt", FileAccess.READ)
	if f:
		var u := f.get_line().strip_edges()
		if u.begins_with("http"):
			return u
	return DEFAULT_MANIFEST_URL

func check_for_updates() -> void:
	if _downloading:
		return
	var url := _manifest_url()
	# Unconfigured default: stay quiet, don't spam player with 404 toast
	if "PUT_UPDATE_TXT_FILE_ID_HERE" in url:
		return
	_http.download_file = ""
	if _http.request(url) != OK:
		update_failed.emit("Update check: bad URL")

## Fetches the zip. Must run from an exported build (editor exe can't be swapped).
func download_update() -> bool:
	if _zip_url == "":
		return false
	if OS.has_feature("editor"):
		update_failed.emit("Updates only apply to the exported game")
		return false
	_downloading = true
	_http.download_file = OS.get_user_data_dir() + "/update.zip"
	if _http.request(_zip_url) != OK:
		_downloading = false
		_http.download_file = ""
		update_failed.emit("Download could not start")
		return false
	return true

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_downloading = false
		_http.download_file = ""
		update_failed.emit("Update server error (HTTP %d)" % code)
		return
	if _downloading:
		_downloading = false
		_http.download_file = ""
		update_downloaded.emit()
		_apply_update()
		return
	# Manifest line: <version>|<zip url>
	var parts := body.get_string_from_utf8().strip_edges().split("|")
	if parts.size() < 2 or parts[0].strip_edges() == "" or not parts[1].strip_edges().begins_with("http"):
		update_failed.emit("Bad update manifest (expected version|url)")
		return
	latest_version = parts[0].strip_edges()
	_zip_url = parts[1].strip_edges()
	update_check_done.emit(latest_version != VERSION, latest_version)

## Writes a batch file that swaps the files after we quit, then relaunches.
func _apply_update() -> void:
	var exe := OS.get_executable_path()
	var game_dir := exe.get_base_dir()
	var zip := OS.get_user_data_dir() + "/update.zip"
	var bat := OS.get_user_data_dir() + "/update.bat"
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f == null:
		update_failed.emit("Could not write updater script")
		return
	# Rename allows overwriting a running exe on Windows; .old.exe is cleaned
	# up on the next run.
	f.store_line("@echo off")
	f.store_line("timeout /t 2 /nobreak >nul")
	f.store_line('if exist "%s\\Call Of Diddy.old.exe" del "%s\\Call Of Diddy.old.exe" 2>nul' % [game_dir, game_dir])
	f.store_line('move /y "%s" "%s\\Call Of Diddy.old.exe" 2>nul' % [exe, game_dir])
	f.store_line('powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force \'%s\' \'%s\'"' % [zip, game_dir])
	f.store_line('del "%s" 2>nul' % zip)
	f.store_line('start "" "%s"' % exe)
	f.store_line('del "%s"' % bat)
	f.close()
	if OS.create_process("cmd.exe", ["/c", bat]) == 0:
		update_failed.emit("Could not launch updater")
		return
	get_tree().quit()
