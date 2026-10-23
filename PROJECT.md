# Call of Diddy — Project Document

**Genre:** 5v5 tactical first-person shooter
**Engine:** Godot 4.7.2 (Jolt physics)
**Platform:** Windows PC
**Networking:** Steam P2P, host-authoritative
**Status:** Playable multiplayer build, actively developed

---

## 1. Overview

Round-based team FPS supporting 2 human players plus AI bot fill (5v5 total), with Search & Destroy as the flagship mode. Host runs the authoritative simulation; clients receive replicated state and send inputs/RPCs. Offline play with bots is supported for every system.

Core pillars:

- Host-authoritative multiplayer over Steam lobbies (no dedicated server)
- Team-aware AI bots that fill both teams in every mode
- Multi-seat vehicles (Humvee, M1 Abrams, helicopter, aircraft)
- Expanding arsenal with operators and skills (sentry turret, airstrike, sonar bow, shockwave, grappler, flashbang, grenade, adrenaline)
- Search & Destroy: CS-style rounds with plant/defuse, halftime side swap, no mid-round respawn
- Currency economy (Cash & Gold) with post-match payroll, career stats (K/D, Headshot Rate, Win Rate), and a player card dossier

---

## 2. Game Modes

### 2.1 Search & Destroy (flagship)

Spec (`docs/SEARCH_AND_DESTROY.md` has mode detail; rules implemented in `scripts/multiplayer/search_and_destroy_manager.gd`):

| Rule | Value |
|---|---|
| Team size | 5v5 (humans + bot fill) |
| Round time | 120 s |
| Plant / defuse | 4 s / 5 s |
| Bomb countdown | 40 s |
| Rounds to win | 5 (first to 5) |
| Halftime swap | After round 4 — sides swap, scores follow teams |
| Respawn | Disabled mid-round; full respawn each round |

Flow: `WARMUP → ACTIVE → ROUND_END → …` governed by a 1 s host tick. Bomb states: `CARRIED → DROPPED → PLANTING → PLANTED → DEFUSING → DEFUSED / DETONATED`.

- Win conditions: elimination, bomb detonation (attackers), defuse (defenders), time expiry (defenders).
- Attackers pick up the dropped bomb by walking over it (auto-pickup, radius 3.0); any living attacker, human or bot.
- Bomb carrier prefers a human attacker at round start.
- Halftime: every combatant (humans, bots, corpses) teleports to the opposite base; bot puppets are re-synced to clients with post-swap team/tint; the scoreboard flips with them.
- Round freeze: players and bots are input-frozen during `WARMUP` only.

### 2.2 Ground War

Team deathmatch with vehicles and continuous respawn (`scripts/levels/ground_war.gd`). Enemy puppets and bots remain visible across respawns via bot respawn replication.

---

## 3. Multiplayer Architecture

Everything below lives in `scripts/multiplayer/`.

### 3.1 Authority model

- **Host (peer 1)** owns all simulation: bots, bomb state, round timer, team scores, stats.
- Clients send `request_join_team`, `report_kill`, and input for their own player.
- State sync: `sync_players_data` (roster, scores, `match_stats`), `sync_state` (match state machine), `sync_bomb_data` (bomb).

### 3.2 Identity and stats

- `players_data`: `{ peer_id: { name, team, kills, deaths, ping } }`.
- `match_stats`: scoreboard entries keyed by name. Host's entry key is `"Player"`; each client's key is its peer id string; bots use `bot_name`.
- **Invariant (bug-fixed):** `players_data[peer]["name"]` must equal the `match_stats` key used for that peer — the halftime swap and kill attribution look up stats by name. Host names were once `str(peer)` while stats lived under `"Player"`, producing a 4v6 scoreboard after side swap; fixed by naming both `"Player"` for peer 1 plus an alias fallback in the swap loop.
- `multiplayer_hud.gd` groups `match_stats` by `"team"`; entry key `"Player"` renders as **"You"**.

### 3.3 Bots

- Host spawns/kicks bots via `host_spawn_bot` / `host_kick_bots`; `_balance_team_bots(team)` reconciles the tree against `team_size` minus human count every round start.
- Replication: host broadcasts `net_spawn_bot` / `net_despawn_bot` / `net_bot_respawned`; clients hold puppet bots (`is_net_puppet`), which sync at 10 Hz.
- Deaths: player and bot puppets set `is_dead = true` on `net_play_death` so host elimination checks and bot targeting ignore corpses.

### 3.4 Team relations

- Team modes stamp `snd_team` ("attackers"/"defenders") on players, bots, and turrets.
- `_snd_side_of(node)` reads `snd_team`, falls back to `team`, then to legacy `ally`/`enemy` groups outside team modes.
- Bots and the sentry turret target only the opposite side; turrets cannot be damaged by allies (`snd_team`-aware `is_valid_enemy` / `take_damage`).
- Halftime swap flips `snd_team`, groups, body tint, and `match_stats` teams together.

