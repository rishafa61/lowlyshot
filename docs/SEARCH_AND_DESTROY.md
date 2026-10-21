# Search & Destroy — Setup & Test Guide

5v5 round-based mode. Attackers plant the bomb at Site A or B; Defenders stop them. First team to **5 round wins** takes the match. Teams swap sides at halftime (after round 4). No respawns — dead players spectate until the next round.

## Files

| What | Where |
|---|---|
| Game mode logic (host-authoritative) | `scripts/multiplayer/search_and_destroy_manager.gd` |
| Level scene (arena + sites + spawns) | `scenes/levels/search_and_destroy.tscn` |
| Bomb site zone (A/B) | `scenes/levels/bomb_site.tscn`, `scripts/multiplayer/bomb_site.gd` |
| World bomb visual | `scenes/objects/bomb_item.tscn`, `scripts/objects/bomb_item.gd` |
| HUD extras (bomb status, sites, progress bar, banners) | `scripts/multiplayer/multiplayer_hud.gd` |
| Player plant/defuse/pickup input | `scenes/player/player.gd` (bottom: `_snd_process_interactions`) |
| Headless test (33 checks) | `tests/test_search_and_destroy.gd` |

## Setup

1. Launch the game → **Multiplayer** → **Search & Destroy** → host, or join via Steam lobby.
2. Pick a side (ATTACKERS / DEFENDERS) on the team select screen. Bots backfill empty slots.
3. Round flow per round:
   - WARMUP (~5 s): everyone spawned at team spawns, bomb assigned to a random attacker.
   - ACTIVE (120 s): plant / defuse / eliminate.
   - ROUND_END (5 s): banner shows result, then next round.
4. Controls:
   - **F** (the `interact` action): hold to plant / defuse / pick up. Release or move to cancel.
   - Plant only works **inside** Site A/B (orange ring on the floor).
   - TAB: scoreboard.

### Config values (exported on the manager node)

`round_duration=120`, `plant_duration=4`, `defuse_duration=5`, `bomb_countdown=40`, `rounds_to_win=5`, `halftime_round=4`, `plant_radius=6`, `defuse_radius=3.5`, `pickup_radius=3`.

### Win conditions

- Attackers win: bomb detonates, or all defenders dead **before plant**.
- Defenders win: defuse, all attackers dead **before plant**, or round time expires pre-plant.
- After plant: killing all attackers does NOT end the round — defenders must defuse or eat the blast.
- Halftime after 4 played rounds; match ends at 5 round wins (max 9 rounds).

## Build

```
& "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --export-release "Windows Desktop" "build\Call Of Diddy.exe"
powershell -ExecutionPolicy Bypass -File .\utils\package_build.ps1
```

Output: `build/CallOfDiddy_Steam_Multiplayer.zip`.

## Manual test plan (host + 1 client)

Run one host and at least one client from the packaged build. Each case lists setup, steps, expected result. Host console output (`[S&D] ...` lines) is the authority log.

### 1. Full round: plant + detonate
- Setup: host = attacker (carrier), client = defender.
- Steps: wait for ACTIVE → walk to Site A ring → hold F 4 s → "BOMB PLANTED AT SITE A!" appears on both screens, timer flips to red `BOMB 40s` → defend for 40 s.
- Expected: explosion sound + "BOMB DETONATED!", banner "ATTACKERS WIN — TARGET DESTROYED", attackers score 1, next round starts with everyone respawned.

### 2. Full round: defuse
- Setup: host = attacker, client = defender.
- Steps: host plants at Site B → client stands next to bomb → holds F 5 s.
- Expected: progress bar labeled "DEFUSING — YOU" fills; "BOMB DEFUSED!" + defenders win banner; score updates.

### 3. Defuse interrupted by bomb timer (edge case: bomb expires mid-defuse)
- Steps: plant, let countdown reach 1–2 s, defender starts defusing (5 s).
- Expected: bomb detonates at 0 mid-defuse, defuse progress bar hides, attackers win. No double round-end in the log (only one `Round N ended` line).

