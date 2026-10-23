# Changelog

All notable changes to Call of Diddy are documented here.
Format: version — date — Added / Changed / Fixed. Newest first.

---

## v0.04 — 2026-10-23

Windowed-mode toggle replaces fullscreen toggle; default is now windowed (1280x720 centered).

### Fixed
- Fixed GDScript `INTEGER_DIVISION` warning in `global_settings.gd` center position calculation.
- Windowed mode now actually resizes to a 1280x720 decorated window centered on screen (`window_set_size`, `window_set_position`, `WINDOW_FLAG_BORDERLESS = false`) instead of retaining screen dimensions.
- Default mode set to windowed (`window/size/mode=0` with `1280x720` override in `project.godot`).
- Settings immediately persist on toggle.

### Changed
- Settings → Visual: **Fullscreen** toggle replaced by **Windowed** toggle (ON = windowed, OFF = fullscreen).
- `GlobalSettings`: `windowed` property defaults to `true`. Legacy config files migrate automatically; `set_fullscreen()` retained as wrapper.

### Test Status
- `test_settings_styling.gd` 15/15 PASS
- All regression suites PASS (currency/profile 40, multiplayer 13, S&D 33, team/turret 9, killfeed 6)

---

## v0.03 — 2026-10-23

Profile panel restyled as a tactical military dossier (player card + main menu frame).

### Changed
- **Player card** (`scenes/ui/player_card_dialog.gd`) — full tactical dossier redesign:
  - Rank/level system: XP = kills×100 + headshots×50 + wins×500 + matches×100, 1000 XP per level, rank titles RECRUIT → VETERAN.
  - Insignia badge with level, operator title tag, and XP progress bar in the header.
  - Styled vault pills for COMBAT CASH / WAR GOLD with thousands separators.
  - 4 metric cards (KILL/DEATH, HEADSHOT RATIO, WIN RATE, DEPLOYMENTS) with accent pips and mini meter bars.
  - COMBAT LOG with mode filter tabs (ALL / SEARCH & DESTROY / GROUND WAR / DEATHMATCH), empty-state panel.
  - History rows: VICTORY/DRAW/DEFEAT badges, K/D/HS mini columns, payroll pills, MM-DD HH:MM timestamps.
- **Main menu profile frame** (`_init_profile_frame`): restyled to match — military ID badge with ◆ insignia plate showing the live level, cyan `DOSSIER // VIEW STATS` tag, orange hover border.

### Test Status
- `test_currency_and_profile.gd` 40/40 PASS (new checks: level calculator, filter tabs)
- All regression suites PASS (multiplayer 13, S&D 33, team/turret 9, killfeed 6)

---

## v0.02 — 2026-10-23

Currency economy, post-match payroll, and the profile / player card system.

### Added
- **Currency system** (`scripts/economy/player_profile.gd`, autoload `PlayerProfile`): Cash + Gold wallet persisted to `user://player_profile.json`. Spend/earn API (`spend`, `add_currency`, `can_afford`) ready for the future weapon shop and operator unlocks.
- **Post-match payroll** (multiplayer matches): every networked match awards Cash/Gold — played 250, win 750 Cash + 25 Gold, draw 375 + 10, 50 Cash per kill, 25 Cash per headshot. Itemized payroll panel appears on the match-end screen on every peer.
- **Career stats tracking**: per-match kills/deaths/headshots accumulate into career totals; matches, wins, losses, draws, assists field reserved.
- **Headshot detection** on bot kills: hit part (head/torso/lower) tracked through `receive_damage`, final-blow headshots flag `register_kill` so headshot rate = headshot kills / kills.
- **Profile frame** in the main menu top-left corner: rectangle plate with player badge + name; click opens the **player card** modal (`scenes/ui/player_card_dialog.gd`) with wallet pills, K/D, headshot rate, win rate, match count, and the last 50 match results (mode, W/L/D color-coded, K/D/HS, payout, timestamp).
- **Main menu wallet pills**: the existing CASH/GOLD plates in the right panel now display live balances and update on `wallet_changed`.
- `tests/test_currency_and_profile.gd` — 34-check suite (wallet math, persistence, payroll for win/loss, stats, KD/HSR/win-rate, UI instantiation).

### Changed
- `GlobalData.register_kill` gained an optional `was_headshot` flag stored on `_last_kill_headshot` for the profile listener.
- `LeftNav` margin top 40 → 100 so the profile frame has clearance above the menu title.

### Test Status
- `test_currency_and_profile.gd` 34/34 PASS
- `test_multiplayer_issues.gd` 13/13 PASS
- `test_search_and_destroy.gd` 33 checks PASS
- `test_snd_team_and_turret.gd` 9/9 PASS
- `test_killfeed_colors.gd` 6/6 PASS

---

## v0.01 — 2026-10-23

Baseline playable build plus this cycle's multiplayer fixes and polish.

### Added
- `PROJECT.md` — current-state project document (modes, architecture, testing, build).
- Viewer-relative killfeed colors (`scenes/ui/hud.gd`): own name yellow, teammates blue, enemies red — each peer colors the same kill from its own perspective; faction strings remain as fallback.
- `tests/test_killfeed_colors.gd` — 6-check regression suite for killfeed coloring.
- Halftime swap regression checks in `tests/test_multiplayer_issues.gd` (host `"Player"` alias flip, correct roster split).
- Managers register in the `multiplayer_manager` group so the HUD can locate them.

### Changed
- Export refreshed: `build\Call Of Diddy.exe` + `build\CallOfDiddy_Steam_Multiplayer.zip`.

### Fixed
- 4v6 scoreboard imbalance after S&D halftime side swap (`8f12509`): host `players_data` name (`"1"`) mismatched its `match_stats` key (`"Player"`), so the host's scoreboard entry never flipped teams. Host entries are now named `"Player"` at creation, with a legacy alias fallback in `swap_halftime_teams()`.
- Own killfeed entries always showed blue (`77cee96`): team modes never sent the `"Player"` faction, so colors were keyed by static faction strings instead of viewer relationship.
- Earlier in cycle (`e18937d`, `d82f0e4`): puppet deaths mark `is_dead` so round elimination counts clients; bot respawn replication; halftime bot teleport + client puppet re-team; dropped-bomb auto-pickup on walk-over; world bomb visual sync; halftime AI relations; turret friendly fire.

### Test Status
- `test_multiplayer_issues.gd` 13/13 PASS
- `test_search_and_destroy.gd` 33 checks PASS
- `test_snd_team_and_turret.gd` 9/9 PASS
- `test_killfeed_colors.gd` 6/6 PASS