### 3.5 Scoreboard and killfeed

- Killfeed colors are **viewer-relative** (`scenes/ui/hud.gd`): your own name is yellow (`#ffeb3b`), teammates blue (`#38bdf8`), enemies red (`#ef4444`). Resolution looks up each name's team in `match_stats` from the local viewer's perspective; static faction strings are only a fallback.
- Managers register in the `multiplayer_manager` group so the HUD can locate them.

---

## 4. Player, Weapons, Vehicles

- `scenes/player/player.gd`: movement, slide, grapple, ghost controls while dead, spectator flow, planting/defusing interactions, net damage pipeline (`_net_apply_damage` → `take_damage`).
- Arsenal (scenes/weapons): AK47, M4A4, M700, MP5, Remington 870, RPD, Steyr AUG, Knife, Desert Hawk, Glock, plus launchers (AT4, tank shells) and utilities.
- Operators (scenes/operators): Assault, Breacher, Recon, Sentry, Wingman, Greppy — each with a skill (turret, airstrike, sonar, shockwave, adrenaline…).
- Vehicles (scenes/vehicles + scripts/vehicles): driver/gunner/passenger seats, replicated enter/exit, helicopter and aircraft flight with ordnance.

---

## 5. Testing

Headless SceneTree suites in `tests/` (each exits 0 on pass, 1 on fail):

| Suite | Coverage |
|---|---|
| `test_multiplayer_issues.gd` | Puppet death `is_dead`, auto-pickup, bot respawn replication, halftime swap keeps roster balanced (host `"Player"` alias) |
| `test_search_and_destroy.gd` | Full S&D rules: timers, plant/defuse, detonation, elimination, halftime, match end |
| `test_snd_team_and_turret.gd` | `snd_team` relations, turret friendly fire, swapped-side targeting |
| `test_snd_freeze_and_end.gd` | Freeze gating and end-of-match flow |
| `test_killfeed_colors.gd` | Viewer-relative killfeed colors |
| `test_scoreboard_kill_attribution.gd` | Kill/credit attribution across peers |

Run (benign Steam IPC noise at startup is expected):

```powershell
E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe --headless -s res://tests/test_search_and_destroy.gd
```

---

## 6. Build & Export

```powershell
# Export Windows release
& "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --export-release "Windows Desktop" "build\Call Of Diddy.exe"

# Package the Steam multiplayer zip
powershell -ExecutionPolicy Bypass -File .\utils\package_build.ps1
```

Outputs: `build\Call Of Diddy.exe` and `build\CallOfDiddy_Steam_Multiplayer.zip`.

---

## 7. Repository Map

```
scenes/
  player/        player.tscn/gd (controller, HUD instance, net puppet)
  enemies/       capsule_enemy / capsule_ally bots (team-aware AI)
  weapons/       arsenal, skills (auto_turret, airstrike, sonar…)
  vehicles/      humvee, m1_abrams, helicopter, aircraft
  levels/        search_and_destroy, ground_war, multiplayer_arena
  objects/       bomb_item, doors, flickering lights
  ui/            hud, multiplayer_hud, menus, lobby dialogs
scripts/
  multiplayer/   multiplayer_manager, search_and_destroy_manager,
                 player_spawner, multiplayer_hud, bomb_site, spawn_point
  vehicles/      vehicle controllers
  enemy_operators/ bot operator brains (assault, sentry, recon…)
tests/           headless regression suites (see §5)
utils/           packaging, navmesh bake, optimization scripts
docs/            SEARCH_AND_DESTROY.md, this file
```

---

## 8. Recent Fix History

| Commit | Fix |
|---|---|
| `77cee96` | Viewer-relative killfeed colors (self yellow / team blue / enemy red) |
| `8f12509` | 4v6 scoreboard imbalance after halftime swap (host name/stats key mismatch) |
| `e18937d` | Puppet death `is_dead`, bot respawn replication, halftime bot teleport, dropped-bomb auto-pickup, world bomb sync |
| `d82f0e4` | Halftime AI relations + turret friendly fire |
| `56146fc` | S&D freeze gating, ghost controls, procedural SFX, carrier-death drop, match-end lobby return, moving sky shader |

---

## 9. Known Simplifications

- Bot bomb carriers never plant — bomb rounds resolve by elimination/time when a bot holds the C4 (`ponytail` note in `_assign_bomb_carrier`).
- Kill events replicate to the victim's peer and the host; third-party peers may not see every killfeed entry for kills they are uninvolved in.
- `PRD.md` reflects the original single-player prototype scope and is superseded by this document.
