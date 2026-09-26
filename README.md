# CPFreezeTag-3D ❄️🏃‍♂️

A 3D Third-Person Freeze Tag multiplayer & AI practice game built with **Godot Engine 4 (Compatibility / WebGL 2 ready)**.

---

## 🎮 Key Features

- **3D Third-Person Orbit Camera**: SpringArm3D with raycast collision avoidance, smooth mouse-look, and camera-relative WASD movement.
- **Freeze & Rescue Gameplay**:
  - 🔴 **Taggers**: Hunt and freeze runners into translucent 3D ice blocks.
  - 🟢 **Runners**: Flee from taggers and rush in to rescue frozen teammates.
  - 🟡 **Dynamic `RESCUING` State**: Visual indicators when in range of thawing frozen teammates.
- **Single Held-Item Slot System**:
  - Collect interactive 3D items on the ground and press `[E]` to use.
  - ⚡ **Speed Boost**: 1.3x speed boost for 6s.
  - 🛡️ **Shield**: Blocks 1 tag / freeze attempt.
  - 🔥 **Heater**: Immediately melts yourself or nearby frozen players.
  - 🍌 **Banana Trap**: Drops a banana peel that causes opponents to slip and freeze for 2.5s.
  - 🌀 **Black Hole Vortex**: Creates a gravitational field pulling nearby players.
- **Real-Time 2D Minimap Radar**:
  - WebGL-safe custom-drawn circular radar tracking taggers, runners, frozen teammates, and player orientation.
- **Among Us-Style Room Lobby**:
  - 6-character random room PIN (e.g. `A7X9K2`) for private joining.
  - Host customization (4–8 players, round count, map selection).
  - Clean empty-state browser list.
- **AI Practice Mode with Role Selector**:
  - Modal and in-game live switcher to select roles:
    - 🎲 **RANDOM**: Fair 4-player randomization re-rolled each round.
    - 🔴 **TAGGER**: Hunt 3 bots.
    - 🟢 **RUNNER**: Flee from a bot tagger while cooperating with 2 bot runners.
- **Match MVP Summary**:
  - Best-of-3 round tracking with MVP calculation based on tags and rescues.

---

## 🕹️ Controls

| Action | Key / Input |
| :--- | :--- |
| **Move** | `W`, `A`, `S`, `D` |
| **Look / Aim** | `Mouse Motion` |
| **Jump** | `Spacebar` |
| **Use Item** | `E` or Click HUD Item Button |
| **Toggle Mouse Capture** | `Esc` |
| **Switch AI Practice Role** | Click Top HUD `ROLE` Button |

---

## 🛠️ Technology Stack

- **Game Engine**: Godot 4.7
- **Renderer**: `gl_compatibility` (WebGL 2 / Web export safe)
- **Language**: GDScript 2.0
