# Godot FPS Game — Product Requirements Document

**Project Type:** First-Person Shooter  
**Engine:** Godot 4.x  
**Platform:** PC  
**Game Mode:** Single-player  
**Target:** Beginner-friendly FPS prototype  
**Development Approach:** Phase-by-phase  
**Core Goal:** Create a simple but complete playable FPS from zero.

---

# 1. Game Overview

## 1.1 Concept

A simple single-player FPS where the player explores a small arena, fights enemies using a firearm, survives enemy attacks, and reaches the objective.

The project is intentionally designed with a limited scope so the core gameplay can be completed before adding advanced systems.

## 1.2 Core Gameplay Loop

```text
Start Game
    ↓
Spawn Player
    ↓
Explore Arena
    ↓
Find / Encounter Enemies
    ↓
Aim & Shoot
    ↓
Defeat Enemies
    ↓
Reach Objective
    ↓
Win
```

If the player loses all health:

```text
Player Dies
    ↓
Game Over
    ↓
Restart
```

---

# 2. MVP Feature List

The first playable version only needs:

- First-person player controller
- Mouse camera control
- WASD movement
- Jump
- Sprint
- Crouch
- One weapon
- Shooting
- Reloading
- Crosshair
- Player health
- Enemy AI
- Enemy health
- Enemy attacks
- Simple arena
- Ammo system
- Pickups
- Win condition
- Game over
- Main menu
- Pause menu

Everything else is optional.

---

# 3. Technical Architecture

Recommended basic structure:

```text
FPSGame/
│
├── scenes/
│   ├── player/
│   │   ├── player.tscn
│   │   └── player.gd
│   │
│   ├── weapons/
│   │   ├── pistol.tscn
│   │   └── pistol.gd
│   │
│   ├── enemies/
│   │   ├── enemy.tscn
│   │   └── enemy.gd
│   │
│   ├── levels/
│   │   └── test_arena.tscn
│   │
│   └── ui/
│       ├── hud.tscn
│       ├── main_menu.tscn
│       └── pause_menu.tscn
│
├── scripts/
│   ├── game_manager.gd
│   ├── damageable.gd
│   └── interactable.gd
│
├── assets/
│   ├── models/
│   ├── textures/
│   ├── sounds/
│   └── animations/
│
└── project.godot
```

Keep the architecture simple at first.

Do not create a giant framework before the game exists.

---

# 4. PHASE 0 — Project Setup

## Objective

Create a clean Godot project and prepare the basic development environment.

## Tasks

### Project

- Create Godot 4 project
- Set project name
- Set resolution
- Configure input actions
- Create project folders
- Create main scene

### Input

Create:

```text
move_forward
move_backward
move_left
move_right

jump
sprint
crouch

fire
reload

pause
```

Recommended keyboard:

| Action | Input |
|---|---|
| Forward | W |
| Backward | S |
| Left | A |
| Right | D |
| Jump | Space |
| Sprint | Shift |
| Crouch | Ctrl |
| Fire | Left Mouse |
| Reload | R |
| Pause | Esc |

## Completion Criteria

The project opens successfully and all inputs are recognized.

---

# 5. PHASE 1 — First-Person Controller

## Objective

Make the player walk around a 3D environment.

## Player Components

Use:

```text
CharacterBody3D
│
├── CollisionShape3D
├── Head
│   └── Camera3D
│
└── WeaponHolder
```

## Features

### Movement

- WASD movement
- Gravity
- Jump
- Floor detection
- Smooth movement

### Camera

- Mouse look
- Horizontal rotation
- Vertical rotation
- Vertical camera clamp

Example:

```text
Mouse X → Player rotates
Mouse Y → Camera rotates
```

### Sprint

Holding Shift:

```text
Normal Speed = 5
Sprint Speed = 8
```

Numbers can be adjusted later.

### Crouch

Holding Ctrl:

```text
Standing Height
        ↓
Crouching Height
```

For the first version, crouching does not need advanced animation.

## Completion Criteria

The player can:

- Walk
- Look around
- Jump
- Sprint
- Crouch
- Collide with the environment

---

# 6. PHASE 2 — Test Arena

## Objective

Create a simple playable environment.

Do NOT spend time making beautiful graphics yet.

## Environment

Create:

```text
Floor
Walls
Boxes
Platforms
Cover
Enemy Spawn Points
Player Spawn
Goal Area
```

Example:

```text
+--------------------------------+
|                                |
|     BOX             BOX        |
|                                |
|          ENEMY                 |
|                                |
|   BOX                    BOX   |
|                                |
|          PLAYER                |
|                                |
|              EXIT              |
+--------------------------------+
```

## Requirements

- Player cannot fall outside map
- Walls have collision
- Objects have collision
- Arena has enough cover for combat