### 4. Elimination pre-plant vs post-plant
- Pre-plant: kill all attackers (use bots / suicide by falling off map). Expected: "DEFENDERS WIN — TEAM ELIMINATED" immediately.
- Post-plant: plant, then kill all attackers. Expected: round does NOT end; defenders must defuse or detonation decides.

### 5. Carrier death → drop → pickup
- Steps: bomb carrier dies → bomb spawns on the ground (blinking light) + HUD shows "C4: DROPPED" → another attacker walks over and holds F.
- Expected: only attackers can pick up; defender near bomb sees no prompt and pickup is rejected server-side. After pickup: "C4: CARRIED BY <name>".

### 6. Cancel plant/defuse
- Steps: start planting, release F halfway, restart; then start planting and walk away.
- Expected: progress bar disappears on release and on moving >2.5 m; bomb still CARRIED (HUD confirms); can restart plant.

### 7. Carrier disconnect mid-carry (edge case)
- Steps: 3 players — make client 2 the carrier (re-roll until assigned), then have client 2 Alt-F4.
- Expected: bomb drops at carrier's last position, round continues, elimination check runs. If the whole attacker team is now gone pre-plant, defenders win.

### 8. Simultaneous pickup (edge case)
- Steps: two attackers stand on the dropped bomb, both hold F on the same tick.
- Expected: exactly one becomes carrier (host processes first request, second is rejected — bomb is no longer DROPPED). Log shows a single `picked up` line. No duplicate bomb in the world.

### 9. Team dead at round start (edge case)
- Steps: empty both teams down to bots only, or set up so a team has 0 players at round start (bots backfill normally, so easiest to verify via log after a team-wipe round transitions).
- Expected: round proceeds or ends by elimination immediately; no hang between WARMUP→ACTIVE.

### 10. Delayed state updates / late join (edge case)
- Steps: client joins mid-round (round 2+).
- Expected: `client_ready` sends bomb state — client HUD immediately shows correct bomb status, scores, round number, and timer; no ghost bomb model.

### 11. Halftime swap
- Steps: play 4 rounds (fastest: 4 quick elimination rounds).
- Expected: after round 4 banner "HALFTIME — TEAMS SWAPPED", round 5 spawns everyone at the opposite side's spawns; scoreboard team column flips; scores preserved.

### 12. Match end + rematch/return to lobby
- Steps: reach 5 round wins for one team.
- Expected: VICTORY/DEFEAT/DRAW screen with final round score; Return-to-lobby / rematch buttons work and reset all S&D state (bomb, scores, round number).

### 13. Scores preserved across rounds
- Watch the header through all of the above: ATT/DEF counts only move on round wins, never reset between rounds, and match `team_scores` in the host log.

## Map testing checklist (search_and_destroy.tscn)

- [ ] Both Site A (-8, -14) and Site B (8, 14) show an orange floor ring + "SITE A/B" billboard label visible from mid-map.
- [ ] Both sites reachable on foot from BOTH spawns without jumping exploits.
- [ ] Plant prompt appears only inside the ring: walk the ring edge — prompt "HOLD [F] TO PLANT..." must toggle exactly at the ring boundary (~6 m radius).
- [ ] Plant prompt never appears outside sites (mid-map, enemy spawn, roof).
- [ ] Defuse prompt only within ~4 m of the planted bomb; server rejects beyond `defuse_radius` (3.5 m) even if the prompt was up.
- [ ] No spawn-kill sightlines: standing at attackers' spawn (x≈-27) you cannot see defenders' spawn (x≈+27); cover crates block the mid lanes.
- [ ] Spawn points (5 per team) never overlap on spawn — no players stuck inside each other on round start.
- [ ] Bomb drop position after carrier death is always on walkable ground (not on a crate roof / out of bounds).
- [ ] 10 combatants (5v5 players or bots) navigate without physics jams at the site chokepoints; round-start respawn wave does not push anyone through walls.
- [ ] Site labels readable at distance (no depth-test issues) and don't obstruct aiming (no_depth_test only on the Label3D, not gameplay geometry).

## Known simplification

- Bots fight but never plant/defuse/pick up the bomb. If a bot ends up the only attacker alive, the round plays out by elimination/time rules. Upgrade path: give capsule bots a "move to site + hold F" goal state when they carry the bomb (`ponytail:` marker in the manager).
