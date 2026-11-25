# Lowlyshot

A fast-paced, high-performance low-poly combined arms first-person shooter built in Godot 4.

Lowlyshot delivers large-scale vehicle and infantry battles designed to run at high frame rates even on modest PC hardware. Jump into tactical 5v5 bomb defusal rounds, all-out vehicle warfare, or low-gravity sniper duels, playable completely offline against bots or online in multiplayer with friends.

---

## Features

### Vehicles & Combined Arms
Multi-seat vehicles with driver, independent gunner, and passenger stations:
- **M1 Abrams Battle Tank**: Main 120mm cannon, independent turret traverse, and commander cupola machine gun.
- **Attack & Transport Helicopters**: Flight physics, gunner target-tracking optics, and passenger side benches.
- **Fighter Jets**: High-speed aerial combat and strafing runs.
- **Armed Humvees**: Fast ground transport with mounted firepower.

### Game Modes
- **Ground War**: Large-scale combined arms warfare with land vehicles, air support, and continuous respawns.
- **Search & Destroy**: 5v5 high-stakes tactical rounds with bomb plant and defusal, halftime side swap, and no mid-round respawns.
- **Flying Scoutsman**: Low-gravity sniper arena combat featuring the bolt-action M700.
- **Free-For-All**: Fast-paced solo deathmatch.

### Full AI Bot Support & Offline Play
Every game mode includes full AI bot fill. Play solo offline without an internet connection, or fill empty player slots in multiplayer lobbies.

### Weapons & Gadgets
- **Arsenal**: AK-47, M4A4, Steyr AUG, MP5 SMG, RPD LMG, Remington 870 Shotgun, M700 Sniper, AT4 Rocket Launcher, and Combat Knife.
- **Tactical Gadgets**: Grappling hook, deployable sentry turret, sonar scouting bow, airstrikes, smoke/frag grenades, flashbangs, and adrenaline shots.
- **Fluid Movement**: Sprinting, sliding, ledge mantling, and smooth stair climbing.

### Multiplayer Architecture
- **Steam P2P Networking**: Host-authoritative multiplayer using GodotSteam and Steam P2P lobbies (Spacewar AppID 480).
- **No Dedicated Server Required**: Any player can host a lobby; clients connect seamlessly with automatic bot fill and state replication.

---

## Getting Started

### Prerequisites
- **Engine**: [Godot Engine 4.7+](https://godotengine.org) (Compatibility / GL renderer)
- **GDExtension**: GodotSteam (included in `addons/godotsteam`)
- **Steam Client**: Steam desktop application running in the background for multiplayer features (offline play does not require Steam).

### Running from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/rishafa61/lowlyshot.git
   ```
2. Open the Godot Project Manager, click **Import**, and select `project.godot`.
3. Press **F5** to run the project.

### Building / Exporting
The project includes automated packaging scripts in `utils/`:
- Export using the **Windows Desktop** preset in Godot.
- Run `utils/package_build.ps1` to generate a release zip bundle ready for distribution.

---

## Controls

| Action | Key / Input |
|---|---|
| Movement | W / A / S / D |
| Jump / Handbrake | Space |
| Sprint | Left Shift |
| Crouch / Slide | C / Left Ctrl |
| Interact / Enter Vehicle | F |
| Switch Vehicle Seats | Ctrl + 1 / Ctrl + 2 |
| Fire / Main Cannon | Left Mouse Button |
| Aim Down Sights / Alt Fire | Right Mouse Button |
| Reload | R |
| Grapple / Ability | E / Q |
| Scoreboard | Tab |

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
