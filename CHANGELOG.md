# Changelog

All notable changes to Call of Diddy are documented here.
Format: version — date — Added / Changed / Fixed. Newest first.

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