## Completion Criteria

The player can freely explore the entire arena.

---

# 7. PHASE 3 — Weapon System

## Objective

Give the player a functional firearm.

Start with ONE weapon.

Recommended:

**Pistol**

## Weapon Features

- Fire
- Fire rate
- Damage
- Magazine size
- Ammo
- Reload
- Recoil
- Muzzle flash
- Shooting sound

Example configuration:

```text
Damage: 25
Magazine: 12
Reserve Ammo: 48
Fire Rate: 0.2 seconds
Reload: 1.5 seconds
```

## Shooting

Use a raycast from the camera.

```text
Camera
   │
   │ Raycast
   ↓
Enemy
```

If the ray hits an enemy:

```text
Enemy.take_damage(25)
```

## Completion Criteria

The player can:

- Equip pistol
- Aim
- Shoot
- Damage enemies
- Reload

---

# 8. PHASE 4 — Combat UI

## Objective

Make combat information visible.

## HUD

Display:

```text
+-------------------------------+
|                               |
|             +                 |
|                               |
|                               |
| HP: 100                       |
|                               |
|                    12 / 48    |
+-------------------------------+
```

## UI Components

### Crosshair

Simple:

```text
+
```

### Health

```text
HP: 100
```

### Ammo

```text
12 / 48
```

### Hit Marker

When shooting an enemy:

```text
X
```

appears briefly.

## Completion Criteria

The player always knows:

- Health
- Magazine ammo
- Reserve ammo
- Crosshair position

---

# 9. PHASE 5 — Enemy

## Objective

Create a basic enemy.

Start with extremely simple AI.

## Enemy Structure

```text
CharacterBody3D
│
├── CollisionShape3D
├── Mesh
├── NavigationAgent3D
├── AttackPoint
└── DetectionArea
```

## Enemy States

Only use four states:

```text
IDLE
  ↓
CHASE
  ↓
ATTACK
  ↓
DEAD
```

## Behavior

### Idle

Enemy waits.

### Detection

If player enters detection range:

```text
Player detected
      ↓
CHASE
```

### Chase

Enemy moves toward player.

### Attack

When close enough:

```text
Enemy attacks
    ↓
Player takes damage
```

### Death

When health reaches zero:

```text
Enemy
 ↓
Death
 ↓
Remove enemy
```

## Completion Criteria

Enemy can:

- Detect player
- Chase player
- Attack player
- Receive damage
- Die

---

# 10. PHASE 6 — Player Health & Death

## Objective

Implement the player damage system.

## Health

Example:

```text
Max HP = 100
Current HP = 100
```

Enemy attack:

```text
Damage = 10
```

Player:

```text
100
 ↓
90
 ↓
80
 ↓
...
 ↓
0
```

## Death

When HP reaches 0:

```text
Player Death
     ↓
Disable Movement
     ↓
Death UI
     ↓
Game Over
```

## Game Over UI

```text
+---------------------------+
|        GAME OVER          |
|                           |
|      YOU DIED             |
|                           |
|      [RESTART]            |
|      [MAIN MENU]          |
+---------------------------+
```

---

# 11. PHASE 7 — Objective System

## Objective

Give the player an actual reason to fight.

Simple objective:

> Eliminate all enemies and reach the exit.

## Objective Flow

```text
Start
 ↓
Enemies Spawn
 ↓
Player fights
 ↓
Enemy Count = 0
 ↓
Exit Opens
 ↓
Player reaches Exit
 ↓
MISSION COMPLETE
```

## UI

Before enemies are defeated:

```text
Enemies Remaining: 5
```

After all enemies die:

```text
EXIT UNLOCKED
```

---

# 12. PHASE 8 — Pickups

## Objective

Add basic interaction with the environment.

## Pickup Types

Start with only two:

### Ammo

```text
+12 Ammo
```

### Health

```text
+25 HP
```

## Example

Player walks over pickup:

```text
Pickup
 ↓
Player enters Area3D
 ↓
Give item
 ↓
Delete pickup
```

## Completion Criteria

Pickups work correctly and cannot be collected twice.

---

# 13. PHASE 9 — Main Menu

## Objective

Create a basic game flow.

## Main Menu

```text
============================

        PROJECT FPS

      [ PLAY ]

      [ OPTIONS ]

      [ QUIT ]

============================
```

## Play

Loads:

```text
test_arena.tscn
```

## Options

Basic settings:

- Mouse sensitivity
- Master volume
- Fullscreen

## Quit

Closes the application.

---

# 14. PHASE 10 — Pause Menu

Press:

```text
ESC
```

Display:

```text
============================

          PAUSED

       [ RESUME ]

       [ OPTIONS ]

       [ QUIT ]

============================
```

When paused:

