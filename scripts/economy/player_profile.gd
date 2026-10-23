extends Node
## PlayerProfile — persistent wallet + career stats + match history.
## Autoloaded as "PlayerProfile". Saves to user://player_profile.json.
## Currency feeds the future weapon shop / operator unlocks (see GlobalData ponytail).

signal wallet_changed
signal payroll_ready(payroll: Dictionary)

const SAVE_PATH := "user://player_profile.json"
const HISTORY_CAP := 50

# Payroll rules (per multiplayer match)
const PAYOUT_PLAY_CASH := 250        # just for playing
const PAYOUT_WIN_CASH := 750
const PAYOUT_WIN_GOLD := 25
const PAYOUT_DRAW_CASH := 375
const PAYOUT_DRAW_GOLD := 10
const PAYOUT_PER_KILL_CASH := 50
const PAYOUT_PER_HEADSHOT_CASH := 25

var cash: int = 0
var gold: int = 0

# Career totals
var stats: Dictionary = {
	"matches": 0, "wins": 0, "losses": 0, "draws": 0,
	"kills": 0, "deaths": 0, "assists": 0, "headshots": 0,
}

# Newest first: { mode, result, kills, deaths, headshots, cash, gold, timestamp }
var history: Array = []

# Per-match accumulators (fed by GlobalData.kill_occurred while tracking)
var _tracking := false
var _mode := ""
var _m_kills := 0
var _m_deaths := 0
var _m_headshots := 0

func _ready() -> void:
	_load()
	_ensure_connected()

func _ensure_connected() -> void:
	var gd = get_node_or_null("/root/GlobalData")
	if gd and gd.has_signal("kill_occurred") and not gd.kill_occurred.is_connected(_on_kill_occurred):
		gd.kill_occurred.connect(_on_kill_occurred)

# ---------------- Match tracking ----------------

func start_match_tracking(mode: String) -> void:
	_ensure_connected()
	_tracking = true
	_mode = mode
	_m_kills = 0
	_m_deaths = 0
	_m_headshots = 0

func is_tracking() -> bool:
	return _tracking

func _on_kill_occurred(killer: String, _kf: String, _w: String, victim: String, _vf: String) -> void:
	if not _tracking:
		return
	var me := local_name()
	if killer == me:
		_m_kills += 1
		# GlobalData._last_kill_headshot is set by register_kill right before
		# the signal fires — synchronous, so this read is safe.
		# ponytail: per-kill payload on the signal instead, when a second
		# consumer needs it.
		if get_node_or_null("/root/GlobalData") != null and GlobalData.get("_last_kill_headshot") == true:
			_m_headshots += 1
	if victim == me:
		_m_deaths += 1

## Resolves the local player's scoreboard name from the active manager.
func local_name() -> String:
	var managers := get_tree().get_nodes_in_group("multiplayer_manager")
	if managers.is_empty():
		return "Player"
	var mgr = managers[0]
	var peer := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var pdata = mgr.get("players_data")
	if pdata == null:
		return "Player"
	return str(pdata.get(peer, {}).get("name", "Player"))

## Ends tracking for one match, pays out, records stats + history.
## result: "win" | "loss" | "draw"
func finish_match(result: String) -> Dictionary:
	var lines: Array = [] # [label, cash, gold]
	var cash_out := PAYOUT_PLAY_CASH
	lines.append(["Match played", PAYOUT_PLAY_CASH, 0])
	var gold_out := 0
	match result:
		"win":
			cash_out += PAYOUT_WIN_CASH
			gold_out += PAYOUT_WIN_GOLD
			lines.append(["Victory bonus", PAYOUT_WIN_CASH, PAYOUT_WIN_GOLD])
		"draw":
			cash_out += PAYOUT_DRAW_CASH
			gold_out += PAYOUT_DRAW_GOLD
			lines.append(["Draw bonus", PAYOUT_DRAW_CASH, PAYOUT_DRAW_GOLD])
		_:
			lines.append(["Defeat bonus", 0, 0])
	if _m_kills > 0:
		var kc := _m_kills * PAYOUT_PER_KILL_CASH
		cash_out += kc
		lines.append(["Kills × %d" % _m_kills, kc, 0])
	if _m_headshots > 0:
		var hc := _m_headshots * PAYOUT_PER_HEADSHOT_CASH
		cash_out += hc
		lines.append(["Headshots × %d" % _m_headshots, hc, 0])

	cash += cash_out
	gold += gold_out
	stats["matches"] += 1
	match result:
		"win": stats["wins"] += 1
		"draw": stats["draws"] += 1
		_: stats["losses"] += 1
	stats["kills"] += _m_kills
	stats["deaths"] += _m_deaths
	stats["headshots"] += _m_headshots

	history.push_front({
		"mode": _mode, "result": result,
		"kills": _m_kills, "deaths": _m_deaths, "headshots": _m_headshots,
		"cash": cash_out, "gold": gold_out,
		"timestamp": Time.get_datetime_string_from_system(),
	})
	if history.size() > HISTORY_CAP:
		history.resize(HISTORY_CAP)

	_tracking = false
	_m_kills = 0
	_m_deaths = 0
	_m_headshots = 0
	save()
	wallet_changed.emit()
	var payroll := {
		"mode": _mode, "result": result, "lines": lines,
		"cash": cash_out, "gold": gold_out,
		"kills": stats["kills"], "deaths": stats["deaths"],
	}
	payroll_ready.emit(payroll)
	return payroll

# ---------------- Career getters ----------------

func get_kd() -> float:
	if stats["deaths"] <= 0:
		return float(stats["kills"])
	return float(stats["kills"]) / float(stats["deaths"])

func get_headshot_rate() -> float:
	if stats["kills"] <= 0:
		return 0.0
	return float(stats["headshots"]) / float(stats["kills"])

func get_win_rate() -> float:
	if stats["matches"] <= 0:
		return 0.0
	return float(stats["wins"]) / float(stats["matches"])

# ---------------- Wallet ----------------

func can_afford(c: int, g: int) -> bool:
	return cash >= c and gold >= g

func spend(c: int, g: int) -> bool:
	if not can_afford(c, g):
		return false
	cash -= c
	gold -= g
	save()
	wallet_changed.emit()
	return true

func add_currency(c: int, g: int) -> void:
	cash += c
	gold += g
	save()
	wallet_changed.emit()

# ---------------- Persistence ----------------

func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"cash": cash, "gold": gold, "stats": stats, "history": history}))
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data == null or not data is Dictionary:
		return
	cash = int(data.get("cash", 0))
	gold = int(data.get("gold", 0))
	var s = data.get("stats", {})
	if s is Dictionary:
		for k in stats.keys():
			stats[k] = int(s.get(k, stats[k]))
	var h = data.get("history", [])
	if h is Array:
		history = h

## Test hook — wipes everything including the save file.
func reset() -> void:
	cash = 0
	gold = 0
	for k in stats.keys():
		stats[k] = 0
	history.clear()
	_tracking = false
	_m_kills = 0
	_m_deaths = 0
	_m_headshots = 0
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
