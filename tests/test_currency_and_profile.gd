extends SceneTree
## Test suite for currency system, post-match payroll, and player profile card.

var fails: int = 0
func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		printerr("FAIL: " + label)
		fails += 1

func _initialize() -> void:
	var prof = root.get_node("PlayerProfile")
	prof.reset()

	# 1. Baseline wallet
	check(prof.cash == 0 and prof.gold == 0, "Wallet starts empty after reset")
	prof.add_currency(500, 50)
	check(prof.cash == 500 and prof.gold == 50, "add_currency updates wallet")
	check(prof.can_afford(300, 20), "can_afford true when balance sufficient")
	check(not prof.can_afford(600, 20), "can_afford false when cash deficient")
	check(not prof.can_afford(300, 60), "can_afford false when gold deficient")
	check(prof.spend(200, 10), "spend succeeds on valid funds")
	check(prof.cash == 300 and prof.gold == 40, "spend deducts exact amounts")
	check(not prof.spend(999, 0), "spend rejected on insufficient funds")
	check(prof.cash == 300, "balance unchanged on rejected spend")

	# 2. Persistence save & reload
	prof.save()
	prof.cash = 0
	prof.gold = 0
	prof._load()
	check(prof.cash == 300 and prof.gold == 40, "Wallet persists across save/load")

	# 3. Match tracking + payroll: WIN with kills and headshots
	prof.reset()
	await process_frame # let autoload _ready connections settle
	prof.start_match_tracking("Search & Destroy")
	check(prof.is_tracking(), "Profile is tracking match")

	# Simulate 3 kills, 1 headshot
	var gd = root.get_node("GlobalData")
	gd.register_kill("Player", "Ally", "ak47", "Bot1", "Enemy", false)
	gd.register_kill("Player", "Ally", "m700", "Bot2", "Enemy", true)
	gd.register_kill("Player", "Ally", "ak47", "Bot3", "Enemy", false)
	# Simulate 1 death
	gd.register_kill("EnemyBot", "Enemy", "m4a4", "Player", "Ally", false)

	# Finish match as WIN
	# Expected payout: Play(250) + Win(750) + Kills(3*50=150) + Headshot(1*25=25) = 1175 Cash, 25 Gold
	var payroll = prof.finish_match("win")
	check(payroll.cash == 1175, "Win payroll cash is 1175 (got %d)" % payroll.cash)
	check(payroll.gold == 25, "Win payroll gold is 25 (got %d)" % payroll.gold)
	check(prof.cash == 1175 and prof.gold == 25, "Profile wallet reflects win payroll")
	check(prof.stats["matches"] == 1, "Matches count is 1")
	check(prof.stats["wins"] == 1, "Wins count is 1")
	check(prof.stats["kills"] == 3, "Kills count is 3")
	check(prof.stats["deaths"] == 1, "Deaths count is 1")
	check(prof.stats["headshots"] == 1, "Headshots count is 1")
	check(abs(prof.get_kd() - 3.0) < 0.01, "KD ratio is 3.0 (got %.2f)" % prof.get_kd())
	check(abs(prof.get_headshot_rate() - (1.0 / 3.0)) < 0.01, "Headshot rate is 33.3%%")
	check(abs(prof.get_win_rate() - 1.0) < 0.01, "Win rate is 100%%")
	check(prof.history.size() == 1, "Match history has 1 entry")
	check(prof.history[0]["mode"] == "Search & Destroy", "History entry records mode")
	check(prof.history[0]["result"] == "win", "History entry records win")

	# 4. Match tracking: LOSS
	prof.start_match_tracking("Ground War")
	gd.register_kill("EnemyBot", "Enemy", "glock", "Player", "Ally", false)
	# Expected loss payout: Play(250) + 0 kills = 250 Cash, 0 Gold
	var pay_loss = prof.finish_match("loss")
	check(pay_loss.cash == 250 and pay_loss.gold == 0, "Loss payout pays play bonus only")
	check(prof.stats["matches"] == 2 and prof.stats["losses"] == 1, "Stats record 2 matches, 1 loss")
	check(abs(prof.get_win_rate() - 0.5) < 0.01, "Win rate now 50%%")
	check(prof.history.size() == 2, "History has 2 entries")

	# 5. Player card dialog instantiates and populates
	var card_script = load("res://scenes/ui/player_card_dialog.gd")
	var card: CanvasLayer = CanvasLayer.new()
	card.set_script(card_script)
	root.add_child(card)
	await process_frame
	check(card.get_child_count() > 0, "Player card dialog creates UI elements")
	card.queue_free()

	# 6. Main menu loads with profile frame and wallet pills
	var menu_scene = load("res://scenes/ui/main_menu.tscn")
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	await process_frame
	var frame = menu.get_node_or_null("ProfileFrame")
	check(frame != null, "Main menu has ProfileFrame button")
	var coin_lbl = menu.get_node_or_null("RightPanel/VBoxContainer/CurrencyHBox/CoinPanel/Label")
	var gem_lbl = menu.get_node_or_null("RightPanel/VBoxContainer/CurrencyHBox/GemPanel/Label")
	check(coin_lbl != null and coin_lbl.text.contains("CASH:"), "Cash pill displays balance")
	check(gem_lbl != null and gem_lbl.text.contains("GOLD:"), "Gold pill displays balance")
	menu.queue_free()
	await process_frame

	prof.reset() # clean up test state
	print("--- currency and profile tests done: %d fails ---" % fails)
	quit(1 if fails > 0 else 0)