- Player cannot move
- Enemy AI stops
- Game simulation pauses

---

# 15. PHASE 11 — Audio

## Objective

Add basic sound feedback.

## Required Sounds

### Weapon

- Shoot
- Reload
- Empty magazine

### Player

- Jump
- Footsteps
- Damage
- Death

### Enemy

- Detection
- Attack
- Damage
- Death

### Environment

- Ambient sound
- Background music

Do not spend hours searching for perfect audio.

Placeholder sounds are completely acceptable during development.

---

# 16. PHASE 12 — Animation & Polish

Only start this phase after the game is already playable.

## Player

Add:

- Weapon idle animation
- Shooting animation
- Reload animation
- Weapon sway
- Head bob

## Enemy

Add:

- Idle
- Walk
- Attack
- Hit
- Death

## Effects

Add:

- Muzzle flash
- Bullet impact
- Blood / hit effect
- Shell casing
- Screen damage effect

---

# 17. PHASE 13 — Game Balance

## Objective

Make the game actually fun.

Test:

### Weapon

- Damage
- Fire rate
- Magazine size
- Reload time

### Enemy

- Health
- Speed
- Attack damage
- Detection range
- Attack cooldown

### Level

- Enemy placement
- Cover
- Ammo placement
- Health placement

Example:

```text
Player HP:       100
Pistol Damage:    25
Enemy HP:         100
Enemy Damage:      10
Enemies:            5
```

The player should be able to win without requiring perfect aim.

---

# 18. PHASE 14 — Final MVP

At this point the game should contain:

```text
MAIN MENU
    ↓
GAME
    ↓
PLAYER
    ↓
WEAPON
    ↓
ENEMIES
    ↓
COMBAT
    ↓
OBJECTIVE
    ↓
WIN / LOSE
    ↓
RESTART
```

## MVP Feature Checklist

- [ ] Main menu
- [ ] FPS movement
- [ ] Camera
- [ ] Jump
- [ ] Sprint
- [ ] Crouch
- [ ] Pistol
- [ ] Shooting
- [ ] Reloading
- [ ] Ammo
- [ ] Health
- [ ] Enemy AI
- [ ] Enemy attacks
- [ ] Enemy death
- [ ] Crosshair
- [ ] HUD
- [ ] Pickups
- [ ] Objective
- [ ] Win screen
- [ ] Game over
- [ ] Pause menu
- [ ] Basic audio

---

# 19. Recommended Development Order

Do NOT develop systems randomly.

Follow this exact order:

```text
PHASE 0
Project Setup
       ↓
PHASE 1
Player Controller
       ↓
PHASE 2
Test Arena
       ↓
PHASE 3
Weapon
       ↓
PHASE 4
Combat UI
       ↓
PHASE 5
Enemy AI
       ↓
PHASE 6
Health & Death
       ↓
PHASE 7
Objective
       ↓
PHASE 8
Pickups
       ↓
PHASE 9
Main Menu
       ↓
PHASE 10
Pause
       ↓
PHASE 11
Audio
       ↓
PHASE 12
Animation
       ↓
PHASE 13
Balance
       ↓
PHASE 14
FINAL MVP
```

---

# 20. Future Expansion — AFTER MVP

Only after the MVP is finished should you consider:

## Weapons

- Shotgun
- SMG
- Assault rifle
- Sniper
- Knife

## Enemies

- Fast enemy
- Tank enemy
- Ranged enemy
- Boss

## Gameplay

- Multiple maps
- Waves
- Objectives
- Doors
- Keys
- Interactive objects

## Progression

- XP
- Levels
- Currency
- Weapon upgrades

## Multiplayer

Potentially:

```text
Lobby
 ↓
Matchmaking
 ↓
Server
 ↓
Players
 ↓
FPS Combat
```

**Do not add multiplayer during the first MVP.**

---

# 21. Definition of Done

The project is considered complete when a player can:

1. Launch the game.
2. Enter the main menu.
3. Start the game.
4. Control the FPS character.
5. Explore the arena.
6. Find enemies.
7. Shoot enemies.
8. Reload.
9. Take damage.
10. Collect health/ammo.
11. Kill all enemies.
12. Reach the exit.
13. Receive a victory screen.
14. Restart the game.
15. Lose and receive a Game Over screen.

If all of these work reliably, **you have successfully built an FPS game prototype in Godot.**

---

# 22. Golden Rule

The project should follow this development philosophy:

> **Make it work → Make it playable → Make it fun → Make it pretty.**

Do not start with:

- complicated weapon systems
- multiplayer
- inventory
- procedural generation
- advanced AI
- realistic graphics
- massive maps
- skill trees
- matchmaking
- skins
- monetization

Build the tiny FPS first.

Once the tiny FPS is finished, expanding it becomes much easier.