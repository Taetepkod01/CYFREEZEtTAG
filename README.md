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

## Firebase setup

The `FirebaseService` autoload provides Firebase Authentication email/password
sign-up and sign-in, plus Firestore player-profile read/write methods. It uses
Firebase's HTTPS REST APIs and does not require a Godot Firebase plugin.

1. In Firebase Console, create a project and enable **Authentication >
   Sign-in method > Email/Password**.
2. Create a **Cloud Firestore** database.
3. In Godot, open **Project > Project Settings > Firebase** and set `api_key`
   to the project's Web API key and `project_id` to the Firebase project ID.
   These values are project identifiers, not service-account credentials.
4. Apply rules that restrict each profile to its owner:

   ```text
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /playerProfiles/{userId} {
         allow read, write: if request.auth != null
                            && request.auth.uid == userId;
       }
     }
   }
   ```

Call `await FirebaseService.sign_up_with_email(email, password)` or
`await FirebaseService.sign_in_with_email(email, password)`. On success,
`FirebaseService.current_user` contains the authenticated UID and email;
`auth_state_changed` and `auth_error` report state and failures. Use
`await FirebaseService.save_player_profile(profile)` and
`await FirebaseService.load_player_profile()` for the authenticated user's
`playerProfiles/{uid}` Firestore document. Authentication tokens are currently
kept in memory for the running game only; users must sign in again after
restarting it.
